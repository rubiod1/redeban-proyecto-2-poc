#!/usr/bin/env bash
# Un escenario por subcomando, para ejecutarlo aparte en el video.
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
NS=comercios
C=http://comercios-api.$NS.svc.cluster.local:8080
A=http://autorizacion-svc.$NS.svc.cluster.local:8080
cli() {
  if [ "$(kubectl -n $NS get pod demo-client -o jsonpath='{.status.phase}' 2>/dev/null)" != "Running" ]; then
    kubectl -n $NS delete pod demo-client --ignore-not-found >/dev/null 2>&1
    kubectl -n $NS run demo-client --image=curlimages/curl:8.10.1 --restart=Never -- sleep 7200 >/dev/null
    kubectl -n $NS wait --for=condition=Ready pod/demo-client --timeout=180s >/dev/null
  fi
  kubectl -n $NS exec demo-client -- "$@"
}
fichas_autorizacion() { cli curl -s $A/stats 2>/dev/null | python3 -c "import sys,json;print(json.load(sys.stdin)['fichas'])" 2>/dev/null || echo 0; }
esperar_fichas() {  # espera hasta $1 fichas o 60 s
  local n=0; for _ in $(seq 1 20); do n=$(fichas_autorizacion); [ "${n:-0}" -ge "$1" ] && break; sleep 3; done; echo "$n"; }
resultado() { if [ "$1" = "0" ]; then echo "RESULTADO: OK · $2"; else echo "RESULTADO: FALLA · $2"; exit 1; fi; }

case "${1:-}" in
publicador)
  echo "== GP publicador: crea tópico, esquema, componente, Deployment y repo"
  make gp-publicador; resultado $? "recursos creados sin tickets" ;;
suscriptor)
  echo "== GP suscriptor con desde=inicio: reconstruye el estado"
  make gp-suscriptor DESDE=inicio; rc=$?
  n=$(esperar_fichas 1)
  echo "fichas en Autorización: $n"; resultado $([ $rc -eq 0 ] && [ "${n:-0}" -gt 0 ] && echo 0 || echo 1) "estado reconstruido desde el inicio" ;;
escritor)
  echo "== Escritor único: un segundo servicio intenta publicar en el mismo stream"
  .venv/bin/python gp/publicador.py --service impostor-api --owner equipo-otro --cost-center CC-9999; rc=$?
  resultado $([ $rc -ne 0 ] && echo 0 || echo 1) "segundo escritor rechazado" ;;
esquema)
  echo "== Esquema incompatible: se quita 'estado' y el GP se detiene"
  python3 -c "import json;s=json.load(open('schemas/merchant-state.avsc'));s['fields']=[f for f in s['fields'] if f['name']!='estado'];json.dump(s,open('schemas/_demo-incompatible.avsc','w'))"
  .venv/bin/python gp/publicador.py --service comercios-api --owner equipo-comercios --cost-center CC-1001 --schema schemas/_demo-incompatible.avsc; rc=$?
  rm -f schemas/_demo-incompatible.avsc
  resultado $([ $rc -ne 0 ] && echo 0 || echo 1) "409 de Apicurio, nada llega al tópico" ;;
apagado)
  echo "== ECST en acción: se apaga comercios-api"
  m="M-APAGADO-$(date +%s)"
  cli curl -s -X POST -H 'Content-Type: application/json' -d "{\"merchantId\":\"$m\",\"estado\":\"ACTIVO\",\"mcc\":\"5411\",\"limiteDiario\":500000}" $C/comercios >/dev/null
  esperar_fichas 1 >/dev/null
  sleep 3
  kubectl -n $NS scale deploy/comercios-api --replicas=0 >/dev/null && kubectl -n $NS wait --for=delete pod -l app=comercios-api --timeout=120s >/dev/null 2>&1
  echo "comercios-api apagado"
  r=$(cli curl -s -X POST -H 'Content-Type: application/json' -d "{\"merchantId\":\"$m\",\"monto\":100000}" $A/transacciones); echo "$r"
  kubectl -n $NS scale deploy/comercios-api --replicas=1 >/dev/null && kubectl -n $NS rollout status deploy/comercios-api --timeout=180s >/dev/null
  echo "comercios-api restaurado"
  echo "$r" | grep -q '"aprobada": true'; resultado $? "Autorización aprueba sin comercios-api" ;;
json)
  echo "== JSON mal formado en comercios-api"
  code=$(cli curl -s -o /dev/null -w "%{http_code}" -X POST -H 'Content-Type: application/json' -d '{"merchantId":' $C/comercios); echo "HTTP $code"
  resultado $([ "$code" = "400" ] && echo 0 || echo 1) "entrada inválida rechazada con 400" ;;
version)
  echo "== Versión antigua: una ficha tardía no pisa a la más reciente"
  m="M-VER-$(date +%s)"
  cli curl -s -X POST -H 'Content-Type: application/json' -d "{\"merchantId\":\"$m\",\"estado\":\"ACTIVO\",\"mcc\":\"5411\",\"limiteDiario\":500000,\"version\":3}" $C/comercios >/dev/null
  sleep 3
  echo "publicada v3 (limite 500000); ahora llega una v1 tardía con limite 1"
  cli curl -s -X POST -H 'Content-Type: application/json' -d "{\"merchantId\":\"$m\",\"estado\":\"ACTIVO\",\"mcc\":\"5411\",\"limiteDiario\":1,\"version\":1}" $C/comercios >/dev/null
  sleep 3
  r=$(cli curl -s -X POST -H 'Content-Type: application/json' -d "{\"merchantId\":\"$m\",\"monto\":100000}" $A/transacciones); echo "$r"
  echo "$r" | grep -q '"aprobada": true' && echo "$r" | grep -q '"versionFicha": 3'; resultado $? "se conserva la v3; la v1 tardía fue descartada" ;;
rechazo)
  echo "== Reglas de negocio: comercio suspendido y monto mayor al límite"
  s="M-SUS-$(date +%s)"; l="M-LIM-$(date +%s)"
  cli curl -s -X POST -H 'Content-Type: application/json' -d "{\"merchantId\":\"$s\",\"estado\":\"SUSPENDIDO\",\"mcc\":\"5411\",\"limiteDiario\":500000}" $C/comercios >/dev/null
  cli curl -s -X POST -H 'Content-Type: application/json' -d "{\"merchantId\":\"$l\",\"estado\":\"ACTIVO\",\"mcc\":\"5411\",\"limiteDiario\":1000}" $C/comercios >/dev/null
  sleep 4
  code1=$(cli curl -s -o /dev/null -w "%{http_code}" -X POST -H 'Content-Type: application/json' -d "{\"merchantId\":\"$s\",\"monto\":100}" $A/transacciones)
  r1=$(cli curl -s -X POST -H 'Content-Type: application/json' -d "{\"merchantId\":\"$s\",\"monto\":100}" $A/transacciones); echo "suspendido: $r1"
  r2=$(cli curl -s -X POST -H 'Content-Type: application/json' -d "{\"merchantId\":\"$l\",\"monto\":5000}" $A/transacciones); echo "monto mayor al límite: $r2"
  [ "$code1" = "403" ] && echo "$r2" | grep -q "supera limiteDiario"; resultado $? "ambas transacciones rechazadas con 403" ;;
nuevos)
  echo "== Suscriptor con desde=nuevos: no lee el historial"
  make gp-suscriptor DESDE=nuevos >/dev/null 2>&1; rc=$?
  sleep 5
  antes=$(fichas_autorizacion)
  echo "fichas al arrancar (desde=nuevos): $antes"
  m="M-NUEVO-$(date +%s)"
  cli curl -s -X POST -H 'Content-Type: application/json' -d "{\"merchantId\":\"$m\",\"estado\":\"ACTIVO\",\"mcc\":\"5411\",\"limiteDiario\":500000}" $C/comercios >/dev/null
  sleep 4
  despues=$(esperar_fichas 1)
  echo "fichas tras un evento nuevo: $despues"
  make gp-suscriptor DESDE=inicio >/dev/null 2>&1
  resultado $([ $rc -eq 0 ] && [ "$antes" = "0" ] && [ "$despues" = "1" ] && echo 0 || echo 1) "solo recibe eventos posteriores a su arranque" ;;
eventos)
  N="${2:-5}"
  echo "== Eventos en vivo: el publicador emite $N fichas y el suscriptor las recibe"
  antes=$(fichas_autorizacion)
  echo "fichas en Autorización antes: $antes"
  base="M-LIVE-$(date +%s)"
  for i in $(seq 1 "$N"); do
    cli curl -s -X POST -H 'Content-Type: application/json' \
      -d "{\"merchantId\":\"$base-$i\",\"estado\":\"ACTIVO\",\"mcc\":\"5411\",\"limiteDiario\":500000}" $C/comercios | sed "s/^/  evento $i publicado: /"; echo
  done
  despues=$(esperar_fichas $((antes + N)))
  echo "fichas en Autorización después: $despues"
  resultado $([ "${despues:-0}" -ge $((antes + N)) ] && echo 0 || echo 1) "$N eventos publicados y recibidos por el suscriptor" ;;
*) echo "uso: $0 {publicador|suscriptor|escritor|esquema|apagado|json|version|rechazo|nuevos|eventos}"; exit 2 ;;
esac
