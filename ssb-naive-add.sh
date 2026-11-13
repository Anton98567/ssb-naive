#!/bin/bash
# ssb-naive-add — выдать только NAIVE-конфиги заказа (обёртка над ssb-3proto-add).
# Использование: ssb-naive-add ORDER-xxxxxx [count=10] [out-tag]
# Маршрутизация — как в продовом template.json (см. ssb-3proto-add).
exec /usr/local/bin/ssb-3proto-add "${1:-}" "${2:-10}" "${3:-}" NAIVE
