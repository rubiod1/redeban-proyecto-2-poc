#!/usr/bin/env python3
"""GP suscriptor: conecta un servicio de solo lectura a un stream ECST.

Pasos: valida owner y desde -> verifica el stream y su esquema -> aplica el componente de
lectura (scope del suscriptor, consumer group propio) -> despliega el suscriptor con
sidecar -> genera el repo de materialización.
"""
import argparse, json, shutil, subprocess, sys, time, urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from publicador import ROOT, TPL, OUT, fail, sh, sh_apply, render, registro_session  # noqa: E402


def validar(args):
    for campo, valor in (("owner", args.owner), ("cost-center", args.cost_center)):
        if not valor or not valor.strip():
            fail(f"{campo} es obligatorio")
    if args.desde not in ("inicio", "nuevos"):
        fail("--desde debe ser 'inicio' o 'nuevos'")
    print(f"[1/5] validado: owner={args.owner}, desde={args.desde}")


def verificar_stream(args):
    r = subprocess.run(["kubectl", "-n", "messaging", "exec", "deploy/kafka", "--", "/opt/kafka/bin/kafka-topics.sh",
                        "--bootstrap-server", "localhost:9092", "--describe", "--topic", args.stream],
                       text=True, capture_output=True)
    if r.returncode != 0 or "PartitionCount" not in r.stdout:
        fail(f"el stream {args.stream} no existe; primero corre el GP publicador")
    subject = f"{args.stream}-value"
    with registro_session() as base:
        try:
            with urllib.request.urlopen(f"{base}/subjects/{subject}/versions", timeout=10) as resp:
                versiones = json.loads(resp.read())
        except Exception:
            versiones = []
    if not versiones:
        fail(f"el esquema {subject} no está registrado")
    print(f"[2/5] stream {args.stream} verificado; esquema {subject} con versiones {versiones}")


def aplicar_lectura_y_deployment(args):
    # Grupo nuevo en cada ejecución: así desde=inicio reconstruye siempre y desde=nuevos
    # no hereda offsets de corridas anteriores.
    grupo = f"{args.service}-{args.desde}-{int(time.time())}"
    offset = "oldest" if args.desde == "inicio" else "newest"
    vars_ = dict(PUBSUB=args.pubsub, NAMESPACE=args.namespace, SERVICE=args.service, OWNER=args.owner,
                 COST_CENTER=args.cost_center, IMAGE=args.image, STREAM=args.stream,
                 CONSUMER_GROUP=grupo, INITIAL_OFFSET=offset)
    sh_apply(render((TPL / "read-component.yaml.tpl").read_text(), **vars_))
    print(f"[3/5] componente de lectura {args.pubsub} (scope: {args.service}, grupo: {grupo}, offset: {offset})")
    sh_apply(render((TPL / "subscriber-deployment.yaml.tpl").read_text(), **vars_))
    # El componente cambió pero el Deployment no: se reinicia para que el sidecar lo cargue.
    sh(["kubectl", "-n", args.namespace, "rollout", "restart", f"deploy/{args.service}"])
    sh(["kubectl", "-n", args.namespace, "rollout", "status", f"deploy/{args.service}", "--timeout=300s"])
    print(f"[4/5] suscriptor {args.service} desplegado con sidecar")


def generar_repo(args):
    destino = OUT / args.service
    if destino.exists():
        shutil.rmtree(destino)
    (destino / "app").mkdir(parents=True)
    shutil.copy(ROOT / "services" / "autorizacion-svc" / "app.py", destino / "app" / "app.py")
    (destino / "Dockerfile").write_text(
        "FROM python:3.12-slim\nWORKDIR /app\nCOPY app/app.py .\nEXPOSE 8080\nCMD [\"python\", \"app.py\"]\n")
    (destino / "README.md").write_text(
        f"# {args.service}\n\nServicio de materialización generado por el GP suscriptor.\n\n"
        f"- Owner: {args.owner}\n- Cost-center: {args.cost_center}\n- Stream: {args.stream}\n"
        f"- Componente de lectura: {args.pubsub} (scope: {args.service})\n- Desde: {args.desde}\n\n"
        "Mantiene una copia local de la ficha y decide sin llamar al productor.\n"
        "Limitación: Dapr limita qué app usa el componente, no si lee o escribe; la protección completa requiere ACL de Kafka.\n")
    sh(["git", "init", "-q", "-b", "main"], cwd=destino)
    print(f"[5/5] repo de materialización generado en {destino.relative_to(ROOT)}")


def main():
    p = argparse.ArgumentParser(description="GP suscriptor")
    p.add_argument("--service", required=True)
    p.add_argument("--stream", default="estado-comercio")
    p.add_argument("--owner", required=True)
    p.add_argument("--cost-center", required=True)
    p.add_argument("--desde", default="inicio", choices=["inicio", "nuevos"])
    p.add_argument("--pubsub", default="comercios-lectura-pubsub")
    p.add_argument("--namespace", default="comercios")
    p.add_argument("--image", default="redeban/autorizacion-svc:poc")
    args = p.parse_args()
    validar(args)
    verificar_stream(args)
    aplicar_lectura_y_deployment(args)
    generar_repo(args)
    print("GP suscriptor completado")


if __name__ == "__main__":
    main()
