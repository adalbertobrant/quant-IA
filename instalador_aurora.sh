#!/bin/bash
# ════════════════════════════════════════════════════════════════
#  QUANT·IA — Instalador Automático para Linux Aurora
#  Testado em: Aurora (Universal Blue / Fedora imutável)
#
#  O que este instalador faz:
#    1. Verifica compatibilidade (CPU, RAM, KVM, Aurora)
#    2. Instala KVM + virt-manager via rpm-ostree
#    3. Configura libvirt e permissões do usuário
#    4. Configura rede bridge para comunicação VM ↔ Host
#    5. Baixa drivers VirtIO para Windows
#    6. Cria a VM Windows 11 automaticamente (8 GB RAM, 80 GB disco)
#    7. Instala Node.js via nvm no host
#    8. Configura o Dashboard React no host
#    9. Cria scripts de atalho no Desktop
#   10. Exibe relatório final e próximos passos
#
#  USO:
#    chmod +x instalador_aurora.sh
#    ./instalador_aurora.sh
# ════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Cores ─────────────────────────────────────────────────────────
RED='\033[0;91m'
GREEN='\033[0;92m'
YELLOW='\033[0;93m'
CYAN='\033[0;96m'
WHITE='\033[0;97m'
BOLD='\033[1m'
DIM='\033[2m'
RESET='\033[0m'

# ── Caminhos ──────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE="$SCRIPT_DIR/instalacao_aurora.log"
DESKTOP="$HOME/Desktop"
VM_DISK_DIR="$HOME/VMs"
VM_NAME="quant-ia-windows11"
VM_DISK="$VM_DISK_DIR/${VM_NAME}.qcow2"
VIRTIO_ISO="$VM_DISK_DIR/virtio-win.iso"
WIN11_ISO=""   # preenchido pelo usuário

# ── Configurações da VM ───────────────────────────────────────────
VM_RAM_MB=8192
VM_VCPUS=$(( $(nproc) / 2 ))
VM_DISK_GB=80

# ── Log ───────────────────────────────────────────────────────────
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG_FILE"; }
ok()   { echo -e "  ${GREEN}✓${RESET}  $*"; log "OK: $*"; }
warn() { echo -e "  ${YELLOW}⚠${RESET}  $*"; log "WARN: $*"; }
fail() { echo -e "  ${RED}✗${RESET}  $*"; log "FAIL: $*"; }
info() { echo -e "  ${DIM}$*${RESET}"; log "INFO: $*"; }
step() { echo -e "\n${CYAN}[$1]${RESET} ${BOLD}$2${RESET}"; log "STEP [$1]: $2"; }

# ── Verificação de erro com mensagem amigável ─────────────────────
die() {
    echo -e "\n${RED}${BOLD}  ERRO FATAL: $*${RESET}"
    echo -e "  Verifique o log: ${LOG_FILE}\n"
    log "FATAL: $*"
    exit 1
}

# ════════════════════════════════════════════════════════════════
tela_boas_vindas() {
    clear
    echo
    echo -e "${CYAN}${BOLD}  ╔══════════════════════════════════════════════════════╗${RESET}"
    echo -e "${CYAN}${BOLD}  ║           QUANT·IA — B3 Terminal                    ║${RESET}"
    echo -e "${CYAN}${BOLD}  ║     Instalador para Linux Aurora (Fedora)            ║${RESET}"
    echo -e "${CYAN}${BOLD}  ╚══════════════════════════════════════════════════════╝${RESET}"
    echo
    echo -e "  ${WHITE}Robô de Trading com IA · BTG Pactual · Toro Investimentos${RESET}"
    echo
    echo -e "  ${DIM}══════════════════════════════════════════════════════${RESET}"
    echo
    echo -e "  O que será configurado nesta máquina:"
    echo
    echo -e "  ${GREEN}✓${RESET}  KVM/QEMU (virtualização nativa do Linux)"
    echo -e "  ${GREEN}✓${RESET}  virt-manager (gerenciador visual de VMs)"
    echo -e "  ${GREEN}✓${RESET}  VM Windows 11 (${VM_RAM_MB} MB RAM, ${VM_DISK_GB} GB disco)"
    echo -e "  ${GREEN}✓${RESET}  Rede bridge (VM visível na rede local)"
    echo -e "  ${GREEN}✓${RESET}  Drivers VirtIO (alta performance na VM)"
    echo -e "  ${GREEN}✓${RESET}  Node.js via nvm (Dashboard React no host)"
    echo -e "  ${GREEN}✓${RESET}  Scripts de atalho no Desktop"
    echo
    echo -e "  ${YELLOW}Tempo estimado: 15 a 30 minutos${RESET}"
    echo -e "  ${YELLOW}Requer conexão com a internet${RESET}"
    echo -e "  ${YELLOW}Será necessário reiniciar ao final${RESET}"
    echo
    echo -e "  ${DIM}══════════════════════════════════════════════════════${RESET}"
    echo
    read -rp "  Pressione ENTER para começar ou Ctrl+C para cancelar..."
    echo
    log "=== Instalador iniciado por $USER em $(date) ==="
}

# ════════════════════════════════════════════════════════════════
verificar_sistema() {
    step "1/10" "Verificando compatibilidade do sistema"

    # Verifica Aurora / Universal Blue
    if grep -qi "aurora\|universal.blue\|ublue" /etc/os-release 2>/dev/null; then
        ok "Sistema Aurora (Universal Blue) detectado."
    elif grep -qi "fedora" /etc/os-release 2>/dev/null; then
        warn "Fedora padrão detectado (não Aurora). Alguns passos podem diferir."
    else
        warn "Distribuição não reconhecida. Prosseguindo com cautela."
    fi

    # rpm-ostree disponível
    if ! command -v rpm-ostree &>/dev/null; then
        die "rpm-ostree não encontrado. Este script requer Aurora ou Fedora Silverblue/Kinoite."
    fi
    ok "rpm-ostree disponível."

    # Verifica suporte à virtualização no CPU
    if grep -qE '(vmx|svm)' /proc/cpuinfo; then
        CPU_VIRT=$(grep -oE '(vmx|svm)' /proc/cpuinfo | head -1)
        ok "Virtualização de hardware ativa (${CPU_VIRT})."
    else
        fail "Virtualização de hardware NÃO detectada."
        echo
        echo -e "  Para ativar, acesse a BIOS/UEFI do seu ASUS TUF F16:"
        echo -e "  ${DIM}Reinicie → F2 ou Del → Advanced → CPU Configuration${RESET}"
        echo -e "  ${DIM}Ative: Intel VT-x (Intel) ou AMD-V (AMD)${RESET}"
        echo
        read -rp "  Continuar mesmo assim? (s/N): " CONT
        [[ "${CONT,,}" == "s" ]] || exit 1
    fi

    # Verifica KVM disponível
    if [ -e /dev/kvm ]; then
        ok "/dev/kvm disponível — KVM pronto para uso."
    else
        warn "/dev/kvm não encontrado — será instalado nos próximos passos."
    fi

    # RAM total
    RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    RAM_GB=$(( RAM_KB / 1024 / 1024 ))
    if (( RAM_GB >= 14 )); then
        ok "RAM: ${RAM_GB} GB — configuração excelente para VM de 8 GB."
    elif (( RAM_GB >= 8 )); then
        ok "RAM: ${RAM_GB} GB — suficiente."
    else
        warn "RAM: ${RAM_GB} GB — abaixo do recomendado (16 GB)."
    fi

    # Núcleos de CPU
    CORES=$(nproc)
    VM_VCPUS=$(( CORES / 2 ))
    ok "CPU: ${CORES} núcleos detectados. VM receberá ${VM_VCPUS} vCPUs."

    # Espaço em disco
    DISK_FREE_GB=$(df -BG "$HOME" | awk 'NR==2 {gsub("G",""); print $4}')
    if (( DISK_FREE_GB >= 100 )); then
        ok "Espaço livre: ${DISK_FREE_GB} GB — suficiente."
    elif (( DISK_FREE_GB >= 60 )); then
        warn "Espaço livre: ${DISK_FREE_GB} GB — apertado. Mínimo recomendado: 100 GB."
    else
        fail "Espaço livre insuficiente: ${DISK_FREE_GB} GB. Libere espaço e tente novamente."
        exit 1
    fi
}

# ════════════════════════════════════════════════════════════════
instalar_kvm() {
    step "2/10" "Instalando KVM + virt-manager via rpm-ostree"

    # Verifica se já está instalado
    if rpm -q virt-manager &>/dev/null && rpm -q libvirt &>/dev/null; then
        ok "KVM e virt-manager já instalados."
        return
    fi

    echo
    echo -e "  ${YELLOW}ATENÇÃO:${RESET} O rpm-ostree instala pacotes em camada."
    echo -e "  ${YELLOW}O sistema precisará reiniciar ao final da instalação.${RESET}"
    echo
    echo -e "  Pacotes que serão instalados:"
    echo -e "  ${DIM}virt-manager libvirt qemu-kvm libvirt-daemon-kvm${RESET}"
    echo -e "  ${DIM}virt-install libvirt-client bridge-utils${RESET}"
    echo

    log "Iniciando rpm-ostree install..."

    rpm-ostree install --idempotent --assumeyes \
        virt-manager \
        libvirt \
        qemu-kvm \
        libvirt-daemon-kvm \
        virt-install \
        libvirt-client \
        bridge-utils \
        2>&1 | tee -a "$LOG_FILE" | grep -E "^(Instalando|Installing|Erro|Error|✓|Concluído)" || true

    ok "Pacotes KVM instalados via rpm-ostree."
    warn "Uma reinicialização será necessária para ativar os módulos."
    log "rpm-ostree install concluído."
}

# ════════════════════════════════════════════════════════════════
configurar_libvirt() {
    step "3/10" "Configurando libvirt e permissões"

    # Ativa serviços (podem não funcionar até reiniciar, mas prepara)
    for SVC in libvirtd virtlogd; do
        sudo systemctl enable "$SVC" 2>/dev/null && \
            ok "Serviço $SVC habilitado para iniciar automaticamente." || \
            warn "Serviço $SVC não disponível ainda (normal antes de reiniciar)."
    done

    # Inicia se possível
    sudo systemctl start libvirtd 2>/dev/null && \
        ok "libvirtd iniciado." || \
        warn "libvirtd não pôde iniciar agora — normal antes de reiniciar."

    # Adiciona usuário ao grupo libvirt e kvm
    for GRP in libvirt kvm; do
        if getent group "$GRP" &>/dev/null; then
            sudo usermod -aG "$GRP" "$USER" 2>/dev/null && \
                ok "Usuário $USER adicionado ao grupo $GRP."
        fi
    done

    # Configura acesso como usuário não-root (recomendado)
    QEMU_CONF="/etc/libvirt/qemu.conf"
    if [ -f "$QEMU_CONF" ]; then
        if ! grep -q "^user = \"$USER\"" "$QEMU_CONF"; then
            sudo sed -i "s/#user = \"root\"/user = \"$USER\"/" "$QEMU_CONF" 2>/dev/null || true
            sudo sed -i "s/#group = \"root\"/group = \"$USER\"/" "$QEMU_CONF" 2>/dev/null || true
            ok "qemu.conf configurado para o usuário $USER."
        else
            ok "qemu.conf já configurado."
        fi
    fi

    # Cria pasta para discos das VMs
    mkdir -p "$VM_DISK_DIR"
    ok "Pasta para VMs criada: $VM_DISK_DIR"
}

# ════════════════════════════════════════════════════════════════
configurar_rede_bridge() {
    step "4/10" "Configurando rede bridge"

    echo
    echo -e "  A rede bridge permite que a VM Windows tenha IP próprio"
    echo -e "  na sua rede, possibilitando comunicação com o Dashboard"
    echo -e "  React rodando no host Aurora."
    echo
    echo -e "  ${CYAN}Interfaces de rede detectadas:${RESET}"
    echo

    # Lista interfaces físicas
    mapfile -t IFACES < <(ip link show | awk '/^[0-9]+:/ {gsub(":",""); if ($2 != "lo") print $2}')
    for i in "${!IFACES[@]}"; do
        IP=$(ip addr show "${IFACES[$i]}" 2>/dev/null | grep 'inet ' | awk '{print $2}' | head -1)
        echo -e "  ${CYAN}$((i+1)).${RESET}  ${IFACES[$i]}  ${DIM}${IP:-sem IP}${RESET}"
    done

    echo
    read -rp "  Qual interface usar para a bridge? (número ou nome, ex: 1): " IFACE_CHOICE

    # Resolve nome da interface
    if [[ "$IFACE_CHOICE" =~ ^[0-9]+$ ]]; then
        IDX=$(( IFACE_CHOICE - 1 ))
        IFACE="${IFACES[$IDX]}"
    else
        IFACE="$IFACE_CHOICE"
    fi

    if [ -z "$IFACE" ]; then
        warn "Interface não selecionada. Usando rede NAT padrão (mais simples)."
        BRIDGE_MODE="nat"
        return
    fi

    echo
    echo -e "  Interface selecionada: ${CYAN}${IFACE}${RESET}"
    echo
    echo -e "  ${YELLOW}Deseja configurar a bridge agora?${RESET}"
    echo -e "  ${DIM}(Recomendado para comunicação direta VM ↔ Dashboard)${RESET}"
    echo -e "  ${DIM}Alternativa: NAT (mais simples, mas exige proxy para comunicação)${RESET}"
    echo
    read -rp "  Configurar bridge? (s/N, padrão: N para NAT): " CONF_BRIDGE

    if [[ "${CONF_BRIDGE,,}" == "s" ]]; then
        # Cria bridge via nmcli
        BRIDGE_NAME="br-quantia"

        # Remove se já existir
        nmcli connection delete "$BRIDGE_NAME" 2>/dev/null || true

        nmcli connection add type bridge \
            ifname "$BRIDGE_NAME" \
            con-name "$BRIDGE_NAME" \
            bridge.stp no \
            2>/dev/null && ok "Bridge $BRIDGE_NAME criada." || \
            warn "Falha ao criar bridge — usando NAT."

        nmcli connection add type bridge-slave \
            ifname "$IFACE" \
            master "$BRIDGE_NAME" \
            con-name "${BRIDGE_NAME}-slave" \
            2>/dev/null && ok "Interface $IFACE associada à bridge." || \
            warn "Falha ao associar interface."

        nmcli connection up "$BRIDGE_NAME" 2>/dev/null && \
            ok "Bridge $BRIDGE_NAME ativa." || \
            warn "Bridge não pôde ser ativada agora."

        BRIDGE_MODE="bridge"
        BRIDGE_IFACE="$BRIDGE_NAME"
        ok "Rede bridge configurada: ${BRIDGE_NAME}"

        # Salva o nome da bridge para uso na criação da VM
        echo "$BRIDGE_NAME" > "$VM_DISK_DIR/.bridge_name"

    else
        BRIDGE_MODE="nat"
        ok "Usando rede NAT. A VM terá acesso à internet e ao host via 192.168.122.1."
        info "Para encontrar o IP da VM depois: execute 'ip addr' dentro do Windows"
    fi

    echo "$BRIDGE_MODE" > "$VM_DISK_DIR/.network_mode"
}

# ════════════════════════════════════════════════════════════════
baixar_virtio() {
    step "5/10" "Baixando drivers VirtIO para Windows"

    VIRTIO_URL="https://fedorapeople.org/groups/virt/virtio-win/direct-downloads/stable-virtio/virtio-win.iso"

    if [ -f "$VIRTIO_ISO" ]; then
        ok "virtio-win.iso já existe em $VM_DISK_DIR — pulando download."
        return
    fi

    echo
    echo -e "  Os drivers VirtIO garantem alto desempenho de disco e rede"
    echo -e "  dentro da VM Windows."
    echo -e "  ${DIM}Tamanho: ~600 MB${RESET}"
    echo

    if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$VIRTIO_ISO" "$VIRTIO_URL" 2>&1 | \
            grep -E "%" || wget -O "$VIRTIO_ISO" "$VIRTIO_URL"
    elif command -v curl &>/dev/null; then
        curl -L --progress-bar -o "$VIRTIO_ISO" "$VIRTIO_URL"
    else
        warn "wget e curl não encontrados. Pulando download dos drivers VirtIO."
        warn "Baixe manualmente: $VIRTIO_URL"
        warn "Salve em: $VIRTIO_ISO"
        return
    fi

    if [ -f "$VIRTIO_ISO" ] && [ -s "$VIRTIO_ISO" ]; then
        ok "virtio-win.iso baixado com sucesso."
    else
        warn "Download dos drivers VirtIO falhou. A VM funcionará, mas com desempenho reduzido."
    fi
}

# ════════════════════════════════════════════════════════════════
localizar_iso_windows() {
    step "6/10" "Localizando ISO do Windows 11"

    echo
    echo -e "  ${BOLD}Você precisa de uma ISO do Windows 11.${RESET}"
    echo
    echo -e "  ${CYAN}Como obter gratuitamente:${RESET}"
    echo -e "  ${DIM}1. Acesse: https://www.microsoft.com/pt-br/software-download/windows11${RESET}"
    echo -e "  ${DIM}2. Clique em \"Baixar imagem de disco ISO\"${RESET}"
    echo -e "  ${DIM}3. Selecione Windows 11 (multi-edition ISO)${RESET}"
    echo -e "  ${DIM}4. Idioma: Português (Brasil)${RESET}"
    echo -e "  ${DIM}5. Baixe o arquivo (~6 GB)${RESET}"
    echo
    echo -e "  Se já tiver a ISO baixada, informe o caminho completo."
    echo

    # Tenta encontrar automaticamente
    ISO_SEARCH=$(find "$HOME" /tmp /media /run/media -maxdepth 5 \
        -name "*.iso" -iname "*windows*" -o -name "*.iso" -iname "*win11*" \
        2>/dev/null | head -5)

    if [ -n "$ISO_SEARCH" ]; then
        echo -e "  ${GREEN}ISOs encontradas automaticamente:${RESET}"
        echo
        mapfile -t ISOS <<< "$ISO_SEARCH"
        for i in "${!ISOS[@]}"; do
            SIZE=$(du -h "${ISOS[$i]}" 2>/dev/null | cut -f1)
            echo -e "  ${CYAN}$((i+1)).${RESET}  ${ISOS[$i]}  ${DIM}(${SIZE})${RESET}"
        done
        echo -e "  ${CYAN}$((${#ISOS[@]}+1)).${RESET}  Informar outro caminho"
        echo
        read -rp "  Escolha (número): " ISO_CHOICE

        if [[ "$ISO_CHOICE" =~ ^[0-9]+$ ]] && (( ISO_CHOICE <= ${#ISOS[@]} )); then
            WIN11_ISO="${ISOS[$((ISO_CHOICE-1))]}"
        else
            read -rp "  Caminho completo da ISO: " WIN11_ISO
        fi
    else
        echo -e "  ${DIM}Nenhuma ISO encontrada automaticamente.${RESET}"
        echo
        read -rp "  Caminho completo da ISO do Windows 11: " WIN11_ISO
    fi

    # Expande ~ se necessário
    WIN11_ISO="${WIN11_ISO/#\~/$HOME}"

    if [ ! -f "$WIN11_ISO" ]; then
        warn "ISO não encontrada: $WIN11_ISO"
        warn "A VM será criada SEM a ISO — você precisará associá-la manualmente no virt-manager."
        WIN11_ISO=""
    else
        ISO_SIZE=$(du -h "$WIN11_ISO" | cut -f1)
        ok "ISO localizada: $WIN11_ISO (${ISO_SIZE})"
    fi
}

# ════════════════════════════════════════════════════════════════
criar_vm() {
    step "7/10" "Criando VM Windows 11"

    # Verifica se libvirtd está rodando
    if ! systemctl is-active libvirtd &>/dev/null; then
        warn "libvirtd não está ativo. A VM será criada após reiniciar."
        warn "Execute este script novamente após reiniciar."
        PRECISA_REINICIAR=true
        return
    fi

    # Verifica se a VM já existe
    if virsh dominfo "$VM_NAME" &>/dev/null 2>&1; then
        ok "VM '$VM_NAME' já existe — pulando criação."
        return
    fi

    echo
    echo -e "  Criando disco virtual de ${VM_DISK_GB} GB..."
    mkdir -p "$VM_DISK_DIR"
    qemu-img create -f qcow2 "$VM_DISK" "${VM_DISK_GB}G" 2>/dev/null && \
        ok "Disco criado: $VM_DISK" || \
        warn "Falha ao criar disco — verifique permissões em $VM_DISK_DIR"

    # Configuração de rede
    NET_MODE="nat"
    NET_ARG="--network network=default"
    if [ -f "$VM_DISK_DIR/.bridge_name" ] && [ -f "$VM_DISK_DIR/.network_mode" ]; then
        SAVED_MODE=$(cat "$VM_DISK_DIR/.network_mode")
        if [ "$SAVED_MODE" == "bridge" ]; then
            BRIDGE=$(cat "$VM_DISK_DIR/.bridge_name")
            NET_ARG="--network bridge=${BRIDGE},model=virtio"
            NET_MODE="bridge ($BRIDGE)"
        fi
    fi

    echo -e "  Rede: ${CYAN}${NET_MODE}${RESET}"
    echo -e "  RAM: ${CYAN}${VM_RAM_MB} MB${RESET}"
    echo -e "  vCPUs: ${CYAN}${VM_VCPUS}${RESET}"
    echo -e "  Disco: ${CYAN}${VM_DISK_GB} GB (VirtIO)${RESET}"
    echo

    # Monta argumentos da ISO
    CDROM_ARGS=""
    if [ -n "$WIN11_ISO" ] && [ -f "$WIN11_ISO" ]; then
        CDROM_ARGS="--cdrom $WIN11_ISO"
    else
        CDROM_ARGS="--pxe"
        warn "Sem ISO — VM criada sem mídia de boot. Associe a ISO manualmente no virt-manager."
    fi

    # VirtIO ISO como segundo CD se disponível
    VIRTIO_ARG=""
    if [ -f "$VIRTIO_ISO" ]; then
        VIRTIO_ARG="--disk $VIRTIO_ISO,device=cdrom,bus=sata"
    fi

    # Cria a VM com virt-install
    virt-install \
        --name "$VM_NAME" \
        --memory "$VM_RAM_MB" \
        --vcpus "$VM_VCPUS" \
        --disk "path=$VM_DISK,size=${VM_DISK_GB},bus=virtio,format=qcow2" \
        $VIRTIO_ARG \
        $CDROM_ARGS \
        $NET_ARG \
        --os-variant win11 \
        --machine q35 \
        --boot uefi \
        --features smm=on \
        --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
        --graphics spice,listen=none \
        --video qxl \
        --channel spicevmc \
        --noautoconsole \
        --print-xml > "$VM_DISK_DIR/${VM_NAME}.xml" 2>/dev/null || true

    # Tenta com virt-install (sem --boot uefi se não suportado)
    if ! virsh dominfo "$VM_NAME" &>/dev/null; then
        virt-install \
            --name "$VM_NAME" \
            --memory "$VM_RAM_MB" \
            --vcpus "$VM_VCPUS" \
            --disk "path=$VM_DISK,size=${VM_DISK_GB},bus=virtio,format=qcow2" \
            $CDROM_ARGS \
            $NET_ARG \
            --os-variant win11 \
            --machine q35 \
            --tpm backend.type=emulator,backend.version=2.0,model=tpm-crb \
            --graphics spice,listen=none \
            --video qxl \
            --noautoconsole \
            2>&1 | tee -a "$LOG_FILE" || warn "Falha na criação automática da VM."
    fi

    if virsh dominfo "$VM_NAME" &>/dev/null 2>&1; then
        ok "VM '$VM_NAME' criada com sucesso!"
        ok "Abra o virt-manager para prosseguir com a instalação do Windows 11."
    else
        warn "VM não pôde ser criada automaticamente."
        warn "Use o virt-manager para criar manualmente com as configurações do README."
    fi
}

# ════════════════════════════════════════════════════════════════
instalar_nodejs_host() {
    step "8/10" "Instalando Node.js no host (via nvm)"

    echo
    echo -e "  Node.js é necessário para rodar o Dashboard React no host Aurora."
    echo -e "  Será instalado via nvm (Node Version Manager) — não afeta o sistema."
    echo

    # Instala nvm se não existir
    if [ ! -d "$HOME/.nvm" ]; then
        echo -e "  Baixando nvm..."
        curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.7/install.sh | bash \
            2>&1 | tee -a "$LOG_FILE" | grep -E "(Downloading|Installed|nvm)" || true
        ok "nvm instalado."
    else
        ok "nvm já instalado."
    fi

    # Carrega nvm nesta sessão
    export NVM_DIR="$HOME/.nvm"
    # shellcheck source=/dev/null
    [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

    # Instala Node.js 20 LTS
    if nvm ls 20 2>/dev/null | grep -q "v20"; then
        ok "Node.js 20 LTS já instalado."
    else
        echo -e "  Instalando Node.js 20 LTS..."
        nvm install 20 2>&1 | tee -a "$LOG_FILE" | grep -E "(Downloading|Installing|Now using)" || true
        nvm use 20
        nvm alias default 20
        ok "Node.js 20 LTS instalado."
    fi

    NODE_VER=$(node --version 2>/dev/null || echo "não encontrado")
    ok "Node.js: ${NODE_VER}"
    ok "npm: $(npm --version 2>/dev/null || echo 'não encontrado')"

    # Adiciona nvm ao .bashrc e .zshrc se não existir
    for RC in "$HOME/.bashrc" "$HOME/.zshrc"; do
        if [ -f "$RC" ] && ! grep -q "NVM_DIR" "$RC"; then
            {
                echo ''
                echo '# nvm (Node Version Manager) — adicionado pelo instalador QUANT·IA'
                echo 'export NVM_DIR="$HOME/.nvm"'
                echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"'
                echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"'
            } >> "$RC"
            ok "nvm adicionado ao $RC"
        fi
    done
}

# ════════════════════════════════════════════════════════════════
configurar_dashboard() {
    step "9/10" "Configurando Dashboard React no host"

    # Carrega nvm
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && source "$NVM_DIR/nvm.sh"

    if [ ! -f "$SCRIPT_DIR/package.json" ]; then
        warn "package.json não encontrado em $SCRIPT_DIR"
        warn "Copie os arquivos do projeto para $SCRIPT_DIR e execute:"
        warn "  cd $SCRIPT_DIR && npm install"
        return
    fi

    echo -e "  Instalando dependências Node.js do Dashboard..."
    cd "$SCRIPT_DIR"
    npm install --silent 2>&1 | tee -a "$LOG_FILE" | tail -3 || \
        warn "npm install falhou — execute manualmente: cd $SCRIPT_DIR && npm install"

    if [ -d "$SCRIPT_DIR/node_modules" ]; then
        ok "Dependências Node.js instaladas."
    else
        warn "node_modules não criado — verifique o log."
    fi

    # Ajusta o IP da API no dashboard
    echo
    echo -e "  ${BOLD}Configuração do endereço da API:${RESET}"
    echo
    echo -e "  O Dashboard precisa saber onde a API FastAPI está rodando."
    echo -e "  ${DIM}(A API roda dentro da VM Windows — você precisará do IP dela)${RESET}"
    echo
    echo -e "  ${CYAN}1.${RESET}  Usar localhost (se rodar Dashboard e API na mesma máquina)"
    echo -e "  ${CYAN}2.${RESET}  Digitar o IP da VM agora (se já souber)"
    echo -e "  ${CYAN}3.${RESET}  Configurar depois manualmente no src/App.jsx"
    echo
    read -rp "  Escolha (1/2/3, padrão: 3): " IP_CHOICE

    APP_FILE="$SCRIPT_DIR/src/App.jsx"

    case "$IP_CHOICE" in
        1)
            API_HOST="localhost"
            ok "Dashboard apontado para localhost:8000"
            ;;
        2)
            read -rp "  IP da VM Windows (ex: 192.168.1.105): " VM_IP
            if [[ "$VM_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
                API_HOST="$VM_IP"
                ok "Dashboard apontado para ${VM_IP}:8000"
            else
                warn "IP inválido. Usando localhost."
                API_HOST="localhost"
            fi
            ;;
        *)
            warn "Configuração manual necessária — edite src/App.jsx:"
            info "  const API = \"http://SEU_IP_DA_VM:8000\";"
            info "  const WS  = \"ws://SEU_IP_DA_VM:8000/ws/logs\";"
            API_HOST=""
            ;;
    esac

    # Aplica o IP no App.jsx se o arquivo existir
    if [ -n "$API_HOST" ] && [ -f "$APP_FILE" ]; then
        sed -i \
            "s|const API = \"http://localhost:8000\"|const API = \"http://${API_HOST}:8000\"|g" \
            "$APP_FILE" 2>/dev/null && ok "src/App.jsx atualizado com IP: ${API_HOST}" || \
            warn "Não foi possível atualizar src/App.jsx automaticamente."

        sed -i \
            "s|const WS  = \"ws://localhost:8000|const WS  = \"ws://${API_HOST}:8000|g" \
            "$APP_FILE" 2>/dev/null || true

        # Salva para uso nos scripts
        echo "$API_HOST" > "$VM_DISK_DIR/.vm_ip"
    fi
}

# ════════════════════════════════════════════════════════════════
criar_scripts_desktop() {
    step "10/10" "Criando scripts de atalho"

    mkdir -p "$DESKTOP"

    # ── Script 1: Iniciar Dashboard ───────────────────────────────
    cat > "$DESKTOP/quant-ia-dashboard.sh" << SCRIPT
#!/bin/bash
# QUANT·IA — Iniciar Dashboard React
export NVM_DIR="\$HOME/.nvm"
[ -s "\$NVM_DIR/nvm.sh" ] && source "\$NVM_DIR/nvm.sh"
cd "$SCRIPT_DIR"
echo ""
echo "  QUANT·IA Dashboard iniciando..."
echo "  Acesse: http://localhost:5173"
echo "  Pressione Ctrl+C para parar."
echo ""
npm run dev
SCRIPT
    chmod +x "$DESKTOP/quant-ia-dashboard.sh"
    ok "quant-ia-dashboard.sh criado no Desktop"

    # ── Script 2: Abrir virt-manager ──────────────────────────────
    cat > "$DESKTOP/quant-ia-gerenciar-vm.sh" << SCRIPT
#!/bin/bash
# QUANT·IA — Abrir gerenciador de VMs
echo "  Abrindo virt-manager..."
virt-manager --connect qemu:///system &
sleep 2
echo "  Use o virt-manager para iniciar, pausar ou abrir o console da VM."
SCRIPT
    chmod +x "$DESKTOP/quant-ia-gerenciar-vm.sh"
    ok "quant-ia-gerenciar-vm.sh criado no Desktop"

    # ── Script 3: Iniciar VM Windows ──────────────────────────────
    cat > "$DESKTOP/quant-ia-iniciar-vm.sh" << SCRIPT
#!/bin/bash
# QUANT·IA — Iniciar VM Windows 11
VM="$VM_NAME"
echo ""
echo "  Iniciando VM: \$VM"

if ! systemctl is-active libvirtd &>/dev/null; then
    echo "  Iniciando libvirtd..."
    sudo systemctl start libvirtd
fi

STATUS=\$(virsh domstate "\$VM" 2>/dev/null || echo "não encontrada")

if [ "\$STATUS" == "running" ]; then
    echo "  VM já está rodando."
    echo "  Abrindo console..."
    virt-manager --connect qemu:///system --show-domain-console "\$VM" &
elif [ "\$STATUS" == "não encontrada" ]; then
    echo "  VM não encontrada. Abra o virt-manager para criar."
    virt-manager --connect qemu:///system &
else
    virsh start "\$VM" && echo "  VM iniciada com sucesso!" || echo "  Falha ao iniciar VM."
    sleep 3
    virt-manager --connect qemu:///system --show-domain-console "\$VM" &
fi
SCRIPT
    chmod +x "$DESKTOP/quant-ia-iniciar-vm.sh"
    ok "quant-ia-iniciar-vm.sh criado no Desktop"

    # ── Script 4: Parar VM com segurança ──────────────────────────
    cat > "$DESKTOP/quant-ia-parar-vm.sh" << SCRIPT
#!/bin/bash
# QUANT·IA — Parar VM Windows com segurança (shutdown gracioso)
VM="$VM_NAME"
echo ""
echo "  Enviando sinal de desligamento para: \$VM"
virsh shutdown "\$VM" && \
    echo "  VM está desligando (pode demorar ~30s)..." || \
    echo "  Falha ao enviar sinal. Use o virt-manager para forçar."
echo ""
echo "  Para forçar parada imediata: virsh destroy \$VM"
SCRIPT
    chmod +x "$DESKTOP/quant-ia-parar-vm.sh"
    ok "quant-ia-parar-vm.sh criado no Desktop"

    # ── Script 5: Normalizar CSV ───────────────────────────────────
    cat > "$DESKTOP/quant-ia-normalizar-csv.sh" << SCRIPT
#!/bin/bash
# QUANT·IA — Normalizar CSV do screener
cd "$SCRIPT_DIR"

if [ ! -d ".venv" ] && [ ! -f "utils/utils.py" ]; then
    echo "  utils/utils.py não encontrado. Certifique-se que os arquivos estão em $SCRIPT_DIR"
    read -rp "  Pressione ENTER para fechar..."
    exit 1
fi

echo ""
echo "  QUANT·IA — Normalizador de CSV"
echo "  ════════════════════════════════"
read -rp "  Caminho do CSV bruto (ex: ~/Downloads/screener.csv): " CSV_IN
CSV_IN="\${CSV_IN/#\~/$HOME}"

if [ ! -f "\$CSV_IN" ]; then
    echo "  Arquivo não encontrado: \$CSV_IN"
    read -rp "  ENTER para fechar..."
    exit 1
fi

python3 utils/utils.py "\$CSV_IN" screener_resultados.csv
echo ""
echo "  Arquivo salvo: screener_resultados.csv"
read -rp "  Pressione ENTER para fechar..."
SCRIPT
    chmod +x "$DESKTOP/quant-ia-normalizar-csv.sh"
    ok "quant-ia-normalizar-csv.sh criado no Desktop"

    # ── Script 6: Ver IP da VM ────────────────────────────────────
    cat > "$DESKTOP/quant-ia-ip-vm.sh" << SCRIPT
#!/bin/bash
# QUANT·IA — Descobre o IP da VM Windows
VM="$VM_NAME"
echo ""
echo "  Buscando IP da VM: \$VM"
echo ""

# Tenta via virsh domifaddr
IP_VIRSH=\$(virsh domifaddr "\$VM" 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | head -1)

if [ -n "\$IP_VIRSH" ]; then
    echo "  IP da VM detectado: \$IP_VIRSH"
    echo ""
    echo "  Use esse IP no src/App.jsx:"
    echo "    const API = \"http://\$IP_VIRSH:8000\";"
    echo "    const WS  = \"ws://\$IP_VIRSH:8000/ws/logs\";"
    echo "\$IP_VIRSH" > "$VM_DISK_DIR/.vm_ip"
else
    echo "  IP não detectado automaticamente."
    echo ""
    echo "  Para encontrar manualmente:"
    echo "  1. Abra o console da VM"
    echo "  2. Abra o Prompt de Comando dentro do Windows"
    echo "  3. Execute: ipconfig"
    echo "  4. Anote o 'Endereço IPv4'"
fi
echo ""
read -rp "  ENTER para fechar..."
SCRIPT
    chmod +x "$DESKTOP/quant-ia-ip-vm.sh"
    ok "quant-ia-ip-vm.sh criado no Desktop"

    # ── Cria .desktop para integração com o GNOME/KDE ─────────────
    APPS_DIR="$HOME/.local/share/applications"
    mkdir -p "$APPS_DIR"

    cat > "$APPS_DIR/quant-ia-dashboard.desktop" << DESKTOP_FILE
[Desktop Entry]
Version=1.0
Type=Application
Name=QUANT·IA Dashboard
Comment=Iniciar o Dashboard React do QUANT·IA
Exec=bash -c 'cd $SCRIPT_DIR && export NVM_DIR="$HOME/.nvm" && . "\$NVM_DIR/nvm.sh" && npm run dev; read'
Terminal=true
Icon=utilities-terminal
Categories=Finance;
DESKTOP_FILE

    cat > "$APPS_DIR/quant-ia-vm.desktop" << DESKTOP_FILE
[Desktop Entry]
Version=1.0
Type=Application
Name=QUANT·IA VM Windows
Comment=Gerenciar VM Windows do QUANT·IA
Exec=virt-manager --connect qemu:///system
Terminal=false
Icon=virt-manager
Categories=Finance;System;
DESKTOP_FILE

    chmod +x "$APPS_DIR"/*.desktop 2>/dev/null || true
    ok "Atalhos integrados ao menu de aplicativos."
}

# ════════════════════════════════════════════════════════════════
relatorio_final() {
    echo
    echo -e "${DIM}  ════════════════════════════════════════════════════════${RESET}"
    echo -e "${BOLD}  Verificação final da instalação${RESET}"
    echo -e "${DIM}  ════════════════════════════════════════════════════════${RESET}"
    echo

    TOTAL=0; PASSOU=0

    verificar_item() {
        local DESC="$1"; shift
        TOTAL=$((TOTAL+1))
        if eval "$@" &>/dev/null 2>&1; then
            ok "$DESC"
            PASSOU=$((PASSOU+1))
        else
            warn "$DESC — pendente"
        fi
    }

    verificar_item "rpm-ostree disponível"          command -v rpm-ostree
    verificar_item "KVM instalado"                  rpm -q qemu-kvm
    verificar_item "virt-manager instalado"         command -v virt-manager
    verificar_item "libvirt disponível"             command -v virsh
    verificar_item "Usuário no grupo libvirt"       id | grep -q libvirt
    verificar_item "VirtIO ISO baixado"             test -f "$VIRTIO_ISO"
    verificar_item "Pasta de VMs criada"            test -d "$VM_DISK_DIR"
    verificar_item "VM Windows criada"              virsh dominfo "$VM_NAME"
    verificar_item "nvm instalado"                  test -d "$HOME/.nvm"
    verificar_item "Node.js disponível"             bash -c '. "$HOME/.nvm/nvm.sh" && node --version'
    verificar_item "node_modules instalado"         test -d "$SCRIPT_DIR/node_modules"
    verificar_item "Scripts de atalho no Desktop"   test -f "$DESKTOP/quant-ia-dashboard.sh"

    echo
    echo -e "${DIM}  ────────────────────────────────────────────────────────${RESET}"
    echo -e "  Resultado: ${GREEN}${PASSOU}${RESET} de ${TOTAL} verificações passaram."
    echo

    log "Relatório final: $PASSOU/$TOTAL"
}

# ════════════════════════════════════════════════════════════════
tela_conclusao() {
    PRECISA_REINICIAR=${PRECISA_REINICIAR:-false}

    echo
    echo -e "${DIM}  ════════════════════════════════════════════════════════${RESET}"
    echo

    if $PRECISA_REINICIAR; then
        echo -e "  ${YELLOW}${BOLD}  ⚠   REINICIALIZAÇÃO NECESSÁRIA${RESET}"
        echo
        echo -e "  O rpm-ostree instalou os pacotes KVM em uma nova camada."
        echo -e "  ${BOLD}Você DEVE reiniciar para que o KVM seja ativado.${RESET}"
        echo
        echo -e "  ${CYAN}Após reiniciar, execute este instalador novamente:${RESET}"
        echo -e "  ${DIM}  ./instalador_aurora.sh${RESET}"
        echo -e "  ${DIM}  (As etapas já concluídas serão puladas automaticamente)${RESET}"
    else
        echo -e "  ${GREEN}${BOLD}  ✅  INSTALAÇÃO CONCLUÍDA!${RESET}"
    fi

    echo
    echo -e "${DIM}  ════════════════════════════════════════════════════════${RESET}"
    echo
    echo -e "  ${BOLD}PRÓXIMOS PASSOS:${RESET}"
    echo
    echo -e "  ${CYAN}1.${RESET}  $( $PRECISA_REINICIAR && echo "REINICIE o sistema agora" || echo "Abra o virt-manager" )"
    echo -e "  ${DIM}     Desktop → quant-ia-gerenciar-vm.sh${RESET}"
    echo
    echo -e "  ${CYAN}2.${RESET}  Inicie a VM e instale o Windows 11"
    echo -e "  ${DIM}     Desktop → quant-ia-iniciar-vm.sh${RESET}"
    echo
    echo -e "  ${CYAN}3.${RESET}  Dentro do Windows: instale os drivers VirtIO"
    echo -e "  ${DIM}     Acesse o CD-ROM D:\\ e execute virtio-win-gt-x64.exe${RESET}"
    echo
    echo -e "  ${CYAN}4.${RESET}  Dentro do Windows: siga o README_instala.md → Seção 2"
    echo -e "  ${DIM}     (instalar Python, Node.js, MT5 e rodar o instalador.bat)${RESET}"
    echo
    echo -e "  ${CYAN}5.${RESET}  Descubra o IP da VM"
    echo -e "  ${DIM}     Desktop → quant-ia-ip-vm.sh${RESET}"
    echo
    echo -e "  ${CYAN}6.${RESET}  Inicie o Dashboard no host Aurora"
    echo -e "  ${DIM}     Desktop → quant-ia-dashboard.sh${RESET}"
    echo
    echo -e "${DIM}  ════════════════════════════════════════════════════════${RESET}"
    echo
    echo -e "  ${DIM}  Log: $LOG_FILE${RESET}"
    echo -e "  ${DIM}  Documentação: README_aurora_automatizado.md${RESET}"
    echo

    if $PRECISA_REINICIAR; then
        read -rp "  Reiniciar agora? (s/N): " REBOOT_NOW
        if [[ "${REBOOT_NOW,,}" == "s" ]]; then
            echo -e "  ${YELLOW}Reiniciando em 5 segundos...${RESET}"
            sleep 5
            systemctl reboot
        fi
    else
        read -rp "  Pressione ENTER para fechar..."
    fi
}

# ════════════════════════════════════════════════════════════════
# EXECUÇÃO PRINCIPAL
# ════════════════════════════════════════════════════════════════
PRECISA_REINICIAR=false

tela_boas_vindas
verificar_sistema
instalar_kvm

# Verifica se precisa reiniciar após rpm-ostree
if ! command -v virsh &>/dev/null || ! rpm -q qemu-kvm &>/dev/null; then
    PRECISA_REINICIAR=true
fi

configurar_libvirt
configurar_rede_bridge
baixar_virtio
localizar_iso_windows

if ! $PRECISA_REINICIAR; then
    criar_vm
fi

instalar_nodejs_host
configurar_dashboard
criar_scripts_desktop
relatorio_final
tela_conclusao
