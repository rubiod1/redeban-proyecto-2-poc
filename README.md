# redeban-proyecto-2-poc

Prueba de concepto de un stream **ECST** (Event-Carried State Transfer) para Comercios → Autorización. Corre **en tu computador**, con un clúster kind.

🎞️ Presentación: https://rubiod1.github.io/redeban-proyecto-2/

## 🚀 Inicio rápido

```bash
make setup                        # 1. instala herramientas (macOS + Homebrew)
make up && make dapr-init         # 2. clúster y Dapr
make deploy-infra                 # 3. Kafka, Apicurio y Redis
make build-services deploy-services   # 4. servicios
make gp-publicador && make gp-suscriptor DESDE=inicio   # 5. Golden Paths
```

> Docker Desktop debe estar encendido antes del paso 2.

## 🎬 Escenarios

Cada escenario es un comando independiente:

| Comando | Qué demuestra |
|---|---|
| `make demo-publicador` | GP publicador: recursos creados sin tickets |
| `make demo-eventos N=5` | El publicador emite eventos y el suscriptor los recibe |
| `make demo-escritor` | Un segundo escritor es rechazado |
| `make demo-esquema` | Esquema incompatible: 409 y nada llega al tópico |
| `make demo-suscriptor` | Reconstrucción del estado desde el inicio |
| `make demo-nuevos` | Solo eventos posteriores al arranque |
| `make demo-version` | Una versión antigua no pisa a la más reciente |
| `make demo-rechazo` | Comercio suspendido y límite superado: 403 |
| `make demo-apagado` | Se apaga Comercios y Autorización sigue aprobando |
| `make demo-json` | Entrada mal formada: 400 |
| `make demo-broker-redis` | Mismo código con Redis, sin tocar las apps |

## 🧭 Golden Paths desde Backstage

```bash
make backstage-install    # solo la primera vez
make backstage-up         # abre http://localhost:3000 y entra como Guest
```

En **Create** encontrarás:
- **Golden Path · Publicar nuevo tópico**
- **Golden Path · Consumir tópico**

Cada formulario ejecuta el mismo `make` que usas en terminal.

<details>
<summary>📦 Estructura del repo</summary>

| Ruta | Contenido |
|---|---|
| `schemas/` | Contrato Avro `MerchantState` |
| `services/` | `comercios-api` y `autorizacion-svc` |
| `gp/` | Golden Paths en Python |
| `infra/` | Kubernetes y componentes de Dapr |
| `backstage/` | Portal local |
| `demo/` | Escenarios |

</details>

<details>
<summary>⚠️ Límites conocidos</summary>

- **Avro:** Dapr publica JSON dentro de CloudEvents; el GP valida contra el esquema Avro (plan B).
- **Escritor único:** el GP lo valida, pero la protección completa requiere ACL de Kafka.
- **Redis:** no compacta por clave ni reprocesa desde el inicio; el stream queda en Kafka.
- **Consistencia eventual:** Autorización decide con la última ficha recibida.

</details>
