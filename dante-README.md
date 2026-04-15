# 👻 Dante SOCKS Proxy — SOCKS5 Proxy установка

Быстрая установка SOCKS5 прокси сервера Dante на Ubuntu.

---

## 📋 Требования

| Компонент | Минимум |
|---|---|
| ОС | Ubuntu 22.04 / 24.04 |
| RAM | 256 MB |
| CPU | 1 vCPU |
| Диск | 5 GB |
| Порт | 1080/tcp открыт |
| IP | Белый статический IPv4 |

---

## ⚡ Быстрая установка

```bash
sudo bash dante-install.sh
```

Скрипт автоматически определит IP-адрес сервера.

---

## 📖 Ручная установка

### Шаг 1 — Установка Dante

```bash
sudo apt update
sudo apt install dante-server
```

### Шаг 2 — Настройка конфига

Создайте `/etc/danted.conf`:

```
logoutput: syslog
internal: 0.0.0.0 port = 1080
external: eth0
method: username none
client pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}
socks pass {
    from: 0.0.0.0/0 to: 0.0.0.0/0
}
```

### Шаг 3 — Запуск

```bash
sudo systemctl enable danted
sudo systemctl start danted
```

### Шаг 4 — Открыть порт

```bash
sudo ufw allow 1080/tcp
```

---

## 🔧 Использование

- **Сервер:** Ваш IP
- **Порт:** 1080
- **Тип:** SOCKS5 Proxy

Настройте в приложении SOCKS5 прокси на ваш IP:1080.