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
      value: "{appID}"
    - name: disableTls
      value: "true"
