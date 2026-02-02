import base64
import json
import os
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer


def build_auth_header(user, password):
    if not user:
        return {}
    token = base64.b64encode(f"{user}:{password}".encode("utf-8")).decode("utf-8")
    return {"Authorization": f"Basic {token}"}


def post_iotdb(payload):
    base_url = os.getenv("IOTDB_REST_URL", "http://iotdb:18080")
    endpoint = os.getenv("IOTDB_INSERT_ENDPOINT", "/rest/v1/insertRecord")
    url = f"{base_url}{endpoint}"
    user = os.getenv("IOTDB_USER", "root")
    password = os.getenv("IOTDB_PASS", "root")
    request_body = json.dumps(payload).encode("utf-8")
    headers = {"Content-Type": "application/json"}
    headers.update(build_auth_header(user, password))
    req = urllib.request.Request(url, data=request_body, headers=headers, method="POST")
    with urllib.request.urlopen(req, timeout=10) as response:
        return response.status, response.read().decode("utf-8")


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
        if self.path != "/ingest":
            self._send_json(404, {"error": "not_found"})
            return
        content_length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(content_length) if content_length else b"{}"
        try:
            payload = json.loads(body.decode("utf-8"))
        except json.JSONDecodeError:
            self._send_json(400, {"error": "invalid_json"})
            return
        required = ["device_id", "timestamp", "measurements", "values"]
        if not all(key in payload for key in required):
            self._send_json(400, {"error": "missing_fields", "required": required})
            return
        iotdb_payload = {
            "deviceId": payload["device_id"],
            "timestamp": payload["timestamp"],
            "measurements": payload["measurements"],
            "values": payload["values"]
        }
        if "data_types" in payload:
            iotdb_payload["dataTypes"] = payload["data_types"]
        try:
            status, response = post_iotdb(iotdb_payload)
            self._send_json(200, {"status": "forwarded", "iotdb_status": status, "iotdb_response": response})
        except Exception as exc:
            self._send_json(502, {"error": "iotdb_request_failed", "details": str(exc)})


def main():
    port = int(os.getenv("IOTDB_ADAPTER_PORT", "8089"))
    server = HTTPServer(("0.0.0.0", port), Handler)
    server.serve_forever()


if __name__ == "__main__":
    main()
