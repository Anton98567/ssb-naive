#!/bin/bash
# ssb-naive-patch — добавить/убрать протокол Naive (HTTP/2 CONNECT, Chromium-стек)
# на существующей ноде Secret-Sing-Box.
#
# Использование:
#   ssb-naive-patch apply  [порт]   — добавить naive-in (по умолчанию 8443)
#   ssb-naive-patch remove [порт]   — убрать naive-in
#   ssb-naive-patch status          — что сейчас настроено
#
# Требования: sing-box >= 1.9 (naive inbound), LE-сертификат домена (certbot), root.
# Домен определяется автоматически: /etc/ssb-node.conf -> letsencrypt -> nginx.
# Бэкап конфига: /root/sb-config-backup-<дата>.json (держим 10 последних).
set -uo pipefail

CMD="${1:-status}"
PORT="${2:-8443}"
[[ $PORT =~ ^[0-9]+$ ]] || { echo "Ошибка: порт должен быть числом"; exit 1; }

SBXCFG=/etc/sing-box/config.json
RELOAD="systemctl reload sing-box.service"
if [[ ! -f $SBXCFG && -f /etc/mbox/config.json ]]; then
    SBXCFG=/etc/mbox/config.json
    RELOAD="systemctl restart mbox"
fi
[[ -f $SBXCFG ]] || { echo "Ошибка: SSB не установлен (нет конфига sing-box)"; exit 1; }

backup_config() {
    cp "$SBXCFG" "/root/sb-config-backup-$(date +%Y%m%d-%H%M%S).json"
    ls -1t /root/sb-config-backup-*.json 2>/dev/null | tail -n +11 | xargs -r rm -f
}

detect_domain() {
    local d=""
    [[ -f /etc/ssb-node.conf ]] && d=$(sed -n 's/^[[:space:]]*SSB_DOMAIN="\{0,1\}\([^"]*\)"\{0,1\}[[:space:]]*$/\1/p' /etc/ssb-node.conf | head -1)
    [[ -z $d ]] && d=$(ls -d /etc/letsencrypt/live/*/ 2>/dev/null | grep -v README | head -1 | xargs -r basename)
    [[ -z $d ]] && d=$(nginx -T 2>/dev/null | grep -m1 -oP 'ssl_certificate\s+/etc/letsencrypt/live/\K[^/;]+' || true)
    echo "$d"
}

reload_sbx() {
    $RELOAD 2>/dev/null
    sleep 5
    if systemctl is-active --quiet "${RELOAD##* }" 2>/dev/null || systemctl is-active --quiet sing-box 2>/dev/null; then
        echo "  сервис перезагружен ✅"
    else
        echo "  reload не прошёл — делаю restart"
        systemctl restart sing-box.service 2>/dev/null || systemctl restart mbox 2>/dev/null
        sleep 8
        systemctl is-active sing-box 2>/dev/null || systemctl is-active mbox
    fi
}

fw_open() {
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
        ufw allow "$1/tcp" >/dev/null 2>&1 && echo "  ufw: $1/tcp открыт"
    fi
    if command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -q running; then
        firewall-cmd --permanent --add-port="$1/tcp" >/dev/null 2>&1 && firewall-cmd --reload >/dev/null 2>&1 && echo "  firewalld: $1/tcp открыт"
    fi
    return 0
}

case "$CMD" in

apply)
    if jq -e 'any(.inbounds[]; .tag == "naive-in")' "$SBXCFG" >/dev/null 2>&1; then
        echo "naive-in уже добавлен (ничего не меняю). Статус:"
        exec "$0" status
    fi
    domain=$(detect_domain)
    cert="/etc/letsencrypt/live/${domain}/fullchain.pem"
    key="/etc/letsencrypt/live/${domain}/privkey.pem"
    if [[ -z $domain || ! -f $cert || ! -f $key ]]; then
        echo "Ошибка: не найден LE-сертификат домена (домен='${domain:-?}')."
        echo "  Сначала выпустите сертификат: certbot --nginx -d <домен> (или установка SSB должна была это сделать)"
        exit 1
    fi
    seed_u="seed-$(head -c8 /dev/urandom | od -An -tx1 | tr -d ' \n')"
    seed_p=$(head -c18 /dev/urandom | od -An -tx1 | tr -d ' \n')
    echo "Добавляю naive-in: порт ${PORT}/tcp, домен ${domain}"
    backup_config
    jq --arg p "$PORT" --arg d "$domain" --arg cu "$seed_u" --arg cp "$seed_p" --arg cert "$cert" --arg key "$key" '
        .inbounds += [{
            "type":"naive","tag":"naive-in","listen":"::","listen_port":($p|tonumber),
            "network":"tcp","users":[{"username":$cu,"password":$cp}],
            "tls":{"enabled":true,"server_name":$d,"certificate_path":$cert,"key_path":$key}
        }]' "$SBXCFG" > /tmp/naive-add-$$.json && mv /tmp/naive-add-$$.json "$SBXCFG"
    if sing-box check -C "$(dirname "$SBXCFG")" >/dev/null 2>&1; then
        echo "  конфиг валиден ✅"
    else
        echo "!!! sing-box check провалился — откат"
        cp "$(ls -1t /root/sb-config-backup-*.json | head -1)" "$SBXCFG"
        exit 1
    fi
    fw_open "$PORT"
    reload_sbx
    echo "Готово. Выдать конфиги заказа: ssb-naive-add ORDER-xxxxxx 10"
    ;;

remove)
    if ! jq -e 'any(.inbounds[]; .tag == "naive-in")' "$SBXCFG" >/dev/null 2>&1; then
        echo "naive-in не найден — удалять нечего."
        exit 0
    fi
    echo "Удаляю naive-in (порты и сертификат не трогаю)..."
    backup_config
    jq 'del(.inbounds[] | select(.tag == "naive-in"))' "$SBXCFG" > /tmp/naive-del-$$.json && mv /tmp/naive-del-$$.json "$SBXCFG"
    sing-box check -C "$(dirname "$SBXCFG")" >/dev/null 2>&1 || { echo "!!! check провалился — откат"; cp "$(ls -1t /root/sb-config-backup-*.json | head -1)" "$SBXCFG"; exit 1; }
    reload_sbx
    echo "Готово."
    ;;

status)
    if jq -e 'any(.inbounds[]; .tag == "naive-in")' "$SBXCFG" >/dev/null 2>&1; then
        jq -r '.inbounds[]|select(.tag=="naive-in")|
            "naive-in: ЕСТЬ\n  порт: \(.listen_port)/\(.network // "tcp")\n  домен: \(.tls.server_name)\n  юзеров: \((.users|length))\n  cert: \(.tls.certificate_path)"' "$SBXCFG"
        echo "  слушает: $(ss -tlnp 2>/dev/null | grep -c ":$(jq -r '.inbounds[]|select(.tag=="naive-in")|.listen_port' "$SBXCFG") ") процесс(ов)"
        d=$(jq -r '.inbounds[]|select(.tag=="naive-in")|.tls.server_name' "$SBXCFG")
        openssl x509 -in "/etc/letsencrypt/live/$d/fullchain.pem" -noout -enddate 2>/dev/null | sed 's/^/  /'
    else
        echo "naive-in: НЕ добавлен (ssb-naive-patch apply)"
    fi
    ;;

*)
    echo "Использование: ssb-naive-patch apply|remove|status [порт]"
    exit 1
    ;;
esac
