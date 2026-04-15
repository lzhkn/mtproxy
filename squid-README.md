# 🦑 Squid Proxy — HTTP Proxy установка

Быстрая установка HTTP прокси сервера Squid на Ubuntu.

---

## 📋 Требования

| Компонент | Минимум |
|---|---|
| ОС | Ubuntu 22.04 / 24.04 |
| RAM | 256 MB |
| CPU | 1 vCPU |
| Диск | 5 GB |
| Порт | 3128/tcp открыт |
| IP | Белый статический IPv4 |

---

## ⚡ Быстрая установка

```bash
sudo bash squid-install.sh
```

Скрипт автоматически определит IP-адрес сервера.

---

## 📖 Ручная установка

### Шаг 1 — Установка Squid

```bash
sudo apt update
sudo apt install squid
```

### Шаг 2 — Настройка конфига

Отредактируйте `/etc/squid/squid.conf`:

```
http_port 3128
acl all src 0.0.0.0/0
http_access allow all
cache deny all
```

### Шаг 3 — Запуск

```bash
sudo systemctl enable squid
sudo systemctl start squid
```

### Шаг 4 — Открыть порт

```bash
sudo ufw allow 3128/tcp
```

---

## 🔧 Использование

- **Сервер:** Ваш IP
- **Порт:** 3128
- **Тип:** HTTP Proxy

Настройте в браузере или приложении HTTP прокси на ваш IP:3128.