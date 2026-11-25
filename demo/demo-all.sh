#!/usr/bin/env bash
# Ejecuta todas las escenas de la PoC en orden y resume el resultado.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
RES=()
escena() {  # $1 = subcomando de escenarios.sh, $2 = etiqueta
  local out rc
  out=$(./demo/escenarios.sh "$1" 2>&1); rc=$?
  if [ $rc -eq 0 ] && echo "$out" | grep -q "RESULTADO: OK"; then
    RES+=("OK      $2"); echo "[OK] $2"
  else
    RES+=("FALLA   $2"); echo "[FALLA] $2"; echo "$out" | tail -5
  fi
}
escena publicador  "GP publicador: recursos sin tickets"
escena suscriptor  "GP suscriptor: reconstruye el estado desde el inicio"
escena escritor    "escritor único: segundo escritor rechazado"
escena esquema     "esquema incompatible: 409 y GP detenido"
escena apagado     "ECST: Autorización aprueba con comercios-api apagado"
escena json        "JSON mal formado: 400"
escena version     "versión antigua: no pisa a la más reciente"
escena rechazo     "reglas de negocio: 403"
escena nuevos      "suscriptor desde=nuevos: solo eventos posteriores"
out=$(make demo-broker-redis 2>&1); rc=$?
if [ $rc -eq 0 ] && echo "$out" | grep -q "RESULTADO: el mismo código funcionó con Redis"; then
  RES+=("OK      broker Redis sin tocar código"); echo "[OK] broker Redis sin tocar código"
else
  RES+=("FALLA   broker Redis sin tocar código"); echo "[FALLA] broker Redis"
fi
echo; echo "== RESUMEN"; printf '%s\n' "${RES[@]}"
