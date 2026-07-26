#!/bin/bash
# health-check.sh — Vérification complète Honcho + OpenViking
# Usage: bash health-check.sh
# Retour : ✅ ou ❌ par check. Sortie silencieuse si tout va bien.

set -e

HAS_ERROR=0

check() {
  local name="$1"
  shift
  if "$@" 2>/dev/null; then
    echo "  ✅ $name"
  else
    echo "  ❌ $name"
    HAS_ERROR=1
  fi
}

echo "=== Honcho ==="
check "4 containers Up" \
  docker ps --format '{{.Names}}' 2>/dev/null | grep -c honcho | grep -q 4

check "API health" \
  sh -c 'curl -sf --connect-timeout 2 http://localhost:8001/health | grep -q ok'

check "Provider = honcho" \
  sh -c 'grep -A3 "^memory:" ~/.hermes/config.yaml 2>/dev/null | grep -q "provider: honcho"'

echo "=== OpenViking ==="
check "Service actif" \
  systemctl is-active --quiet openviking 2>/dev/null

check "API health" \
  sh -c 'curl -sf --connect-timeout 2 http://127.0.0.1:1933/health | grep -q healthy'

check "Plugin Hermes dispo" \
  sh -c 'python3 -c "from plugins.memory.openviking import OpenVikingMemoryProvider; p = OpenVikingMemoryProvider(); assert p.is_available()" 2>/dev/null'

echo "=== Config ==="
check "honcho.json valide" \
  sh -c 'python3 -m json.tool ~/.hermes/honcho.json >/dev/null 2>&1'

check "ov.conf present" \
  test -f ~/.openviking/ov.conf

check "ovcli.conf present" \
  test -f ~/.openviking/ovcli.conf

exit $HAS_ERROR
