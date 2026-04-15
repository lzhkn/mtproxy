#!/bin/bash

# =============================================================================
# Squid Proxy — автоматическая установка
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
PROXY_PORT=3128
ALLOWED_IPS=()
CONFIG_FILE="/etc/squid/squid.conf"

# =============================================================================

print_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║        Squid Proxy — установка            ║"
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
    ALLOWED_PORTS=()
    for entry in "${entries[@]}"; do
        if [[ "$entry" =~ ^([^:]+):([0-9]+)$ ]]; then
            ALLOWED_IPS+=("${BASH_REMATCH[1]}")
            ALLOWED_PORTS+=("${BASH_REMATCH[2]}")
        else
            ALLOWED_IPS+=("$entry")
            ALLOWED_PORTS+=("")
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
        for i in "${!ALLOWED_IPS[@]}"; do
            local display="${ALLOWED_IPS[$i]}"
            [[ -n "${ALLOWED_PORTS[$i]}" ]] && display+=" (порт клиента: ${ALLOWED_PORTS[$i]})"
            echo -e "    ${GREEN}•${NC} $display"
        done
    fi
    log_info "Порт прокси: $PROXY_PORT"
}

install_squid() {
    log_step "Установка Squid..."
    apt update -qq
    apt install -y squid -qq
    log_info "Squid установлен"
}

configure_squid() {
    log_step "Настройка Squid..."
    cp "$CONFIG_FILE" "$CONFIG_FILE.bak"

    {
        echo "# Squid Configuration"
        echo "http_port $PROXY_PORT"
        echo ""
        echo "# Disable caching"
        echo "cache deny all"
        echo ""
        echo "# Logging"
        echo "access_log /var/log/squid/access.log squid"
        echo "cache_log /var/log/squid/cache.log"
        echo ""
    } > "$CONFIG_FILE"

    if [[ ${#ALLOWED_IPS[@]} -eq 0 ]]; then
        # Разрешить всем
        {
            echo "acl all src 0.0.0.0/0"
            echo "http_access allow all"
        } >> "$CONFIG_FILE"
    else
        # ACL для каждого разрешённого IP/подсети
        {
            for i in "${!ALLOWED_IPS[@]}"; do
                local ip="${ALLOWED_IPS[$i]}"
                local port="${ALLOWED_PORTS[$i]}"
                local acl_name="allowed_client_$i"
                echo "acl $acl_name src $ip"
                if [[ -n "$port" ]]; then
                    echo "acl ${acl_name}_port port $port"
                fi
            done
            echo ""
            for i in "${!ALLOWED_IPS[@]}"; do
                local acl_name="allowed_client_$i"
                local port="${ALLOWED_PORTS[$i]}"
                if [[ -n "$port" ]]; then
                    echo "http_access allow $acl_name ${acl_name}_port"
                else
                    echo "http_access allow $acl_name"
                fi
            done
            echo "http_access deny all"
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
        for i in "${!ALLOWED_IPS[@]}"; do
            local ip="${ALLOWED_IPS[$i]}"
            ufw allow from "$ip" to any port "$PROXY_PORT" proto tcp &>/dev/null
            log_info "Порт $PROXY_PORT/tcp открыт для $ip"
        done
    fi

    if ufw status | grep -q "Status: inactive"; then
        ufw --force enable &>/dev/null
    fi

    ufw reload &>/dev/null
}

start_squid() {
    log_step "Запуск Squid..."
    systemctl enable squid
    systemctl start squid

    sleep 2

    if systemctl is-active --quiet squid; then
        log_info "Squid запущен"
    else
        log_error "Squid не запустился. Проверь логи: journalctl -u squid"
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
    echo -e "  systemctl status squid             # статус"
    echo -e "  systemctl restart squid            # перезапуск"
    echo -e "  tail -f /var/log/squid/access.log  # логи"
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
install_squid
configure_squid
setup_firewall
start_squid
print_result