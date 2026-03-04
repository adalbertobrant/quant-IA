@echo off
title QUANT-IA Launcher
color 0A

echo.
echo  ========================================
echo   QUANT-IA  --  B3 Terminal Launcher
echo  ========================================
echo.

REM ── Verifica se o .env existe ────────────────────────────────────────────────
if not exist ".env" (
    echo  [ERRO] Arquivo .env nao encontrado!
    echo  Crie o .env com suas credenciais antes de continuar.
    echo  Consulte o README.md para o formato correto.
    pause
    exit /b 1
)

REM ── Instala dependencias Python se necessario ─────────────────────────────────
echo  [1/3] Verificando dependencias Python...
pip show fastapi >nul 2>&1
if errorlevel 1 (
    echo  Instalando dependencias...
    pip install fastapi uvicorn python-dotenv google-generativeai pandas yfinance MetaTrader5 -q
)

REM ── Instala dependencias Node se necessario ───────────────────────────────────
echo  [2/3] Verificando dependencias Node.js...
if not exist "node_modules" (
    echo  Instalando pacotes npm...
    npm install react react-dom vite @vitejs/plugin-react --save-dev -q
)

REM ── Sobe a API FastAPI em nova janela ─────────────────────────────────────────
echo  [3/3] Iniciando servicos...
echo.
start "QUANT-IA :: API FastAPI ::" cmd /k "color 0B && echo  API rodando em http://localhost:8000 && echo  Docs em http://localhost:8000/docs && echo. && python api.py"

REM ── Aguarda API subir ────────────────────────────────────────────────────────
timeout /t 3 /nobreak >nul

REM ── Sobe o dashboard React em nova janela ─────────────────────────────────────
start "QUANT-IA :: Dashboard React ::" cmd /k "color 0E && echo  Dashboard rodando em http://localhost:5173 && echo. && npm run dev"

REM ── Abre o navegador apos 5 segundos ─────────────────────────────────────────
timeout /t 5 /nobreak >nul
start http://localhost:5173

echo.
echo  ========================================
echo   Servicos iniciados com sucesso!
echo.
echo   API:        http://localhost:8000
echo   Dashboard:  http://localhost:5173
echo   API Docs:   http://localhost:8000/docs
echo  ========================================
echo.
echo  Pressione qualquer tecla para fechar este launcher.
echo  (Os servicos continuam rodando nas outras janelas)
echo.
pause >nul
