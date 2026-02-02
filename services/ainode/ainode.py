import json
import os
from http.server import BaseHTTPRequestHandler, HTTPServer


def compute_score(payload):
    fields = payload.get("fields") if isinstance(payload, dict) else None
    if not isinstance(fields, dict):
        fields = {"value": payload.get("value", 0) if isinstance(payload, dict) else 0}
    numeric_values = []
    for value in fields.values():
        if isinstance(value, (int, float)):
            numeric_values.append(float(value))
    if not numeric_values:
        return 0.0
    return sum(numeric_values) / len(numeric_values)


class Handler(BaseHTTPRequestHandler):
    def _send_json(self, status, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/healthz":
            self._send_json(200, {"status": "ok"})
            return
        self._send_json(404, {"error": "not_found"})

    def do_POST(self):
        if self.path != "/infer":
            self._send_json(404, {"error": "not_found"})
            return
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length else b"{}"
        try:
            payload = json.loads(body.decode("utf-8"))
        except json.JSONDecodeError:
            self._send_json(400, {"error": "invalid_json"})
            return
        score = compute_score(payload)
        response = {
            "device_id": payload.get("device_id", "device-1") if isinstance(payload, dict) else "device-1",
            "timestamp": payload.get("timestamp") if isinstance(payload, dict) else None,
            "score": score,
            "label": "anomaly" if score > 50 else "normal",
            "model_version": os.getenv("AINODE_MODEL_VERSION", "v0")
        }
        self._send_json(200, response)


def main():
    port = int(os.getenv("AINODE_PORT", "8090"))
    server = HTTPServer(("0.0.0.0", port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
