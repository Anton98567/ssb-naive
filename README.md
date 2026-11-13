# ssb-naive

Добавление протокола **Naive (HTTP/2 CONNECT)** к ноде
[Secret-Sing-Box](https://github.com/A-Zuro/Secret-Sing-Box) + скрипт выдачи
naive-конфигов заказа (по 10 штук).

NaiveProxy — прокси поверх HTTP/2 CONNECT с настоящим TLS-стеком **Chromium**
(а не его имитацией), поэтому по сигнатуре трафик неотличим от обычного
браузерного HTTPS. Работает на TCP 8443 с LE-сертификатом домена ноды.

## Возможности

* `ssb-naive-patch` — добавить/убрать/проверить naive-in на **существующей** ноде
  без переустановки (один `apply`, конфиг с бэкапом, проверка `sing-box check`,
  reload с фолбэком на restart);
* `ssb-naive-add` — выдать **N конфигов заказа** (по умолчанию 10): пользователи,
  маршрут через персональный OUT заказа, клиентские JSON + ссылки
  `naive+https://…` для импорта;
* идемпотентность: повторный `apply` ничего не ломает; любой сбой конфига — откат
  из бэкапа.

## Установка

```bash
curl -fsSL https://raw.githubusercontent.com/Anton98567/ssb-naive/main/install.sh | bash
```

## Использование

### 1. Добавить протокол Naive на ноду

```bash
ssb-naive-patch apply          # порт 8443/tcp (по умолчанию)
ssb-naive-patch apply 2053     # или свой порт
ssb-naive-patch status         # что настроено
ssb-naive-patch remove         # убрать naive-in
```

Что делает `apply`:
1. определяет домен ноды (`/etc/ssb-node.conf` → Let's Encrypt → nginx);
2. проверяет LE-сертификат (без него откажет — naive требует настоящий TLS);
3. добавляет inbound `naive-in` (TCP, `network: tcp`, seed-пользователь);
4. открывает порт в файрволе (ufw/firewalld — если активны);
5. `sing-box check` → reload (при неудаче — restart).

### 2. Выдать 10 конфигов заказа

```bash
ssb-naive-add ORDER-123456           # 10 конфигов, OUT = out-123456
ssb-naive-add ORDER-123456 10 out-99 # явный OUT-узел
```

### 2b. Выдать 3 протокола сразу (VLESS + Trojan + Naive)

```bash
ssb-3proto-add ORDER-123456 10       # 30 конфигов: 10x3 протокола
```

Те же пользователи создаются сразу в трёх inbound'ах; на выходе — 30 JSON-ссылок
(по 10 на протокол) со сплит-маршрутизацией. Списки для тикета:
`/root/ssb-3proto-out/ORDER-123456/links-all.txt` (30) и `links-naive.txt` (10).

На выходе (каждый конфиг — **полный sing-box JSON с раздельной маршрутизацией**):
* ссылки `https://<домен>/<секрет>/<имя>-NAIVE-CLIENT.json` (секрет-каталог ноды,
  autoindex off) — или локальные файлы, если веб-выдачи нет;
* файлы — `/root/ssb-naive-out/ORDER-123456/<имя>-NAIVE-CLIENT.json`;
* трафик конфигов идёт через **персональный OUT** заказа (правило `auth_user`),
  без общих/default-цепочек.

Сплит-маршрутизация в каждом конфиге:
* реклама и encrypted-dns → reject (drop);
* торрент-клиенты, bypass-apps (банки/Госуслуги/маркетплейсы), android-fcm → direct;
* рунет (`.ru`/`.su` + geoip-ru) → direct, DNS для них — локальный;
* AI (OpenAI/Anthropic) → proxy;
* всё остальное → proxy (туннель); приватные IP → direct.
Rule-sets подтягиваются клиентом с GitHub (A-Zuro/sb-rule-sets, SagerNet).

Пример (сокращённо) клиентского конфига:

```json
{
  "log": {"level": "info", "timestamp": true},
  "dns": {
    "servers": [
      {"tag": "dns-local", "address": "local", "detour": "direct"},
      {"tag": "dns-remote", "address": "https://8.8.8.8/dns-query", "detour": "proxy"}
    ],
    "rules": [{"rule_set": ["geoip-ru", "bypass-apps", "android-fcm"], "server": "dns-local"}]
  },
  "outbounds": [
    {"type": "naive", "tag": "proxy", "server": "node.example.com", "server_port": 8443,
     "username": "ORDER-123456-abcdef123456", "password": "0a1b2c3d4e5f",
     "tls": {"enabled": true, "server_name": "node.example.com"}},
    {"type": "direct", "tag": "direct"},
    {"type": "block", "tag": "block"}
  ],
  "route": {
    "rule_set": [ "…category-ads-all, geoip-ru, torrent-clients, bypass-apps, encrypted-dns, android-fcm…" ],
    "rules": [
      {"rule_set": ["category-ads-all"], "action": "reject", "method": "drop"},
      {"rule_set": ["torrent-clients", "bypass-apps", "android-fcm"], "outbound": "direct"},
      {"rule_set": ["geoip-ru"], "outbound": "direct"},
      {"domain_suffix": [".ru", ".su"], "outbound": "direct"}
    ],
    "final": "proxy"
  }
}
```

## Требования

* sing-box >= 1.9 (inbound `naive`); проверено на 1.14.x;
* действующий Let's Encrypt сертификат домена (certbot);
* открытый TCP-порт (по умолчанию 8443);
* корневой доступ к ноде.

## Клиенты

Naive поддерживают: **Karing**, **Hiddify**, **Clash.Meta (mihomo)**, **NekoBox**,
родной клиент [naiveproxy](https://github.com/Klzgrad/naiveproxy).

## Примечания

* `ssb-naive-add` требует существующего персонального OUT-узла заказа
  (`ssb-out add …`) — это принцип архитектуры: изоляция трафика заказов;
* seed-пользователь в naive-in нужен только потому, что sing-box не принимает
  inbound с пустым списком `users`; наружу он не выдаётся;
* бэкапы конфига: `/root/sb-config-backup-*.json` (10 последних);
* журнал: `/root/ssb-orders.log`.
