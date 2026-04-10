# 🚀 MTProxy — Telegram MTProto Proxy с FakeTLS

Быстрая установка Telegram MTProto прокси на Ubuntu 24.04 с маскировкой трафика под HTTPS (FakeTLS).

---

## 📋 Требования

| Компонент | Минимум |
|---|---|
| ОС | Ubuntu 22.04 / 24.04 |
| RAM | 256 MB |
| CPU | 1 vCPU |
| Диск | 5 GB |
| Порт | 443/tcp открыт |
| IP | Белый статический IPv4 |

> **Рекомендуемые локации VPS:** Финляндия, Германия, Нидерланды — минимальный пинг из России.
> Избегай серверов в Казахстане, Азии, США — высокая задержка.

---

## ⚡ Быстрая установка

```bash
curl -fsSL https://raw.githubusercontent.com/lzhkn/mtproxy/main/install.sh | bash
```

Или вручную по шагам ниже.

---

## 📖 Ручная установка

### Шаг 1 — Установка Docker

```bash
sudo apt update && sudo apt upgrade -y
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker
```

Проверка:
```bash
docker --version
# Docker version 29.x.x
```

### Шаг 2 — Открыть порт 443

```bash
# Если UFW не установлен
sudo apt install -y ufw

sudo ufw allow 443/tcp
sudo ufw enable
sudo ufw reload
sudo ufw status
```

### Шаг 3 — Генерация FakeTLS секрета

```bash
docker run --rm nineseconds/mtg:2 generate-secret cloudflare.com
```

Пример вывода:
```
7gDW2wY-wjbLMdpgDqjoMpFjbG91ZGZsYXJlLmNvbQ
```

> Вместо `cloudflare.com` можно использовать любой крупный зарубежный HTTPS-домен:
> `microsoft.com`, `amazon.com`, `wikipedia.org`
>
> ❌ **Не используй** российские домены (.ru) — маскировка под них не эффективна.

### Шаг 4 — Создать конфиг

```bash
mkdir -p ~/mtg
cat > ~/mtg/config.toml << EOF
secret = "ВСТАВЬ_СЕКРЕТ_СЮДА"
bind-to = "0.0.0.0:3128"
EOF
```

### Шаг 5 — Запуск контейнера

```bash
docker run -d \
  --name mtproto-proxy \
  --restart always \
  -p 443:3128 \
  -v ~/mtg/config.toml:/config.toml \
  nineseconds/mtg:2 \
  run /config.toml
```

> ⚠️ **Важно:**
> - Контейнер слушает внутри на порту `3128`, Docker пробрасывает на `443`
> - Порт `3128` в UFW открывать **не нужно**
> - Правильный образ — `nineseconds/mtg:2` (не `9seconds/mtg` и не `telegrammessenger/proxy`)

### Шаг 6 — Получить данные подключения

```bash
# Узнать внешний IPv4
curl -4 ifconfig.me

# Получить ссылку (в выводе порт будет 3128 — заменить на 443 вручную!)
docker run --rm nineseconds/mtg:2 access /config.toml
```

Итоговая ссылка:
```
tg://proxy?server=ВАШ_IP&port=443&secret=ВАШ_СЕКРЕТ
```

### Шаг 7 — Настройка автообновления

```bash
(crontab -l 2>/dev/null; echo "0 4 * * * docker restart mtproto-proxy") | crontab -
crontab -l
```

---

## 📱 Подключение в Telegram

### На телефоне
Открой ссылку `tg://proxy?...` в браузере — Telegram подхватит настройки автоматически.

### Telegram Desktop
**Настройки → Продвинутые → Тип подключения → Добавить прокси**

| Поле | Значение |
|---|---|
| Тип | MTProto |
| Сервер | ВАШ_IPv4 |
| Порт | 443 |
| Секрет | ВАШ_СЕКРЕТ |

---

## 🛠 Управление

```bash
# Статус
docker ps | grep mtproto

# Логи в реальном времени
docker logs -f mtproto-proxy

# Перезапуск
docker restart mtproto-proxy

# Остановить
docker stop mtproto-proxy

# Запустить
docker start mtproto-proxy
```

---

## 🗑 Полное удаление

```bash
# Контейнер
docker rm -f mtproto-proxy

# Образ
docker rmi nineseconds/mtg:2

# Конфиг
rm -rf ~/mtg

# Порт
sudo ufw delete allow 443/tcp
sudo ufw reload

# Cron (удалить строку с docker restart)
crontab -e
```

---

## 🔥 Частые проблемы

| Проблема | Причина | Решение |
|---|---|---|
| `pull access denied` | Неверное имя образа | Использовать `nineseconds/mtg:2` |
| `Bad secret format` | Ручной секрет вместо generate-secret | Использовать `generate-secret cloudflare.com` |
| `hostname cannot be empty` | Неверный формат секрета | Пересоздать секрет через `generate-secret` |
| Telegram: «недоступен» | Неверный порт в ссылке | Заменить `3128` на `443` в ссылке |
| `address already in use` | Порт 443 занят другим сервисом | `sudo ss -tlpn \| grep 443` — найти и остановить |
| Высокий пинг (>300ms) | Далёкий сервер географически | Взять VPS в Финляндии/Германии |
| FakeTLS блокируется | Продвинутый DPI | Использовать VLESS+XTLS-Reality |

---

## 🔒 Безопасность

- MTProxy с FakeTLS маскирует трафик под HTTPS соединение с выбранным доменом
- Продвинутые DPI системы всё равно могут определить MTProxy
- Если MTProxy блокируется — следующий уровень: **VLESS+XTLS-Reality**
- Закрой все лишние порты на сервере
- Регулярно обновляй Docker образ: `docker pull nineseconds/mtg:2`

---

## 📊 Выбор локации VPS

| Локация | Пинг из Москвы | Рекомендация |
|---|---|---|
| Финляндия (Helsinki) | 20-40ms | ✅ Лучший выбор |
| Германия (Frankfurt) | 40-60ms | ✅ Хорошо |
| Нидерланды (Amsterdam) | 40-60ms | ✅ Хорошо |
| Польша (Warsaw) | 30-50ms | ✅ Хорошо |
| Казахстан (Almaty) | 80-150ms | ❌ Высокий пинг |
| США (любой) | 150-250ms | ❌ Очень высокий пинг |
