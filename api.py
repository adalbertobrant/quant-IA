"""
QUANT·IA — API Bridge (FastAPI)
Ponte entre o Dashboard React e o Robô Python / MetaTrader 5.

Endpoints:
  GET  /status            → estado atual do robô e sessão
  POST /start             → inicia o robô em background thread
  POST /stop              → para o robô com segurança
  GET  /operations        → lista operações abertas no MT5
  POST /order             → envia ordem manual
  DELETE /order/{ticket}  → cancela ordem por ticket MT5
  POST /upload-csv        → faz upload do screener CSV
  GET  /risk              → retorna configuração de risco atual
  POST /risk              → atualiza configuração de risco
  POST /broker            → troca corretora (BTG/TORO)
  WS   /ws/logs           → stream de logs em tempo real
"""

import asyncio
import json
import logging
import os
import threading
import time
from collections import deque
from datetime import datetime
from pathlib import Path
from typing import Optional

import MetaTrader5 as mt5
import pandas as pd
from dotenv import load_dotenv, set_key
from fastapi import FastAPI, File, HTTPException, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# ── Importa o robô como módulo ────────────────────────────────────────────────
from robo_ia_quantitativo import (
    RiskConfig,
    SessionState,
    conectar_mt5,
    enviar_ordem,
    gerar_ordens_ia,
    validar_horario,
    validar_ordem,
    obter_saldo,
    coletar_dados,
)
import robo_ia_quantitativo as robo
from utils.utils import normalize_csv, print_report

load_dotenv()

# ── App ───────────────────────────────────────────────────────────────────────
app = FastAPI(title="QUANT·IA API", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],          # Em produção, restrinja para localhost:3000
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ── Estado global da API ──────────────────────────────────────────────────────
class AppState:
    bot_running: bool      = False
    bot_thread: Optional[threading.Thread] = None
    stop_event: threading.Event = threading.Event()
    log_buffer: deque      = deque(maxlen=500)
    ws_clients: list       = []
    csv_path: str          = "screener_resultados.csv"
    broker: str            = os.getenv("BROKER_NAME", "BTG")
    session_start: Optional[str] = None

state = AppState()

# ── Logger customizado que alimenta o WebSocket ───────────────────────────────
class WSLogHandler(logging.Handler):
    def emit(self, record):
        level_map = {
            logging.INFO:    "INFO",
            logging.WARNING: "WARN",
            logging.ERROR:   "ERROR",
            logging.DEBUG:   "DEBUG",
        }
        entry = {
            "time": datetime.now().strftime("%H:%M:%S"),
            "type": level_map.get(record.levelno, "INFO"),
            "msg":  self.format(record),
        }
        state.log_buffer.append(entry)
        # Broadcast assíncrono para todos os clientes WebSocket conectados
        asyncio.run_coroutine_threadsafe(_broadcast_log(entry), _loop)

async def _broadcast_log(entry: dict):
    disconnected = []
    for ws in state.ws_clients:
        try:
            await ws.send_json(entry)
        except Exception:
            disconnected.append(ws)
    for ws in disconnected:
        state.ws_clients.remove(ws)

# Instala o handler no logger do robô
_loop = asyncio.get_event_loop()
ws_handler = WSLogHandler()
ws_handler.setFormatter(logging.Formatter("%(message)s"))
logging.getLogger().addHandler(ws_handler)
log = logging.getLogger(__name__)

# ── Pydantic models ───────────────────────────────────────────────────────────
class OrderRequest(BaseModel):
    TICKER:   str
    DIRECAO:  str        # COMPRA | VENDA
    ENTRADA:  float
    ALVO:     float
    STOP:     float
    LOTE:     float

class RiskUpdate(BaseModel):
    maxLossDiaria:   Optional[float] = None
    maxOrdens:       Optional[int]   = None
    maxLote:         Optional[float] = None
    minRR:           Optional[float] = None
    maxRiscoPct:     Optional[float] = None
    dryRun:          Optional[bool]  = None

class BrokerUpdate(BaseModel):
    broker: str   # BTG | TORO

# ── Bot runner (roda em thread separada) ──────────────────────────────────────
def _bot_worker():
    """Loop principal do robô — controlado pelo stop_event."""
    log.info(f"═══ Robô iniciado | Corretora: {state.broker} | "
             f"DRY RUN: {robo.RISK.dry_run} ═══")

    if not conectar_mt5():
        log.error("Falha na conexão MT5. Robô encerrado.")
        state.bot_running = False
        return

    try:
        saldo = obter_saldo()
        if saldo <= 0:
            log.error("Saldo indisponível. Robô encerrado.")
            return

        # Loop principal: roda a cada 30 segundos até receber sinal de parada
        while not state.stop_event.is_set():
            if not validar_horario():
                log.warning("Fora do horário operacional. Aguardando...")
                state.stop_event.wait(timeout=60)
                continue

            try:
                dados, noticias = coletar_dados(state.csv_path)
                ordens = gerar_ordens_ia(dados, noticias)

                aprovadas = rejeitadas = 0
                for ordem in ordens:
                    if state.stop_event.is_set():
                        break
                    ticker = ordem.get("TICKER", "???")
                    ok, motivo = validar_ordem(ordem, saldo)
                    if not ok:
                        log.warning(f"🚫 [{ticker}] Rejeitada — {motivo}")
                        rejeitadas += 1
                        continue
                    if enviar_ordem(ordem, saldo):
                        aprovadas += 1

                log.info(f"Ciclo concluído | Aprovadas: {aprovadas} | Rejeitadas: {rejeitadas}")

            except Exception as e:
                log.error(f"Erro no ciclo: {e}")

            # Aguarda 5 minutos antes do próximo ciclo (interrompível)
            state.stop_event.wait(timeout=300)

    finally:
        mt5.shutdown()
        state.bot_running = False
        log.info("🔌 Robô parado. Conexão MT5 encerrada.")


# ── Endpoints ─────────────────────────────────────────────────────────────────

@app.get("/status")
def get_status():
    """Retorna o estado completo da sessão."""
    ops = _get_mt5_operations()
    total_pnl = sum(o["pnl"] for o in ops)
    return {
        "running":          state.bot_running,
        "broker":           state.broker,
        "dryRun":           robo.RISK.dry_run,
        "sessionStart":     state.session_start,
        "ordersCount":      robo.STATE.ordens_enviadas,
        "accumulatedLoss":  robo.STATE.prejuizo_acumulado,
        "totalPnL":         round(total_pnl, 2),
        "activeOps":        len([o for o in ops if o["status"] == "ATIVA"]),
        "csvLoaded":        Path(state.csv_path).exists(),
        "csvName":          Path(state.csv_path).name,
        "risk": {
            "maxLossDiaria":  robo.RISK.max_loss_diaria_brl,
            "maxOrdens":      robo.RISK.max_ordens_por_dia,
            "maxLote":        robo.RISK.max_lote_por_ordem,
            "minRR":          robo.RISK.min_rr_ratio,
            "maxRiscoPct":    robo.RISK.max_risco_por_ordem_pct,
        },
    }


@app.post("/start")
def start_bot():
    """Inicia o robô em thread background."""
    if state.bot_running:
        raise HTTPException(400, "Robô já está em execução.")

    # Reinicia o estado da sessão
    robo.STATE = SessionState()
    state.stop_event.clear()
    state.bot_running = True
    state.session_start = datetime.now().strftime("%H:%M:%S")

    state.bot_thread = threading.Thread(target=_bot_worker, daemon=True)
    state.bot_thread.start()

    log.info(f"▶ Robô iniciado pelo dashboard. Corretora: {state.broker}")
    return {"ok": True, "message": "Robô iniciado."}


@app.post("/stop")
def stop_bot():
    """Para o robô com segurança."""
    if not state.bot_running:
        raise HTTPException(400, "Robô não está em execução.")

    state.stop_event.set()
    log.warning("◼ Sinal de parada enviado pelo dashboard.")
    return {"ok": True, "message": "Sinal de parada enviado."}


@app.get("/operations")
def get_operations():
    """Retorna operações abertas/pendentes do MT5."""
    return {"operations": _get_mt5_operations()}


def _get_mt5_operations() -> list:
    """Lê posições e ordens abertas diretamente do MT5."""
    ops = []
    if not mt5.initialize():
        return ops

    # Posições abertas (já executadas)
    positions = mt5.positions_get()
    if positions:
        for p in positions:
            direction = "COMPRA" if p.type == mt5.ORDER_TYPE_BUY else "VENDA"
            ops.append({
                "id":        p.ticket,
                "ticker":    p.symbol,
                "direction": direction,
                "entry":     round(p.price_open, 2),
                "current":   round(p.price_current, 2),
                "target":    round(p.tp, 2),
                "stop":      round(p.sl, 2),
                "lot":       p.volume,
                "pnl":       round(p.profit, 2),
                "status":    "ATIVA",
                "time":      datetime.fromtimestamp(p.time).strftime("%H:%M:%S"),
                "broker":    state.broker,
                "rr":        _calc_rr(direction, p.price_open, p.tp, p.sl),
            })

    # Ordens pendentes (ainda não executadas)
    orders = mt5.orders_get()
    if orders:
        for o in orders:
            direction = "COMPRA" if o.type in (
                mt5.ORDER_TYPE_BUY_LIMIT, mt5.ORDER_TYPE_BUY_STOP
            ) else "VENDA"
            ops.append({
                "id":        o.ticket,
                "ticker":    o.symbol,
                "direction": direction,
                "entry":     round(o.price_open, 2),
                "current":   round(o.price_current, 2),
                "target":    round(o.tp, 2),
                "stop":      round(o.sl, 2),
                "lot":       o.volume_current,
                "pnl":       0.0,
                "status":    "PENDENTE",
                "time":      datetime.fromtimestamp(o.time_setup).strftime("%H:%M:%S"),
                "broker":    state.broker,
                "rr":        _calc_rr(direction, o.price_open, o.tp, o.sl),
            })

    return ops


def _calc_rr(direction, entry, tp, sl) -> float:
    try:
        if direction == "COMPRA":
            return round((tp - entry) / (entry - sl), 2) if entry != sl else 0
        else:
            return round((entry - tp) / (sl - entry), 2) if sl != entry else 0
    except Exception:
        return 0.0


@app.post("/order")
def send_manual_order(order: OrderRequest):
    """Envia uma ordem manual vinda do dashboard."""
    if not mt5.initialize():
        raise HTTPException(503, "MT5 não disponível.")

    saldo = obter_saldo()
    ordem_dict = order.dict()

    ok, motivo = validar_ordem(ordem_dict, saldo)
    if not ok:
        log.warning(f"🚫 Ordem manual rejeitada: {motivo}")
        raise HTTPException(400, motivo)

    sucesso = enviar_ordem(ordem_dict, saldo)
    if not sucesso:
        raise HTTPException(500, "Falha ao enviar ordem ao MT5.")

    log.info(f"✅ Ordem manual {order.DIRECAO} {order.LOTE}x {order.TICKER} enviada pelo dashboard.")
    return {"ok": True, "message": f"Ordem {order.DIRECAO} {order.TICKER} enviada."}


@app.delete("/order/{ticket}")
def cancel_order(ticket: int):
    """Cancela uma ordem pendente pelo ticket MT5."""
    if not mt5.initialize():
        raise HTTPException(503, "MT5 não disponível.")

    request = {
        "action": mt5.TRADE_ACTION_REMOVE,
        "order":  ticket,
    }
    result = mt5.order_send(request)
    if result and result.retcode == mt5.TRADE_RETCODE_DONE:
        log.warning(f"🗑️ Ordem #{ticket} cancelada pelo dashboard.")
        return {"ok": True}
    else:
        code = result.retcode if result else "N/A"
        raise HTTPException(500, f"Falha ao cancelar ordem. MT5 retcode: {code}")


@app.post("/upload-csv")
async def upload_csv(file: UploadFile = File(...)):
    """Recebe o CSV do screener, normaliza via utils e persiste."""
    if not file.filename.endswith(".csv"):
        raise HTTPException(400, "Apenas arquivos .csv são aceitos.")

    # Salva o arquivo bruto temporariamente
    raw_path = Path("screener_raw_upload.csv")
    content  = await file.read()
    raw_path.write_bytes(content)

    # Normaliza via utils
    dest = Path("screener_resultados.csv")
    df, report = normalize_csv(
        input_path=str(raw_path),
        output_path=str(dest),
        validate_mt5=False,
    )
    raw_path.unlink(missing_ok=True)   # remove arquivo temporário

    if report["errors"]:
        raise HTTPException(400, f"Erro ao processar CSV: {report['errors']}")

    # Monta resposta detalhada para o dashboard
    rows = len(df)
    cols = list(df.columns)

    summary = []
    if report["column_renames"]:
        summary.append(f"{len(report['column_renames'])} coluna(s) renomeadas")
    if report["tickers_cleaned"]:
        summary.append(f"{len(report['tickers_cleaned'])} ticker(s) limpos (.SA removido)")
    if report["emojis_removed_cols"]:
        summary.append(f"emojis removidos de: {report['emojis_removed_cols']}")
    if report["warnings"]:
        summary += report["warnings"]

    log.info(f"📄 CSV '{file.filename}' normalizado — {rows} ativo(s) | "
             + " | ".join(summary) if summary else "sem alterações")

    return {
        "ok":       True,
        "rows":     rows,
        "columns":  cols,
        "filename": file.filename,
        "summary":  summary,
        "report":   {
            "column_renames":      report["column_renames"],
            "tickers_cleaned":     report["tickers_cleaned"],
            "emojis_removed_cols": report["emojis_removed_cols"],
            "warnings":            report["warnings"],
        },
    }


@app.get("/risk")
def get_risk():
    return {
        "maxLossDiaria": robo.RISK.max_loss_diaria_brl,
        "maxOrdens":     robo.RISK.max_ordens_por_dia,
        "maxLote":       robo.RISK.max_lote_por_ordem,
        "minRR":         robo.RISK.min_rr_ratio,
        "maxRiscoPct":   robo.RISK.max_risco_por_ordem_pct,
        "dryRun":        robo.RISK.dry_run,
    }


@app.post("/risk")
def update_risk(update: RiskUpdate):
    """Atualiza parâmetros de risco em tempo real sem reiniciar o robô."""
    if update.maxLossDiaria is not None:
        robo.RISK.max_loss_diaria_brl      = update.maxLossDiaria
    if update.maxOrdens is not None:
        robo.RISK.max_ordens_por_dia       = update.maxOrdens
    if update.maxLote is not None:
        robo.RISK.max_lote_por_ordem       = update.maxLote
    if update.minRR is not None:
        robo.RISK.min_rr_ratio             = update.minRR
    if update.maxRiscoPct is not None:
        robo.RISK.max_risco_por_ordem_pct  = update.maxRiscoPct
    if update.dryRun is not None:
        robo.RISK.dry_run                  = update.dryRun

    log.info(f"⚙️ Parâmetros de risco atualizados pelo dashboard.")
    return {"ok": True, "risk": get_risk()}


@app.post("/broker")
def update_broker(update: BrokerUpdate):
    """Troca a corretora ativa. Reinicia a conexão MT5."""
    if state.bot_running:
        raise HTTPException(400, "Pare o robô antes de trocar a corretora.")
    if update.broker not in ("BTG", "TORO"):
        raise HTTPException(400, "Corretora inválida. Use BTG ou TORO.")

    state.broker = update.broker
    brokers = {
        "BTG":  "BTGPactual-PRD",
        "TORO": "ToroInvestimentos-PRD",
    }
    robo.MT5_SERVER = brokers[update.broker]

    # Persiste no .env
    env_path = Path(".env")
    if env_path.exists():
        set_key(str(env_path), "BROKER_NAME", update.broker)
        set_key(str(env_path), "MT5_SERVER",  brokers[update.broker])

    log.info(f"🏦 Corretora alterada para {update.broker} ({brokers[update.broker]})")
    return {"ok": True, "broker": update.broker, "server": brokers[update.broker]}


@app.get("/logs")
def get_logs(limit: int = 100):
    """Retorna os últimos N logs do buffer."""
    return {"logs": list(state.log_buffer)[-limit:]}


# ── WebSocket — stream de logs em tempo real ──────────────────────────────────
@app.websocket("/ws/logs")
async def websocket_logs(ws: WebSocket):
    await ws.accept()
    state.ws_clients.append(ws)
    log.info(f"🔌 Dashboard conectado via WebSocket.")

    # Envia buffer histórico ao conectar
    for entry in list(state.log_buffer):
        await ws.send_json(entry)

    try:
        while True:
            # Mantém a conexão viva aguardando ping do cliente
            await ws.receive_text()
    except WebSocketDisconnect:
        state.ws_clients.remove(ws)
        log.info("🔌 Dashboard desconectado.")


# ── Inicialização ─────────────────────────────────────────────────────────────
@app.on_event("startup")
async def startup():
    global _loop
    _loop = asyncio.get_event_loop()
    log.info("🚀 QUANT·IA API rodando em http://localhost:8000")
    log.info("📡 WebSocket disponível em ws://localhost:8000/ws/logs")
    log.info("📖 Documentação em http://localhost:8000/docs")


@app.on_event("shutdown")
async def shutdown():
    if state.bot_running:
        state.stop_event.set()
    mt5.shutdown()
    log.info("API encerrada.")


# ── Entrypoint ────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import uvicorn
    uvicorn.run("api:app", host="0.0.0.0", port=8000, reload=False, log_level="warning")
