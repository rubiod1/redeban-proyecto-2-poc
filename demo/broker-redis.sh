#!/usr/bin/env bash
# Demo: cambiar el broker de Kafka a Redis sin tocar el código de las apps.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
NS=comercios
COMERCIOS=http://comercios-api.$NS.svc.cluster.local:8080
AUTORIZA=http://autorizacion-svc.$NS.svc.cluster.local:8080

restaurar() {
  echo "== restaurando Kafka con los GP (fuente de verdad)"
  make gp-publicador >/dev/null
  make gp-suscriptor >/dev/null
  echo "== broker restaurado: Kafka"
}
trap restaurar EXIT

echo "== 1. Redis en el clúster"
kubectl apply -f infra/k8s/redis.yaml >/dev/null
kubectl -n messaging rollout status deploy/redis --timeout=180s >/dev/null

echo "== 2. componentes Dapr cambiados a pubsub.redis (mismos nombres, sin tocar apps)"
for f in infra/dapr/demo-redis/*.yaml; do kubectl apply -f "$f" >/dev/null; done
sleep 5

echo "== 3. cliente de prueba"
kubectl -n $NS get pod demo-client >/dev/null 2>&1 || kubectl -n $NS run demo-client --image=curlimages/curl:8.10.1 --restart=Never -- sleep 3600 >/dev/null
kubectl -n $NS wait --for=condition=Ready pod/demo-client --timeout=180s >/dev/null

antes=$(kubectl -n $NS exec demo-client -- curl -s $AUTORIZA/stats | python3 -c "import sys,json;print(json.load(sys.stdin)['fichas'])")
merchant="M-REDIS-$(date +%s)"
echo "== 4. publicar ficha $merchant con comercios-api (broker: Redis)"
kubectl -n $NS exec demo-client -- curl -s -X POST -H 'Content-Type: application/json' \
  -d "{\"merchantId\":\"$merchant\",\"estado\":\"ACTIVO\",\"mcc\":\"5411\",\"limiteDiario\":500000}" $COMERCIOS/comercios >/dev/null
sleep 5

despues=$(kubectl -n $NS exec demo-client -- curl -s $AUTORIZA/stats | python3 -c "import sys,json;print(json.load(sys.stdin)['fichas'])")
echo "== 5. fichas en Autorización: antes=$antes, después=$despues"
aprobada=$(kubectl -n $NS exec demo-client -- curl -s -X POST -H 'Content-Type: application/json' \
  -d "{\"merchantId\":\"$merchant\",\"monto\":100000}" $AUTORIZA/transacciones)
echo "== 6. transacción: $aprobada"

if [ "$despues" -gt "$antes" ] && echo "$aprobada" | grep -q '"aprobada": true'; then
  echo "RESULTADO: el mismo código funcionó con Redis."
else
  echo "RESULTADO: falló la prueba con Redis."; exit 1
fi
