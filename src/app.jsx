import { useState, useEffect, useRef, useCallback } from "react";

// ─── CONFIG ───────────────────────────────────────────────────────────────────
const API = "http://localhost:8000";
const WS  = "ws://localhost:8000/ws/logs";

// ─── PALETTE ─────────────────────────────────────────────────────────────────
const C = {
  bg: "#070A0F", panel: "#0D1117", border: "#1C2333", border2: "#243047",
  accent: "#00D4FF", green: "#00E676", red: "#FF3D57", yellow: "#FFD600",
  muted: "#4A5568", text: "#C9D1D9", textDim: "#6B7280",
};

// ─── HELPERS ─────────────────────────────────────────────────────────────────
const fmt    = (v, d = 2) => (v >= 0 ? "+" : "") + v.toFixed(d);
const fmtBRL = (v) => "R$ " + Math.abs(v).toLocaleString("pt-BR", { minimumFractionDigits: 2 });
const statusColor = (s) => ({ ATIVA: C.accent, PENDENTE: C.yellow, STOP: C.red, ALVO: C.green })[s] ?? C.muted;

async function api(path, opts = {}) {
  try {
    const res = await fetch(`${API}${path}`, {
      headers: { "Content-Type": "application/json" },
      ...opts,
    });
    if (!res.ok) {
      const err = await res.json().catch(() => ({ detail: res.statusText }));
      throw new Error(err.detail ?? res.statusText);
    }
    return res.json();
  } catch (e) {
    throw e;
  }
}

// ─── SPARKLINE ────────────────────────────────────────────────────────────────
function Sparkline({ data, w = 300, h = 56, color = C.accent }) {
  if (!data?.length) return null;
  const min = Math.min(...data), max = Math.max(...data), range = max - min || 1;
  const pts = data.map((v, i) =>
    `${(i / (data.length - 1)) * w},${h - ((v - min) / range) * (h - 6) - 3}`
  ).join(" ");
  return (
    <svg width={w} height={h} style={{ display: "block", width: "100%" }}>
      <defs>
        <linearGradient id="sg" x1="0" y1="0" x2="0" y2="1">
          <stop offset="0%" stopColor={color} stopOpacity="0.35" />
          <stop offset="100%" stopColor={color} stopOpacity="0" />
        </linearGradient>
      </defs>
      <polygon points={`0,${h} ${pts} ${w},${h}`} fill="url(#sg)" />
      <polyline points={pts} fill="none" stroke={color} strokeWidth="1.8" />
    </svg>
  );
}

// ─── GAUGE ────────────────────────────────────────────────────────────────────
function RiskGauge({ pct, label }) {
  const r = 36, cx = 44, cy = 44, circ = Math.PI * r;
  const arc = (Math.min(pct, 100) / 100) * circ;
  const color = pct > 80 ? C.red : pct > 50 ? C.yellow : C.green;
  return (
    <div style={{ textAlign: "center" }}>
      <svg width={88} height={52}>
        <path d={`M 8,44 A ${r},${r} 0 0 1 80,44`} fill="none" stroke={C.border2} strokeWidth="6" strokeLinecap="round" />
        <path d={`M 8,44 A ${r},${r} 0 0 1 80,44`} fill="none" stroke={color} strokeWidth="6"
          strokeDasharray={`${arc} ${circ}`} strokeLinecap="round"
          style={{ transition: "stroke-dasharray 0.7s ease" }} />
        <text x={cx} y={42} textAnchor="middle" fill={color} fontSize="12" fontWeight="700"
          fontFamily="'JetBrains Mono',monospace">{pct.toFixed(0)}%</text>
      </svg>
      <div style={{ fontSize: 9, color: C.textDim, marginTop: -4, letterSpacing: 1 }}>{label}</div>
    </div>
  );
}

function StatCard({ label, value, sub, color = C.text, accent = false }) {
  return (
    <div style={{
      background: C.panel, border: `1px solid ${accent ? C.accent + "55" : C.border}`,
      borderRadius: 6, padding: "12px 16px", flex: 1, minWidth: 120,
      boxShadow: accent ? `0 0 20px ${C.accent}15` : "none",
    }}>
      <div style={{ fontSize: 9, color: C.textDim, letterSpacing: 1.5, textTransform: "uppercase", marginBottom: 4 }}>{label}</div>
      <div style={{ fontSize: 19, fontWeight: 700, color, fontFamily: "'JetBrains Mono',monospace", lineHeight: 1.2 }}>{value}</div>
      {sub && <div style={{ fontSize: 10, color: C.textDim, marginTop: 4 }}>{sub}</div>}
    </div>
  );
}

function LogLine({ entry }) {
  const color = { ERROR: C.red, WARN: C.yellow, OK: C.green }[entry.type] ?? C.textDim;
  return (
    <div style={{ display: "flex", gap: 8, fontSize: 11, fontFamily: "'JetBrains Mono',monospace", padding: "3px 0", borderBottom: `1px solid ${C.border}18` }}>
      <span style={{ color: C.textDim, minWidth: 72 }}>{entry.time}</span>
      <span style={{ color, minWidth: 46 }}>{entry.type}</span>
      <span style={{ color: C.text }}>{entry.msg}</span>
    </div>
  );
}

function Toast({ msg, type, onClose }) {
  useEffect(() => { const t = setTimeout(onClose, 4000); return () => clearTimeout(t); }, [onClose]);
  const color = type === "error" ? C.red : type === "warn" ? C.yellow : C.green;
  return (
    <div style={{
      position: "fixed", bottom: 24, right: 24, zIndex: 9999,
      background: C.panel, border: `1px solid ${color}55`, borderRadius: 8,
      padding: "12px 20px", color, fontSize: 12, fontFamily: "'JetBrains Mono',monospace",
      boxShadow: `0 4px 24px ${color}22`, maxWidth: 360,
      animation: "fadeIn 0.2s ease",
    }}>{msg}</div>
  );
}

// ─── MAIN DASHBOARD ──────────────────────────────────────────────────────────
export default function TradingDashboard() {
  const [tab, setTab]             = useState("monitor");
  const [status, setStatus]       = useState(null);
  const [ops, setOps]             = useState([]);
  const [logs, setLogs]           = useState([]);
  const [pnlHistory, setPnlHistory] = useState([]);
  const [toast, setToast]         = useState(null);
  const [csvFile, setCsvFile]     = useState(null);
  const [csvName, setCsvName]     = useState("");
  const [csvPreview, setCsvPreview] = useState(null);
  const [apiOnline, setApiOnline] = useState(false);
  const [risk, setRisk]           = useState({
    maxLossDiaria: 500, maxOrdens: 10, maxLote: 500, minRR: 1.5, maxRiscoPct: 2.0, dryRun: true,
  });
  const [orderForm, setOrderForm] = useState({
    TICKER: "", DIRECAO: "COMPRA", ENTRADA: "", ALVO: "", STOP: "", LOTE: "",
  });

  const logsEnd  = useRef(null);
  const fileRef  = useRef(null);
  const wsRef    = useRef(null);
  const pollRef  = useRef(null);

  const showToast = (msg, type = "ok") => setToast({ msg, type });

  // ── WebSocket ──────────────────────────────────────────────────────────────
  const connectWS = useCallback(() => {
    if (wsRef.current?.readyState === WebSocket.OPEN) return;
    const ws = new WebSocket(WS);
    ws.onopen    = () => { setApiOnline(true); ws.send("ping"); };
    ws.onmessage = (e) => {
      const entry = JSON.parse(e.data);
      setLogs((prev) => [...prev.slice(-300), entry]);
    };
    ws.onerror   = () => setApiOnline(false);
    ws.onclose   = () => { setApiOnline(false); setTimeout(connectWS, 3000); };
    wsRef.current = ws;
    // Keepalive
    const ping = setInterval(() => { if (ws.readyState === WebSocket.OPEN) ws.send("ping"); }, 20000);
    ws.addEventListener("close", () => clearInterval(ping));
  }, []);

  useEffect(() => {
    connectWS();
    return () => wsRef.current?.close();
  }, [connectWS]);

  // ── Polling status + operations ────────────────────────────────────────────
  const fetchStatus = useCallback(async () => {
    try {
      const s = await api("/status");
      setStatus(s);
      setRisk(s.risk ? { ...risk, ...s.risk, dryRun: s.dryRun } : risk);
      setApiOnline(true);
    } catch { setApiOnline(false); }
  }, []);

  const fetchOps = useCallback(async () => {
    try {
      const { operations } = await api("/operations");
      setOps(operations);
      // Acumula histórico de PnL para sparkline
      const total = operations.reduce((a, o) => a + o.pnl, 0);
      setPnlHistory((prev) => [...prev.slice(-60), total]);
    } catch {}
  }, []);

  useEffect(() => {
    fetchStatus();
    fetchOps();
    pollRef.current = setInterval(() => { fetchStatus(); fetchOps(); }, 3000);
    return () => clearInterval(pollRef.current);
  }, [fetchStatus, fetchOps]);

  // Auto-scroll logs
  useEffect(() => { logsEnd.current?.scrollIntoView({ behavior: "smooth" }); }, [logs]);

  // ── Bot control ────────────────────────────────────────────────────────────
  const handleStartStop = async () => {
    try {
      if (status?.running) {
        await api("/stop", { method: "POST" });
        showToast("Sinal de parada enviado.", "warn");
      } else {
        await api("/start", { method: "POST" });
        showToast("Robô iniciado.", "ok");
      }
      await fetchStatus();
    } catch (e) { showToast(e.message, "error"); }
  };

  // ── Broker switch ──────────────────────────────────────────────────────────
  const handleBroker = async (broker) => {
    try {
      await api("/broker", { method: "POST", body: JSON.stringify({ broker }) });
      showToast(`Corretora alterada para ${broker}`, "ok");
      await fetchStatus();
    } catch (e) { showToast(e.message, "error"); }
  };

  // ── Risk update ────────────────────────────────────────────────────────────
  const handleRiskChange = async (key, val) => {
    const updated = { ...risk, [key]: val };
    setRisk(updated);
    try {
      await api("/risk", {
        method: "POST",
        body: JSON.stringify({
          maxLossDiaria: updated.maxLossDiaria,
          maxOrdens:     updated.maxOrdens,
          maxLote:       updated.maxLote,
          minRR:         updated.minRR,
          maxRiscoPct:   updated.maxRiscoPct,
          dryRun:        updated.dryRun,
        }),
      });
    } catch {}
  };

  // ── CSV Upload ─────────────────────────────────────────────────────────────
  const handleFileSelect = (e) => {
    const file = e.target.files[0];
    if (!file) return;
    setCsvFile(file);
    setCsvName(file.name);
    // Preview local
    const reader = new FileReader();
    reader.onload = (ev) => {
      const lines = ev.target.result.trim().split("\n");
      const headers = lines[0].split(",").map((h) => h.trim().replace(/"/g, ""));
      const rows = lines.slice(1, 6).map((l) =>
        Object.fromEntries(l.split(",").map((v, i) => [headers[i], v.trim()]))
      );
      setCsvPreview({ headers, rows, total: lines.length - 1 });
    };
    reader.readAsText(file);
  };

  const handleCsvUpload = async () => {
    if (!csvFile) return;
    const fd = new FormData();
    fd.append("file", csvFile);
    try {
      const res = await fetch(`${API}/upload-csv`, { method: "POST", body: fd });
      const data = await res.json();
      if (!res.ok) throw new Error(data.detail);
      showToast(`CSV carregado: ${data.rows} ativo(s)`, "ok");
      await fetchStatus();
    } catch (e) { showToast(e.message, "error"); }
  };

  // ── Manual order ───────────────────────────────────────────────────────────
  const handleManualOrder = async () => {
    const { TICKER, DIRECAO, ENTRADA, ALVO, STOP, LOTE } = orderForm;
    if (!TICKER || !ENTRADA || !ALVO || !STOP || !LOTE) {
      showToast("Preencha todos os campos.", "warn"); return;
    }
    try {
      await api("/order", {
        method: "POST",
        body: JSON.stringify({
          TICKER, DIRECAO,
          ENTRADA: parseFloat(ENTRADA), ALVO: parseFloat(ALVO),
          STOP: parseFloat(STOP),       LOTE: parseFloat(LOTE),
        }),
      });
      showToast(`Ordem ${DIRECAO} ${TICKER} enviada!`, "ok");
      setOrderForm({ TICKER: "", DIRECAO: "COMPRA", ENTRADA: "", ALVO: "", STOP: "", LOTE: "" });
      await fetchOps();
    } catch (e) { showToast(e.message, "error"); }
  };

  // ── Cancel order ───────────────────────────────────────────────────────────
  const handleCancel = async (id) => {
    try {
      await api(`/order/${id}`, { method: "DELETE" });
      showToast(`Ordem #${id} cancelada.`, "warn");
      await fetchOps();
    } catch (e) { showToast(e.message, "error"); }
  };

  // ─── DERIVED ──────────────────────────────────────────────────────────────
  const totalPnL    = ops.reduce((a, o) => a + o.pnl, 0);
  const activeOps   = ops.filter((o) => o.status === "ATIVA").length;
  const winOps      = ops.filter((o) => o.status === "ALVO").length;
  const lossOps     = ops.filter((o) => o.status === "STOP").length;
  const lossMax     = risk.maxLossDiaria || 1;
  const dailyLossPct= Math.min(100, (Math.abs(Math.min(0, totalPnL)) / lossMax) * 100);
  const ordPct      = Math.min(100, ((status?.ordersCount ?? 0) / (risk.maxOrdens || 1)) * 100);

  const calcRR = () => {
    const e = parseFloat(orderForm.ENTRADA), a = parseFloat(orderForm.ALVO), s = parseFloat(orderForm.STOP);
    if (!e || !a || !s || e === s) return null;
    return orderForm.DIRECAO === "COMPRA" ? (a - e) / (e - s) : (e - a) / (s - e);
  };
  const rr = calcRR();

  // ─── STYLES ───────────────────────────────────────────────────────────────
  const P  = { background: C.panel, border: `1px solid ${C.border}`, borderRadius: 8, padding: 16 };
  const IS = { background: C.bg, border: `1px solid ${C.border2}`, borderRadius: 4, color: C.text, padding: "6px 10px", fontSize: 12, fontFamily: "'JetBrains Mono',monospace", width: "100%", outline: "none" };
  const Btn = (active, color = C.accent) => ({
    background: active ? color + "22" : "transparent",
    border: `1px solid ${active ? color : C.border}`,
    color: active ? color : C.textDim,
    borderRadius: 4, padding: "5px 14px", fontSize: 11, cursor: "pointer",
    letterSpacing: 1, fontFamily: "'JetBrains Mono',monospace", transition: "all 0.15s",
  });

  const running = status?.running ?? false;
  const broker  = status?.broker  ?? "BTG";
  const dryRun  = status?.dryRun  ?? true;

  return (
    <div style={{ background: C.bg, minHeight: "100vh", fontFamily: "'JetBrains Mono',monospace", color: C.text }}>
      <style>{`
        @import url('https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@300;400;500;700&family=Syne:wght@700;800&display=swap');
        * { box-sizing: border-box; margin: 0; padding: 0; }
        ::-webkit-scrollbar { width: 4px; height: 4px; }
        ::-webkit-scrollbar-track { background: ${C.bg}; }
        ::-webkit-scrollbar-thumb { background: ${C.border2}; border-radius: 2px; }
        input::placeholder { color: ${C.muted}; }
        .rh:hover { background: ${C.border}22 !important; }
        @keyframes pulse { 0%,100%{opacity:1} 50%{opacity:.3} }
        @keyframes fadeIn { from{opacity:0;transform:translateY(6px)} to{opacity:1;transform:translateY(0)} }
        .blink { animation: pulse 1.5s infinite; }
        .fade-in { animation: fadeIn 0.25s ease forwards; }
      `}</style>

      {/* ── TOPBAR ── */}
      <div style={{ background: C.panel, borderBottom: `1px solid ${C.border}`, padding: "0 20px", display: "flex", alignItems: "center", gap: 16, height: 52, flexWrap: "wrap" }}>
        <div style={{ display: "flex", alignItems: "center", gap: 8 }}>
          <div style={{ width: 8, height: 8, borderRadius: "50%", background: apiOnline ? (running ? C.green : C.accent) : C.red, boxShadow: apiOnline ? `0 0 8px ${running ? C.green : C.accent}` : "none" }} className={running ? "blink" : ""} />
          <span style={{ fontSize: 14, fontWeight: 800, fontFamily: "'Syne',sans-serif", color: C.accent, letterSpacing: 2 }}>QUANT·IA</span>
          <span style={{ fontSize: 9, color: C.textDim, letterSpacing: 1 }}>B3 TERMINAL</span>
        </div>
        {!apiOnline && (
          <span style={{ fontSize: 10, color: C.red, border: `1px solid ${C.red}44`, borderRadius: 3, padding: "2px 8px" }}>
            ⚠ API OFFLINE — rode: python api.py
          </span>
        )}
        <div style={{ flex: 1 }} />
        {["BTG", "TORO"].map((b) => (
          <button key={b} onClick={() => handleBroker(b)} style={{ ...Btn(broker === b), fontSize: 10, padding: "4px 12px" }}>{b}</button>
        ))}
        <button onClick={() => handleRiskChange("dryRun", !dryRun)}
          style={{ ...Btn(!dryRun, C.yellow), fontSize: 10, padding: "4px 12px" }}>
          {dryRun ? "🧪 DRY RUN" : "⚡ REAL"}
        </button>
        <button onClick={handleStartStop} disabled={!apiOnline}
          style={{ ...Btn(running, running ? C.red : C.green), fontSize: 10, padding: "4px 16px", fontWeight: 700, opacity: apiOnline ? 1 : 0.4 }}>
          {running ? "◼ PARAR" : "▶ INICIAR"}
        </button>
        <span style={{ fontSize: 10, color: C.textDim }}>{new Date().toLocaleTimeString("pt-BR")}</span>
      </div>

      {/* ── TABS ── */}
      <div style={{ background: C.panel, borderBottom: `1px solid ${C.border}`, padding: "0 20px", display: "flex" }}>
        {["monitor", "ordens", "risco"].map((t) => (
          <button key={t} onClick={() => setTab(t)} style={{
            background: "transparent", border: "none",
            borderBottom: `2px solid ${tab === t ? C.accent : "transparent"}`,
            color: tab === t ? C.accent : C.textDim,
            padding: "10px 20px", fontSize: 11, cursor: "pointer", letterSpacing: 1.5, textTransform: "uppercase",
          }}>{t}</button>
        ))}
      </div>

      <div style={{ padding: 16 }}>

        {/* ══ MONITOR ══ */}
        {tab === "monitor" && (
          <div className="fade-in" style={{ display: "flex", flexDirection: "column", gap: 14 }}>
            {/* Stat row */}
            <div style={{ display: "flex", gap: 10, flexWrap: "wrap" }}>
              <StatCard label="P&L Total" value={fmtBRL(totalPnL)} sub={fmt(totalPnL)} color={totalPnL >= 0 ? C.green : C.red} accent />
              <StatCard label="Ativas" value={activeOps} color={C.accent} />
              <StatCard label="Alvos" value={winOps} color={C.green} />
              <StatCard label="Stops" value={lossOps} color={C.red} />
              <StatCard label="Ordens/Dia" value={`${status?.ordersCount ?? 0}/${risk.maxOrdens}`} color={C.text} />
              <StatCard label="Corretora" value={broker} sub={dryRun ? "DRY RUN" : "REAL"} color={dryRun ? C.yellow : C.green} />
            </div>

            {/* Chart + Gauges */}
            <div style={{ display: "flex", gap: 12 }}>
              <div style={{ ...P, flex: 1 }}>
                <div style={{ fontSize: 9, color: C.textDim, letterSpacing: 1.5, marginBottom: 10 }}>CURVA P&L DA SESSÃO (TEMPO REAL)</div>
                <Sparkline data={pnlHistory} color={totalPnL >= 0 ? C.green : C.red} />
              </div>
              <div style={{ ...P, display: "flex", gap: 20, alignItems: "center", padding: "16px 24px" }}>
                <RiskGauge pct={dailyLossPct} label="PERDA DIÁRIA" />
                <RiskGauge pct={ordPct} label="ORDENS/DIA" />
                <RiskGauge pct={Math.min(100, (activeOps / 5) * 100)} label="EXPOSIÇÃO" />
              </div>
            </div>

            {/* Operations table */}
            <div style={P}>
              <div style={{ fontSize: 9, color: C.textDim, letterSpacing: 1.5, marginBottom: 12 }}>
                OPERAÇÕES MT5 — ATUALIZAÇÃO A CADA 3S
              </div>
              {ops.length === 0 ? (
                <div style={{ color: C.muted, fontSize: 11, padding: "20px 0", textAlign: "center" }}>
                  {apiOnline ? "Nenhuma operação aberta no MT5." : "Aguardando conexão com a API..."}
                </div>
              ) : (
                <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 11 }}>
                  <thead>
                    <tr style={{ color: C.textDim, fontSize: 9, letterSpacing: 1, textTransform: "uppercase" }}>
                      {["Ticker","Dir","Entrada","Atual","Alvo","Stop","Lote","R/R","P&L","Status","Hora",""].map((h) => (
                        <th key={h} style={{ padding: "4px 8px", textAlign: "left", borderBottom: `1px solid ${C.border}` }}>{h}</th>
                      ))}
                    </tr>
                  </thead>
                  <tbody>
                    {ops.map((op) => (
                      <tr key={op.id} className="rh" style={{ borderBottom: `1px solid ${C.border}18`, transition: "background 0.1s" }}>
                        <td style={{ padding: "7px 8px", color: C.accent, fontWeight: 700 }}>{op.ticker}</td>
                        <td style={{ padding: "7px 8px", color: op.direction === "COMPRA" ? C.green : C.red, fontWeight: 600 }}>{op.direction}</td>
                        <td style={{ padding: "7px 8px" }}>{op.entry?.toFixed(2)}</td>
                        <td style={{ padding: "7px 8px", color: C.text }}>{op.current?.toFixed(2)}</td>
                        <td style={{ padding: "7px 8px", color: C.green }}>{op.target?.toFixed(2)}</td>
                        <td style={{ padding: "7px 8px", color: C.red }}>{op.stop?.toFixed(2)}</td>
                        <td style={{ padding: "7px 8px" }}>{op.lot}</td>
                        <td style={{ padding: "7px 8px", color: (op.rr ?? 0) >= risk.minRR ? C.green : C.yellow }}>{op.rr?.toFixed(2)}</td>
                        <td style={{ padding: "7px 8px", color: op.pnl >= 0 ? C.green : C.red, fontWeight: 700 }}>{fmt(op.pnl)} R$</td>
                        <td style={{ padding: "7px 8px" }}>
                          <span style={{ background: statusColor(op.status) + "22", color: statusColor(op.status), border: `1px solid ${statusColor(op.status)}55`, borderRadius: 3, padding: "2px 7px", fontSize: 9, letterSpacing: 1 }}>{op.status}</span>
                        </td>
                        <td style={{ padding: "7px 8px", color: C.textDim }}>{op.time}</td>
                        <td style={{ padding: "7px 8px" }}>
                          {(op.status === "ATIVA" || op.status === "PENDENTE") && (
                            <button onClick={() => handleCancel(op.id)}
                              style={{ background: C.red + "18", border: `1px solid ${C.red}55`, color: C.red, borderRadius: 3, padding: "2px 8px", fontSize: 9, cursor: "pointer" }}>✕</button>
                          )}
                        </td>
                      </tr>
                    ))}
                  </tbody>
                </table>
              )}
            </div>

            {/* Live log */}
            <div style={{ ...P, maxHeight: 200, overflowY: "auto" }}>
              <div style={{ fontSize: 9, color: C.textDim, letterSpacing: 1.5, marginBottom: 8 }}>LOG AO VIVO — WEBSOCKET</div>
              {logs.length === 0 && <div style={{ color: C.muted, fontSize: 11 }}>Aguardando logs...</div>}
              {logs.map((l, i) => <LogLine key={i} entry={l} />)}
              <div ref={logsEnd} />
            </div>
          </div>
        )}

        {/* ══ ORDENS ══ */}
        {tab === "ordens" && (
          <div className="fade-in" style={{ display: "flex", gap: 14, flexWrap: "wrap" }}>

            {/* CSV Upload */}
            <div style={{ ...P, flex: 1, minWidth: 300 }}>
              <div style={{ fontSize: 9, color: C.textDim, letterSpacing: 1.5, marginBottom: 14 }}>📄 SCREENER CSV</div>
              <div onClick={() => fileRef.current?.click()} style={{
                border: `2px dashed ${csvPreview ? C.green + "66" : C.border2}`, borderRadius: 8,
                padding: "28px 20px", textAlign: "center", cursor: "pointer",
                background: csvPreview ? C.green + "08" : "transparent", transition: "all 0.2s",
              }}>
                <div style={{ fontSize: 26, marginBottom: 8 }}>📥</div>
                <div style={{ color: csvPreview ? C.green : C.textDim, fontSize: 12 }}>
                  {csvPreview ? `✅ ${csvName}` : "Clique para selecionar CSV"}
                </div>
                {csvPreview && <div style={{ color: C.textDim, fontSize: 10, marginTop: 4 }}>{csvPreview.total} ativos</div>}
              </div>
              <input ref={fileRef} type="file" accept=".csv" onChange={handleFileSelect} style={{ display: "none" }} />

              {csvPreview && (
                <>
                  <div style={{ marginTop: 14, maxHeight: 240, overflowY: "auto" }}>
                    <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 10 }}>
                      <thead>
                        <tr>{csvPreview.headers.map((h) => (
                          <th key={h} style={{ padding: "4px 6px", color: C.textDim, textAlign: "left", borderBottom: `1px solid ${C.border}`, letterSpacing: 1 }}>{h}</th>
                        ))}</tr>
                      </thead>
                      <tbody>
                        {csvPreview.rows.map((row, i) => (
                          <tr key={i} className="rh">
                            {csvPreview.headers.map((h) => (
                              <td key={h} style={{ padding: "5px 6px", borderBottom: `1px solid ${C.border}22` }}>{row[h]}</td>
                            ))}
                          </tr>
                        ))}
                      </tbody>
                    </table>
                    {csvPreview.total > 5 && <div style={{ fontSize: 9, color: C.textDim, padding: "6px 0", textAlign: "center" }}>+{csvPreview.total - 5} linhas ocultas</div>}
                  </div>
                  <button onClick={handleCsvUpload}
                    style={{ ...Btn(true), width: "100%", padding: "8px", fontWeight: 700, marginTop: 10 }}>
                    ⬆️ ENVIAR CSV PARA A API
                  </button>
                </>
              )}
              {status?.csvLoaded && (
                <div style={{ marginTop: 10, fontSize: 10, color: C.green, textAlign: "center" }}>
                  ✅ API usando: {status.csvName}
                </div>
              )}
            </div>

            {/* Manual order */}
            <div style={{ ...P, flex: 1, minWidth: 260 }}>
              <div style={{ fontSize: 9, color: C.textDim, letterSpacing: 1.5, marginBottom: 14 }}>✏️ ORDEM MANUAL</div>
              <div style={{ display: "flex", flexDirection: "column", gap: 10 }}>
                <div>
                  <div style={{ fontSize: 9, color: C.textDim, marginBottom: 4 }}>TICKER</div>
                  <input style={IS} placeholder="Ex: PETR4"
                    value={orderForm.TICKER}
                    onChange={(e) => setOrderForm((p) => ({ ...p, TICKER: e.target.value.toUpperCase() }))} />
                </div>
                <div>
                  <div style={{ fontSize: 9, color: C.textDim, marginBottom: 4 }}>DIREÇÃO</div>
                  <div style={{ display: "flex", gap: 8 }}>
                    {["COMPRA", "VENDA"].map((d) => (
                      <button key={d} onClick={() => setOrderForm((p) => ({ ...p, DIRECAO: d }))}
                        style={{ ...Btn(orderForm.DIRECAO === d, d === "COMPRA" ? C.green : C.red), flex: 1, padding: "7px" }}>{d}</button>
                    ))}
                  </div>
                </div>
                {[["ENTRADA", "ENTRADA"], ["ALVO", "ALVO"], ["STOP", "STOP"], ["LOTE", "LOTE"]].map(([lbl, key]) => (
                  <div key={key}>
                    <div style={{ fontSize: 9, color: C.textDim, marginBottom: 4 }}>{lbl}</div>
                    <input style={IS} type="number" placeholder="0.00"
                      value={orderForm[key]}
                      onChange={(e) => setOrderForm((p) => ({ ...p, [key]: e.target.value }))} />
                  </div>
                ))}

                {rr !== null && (
                  <div style={{ background: C.border + "44", borderRadius: 4, padding: "8px 12px", fontSize: 10 }}>
                    <span style={{ color: rr >= risk.minRR ? C.green : C.red }}>
                      R/R: {isFinite(rr) ? rr.toFixed(2) : "—"} {rr >= risk.minRR ? "✅" : "⚠️ Abaixo do mínimo"}
                    </span>
                  </div>
                )}

                <button onClick={handleManualOrder} disabled={!apiOnline}
                  style={{ ...Btn(true), padding: "10px", fontWeight: 700, marginTop: 4, opacity: apiOnline ? 1 : 0.4 }}>
                  {dryRun ? "🧪 SIMULAR ORDEM" : "⚡ ENVIAR ORDEM"}
                </button>
              </div>
            </div>
          </div>
        )}

        {/* ══ RISCO ══ */}
        {tab === "risco" && (
          <div className="fade-in" style={{ display: "flex", gap: 14, flexWrap: "wrap" }}>
            <div style={{ ...P, flex: 1, minWidth: 300 }}>
              <div style={{ fontSize: 9, color: C.textDim, letterSpacing: 1.5, marginBottom: 16 }}>🛡️ PARÂMETROS DE RISCO (TEMPO REAL)</div>
              {[
                ["Perda Máx. Diária (R$)", "maxLossDiaria", 50, 5000, 50],
                ["Máx. Ordens / Dia",      "maxOrdens",     1,  50,   1],
                ["Lote Máx. por Ordem",    "maxLote",       100,5000, 100],
                ["R/R Mínimo",             "minRR",         1.0,5.0,  0.1],
                ["Risco Máx. / Ordem (%)", "maxRiscoPct",   0.5,10.0, 0.5],
              ].map(([label, key, min, max, step]) => (
                <div key={key} style={{ marginBottom: 16 }}>
                  <div style={{ display: "flex", justifyContent: "space-between", fontSize: 11, marginBottom: 6 }}>
                    <span style={{ color: C.text }}>{label}</span>
                    <span style={{ color: C.accent, fontWeight: 700 }}>{risk[key]}</span>
                  </div>
                  <input type="range" min={min} max={max} step={step} value={risk[key]}
                    onChange={(e) => handleRiskChange(key, parseFloat(e.target.value))}
                    style={{ width: "100%", accentColor: C.accent, cursor: "pointer" }} />
                  <div style={{ display: "flex", justifyContent: "space-between", fontSize: 9, color: C.muted }}>
                    <span>{min}</span><span>{max}</span>
                  </div>
                </div>
              ))}
              <div style={{ display: "flex", gap: 8, marginTop: 4 }}>
                <button onClick={() => handleRiskChange("dryRun", true)}
                  style={{ ...Btn(dryRun, C.yellow), flex: 1, padding: "8px" }}>🧪 DRY RUN</button>
                <button onClick={() => handleRiskChange("dryRun", false)}
                  style={{ ...Btn(!dryRun, C.red), flex: 1, padding: "8px" }}>⚡ REAL</button>
              </div>
            </div>

            <div style={{ ...P, flex: 1, minWidth: 260 }}>
              <div style={{ fontSize: 9, color: C.textDim, letterSpacing: 1.5, marginBottom: 16 }}>📊 STATUS DA SESSÃO</div>
              <div style={{ display: "flex", gap: 20, justifyContent: "center", marginBottom: 20 }}>
                <RiskGauge pct={dailyLossPct} label="PERDA DIÁRIA" />
                <RiskGauge pct={ordPct}       label="ORDENS USADAS" />
              </div>
              {[
                ["P&L Acumulado",    fmtBRL(totalPnL),                       totalPnL >= 0 ? C.green : C.red],
                ["Ordens Enviadas",  `${status?.ordersCount ?? 0} / ${risk.maxOrdens}`, C.text],
                ["Perda Acumulada",  fmtBRL(status?.accumulatedLoss ?? 0),   C.red],
                ["Limite Diário",    fmtBRL(risk.maxLossDiaria),             C.text],
                ["Operações Ativas", activeOps,                              C.accent],
              ].map(([label, value, color]) => (
                <div key={label} style={{ display: "flex", justifyContent: "space-between", padding: "8px 0", borderBottom: `1px solid ${C.border}` }}>
                  <span style={{ color: C.textDim, fontSize: 11 }}>{label}</span>
                  <span style={{ color, fontWeight: 700, fontSize: 11 }}>{value}</span>
                </div>
              ))}
              <div style={{
                marginTop: 16, padding: "10px 14px", borderRadius: 6, fontSize: 11,
                background: dailyLossPct > 80 ? C.red + "18" : C.green + "18",
                border: `1px solid ${dailyLossPct > 80 ? C.red : C.green}44`,
              }}>
                {dailyLossPct > 80
                  ? "⚠️ Limite de perda próximo. Novas ordens serão bloqueadas em breve."
                  : "✅ Risco da sessão dentro dos parâmetros."}
              </div>
            </div>
          </div>
        )}
      </div>

      {/* Toast */}
      {toast && <Toast msg={toast.msg} type={toast.type} onClose={() => setToast(null)} />}
    </div>
  );
}
