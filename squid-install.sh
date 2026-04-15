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
    read -rp "  Порт прокси [${PROXY_PORT}]: " input_port
    if [[ -n "$input_port" ]]; then
        if [[ "$input_port" =~ ^[0-9]+$ ]] && (( input_port >= 1 && input_port <= 65535 )); then
            PROXY_PORT="$input_port"
        else
            log_error "Некорректный порт: $input_port"
        fi
    fi

    echo ""
    echo -e "  IP-адреса клиентов через запятую (например: 1.2.3.4,10.0.0.0/24)"
    echo -e "  ${YELLOW}Оставь пустым — разрешить всем.${NC}"
    read -rp "  IP клиентов: " ip_input

    ALLOWED_IPS=()
    if [[ -n "$ip_input" ]]; then
        IFS=',' read -ra raw_ips <<< "$ip_input"
        for ip in "${raw_ips[@]}"; do
            ip="${ip// /}"  # убираем пробелы
            [[ -n "$ip" ]] && ALLOWED_IPS+=("$ip")
        done
    fi

    echo ""
    log_info "Порт прокси: $PROXY_PORT"
    if [[ ${#ALLOWED_IPS[@]} -eq 0 ]]; then
        log_info "Разрешённые клиенты: все (0.0.0.0/0)"
    else
        log_info "Разрешённые клиенты:"
        for ip in "${ALLOWED_IPS[@]}"; do
            echo -e "    ${GREEN}•${NC} $ip"
        done
    fi
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
                echo "acl allowed_client_$i src ${ALLOWED_IPS[$i]}"
            done
            echo ""
            for i in "${!ALLOWED_IPS[@]}"; do
                echo "http_access allow allowed_client_$i"
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