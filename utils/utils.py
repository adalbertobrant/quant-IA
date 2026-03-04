"""
QUANT·IA — utils.py
Módulo de normalização e validação de CSV screener.

Responsabilidades:
  - Detectar e remover sufixos de ticker (.SA, .F, etc.)
  - Sanitizar nomes de colunas (acentos, espaços, emojis, parênteses)
  - Remover emojis e caracteres especiais de valores
  - Detectar e padronizar colunas obrigatórias por similaridade de nome
  - Validar tickers contra o MT5
  - Arredondar floats para reduzir tokens enviados à IA
  - Exportar CSV limpo pronto para uso
  - Gerar relatório de diagnóstico com tudo que foi alterado
"""

import re
import logging
import unicodedata
from pathlib import Path
from typing import Optional

import pandas as pd

log = logging.getLogger(__name__)

# ── Mapeamento de nomes alternativos → nome canônico ─────────────────────────
# Adicione aqui qualquer variação que seu screener possa gerar
COLUMN_ALIASES: dict[str, str] = {
    # Ticker
    "ticker":           "Ticker",
    "ativo":            "Ticker",
    "papel":            "Ticker",
    "codigo":           "Ticker",
    "symbol":           "Ticker",

    # Preço
    "preco_fech":       "Preco_Fech",
    "preco fech":       "Preco_Fech",
    "preco fech.":      "Preco_Fech",
    "preco fechamento": "Preco_Fech",
    "fechamento":       "Preco_Fech",
    "close":            "Preco_Fech",
    "ultimo":           "Preco_Fech",
    "ultimo preco":     "Preco_Fech",

    # RSI
    "rsi":              "RSI",
    "rsi_14":           "RSI",
    "rsi14":            "RSI",

    # MACD
    "macd":             "MACD",
    "macd_linha":       "MACD",
    "macd linha":       "MACD",

    # Sinal MACD
    "sinal_macd":       "Sinal_MACD",
    "sinal macd":       "Sinal_MACD",
    "macd_sinal":       "Sinal_MACD",
    "macd signal":      "Sinal_MACD",

    # Sinais / alertas
    "sinal(is)":        "Sinais",
    "sinais":           "Sinais",
    "sinal":            "Sinais",
    "alerta":           "Sinais",
    "alertas":          "Sinais",
    "signal":           "Sinais",

    # Volume
    "volume":           "Volume",
    "vol":              "Volume",

    # Médias móveis
    "media_20":         "Media_20",
    "mm20":             "Media_20",
    "sma20":            "Media_20",
    "ema20":            "Media_20",
    "media_50":         "Media_50",
    "mm50":             "Media_50",
    "sma50":            "Media_50",
    "ema50":            "Media_50",

    # Fundamentos
    "p/l":              "P_L",
    "pl":               "P_L",
    "p_l":              "P_L",
    "preco_lucro":      "P_L",
    "ev/ebitda":        "EV_EBITDA",
    "ev_ebitda":        "EV_EBITDA",
    "dy":               "Div_Yield",
    "div_yield":        "Div_Yield",
    "dividend yield":   "Div_Yield",
    "roe":              "ROE",
    "setor":            "Setor",
    "sector":           "Setor",
}

# Sufixos de troca/mercado a remover dos tickers
TICKER_SUFFIXES = re.compile(r"\.(SA|F|BZ|US|L)$", re.IGNORECASE)

# Padrão de ticker válido na B3 após limpeza
TICKER_VALID = re.compile(r"^[A-Z]{4}\d{1,2}[A-Z]?$")

# Colunas numéricas — serão arredondadas para 2 casas decimais
NUMERIC_COLS = {"Preco_Fech", "RSI", "MACD", "Sinal_MACD", "Volume",
                "Media_20", "Media_50", "P_L", "EV_EBITDA", "Div_Yield", "ROE"}


# ─────────────────────────────────────────────────────────────────────────────
# Funções auxiliares
# ─────────────────────────────────────────────────────────────────────────────

def _remove_emojis(text: str) -> str:
    """Remove todos os emojis e símbolos Unicode não-ASCII de uma string."""
    return "".join(
        ch for ch in text
        if unicodedata.category(ch) not in ("So", "Cs")   # So = symbol-other, Cs = surrogate
        and ord(ch) < 0x1F600 or ord(ch) < 128
    ).strip()


def _sanitize_column_name(name: str) -> str:
    """
    Converte um nome de coluna bruto para formato canônico:
      'Preço Fech.' → 'preco fech.'  (minúscula, sem acento, sem emoji)
    O resultado é usado como chave no COLUMN_ALIASES.
    """
    # Remove emojis
    clean = _remove_emojis(str(name))
    # Remove acentos
    clean = unicodedata.normalize("NFKD", clean)
    clean = "".join(ch for ch in clean if not unicodedata.combining(ch))
    # Minúscula e remove espaços extras
    return clean.lower().strip()


def _normalize_column_names(df: pd.DataFrame) -> tuple[pd.DataFrame, dict]:
    """
    Renomeia colunas usando COLUMN_ALIASES.
    Retorna o DataFrame renomeado e um dict com o log das alterações.
    """
    changes = {}
    rename_map = {}

    for col in df.columns:
        sanitized = _sanitize_column_name(col)
        canonical = COLUMN_ALIASES.get(sanitized)
        if canonical and canonical != col:
            rename_map[col] = canonical
            changes[col] = canonical

    if rename_map:
        df = df.rename(columns=rename_map)

    return df, changes


def _clean_ticker(raw: str) -> str:
    """
    Limpa um ticker:
      'PETR4.SA' → 'PETR4'
      ' vale3 '  → 'VALE3'
      'PETR4F'   → 'PETR4F'  (fracionário, mantém)
    """
    ticker = str(raw).strip().upper()
    ticker = TICKER_SUFFIXES.sub("", ticker)
    return ticker


def _remove_string_emojis(series: pd.Series) -> pd.Series:
    """Aplica remoção de emojis em todos os valores de uma Series de texto."""
    return series.apply(lambda v: _remove_emojis(str(v)) if pd.notna(v) else v)


def _validate_tickers_mt5(tickers: list[str]) -> tuple[list[str], list[str]]:
    """
    Tenta verificar cada ticker no MT5.
    Retorna (validos, invalidos).
    Se o MT5 não estiver disponível, retorna todos como válidos com aviso.
    """
    try:
        import MetaTrader5 as mt5
        if not mt5.initialize():
            log.warning("MT5 não disponível para validação de tickers — pulando.")
            return tickers, []

        valid, invalid = [], []
        for t in tickers:
            if mt5.symbol_info(t) is not None:
                valid.append(t)
            else:
                invalid.append(t)

        mt5.shutdown()
        return valid, invalid

    except ImportError:
        log.warning("MetaTrader5 não instalado — validação de tickers ignorada.")
        return tickers, []


# ─────────────────────────────────────────────────────────────────────────────
# Função principal
# ─────────────────────────────────────────────────────────────────────────────

def normalize_csv(
    input_path: str,
    output_path: Optional[str] = None,
    validate_mt5: bool = False,
    round_decimals: int = 2,
) -> tuple[pd.DataFrame, dict]:
    """
    Normaliza um CSV screener para o padrão QUANT·IA.

    Parâmetros
    ----------
    input_path    : caminho do CSV original
    output_path   : onde salvar o CSV limpo (None = não salva, só retorna)
    validate_mt5  : se True, verifica cada ticker contra o MT5
    round_decimals: casas decimais para arredondar colunas numéricas

    Retorno
    -------
    df      : DataFrame normalizado
    report  : dicionário com diagnóstico completo das alterações
    """
    report: dict = {
        "input_file":       str(input_path),
        "output_file":      output_path,
        "total_rows":       0,
        "column_renames":   {},
        "tickers_cleaned":  [],
        "tickers_invalid":  [],
        "tickers_removed":  [],
        "emojis_removed_cols": [],
        "numeric_rounded":  [],
        "warnings":         [],
        "errors":           [],
    }

    # ── 1. Leitura ────────────────────────────────────────────────────────────
    path = Path(input_path)
    if not path.exists():
        msg = f"Arquivo não encontrado: {input_path}"
        log.error(msg)
        report["errors"].append(msg)
        return pd.DataFrame(), report

    try:
        # Tenta UTF-8 primeiro, cai para latin-1 se falhar (comum em exports Windows)
        try:
            df = pd.read_csv(path, encoding="utf-8")
        except UnicodeDecodeError:
            df = pd.read_csv(path, encoding="latin-1")
            report["warnings"].append("Arquivo lido com encoding latin-1 — salvar como UTF-8 é recomendado.")
    except Exception as e:
        msg = f"Falha ao ler CSV: {e}"
        log.error(msg)
        report["errors"].append(msg)
        return pd.DataFrame(), report

    report["total_rows"] = len(df)
    log.info(f"CSV carregado: {len(df)} linhas, {len(df.columns)} colunas.")

    # ── 2. Normalização dos nomes de colunas ──────────────────────────────────
    df, col_changes = _normalize_column_names(df)
    report["column_renames"] = col_changes
    if col_changes:
        log.info(f"Colunas renomeadas: {col_changes}")

    # ── 3. Verificação da coluna Ticker ──────────────────────────────────────
    if "Ticker" not in df.columns:
        msg = "Coluna 'Ticker' não encontrada após normalização. Verifique o CSV."
        log.error(msg)
        report["errors"].append(msg)
        return df, report

    # ── 4. Limpeza dos tickers ────────────────────────────────────────────────
    original_tickers = df["Ticker"].tolist()
    df["Ticker"] = df["Ticker"].apply(_clean_ticker)
    cleaned = [(o, n) for o, n in zip(original_tickers, df["Ticker"]) if o != n]
    report["tickers_cleaned"] = cleaned
    if cleaned:
        log.info(f"{len(cleaned)} ticker(s) limpos: {cleaned[:5]}{'...' if len(cleaned)>5 else ''}")

    # ── 5. Remoção de tickers claramente inválidos (formato errado) ───────────
    invalid_fmt = df[~df["Ticker"].apply(lambda t: bool(TICKER_VALID.match(t)))]["Ticker"].tolist()
    if invalid_fmt:
        report["warnings"].append(f"Tickers com formato não padrão B3: {invalid_fmt}")
        log.warning(f"Tickers com formato atípico (não removidos): {invalid_fmt}")

    # ── 6. Remoção de emojis nas colunas de texto ─────────────────────────────
    text_cols = df.select_dtypes(include="object").columns.tolist()
    text_cols = [c for c in text_cols if c != "Ticker"]
    for col in text_cols:
        original = df[col].copy()
        df[col] = _remove_string_emojis(df[col])
        if not df[col].equals(original):
            report["emojis_removed_cols"].append(col)
    if report["emojis_removed_cols"]:
        log.info(f"Emojis removidos nas colunas: {report['emojis_removed_cols']}")

    # ── 7. Arredondamento de colunas numéricas ────────────────────────────────
    for col in NUMERIC_COLS:
        if col in df.columns:
            try:
                df[col] = pd.to_numeric(df[col], errors="coerce").round(round_decimals)
                report["numeric_rounded"].append(col)
            except Exception as e:
                report["warnings"].append(f"Não foi possível arredondar coluna '{col}': {e}")

    # ── 8. Validação opcional no MT5 ─────────────────────────────────────────
    if validate_mt5:
        tickers = df["Ticker"].tolist()
        valid, invalid = _validate_tickers_mt5(tickers)
        report["tickers_invalid"] = invalid
        if invalid:
            log.warning(f"Tickers não encontrados no MT5: {invalid}")
            # Remove do DataFrame os tickers inválidos
            before = len(df)
            df = df[df["Ticker"].isin(valid)].reset_index(drop=True)
            removed = before - len(df)
            report["tickers_removed"] = invalid
            if removed:
                log.warning(f"{removed} ticker(s) removidos por não existirem no MT5.")

    # ── 9. Remoção de duplicatas de ticker ────────────────────────────────────
    dupes = df[df["Ticker"].duplicated()]["Ticker"].tolist()
    if dupes:
        df = df.drop_duplicates(subset="Ticker").reset_index(drop=True)
        report["warnings"].append(f"Tickers duplicados removidos: {dupes}")
        log.warning(f"Duplicatas removidas: {dupes}")

    # ── 10. Salvar CSV normalizado ────────────────────────────────────────────
    if output_path:
        out = Path(output_path)
        out.parent.mkdir(parents=True, exist_ok=True)
        df.to_csv(out, index=False, encoding="utf-8")
        log.info(f"✅ CSV normalizado salvo em: {out} ({len(df)} linhas)")
        report["output_file"] = str(out)

    return df, report


def print_report(report: dict) -> None:
    """Imprime o relatório de normalização de forma legível."""
    print("\n" + "═" * 56)
    print("  QUANT·IA — Relatório de Normalização do CSV")
    print("═" * 56)
    print(f"  Arquivo:      {report['input_file']}")
    print(f"  Linhas:       {report['total_rows']}")

    if report["column_renames"]:
        print(f"\n  Colunas renomeadas ({len(report['column_renames'])}):")
        for old, new in report["column_renames"].items():
            print(f"    '{old}'  →  '{new}'")

    if report["tickers_cleaned"]:
        print(f"\n  Tickers limpos ({len(report['tickers_cleaned'])}):")
        for old, new in report["tickers_cleaned"][:10]:
            print(f"    '{old}'  →  '{new}'")
        if len(report["tickers_cleaned"]) > 10:
            print(f"    ... e mais {len(report['tickers_cleaned'])-10}")

    if report["emojis_removed_cols"]:
        print(f"\n  Emojis removidos nas colunas: {report['emojis_removed_cols']}")

    if report["numeric_rounded"]:
        print(f"\n  Colunas arredondadas: {report['numeric_rounded']}")

    if report["tickers_invalid"]:
        print(f"\n  ⚠️  Tickers não encontrados no MT5: {report['tickers_invalid']}")

    if report["tickers_removed"]:
        print(f"\n  🗑️  Tickers removidos do CSV: {report['tickers_removed']}")

    if report["warnings"]:
        print(f"\n  ⚠️  Avisos:")
        for w in report["warnings"]:
            print(f"    - {w}")

    if report["errors"]:
        print(f"\n  ❌  Erros:")
        for e in report["errors"]:
            print(f"    - {e}")

    if report["output_file"]:
        print(f"\n  ✅  Salvo em: {report['output_file']}")

    print("═" * 56 + "\n")


# ─────────────────────────────────────────────────────────────────────────────
# Uso direto via linha de comando
# ─────────────────────────────────────────────────────────────────────────────
if __name__ == "__main__":
    import sys

    input_file  = sys.argv[1] if len(sys.argv) > 1 else "screener_resultados.csv"
    output_file = sys.argv[2] if len(sys.argv) > 2 else "screener_resultados.csv"
    mt5_check   = "--validate-mt5" in sys.argv

    logging.basicConfig(level=logging.INFO, format="%(levelname)s %(message)s")

    df, report = normalize_csv(
        input_path=input_file,
        output_path=output_file,
        validate_mt5=mt5_check,
    )

    print_report(report)

    if report["errors"]:
        sys.exit(1)
