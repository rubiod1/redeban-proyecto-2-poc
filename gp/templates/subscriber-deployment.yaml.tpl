apiVersion: apps/v1
kind: Deployment
metadata:
  name: ${SERVICE}
  namespace: ${NAMESPACE}
  labels:
    owner: "${OWNER}"
    cost-center: "${COST_CENTER}"
spec:
  replicas: 1
  # Recreate: el pod viejo termina antes de arrancar el nuevo, para que dos consumidores
  # del mismo grupo no se pisen los offsets.
  strategy:
    type: Recreate
  selector:
    matchLabels: {app: ${SERVICE}}
  template:
    metadata:
      labels: {app: ${SERVICE}, owner: "${OWNER}", cost-center: "${COST_CENTER}"}
      annotations:
        dapr.io/enabled: "true"
        dapr.io/app-id: "${SERVICE}"
        dapr.io/app-port: "8080"
    spec:
      containers:
        - name: app
          image: ${IMAGE}
          imagePullPolicy: IfNotPresent
          env:
            - {name: PUBSUB, value: "${PUBSUB}"}
            - {name: TOPIC, value: "${STREAM}"}
          ports: [{containerPort: 8080}]
