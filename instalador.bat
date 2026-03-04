@echo off
setlocal EnableDelayedExpansion
chcp 65001 >nul 2>&1
title QUANT·IA — Instalador

:: ════════════════════════════════════════════════════════════════
::  QUANT·IA — Instalador Automático
::  Windows 10 / 11
::
::  O que este instalador faz:
::    1. Verifica requisitos do sistema (RAM, OS, arquitetura)
::    2. Instala Python 3.12 se não encontrado
::    3. Instala Node.js 20 LTS se não encontrado
::    4. Cria o ambiente virtual Python (.venv)
::    5. Instala todos os pacotes do requirements.txt
::    6. Instala dependências Node.js (npm install)
::    7. Cria a estrutura de pastas do projeto
::    8. Guia o usuário na criação do arquivo .env
::    9. Cria atalhos na Área de Trabalho
::   10. Testa a instalação e exibe relatório final
:: ════════════════════════════════════════════════════════════════

:: ── Cores ANSI (Windows 10 1511+) ────────────────────────────────
set "RESET=[0m"
set "BOLD=[1m"
set "RED=[91m"
set "GREEN=[92m"
set "YELLOW=[93m"
set "CYAN=[96m"
set "WHITE=[97m"
set "DIM=[2m"

:: ── Pastas temporárias ────────────────────────────────────────────
set "INSTALL_DIR=%~dp0"
set "INSTALL_DIR=%INSTALL_DIR:~0,-1%"
set "LOG_FILE=%INSTALL_DIR%\instalacao.log"
set "PYTHON_INSTALLER=%TEMP%\python_installer.exe"
set "NODE_INSTALLER=%TEMP%\node_installer.msi"

:: ── Versões alvo ──────────────────────────────────────────────────
set "PYTHON_URL=https://www.python.org/ftp/python/3.12.3/python-3.12.3-amd64.exe"
set "NODE_URL=https://nodejs.org/dist/v20.12.2/node-v20.12.2-x64.msi"
set "PYTHON_MIN_VER=3.10"

:: ── Inicia o log ─────────────────────────────────────────────────
echo [%date% %time%] Instalador QUANT·IA iniciado > "%LOG_FILE%"

:: ════════════════════════════════════════════════════════════════
call :tela_boas_vindas
call :verificar_admin
call :verificar_sistema
call :verificar_python
call :verificar_nodejs
call :criar_estrutura_pastas
call :criar_venv
call :instalar_python_deps
call :instalar_node_deps
call :configurar_env
call :criar_atalhos
call :teste_final
call :tela_conclusao
goto :eof


:: ════════════════════════════════════════════════════════════════
:tela_boas_vindas
cls
echo.
echo %CYAN%%BOLD%  ██████╗ ██╗   ██╗ █████╗ ███╗   ██╗████████╗    ██╗ █████╗ %RESET%
echo %CYAN%%BOLD%  ██╔═══██╗██║   ██║██╔══██╗████╗  ██║╚══██╔══╝    ██║██╔══██╗%RESET%
echo %CYAN%%BOLD%  ██║   ██║██║   ██║███████║██╔██╗ ██║   ██║       ██║███████║%RESET%
echo %CYAN%%BOLD%  ██║▄▄ ██║██║   ██║██╔══██║██║╚██╗██║   ██║  ██   ██║██╔══██║%RESET%
echo %CYAN%%BOLD%  ╚██████╔╝╚██████╔╝██║  ██║██║ ╚████║   ██║  ╚█████╔╝██║  ██║%RESET%
echo %CYAN%%BOLD%   ╚══▀▀═╝  ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚════╝ ╚═╝  ╚═╝%RESET%
echo.
echo %WHITE%         Instalador Automático — B3 Terminal v1.0%RESET%
echo %DIM%         Robô de Trading com IA · BTG Pactual · Toro%RESET%
echo.
echo %DIM%  ════════════════════════════════════════════════════════%RESET%
echo.
echo  Este instalador irá configurar tudo automaticamente:
echo.
echo  %GREEN%✓%RESET%  Python 3.12 e ambiente virtual isolado
echo  %GREEN%✓%RESET%  Node.js 20 LTS e dependências do dashboard
echo  %GREEN%✓%RESET%  Todos os pacotes Python necessários
echo  %GREEN%✓%RESET%  Estrutura de pastas do projeto
echo  %GREEN%✓%RESET%  Formulário guiado para suas credenciais
echo  %GREEN%✓%RESET%  Atalhos na Área de Trabalho
echo.
echo %YELLOW%  Tempo estimado: 5 a 15 minutos%RESET%
echo %YELLOW%  Requer conexão com a internet%RESET%
echo.
echo %DIM%  ════════════════════════════════════════════════════════%RESET%
echo.
set /p "CONTINUAR=  Pressione ENTER para começar ou Ctrl+C para cancelar..."
echo.
goto :eof


:: ════════════════════════════════════════════════════════════════
:verificar_admin
echo %CYAN%[1/10]%RESET% Verificando permissões de administrador...
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo.
    echo %YELLOW%  ⚠  Este instalador não está rodando como Administrador.%RESET%
    echo %YELLOW%     Algumas etapas podem falhar (instalação de Python/Node).%RESET%
    echo.
    echo  Para rodar como Administrador:
    echo  1. Feche esta janela
    echo  2. Clique com o botão DIREITO no instalador.bat
    echo  3. Selecione "Executar como administrador"
    echo.
    set /p "IGNORAR=  Continuar mesmo assim? (S/N): "
    if /i "!IGNORAR!" neq "S" (
        echo  Instalação cancelada.
        pause
        exit /b 1
    )
) else (
    echo  %GREEN%✓%RESET%  Rodando como Administrador.
)
echo [%date% %time%] Admin: verificado >> "%LOG_FILE%"
goto :eof


:: ════════════════════════════════════════════════════════════════
:verificar_sistema
echo.
echo %CYAN%[2/10]%RESET% Verificando compatibilidade do sistema...

:: Versão do Windows
for /f "tokens=4-5 delims=. " %%i in ('ver') do set WIN_VER=%%i.%%j
echo %DIM%        Windows versão: %WIN_VER%%RESET%

:: Arquitetura
if "%PROCESSOR_ARCHITECTURE%"=="AMD64" (
    echo  %GREEN%✓%RESET%  Arquitetura: 64-bit (AMD64/x86_64)
) else if "%PROCESSOR_ARCHITEW6432%"=="AMD64" (
    echo  %GREEN%✓%RESET%  Arquitetura: 64-bit (WOW64)
) else (
    echo  %RED%✗%RESET%  Arquitetura 32-bit não suportada. Use Windows 64-bit.
    pause
    exit /b 1
)

:: RAM disponível (em MB)
for /f "skip=1 tokens=2" %%m in ('wmic computersystem get TotalPhysicalMemory') do (
    set "RAM_BYTES=%%m"
    goto :ram_ok
)
:ram_ok
set /a RAM_MB=!RAM_BYTES:~0,-6!
echo %DIM%        RAM total: ~%RAM_MB% MB%RESET%

if !RAM_MB! lss 3500 (
    echo  %RED%✗%RESET%  RAM insuficiente: !RAM_MB! MB detectados. Mínimo recomendado: 4 GB.
    echo  %YELLOW%     O sistema pode funcionar, mas será lento durante o pregão.%RESET%
    echo.
    set /p "IGNORAR_RAM=  Continuar mesmo assim? (S/N): "
    if /i "!IGNORAR_RAM!" neq "S" exit /b 1
) else (
    echo  %GREEN%✓%RESET%  RAM: !RAM_MB! MB disponíveis.
)

:: Espaço em disco (na unidade do projeto)
for /f "tokens=3" %%s in ('dir /-c "%INSTALL_DIR%" 2^>nul ^| find "bytes livres"') do set DISCO_FREE=%%s
echo  %GREEN%✓%RESET%  Verificação do sistema concluída.
echo [%date% %time%] Sistema: OK, RAM=%RAM_MB%MB >> "%LOG_FILE%"
goto :eof


:: ════════════════════════════════════════════════════════════════
:verificar_python
echo.
echo %CYAN%[3/10]%RESET% Verificando Python...

python --version >nul 2>&1
if %errorlevel% neq 0 goto :instalar_python

:: Verifica versão mínima
for /f "tokens=2 delims= " %%v in ('python --version 2^>^&1') do set PY_VER=%%v
for /f "tokens=1,2 delims=." %%a in ("%PY_VER%") do (
    set PY_MAJOR=%%a
    set PY_MINOR=%%b
)

if !PY_MAJOR! lss 3 goto :instalar_python
if !PY_MAJOR! equ 3 if !PY_MINOR! lss 10 goto :instalar_python

echo  %GREEN%✓%RESET%  Python %PY_VER% encontrado em:
for /f %%p in ('where python') do echo %DIM%         %%p%RESET%
echo [%date% %time%] Python: %PY_VER% ja instalado >> "%LOG_FILE%"
goto :eof

:instalar_python
echo  %YELLOW%⚠%RESET%  Python não encontrado ou versão antiga. Instalando Python 3.12...
echo.
echo  Baixando Python 3.12.3 (~25 MB)...
echo %DIM%  Origem: python.org%RESET%
echo.

:: Tenta com PowerShell (mais confiável que curl no Windows)
powershell -Command "& { $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%PYTHON_URL%' -OutFile '%PYTHON_INSTALLER%' }" 2>>"%LOG_FILE%"

if not exist "%PYTHON_INSTALLER%" (
    echo  %RED%✗%RESET%  Falha no download do Python. Verifique sua conexão.
    echo  %YELLOW%     Baixe manualmente em: https://python.org/downloads%RESET%
    echo  %YELLOW%     Marque "Add Python to PATH" e execute este instalador novamente.%RESET%
    pause
    exit /b 1
)

echo  Instalando Python 3.12 (aguarde)...
"%PYTHON_INSTALLER%" /quiet InstallAllUsers=1 PrependPath=1 Include_test=0 Include_doc=0
if %errorlevel% neq 0 (
    echo  %RED%✗%RESET%  Falha na instalação do Python.
    echo  %YELLOW%     Tente instalar manualmente em python.org%RESET%
    pause
    exit /b 1
)

del "%PYTHON_INSTALLER%" >nul 2>&1

:: Recarrega o PATH
call :recarregar_path

python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo  %RED%✗%RESET%  Python instalado mas não encontrado no PATH.
    echo  %YELLOW%     Feche e reabra este instalador.%RESET%
    pause
    exit /b 1
)

echo  %GREEN%✓%RESET%  Python 3.12 instalado com sucesso!
echo [%date% %time%] Python: instalado >> "%LOG_FILE%"
goto :eof


:: ════════════════════════════════════════════════════════════════
:verificar_nodejs
echo.
echo %CYAN%[4/10]%RESET% Verificando Node.js...

node --version >nul 2>&1
if %errorlevel% neq 0 goto :instalar_nodejs

for /f %%v in ('node --version') do set NODE_VER=%%v
for /f "tokens=1 delims=." %%n in ("%NODE_VER:v=%") do set NODE_MAJOR=%%n

if !NODE_MAJOR! lss 18 goto :instalar_nodejs

echo  %GREEN%✓%RESET%  Node.js %NODE_VER% encontrado.
echo [%date% %time%] Node: %NODE_VER% ja instalado >> "%LOG_FILE%"
goto :eof

:instalar_nodejs
echo  %YELLOW%⚠%RESET%  Node.js não encontrado ou versão antiga. Instalando Node.js 20 LTS...
echo.
echo  Baixando Node.js 20 LTS (~30 MB)...

powershell -Command "& { $ProgressPreference='SilentlyContinue'; Invoke-WebRequest -Uri '%NODE_URL%' -OutFile '%NODE_INSTALLER%' }" 2>>"%LOG_FILE%"

if not exist "%NODE_INSTALLER%" (
    echo  %RED%✗%RESET%  Falha no download do Node.js.
    echo  %YELLOW%     Baixe manualmente em: https://nodejs.org%RESET%
    pause
    exit /b 1
)

echo  Instalando Node.js 20 LTS (aguarde)...
msiexec /i "%NODE_INSTALLER%" /quiet /norestart
if %errorlevel% neq 0 (
    echo  %RED%✗%RESET%  Falha na instalação do Node.js.
    pause
    exit /b 1
)

del "%NODE_INSTALLER%" >nul 2>&1
call :recarregar_path

echo  %GREEN%✓%RESET%  Node.js 20 instalado com sucesso!
echo [%date% %time%] Node: instalado >> "%LOG_FILE%"
goto :eof


:: ════════════════════════════════════════════════════════════════
:criar_estrutura_pastas
echo.
echo %CYAN%[5/10]%RESET% Criando estrutura de pastas...

:: Pastas do projeto
if not exist "%INSTALL_DIR%\utils"       mkdir "%INSTALL_DIR%\utils"
if not exist "%INSTALL_DIR%\src"         mkdir "%INSTALL_DIR%\src"
if not exist "%INSTALL_DIR%\logs"        mkdir "%INSTALL_DIR%\logs"
if not exist "%INSTALL_DIR%\docker"      mkdir "%INSTALL_DIR%\docker"

:: __init__.py do utils
if not exist "%INSTALL_DIR%\utils\__init__.py" (
    echo. > "%INSTALL_DIR%\utils\__init__.py"
)

:: Move utils.py se estiver na raiz
if exist "%INSTALL_DIR%\utils.py" (
    if not exist "%INSTALL_DIR%\utils\utils.py" (
        move "%INSTALL_DIR%\utils.py" "%INSTALL_DIR%\utils\utils.py" >nul
        echo  %GREEN%✓%RESET%  utils.py movido para utils\utils.py
    )
)

:: Move o dashboard para src\ se necessário
if exist "%INSTALL_DIR%\trading_dashboard_v2.jsx" (
    if not exist "%INSTALL_DIR%\src\App.jsx" (
        copy "%INSTALL_DIR%\trading_dashboard_v2.jsx" "%INSTALL_DIR%\src\App.jsx" >nul
        echo  %GREEN%✓%RESET%  Dashboard movido para src\App.jsx
    )
)

echo  %GREEN%✓%RESET%  Estrutura de pastas criada.
echo [%date% %time%] Pastas: criadas >> "%LOG_FILE%"
goto :eof


:: ════════════════════════════════════════════════════════════════
:criar_venv
echo.
echo %CYAN%[6/10]%RESET% Criando ambiente virtual Python (.venv)...

if exist "%INSTALL_DIR%\.venv\Scripts\python.exe" (
    echo  %GREEN%✓%RESET%  Ambiente virtual já existe. Pulando criação.
    goto :eof
)

cd /d "%INSTALL_DIR%"
python -m venv .venv 2>>"%LOG_FILE%"

if not exist "%INSTALL_DIR%\.venv\Scripts\python.exe" (
    echo  %RED%✗%RESET%  Falha ao criar o ambiente virtual.
    echo  Verifique o log: %LOG_FILE%
    pause
    exit /b 1
)

echo  %GREEN%✓%RESET%  Ambiente virtual criado em .venv\
echo [%date% %time%] venv: criado >> "%LOG_FILE%"
goto :eof


:: ════════════════════════════════════════════════════════════════
:instalar_python_deps
echo.
echo %CYAN%[7/10]%RESET% Instalando pacotes Python...
echo %DIM%        Isso pode levar de 2 a 8 minutos dependendo da internet.%RESET%
echo.

set "PIP=%INSTALL_DIR%\.venv\Scripts\pip.exe"
set "PYTHON_VENV=%INSTALL_DIR%\.venv\Scripts\python.exe"

:: Atualiza pip silenciosamente
echo  Atualizando pip...
"%PYTHON_VENV%" -m pip install --upgrade pip --quiet 2>>"%LOG_FILE%"

if not exist "%INSTALL_DIR%\requirements.txt" (
    echo  %YELLOW%⚠%RESET%  requirements.txt não encontrado. Criando com os pacotes padrão...

    (
        echo fastapi^>=0.110.0
        echo uvicorn^>=0.29.0
        echo pydantic^>=2.0.0
        echo google-generativeai^>=0.7.0
        echo pandas^>=2.0.0
        echo yfinance^>=0.2.40
        echo requests^>=2.31.0
        echo MetaTrader5^>=5.0.45
        echo python-dotenv^>=1.0.0
    ) > "%INSTALL_DIR%\requirements.txt"
)

:: Instala com barra de progresso visível
echo  Instalando pacotes (acompanhe o progresso abaixo):
echo.
"%PIP%" install -r "%INSTALL_DIR%\requirements.txt" 2>>"%LOG_FILE%"

if %errorlevel% neq 0 (
    echo.
    echo  %RED%✗%RESET%  Erro ao instalar alguns pacotes.
    echo  %YELLOW%     Verifique o log em: %LOG_FILE%%RESET%
    echo.
    echo  Tentando instalar pacote por pacote...
    for /f "eol=# tokens=1 delims=>= " %%p in ("%INSTALL_DIR%\requirements.txt") do (
        echo  Instalando %%p...
        "%PIP%" install "%%p" --quiet 2>>"%LOG_FILE%"
    )
)

:: Verifica os pacotes críticos
echo.
set DEPS_OK=1
for %%p in (fastapi uvicorn pandas dotenv google.generativeai) do (
    "%PYTHON_VENV%" -c "import %%p" >nul 2>&1
    if !errorlevel! equ 0 (
        echo  %GREEN%✓%RESET%  %%p
    ) else (
        echo  %RED%✗%RESET%  %%p — falhou
        set DEPS_OK=0
    )
)

:: MetaTrader5 só instala no Windows (verificação separada)
"%PYTHON_VENV%" -c "import MetaTrader5" >nul 2>&1
if %errorlevel% equ 0 (
    echo  %GREEN%✓%RESET%  MetaTrader5
) else (
    echo  %YELLOW%⚠%RESET%  MetaTrader5 — não instalado (requer MT5 da corretora instalado primeiro^)
)

echo [%date% %time%] Python deps: instaladas >> "%LOG_FILE%"
goto :eof


:: ════════════════════════════════════════════════════════════════
:instalar_node_deps
echo.
echo %CYAN%[8/10]%RESET% Instalando dependências do Dashboard (npm)...

if not exist "%INSTALL_DIR%\package.json" (
    echo  %YELLOW%⚠%RESET%  package.json não encontrado. Criando configuração padrão...
    (
        echo {
        echo   "name": "quant-ia-dashboard",
        echo   "version": "1.0.0",
        echo   "private": true,
        echo   "scripts": {
        echo     "dev": "vite --port 5173",
        echo     "build": "vite build",
        echo     "preview": "vite preview"
        echo   },
        echo   "dependencies": {
        echo     "react": "^18.2.0",
        echo     "react-dom": "^18.2.0"
        echo   },
        echo   "devDependencies": {
        echo     "@vitejs/plugin-react": "^4.2.0",
        echo     "vite": "^5.0.0"
        echo   }
        echo }
    ) > "%INSTALL_DIR%\package.json"
)

cd /d "%INSTALL_DIR%"
echo  Baixando pacotes Node.js...
npm install --silent 2>>"%LOG_FILE%"

if %errorlevel% neq 0 (
    echo  %RED%✗%RESET%  Erro no npm install. Verifique o log.
) else (
    echo  %GREEN%✓%RESET%  Dependências Node.js instaladas.
)

echo [%date% %time%] npm: instalado >> "%LOG_FILE%"
goto :eof


:: ════════════════════════════════════════════════════════════════
:configurar_env
echo.
echo %CYAN%[9/10]%RESET% Configurando credenciais (.env)...
echo.

if exist "%INSTALL_DIR%\.env" (
    echo  %YELLOW%⚠%RESET%  Arquivo .env já existe.
    set /p "RECONF=  Deseja reconfigurar as credenciais? (S/N): "
    if /i "!RECONF!" neq "S" (
        echo  %GREEN%✓%RESET%  Credenciais mantidas.
        goto :eof
    )
    copy "%INSTALL_DIR%\.env" "%INSTALL_DIR%\.env.backup" >nul
    echo  %DIM%  Backup salvo em .env.backup%RESET%
)

cls
echo.
echo %CYAN%%BOLD%  ════════════════════════════════════════════════════════%RESET%
echo %CYAN%%BOLD%   Configuração das Credenciais%RESET%
echo %CYAN%%BOLD%  ════════════════════════════════════════════════════════%RESET%
echo.
echo  Preencha os dados abaixo. Eles serão salvos de forma segura
echo  no arquivo .env que %RED%NUNCA%RESET% deve ser compartilhado.
echo.
echo %DIM%  Dica: Para encontrar seus dados do MT5, abra o MetaTrader 5,%RESET%
echo %DIM%  clique em Ver → Terminal e veja a aba "Conta".%RESET%
echo.

:: ── Corretora ──────────────────────────────────────────────────
echo %YELLOW%  ┌─ CORRETORA ─────────────────────────────────────────┐%RESET%
echo.
echo  Qual é a sua corretora?
echo.
echo    1. BTG Pactual
echo    2. Toro Investimentos
echo.
set /p "BROKER_CHOICE=  Digite 1 ou 2: "

if "%BROKER_CHOICE%"=="1" (
    set "BROKER_NAME=BTG"
    set "MT5_SERVER=BTGPactual-PRD"
    echo  %GREEN%✓%RESET%  BTG Pactual selecionado.
) else if "%BROKER_CHOICE%"=="2" (
    set "BROKER_NAME=TORO"
    set "MT5_SERVER=ToroInvestimentos-PRD"
    echo  %GREEN%✓%RESET%  Toro Investimentos selecionado.
) else (
    echo  %YELLOW%⚠%RESET%  Opção inválida. Usando BTG como padrão.
    set "BROKER_NAME=BTG"
    set "MT5_SERVER=BTGPactual-PRD"
)

echo.
echo %YELLOW%  ┌─ CONTA METATRADER 5 ────────────────────────────────┐%RESET%
echo.
echo  %DIM%  Como encontrar: Abra o MT5 → Ver → Terminal → aba "Conta"%RESET%
echo  %DIM%  O número exibido em destaque é o seu login.%RESET%
echo.
set /p "MT5_LOGIN=  Número da sua conta MT5 (só números, ex: 12345678): "
echo.

echo  %DIM%  ATENÇÃO: Esta é a SENHA DE NEGOCIAÇÃO, diferente da senha%RESET%
echo  %DIM%  do aplicativo da corretora. Se não souber, contate o suporte.%RESET%
echo.
set /p "MT5_PASSWORD=  Senha de negociação MT5: "
echo.

echo %YELLOW%  ┌─ SERVIDOR DA CORRETORA ─────────────────────────────┐%RESET%
echo.
echo  Servidor detectado automaticamente: %CYAN%%MT5_SERVER%%RESET%
echo.
echo  Se estiver incorreto, você pode alterar agora.
echo  (Para confirmar o correto: MT5 → Arquivo → Abrir Conta → pesquise sua corretora)
echo.
set /p "MT5_SERVER_CONFIRM=  Servidor (ENTER para usar %MT5_SERVER%): "
if not "!MT5_SERVER_CONFIRM!"=="" set "MT5_SERVER=!MT5_SERVER_CONFIRM!"

echo.
echo %YELLOW%  ┌─ CHAVE DO GOOGLE AI ────────────────────────────────┐%RESET%
echo.
echo  %DIM%  Como obter (gratuito):%RESET%
echo  %DIM%  1. Acesse: https://aistudio.google.com%RESET%
echo  %DIM%  2. Clique em "Get API key" → "Create API key"%RESET%
echo  %DIM%  3. Copie a chave que começa com AIzaSy...%RESET%
echo.
set /p "GOOGLE_API_KEY=  Cole sua chave do Google AI: "
echo.

echo %YELLOW%  ┌─ PARÂMETROS DE RISCO ───────────────────────────────┐%RESET%
echo.
echo  %DIM%  Estes valores protegem seu capital. Podem ser ajustados%RESET%
echo  %DIM%  depois pelo Dashboard sem precisar reinstalar.%RESET%
echo.
echo  Perda máxima por dia em R$ (padrão: 500):
set /p "MAX_LOSS=  R$ "
if "!MAX_LOSS!"=="" set "MAX_LOSS=500.0"

echo.
echo  Máximo de ordens por dia (padrão: 10):
set /p "MAX_ORDENS=  "
if "!MAX_ORDENS!"=="" set "MAX_ORDENS=10"

echo.
echo  Lote máximo por ordem em ações (padrão: 500):
set /p "MAX_LOTE=  "
if "!MAX_LOTE!"=="" set "MAX_LOTE=500"

echo.
echo %YELLOW%  ┌─ MODO DE OPERAÇÃO ──────────────────────────────────┐%RESET%
echo.
echo  %GREEN%  RECOMENDADO:%RESET% Começar em modo SIMULAÇÃO (DRY RUN).
echo  Você poderá mudar para REAL depois pelo Dashboard.
echo.
echo    1. Modo SIMULAÇÃO - não envia ordens reais (recomendado)
echo    2. Modo REAL      - envia ordens para a B3
echo.
set /p "DRY_RUN_CHOICE=  Digite 1 ou 2 (padrão: 1): "
if "%DRY_RUN_CHOICE%"=="2" (
    set "DRY_RUN=false"
    echo  %RED%⚠%RESET%  Modo REAL selecionado. Ordens serão enviadas para a B3.
) else (
    set "DRY_RUN=true"
    echo  %GREEN%✓%RESET%  Modo SIMULAÇÃO selecionado.
)

:: ── Grava o .env ─────────────────────────────────────────────
echo.
echo  Salvando credenciais...

(
    echo # ════════════════════════════════════════════
    echo # QUANT·IA — Credenciais e Configurações
    echo # Gerado pelo instalador em %date% %time%
    echo # NÃO COMPARTILHE ESTE ARQUIVO
    echo # ════════════════════════════════════════════
    echo.
    echo # Corretora
    echo BROKER_NAME=%BROKER_NAME%
    echo MT5_LOGIN=%MT5_LOGIN%
    echo MT5_PASSWORD=%MT5_PASSWORD%
    echo MT5_SERVER=%MT5_SERVER%
    echo.
    echo # Inteligência Artificial
    echo GOOGLE_API_KEY=%GOOGLE_API_KEY%
    echo.
    echo # Parâmetros de Risco
    echo MAX_LOSS_DIARIA=%MAX_LOSS%
    echo MAX_ORDENS_DIA=%MAX_ORDENS%
    echo MAX_LOTE_ORDEM=%MAX_LOTE%
    echo MIN_RR_RATIO=1.5
    echo MAX_RISCO_PCT=2.0
    echo.
    echo # Modo de Operação
    echo DRY_RUN=%DRY_RUN%
) > "%INSTALL_DIR%\.env"

echo  %GREEN%✓%RESET%  Credenciais salvas em .env

:: Protege o arquivo (somente leitura para outros usuários)
attrib +r "%INSTALL_DIR%\.env" >nul 2>&1

echo [%date% %time%] .env: criado >> "%LOG_FILE%"
goto :eof


:: ════════════════════════════════════════════════════════════════
:criar_atalhos
echo.
echo %CYAN%[10/10]%RESET% Criando atalhos na Área de Trabalho...

set "DESKTOP=%USERPROFILE%\Desktop"
set "VENV_PYTHON=%INSTALL_DIR%\.venv\Scripts\python.exe"

:: ── Atalho 1: Iniciar QUANT·IA (start.bat) ───────────────────
set "SHORTCUT_START=%DESKTOP%\QUANT-IA Iniciar.lnk"
powershell -Command "& {
    $s = (New-Object -COM WScript.Shell).CreateShortcut('%SHORTCUT_START%');
    $s.TargetPath = '%INSTALL_DIR%\start.bat';
    $s.WorkingDirectory = '%INSTALL_DIR%';
    $s.Description = 'Iniciar QUANT-IA (API + Dashboard)';
    $s.IconLocation = '%SystemRoot%\System32\shell32.dll,23';
    $s.Save()
}" 2>>"%LOG_FILE%"

:: ── Atalho 2: Apenas API ─────────────────────────────────────
set "SHORTCUT_API=%DESKTOP%\QUANT-IA API.lnk"
powershell -Command "& {
    $s = (New-Object -COM WScript.Shell).CreateShortcut('%SHORTCUT_API%');
    $s.TargetPath = 'cmd.exe';
    $s.Arguments = '/k \"cd /d %INSTALL_DIR% && .venv\Scripts\activate.bat && python api.py\"';
    $s.WorkingDirectory = '%INSTALL_DIR%';
    $s.Description = 'QUANT-IA - API FastAPI';
    $s.IconLocation = '%SystemRoot%\System32\shell32.dll,13';
    $s.Save()
}" 2>>"%LOG_FILE%"

:: ── Atalho 3: Dashboard ───────────────────────────────────────
set "SHORTCUT_DASH=%DESKTOP%\QUANT-IA Dashboard.lnk"
powershell -Command "& {
    $s = (New-Object -COM WScript.Shell).CreateShortcut('%SHORTCUT_DASH%');
    $s.TargetPath = 'cmd.exe';
    $s.Arguments = '/k \"cd /d %INSTALL_DIR% && npm run dev\"';
    $s.WorkingDirectory = '%INSTALL_DIR%';
    $s.Description = 'QUANT-IA - Dashboard React';
    $s.IconLocation = '%SystemRoot%\System32\shell32.dll,14';
    $s.Save()
}" 2>>"%LOG_FILE%"

:: ── Atalho 4: Normalizar CSV ──────────────────────────────────
set "SHORTCUT_CSV=%DESKTOP%\QUANT-IA Normalizar CSV.lnk"
powershell -Command "& {
    $s = (New-Object -COM WScript.Shell).CreateShortcut('%SHORTCUT_CSV%');
    $s.TargetPath = 'cmd.exe';
    $s.Arguments = '/k \"cd /d %INSTALL_DIR% && .venv\Scripts\activate.bat && python utils\utils.py screener_bruto.csv screener_resultados.csv && echo. && echo CSV normalizado! && pause\"';
    $s.WorkingDirectory = '%INSTALL_DIR%';
    $s.Description = 'Normalizar CSV do screener';
    $s.IconLocation = '%SystemRoot%\System32\shell32.dll,1';
    $s.Save()
}" 2>>"%LOG_FILE%"

:: ── Atalho 5: Abrir Dashboard no navegador ────────────────────
set "SHORTCUT_BROWSER=%DESKTOP%\QUANT-IA Abrir no Navegador.lnk"
powershell -Command "& {
    $s = (New-Object -COM WScript.Shell).CreateShortcut('%SHORTCUT_BROWSER%');
    $s.TargetPath = 'http://localhost:5173';
    $s.Description = 'Abrir QUANT-IA no navegador';
    $s.IconLocation = '%SystemRoot%\System32\shell32.dll,220';
    $s.Save()
}" 2>>"%LOG_FILE%"

echo  %GREEN%✓%RESET%  5 atalhos criados na Área de Trabalho:
echo  %DIM%    • QUANT-IA Iniciar (abre tudo de uma vez)%RESET%
echo  %DIM%    • QUANT-IA API%RESET%
echo  %DIM%    • QUANT-IA Dashboard%RESET%
echo  %DIM%    • QUANT-IA Normalizar CSV%RESET%
echo  %DIM%    • QUANT-IA Abrir no Navegador%RESET%
echo [%date% %time%] Atalhos: criados >> "%LOG_FILE%"
goto :eof


:: ════════════════════════════════════════════════════════════════
:teste_final
echo.
echo %DIM%  ════════════════════════════════════════════════════════%RESET%
echo %BOLD%  Executando testes de verificação...%RESET%
echo %DIM%  ════════════════════════════════════════════════════════%RESET%
echo.

set "VENV_PY=%INSTALL_DIR%\.venv\Scripts\python.exe"
set TESTS_OK=0
set TESTS_TOTAL=0

:: Teste 1 — Python no venv
set /a TESTS_TOTAL+=1
"%VENV_PY%" --version >nul 2>&1
if %errorlevel% equ 0 (
    for /f "tokens=2" %%v in ('"%VENV_PY%" --version 2^>^&1') do set PY_V=%%v
    echo  %GREEN%✓%RESET%  Python !PY_V! no ambiente virtual
    set /a TESTS_OK+=1
) else (
    echo  %RED%✗%RESET%  Python no ambiente virtual — falhou
)

:: Teste 2 — Pacotes críticos
set /a TESTS_TOTAL+=1
"%VENV_PY%" -c "import fastapi, pandas, google.generativeai, dotenv" >nul 2>&1
if %errorlevel% equ 0 (
    echo  %GREEN%✓%RESET%  Pacotes Python principais instalados
    set /a TESTS_OK+=1
) else (
    echo  %RED%✗%RESET%  Pacotes Python — verifique o log
)

:: Teste 3 — MetaTrader5
set /a TESTS_TOTAL+=1
"%VENV_PY%" -c "import MetaTrader5" >nul 2>&1
if %errorlevel% equ 0 (
    echo  %GREEN%✓%RESET%  MetaTrader5 instalado
    set /a TESTS_OK+=1
) else (
    echo  %YELLOW%⚠%RESET%  MetaTrader5 não encontrado
    echo  %DIM%     Instale o MT5 da sua corretora e execute:%RESET%
    echo  %DIM%     .venv\Scripts\pip install MetaTrader5%RESET%
)

:: Teste 4 — Node.js
set /a TESTS_TOTAL+=1
node --version >nul 2>&1
if %errorlevel% equ 0 (
    for /f %%v in ('node --version') do echo  %GREEN%✓%RESET%  Node.js %%v
    set /a TESTS_OK+=1
) else (
    echo  %RED%✗%RESET%  Node.js — não encontrado
)

:: Teste 5 — node_modules
set /a TESTS_TOTAL+=1
if exist "%INSTALL_DIR%\node_modules\vite" (
    echo  %GREEN%✓%RESET%  Dependências Node.js instaladas
    set /a TESTS_OK+=1
) else (
    echo  %RED%✗%RESET%  node_modules — execute: npm install
)

:: Teste 6 — .env
set /a TESTS_TOTAL+=1
if exist "%INSTALL_DIR%\.env" (
    echo  %GREEN%✓%RESET%  Arquivo .env criado
    set /a TESTS_OK+=1
) else (
    echo  %RED%✗%RESET%  .env não encontrado
)

:: Teste 7 — utils\
set /a TESTS_TOTAL+=1
if exist "%INSTALL_DIR%\utils\utils.py" (
    echo  %GREEN%✓%RESET%  Módulo utils\ configurado
    set /a TESTS_OK+=1
) else (
    echo  %YELLOW%⚠%RESET%  utils\utils.py não encontrado (copie o arquivo)
)

:: Teste 8 — Chave do Google AI
set /a TESTS_TOTAL+=1
"%VENV_PY%" -c "
import os
from dotenv import load_dotenv
load_dotenv()
key = os.getenv('GOOGLE_API_KEY', '')
if key and key.startswith('AIza') and len(key) > 20:
    print('OK')
else:
    print('FALHA')
" 2>nul | find "OK" >nul 2>&1
if %errorlevel% equ 0 (
    echo  %GREEN%✓%RESET%  Chave do Google AI configurada
    set /a TESTS_OK+=1
) else (
    echo  %YELLOW%⚠%RESET%  Chave do Google AI parece inválida — verifique o .env
)

echo.
echo %DIM%  ────────────────────────────────────────────────────────%RESET%
echo  Resultado: %GREEN%!TESTS_OK!%RESET% de %TESTS_TOTAL% testes passaram
echo [%date% %time%] Testes: %TESTS_OK%/%TESTS_TOTAL% >> "%LOG_FILE%"
goto :eof


:: ════════════════════════════════════════════════════════════════
:tela_conclusao
echo.
echo %DIM%  ════════════════════════════════════════════════════════%RESET%
echo.

if !TESTS_OK! geq 6 (
    echo  %GREEN%%BOLD%  ✅  INSTALAÇÃO CONCLUÍDA COM SUCESSO!%RESET%
) else (
    echo  %YELLOW%%BOLD%  ⚠   INSTALAÇÃO CONCLUÍDA COM AVISOS%RESET%
    echo  %YELLOW%      Verifique os itens marcados com ✗ ou ⚠ acima.%RESET%
)

echo.
echo %DIM%  ════════════════════════════════════════════════════════%RESET%
echo.
echo %BOLD%  PRÓXIMOS PASSOS:%RESET%
echo.
echo  %CYAN%1.%RESET%  Instale o MetaTrader 5 da sua corretora
echo      %DIM%BTG:  portal.btgpactual.com → Plataformas%RESET%
echo      %DIM%Toro: app.toroinvestimentos.com.br → MT5%RESET%
echo.
echo  %CYAN%2.%RESET%  Abra o MT5, faça login e ative o "Algo Trading"
echo      %DIM%(botão verde na barra de ferramentas do MT5)%RESET%
echo.
echo  %CYAN%3.%RESET%  Instale o pacote MetaTrader5 após instalar o MT5:
echo      %DIM%.venv\Scripts\pip install MetaTrader5%RESET%
echo.
echo  %CYAN%4.%RESET%  Prepare seu CSV do screener
echo      %DIM%Trademap, Status Invest ou python gerar_screener.py%RESET%
echo.
echo  %CYAN%5.%RESET%  Dê duplo clique em: %GREEN%QUANT-IA Iniciar%RESET% na Área de Trabalho
echo.
echo %DIM%  ════════════════════════════════════════════════════════%RESET%
echo.
echo  %DIM%  Log completo salvo em: %LOG_FILE%%RESET%
echo  %DIM%  Suporte: consulte o README.md do projeto%RESET%
echo.
echo %DIM%  ════════════════════════════════════════════════════════%RESET%
echo.
pause
goto :eof


:: ════════════════════════════════════════════════════════════════
:recarregar_path
:: Recarrega variáveis de ambiente sem precisar fechar o terminal
for /f "tokens=2*" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v PATH 2^>nul') do set "SYS_PATH=%%b"
for /f "tokens=2*" %%a in ('reg query "HKCU\Environment" /v PATH 2^>nul') do set "USR_PATH=%%b"
if defined USR_PATH (
    set "PATH=!SYS_PATH!;!USR_PATH!"
) else (
    set "PATH=!SYS_PATH!"
)
goto :eof
