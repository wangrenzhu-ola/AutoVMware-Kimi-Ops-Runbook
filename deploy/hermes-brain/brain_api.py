from __future__ import annotations

import json
import os
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any

STATE_PATH = Path(os.environ.get("BRAIN_STATE_PATH", "/opt/autovmware-hermes-brain/state/workers.json"))
HOST = os.environ.get("BRAIN_API_HOST", "0.0.0.0")
PORT = int(os.environ.get("BRAIN_API_PORT", "3104"))
ALLOWED_STATES = {"ready", "blocked", "lost", "need_token", "low_disk", "doctor_failed", "installed", "token_ok", "doctor_ok", "plan_ready"}
REQUIRED_HEARTBEAT_FIELDS = {
    "machine_id",
    "hostname",
    "worker_version",
    "free_space_gb",
    "kimi_token_present",
    "current_state",
}


def load_state() -> dict[str, Any]:
    if not STATE_PATH.exists():
        return {"workers": {}}
    try:
        return json.loads(STATE_PATH.read_text(encoding="utf-8"))
    except json.JSONDecodeError:
        return {"workers": {}}


def save_state(payload: dict[str, Any]) -> None:
    STATE_PATH.parent.mkdir(parents=True, exist_ok=True)
    tmp = STATE_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True), encoding="utf-8")
    tmp.replace(STATE_PATH)


def redact_worker(payload: dict[str, Any]) -> dict[str, Any]:
    redacted = dict(payload)
    for key in list(redacted):
        lowered = key.lower()
        if "token" in lowered and key != "kimi_token_present":
            redacted[key] = "[redacted]"
        if "password" in lowered or "secret" in lowered or "credential" in lowered:
            redacted[key] = "[redacted]"
    return redacted


class BrainHandler(BaseHTTPRequestHandler):
    server_version = "AutoVMwareHermesBrain/0.1"

    def log_message(self, fmt: str, *args: object) -> None:
        # Default http.server logs request paths; keep logs minimal and avoid body/secret leakage.
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)

    def send_json(self, status: int, payload: dict[str, Any]) -> None:
        body = json.dumps(payload, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802 - stdlib handler name
        if self.path == "/health":
            state = load_state()
            self.send_json(200, {"ok": True, "service": "autovmware-hermes-brain", "worker_count": len(state.get("workers", {}))})
            return
        if self.path == "/workers":
            self.send_json(200, load_state())
            return
        self.send_json(404, {"ok": False, "error": "not_found"})

    def do_POST(self) -> None:  # noqa: N802 - stdlib handler name
        if self.path != "/workers/heartbeat":
            self.send_json(404, {"ok": False, "error": "not_found"})
            return

        length = int(self.headers.get("Content-Length", "0"))
        if length <= 0 or length > 65536:
            self.send_json(400, {"ok": False, "error": "invalid_content_length"})
            return

        try:
            payload = json.loads(self.rfile.read(length).decode("utf-8"))
        except (UnicodeDecodeError, json.JSONDecodeError):
            self.send_json(400, {"ok": False, "error": "invalid_json"})
            return

        missing = sorted(REQUIRED_HEARTBEAT_FIELDS - set(payload))
        if missing:
            self.send_json(422, {"ok": False, "error": "missing_fields", "fields": missing})
            return
        if payload.get("current_state") not in ALLOWED_STATES:
            self.send_json(422, {"ok": False, "error": "invalid_state", "allowed_states": sorted(ALLOWED_STATES)})
            return

        worker = redact_worker(payload)
        worker["last_heartbeat_at"] = int(time.time())
        state = load_state()
        state.setdefault("workers", {})[str(worker["machine_id"])] = worker
        save_state(state)
        self.send_json(202, {"ok": True, "machine_id": worker["machine_id"], "accepted_state": worker["current_state"]})


if __name__ == "__main__":
    server = ThreadingHTTPServer((HOST, PORT), BrainHandler)
    print(f"brain_api listening on {HOST}:{PORT}; state={STATE_PATH}", flush=True)
    server.serve_forever()
