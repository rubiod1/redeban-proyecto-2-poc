# Guion del video · PoC ECST (terminal)

Cada escena es un comando `make` independiente. Antes de grabar: clúster arriba y Docker encendido.

| # | Escena | Comando | Punto relevante para mostrar |
|---|---|---|---|
| 1 | GP publicador | `make demo-publicador` | Un comando crea tópico, esquema, componente, Deployment y repo, sin tickets |
| 2 | Eventos en vivo | `make demo-eventos N=5` | El publicador emite 5 fichas y el suscriptor las recibe |
| 3 | Escritor único | `make demo-escritor` | Un segundo servicio que intenta publicar en el stream es rechazado |
| 4 | Esquema incompatible | `make demo-esquema` | Quitar `estado` responde 409 y el GP se detiene; nada llega al tópico |
| 5 | Reconstrucción | `make demo-suscriptor` | El suscriptor con `desde=inicio` reconstruye el estado completo |
| 6 | Solo eventos nuevos | `make demo-nuevos` | Con `desde=nuevos` no lee el historial, solo lo que llega después |
| 7 | Versión antigua | `make demo-version` | Una ficha tardía no pisa a la más reciente |
| 8 | Reglas de negocio | `make demo-rechazo` | Comercio suspendido y monto mayor al límite se rechazan con 403 |
| 9 | ECST en acción | `make demo-apagado` | Se apaga `comercios-api` y Autorización sigue aprobando con su copia local |
| 10 | Entrada inválida | `make demo-json` | JSON mal formado responde 400 |
| 11 | Cambio de broker | `make demo-broker-redis` | El mismo código funciona con Redis; Kafka se restaura al final |

Cierre: los límites están en la presentación (consistencia eventual, Avro sobre Dapr en plan B, escritor único con ACL pendiente).
