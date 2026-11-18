#!/usr/bin/env python3
"""A stand-in for the OpenAI Responses API, for the real Codex CLI in a test container.

    python3 responses.py --port 8766 --log /tmp/responses.jsonl [--reply TEXT]

Point Codex at it with a provider in its config.toml:

    model = "stand-in"
    model_provider = "testbed"
    [model_providers.testbed]
    name = "testbed"
    base_url = "http://127.0.0.1:8766/v1"
    env_key = "TESTBED_KEY"        # any value
    wire_api = "responses"

Every request is logged (without credentials); every turn is answered with REPLY as one
assistant message. A request whose text carries `[[testbed:fail:MESSAGE]]` (a brief, say) is refused
with HTTP 400 and MESSAGE as the API's error, as the real API refuses one it cannot take. No model is
called and no credential is needed.
"""

import argparse
import json
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SECRET_WORDS = ("key", "auth", "token", "secret")
FAIL = re.compile(r"\[\[testbed:fail:(.*?)\]\]")


def secret(header: str) -> bool:
    """A header that may carry a credential, by its name: logged as <redacted>."""
    return any(word in header.lower() for word in SECRET_WORDS)


def make_handler(log_path: Path, reply: str):
    log_lock = threading.Lock()
    counter = iter(range(1, 1 << 30))

    class Handler(BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def log_message(self, *args):
            pass

        def _log(self, entry):
            with log_lock, log_path.open("a") as log:
                log.write(json.dumps(entry) + "\n")

        def _send(self, status, content_type, body: bytes):
            self.send_response(status)
            self.send_header("content-type", content_type)
            self.send_header("content-length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            self._log({"method": "GET", "path": self.path})
            self._send(200, "application/json", b'{"object": "list", "data": [], "models": []}')

        def do_POST(self):
            length = int(self.headers.get("content-length") or 0)
            try:
                request = json.loads(self.rfile.read(length) or b"{}")
            except ValueError:
                request = {}
            headers = {k: ("<redacted>" if secret(k) else v) for k, v in self.headers.items()}
            self._log({"method": "POST", "path": self.path, "model": request.get("model"), "headers": headers})
            number = next(counter)
            failure = FAIL.search(json.dumps(request))
            if failure:  # a scripted failure: the API refuses the request, as it does one it cannot take
                error = {"message": json.loads(f'"{failure.group(1)}"'), "type": "invalid_request_error",
                         "code": None, "param": None}
                self._log({"failed": error["message"]})
                self._send(400, "application/json", json.dumps({"error": error}).encode())
                return
            item = {"type": "message", "id": f"msg_testbed_{number}", "role": "assistant", "status": "completed",
                    "content": [{"type": "output_text", "text": reply, "annotations": []}]}
            usage = {"input_tokens": 10, "input_tokens_details": {"cached_tokens": 0}, "output_tokens": 2,
                     "output_tokens_details": {"reasoning_tokens": 0}, "total_tokens": 12}
            events = [{"type": "response.created", "response": {"id": f"resp_testbed_{number}"}},
                      {"type": "response.output_item.done", "output_index": 0, "item": item},
                      {"type": "response.completed", "response": {"id": f"resp_testbed_{number}", "usage": usage}}]
            body = "".join(f"event: {e['type']}\ndata: {json.dumps(e)}\n\n" for e in events).encode()
            self._send(200, "text/event-stream", body)

    return Handler


def serve(port: int, log_path: Path, reply="stub reply", host="127.0.0.1"):
    server = ThreadingHTTPServer((host, port), make_handler(Path(log_path), reply))
    server.daemon_threads = True
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=8766)
    parser.add_argument("--log", default="/tmp/responses.jsonl")
    parser.add_argument("--reply", default="stub reply")
    args = parser.parse_args()
    serve(args.port, Path(args.log), args.reply).serve_forever()


if __name__ == "__main__":
    main()
