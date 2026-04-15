#!/bin/bash

# =============================================================================
# Dante SOCKS Proxy — автоматическая установка
# Поддерживаемые ОС: Ubuntu 22.04, Ubuntu 24.04
# =============================================================================

set -e

# Цвета
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Переменные
PROXY_PORT=1080
ALLOWED_IPS=()
CONFIG_FILE="/etc/danted.conf"

# =============================================================================

print_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║      Dante SOCKS Proxy — установка        ║"
    echo "╚═══════════════════════════════════════════╝"
    echo -e "${NC}"
}

log_info()    { echo -e "${GREEN}[✓]${NC} $1"; }
log_warn()    { echo -e "${YELLOW}[!]${NC} $1"; }
log_error()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
log_step()    { echo -e "\n${BLUE}[→]${NC} $1"; }

# =============================================================================

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "Запусти скрипт от root: sudo bash $0"
    fi
}

check_os() {
    log_step "Проверка ОС..."
    if [[ ! -f /etc/os-release ]]; then
        log_error "Не удалось определить ОС"
    fi
    source /etc/os-release
    if [[ "$ID" != "ubuntu" ]]; then
        log_warn "Скрипт тестировался на Ubuntu. Продолжаем на свой страх и риск..."
    else
        log_info "ОС: $PRETTY_NAME"
    fi
}

get_ip() {
    log_step "Определение внешнего IP..."
    SERVER_IP=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s icanhazip.com 2>/dev/null)

    if [[ -z "$SERVER_IP" ]]; then
        log_error "Не удалось определить внешний IP"
    fi
    log_info "IP сервера: $SERVER_IP"
}

ask_connection_params() {
    log_step "Параметры подключения к прокси..."

    echo ""
    echo -e "  Укажи IP-адреса клиентов, которым разрешено подключаться."
    echo -e "  Формат: одно значение на строку, можно с портом (например: 1.2.3.4 или 1.2.3.4:8080)"
    echo -e "  Можно указать подсеть: 192.168.1.0/24"
    echo -e "  ${YELLOW}Оставь пустым и нажми Enter — принимать подключения отовсюду.${NC}"
    echo ""

    local entries=()
    while true; do
        read -rp "  IP клиента (или Enter для завершения): " entry
        [[ -z "$entry" ]] && break
        entries+=("$entry")
    done

    # Парсим записи: разделяем IP и порт если указан через двоеточие
    ALLOWED_IPS=()
    for entry in "${entries[@]}"; do
        # Убираем порт если указан — Dante использует IP/маску без порта в from:
        if [[ "$entry" =~ ^([^:]+):[0-9]+$ ]]; then
            ALLOWED_IPS+=("${BASH_REMATCH[1]}")
        else
            ALLOWED_IPS+=("$entry")
        fi
    done

    echo ""
    echo -e "  Укажи порт, на котором будет слушать прокси."
    read -rp "  Порт [${PROXY_PORT}]: " input_port
    if [[ -n "$input_port" ]]; then
        if [[ "$input_port" =~ ^[0-9]+$ ]] && (( input_port >= 1 && input_port <= 65535 )); then
            PROXY_PORT="$input_port"
        else
            log_error "Некорректный порт: $input_port"
        fi
    fi

    echo ""
    if [[ ${#ALLOWED_IPS[@]} -eq 0 ]]; then
        log_info "Разрешённые клиенты: все (0.0.0.0/0)"
    else
        log_info "Разрешённые клиенты:"
        for ip in "${ALLOWED_IPS[@]}"; do
            echo -e "    ${GREEN}•${NC} $ip"
        done
    fi
    log_info "Порт прокси: $PROXY_PORT"
}

install_dante() {
    log_step "Установка Dante..."
    apt update -qq
    apt install -y dante-server -qq
    log_info "Dante установлен"
}

detect_interface() {
    # Определяем основной сетевой интерфейс
    NET_IFACE=$(ip route get 8.8.8.8 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="dev") print $(i+1)}' | head -1)
    if [[ -z "$NET_IFACE" ]]; then
        NET_IFACE="eth0"
        log_warn "Не удалось определить интерфейс, используем: $NET_IFACE"
    else
        log_info "Сетевой интерфейс: $NET_IFACE"
    fi
}

configure_dante() {
    log_step "Настройка Dante..."

    {
        echo "# Dante Configuration"
        echo "logoutput: syslog"
        echo ""
        echo "internal: 0.0.0.0 port = $PROXY_PORT"
        echo "external: $NET_IFACE"
        echo ""
        echo "method: username none"
        echo "clientmethod: none"
        echo ""
    } > "$CONFIG_FILE"

    if [[ ${#ALLOWED_IPS[@]} -eq 0 ]]; then
        {
            echo "client pass {"
            echo "    from: 0.0.0.0/0 to: 0.0.0.0/0"
            echo "}"
            echo ""
            echo "socks pass {"
            echo "    from: 0.0.0.0/0 to: 0.0.0.0/0"
            echo "}"
        } >> "$CONFIG_FILE"
    else
        for ip in "${ALLOWED_IPS[@]}"; do
            # Добавляем /32 если нет маски
            local cidr="$ip"
            [[ "$cidr" != */* ]] && cidr="${cidr}/32"
            {
                echo "client pass {"
                echo "    from: $cidr to: 0.0.0.0/0"
                echo "}"
                echo ""
                echo "socks pass {"
                echo "    from: $cidr to: 0.0.0.0/0"
                echo "}"
                echo ""
            } >> "$CONFIG_FILE"
        done
        # Блокируем остальных
        {
            echo "client block {"
            echo "    from: 0.0.0.0/0 to: 0.0.0.0/0"
            echo "}"
            echo ""
            echo "socks block {"
            echo "    from: 0.0.0.0/0 to: 0.0.0.0/0"
            echo "}"
        } >> "$CONFIG_FILE"
    fi

    log_info "Конфиг создан: $CONFIG_FILE"
}

setup_firewall() {
    log_step "Настройка файрвола..."

    if ! command -v ufw &>/dev/null; then
        log_info "Устанавливаем UFW..."
        apt install -y ufw -qq
    fi

    if [[ ${#ALLOWED_IPS[@]} -eq 0 ]]; then
        ufw allow $PROXY_PORT/tcp &>/dev/null
        log_info "Порт $PROXY_PORT/tcp открыт для всех"
    else
        for ip in "${ALLOWED_IPS[@]}"; do
            ufw allow from "$ip" to any port "$PROXY_PORT" proto tcp &>/dev/null
            log_info "Порт $PROXY_PORT/tcp открыт для $ip"
        done
    fi

    if ufw status | grep -q "Status: inactive"; then
        ufw --force enable &>/dev/null
    fi

    ufw reload &>/dev/null
}

start_dante() {
    log_step "Запуск Dante..."
    systemctl enable danted
    systemctl start danted

    sleep 2

    if systemctl is-active --quiet danted; then
        log_info "Dante запущен"
    else
        log_error "Dante не запустился. Проверь логи: journalctl -u danted"
    fi
}

print_result() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                  ✅ УСТАНОВКА ЗАВЕРШЕНА                       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BLUE}Сервер:${NC}   $SERVER_IP"
    echo -e "  ${BLUE}Порт:${NC}     $PROXY_PORT"
    if [[ ${#ALLOWED_IPS[@]} -eq 0 ]]; then
        echo -e "  ${BLUE}Доступ:${NC}   разрешён для всех"
    else
        echo -e "  ${BLUE}Доступ:${NC}   разрешён для:"
        for ip in "${ALLOWED_IPS[@]}"; do
            echo -e "            • $ip"
        done
    fi
    echo ""
    echo -e "  Полезные команды:"
    echo -e "  systemctl status danted        # статус"
    echo -e "  systemctl restart danted       # перезапуск"
    echo -e "  journalctl -u danted -f        # логи"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================

print_banner
check_root
check_os
get_ip
ask_connection_params
install_dante
detect_interface
configure_dante
setup_firewall
start_dante
print_result