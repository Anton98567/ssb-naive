#!/bin/bash
# ssb-3proto-add — выдать конфиги заказа: VLESS + Trojan + Naive (по умолчанию все 3).
#
# Использование:
#   ssb-3proto-add ORDER-xxxxxx [count=10] [out-tag] [протоколы: VLESS,TRJ,NAIVE | NAIVE | ...]
#
# Маршрутизация — ТА ЖЕ, что в продовом template.json (проверено на боевых конфигах in2):
#   * порт 853 (DoT), encrypted-dns -> reject; реклама -> reject (DNS: NOERROR);
#   * MAX/VK/rostel (package_name), MAX.exe (process_name), торренты, bypass-apps,
#     android-fcm, гео-наборы (category-gov-ru, yandex, vk, mailru, ozon, zoom, reddit,
#     twitch, tumblr, pinterest, duckduckgo, yahoo, oracle, blender, drweb, debian,
#     canonical, python, doi, springer, elsevier, sciencedirect, sci-hub, duolingo),
#     рунет (.ru/.su/...) -> direct;
#   * telegram + google -> proxy; затем action:resolve -> geoip-ru -> direct;
#   * всё остальное -> proxy (правило для tun-in); DNS-сплит (ru/apps -> local, прочее -> DoT через proxy);
#   * rule-sets подтягиваются с САМОЙ ноды (секрет-каталог); если нода не отдаёт — фолбэк на GitHub.
#
# Результат: count x Nпротоколов JSON-конфигов + ссылки https://<домен>/<секрет>/<имя>-<ПРОТОКОЛ>-CLIENT.json
#   списки для тикета: /root/ssb-3proto-out/ORDER-x/links-all.txt, links-naive.txt
#   маршрут трафика — только через персональный OUT заказа (auth_user-правило).
set -uo pipefail

ORDER="${1:-}"; COUNT="${2:-10}"; OUT="${3:-}"; PROTOS="${4:-VLESS,TRJ,NAIVE}"
[[ $ORDER =~ ^ORDER-[0-9]+$ ]] || { echo "Использование: ssb-3proto-add ORDER-xxxxxx [count=10] [out-tag] [VLESS,TRJ,NAIVE]"; exit 1; }
[[ $COUNT =~ ^[0-9]+$ ]] && (( COUNT >= 1 && COUNT <= 50 )) || { echo "Ошибка: count = 1..50"; exit 1; }
PROTOS=$(echo "$PROTOS" | tr 'a-z' 'A-Z')

SBXCFG=/etc/sing-box/config.json
RELOAD="systemctl reload sing-box.service"
[[ -f $SBXCFG ]] || { echo "Ошибка: SSB не установлен"; exit 1; }

for t in trojan-in vless-in naive-in; do
    jq -e --arg t "$t" 'any(.inbounds[]; .tag == $t)' "$SBXCFG" >/dev/null 2>&1 || {
        echo "Ошибка: inbound '${t}' не найден"; exit 1; }
done

domain=$(jq -r '.inbounds[]|select(.tag=="naive-in")|.tls.server_name' "$SBXCFG")
nport=$(jq -r '.inbounds[]|select(.tag=="naive-in")|.listen_port' "$SBXCFG")
tport=443; vport=443
tws=$(jq -r '.inbounds[]|select(.tag=="trojan-in")|.transport.path // ""' "$SBXCFG")
vws=$(jq -r '.inbounds[]|select(.tag=="vless-in")|.transport.path // ""' "$SBXCFG")

[[ -z $OUT ]] && OUT="out-${ORDER#ORDER-}"
jq -e --arg t "$OUT" 'any(.outbounds[]; .tag == $t)' "$SBXCFG" >/dev/null 2>&1 || {
    echo "Ошибка: OUT-узел '${OUT}' не найден. Политика: каждому заказу — персональный OUT."; exit 1; }

rand() { head -c12 /dev/urandom | od -An -tx1 | tr -d ' \n' | head -c12; }
backup_config() {
    cp "$SBXCFG" "/root/sb-config-backup-$(date +%Y%m%d-%H%M%S).json"
    ls -1t /root/sb-config-backup-*.json 2>/dev/null | tail -n +11 | xargs -r rm -f
}

subspath=$(grep "location ~ ^/" /etc/nginx/nginx.conf 2>/dev/null | tail -n 1 | cut -d "/" -f 2 | cut -d " " -f 1)
webdir=""
[[ -n $subspath && -d /var/www/$subspath ]] && webdir="/var/www/$subspath"

# --- шаблон клиента (продовый template.json с плейсхолдерами DOMAIN/RULESETPATH) ---
TPL_B64="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"
TPL="/tmp/3proto-tpl-$$.json"
printf '%s' "$TPL_B64" | base64 -d | gunzip > "$TPL"
rulesetpath=$(grep "alias /var/www/" /etc/nginx/nginx.conf 2>/dev/null | head -n 1 | cut -d "/" -f 4)
if [[ -n $rulesetpath && -d /var/www/$rulesetpath ]]; then
    sed -i "s|RULESETPATH|${rulesetpath}|g" "$TPL"
else
    # нода не отдаёт наборы — качаем клиентом с GitHub (A-Zuro / SagerNet)
    jq '(.route.rule_set[]) |= (.url = (
          if (.tag=="torrent-clients" or .tag=="bypass-apps" or .tag=="encrypted-dns" or .tag=="android-fcm")
          then "https://raw.githubusercontent.com/A-Zuro/sb-rule-sets/main/" + (.url|split("/")|last)
          elif .tag=="geoip-ru"
          then "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs"
          else "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/" + (.url|split("/")|last)
          end))' "$TPL" > "$TPL.n" && mv "$TPL.n" "$TPL"
    echo "ВНИМАНИЕ: каталог rule-set на ноде не найден — ссылки наборов на GitHub."
fi
sed -i "s|DOMAIN|${domain}|g" "$TPL"

gen_cfg() { # $1=файл, $2=proxy-outbound (json)
    jq --argjson proxy "$2" '(.outbounds[] | select(.tag=="proxy")) = $proxy' "$TPL" > "$1"
    chmod 600 "$1"
}

OUTDIR="/root/ssb-3proto-out/${ORDER}"
mkdir -p "$OUTDIR"
chmod 700 /root/ssb-3proto-out "$OUTDIR" 2>/dev/null

echo "Выдаю ${COUNT}x$(echo "$PROTOS" | tr ',' '\n' | wc -l) конфиг(ов) [${PROTOS}] (маршрутизация как в проде): ${ORDER}, OUT '${OUT}', домен ${domain}"
backup_config

names=(); add_tj=""; add_vl=""; add_np=""
lv_all=""; lv_naive=""; lv_vless=""; lv_trj=""
for ((i = 1; i <= COUNT; i++)); do
    name="${ORDER}-$(rand)"
    trjpass="$(rand)"
    uuid=$(cat /proc/sys/kernel/random/uuid)
    npass="$(rand)"
    names+=("$name")
    add_tj+="${add_tj:+,}{\"name\":\"${name}\",\"password\":\"${trjpass}\"}"
    add_vl+="${add_vl:+,}{\"name\":\"${name}\",\"uuid\":\"${uuid}\"}"
    add_np+="${add_np:+,}{\"username\":\"${name}\",\"password\":\"${npass}\"}"

    if [[ ,$PROTOS, == *,TRJ,* ]]; then
        P=$(jq -n --arg d "$domain" --argjson p "$tport" --arg pw "$trjpass" --arg path "$tws" '
            {type:"trojan", tag:"proxy", server:$d, server_port:$p, password:$pw,
             tls:{enabled:true, server_name:$d}}
            + (if $path != "" then {transport:{type:"ws", path:$path}} else {} end)
            + {multiplex:{enabled:true, padding:true}}')
        gen_cfg "${OUTDIR}/${name}-TRJ-CLIENT.json" "$P"
    fi
    if [[ ,$PROTOS, == *,VLESS,* ]]; then
        P=$(jq -n --arg d "$domain" --argjson p "$vport" --arg u "$uuid" --arg path "$vws" '
            {type:"vless", tag:"proxy", server:$d, server_port:$p, uuid:$u,
             tls:{enabled:true, server_name:$d}}
            + (if $path != "" then {transport:{type:"ws", path:$path}} else {} end)
            + {multiplex:{enabled:true, padding:true}}')
        gen_cfg "${OUTDIR}/${name}-VLESS-CLIENT.json" "$P"
    fi
    if [[ ,$PROTOS, == *,NAIVE,* ]]; then
        P=$(jq -n --arg d "$domain" --argjson p "$nport" --arg u "$name" --arg pw "$npass" '
            {type:"naive", tag:"proxy", server:$d, server_port:$p, username:$u, password:$pw,
             tls:{enabled:true, server_name:$d}}')
        gen_cfg "${OUTDIR}/${name}-NAIVE-CLIENT.json" "$P"
    fi

    # база ссылок (после первого файла она одинакова)
    if [[ -n $webdir ]]; then
        base="https://${domain}/${subspath}"
        for f in "${OUTDIR}/${name}"-*-CLIENT.json; do
            [[ -f $f ]] || continue
            cp "$f" "${webdir}/$(basename "$f")"
            chmod 644 "${webdir}/$(basename "$f")"
        done
    else
        base="${OUTDIR}"
    fi
done

# пере-сборка ссылок с корректным base (простой проход)
lv_vless=""; lv_trj=""; lv_naive=""
for name in "${names[@]}"; do
    [[ -f ${OUTDIR}/${name}-VLESS-CLIENT.json ]] && lv_vless+="${base}/${name}-VLESS-CLIENT.json"$'\n'
    [[ -f ${OUTDIR}/${name}-TRJ-CLIENT.json ]]   && lv_trj+="${base}/${name}-TRJ-CLIENT.json"$'\n'
    [[ -f ${OUTDIR}/${name}-NAIVE-CLIENT.json ]] && lv_naive+="${base}/${name}-NAIVE-CLIENT.json"$'\n'
done

# пользователи в inbound'ах
jq --argjson u "[${add_tj}]" '(.inbounds[] | select(.tag=="trojan-in") | .users) += $u' "$SBXCFG" > /tmp/3p-$$.json && mv /tmp/3p-$$.json "$SBXCFG"
jq --argjson u "[${add_vl}]" '(.inbounds[] | select(.tag=="vless-in") | .users) += $u' "$SBXCFG" > /tmp/3p-$$.json && mv /tmp/3p-$$.json "$SBXCFG"
jq --argjson u "[${add_np}]" '(.inbounds[] | select(.tag=="naive-in") | .users) += $u' "$SBXCFG" > /tmp/3p-$$.json && mv /tmp/3p-$$.json "$SBXCFG"

# маршрут -> персональный OUT
if jq -e --arg t "$OUT" 'any(.route.rules[]; .outbound == $t and has("auth_user"))' "$SBXCFG" >/dev/null 2>&1; then
    jq --arg t "$OUT" --argjson n "$(printf '%s\n' "${names[@]}" | jq -R . | jq -s .)" '
        (.route.rules[] | select(.outbound == $t and has("auth_user")) | .auth_user) += $n' \
        "$SBXCFG" > /tmp/3p-$$.json && mv /tmp/3p-$$.json "$SBXCFG"
else
    jq --arg t "$OUT" --argjson n "$(printf '%s\n' "${names[@]}" | jq -R . | jq -s .)" '
        (.route.rules) = ((.route.rules | map(select(. != {"action":"reject"})))
          + [{"auth_user": $n, "outbound": $t}] + [{"action":"reject"}])' \
        "$SBXCFG" > /tmp/3p-$$.json && mv /tmp/3p-$$.json "$SBXCFG"
fi

rm -f "$TPL" "$TPL.n"
if sing-box check -C "$(dirname "$SBXCFG")" >/dev/null 2>&1; then
    $RELOAD 2>/dev/null; sleep 5
    systemctl is-active --quiet sing-box 2>/dev/null || systemctl is-active --quiet mbox 2>/dev/null || {
        echo "reload не поднял — restart..."; systemctl restart sing-box.service 2>/dev/null || systemctl restart mbox 2>/dev/null; sleep 8; }
else
    echo "!!! sing-box check провалился — откат"
    cp "$(ls -1t /root/sb-config-backup-*.json | head -1)" "$SBXCFG"
    exit 1
fi

lv_all="${lv_vless}${lv_trj}${lv_naive}"
printf '%s' "$lv_all"   > "${OUTDIR}/links-all.txt"
printf '%s' "$lv_naive" > "${OUTDIR}/links-naive.txt"
echo "$(date '+%F %T') order=${ORDER} 3proto-add count=${COUNT} out=${OUT} protos=${PROTOS}" >> /root/ssb-orders.log

echo
[[ -n $lv_vless ]] && { echo "=== VLESS ==="; printf '%s' "$lv_vless"; }
[[ -n $lv_trj ]]   && { echo "=== TRJ ==="; printf '%s' "$lv_trj"; }
[[ -n $lv_naive ]] && { echo "=== NAIVE ==="; printf '%s' "$lv_naive"; }
echo "=== Итого: $(printf '%s' "$lv_all" | grep -c .) ссылок, маршрут: ${ORDER} -> ${OUT} ==="
echo "Файлы и списки для тикета: ${OUTDIR}/ (links-all.txt, links-naive.txt)"
