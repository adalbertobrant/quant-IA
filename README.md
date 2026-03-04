# QUANT·IA — B3 Terminal
### Robô de Trading Quantitativo com IA + Dashboard em Tempo Real

> Sistema completo de automação de ordens na B3 com inteligência artificial (Google Gemini),
> integração nativa com MetaTrader 5, normalização automática de dados via `utils/`,
> API FastAPI e interface gráfica React com logs ao vivo via WebSocket.

---

## Índice

1. [Visão Geral da Arquitetura](#1-visão-geral-da-arquitetura)
2. [Estrutura de Arquivos](#2-estrutura-de-arquivos)
3. [Pré-requisitos](#3-pré-requisitos)
4. [Instalação Passo a Passo](#4-instalação-passo-a-passo)
5. [Configurando as Credenciais](#5-configurando-as-credenciais)
6. [Configurando o MetaTrader 5](#6-configurando-o-metatrader-5)
7. [Configurando a Chave do Google AI](#7-configurando-a-chave-do-google-ai)
8. [Módulo utils/ — Normalização do CSV](#8-módulo-utils--normalização-do-csv)
9. [Capturando Dados de Terceiros para o Screener](#9-capturando-dados-de-terceiros-para-o-screener)
10. [Rodando o Sistema Completo](#10-rodando-o-sistema-completo)
11. [Usando o Dashboard](#11-usando-o-dashboard)
12. [Parâmetros de Risco](#12-parâmetros-de-risco)
13. [Corretoras Suportadas](#13-corretoras-suportadas)
14. [Referência da API](#14-referência-da-api)
15. [Segurança](#15-segurança)
16. [Solução de Problemas](#16-solução-de-problemas)
17. [Aviso Legal](#17-aviso-legal)

---

## 1. Visão Geral da Arquitetura

```
┌──────────────────────────────────────────────────────────────┐
│              FONTES EXTERNAS DE DADOS (Screener)             │
│  Yahoo Finance · Trademap · Status Invest · Economatica      │
│  Fundamentus · Código Python próprio (yfinance / pandas)     │
└─────────────────────────┬────────────────────────────────────┘
                          │  CSV bruto (qualquer formato)
┌─────────────────────────▼────────────────────────────────────┐
│                    utils/utils.py                            │
│  • Remove sufixos .SA, .F, .BZ dos tickers                  │
│  • Renomeia colunas por similaridade (40+ aliases)          │
│  • Elimina emojis e caracteres especiais                     │
│  • Arredonda floats · Remove duplicatas                      │
│  • Detecta encoding UTF-8 / latin-1 automaticamente         │
│  • Gera relatório de diagnóstico                             │
└─────────────────────────┬────────────────────────────────────┘
                          │  CSV padronizado
┌─────────────────────────▼────────────────────────────────────┐
│                DASHBOARD REACT (porta 5173)                  │
│  • Upload de CSV com preview e relatório de normalização     │
│  • Monitoramento de P&L e operações ao vivo                  │
│  • Controle do robô (iniciar / parar)                        │
│  • Sliders de risco em tempo real                            │
└──────────────────────────┬───────────────────────────────────┘
                           │  HTTP + WebSocket
┌──────────────────────────▼───────────────────────────────────┐
│                  API FASTAPI (porta 8000)                    │
│  • Ponte entre Dashboard e Robô                              │
│  • Normaliza CSV no upload via utils/                        │
│  • Stream de logs via WebSocket                              │
└──────────┬────────────────────────────┬──────────────────────┘
           │ Python import              │ MT5 API (DLL)
┌──────────▼───────────┐  ┌────────────▼─────────────────────┐
│  ROBÔ IA (Python)    │  │      METATRADER 5                │
│  • Google Gemini     │  │  • BTG Pactual / Toro            │
│  • utils/ antes      │  │  • Ordens pendentes (B3)         │
│    de cada ciclo     │  │  • Posições abertas              │
│  • Validação risco   │  │  • Saldo e margem                │
└──────────────────────┘  └──────────────────────────────────┘
```

**Fluxo completo de uma operação:**

```
Fonte externa (yfinance, Trademap, etc.)
          │
          ▼  CSV bruto
    utils/utils.py  ──── normaliza tickers, colunas, emojis, encoding
          │
          ▼  CSV limpo
  Google Gemini 1.5 Pro  ──── analisa dados técnicos + notícias
          │
          ▼  JSON com ordens candidatas
     Validação de Risco  ──── R/R, lote, % capital, perda diária
          │
          ▼
    MT5 order_send()  ──── ordem pendente na B3
          │
          ▼
    WebSocket  ──── log ao vivo no Dashboard
```

---

## 2. Estrutura de Arquivos

```
quant-ia/
│
├── utils/
│   ├── __init__.py                 ← torna utils um pacote Python
│   └── utils.py                   ← normalização e validação de CSV
│
├── src/
│   ├── App.jsx                    ← Dashboard React (renomear de trading_dashboard_v2.jsx)
│   └── main.jsx                   ← Entry point React
│
├── robo_ia_quantitativo.py        ← Robô Python (cérebro)
├── api.py                         ← API FastAPI (ponte)
├── index.html                     ← HTML base do Vite
├── vite.config.js                 ← Configuração do Vite
├── package.json                   ← Dependências Node.js
│
├── screener_resultados.csv        ← CSV normalizado (gerado pelo utils/)
│
├── .env                           ← ⚠️ CREDENCIAIS — nunca commitar
├── .gitignore
├── start.bat                      ← Sobe tudo com duplo clique (Windows)
│
└── robo_YYYYMMDD.log              ← Logs diários (gerados automaticamente)
```

### Preparação inicial dos arquivos

```bash
# 1. Crie a pasta utils e o __init__.py
mkdir utils
copy NUL utils\__init__.py

# 2. Mova o utils.py para dentro da pasta
move utils.py utils\utils.py

# 3. Crie a pasta src e mova o dashboard
mkdir src
copy trading_dashboard_v2.jsx src\App.jsx
copy main.jsx src\main.jsx
```

---

## 3. Pré-requisitos

### Sistema Operacional

| Componente | OS necessário | Motivo |
|---|---|---|
| Robô + API | **Windows 10 ou 11** | MetaTrader5 só tem DLL para Windows |
| Dashboard React | Windows, macOS ou Linux | Roda no navegador |

### Softwares

**Python 3.10+**
```
https://www.python.org/downloads/
```
Marque ✅ **Add Python to PATH** durante a instalação.

**Node.js 18+ LTS**
```
https://nodejs.org/en/download
```

**MetaTrader 5**
Baixe diretamente do portal da sua corretora — **não** do site da MetaQuotes.

### Contas necessárias

| Conta | Finalidade | Custo |
|---|---|---|
| BTG Pactual ou Toro | Enviar ordens à B3 via MT5 | Conforme corretora |
| Google AI Studio | Chave de API para o Gemini | Gratuito |
| Yahoo Finance / Trademap / etc. | Fonte de dados do screener | Gratuito ou pago |

---

## 4. Instalação Passo a Passo

Abra o **Prompt de Comando** como administrador na pasta do projeto.

### Etapa 1 — Dependências Python

```bash
pip install fastapi uvicorn python-dotenv google-generativeai pandas yfinance MetaTrader5
```

Confirme:
```bash
python -c "import fastapi, MetaTrader5, google.generativeai, pandas; print('OK')"
```

### Etapa 2 — Dependências Node.js

```bash
npm install
```

### Etapa 3 — Estrutura de pastas

```bash
mkdir utils
copy NUL utils\__init__.py
move utils.py utils\utils.py
mkdir src
copy trading_dashboard_v2.jsx src\App.jsx
```

### Etapa 4 — Arquivo `.env`

Veja a seção [Configurando as Credenciais](#5-configurando-as-credenciais).

### Etapa 5 — Verificação rápida

```bash
# Testa o módulo utils com seu CSV
python utils\utils.py seu_screener.csv screener_resultados.csv

# Testa a API
python api.py
# Ctrl+C para parar após ver "QUANT·IA API rodando"
```

---

## 5. Configurando as Credenciais

Crie o arquivo `.env` na raiz do projeto:

```bash
copy NUL .env
notepad .env
```

Cole e preencha:

```env
# ════════════════════════════════════════
#  CORRETORA
# ════════════════════════════════════════

# BTG ou TORO
BROKER_NAME=BTG

# Número da conta MT5
# MT5 → Ver → Terminal → aba "Conta" → número no topo
MT5_LOGIN=12345678

# Senha de negociação MT5
# Diferente da senha do app — veja seção "Configurando o MT5"
MT5_PASSWORD=SuaSenhaDaNegociacao

# Servidor da corretora — veja seção "Corretoras Suportadas"
MT5_SERVER=BTGPactual-PRD


# ════════════════════════════════════════
#  INTELIGÊNCIA ARTIFICIAL
# ════════════════════════════════════════

# Chave do Google AI Studio (começa com AIzaSy...)
GOOGLE_API_KEY=AIzaSyXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX


# ════════════════════════════════════════
#  PARÂMETROS DE RISCO
# ════════════════════════════════════════

MAX_LOSS_DIARIA=500.0
MAX_ORDENS_DIA=10
MAX_LOTE_ORDEM=500
MIN_RR_RATIO=1.5
MAX_RISCO_PCT=2.0


# ════════════════════════════════════════
#  MODO DE OPERAÇÃO
# ════════════════════════════════════════

# true = simulação | false = ordens reais
DRY_RUN=true
```

### Onde encontrar cada dado

**MT5_LOGIN:**
```
MT5 → Ver → Terminal (Ctrl+T) → aba "Conta" → número em destaque
```

**MT5_PASSWORD (senha de negociação):**

É diferente da senha do aplicativo da corretora. Se não souber:
- **BTG:** acesse o suporte e solicite a "senha de negociação MetaTrader 5"
- **Toro:** abra o chat do app Toro e peça a "senha de acesso ao MT5"

**MT5_SERVER:**
```
MT5 → Arquivo → Abrir Conta → pesquise sua corretora → copie o nome exato da lista
```

---

## 6. Configurando o MetaTrader 5

### Habilitar trading automático

```
MT5 → Ferramentas → Opções → Expert Advisors
```

Marque:
- ✅ Permitir negociação automática
- ✅ Permitir importações DLL
- ✅ Permitir negociação para Expert Advisors ao vivo

Reinicie o MT5. Na barra de ferramentas, o botão **"Algo Trading"** deve ficar **verde**.

### Lote padrão vs. fracionário

| Modo | Ticker | Lote mínimo |
|---|---|---|
| Lote padrão | `PETR4` | 100 ações |
| Fracionário | `PETR4F` | 1 ação |

---

## 7. Configurando a Chave do Google AI

1. Acesse [aistudio.google.com](https://aistudio.google.com)
2. Login com conta Google → **"Get API key"** → **"Create API key"**
3. Copie a chave (`AIzaSy...`) para o `.env`

Teste:
```bash
python -c "
import google.generativeai as genai, os
from dotenv import load_dotenv
load_dotenv()
genai.configure(api_key=os.getenv('GOOGLE_API_KEY'))
r = genai.GenerativeModel('gemini-1.5-pro').generate_content('Responda: OK')
print(r.text.strip())
"
```

O plano gratuito suporta 1.500 requisições/dia — suficiente para pregões normais (o robô faz 1 requisição a cada 5 minutos).

---

## 8. Módulo utils/ — Normalização do CSV

O módulo `utils/utils.py` é executado automaticamente toda vez que um CSV é carregado — seja pelo robô Python, pelo upload no Dashboard, ou manualmente via linha de comando. Ele garante que qualquer CSV gerado por qualquer fonte externa chegue ao sistema no formato correto.

### O que o módulo corrige automaticamente

**Tickers:**
Remove sufixos de origem de dados externos como `.SA` (Yahoo Finance), `.F` (fracionário Yahoo), `.BZ` (Bloomberg) e `.US`, convertendo para o formato exato que o MT5 da B3 espera.

| Entrada | Saída |
|---|---|
| `PETR4.SA` | `PETR4` |
| `VALE3.BZ` | `VALE3` |
| `ITUB4.F` | `ITUB4` |
| ` petr4 ` | `PETR4` |

**Colunas:**
Detecta nomes alternativos por similaridade e renomeia para o padrão canônico. Funciona com 40+ variações comuns:

| Entrada (exemplos) | Saída canônica |
|---|---|
| `Preço Fech.`, `close`, `ultimo`, `fechamento` | `Preco_Fech` |
| `Sinal(is)`, `alertas`, `signal` | `Sinais` |
| `Sinal MACD`, `macd_sinal`, `macd signal` | `Sinal_MACD` |
| `P/L`, `pl`, `preco_lucro` | `P_L` |
| `EV/EBITDA`, `ev_ebitda` | `EV_EBITDA` |
| `DY`, `dividend yield` | `Div_Yield` |

**Valores:**
Remove emojis e símbolos Unicode de colunas de texto (comum em exports do Trademap e Status Invest), arredonda floats para 2 casas decimais para reduzir tokens enviados à IA.

**Encoding:**
Detecta automaticamente UTF-8 ou latin-1 — resolve o problema de arquivos exportados pelo Excel no Windows.

**Duplicatas:**
Remove tickers duplicados, mantendo a primeira ocorrência.

### Uso via linha de comando

```bash
# Normalizar e sobrescrever
python utils\utils.py screener_bruto.csv screener_resultados.csv

# Normalizar + validar tickers contra o MT5 (remove os não encontrados)
python utils\utils.py screener_bruto.csv screener_resultados.csv --validate-mt5

# Ver o relatório sem salvar
python utils\utils.py screener_bruto.csv
```

Saída de exemplo:
```
════════════════════════════════════════════════════════
  QUANT·IA — Relatório de Normalização do CSV
════════════════════════════════════════════════════════
  Arquivo:      screener_bruto.csv
  Linhas:       36

  Colunas renomeadas (3):
    'Preço Fech.'  →  'Preco_Fech'
    'Sinal MACD'   →  'Sinal_MACD'
    'Sinal(is)'    →  'Sinais'

  Tickers limpos (36):
    'PETR4.SA'  →  'PETR4'
    'VALE3.SA'  →  'VALE3'
    ... e mais 34

  Emojis removidos nas colunas: ['Sinais']
  Colunas arredondadas: ['Preco_Fech', 'RSI', 'MACD', 'Sinal_MACD']

  ✅  Salvo em: screener_resultados.csv
════════════════════════════════════════════════════════
```

### Adicionando novos aliases de coluna

Edite o dicionário `COLUMN_ALIASES` em `utils/utils.py`:

```python
COLUMN_ALIASES: dict[str, str] = {
    # Adicione sua variação aqui:
    "minha coluna": "Nome_Canonico",
    ...
}
```

---

## 9. Capturando Dados de Terceiros para o Screener

O CSV de entrada pode vir de qualquer fonte. O módulo `utils/` normaliza automaticamente o formato. Abaixo estão as principais fontes e como exportar de cada uma.

---

### Opção A — Yahoo Finance via Python (automatizado)

A forma mais prática: um script Python que gera o CSV diretamente, sem intervenção manual. Rode antes de iniciar o robô.

**Instale a dependência:**
```bash
pip install yfinance pandas
```

**Script `gerar_screener.py`:**

```python
"""
Gera screener_resultados.csv com dados técnicos via yfinance.
Execute toda manhã antes de iniciar o robô:
  python gerar_screener.py
"""
import yfinance as yf
import pandas as pd
from utils.utils import normalize_csv, print_report

# Lista de tickers que você quer monitorar (sufixo .SA é removido pelo utils/)
TICKERS = [
    "PETR4.SA", "VALE3.SA", "ITUB4.SA", "BBDC4.SA", "WEGE3.SA",
    "RENT3.SA", "LREN3.SA", "MGLU3.SA", "GGBR4.SA", "CSNA3.SA",
]

def calcular_rsi(serie: pd.Series, periodo: int = 14) -> float:
    delta  = serie.diff()
    ganho  = delta.clip(lower=0).rolling(periodo).mean()
    perda  = (-delta.clip(upper=0)).rolling(periodo).mean()
    rs     = ganho / perda
    return round(100 - (100 / (1 + rs.iloc[-1])), 2)

def calcular_macd(serie: pd.Series):
    ema12  = serie.ewm(span=12).mean()
    ema26  = serie.ewm(span=26).mean()
    macd   = ema12 - ema26
    sinal  = macd.ewm(span=9).mean()
    return round(macd.iloc[-1], 4), round(sinal.iloc[-1], 4)

rows = []
for ticker in TICKERS:
    try:
        hist = yf.Ticker(ticker).history(period="3mo")
        if hist.empty:
            print(f"[AVISO] Sem dados para {ticker}")
            continue

        close  = hist["Close"]
        rsi    = calcular_rsi(close)
        macd, sinal_macd = calcular_macd(close)
        mm20   = round(close.rolling(20).mean().iloc[-1], 2)
        mm50   = round(close.rolling(50).mean().iloc[-1], 2)
        vol    = int(hist["Volume"].iloc[-1])

        rows.append({
            "Ticker":     ticker,
            "Preco_Fech": round(close.iloc[-1], 2),
            "RSI":        rsi,
            "MACD":       macd,
            "Sinal_MACD": sinal_macd,
            "Volume":     vol,
            "Media_20":   mm20,
            "Media_50":   mm50,
        })
        print(f"✅ {ticker}")
    except Exception as e:
        print(f"❌ {ticker}: {e}")

df_bruto = pd.DataFrame(rows)
df_bruto.to_csv("screener_bruto.csv", index=False)

# Normaliza via utils/ (remove .SA, padroniza colunas, etc.)
df, report = normalize_csv("screener_bruto.csv", "screener_resultados.csv")
print_report(report)
print(f"\n✅ screener_resultados.csv gerado com {len(df)} ativos.")
```

Execute:
```bash
python gerar_screener.py
```

---

### Opção B — Trademap (export manual)

O [Trademap](https://trademap.com.br) é um dos screeners mais completos para a B3 e exporta CSV diretamente.

1. Acesse trademap.com.br e faça login
2. Vá em **Ações → Filtros**
3. Configure os indicadores que quiser (RSI, MACD, Volume, P/L, etc.)
4. Clique em **Exportar → CSV**
5. Salve como `screener_bruto.csv` na pasta do projeto
6. O utils/ normaliza automaticamente no próximo ciclo ou upload

O CSV do Trademap vem com colunas como `Preço Fech.`, `Sinal(is)` e emojis — tudo tratado pelo `utils/utils.py`.

---

### Opção C — Status Invest (export manual)

O [Status Invest](https://statusinvest.com.br) é gratuito e tem uma boa cobertura de fundamentos.

1. Acesse statusinvest.com.br → **Ações**
2. Use os filtros avançados para montar sua lista
3. Clique em **Exportar** (ícone de planilha no canto superior direito)
4. Salve como `screener_bruto.csv`
5. Normalize com:
```bash
python utils\utils.py screener_bruto.csv screener_resultados.csv
```

---

### Opção D — Fundamentus (scraping automatizado)

O [Fundamentus](https://fundamentus.com.br) não tem API oficial, mas é simples de raspar com `requests` + `pandas`.

**Script `gerar_screener_fundamentus.py`:**

```python
"""
Captura dados fundamentalistas do Fundamentus e combina com dados
técnicos do yfinance para gerar o screener completo.
"""
import requests
import pandas as pd
from utils.utils import normalize_csv

HEADERS = {"User-Agent": "Mozilla/5.0"}

def buscar_fundamentus():
    url = "https://www.fundamentus.com.br/resultado.php"
    r = requests.get(url, headers=HEADERS, timeout=15)
    # Fundamentus retorna tabela HTML — pandas lê direto
    tabelas = pd.read_html(r.text, decimal=",", thousands=".")
    df = tabelas[0]
    df = df.rename(columns={"Papel": "Ticker"})
    return df

df_fund = buscar_fundamentus()
df_fund.to_csv("screener_bruto.csv", index=False, encoding="utf-8")

# Normaliza via utils/
df, report = normalize_csv("screener_bruto.csv", "screener_resultados.csv")
print(f"✅ {len(df)} ativos do Fundamentus normalizados.")
```

---

### Opção E — Economatica / Bloomberg / outras plataformas profissionais

Plataformas profissionais exportam em formatos variados (CSV, XLSX, texto delimitado). O módulo `utils/` lida com todas as variações comuns. Para XLSX, converta antes:

```python
import pandas as pd

# Converte XLSX para CSV antes de passar ao utils/
df = pd.read_excel("export_economatica.xlsx", sheet_name=0)
df.to_csv("screener_bruto.csv", index=False, encoding="utf-8")
```

Depois:
```bash
python utils\utils.py screener_bruto.csv screener_resultados.csv
```

---

### Formato mínimo aceito pelo utils/

Independente da fonte, o CSV precisa ter **pelo menos** uma coluna identificável como ticker:

```csv
Ticker
PETR4.SA
VALE3.SA
ITUB4.SA
```

Colunas adicionais enriquecem a análise da IA. Quanto mais indicadores, melhor a qualidade das ordens geradas.

### Colunas reconhecidas pelo utils/

| Coluna canônica | Aliases reconhecidos automaticamente |
|---|---|
| `Ticker` | ticker, ativo, papel, codigo, symbol |
| `Preco_Fech` | Preço Fech., close, fechamento, ultimo, último preço |
| `RSI` | rsi, RSI_14, rsi14 |
| `MACD` | macd, macd_linha, macd linha |
| `Sinal_MACD` | Sinal MACD, sinal macd, macd_sinal, macd signal |
| `Sinais` | Sinal(is), sinal, alertas, signal |
| `Volume` | volume, vol |
| `Media_20` | mm20, sma20, ema20, media_20 |
| `Media_50` | mm50, sma50, ema50, media_50 |
| `P_L` | P/L, pl, preco_lucro |
| `EV_EBITDA` | EV/EBITDA, ev_ebitda |
| `Div_Yield` | DY, dy, dividend yield |
| `ROE` | roe |
| `Setor` | setor, sector |

---

## 10. Rodando o Sistema Completo

### Fluxo diário recomendado

```
ANTES DO PREGÃO (até 10h00)
│
├── 1. Gere ou exporte o CSV do screener
│       python gerar_screener.py
│       (ou exporte manualmente do Trademap/Status Invest)
│
├── 2. Normalize se necessário
│       python utils\utils.py screener_bruto.csv screener_resultados.csv
│
├── 3. Abra e confirme login no MetaTrader 5
│
└── 4. Inicie o sistema
        start.bat  (duplo clique)

DURANTE O PREGÃO (10h05 – 17h25)
│
├── Acompanhe pelo Dashboard em http://localhost:5173
├── Logs ao vivo na aba Monitor
├── Ajuste parâmetros de risco na aba Risco conforme necessário
└── Cancele ordens individuais pela tabela se precisar

APÓS O PREGÃO
└── Revise os logs do dia: robo_YYYYMMDD.log
```

### Opção A — start.bat (1 clique)

Dê **duplo clique** em `start.bat`. O launcher sobe a API, o Dashboard e abre o navegador automaticamente.

### Opção B — Manualmente (para debug)

**Terminal 1:**
```bash
python api.py
```

**Terminal 2:**
```bash
npm run dev
```

Acesse `http://localhost:5173`.

---

## 11. Usando o Dashboard

### Aba Monitor

Atualiza automaticamente a cada 3 segundos via polling + WebSocket.

**Topbar:**
- `BTG` / `TORO` — troca corretora (robô deve estar parado)
- `🧪 DRY RUN` / `⚡ REAL` — alterna modo de operação em tempo real
- `▶ INICIAR` / `◼ PARAR` — controla o robô

**Tabela de operações:**
Lê posições e ordens pendentes diretamente do MT5. Botão ✕ cancela a ordem real.

**Log ao vivo:**
Cada linha de log do Python aparece instantaneamente via WebSocket.

### Aba Ordens

**Upload de CSV:**
Clique na área tracejada e selecione qualquer CSV. O módulo `utils/` normaliza automaticamente no servidor e o Dashboard exibe o relatório de alterações (colunas renomeadas, tickers limpos, emojis removidos). Clique em **"Enviar CSV para a API"** para confirmar.

**Ordem Manual:**
R/R calculado em tempo real. Bloqueio automático se estiver abaixo do mínimo configurado.

### Aba Risco

Todos os sliders atualizam os parâmetros do robô em tempo real via `POST /risk`. Nenhum reinício necessário.

---

## 12. Parâmetros de Risco

| Parâmetro | `.env` | Padrão | Efeito ao atingir |
|---|---|---|---|
| Perda máx. diária | `MAX_LOSS_DIARIA` | R$ 500 | Para de enviar novas ordens |
| Máx. ordens/dia | `MAX_ORDENS_DIA` | 10 | Bloqueia novas ordens |
| Lote máximo | `MAX_LOTE_ORDEM` | 500 | Rejeita a ordem |
| R/R mínimo | `MIN_RR_RATIO` | 1.5 | Rejeita a ordem |
| Risco por ordem | `MAX_RISCO_PCT` | 2.0% | Rejeita a ordem |
| Simulação | `DRY_RUN` | true | Simula sem enviar ao MT5 |

### Fluxo de validação de cada ordem (9 etapas)

```
 1. Campos obrigatórios presentes e não zerados?
 2. Direção é COMPRA ou VENDA?
 3. Lote ≤ MAX_LOTE_ORDEM?
 4. Preços lógicos?
      COMPRA: STOP < ENTRADA < ALVO
      VENDA:  ALVO < ENTRADA < STOP
 5. R/R ≥ MIN_RR_RATIO?
 6. Risco financeiro ≤ MAX_RISCO_PCT do saldo?
 7. Perda acumulada + risco desta ordem ≤ MAX_LOSS_DIARIA?
 8. Ordens do dia < MAX_ORDENS_DIA?
 9. Já existe ordem aberta neste ticker?

Falhou em qualquer etapa → rejeitada e logada → próxima ordem avaliada.
```

---

## 13. Corretoras Suportadas

### BTG Pactual

```env
BROKER_NAME=BTG
MT5_SERVER=BTGPactual-PRD
# Demo:
MT5_SERVER=BTGPactual-Demo
```

### Toro Investimentos

```env
BROKER_NAME=TORO
MT5_SERVER=ToroInvestimentos-PRD
```

### Como confirmar o servidor exato

```
MT5 → Arquivo → Abrir Conta → pesquise a corretora → copie o nome da lista
```

### Adicionar outra corretora

Em `api.py` e `robo_ia_quantitativo.py`, edite o dicionário:

```python
BROKERS = {
    "BTG":  { "server": "BTGPactual-PRD",       "magic": 100001 },
    "TORO": { "server": "ToroInvestimentos-PRD", "magic": 100002 },
    "XP":   { "server": "XPInvestimentos-PRD",   "magic": 100003 },
}
```

---

## 14. Referência da API

Documentação interativa em `http://localhost:8000/docs`.

| Método | Endpoint | Descrição |
|---|---|---|
| `GET` | `/status` | Estado completo: robô, sessão, P&L, risco |
| `POST` | `/start` | Inicia o robô |
| `POST` | `/stop` | Para o robô |
| `GET` | `/operations` | Posições e ordens do MT5 |
| `POST` | `/order` | Ordem manual com validação de risco |
| `DELETE` | `/order/{ticket}` | Cancela ordem pelo ticket MT5 |
| `POST` | `/upload-csv` | Upload + normalização automática via utils/ |
| `GET` | `/risk` | Parâmetros de risco atuais |
| `POST` | `/risk` | Atualiza parâmetros em tempo real |
| `POST` | `/broker` | Troca corretora (persiste no .env) |
| `GET` | `/logs` | Últimos N logs do buffer |
| `WS` | `/ws/logs` | Stream contínuo de logs |

---

## 15. Segurança

### Proteção do `.env`

```bash
echo .env >> .gitignore
echo *.log >> .gitignore
echo __pycache__/ >> .gitignore
echo node_modules/ >> .gitignore
echo screener_bruto.csv >> .gitignore
```

### Processo antes de operar com dinheiro real

**Semana 1 — DRY RUN:** `DRY_RUN=true`, 5 pregões completos. Revise os logs diariamente.

**Semana 2 — Conta demo:** `DRY_RUN=false`, servidor demo (`BTGPactual-Demo`). Verifique se ordens chegam corretamente.

**Semana 3+ — Conta real mínima:** servidor PRD, `MAX_LOTE_ORDEM=100`, `MAX_LOSS_DIARIA=100`. Acompanhe presencialmente.

### Checklist pré-sessão real

- [ ] MT5 aberto, logado, "Algo Trading" verde
- [ ] CSV do screener gerado e normalizado com dados do dia
- [ ] Dashboard mostra ⚡ REAL (não 🧪 DRY RUN)
- [ ] Limites de risco revisados
- [ ] Log do dia anterior sem erros críticos
- [ ] Horário entre 10h05 e 17h25

---

## 16. Solução de Problemas

### "API OFFLINE" no dashboard
A API não está rodando. Execute `python api.py` e leia a mensagem de erro.

### "Falha ao conectar no MT5"
Verifique se o MT5 está aberto e logado, se `MT5_LOGIN` são apenas números, se `MT5_SERVER` está correto e se "Algo Trading" está verde.

```bash
python -c "
import MetaTrader5 as mt5, os
from dotenv import load_dotenv
load_dotenv()
ok = mt5.initialize(login=int(os.getenv('MT5_LOGIN')),
                    password=os.getenv('MT5_PASSWORD'),
                    server=os.getenv('MT5_SERVER'))
print('OK' if ok else f'ERRO: {mt5.last_error()}')
mt5.shutdown()
"
```

### "Falha ao interpretar JSON da IA"
Reduza o CSV para no máximo 20 tickers. Verifique se o CSV foi normalizado pelo `utils/` (sem acentos nos cabeçalhos, sem emojis).

### "Ativo não encontrado no MT5"
Use `--validate-mt5` ao normalizar o CSV:
```bash
python utils\utils.py screener_bruto.csv screener_resultados.csv --validate-mt5
```
Isso remove automaticamente os tickers não disponíveis na sua corretora.

### Tickers com formato estranho após normalização
Adicione um alias em `utils/utils.py`:
```python
COLUMN_ALIASES["minha variacao"] = "Nome_Canonico"
```

### Dashboard não abre
```bash
rmdir /s /q node_modules
npm install
npm run dev
```

---

## 17. Aviso Legal

Este software é fornecido exclusivamente para fins educacionais e de automação pessoal. Operações em renda variável envolvem risco substancial de perda do capital investido. O desempenho passado não garante resultados futuros. O autor não se responsabiliza por perdas financeiras, falhas técnicas ou erros de execução. Consulte um assessor de investimentos certificado (AAI) antes de automatizar estratégias com capital real.

---

*QUANT·IA B3 Terminal — Documentação v3.0 — Sistema Integrado com utils/*
