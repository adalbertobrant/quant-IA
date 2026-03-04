"""
Robô de Trading IA Quantitativo
Versão melhorada com controles de risco para BTG e Toro Investimentos
"""

import os
import json
import logging
import time
from datetime import datetime, time as dtime
from dataclasses import dataclass, field
from typing import Optional

import google.generativeai as genai
import pandas as pd
import yfinance as yf
import MetaTrader5 as mt5
from dotenv import load_dotenv
from utils import normalize_csv, print_report

# ==========================================
# LOGGING ESTRUTURADO
# ==========================================
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[
        logging.FileHandler(f"robo_{datetime.now().strftime('%Y%m%d')}.log"),
        logging.StreamHandler(),
    ],
)
log = logging.getLogger(__name__)

# ==========================================
# 1. CONFIGURAÇÕES (via .env — NUNCA hardcode credenciais)
# ==========================================
load_dotenv()  # Crie um arquivo .env na mesma pasta (ver instruções ao final)

BROKERS = {
    "BTG": {
        "server": os.getenv("MT5_SERVER", "BTGPactual-PRD"),
        "magic": 100001,
    },
    "TORO": {
        "server": os.getenv("MT5_SERVER", "ToroInvestimentos-PRD"),
        "magic": 100002,
    },
}

BROKER_NAME = os.getenv("BROKER_NAME", "BTG")   # Troque para "TORO" se necessário
BROKER_CFG  = BROKERS[BROKER_NAME]

MT5_LOGIN    = int(os.getenv("MT5_LOGIN", "0"))
MT5_PASSWORD = os.getenv("MT5_PASSWORD", "")
MT5_SERVER   = BROKER_CFG["server"]
MAGIC_NUMBER = BROKER_CFG["magic"]

GOOGLE_API_KEY = os.getenv("GOOGLE_API_KEY", "")

# ==========================================
# 2. PARÂMETROS DE RISCO
# ==========================================
@dataclass
class RiskConfig:
    max_loss_diaria_brl: float = float(os.getenv("MAX_LOSS_DIARIA", "500.0"))
    max_ordens_por_dia: int    = int(os.getenv("MAX_ORDENS_DIA",    "10"))
    max_lote_por_ordem: float  = float(os.getenv("MAX_LOTE_ORDEM",  "500.0"))
    min_rr_ratio: float        = float(os.getenv("MIN_RR_RATIO",    "1.5"))   # Risco/Retorno mínimo
    max_risco_por_ordem_pct: float = float(os.getenv("MAX_RISCO_PCT", "2.0")) # % do capital por ordem
    dry_run: bool              = os.getenv("DRY_RUN", "true").lower() == "true"
    horario_inicio: dtime      = dtime(10, 5)   # Não operar no leilão de abertura
    horario_fim: dtime         = dtime(17, 30)  # Fechar antes do after-market

RISK = RiskConfig()

# ==========================================
# 3. ESTADO DA SESSÃO
# ==========================================
@dataclass
class SessionState:
    ordens_enviadas: int   = 0
    prejuizo_acumulado: float = 0.0
    tickers_com_ordem: list  = field(default_factory=list)

STATE = SessionState()

# ==========================================
# 4. CONEXÃO COM MT5
# ==========================================
def _gerar_otp() -> str:
    """
    Gera o código OTP de 6 dígitos se MT5_OTP_SECRET estiver configurado no .env.
    Retorna string vazia se OTP não estiver configurado ou pyotp não instalado.
    """
    secret = os.getenv("MT5_OTP_SECRET", "").strip()
    if not secret:
        return ""
    try:
        import pyotp
        totp   = pyotp.TOTP(secret)
        codigo = totp.now()
        restam = 30 - (int(time.time()) % 30)
        log.info(f"🔐 OTP gerado: {codigo} (válido por {restam}s)")
        return codigo
    except ImportError:
        log.warning("MT5_OTP_SECRET configurado mas pyotp não instalado. "
                    "Execute: pip install pyotp")
        return ""
    except Exception as e:
        log.error(f"Erro ao gerar OTP: {e}")
        return ""


def conectar_mt5() -> bool:
    """
    Inicializa e autentica no MetaTrader 5.

    Fluxo:
      1. mt5.initialize() — conecta ao terminal MT5 já aberto na máquina
      2. Gera OTP automaticamente se MT5_OTP_SECRET estiver no .env
      3. mt5.login() com senha normal ou senha+OTP conforme necessário
      4. Tenta até 3 vezes em caso de falha transitória
    """
    # Passo 1: inicializa o terminal
    if not mt5.initialize():
        log.error(f"Falha ao inicializar o MT5. "
                  f"Verifique se o terminal está aberto e logado. "
                  f"Erro: {mt5.last_error()}")
        return False

    # Passo 2: prepara credenciais com OTP se necessário
    otp   = _gerar_otp()
    senha = f"{MT5_PASSWORD}{otp}" if otp else MT5_PASSWORD

    if otp:
        log.info("🔐 Autenticação com 2FA/OTP ativada.")

    # Passo 3: login com retry
    for tentativa in range(1, 4):
        authorized = mt5.login(MT5_LOGIN, password=senha, server=MT5_SERVER)

        if authorized:
            info = mt5.account_info()
            log.info(
                f"✅ Conectado | Corretora: {BROKER_NAME} | "
                f"Conta: {info.login} | "
                f"Saldo: R$ {info.balance:,.2f} | "
                f"Margem Livre: R$ {info.margin_free:,.2f}"
            )
            return True

        erro = mt5.last_error()
        log.warning(f"Tentativa {tentativa}/3 falhou. MT5 erro: {erro}")

        # Se o OTP expirou entre tentativas, gera um novo
        if otp and tentativa < 3:
            log.info("🔐 Regenerando OTP para nova tentativa...")
            otp   = _gerar_otp()
            senha = f"{MT5_PASSWORD}{otp}" if otp else MT5_PASSWORD

        time.sleep(2)

    log.error("❌ Falha ao autenticar no MT5 após 3 tentativas.")
    mt5.shutdown()
    return False



def obter_saldo() -> float:
    info = mt5.account_info()
    return info.balance if info else 0.0


# ==========================================
# 5. VALIDAÇÕES DE RISCO PRÉ-ORDEM
# ==========================================
def validar_horario() -> bool:
    agora = datetime.now().time()
    if not (RISK.horario_inicio <= agora <= RISK.horario_fim):
        log.warning(f"⏰ Fora do horário operacional ({RISK.horario_inicio} – {RISK.horario_fim}).")
        return False
    return True


def validar_ordem(ordem: dict, saldo: float) -> tuple[bool, str]:
    """Aplica todas as regras de risco antes de enviar uma ordem."""
    ticker   = ordem.get("TICKER", "")
    direcao  = ordem.get("DIRECAO", "")
    entrada  = float(ordem.get("ENTRADA", 0))
    alvo     = float(ordem.get("ALVO",   0))
    stop     = float(ordem.get("STOP",   0))
    lote     = float(ordem.get("LOTE",   0))

    # — Campos obrigatórios
    if not all([ticker, direcao, entrada, alvo, stop, lote]):
        return False, "Campos obrigatórios ausentes ou zerados."

    # — Direção válida
    if direcao not in ("COMPRA", "VENDA"):
        return False, f"Direção inválida: {direcao}"

    # — Lote máximo
    if lote > RISK.max_lote_por_ordem:
        return False, f"Lote {lote} excede o máximo permitido ({RISK.max_lote_por_ordem})."

    # — Lógica de preços para COMPRA
    if direcao == "COMPRA":
        if not (stop < entrada < alvo):
            return False, f"Preços incoerentes para COMPRA: STOP {stop} < ENTRADA {entrada} < ALVO {alvo}"
    # — Lógica de preços para VENDA
    else:
        if not (alvo < entrada < stop):
            return False, f"Preços incoerentes para VENDA: ALVO {alvo} < ENTRADA {entrada} < STOP {stop}"

    # — Relação Risco/Retorno mínima
    risco   = abs(entrada - stop)
    retorno = abs(alvo - entrada)
    if risco == 0 or (retorno / risco) < RISK.min_rr_ratio:
        return False, f"R/R {retorno/risco:.2f} abaixo do mínimo {RISK.min_rr_ratio}."

    # — Risco financeiro máximo por ordem
    risco_brl     = risco * lote
    risco_pct     = (risco_brl / saldo) * 100 if saldo > 0 else 100
    if risco_pct > RISK.max_risco_por_ordem_pct:
        return False, f"Risco da ordem ({risco_pct:.1f}%) excede o limite de {RISK.max_risco_por_ordem_pct}%."

    # — Limite de perda diária
    if STATE.prejuizo_acumulado + risco_brl > RISK.max_loss_diaria_brl:
        return False, (f"Ordem bloqueada: perda diária acumularia "
                       f"R$ {STATE.prejuizo_acumulado + risco_brl:.2f} "
                       f"(limite: R$ {RISK.max_loss_diaria_brl:.2f}).")

    # — Limite de ordens por dia
    if STATE.ordens_enviadas >= RISK.max_ordens_por_dia:
        return False, f"Limite de {RISK.max_ordens_por_dia} ordens/dia atingido."

    # — Evitar ordens duplicadas no mesmo ticker
    if ticker in STATE.tickers_com_ordem:
        return False, f"Já existe uma ordem aberta para {ticker}."

    return True, "OK"


# ==========================================
# 6. ENVIO DE ORDEM COM RETRY
# ==========================================
def enviar_ordem(ordem: dict, saldo: float, tentativas: int = 3) -> bool:
    ticker   = ordem["TICKER"]
    direcao  = ordem["DIRECAO"]
    entrada  = float(ordem["ENTRADA"])
    alvo     = float(ordem["ALVO"])
    stop     = float(ordem["STOP"])
    lote     = float(ordem["LOTE"])

    if not mt5.symbol_select(ticker, True):
        log.error(f"❌ [{ticker}] Ativo não encontrado no MT5.")
        return False

    # Normaliza preços para a corretora (evita rejeição por tick size)
    info_ativo = mt5.symbol_info(ticker)
    if not info_ativo:
        log.error(f"❌ [{ticker}] Não foi possível obter informações do ativo.")
        return False

    digits = info_ativo.digits
    entrada = round(entrada, digits)
    alvo    = round(alvo,    digits)
    stop    = round(stop,    digits)

    order_type = mt5.ORDER_TYPE_BUY_LIMIT if direcao == "COMPRA" else mt5.ORDER_TYPE_SELL_LIMIT

    request = {
        "action":      mt5.TRADE_ACTION_PENDING,
        "symbol":      ticker,
        "volume":      lote,
        "type":        order_type,
        "price":       entrada,
        "sl":          stop,
        "tp":          alvo,
        "deviation":   10,
        "magic":       MAGIC_NUMBER,
        "comment":     f"RoboIA_{BROKER_NAME}",
        "type_time":   mt5.ORDER_TIME_DAY,
        "type_filling": mt5.ORDER_FILLING_RETURN,
    }

    if RISK.dry_run:
        log.info(f"🧪 [DRY RUN] Ordem simulada: {direcao} {lote}x {ticker} "
                 f"| Entrada: {entrada} | Alvo: {alvo} | Stop: {stop}")
        STATE.ordens_enviadas += 1
        STATE.tickers_com_ordem.append(ticker)
        return True

    for tentativa in range(1, tentativas + 1):
        result = mt5.order_send(request)
        if result and result.retcode == mt5.TRADE_RETCODE_DONE:
            risco_brl = abs(entrada - stop) * lote
            STATE.ordens_enviadas      += 1
            STATE.prejuizo_acumulado   += risco_brl
            STATE.tickers_com_ordem.append(ticker)
            log.info(f"✅ [{ticker}] {direcao} {lote}x enviado | "
                     f"Entrada: {entrada} | Alvo: {alvo} | Stop: {stop} | "
                     f"Risco máx.: R$ {risco_brl:.2f}")
            return True
        else:
            code = result.retcode if result else "N/A"
            msg  = result.comment if result else "sem resposta"
            log.warning(f"⚠️  [{ticker}] Tentativa {tentativa}/{tentativas} falhou. "
                        f"Código MT5: {code} | {msg}")
            time.sleep(1)

    log.error(f"❌ [{ticker}] Falha definitiva após {tentativas} tentativas.")
    return False


# ==========================================
# 7. COLETA DE DADOS
# ==========================================
def coletar_dados(csv_path: str = "screener_resultados.csv") -> tuple[str, str]:
    log.info("📊 Lendo e normalizando screener...")

    df, report = normalize_csv(
        input_path=csv_path,
        output_path=csv_path,   # sobrescreve o arquivo com a versão limpa
        validate_mt5=False,     # validação MT5 opcional — ative se quiser filtrar antes
    )

    if report["errors"]:
        for err in report["errors"]:
            log.error(f"Erro no CSV: {err}")
        return "", ""

    if report["column_renames"] or report["tickers_cleaned"] or report["emojis_removed_cols"]:
        log.info(f"CSV normalizado — renomeações: {report['column_renames']} | "
                 f"tickers limpos: {len(report['tickers_cleaned'])} | "
                 f"emojis removidos: {report['emojis_removed_cols']}")

    if report["warnings"]:
        for w in report["warnings"]:
            log.warning(f"CSV aviso: {w}")

    dados_tecnicos = df.to_string(index=False)
    noticias = ""

    for ticker in df["Ticker"].unique():
        try:
            stock = yf.Ticker(ticker)
            news  = stock.news
            if news:
                noticias += f"\n[{ticker}]: {news[0]['title']}"
        except Exception as e:
            log.debug(f"Falha ao obter notícias para {ticker}: {e}")

    return dados_tecnicos, noticias


# ==========================================
# 8. IA — GERAÇÃO DE ORDENS
# ==========================================
SYSTEM_INSTRUCTION = """
Você é um Estrategista Quantitativo conservador operando na B3.
Analise os dados técnicos, múltiplos fundamentalistas e notícias fornecidos.
Retorne EXCLUSIVAMENTE um array JSON puro, sem markdown, sem comentários.

Regras obrigatórias:
- Só sugira ordens com relação Risco/Retorno >= 1.5
- Para COMPRA: STOP < ENTRADA < ALVO
- Para VENDA:  ALVO  < ENTRADA < STOP
- Limite máximo de 5 ordens por resposta

Formato exigido (array JSON):
[
  {"TICKER": "PETR4", "DIRECAO": "COMPRA", "ENTRADA": 38.50, "ALVO": 40.00, "STOP": 37.50, "LOTE": 100}
]
"""


def gerar_ordens_ia(dados_tecnicos: str, noticias: str) -> list[dict]:
    genai.configure(api_key=GOOGLE_API_KEY)
    model = genai.GenerativeModel(
        model_name="gemini-1.5-pro",
        generation_config={"temperature": 0.0, "response_mime_type": "application/json"},
        system_instruction=SYSTEM_INSTRUCTION,
    )

    prompt = (
        f"Dados Técnicos do Screener:\n{dados_tecnicos}\n\n"
        f"Notícias do Mercado:\n{noticias}"
    )

    log.info("🤖 Consultando IA para geração de ordens...")
    try:
        response = model.generate_content(prompt)
        ordens   = json.loads(response.text)
        if not isinstance(ordens, list):
            log.error("Resposta da IA não é uma lista. Abortando.")
            return []
        log.info(f"IA gerou {len(ordens)} ordem(ns).")
        return ordens
    except json.JSONDecodeError as e:
        log.error(f"Falha ao interpretar JSON da IA: {e}\nResposta bruta: {response.text}")
        return []
    except Exception as e:
        log.error(f"Erro na chamada à IA: {e}")
        return []


# ==========================================
# 9. FLUXO PRINCIPAL
# ==========================================
def main():
    log.info(f"═══ Iniciando Robô IA | Corretora: {BROKER_NAME} | "
             f"DRY RUN: {RISK.dry_run} ═══")

    # — Verificações iniciais
    if not GOOGLE_API_KEY:
        log.error("GOOGLE_API_KEY não configurada. Abortando.")
        return
    if not MT5_LOGIN or not MT5_PASSWORD:
        log.error("Credenciais MT5 não configuradas. Abortando.")
        return

    # — Horário de operação
    if not validar_horario():
        return

    # — Conexão com a corretora
    if not conectar_mt5():
        return

    try:
        saldo = obter_saldo()
        if saldo <= 0:
            log.error("Saldo indisponível ou conta sem fundos. Abortando.")
            return

        # — Coleta de dados
        dados_tecnicos, noticias = coletar_dados()

        # — Geração de ordens pela IA
        ordens = gerar_ordens_ia(dados_tecnicos, noticias)
        if not ordens:
            log.info("Nenhuma ordem gerada pela IA.")
            return

        # — Validação e envio
        aprovadas = rejeitadas = 0
        for ordem in ordens:
            ticker = ordem.get("TICKER", "???")
            ok, motivo = validar_ordem(ordem, saldo)
            if not ok:
                log.warning(f"🚫 [{ticker}] Ordem REJEITADA — {motivo}")
                rejeitadas += 1
                continue

            sucesso = enviar_ordem(ordem, saldo)
            if sucesso:
                aprovadas += 1

        log.info(f"═══ Sessão encerrada | Aprovadas: {aprovadas} | "
                 f"Rejeitadas: {rejeitadas} | "
                 f"Risco acumulado: R$ {STATE.prejuizo_acumulado:.2f} ═══")

    finally:
        mt5.shutdown()
        log.info("🔌 Conexão MT5 encerrada.")


if __name__ == "__main__":
    main()


# ==========================================
# INSTRUÇÕES DE CONFIGURAÇÃO
# ==========================================
# Crie um arquivo chamado ".env" na mesma pasta com o seguinte conteúdo:
#
# BROKER_NAME=BTG               # ou TORO
# MT5_LOGIN=12345678
# MT5_PASSWORD=SuaSenha
# MT5_SERVER=BTGPactual-PRD     # BTGPactual-PRD | ToroInvestimentos-PRD | BTGPactual-Demo
# GOOGLE_API_KEY=sua_chave_aqui
#
# # Parâmetros de Risco (todos opcionais — os valores abaixo são os padrões)
# MAX_LOSS_DIARIA=500.0         # Perda máxima em R$ por dia
# MAX_ORDENS_DIA=10             # Máximo de ordens enviadas por sessão
# MAX_LOTE_ORDEM=500            # Lote máximo por ordem
# MIN_RR_RATIO=1.5              # Relação Risco/Retorno mínima aceita
# MAX_RISCO_PCT=2.0             # % máxima do capital arriscado por ordem
# DRY_RUN=true                  # true = simula sem enviar; false = envia de verdade
#
# IMPORTANTE: Nunca envie o arquivo .env para o Git.
# Adicione ".env" ao seu .gitignore.
#
# Dependências necessárias:
# pip install google-generativeai pandas yfinance MetaTrader5 python-dotenv
