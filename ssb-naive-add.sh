#!/bin/bash
# ssb-naive-add — выдать naive-конфиги заказа (по умолчанию 10 штук).
#
# Использование:
#   ssb-naive-add ORDER-xxxxxx [count=10] [out-tag]
#
# Результат: count JSON-конфигов со сплит-маршрутизацией (как в продовом template.json),
#   ссылками через секрет-каталог ноды; маршрут — только персональный OUT заказа.
set -uo pipefail

ORDER="${1:-}"; COUNT="${2:-10}"; OUT="${3:-}"
[[ $ORDER =~ ^ORDER-[0-9]+$ ]] || { echo "Использование: ssb-naive-add ORDER-xxxxxx [count=10] [out-tag]"; exit 1; }
[[ $COUNT =~ ^[0-9]+$ ]] && (( COUNT >= 1 && COUNT <= 50 )) || { echo "Ошибка: count = 1..50"; exit 1; }

SBXCFG=/etc/sing-box/config.json
RELOAD="systemctl reload sing-box.service"
[[ -f $SBXCFG ]] || { echo "Ошибка: SSB не установлен"; exit 1; }

jq -e 'any(.inbounds[]; .tag == "naive-in")' "$SBXCFG" >/dev/null 2>&1 || {
    echo "Ошибка: naive-in не добавлен. Сначала: ssb-naive-patch apply"; exit 1; }

domain=$(jq -r '.inbounds[]|select(.tag=="naive-in")|.tls.server_name' "$SBXCFG")
nport=$(jq -r '.inbounds[]|select(.tag=="naive-in")|.listen_port' "$SBXCFG")

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
rulesetpath=$(grep "alias /var/www/" /etc/nginx/nginx.conf 2>/dev/null | head -n 1 | cut -d "/" -f 4)

# --- шаблон клиента (продовый template.json с плейсхолдерами DOMAIN/RULESETPATH) ---
TPL_B64="H4sIAAAAAAAC/+1Z3U/cOBB/569A+0xCob1+8IZUpKt0hQpa3cOpWnnt2ayJY0e2s2yK+N9v8j1ZQligOd0Dqq49j+P5/Twez8f6dm9/pkw0O9m/3dvH/4U1KBzMlswzNTsoZF4m4DxLUpR7m8He/h3KZ0K7ZpUDuwZbDP/BYSkr1uUpFKqU4bWqQsgKrGJxUMkL8d3BwDKv3MAiC4nx0ExUwMXcx7D8065QDbliBJotFIia/0EtrRbPNUug1h5GxkQKSk41KZSDN1mJkVqzySvC+NfP0jg2U7C98UI2d+AbMYo48xAZmwdMuICpatuVCpxl3EujKwgQsJQaydZzlhtR8ju/OLu8vLi8b7CU8ZhF0GykgbRZaDQkELI0nTV75iYJ17HRnsUeZ7SwRop2FpdY4zxs0eusPHJsaBwOzm2zSNgmhA20EDgOCn2SQ0/OLXOrlIn5CkkpsOXk01kMmN4ba0H7gCuJ/7jfo3SRp8zhSabpb1JYH0Ww5MkzFAqTMKnnLlsu5YZojfG2aBO6rLXzdebpMGaW0bFLjHCh7QR+BVL3JWuLWFQCfGXCxMVb64K1VAodk4qdNgs61mbNchaxX+AZlSfGcXNTRh4qxrvmbqzRUSHsmam2QAz5jbGCmGDFFrZdzzRqjEw7zrMkyUthXxT0ZeUoNda3cayWBUNCkS2oYGuYgJKdQMbyHhTOW8n62xvya1AQWZa0S2nwGvaeOnju7D7U9NRLUB5iJOmNNZJrxp8vvp5+Oe+cLBMsMr0VMYY4POEUQtmdBsa+FWCANJkWofOZIHOpShXLMS4YrXBt5xEGPRxdWnogehKmIxYaG3WOtzKpw1CQh0quYUff2egg6FxSWiYsuI4S4kiwBCLzHtOgNzxuhceR7FYIGSF3Lzm7bwguNNmAA2b5KmJkVxo2niuTCXJ5XYp4cd5R8JDKDlzJGIhnY7TqPsXv2KI7UhPHnbFvpI4JQ6PJjBILsFYSOzAMrBs0hnOP+mybBiOzDohz4R0UsGmH65jkC6nIh+YXIfPLEI9C5xGyc0F/Iz1fdcMsWShLNq/xpLCq6Y4m43HxHw0ObGW6kbGMq86YWE8g5U6jsDfQXWsBC7zXXXJj2mjJSaBIc78iOxFGdmeYWqkjohqUg3XP0ThmMg5CWuCeSoMViTUiM3hTcD9PTydSL4o7SINNpgOpd40tbXWElQxT974oy8cao6mdSuSu9stq2zSlX41fycrDWzLeljzF9Jt6EitVvH4ocznehto/ZkyI0kGbHc2OPhyHR5/CN+HR4XFbNS7FEk4EX7CTTx8/vD85OTo8On5fbulnrSbzZm5N5oHWkohpJfe9ib3SDMWyGUpHtkpPsS10K9lefSz9BZoVAaz3fVWY1lzaU6FRuCl2i3yFcx/fvXtbyTOcaKz44+rs8vz061m9pKhw6oA4+3Z6dfX3xeXnBpeU14PV9XZxXXNpvKMxzcr7dN4UZj3rVBsr5oNha5AP6PYHqvUGrDmesmUpTxI/Rs3z1p/IFlDRkmXKzwnFbUa97+okgl5mVHUAt3sPXbjWa4pwmNd1/xLNJdP1u3ajg71F1yo4LZfLwTocE5Bpbt3sXouxktd4Q4Ji7v7i2j3+eHtvmYXrLtrMEsD4VXoGlq3pQARJ59LNMZKtWf+udNeh7+iPFsi7dlBP4zl577TLbidvnZ5p8tHO6Zk6H2ycnqkPE6HNUw+idegX+8RTurNdWL82Z6/N2WBzRp2H/Lb02pm9dmbTdmaYnbkUltjz/OLz2Zdvr/3b/75/2yXh0MRXVqM75bgIjEyD7dC9C95u7eID0a73SzqldNv77X+7FjnoPxb0nwWWxiasLNcxYlneyjOrmhrenRweVsHw8PLHX2dXZ9+/nX7/83ALJrx2Rg88UVScWovtSGaB3bDNdyfT6A+ddQ+SGL6SU3ApInmwBTdKrRcVJmNUoYwSqZPvxEQqlFEiW2XBZFQanFEybZSejMY6HiXQyw2TkahQRomQrDQZjQJjlATJhpORKDBGSfSy8GQ0KpTxm0Lz/3T3pEQZJ0Irj+mIlCijRLZrnsm4tECjdO4VXJPx6ZAeyTZduTdhskGQ8VhC68zpokmJMkqkX+FOxqSGGfcVUlxP5yYFyDgNWtVPx6NEeaRm6/cTE1ZrNdB4ZKHNzHRhpUQZP6C2jZrudIwcpbDVvU3Go8EZJbPVOU5GpsEZt8xA1zqdeSjYY7RI2zwloQLmkZRYd+yTJ8QKZ7e+sHkv+a8awxrvAXKD6E3GIm8DL+7kibKHuvgxLv13hRez6al7Dh/6AvFiNkQZ4VL8ElM/zsMmBSsT0L58vi9fTDnjK5gvpYL2bbP/8ls9td7t3f0LC80bNlQqAAA="
TPL="/tmp/naive-tpl-$$.json"
printf '%s' "$TPL_B64" | base64 -d | gunzip > "$TPL"
# подстановка DOMAIN / RULESETPATH (как gen_file в ssb-add-order)
sed -i "s|DOMAIN|${domain}|g" "$TPL"
if [[ -n $rulesetpath && -d /var/www/$rulesetpath ]]; then
    sed -i "s|RULESETPATH|${rulesetpath}|g" "$TPL"
else
    echo "ВНИМАНИЕ: каталог rule-set на ноде не найден — rule-sets качаются с GitHub (медленнее)."
    sed -i "s|RULESETPATH|rulesetpath-missing|g" "$TPL"
fi

# фильтр: оставить только rule_set, которые реально доступны (нода -> GitHub fallback),
# и убрать их теги из route/dns-правил, где они не найдены
TPL_F="/tmp/naive-tplf-$$.json"
python3 - "$TPL" "$TPL_F" "$rulesetpath" "$domain" <<'PY'
import json, subprocess, sys
tpl, out, rp, domain = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]

def probe(url):
    try:
        r = subprocess.run(["curl","-sk","-o","/dev/null","-w","%{http_code}","-m","6", url],
                           capture_output=True, text=True, timeout=10)
        return r.stdout.strip() == "200"
    except Exception:
        return False

def github_url(tag, fn):
    if tag in ("torrent-clients","bypass-apps","encrypted-dns","android-fcm"):
        return "https://raw.githubusercontent.com/A-Zuro/sb-rule-sets/main/" + fn
    if tag == "geoip-ru":
        return "https://raw.githubusercontent.com/SagerNet/sing-geoip/rule-set/geoip-ru.srs"
    return "https://raw.githubusercontent.com/SagerNet/sing-geosite/rule-set/" + fn

c = json.load(open(tpl))
# node-local base (если rp пуст — только GitHub)
base_node = f"https://{domain}/{rp}/" if rp else None

available = set()
for rs in c.get("route", {}).get("rule_set", []):
    tag = rs["tag"]; fn = rs["url"].rsplit("/", 1)[-1]
    url = None
    if base_node:
        u = base_node + fn
        if probe(u): url = u
    if url is None:
        u = github_url(tag, fn)
        if probe(u): url = u
    if url is None:
        continue
    rs["url"] = url
    available.add(tag)

# убрать недоступные теги из route.rules / dns.rules
for sec in ("route", "dns"):
    if sec in c and "rules" in c[sec]:
        new = []
        for r in c[sec]["rules"]:
            if "rule_set" in r:
                r["rule_set"] = [t for t in r["rule_set"] if t in available]
                if not r["rule_set"]:
                    continue
            new.append(r)
        c[sec]["rules"] = new
# убрать недоступные из rule_set
c["route"]["rule_set"] = [rs for rs in c["route"].get("rule_set", []) if rs["tag"] in available]

json.dump(c, open(out, "w"), ensure_ascii=False, indent=1)
PY
python3 "$TPL_F" "$TPL" "$TPL_F" "$rulesetpath" "$domain" && mv "$TPL_F" "$TPL"

OUTDIR="/root/ssb-naive-out/${ORDER}"
mkdir -p "$OUTDIR"
chmod 700 /root/ssb-naive-out "$OUTDIR" 2>/dev/null

echo "Выдаю ${COUNT} NAIVE-конфиг(ов) со сплит-маршрутизацией: ${ORDER}, OUT '${OUT}', ${domain}:${nport}"
backup_config

names=(); users_json=""; links=""
for ((i = 1; i <= COUNT; i++)); do
    name="${ORDER}-$(rand)"
    pass="$(rand)"
    names+=("$name")
    users_json+="${users_json:+,}{\"username\":\"${name}\",\"password\":\"${pass}\"}"
    # proxy-outbound для naive
    proxy_json=$(jq -n --arg d "$domain" --argjson p "$nport" --arg u "$name" --arg pw "$pass" '
        {type:"naive", tag:"proxy", server:$d, server_port:$p, username:$u, password:$pw,
         tls:{enabled:true, server_name:$d}}')
    # собрать конфиг: шаблон (уже с подстановкой) + подмена proxy-outbound
    jq --argjson proxy "$proxy_json" '(.outbounds[] | select(.tag=="proxy")) = $proxy' "$TPL" > "${OUTDIR}/${name}-NAIVE-CLIENT.json"
    chmod 600 "${OUTDIR}/${name}-NAIVE-CLIENT.json"
    if [[ -n $webdir ]]; then
        cp "${OUTDIR}/${name}-NAIVE-CLIENT.json" "${webdir}/${name}-NAIVE-CLIENT.json"
        chmod 644 "${webdir}/${name}-NAIVE-CLIENT.json"
        links+="https://${domain}/${subspath}/${name}-NAIVE-CLIENT.json"$'\n'
    else
        links+="${OUTDIR}/${name}-NAIVE-CLIENT.json"$'\n'
    fi
done

# пользователи в naive-in
jq --argjson u "[${users_json}]" '(.inbounds[] | select(.tag=="naive-in") | .users) += $u' \
    "$SBXCFG" > /tmp/naive-users-$$.json && mv /tmp/naive-users-$$.json "$SBXCFG"

# маршрут -> персональный OUT
if jq -e --arg t "$OUT" 'any(.route.rules[]; .outbound == $t and has("auth_user"))' "$SBXCFG" >/dev/null 2>&1; then
    jq --arg t "$OUT" --argjson n "$(printf '%s\n' "${names[@]}" | jq -R . | jq -s .)" '
        (.route.rules[] | select(.outbound == $t and has("auth_user")) | .auth_user) += $n' \
        "$SBXCFG" > /tmp/naive-route-$$.json && mv /tmp/naive-route-$$.json "$SBXCFG"
else
    jq --arg t "$OUT" --argjson n "$(printf '%s\n' "${names[@]}" | jq -R . | jq -s .)" '
        (.route.rules) = ((.route.rules | map(select(. != {"action":"reject"})))
          + [{"auth_user": $n, "outbound": $t}] + [{"action":"reject"}])' \
        "$SBXCFG" > /tmp/naive-route-$$.json && mv /tmp/naive-route-$$.json "$SBXCFG"
fi

rm -f "$TPL"
if sing-box check -C "$(dirname "$SBXCFG")" >/dev/null 2>&1; then
    $RELOAD 2>/dev/null; sleep 5
    systemctl is-active --quiet sing-box 2>/dev/null || systemctl is-active --quiet mbox 2>/dev/null || {
        echo "reload не поднял — restart..."; systemctl restart sing-box.service 2>/dev/null || systemctl restart mbox 2>/dev/null; sleep 8; }
else
    echo "!!! sing-box check провалился — откат"
    cp "$(ls -1t /root/sb-config-backup-*.json | head -1)" "$SBXCFG"
    exit 1
fi

echo "$(date '+%F %T') order=${ORDER} naive-add count=${COUNT} out=${OUT}" >> /root/ssb-orders.log
echo
echo "=== Конфиги (JSON со сплит-маршрутизацией) ==="
printf '%s' "$links"
echo "=== Итого: ${COUNT} конфиг(ов), маршрут: ${ORDER} -> ${OUT} ==="
echo "Файлы: ${OUTDIR}/"
