# Resultado del spike de F1

- Kafka KRaft de un nodo, Apicurio Registry 3 (H2 en memoria) y Dapr 1.19.1 corren en kind.
- Un evento publicado desde el sidecar llega a `estado-comercio` (clave `merchantId`), envuelto en CloudEvents.
- Esquema `MerchantState` registrado en Apicurio con FULL_TRANSITIVE (id 1).
- Dapr con `valueSchemaType: Avro` y `schemaRegistryURL` devolvió 204, pero el registro en Kafka sigue siendo JSON. No se logró serialización Avro desde Dapr.
- Se aplica el plan B: se publica JSON y el GP valida el mensaje contra el esquema registrado antes de publicar.
- Evolución pendiente: publicar con `rawPayload` y serializar Avro en el GP.
