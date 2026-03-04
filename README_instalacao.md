# QUANT·IA — Guia de Instalação do Ambiente
### Windows 10/11 (nativo) · Máquina Virtual · Docker no Linux

---

## Índice

1. [Escolha seu Ambiente](#1-escolha-seu-ambiente)
2. [Windows 10/11 — Ambiente Virtual Python](#2-windows-1011--ambiente-virtual-python)
3. [Máquina Virtual Windows no Linux](#3-máquina-virtual-windows-no-linux)
4. [Docker no Linux — API + Dashboard](#4-docker-no-linux--api--dashboard)
5. [Verificação Final da Instalação](#5-verificação-final-da-instalação)
6. [Solução de Problemas de Ambiente](#6-solução-de-problemas-de-ambiente)

---

## 1. Escolha seu Ambiente

O MetaTrader 5 **só roda em Windows**. Escolha a opção que melhor se encaixa:

```
Você tem Windows 10 ou 11?
        │
       SIM ──► Seção 2 — Ambiente Virtual Python (recomendado)
        │
        NÃO
        │
        ▼
Você tem Linux e quer rodar tudo localmente?
        │
       SIM ──► Seção 4 — Docker no Linux
               (API + Dashboard rodam no Docker;
                MT5 precisa de VM Windows — veja Seção 3)
        │
        NÃO
        │
        ▼
Seção 3 — Máquina Virtual Windows no Linux (VirtualBox/VMware)
```

> **Resumo prático:** para operar de verdade na B3, o MT5 exige Windows.
> No Linux, você pode rodar a API e o Dashboard via Docker e conectar a um
> MT5 em uma VM Windows na mesma rede.

---

## 2. Windows 10/11 — Ambiente Virtual Python

### 2.1 Pré-requisitos

Instale na ordem abaixo:

**Python 3.10 ou superior**

1. Acesse [python.org/downloads](https://www.python.org/downloads/)
2. Baixe a versão mais recente (ex: Python 3.12.x)
3. Execute o instalador e marque **obrigatoriamente**:
   - ✅ Add Python to PATH
   - ✅ Install for all users (recomendado)
4. Clique em **Install Now**

Confirme no terminal:
```cmd
python --version
pip --version
```

**Node.js 18 LTS**

1. Acesse [nodejs.org](https://nodejs.org/en/download)
2. Baixe o instalador **LTS** (`.msi`)
3. Execute com as opções padrão
4. Confirme:
```cmd
node --version
npm --version
```

**Git (opcional, mas recomendado)**

1. Acesse [git-scm.com/downloads](https://git-scm.com/downloads)
2. Execute com as opções padrão
3. Confirme:
```cmd
git --version
```

---

### 2.2 Criando o Ambiente Virtual

Abra o **Prompt de Comando** ou **PowerShell** como administrador.

**Navegue até a pasta do projeto:**
```cmd
cd C:\quant-ia
```

**Crie o ambiente virtual:**
```cmd
python -m venv .venv
```

Isso cria a pasta `.venv\` dentro do projeto. Ela isola todas as dependências do QUANT·IA do resto do sistema — você pode ter outros projetos Python sem conflito de versões.

**Ative o ambiente virtual:**

No Prompt de Comando (cmd):
```cmd
.venv\Scripts\activate.bat
```

No PowerShell:
```powershell
.venv\Scripts\Activate.ps1
```

> Se o PowerShell bloquear com erro de política de execução, execute primeiro:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> ```

Após ativar, o prompt muda para mostrar o ambiente:
```cmd
(.venv) C:\quant-ia>
```

**Verificação:**
```cmd
where python
# Deve mostrar: C:\quant-ia\.venv\Scripts\python.exe
```

---

### 2.3 Instalando as Dependências

Com o ambiente virtual **ativado**:

```cmd
pip install --upgrade pip
pip install -r requirements.txt
```

Aguarde o download e instalação de todos os pacotes. A saída final deve ser:
```
Successfully installed fastapi-x.x uvicorn-x.x google-generativeai-x.x
pandas-x.x yfinance-x.x MetaTrader5-x.x python-dotenv-x.x ...
```

**Confirme a instalação:**
```cmd
pip list
```

Você deve ver todos os pacotes do `requirements.txt` listados.

---

### 2.4 Instalando as Dependências Node.js

```cmd
npm install
```

Confirme:
```cmd
npx vite --version
```

---

### 2.5 Ativando o Ambiente a Cada Sessão

O ambiente virtual precisa ser ativado **toda vez** que abrir um novo terminal:

```cmd
cd C:\quant-ia
.venv\Scripts\activate.bat
```

Para facilitar, o `start.bat` já faz isso automaticamente. Se preferir ativar manualmente, adicione um atalho na área de trabalho apontando para:
```
cmd /k "cd /d C:\quant-ia && .venv\Scripts\activate.bat"
```

---

### 2.6 Estrutura após a instalação

```
quant-ia/
├── .venv/                  ← ambiente virtual (não commitar)
│   ├── Scripts/
│   │   ├── activate.bat
│   │   ├── python.exe
│   │   └── pip.exe
│   └── Lib/site-packages/  ← pacotes instalados
├── node_modules/           ← pacotes Node.js (não commitar)
├── utils/
│   ├── __init__.py
│   └── utils.py
├── robo_ia_quantitativo.py
├── api.py
├── requirements.txt
├── package.json
└── .env
```

Adicione ao `.gitignore`:
```gitignore
.venv/
node_modules/
.env
*.log
__pycache__/
screener_bruto.csv
```

---

### 2.7 Atualizando as Dependências

Para atualizar todos os pacotes para as versões mais recentes:
```cmd
.venv\Scripts\activate.bat
pip install --upgrade -r requirements.txt
```

Para gerar um `requirements.txt` com as versões exatas instaladas:
```cmd
pip freeze > requirements_lock.txt
```

---

## 3. Máquina Virtual Windows no Linux

Use esta opção quando quiser rodar o MT5 em Windows dentro de uma máquina Linux.

### 3.1 Opção A — VirtualBox (gratuito)

**Instale o VirtualBox:**
```bash
# Ubuntu / Debian
sudo apt update
sudo apt install virtualbox virtualbox-ext-pack -y

# Fedora / RHEL
sudo dnf install VirtualBox -y

# Arch
sudo pacman -S virtualbox virtualbox-host-modules-arch
```

**Crie a VM Windows:**

1. Abra o VirtualBox → **Novo**
2. Nome: `quant-ia-win`
3. Tipo: **Microsoft Windows** | Versão: **Windows 10 (64-bit)**
4. RAM: **4096 MB** (mínimo), 8192 MB recomendado
5. Disco: **60 GB** (dinâmico)
6. Instale o Windows 10/11 com sua licença (ISO)

**Configure a rede em modo Bridge:**
```
VM → Configurações → Rede → Adaptador 1
→ Conectado a: Placa em modo Bridge
→ Nome: sua interface de rede (ex: eth0, enp3s0)
```

Isso permite que o Dashboard no Linux se comunique com a API rodando na VM.

**Descubra o IP da VM:**
```
(dentro da VM) ipconfig
→ Endereço IPv4: 192.168.x.x
```

---

### 3.2 Opção B — VMware Workstation Player (gratuito para uso pessoal)

```bash
# Baixe o instalador em:
# https://www.vmware.com/products/workstation-player.html

chmod +x VMware-Player-*.bundle
sudo ./VMware-Player-*.bundle
```

Crie a VM com as mesmas especificações do VirtualBox acima. Configure a rede em **modo Bridged**.

---

### 3.3 Instalação do QUANT·IA na VM Windows

Dentro da VM Windows, siga inteiramente a **Seção 2** deste guia.

No `.env` da VM, configure `api.py` para ouvir em todas as interfaces:

Edite `api.py`, localize a linha final e altere:
```python
# DE:
uvicorn.run("api:app", host="0.0.0.0", port=8000, reload=False)

# Já está correto — host="0.0.0.0" aceita conexões externas
```

Libere a porta 8000 no Firewall do Windows (dentro da VM):
```cmd
netsh advfirewall firewall add rule name="QUANT-IA API" ^
  dir=in action=allow protocol=TCP localport=8000
```

---

### 3.4 Dashboard React no Linux (fora da VM)

No seu Linux, clone ou copie os arquivos do frontend:

```bash
cd ~/quant-ia
npm install
```

Edite `src/App.jsx` — aponte para o IP da VM Windows:
```javascript
// Substitua localhost pelo IP da sua VM
const API = "http://192.168.x.x:8000";
const WS  = "ws://192.168.x.x:8000/ws/logs";
```

Inicie o dashboard:
```bash
npm run dev
```

Acesse em `http://localhost:5173`.

---

## 4. Docker no Linux — API + Dashboard

Use esta opção para rodar a API FastAPI e o Dashboard React em containers Linux. O MT5 ainda precisará de uma VM Windows (Seção 3) ou máquina Windows separada na mesma rede.

### 4.1 Pré-requisitos Linux

**Docker Engine:**
```bash
# Ubuntu / Debian
sudo apt update
sudo apt install ca-certificates curl gnupg -y
sudo install -m 0755 -d /etc/apt/keyrings

curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo "deb [arch=$(dpkg --print-architecture) \
  signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install docker-ce docker-ce-cli containerd.io -y

# Adiciona seu usuário ao grupo docker (evita usar sudo)
sudo usermod -aG docker $USER
newgrp docker
```

**Docker Compose:**
```bash
sudo apt install docker-compose-plugin -y
docker compose version
```

**Confirme a instalação:**
```bash
docker --version
docker compose version
```

---

### 4.2 Estrutura Docker do Projeto

```
quant-ia/
├── docker/
│   ├── Dockerfile.api          ← imagem da API FastAPI
│   └── Dockerfile.dashboard    ← imagem do Dashboard React
├── docker-compose.yml          ← orquestra os dois containers
├── .env                        ← credenciais (montado como volume)
└── screener_resultados.csv     ← montado como volume
```

---

### 4.3 Dockerfile da API

Crie o arquivo `docker/Dockerfile.api`:

```dockerfile
FROM python:3.12-slim

LABEL maintainer="quant-ia"
LABEL description="QUANT·IA — API FastAPI"

# Variáveis de ambiente Python
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Instala dependências do sistema
RUN apt-get update && apt-get install -y --no-install-recommends \
    gcc \
    && rm -rf /var/lib/apt/lists/*

# Copia e instala dependências Python
# ATENÇÃO: MetaTrader5 não instala no Linux — removido nesta imagem.
# A API em modo Linux opera sem MT5 (modo mock/leitura).
COPY requirements.txt .
RUN pip install --no-cache-dir --upgrade pip && \
    pip install --no-cache-dir \
        fastapi \
        uvicorn \
        python-dotenv \
        google-generativeai \
        pandas \
        yfinance \
        requests \
        pydantic

# Copia o código
COPY api.py .
COPY robo_ia_quantitativo.py .
COPY utils/ ./utils/

# Expõe a porta da API
EXPOSE 8000

# Healthcheck
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
  CMD curl -f http://localhost:8000/ || exit 1

CMD ["uvicorn", "api:app", "--host", "0.0.0.0", "--port", "8000", "--log-level", "warning"]
```

---

### 4.4 Dockerfile do Dashboard

Crie o arquivo `docker/Dockerfile.dashboard`:

```dockerfile
FROM node:20-alpine

LABEL maintainer="quant-ia"
LABEL description="QUANT·IA — Dashboard React"

WORKDIR /app

# Copia dependências e instala
COPY package.json package-lock.json* ./
RUN npm ci --silent

# Copia o código fonte
COPY index.html .
COPY vite.config.js .
COPY src/ ./src/

# Build de produção
RUN npm run build

# Serve o build com um servidor leve
RUN npm install -g serve

EXPOSE 5173

CMD ["serve", "-s", "dist", "-l", "5173"]
```

---

### 4.5 Docker Compose

Crie o arquivo `docker-compose.yml` na raiz do projeto:

```yaml
# ════════════════════════════════════════════════════════
#  QUANT·IA — Docker Compose
#  Sobe a API FastAPI e o Dashboard React em containers
# ════════════════════════════════════════════════════════

version: "3.9"

services:

  # ── API FastAPI ──────────────────────────────────────
  api:
    build:
      context: .
      dockerfile: docker/Dockerfile.api
    container_name: quantia-api
    restart: unless-stopped
    ports:
      - "8000:8000"
    volumes:
      # Monta o .env e o CSV como volumes para atualização sem rebuild
      - ./.env:/app/.env:ro
      - ./screener_resultados.csv:/app/screener_resultados.csv
      - ./logs:/app/logs
    environment:
      - PYTHONUNBUFFERED=1
    networks:
      - quantia-net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 10s

  # ── Dashboard React ──────────────────────────────────
  dashboard:
    build:
      context: .
      dockerfile: docker/Dockerfile.dashboard
    container_name: quantia-dashboard
    restart: unless-stopped
    ports:
      - "5173:5173"
    depends_on:
      api:
        condition: service_healthy
    networks:
      - quantia-net

networks:
  quantia-net:
    driver: bridge
```

---

### 4.6 Adaptação do Dashboard para Docker

Antes de buildar, configure o endereço da API. Se a API e o Dashboard rodam na **mesma máquina Linux**:

```javascript
// src/App.jsx — linha do topo
const API = "http://localhost:8000";
const WS  = "ws://localhost:8000/ws/logs";
```

Se a API roda em uma **VM Windows separada** (Seção 3) e o Dashboard no Linux:
```javascript
const API = "http://192.168.x.x:8000";   // IP da VM Windows
const WS  = "ws://192.168.x.x:8000/ws/logs";
```

---

### 4.7 Adaptação da API para Linux (sem MT5)

O `MetaTrader5` não instala no Linux. Crie um arquivo `api_linux.py` que usa a API normalmente mas retorna dados mock quando o MT5 não está disponível, ou aponte para um MT5 remoto na VM Windows.

Adicione no início de `api.py` logo após os imports:

```python
# Detecta se está rodando em Linux (sem MT5 disponível)
import platform
MT5_AVAILABLE = platform.system() == "Windows"

if not MT5_AVAILABLE:
    import warnings
    warnings.warn(
        "MetaTrader5 não disponível (Linux). "
        "Endpoints de operação retornarão dados simulados. "
        "Para operar de verdade, rode a API no Windows.",
        RuntimeWarning
    )
```

---

### 4.8 Comandos Docker

**Construir as imagens:**
```bash
docker compose build
```

**Subir os containers:**
```bash
docker compose up -d
```

**Verificar se estão rodando:**
```bash
docker compose ps
```

Saída esperada:
```
NAME                IMAGE               STATUS          PORTS
quantia-api         quantia-api         Up (healthy)    0.0.0.0:8000->8000/tcp
quantia-dashboard   quantia-dashboard   Up              0.0.0.0:5173->5173/tcp
```

**Ver logs em tempo real:**
```bash
# Todos os containers
docker compose logs -f

# Apenas a API
docker compose logs -f api

# Apenas o Dashboard
docker compose logs -f dashboard
```

**Atualizar o CSV sem reiniciar:**
```bash
# Como o CSV é um volume, basta copiar o novo arquivo
cp screener_novo.csv screener_resultados.csv
# A API lerá automaticamente no próximo ciclo
```

**Parar os containers:**
```bash
docker compose down
```

**Reconstruir após mudanças no código:**
```bash
docker compose down
docker compose build --no-cache
docker compose up -d
```

**Remover tudo (containers, imagens e volumes):**
```bash
docker compose down --rmi all --volumes
```

---

### 4.9 Acesso após subir os containers

| Serviço | URL |
|---|---|
| Dashboard | `http://localhost:5173` |
| API | `http://localhost:8000` |
| Docs Swagger | `http://localhost:8000/docs` |

---

### 4.10 Variáveis de Ambiente no Docker

O arquivo `.env` é montado como volume somente leitura (`:ro`) no container da API. Qualquer alteração no `.env` do host é refletida no container após reinício:

```bash
# Edite o .env no host
nano .env

# Reinicie apenas a API para aplicar
docker compose restart api
```

Para passar variáveis diretamente sem o `.env`, use a seção `environment` no `docker-compose.yml`:

```yaml
  api:
    environment:
      - MT5_LOGIN=12345678
      - BROKER_NAME=BTG
      - DRY_RUN=true
      - GOOGLE_API_KEY=${GOOGLE_API_KEY}  # pega do shell atual
```

---

## 5. Verificação Final da Instalação

Execute este checklist independente do ambiente escolhido:

### 5.1 Python e pacotes

```bash
# Windows (com venv ativo) ou Linux
python --version
# Esperado: Python 3.10.x ou superior

python -c "
import fastapi, uvicorn, pydantic, pandas, yfinance, dotenv
import google.generativeai
print('✅ Todos os pacotes Python instalados corretamente')
print(f'   fastapi:            {fastapi.__version__}')
print(f'   pandas:             {pandas.__version__}')
print(f'   google-generativeai instalado')
"
```

### 5.2 MetaTrader5 (apenas Windows)

```cmd
python -c "
import MetaTrader5 as mt5
print(f'✅ MetaTrader5 versão: {mt5.__version__}')
"
```

### 5.3 Chave do Google AI

```bash
python -c "
import os, google.generativeai as genai
from dotenv import load_dotenv
load_dotenv()
key = os.getenv('GOOGLE_API_KEY', '')
if not key:
    print('❌ GOOGLE_API_KEY não encontrada no .env')
else:
    genai.configure(api_key=key)
    r = genai.GenerativeModel('gemini-1.5-pro').generate_content('Responda: OK')
    print(f'✅ Google AI respondeu: {r.text.strip()}')
"
```

### 5.4 API FastAPI

```bash
# Terminal 1 — sobe a API
python api.py

# Terminal 2 — testa o endpoint de status
curl http://localhost:8000/status
# ou no Windows:
# Invoke-WebRequest http://localhost:8000/status | Select-Object -Expand Content
```

### 5.5 Node.js e Dashboard

```bash
npm run dev
# Acesse http://localhost:5173
# O indicador no topo esquerdo deve ficar AZUL (API online)
```

### 5.6 Módulo utils/

```bash
python utils\utils.py screener_resultados.csv
# Deve imprimir o relatório de normalização sem erros
```

---

## 6. Solução de Problemas de Ambiente

### Python não encontrado após instalação

```cmd
# Verifique se o PATH está correto
where python

# Se não encontrar, adicione manualmente ao PATH:
# Painel de Controle → Sistema → Variáveis de Ambiente
# → Path → Adicionar: C:\Users\SeuUsuario\AppData\Local\Programs\Python\Python312\
```

### Erro ao ativar o venv no PowerShell

```powershell
# Erro: "não pode ser carregado porque a execução de scripts está desabilitada"
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
# Tente ativar novamente
.venv\Scripts\Activate.ps1
```

### `pip install` falha com erro de permissão

```cmd
# Use o flag --user ou rode como administrador
pip install --user -r requirements.txt

# Ou rode o Prompt de Comando como Administrador
```

### MetaTrader5 não instala

```cmd
# Confirme que está no Windows
python -c "import platform; print(platform.system())"
# Deve imprimir: Windows

# Atualize o pip antes
pip install --upgrade pip
pip install MetaTrader5
```

### Docker: permissão negada ao rodar `docker`

```bash
# Adicione seu usuário ao grupo docker
sudo usermod -aG docker $USER

# Recarregue o grupo sem fazer logout
newgrp docker

# Confirme
docker ps
```

### Docker: porta 8000 ou 5173 já em uso

```bash
# Identifica o processo
sudo lsof -i :8000
sudo lsof -i :5173

# Encerra o processo pelo PID
sudo kill -9 <PID>

# Ou mude a porta no docker-compose.yml:
# ports:
#   - "8001:8000"  ← muda só a porta do host
```

### Container sobe mas API retorna erro 500

```bash
# Veja os logs detalhados
docker compose logs api --tail=50

# Problemas comuns:
# 1. .env não encontrado → confirme que o arquivo existe na pasta do projeto
# 2. GOOGLE_API_KEY inválida → verifique no AI Studio
# 3. MetaTrader5 não disponível no Linux → comportamento esperado (modo mock)
```

### `npm install` falha com erro de versão

```bash
# Confirme a versão do Node.js
node --version  # precisa ser 18+

# Se for inferior, instale o NVM para gerenciar versões:
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash
source ~/.bashrc
nvm install 20
nvm use 20
npm install
```

### Erro `ModuleNotFoundError: No module named 'utils'`

```cmd
# Confirme a estrutura de pastas
dir utils\

# Deve existir:
# utils\__init__.py
# utils\utils.py

# Se não existir o __init__.py:
copy NUL utils\__init__.py
```

---

## Resumo dos Comandos Essenciais

### Windows — uso diário

```cmd
# Ativar ambiente virtual
cd C:\quant-ia
.venv\Scripts\activate.bat

# Iniciar tudo (recomendado)
start.bat

# Ou manualmente:
python api.py          ← Terminal 1
npm run dev            ← Terminal 2
```

### Linux com Docker — uso diário

```bash
cd ~/quant-ia

# Subir
docker compose up -d

# Ver status
docker compose ps

# Ver logs
docker compose logs -f api

# Parar
docker compose down
```

---

*QUANT·IA B3 Terminal — Guia de Instalação v1.0*
