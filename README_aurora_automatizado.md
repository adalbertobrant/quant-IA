# QUANT·IA — Guia do Instalador Automatizado para Linux Aurora
### ASUS TUF F16 · Aurora (Universal Blue / Fedora imutável) · KVM + Windows 11

---

## Índice

1. [Por que esse setup no Aurora](#1-por-que-esse-setup-no-aurora)
2. [Seu hardware e a divisão ideal de recursos](#2-seu-hardware-e-a-divisão-ideal-de-recursos)
3. [O que o instalador faz automaticamente](#3-o-que-o-instalador-faz-automaticamente)
4. [Pré-requisitos antes de rodar](#4-pré-requisitos-antes-de-rodar)
5. [Executando o instalador](#5-executando-o-instalador)
6. [O que acontece após a reinicialização](#6-o-que-acontece-após-a-reinicialização)
7. [Instalando o Windows 11 na VM](#7-instalando-o-windows-11-na-vm)
8. [Instalando o QUANT·IA dentro da VM Windows](#8-instalando-o-quantia-dentro-da-vm-windows)
9. [Iniciando o Dashboard no host Aurora](#9-iniciando-o-dashboard-no-host-aurora)
10. [Scripts de atalho criados no Desktop](#10-scripts-de-atalho-criados-no-desktop)
11. [Uso diário do sistema](#11-uso-diário-do-sistema)
12. [Solução de Problemas](#12-solução-de-problemas)

---

## 1. Por que esse setup no Aurora

O Aurora é uma distribuição **imutável** baseada no Universal Blue (Fedora). Isso
significa que o sistema de arquivos raiz não pode ser modificado diretamente —
o que torna o VirtualBox impraticável, pois ele precisa compilar módulos de
kernel a cada atualização.

A solução certa para o Aurora é o **KVM** (Kernel-based Virtual Machine),
que é a tecnologia de virtualização nativa do Linux e já está embutida no kernel.
O instalador usa `rpm-ostree` para adicionar os pacotes KVM em uma camada
separada, que é o modo correto de instalar software no Aurora sem quebrar
o sistema imutável.

**Comparação:**

| | VirtualBox | KVM (esta solução) |
|---|---|---|
| Compatibilidade com Aurora | ❌ Quebra nas atualizações | ✅ Nativo |
| Desempenho | Médio | ✅ Melhor (hardware-assisted) |
| Instalação | Complexa no Aurora | ✅ Automatizada |
| Suporte oficial Fedora | ❌ Não | ✅ Sim |
| Módulos de kernel | Recompila sempre | ✅ Já no kernel |

---

## 2. Seu hardware e a divisão ideal de recursos

**ASUS TUF F16 com 16 GB RAM + RTX 5050 8 GB**

```
┌─────────────────────────────────────────────────────┐
│  HOST — Linux Aurora                                 │
│                                                     │
│  RAM:    7 GB  (OS + Dashboard React + Chrome)      │
│  vCPUs:  metade dos núcleos                         │
│  GPU:    RTX 5050 (fica no host — o MT5 não usa)    │
│  Disco:  sistema + pasta do projeto                 │
│                                                     │
├─────────────────────────────────────────────────────┤
│  GUEST — Windows 11 (VM KVM)                        │
│                                                     │
│  RAM:    8 GB  (Windows + MT5 + API FastAPI)        │
│  vCPUs:  metade dos núcleos                         │
│  GPU:    QXL virtual (display apenas)               │
│  Disco:  80 GB qcow2 em ~/VMs/                      │
└─────────────────────────────────────────────────────┘
```

**Por que 8 GB para a VM e não mais?**

Com 16 GB totais, 8 GB para a VM deixa 7 GB + 1 GB de margem para o
Aurora rodar confortavelmente com Chrome aberto, o Dashboard React rodando
e outros programas. O MetaTrader 5 + API FastAPI consomem cerca de 1,5 GB
dentro da VM — os 8 GB alocados são mais que suficientes.

**A RTX 5050 fica no host.** O passthrough de GPU para VMs com Nvidia é
um processo complexo que envolve desabilitar o driver Nvidia no host e
configurar VFIO — desnecessário para o QUANT·IA, pois o MT5 e a API
não usam GPU.

---

## 3. O que o instalador faz automaticamente

O `instalador_aurora.sh` executa 10 etapas em sequência:

| Etapa | O que faz |
|---|---|
| **1** | Verifica CPU com suporte KVM, RAM (≥16 GB ideal), espaço em disco, arquitetura 64-bit e se é Aurora |
| **2** | Instala KVM, virt-manager, qemu-kvm e dependências via `rpm-ostree` |
| **3** | Configura o serviço `libvirtd`, adiciona o usuário aos grupos `libvirt` e `kvm`, ajusta `qemu.conf` |
| **4** | Pergunta qual interface de rede usar e configura uma bridge `br-quantia` via nmcli (ou NAT se preferir) |
| **5** | Baixa a ISO dos drivers VirtIO (~600 MB) do repositório oficial Fedora |
| **6** | Pergunta onde está a ISO do Windows 11 (busca automaticamente em Downloads) |
| **7** | Cria a VM com `virt-install`: 8 GB RAM, vCPUs automáticos, disco VirtIO, TPM 2.0, UEFI, SPICE |
| **8** | Instala Node.js 20 LTS via `nvm` no host Aurora (não afeta o sistema imutável) |
| **9** | Roda `npm install` no projeto e pergunta o IP da VM para configurar o Dashboard |
| **10** | Cria 6 scripts de atalho no Desktop + entradas no menu de aplicativos |

**O instalador é idempotente** — se interrompido ou executado novamente após
reiniciar, ele detecta o que já está feito e pula essas etapas automaticamente.

---

## 4. Pré-requisitos antes de rodar

### 4.1 ISO do Windows 11

Baixe antes de executar o instalador:

1. Acesse [microsoft.com/pt-br/software-download/windows11](https://www.microsoft.com/pt-br/software-download/windows11)
2. Selecione **"Baixar imagem de disco ISO para dispositivos x64"**
3. Idioma: **Português (Brasil)**
4. Salve na pasta `~/Downloads/` — o instalador encontrará automaticamente

Tamanho: ~6 GB. O download pode demorar dependendo da sua conexão.

### 4.2 Verificar virtualização ativada na BIOS

No ASUS TUF F16, a virtualização pode estar desabilitada de fábrica.

**Como verificar:**
```bash
grep -c "vmx\|svm" /proc/cpuinfo
# Se retornar 0, a virtualização está desabilitada na BIOS
```

**Como ativar:**
```
Reinicie o computador → pressione F2 durante o boot
→ Advanced → CPU Configuration
→ "Intel Virtualization Technology" ou "SVM Mode" → Enabled
→ F10 para salvar e reiniciar
```

### 4.3 Espaço em disco

O instalador precisa de pelo menos **100 GB livres** em `$HOME`:
- ISO Windows 11: ~6 GB
- ISO VirtIO: ~600 MB
- Disco da VM: 80 GB
- Arquivos do projeto: ~1 GB

Verifique:
```bash
df -h ~
```

### 4.4 Conexão com a internet

Necessária para baixar:
- Pacotes KVM via rpm-ostree (~200 MB)
- ISO VirtIO (~600 MB)
- Node.js via nvm (~50 MB)
- Pacotes npm (~100 MB)

---

## 5. Executando o instalador

Abra um terminal no Aurora e execute:

```bash
# Dê permissão de execução
chmod +x instalador_aurora.sh

# Execute (NÃO use sudo — o script pede sudo quando necessário)
./instalador_aurora.sh
```

> **Importante:** não execute como root (`sudo ./instalador_aurora.sh`).
> O script pede `sudo` internamente apenas nas etapas que precisam.

### O que o instalador vai perguntar

Durante a execução, você responderá a algumas perguntas simples:

**Interface de rede para a bridge:**
```
Interfaces detectadas:
1.  enp3s0  192.168.1.x
2.  wlan0   192.168.1.x
Qual interface usar? (número): 1
```
Se usar cabo de rede (enp3s0), escolha a interface cabeada para melhor estabilidade.

**Deseja configurar bridge?**
```
Configurar bridge? (s/N, padrão: N para NAT):
```
Digite `s` para bridge (recomendado) ou ENTER para NAT (mais simples).

**ISO do Windows 11:**
```
ISOs encontradas automaticamente:
1.  /home/usuario/Downloads/Win11_23H2_Portuguese_x64.iso  (6.1G)
Escolha (número): 1
```

**IP da VM para o Dashboard:**
```
1. Usar localhost
2. Digitar o IP da VM agora
3. Configurar depois manualmente
Escolha (1/2/3, padrão: 3): 3
```
Escolha 3 se ainda não souber o IP — você configurará depois.

---

## 6. O que acontece após a reinicialização

O `rpm-ostree` instala os pacotes KVM em uma **nova camada imutável** do
sistema. Isso requer uma reinicialização para ativar. O instalador irá
perguntar se deseja reiniciar automaticamente.

Após reiniciar, execute o instalador novamente:
```bash
./instalador_aurora.sh
```

Desta vez, as etapas 1 e 2 serão puladas (já instaladas) e o processo
continuará a partir da etapa 3.

**Verificação manual após reiniciar:**
```bash
# KVM disponível
ls -la /dev/kvm

# libvirtd rodando
systemctl status libvirtd

# Usuário nos grupos corretos
groups $USER
# Deve mostrar: ... libvirt kvm ...
```

---

## 7. Instalando o Windows 11 na VM

Após o instalador concluir, abra o gerenciador de VMs:

```bash
# Via script do Desktop
~/Desktop/quant-ia-iniciar-vm.sh

# Ou diretamente
virt-manager
```

### 7.1 Iniciando a instalação

1. No virt-manager, clique duas vezes em `quant-ia-windows11`
2. Clique no botão ▶ **Play** para iniciar a VM
3. A janela do console SPICE abrirá
4. Siga o processo normal de instalação do Windows 11

### 7.2 Opções durante a instalação

Na tela "Que tipo de instalação você deseja?":
- Selecione **"Personalizada: instalar somente o Windows"**

Na tela de seleção de disco:
- O disco pode aparecer vazio (sem partições) — isso é normal com VirtIO
- Se não aparecer nenhum disco, clique em **"Carregar driver"**
- Acesse o CD-ROM dos drivers VirtIO (`D:\`)
- Navegue até `D:\viostor\w11\amd64\` e clique OK
- O disco aparecerá — selecione e clique em **Avançar**

### 7.3 Instalando os drivers VirtIO dentro do Windows

Após o Windows instalar e inicializar:

1. Abra o **Explorador de Arquivos**
2. Acesse o CD-ROM dos drivers (geralmente `D:\`)
3. Execute `virtio-win-gt-x64.exe`
4. Instale todos os componentes (disco, rede, balão de memória)
5. Reinicie a VM quando solicitado

Isso melhora significativamente o desempenho de disco e rede da VM.

### 7.4 Configurações recomendadas no Windows

Após instalar, configure dentro da VM:

```
Configurações → Sistema → Energia → Desempenho máximo
Configurações → Atualização → Pausar atualizações por 5 semanas
Firewall → Permitir porta 8000 (para a API FastAPI)
```

**Liberar a porta 8000 no Firewall:**
Abra o PowerShell como Administrador dentro da VM:
```powershell
New-NetFirewallRule -DisplayName "QUANT-IA API" `
  -Direction Inbound -Protocol TCP -LocalPort 8000 -Action Allow
```

---

## 8. Instalando o QUANT·IA dentro da VM Windows

Dentro da VM Windows, copie os arquivos do projeto e execute o
`instalador.bat` conforme descrito no `README_instala.md` — Seção 2.

**Como copiar os arquivos do host para a VM:**

Opção A — Pasta compartilhada (recomendado):
```bash
# No host Aurora, instale o agente QEMU guest
# (dentro da VM, instale o virtio-win que já inclui o agente)
# Após instalar, use virt-manager → VM → Adicionar Hardware → Filesystem
# Compartilhe a pasta do projeto
```

Opção B — Via rede (após ter IP da VM):
```bash
# No host Aurora
python3 -m http.server 8080 -d /caminho/do/projeto
# Na VM Windows, acesse http://192.168.1.x:8080 e baixe os arquivos
```

Opção C — Pen drive USB:
```
virt-manager → VM → Adicionar Hardware → USB Host Device
Selecione seu pen drive
```

---

## 9. Iniciando o Dashboard no host Aurora

O Dashboard React roda **diretamente no host Aurora**, não na VM.

```bash
# Via script do Desktop
~/Desktop/quant-ia-dashboard.sh

# Ou manualmente
cd /caminho/do/projeto
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"
npm run dev
```

Acesse em: `http://localhost:5173`

### Configurando o IP da VM no Dashboard

Após descobrir o IP da VM (veja abaixo), edite `src/App.jsx`:

```javascript
// Substitua pelo IP real da sua VM Windows
const API = "http://192.168.1.105:8000";
const WS  = "ws://192.168.1.105:8000/ws/logs";
```

### Descobrindo o IP da VM

```bash
# Via script do Desktop
~/Desktop/quant-ia-ip-vm.sh

# Ou manualmente
virsh domifaddr quant-ia-windows11

# Ou dentro da VM Windows
ipconfig
# Anote o "Endereço IPv4"
```

---

## 10. Scripts de atalho criados no Desktop

O instalador cria 6 scripts no `~/Desktop/`:

| Script | Função |
|---|---|
| `quant-ia-dashboard.sh` | Inicia o Dashboard React no host |
| `quant-ia-iniciar-vm.sh` | Inicia a VM Windows e abre o console |
| `quant-ia-parar-vm.sh` | Desliga a VM Windows com segurança |
| `quant-ia-gerenciar-vm.sh` | Abre o virt-manager |
| `quant-ia-normalizar-csv.sh` | Normaliza um CSV via utils/ com prompt |
| `quant-ia-ip-vm.sh` | Detecta e exibe o IP atual da VM |

Para executar, clique duas vezes ou abra um terminal e:
```bash
bash ~/Desktop/quant-ia-dashboard.sh
```

---

## 11. Uso diário do sistema

### Sequência de abertura (toda manhã antes do pregão)

```
1. Abra um terminal
   ~/Desktop/quant-ia-iniciar-vm.sh
   (aguarde o Windows inicializar ~30s)

2. Dentro da VM Windows:
   Clique duas vezes em "QUANT-IA Iniciar" (atalho criado pelo instalador.bat)
   (sobe a API FastAPI na porta 8000)

3. No host Aurora:
   ~/Desktop/quant-ia-dashboard.sh
   (sobe o Dashboard React na porta 5173)

4. Abra o navegador em: http://localhost:5173

5. Gere ou exporte o CSV do screener
   ~/Desktop/quant-ia-normalizar-csv.sh

6. No Dashboard → aba Ordens → carregue o CSV
   → clique em INICIAR
```

### Sequência de fechamento

```
1. No Dashboard → clique em PARAR
   (aguarda o robô terminar o ciclo atual)

2. Feche o terminal do Dashboard (Ctrl+C)

3. ~/Desktop/quant-ia-parar-vm.sh
   (desliga o Windows corretamente)

4. Aguarde a VM desligar (~30s) antes de suspender o notebook
```

### Verificar status da VM sem abrir o console

```bash
# Estado atual
virsh domstate quant-ia-windows11

# Uso de CPU e RAM
virt-top

# Logs do sistema de virtualização
sudo journalctl -u libvirtd -f
```

---

## 12. Solução de Problemas

### `rpm-ostree install` falha com conflito

```bash
# Verifica o status atual
rpm-ostree status

# Remove camadas pendentes se houver conflito
rpm-ostree rollback

# Tenta novamente
rpm-ostree install virt-manager libvirt qemu-kvm --idempotent
```

### libvirtd não inicia após reiniciar

```bash
sudo systemctl status libvirtd
sudo systemctl start libvirtd

# Se falhar, verifica logs
sudo journalctl -xeu libvirtd
```

### VM não aparece no virt-manager

```bash
# Reconecta ao daemon local
virsh -c qemu:///system list --all

# Se vazio, define a conexão padrão
virsh -c qemu:///system define ~/VMs/quant-ia-windows11.xml
```

### Disco VirtIO não aparece na instalação do Windows

Na tela de seleção de disco durante a instalação:
1. Clique em **"Carregar driver"**
2. Acesse `D:\viostor\w11\amd64\`
3. Clique OK
4. O disco VirtIO aparecerá na lista

### VM muito lenta

```bash
# Verifica se KVM está sendo usado (deve mostrar "kvm")
virsh dominfo quant-ia-windows11 | grep "Tipo de CPU"

# Verifica se CPU host-passthrough está ativo
virsh dumpxml quant-ia-windows11 | grep "cpu mode"
# Se não estiver, edite a VM: cpu mode='host-passthrough'
```

### nvm não encontrado após reiniciar

```bash
# Recarrega manualmente
export NVM_DIR="$HOME/.nvm"
source "$NVM_DIR/nvm.sh"
nvm use 20

# Verifica se foi adicionado ao shell
grep "NVM_DIR" ~/.bashrc
```

### Dashboard não conecta na API (VM)

```bash
# 1. Verifica se a VM está ligada
virsh domstate quant-ia-windows11

# 2. Descobre o IP atual da VM
~/Desktop/quant-ia-ip-vm.sh

# 3. Testa conectividade
curl http://IP_DA_VM:8000/status

# 4. Verifica o firewall dentro da VM
# (dentro do Windows PowerShell):
# netstat -ano | findstr :8000
```

### Log completo da instalação

```bash
cat ~/quant-ia/instalacao_aurora.log
```

---

*QUANT·IA B3 Terminal — Guia Aurora Automatizado v1.0*
*ASUS TUF F16 · Aurora Universal Blue · KVM/QEMU · Windows 11 VM*
