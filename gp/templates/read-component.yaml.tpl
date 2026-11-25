apiVersion: dapr.io/v1alpha1
kind: Component
metadata:
  name: ${PUBSUB}
  namespace: ${NAMESPACE}
scopes:
  - ${SERVICE}
spec:
  type: pubsub.kafka
  version: v1
  metadata:
    - name: brokers
      value: "kafka.messaging.svc.cluster.local:9092"
    - name: authType
      value: "none"
    - name: consumerGroup
      value: "${CONSUMER_GROUP}"
    - name: initialOffset
      value: "${INITIAL_OFFSET}"
    - name: disableTls
      value: "true"
