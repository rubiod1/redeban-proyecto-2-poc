CLUSTER ?= redeban-poc

.PHONY: help up down status build-services deploy-services gp-publicador gp-suscriptor backstage-install backstage-up demo-broker-redis demo-all setup dapr-init
.PHONY: deploy-infra demo-publicador demo-suscriptor demo-escritor demo-esquema demo-apagado demo-json demo-version demo-rechazo demo-nuevos demo-eventos

help: ## Muestra los targets disponibles
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN{FS=":.*?## "}{printf "  %-12s %s\n", $$1, $$2}'

up: ## Crea el clúster kind local
	kind create cluster --config infra/kind-config.yaml --name $(CLUSTER)
	kubectl cluster-info --context kind-$(CLUSTER)

down: ## Elimina el clúster kind
	kind delete cluster --name $(CLUSTER)

status: ## Estado del clúster y de los nodos
	kubectl get nodes -o wide

build-services: ## Construye las imágenes de comercios-api y autorizacion-svc
	docker build -f services/comercios-api/Dockerfile -t redeban/comercios-api:poc .
	docker build -f services/autorizacion-svc/Dockerfile -t redeban/autorizacion-svc:poc .
	kind load docker-image redeban/comercios-api:poc redeban/autorizacion-svc:poc --name $(CLUSTER)

deploy-services: ## Despliega los servicios en el namespace comercios
	kubectl create namespace comercios --dry-run=client -o yaml | kubectl apply -f - >/dev/null
	kubectl apply -f infra/k8s/services.yaml
	kubectl -n comercios rollout status deploy/comercios-api --timeout=300s
	kubectl -n comercios rollout status deploy/autorizacion-svc --timeout=300s

GP_VENV ?= .venv
GP_PY := $(GP_VENV)/bin/python

$(GP_PY):
	python3 -m venv $(GP_VENV)
	$(GP_VENV)/bin/pip install -q -r gp/requirements.txt

SERVICE ?= comercios-api
OWNER ?= equipo-comercios
COST_CENTER ?= CC-1001

gp-publicador: $(GP_PY) ## GP publicador: make gp-publicador SERVICE=comercios-api OWNER=... COST_CENTER=...
	$(GP_PY) gp/publicador.py --service $(SERVICE) --owner "$(OWNER)" --cost-center "$(COST_CENTER)"

DESDE ?= inicio
SUSCRIPTOR ?= autorizacion-svc

gp-suscriptor: $(GP_PY) ## GP suscriptor: make gp-suscriptor SUSCRIPTOR=autorizacion-svc DESDE=inicio|nuevos
	$(GP_PY) gp/suscriptor.py --service $(SUSCRIPTOR) --owner "$(OWNER)" --cost-center "$(COST_CENTER)" --desde $(DESDE)

NODE24_BIN ?= $(shell brew --prefix node@24 2>/dev/null)/bin

backstage-install: ## Instala dependencias de Backstage (Node 24 + Yarn 4)
	cd backstage && PATH="$(NODE24_BIN):$$PATH" yarn install

backstage-up: ## Arranca Backstage en local (http://localhost:3000)
	cd backstage && PATH="$(NODE24_BIN):$$PATH" POC_REPO_ROOT="$(CURDIR)" yarn start

demo-broker-redis: ## Demo: cambia el broker a Redis sin tocar código y restaura Kafka
	./demo/broker-redis.sh

demo-all: ## Ejecuta todas las demos de la PoC y resume el resultado
	./demo/demo-all.sh

deploy-infra: ## Kafka, Apicurio y Redis en el clúster
	kubectl create namespace messaging --dry-run=client -o yaml | kubectl apply -f - >/dev/null
	kubectl create namespace registry --dry-run=client -o yaml | kubectl apply -f - >/dev/null
	kubectl apply -f infra/k8s/kafka.yaml -f infra/k8s/apicurio.yaml -f infra/k8s/redis.yaml
	kubectl -n messaging rollout status deploy/kafka --timeout=300s
	kubectl -n registry rollout status deploy/apicurio --timeout=300s

demo-publicador: ## Escena: GP publicador (recursos sin tickets)
	./demo/escenarios.sh publicador

demo-suscriptor: ## Escena: GP suscriptor con desde=inicio
	./demo/escenarios.sh suscriptor

demo-escritor: ## Escena: un segundo escritor es rechazado
	./demo/escenarios.sh escritor

demo-esquema: ## Escena: esquema incompatible responde 409
	./demo/escenarios.sh esquema

demo-apagado: ## Escena: se apaga comercios-api y Autorización sigue aprobando
	./demo/escenarios.sh apagado

demo-json: ## Escena: JSON mal formado responde 400
	./demo/escenarios.sh json

demo-version: ## Escena: una ficha de versión antigua no pisa a la más reciente
	./demo/escenarios.sh version

demo-rechazo: ## Escena: comercio suspendido y monto mayor al límite se rechazan (403)
	./demo/escenarios.sh rechazo

demo-nuevos: ## Escena: suscriptor con desde=nuevos solo recibe eventos posteriores
	./demo/escenarios.sh nuevos

demo-eventos: ## Eventos en vivo: el publicador emite N fichas y el suscriptor las recibe (N=5)
	./demo/escenarios.sh eventos $(N)

setup: ## Instala todas las dependencias (macOS con Homebrew)
	@command -v brew >/dev/null 2>&1 || { echo "Instala Homebrew primero: https://brew.sh"; exit 1; }
	@for p in kind kubectl helm; do command -v $$p >/dev/null 2>&1 || brew install $$p; done
	@command -v dapr >/dev/null 2>&1 || brew install dapr/tap/dapr-cli
	@brew list node@24 >/dev/null 2>&1 || brew install node@24
	@docker info >/dev/null 2>&1 || echo "AVISO: abre Docker Desktop antes de make up"
	@$(MAKE) --no-print-directory $(GP_PY)
	@PATH="$(NODE24_BIN):$$PATH" corepack enable 2>/dev/null || true
	@$(MAKE) --no-print-directory backstage-install
	@echo "Dependencias listas. Siguiente: make up && make dapr-init && make deploy-infra"

dapr-init: ## Instala el runtime de Dapr 1.19.1 en el clúster
	dapr init -k --runtime-version 1.19.1 --wait --timeout 600

