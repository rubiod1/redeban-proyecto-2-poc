#!/usr/bin/env python3
"""GP publicador: crea todo lo necesario para que un servicio publique un stream ECST.

Pasos: valida owner y cost-center -> crea el tópico compactado -> registra el .avsc con
FULL_TRANSITIVE (409 detiene el GP) -> aplica el componente de publicación con scopes del
productor y el Deployment con sidecar -> genera el repo del servicio.
"""
import argparse, json, os, shutil, subprocess, sys, time, urllib.error, urllib.request
from pathlib import Path

from fastavro import parse_schema

ROOT = Path(__file__).resolve().parent.parent
TPL = ROOT / "gp" / "templates"
OUT = ROOT / "generated"


def fail(msg):
    print(f"GP detenido: {msg}", file=sys.stderr)
    sys.exit(1)


def sh(cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kw)


def validar(args):
    for campo, valor in (("owner", args.owner), ("cost-center", args.cost_center)):
        if not valor or not valor.strip():
            fail(f"{campo} es obligatorio")
    if not args.service.replace("-", "").isalnum():
        fail("el nombre del servicio solo admite letras, números y guiones")
    schema_path = ROOT / args.schema
    if not schema_path.exists():
        fail(f"no existe el esquema {args.schema}")
    try:
        parse_schema(json.loads(schema_path.read_text()))
    except Exception as e:
        fail(f"el esquema no es Avro válido: {e}")
    print(f"[1/5] validado: owner={args.owner}, cost-center={args.cost_center}")


def verificar_escritor_unico(args):
    """Escritor único: si el componente del stream ya tiene otro productor, el GP se detiene."""
    r = subprocess.run(["kubectl", "-n", args.namespace, "get", "component", args.pubsub,
                        "-o", "jsonpath={.scopes}"], text=True, capture_output=True)
    scopes = json.loads(r.stdout) if r.returncode == 0 and r.stdout.strip() else []
    otros = [s for s in scopes if s != args.service]
    if otros:
        fail(f"escritor único: el stream ya tiene un productor ({', '.join(otros)}); {args.service} no puede publicar")
    print(f"[1b/5] escritor único verificado: {args.service} es el productor del stream")


def crear_topico(args):
    sh(["kubectl", "-n", "messaging", "exec", "deploy/kafka", "--", "/opt/kafka/bin/kafka-topics.sh",
        "--bootstrap-server", "localhost:9092", "--create", "--if-not-exists", "--topic", args.topic,
        "--partitions", "3", "--replication-factor", "1", "--config", "cleanup.policy=compact"])
    print(f"[2/5] tópico compactado listo: {args.topic}")


import contextlib


@contextlib.contextmanager
def registro_session():
    """Abre un port-forward a Apicurio y devuelve la URL base de ccompat."""
    pf = subprocess.Popen(["kubectl", "-n", "registry", "port-forward", "svc/apicurio", "18080:8080"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        for _ in range(30):
            try:
                urllib.request.urlopen("http://localhost:18080/health/ready", timeout=2)
                break
            except Exception:
                time.sleep(1)
        else:
            fail("Apicurio no responde")
        yield "http://localhost:18080/apis/ccompat/v7"
    finally:
        pf.terminate()


def registrar_esquema(args):
    schema = json.dumps(json.loads((ROOT / args.schema).read_text()))
    subject = f"{args.topic}-value"
    pf = subprocess.Popen(["kubectl", "-n", "registry", "port-forward", "svc/apicurio", "18080:8080"],
                          stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        base = "http://localhost:18080/apis/ccompat/v7"
        for _ in range(30):
            try:
                urllib.request.urlopen("http://localhost:18080/health/ready", timeout=2)
                break
            except Exception:
                time.sleep(1)
        else:
            fail("Apicurio no responde")

        def req(method, path, body=None):
            data = json.dumps(body).encode() if body is not None else None
            r = urllib.request.Request(base + path, data=data, method=method,
                                       headers={"Content-Type": "application/vnd.schemaregistry.v1+json"})
            try:
                with urllib.request.urlopen(r, timeout=10) as resp:
                    return resp.status, json.loads(resp.read() or b"{}")
            except urllib.error.HTTPError as e:
                return e.code, json.loads(e.read() or b"{}")

        req("PUT", f"/config/{subject}", {"compatibility": "FULL_TRANSITIVE"})
        code, body = req("POST", f"/subjects/{subject}/versions", {"schemaType": "AVRO", "schema": schema})
        if code == 409 or code >= 400:
            fail(f"esquema incompatible con el historial (HTTP {code}): {body}. El evento no llegará al tópico")
        print(f"[3/5] esquema registrado en {subject} con FULL_TRANSITIVE (id {body.get('id')})")
    finally:
        pf.terminate()


def render(template, **vars_):
    text = template
    for k, v in vars_.items():
        text = text.replace("${" + k + "}", v)
    return text


def aplicar_componente_y_deployment(args):
    vars_ = dict(PUBSUB=args.pubsub, NAMESPACE=args.namespace, SERVICE=args.service,
                 OWNER=args.owner, COST_CENTER=args.cost_center, IMAGE=args.image)
    comp = render((TPL / "component.yaml.tpl").read_text(), **vars_)
    dep = render((TPL / "deployment.yaml.tpl").read_text(), **vars_)
    sh_apply(comp)
    sh_apply(dep)
    sh(["kubectl", "-n", args.namespace, "rollout", "status", f"deploy/{args.service}", "--timeout=300s"])
    print(f"[4/5] componente {args.pubsub} (scope: {args.service}) y Deployment con sidecar aplicados")


def sh_apply(manifest):
    r = subprocess.run(["kubectl", "apply", "-f", "-"], input=manifest, text=True, capture_output=True)
    if r.returncode != 0:
        fail(f"kubectl apply falló: {r.stderr.strip()}")
    print(r.stdout.strip())


def generar_repo(args):
    destino = OUT / args.service
    if destino.exists():
        shutil.rmtree(destino)
    (destino / "app").mkdir(parents=True)
    shutil.copy(ROOT / "services" / "comercios-api" / "app.py", destino / "app" / "app.py")
    shutil.copy(ROOT / "services" / "comercios-api" / "requirements.txt", destino / "requirements.txt")
    shutil.copy(ROOT / args.schema, destino / "merchant-state.avsc")
    (destino / "Dockerfile").write_text(
        "FROM python:3.12-slim\nWORKDIR /app\nCOPY requirements.txt .\nRUN pip install --no-cache-dir -r requirements.txt\n"
        "COPY app/app.py .\nCOPY merchant-state.avsc /app/merchant-state.avsc\nEXPOSE 8080\nCMD [\"python\", \"app.py\"]\n")
    (destino / "README.md").write_text(
        f"# {args.service}\n\nServicio publicador generado por el GP publicador.\n\n"
        f"- Owner: {args.owner}\n- Cost-center: {args.cost_center}\n- Tópico: {args.topic}\n"
        f"- Componente Dapr: {args.pubsub} (scope: {args.service})\n\n"
        "Publica por el sidecar en `localhost:3500`. El desarrollador escribe solo la lógica del negocio.\n")
    sh(["git", "init", "-q", "-b", "main"], cwd=destino)
    print(f"[5/5] repo generado en {destino.relative_to(ROOT)}")


def main():
    p = argparse.ArgumentParser(description="GP publicador")
    p.add_argument("--service", required=True)
    p.add_argument("--owner", required=True)
    p.add_argument("--cost-center", required=True)
    p.add_argument("--topic", default="estado-comercio")
    p.add_argument("--schema", default="schemas/merchant-state.avsc")
    p.add_argument("--pubsub", default="comercios-pubsub")
    p.add_argument("--namespace", default="comercios")
    p.add_argument("--image", default="redeban/comercios-api:poc")
    args = p.parse_args()
    validar(args)
    verificar_escritor_unico(args)
    crear_topico(args)
    registrar_esquema(args)
    aplicar_componente_y_deployment(args)
    generar_repo(args)
    print("GP publicador completado")


if __name__ == "__main__":
    main()
