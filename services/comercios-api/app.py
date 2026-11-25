"""comercios-api: dueño de la ficha de comercio. Valida contra el esquema y publica el estado completo por Dapr."""
import json, os, time, urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer
from fastavro import parse_schema
from fastavro.validation import validate

SCHEMA = parse_schema(json.load(open(os.environ.get("SCHEMA_PATH", "/app/merchant-state.avsc"))))
PUBSUB = os.environ.get("PUBSUB", "comercios-pubsub")
TOPIC = os.environ.get("TOPIC", "estado-comercio")
DAPR = os.environ.get("DAPR_HTTP", "http://localhost:3500")
fichas = {}  # última ficha por merchantId, solo para consulta local del propio dominio


def publicar(ficha):
    url = f"{DAPR}/v1.0/publish/{PUBSUB}/{TOPIC}?metadata.partitionKey={ficha['merchantId']}"
    req = urllib.request.Request(url, data=json.dumps(ficha).encode(), method="POST",
                                 headers={"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        return r.status


class H(BaseHTTPRequestHandler):
    def _json(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == "/healthz":
            return self._json(200, {"status": "ok"})
        self._json(404, {"error": "no encontrado"})

    def do_POST(self):
        if self.path != "/comercios":
            return self._json(404, {"error": "no encontrado"})
        try:
            ficha = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"null")
        except (ValueError, TypeError):
            return self._json(400, {"error": "JSON mal formado"})
        if not isinstance(ficha, dict):
            return self._json(400, {"error": "se esperaba un objeto JSON con la ficha"})
        ficha.setdefault("version", 1)
        ficha.setdefault("actualizadoEn", int(time.time() * 1000))
        if not validate(ficha, SCHEMA, raise_errors=False):
            return self._json(422, {"error": "la ficha no cumple el esquema MerchantState"})
        status = publicar(ficha)
        fichas[ficha["merchantId"]] = ficha
        self._json(202, {"publicado": True, "dapr_status": status, "merchantId": ficha["merchantId"], "version": ficha["version"]})


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8080), H).serve_forever()
