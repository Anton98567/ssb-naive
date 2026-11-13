#!/bin/bash
# ssb-naive — установка утилит: добавление протокола Naive на ноду Secret-Sing-Box
# и выдача naive-конфигов заказа.
#
# Одна команда:
#   curl -fsSL https://raw.githubusercontent.com/Anton98567/ssb-naive/main/install.sh | bash
set -euo pipefail
BASE="https://raw.githubusercontent.com/Anton98567/ssb-naive/main"
curl -fsSL "$BASE/ssb-naive-patch.sh" -o /usr/local/bin/ssb-naive-patch
curl -fsSL "$BASE/ssb-naive-add.sh" -o /usr/local/bin/ssb-naive-add
curl -fsSL "$BASE/ssb-3proto-add.sh" -o /usr/local/bin/ssb-3proto-add
chmod 755 /usr/local/bin/ssb-naive-patch /usr/local/bin/ssb-naive-add /usr/local/bin/ssb-3proto-add
echo "Установлено:"
echo "  ssb-naive-patch apply|remove|status [порт]  — протокол Naive на ноде"
echo "  ssb-naive-add ORDER-xxxxxx [count=10] [out] — выдать naive-конфиги заказа"
echo "  ssb-3proto-add ORDER-xxxxxx [count=10] [out]— выдать VLESS+TRJ+NAIVE (3*count ссылок)"
