"""autorizacion-svc: mantiene una copia local de las fichas (ECST) y decide sin llamar a comercios-api."""
import json, os
from http.server import BaseHTTPRequestHandler, HTTPServer
from threading import Lock

PUBSUB = os.environ.get("PUBSUB", "comercios-pubsub")
TOPIC = os.environ.get("TOPIC", "estado-comercio")
fichas = {}   # merchantId -> ficha (la de mayor version)
lock = Lock()
aprobadas = rechazadas = 0


def aplicar(ficha):
    """Materialización: solo aplica versiones mayores; un estado tardío no pisa al más reciente."""
    with lock:
        actual = fichas.get(ficha["merchantId"])
        if actual is None or ficha["version"] > actual["version"]:
            fichas[ficha["merchantId"]] = ficha
            return "aplicada"
        return "descartada (version antigua)"


def decidir(merchant_id, monto):
    global aprobadas, rechazadas
    with lock:
        f = fichas.get(merchant_id)
        if f is None:
            rechazadas += 1
            return False, "sin ficha local", None
        if f["estado"] != "ACTIVO":
            rechazadas += 1
            return False, f"comercio {f['estado']}", f["version"]
        if monto > f["limiteDiario"]:
            rechazadas += 1
            return False, "supera limiteDiario", f["version"]
        aprobadas += 1
        return True, "aprobada con ficha local", f["version"]


class H(BaseHTTPRequestHandler):
    def _json(self, code, body):
        data = json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def _body(self):
        return json.loads(self.rfile.read(int(self.headers["Content-Length"])) or b"{}")

    def do_GET(self):
        if self.path == "/healthz":
            return self._json(200, {"status": "ok"})
        if self.path == "/dapr/subscribe":
            return self._json(200, [{"pubsubname": PUBSUB, "topic": TOPIC, "route": "/estado-comercio"}])
        if self.path == "/stats":
            return self._json(200, {"fichas": len(fichas), "aprobadas": aprobadas, "rechazadas": rechazadas})
        self._json(404, {"error": "no encontrado"})

    def do_POST(self):
        if self.path == "/estado-comercio":
            evento = self._body()
            ficha = evento.get("data", evento)
            resultado = aplicar(ficha)
            return self._json(200, {"status": "SUCCESS", "resultado": resultado})
        if self.path == "/transacciones":
            t = self._body()
            ok, motivo, version = decidir(t["merchantId"], t["monto"])
            return self._json(200 if ok else 403, {"aprobada": ok, "motivo": motivo, "versionFicha": version})
        self._json(404, {"error": "no encontrado"})


if __name__ == "__main__":
    HTTPServer(("0.0.0.0", 8080), H).serve_forever()
