#!/bin/bash

# =============================================================================
# MTProxy (MTProto) — автоматическая установка с FakeTLS
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
CONTAINER_NAME="mtproto-proxy"
IMAGE="nineseconds/mtg:2"
CONFIG_DIR="$HOME/mtg"
CONFIG_FILE="$CONFIG_DIR/config.toml"
EXTERNAL_PORT=443
INTERNAL_PORT=3128
DOMAIN="cloudflare.com"

# =============================================================================

print_banner() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════╗"
    echo "║     MTProxy — установка с FakeTLS         ║"
    echo "║     Образ: nineseconds/mtg:2              ║"
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

install_docker() {
    log_step "Проверка Docker..."
    if command -v docker &>/dev/null; then
        log_info "Docker уже установлен: $(docker --version)"
        return
    fi

    log_info "Устанавливаем Docker..."
    apt update -qq
    curl -fsSL https://get.docker.com | sh
    systemctl enable docker
    systemctl start docker
    log_info "Docker установлен успешно"
}

setup_firewall() {
    log_step "Настройка файрвола..."

    if ! command -v ufw &>/dev/null; then
        log_info "Устанавливаем UFW..."
        apt install -y ufw -qq
    fi

    # Разрешаем SSH чтобы не потерять доступ
    ufw allow 22/tcp &>/dev/null
    ufw allow OpenSSH &>/dev/null
    ufw allow ${EXTERNAL_PORT}/tcp &>/dev/null

    # Включаем UFW если не включён
    if ufw status | grep -q "Status: inactive"; then
        ufw --force enable &>/dev/null
    fi

    ufw reload &>/dev/null
    log_info "Порт ${EXTERNAL_PORT}/tcp открыт"
}

generate_secret() {
    log_step "Генерация FakeTLS секрета для домена: $DOMAIN"
    SECRET=$(docker run --rm $IMAGE generate-secret $DOMAIN 2>/dev/null)
    if [[ -z "$SECRET" ]]; then
        log_error "Не удалось сгенерировать секрет"
    fi
    log_info "Секрет сгенерирован: $SECRET"
}

create_config() {
    log_step "Создание конфига..."
    mkdir -p "$CONFIG_DIR"
    cat > "$CONFIG_FILE" << EOF
secret = "$SECRET"
bind-to = "0.0.0.0:${INTERNAL_PORT}"
EOF
    log_info "Конфиг создан: $CONFIG_FILE"
}

remove_existing() {
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        log_warn "Найден существующий контейнер — удаляем..."
        docker rm -f "$CONTAINER_NAME" &>/dev/null
    fi
}

start_container() {
    log_step "Запуск контейнера..."
    remove_existing

    docker run -d \
        --name "$CONTAINER_NAME" \
        --restart always \
        -p ${EXTERNAL_PORT}:${INTERNAL_PORT} \
        -v "$CONFIG_FILE:/config.toml" \
        "$IMAGE" \
        run /config.toml

    # Ждём запуска
    sleep 3

    if docker ps | grep -q "$CONTAINER_NAME"; then
        log_info "Контейнер запущен успешно"
    else
        log_error "Контейнер не запустился. Проверь логи: docker logs $CONTAINER_NAME"
    fi
}

setup_cron() {
    log_step "Настройка автообновления (cron)..."
    CRON_JOB="0 4 * * * docker restart $CONTAINER_NAME"

    # Добавляем только если ещё нет
    if ! crontab -l 2>/dev/null | grep -q "$CONTAINER_NAME"; then
        (crontab -l 2>/dev/null; echo "$CRON_JOB") | crontab -
        log_info "Cron добавлен: перезапуск каждую ночь в 4:00"
    else
        log_info "Cron уже настроен"
    fi
}

get_connection_info() {
    log_step "Получение данных для подключения..."

    # Получаем внешний IPv4
    PUBLIC_IP=$(curl -4 -s ifconfig.me 2>/dev/null || curl -4 -s icanhazip.com 2>/dev/null)

    if [[ -z "$PUBLIC_IP" ]]; then
        log_warn "Не удалось определить внешний IP автоматически"
        PUBLIC_IP="ВАШ_IP"
    fi

    TG_LINK="tg://proxy?server=${PUBLIC_IP}&port=${EXTERNAL_PORT}&secret=${SECRET}"
    TME_LINK="https://t.me/proxy?server=${PUBLIC_IP}&port=${EXTERNAL_PORT}&secret=${SECRET}"
}

print_result() {
    echo ""
    echo -e "${GREEN}╔═══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                  ✅ УСТАНОВКА ЗАВЕРШЕНА                       ║${NC}"
    echo -e "${GREEN}╚═══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    echo -e "  ${BLUE}Сервер:${NC}  $PUBLIC_IP"
    echo -e "  ${BLUE}Порт:${NC}    $EXTERNAL_PORT"
    echo -e "  ${BLUE}Секрет:${NC}  $SECRET"
    echo -e "  ${BLUE}Домен:${NC}   $DOMAIN (FakeTLS)"
    echo ""
    echo -e "  ${YELLOW}Ссылка для Telegram:${NC}"
    echo -e "  $TG_LINK"
    echo ""
    echo -e "  ${YELLOW}Ссылка t.me:${NC}"
    echo -e "  $TME_LINK"
    echo ""
    echo -e "  ${BLUE}Сохрани секрет в надёжном месте!${NC}"
    echo ""
    echo -e "  Полезные команды:"
    echo -e "  docker logs -f $CONTAINER_NAME    # логи"
    echo -e "  docker restart $CONTAINER_NAME    # перезапуск"
    echo -e "  docker rm -f $CONTAINER_NAME      # удалить"
    echo ""
}

# =============================================================================
# MAIN
# =============================================================================

print_banner
check_root
check_os
install_docker
setup_firewall
generate_secret
create_config
start_container
setup_cron
get_connection_info
print_result
