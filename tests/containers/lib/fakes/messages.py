#!/usr/bin/env python3
"""A stand-in for the Anthropic Messages API, for the real Claude Code CLI in a test container.

    python3 messages.py --port 8765 --log /tmp/messages.jsonl [--scripts DIR] [--reply TEXT]

Point Claude at it with ANTHROPIC_BASE_URL=http://127.0.0.1:PORT and ANTHROPIC_API_KEY=dummy.
No model is called and no credential is needed.

Every request is logged (method, path, model, whether it streams, the session header, the
request's headers without credentials). Every turn is answered with REPLY as text, except a
scripted one: when a request offers tools and its session has a script with entries left, the
answer is the script's next tool call. A JSON line {"name": "Edit", "input": {...}} selects a
tool and its input; any other line is a Bash command, preserved verbatim. A session's script is
DIR/session-SESSION_ID if that file exists (Claude sends the id in X-Claude-Code-Session-Id),
else DIR/NAME when the conversation's first user message contains `[[testbed:NAME]]`. Each line
of a script is one tool call, used once per session.
"""

import argparse
import json
import re
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

SECRET_WORDS = ("key", "auth", "token", "secret")


def secret(header: str) -> bool:
    """A header that may carry a credential, by its name: logged as <redacted>."""
    return any(word in header.lower() for word in SECRET_WORDS)
MARKER = re.compile(r"\[\[testbed:([A-Za-z0-9_.-]+)\]\]")


def first_user_text(messages) -> str:
    for message in messages:
        if message.get("role") != "user":
            continue
        content = message.get("content")
        if isinstance(content, str):
            return content
        return " ".join(block.get("text", "") for block in content or [] if isinstance(block, dict))
    return ""


class Scripts:
    """Per-session scripts: which file a session uses and how far it has got."""

    def __init__(self, directory):
        self.directory = Path(directory) if directory else None
        self.position: dict[str, int] = {}
        self.lock = threading.Lock()

    def next_command(self, session: str, messages) -> str | None:
        if self.directory is None:
            return None
        path = self.directory / f"session-{session}"
        if not path.exists():
            found = MARKER.search(first_user_text(messages))
            if not found:
                return None
            path = self.directory / found.group(1)
            if not path.exists():
                return None
        lines = [line for line in path.read_text().splitlines() if line.strip()]
        with self.lock:
            key = f"{session}:{path.name}"
            index = self.position.get(key, 0)
            if index >= len(lines):
                return None
            self.position[key] = index + 1
        return lines[index]


def answered_tool(messages) -> bool:
    last = messages[-1].get("content") if messages else None
    return isinstance(last, list) and any(isinstance(b, dict) and b.get("type") == "tool_result" for b in last)


def scripted_tool(line: str) -> dict:
    """Accept a named tool with object input, keeping plain Bash scripts compatible."""
    try:
        entry = json.loads(line)
    except ValueError:
        entry = None
    if (isinstance(entry, dict) and isinstance(entry.get("name"), str) and entry["name"].strip()
            and isinstance(entry.get("input"), dict)):
        return {"name": entry["name"], "input": entry["input"]}
    return {"name": "Bash", "input": {"command": line, "description": "scripted by the testbed"}}


def make_handler(log_path: Path, reply: str, scripts: Scripts):
    log_lock = threading.Lock()

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
            self._send(200, "application/json", b'{"data": [], "has_more": false}')

        def do_HEAD(self):
            self._send(200, "application/json", b"")

        def do_POST(self):
            length = int(self.headers.get("content-length") or 0)
            try:
                request = json.loads(self.rfile.read(length) or b"{}")
            except ValueError:
                request = {}
            session = self.headers.get("X-Claude-Code-Session-Id") or ""
            headers = {k: ("<redacted>" if secret(k) else v) for k, v in self.headers.items()}
            self._log({"method": "POST", "path": self.path, "model": request.get("model"),
                       "stream": bool(request.get("stream")), "session": session, "headers": headers})
            if "count_tokens" in self.path:
                self._send(200, "application/json", b'{"input_tokens": 10}')
                return
            messages = request.get("messages") or []
            command = None
            if request.get("tools") and not answered_tool(messages):
                command = scripts.next_command(session, messages)
            if command is not None:
                self._log({"scripted": command, "session": session})
            self._answer(request, command, len(messages))

        def _answer(self, request, command, turn):
            usage = {"input_tokens": 10, "output_tokens": 3, "cache_creation_input_tokens": 0,
                     "cache_read_input_tokens": 0}
            if command is not None:
                block = {"type": "tool_use", "id": f"toolu_testbed_{turn}", **scripted_tool(command)}
                stop = "tool_use"
            else:
                block = {"type": "text", "text": reply}
                stop = "end_turn"
            message = {"id": f"msg_testbed_{turn}", "type": "message", "role": "assistant",
                       "model": request.get("model", "stand-in"), "content": [], "stop_reason": None,
                       "stop_sequence": None, "usage": usage}
            if not request.get("stream"):
                message.update(content=[block], stop_reason=stop)
                self._send(200, "application/json", json.dumps(message).encode())
                return
            events = [("message_start", {"type": "message_start", "message": message})]
            if block["type"] == "text":
                events += [("content_block_start", {"type": "content_block_start", "index": 0,
                                                    "content_block": {"type": "text", "text": ""}}),
                           ("content_block_delta", {"type": "content_block_delta", "index": 0,
                                                    "delta": {"type": "text_delta", "text": reply}})]
            else:
                events += [("content_block_start", {"type": "content_block_start", "index": 0,
                                                    "content_block": {**block, "input": {}}}),
                           ("content_block_delta", {"type": "content_block_delta", "index": 0,
                                                    "delta": {"type": "input_json_delta",
                                                              "partial_json": json.dumps(block["input"])}})]
            events += [("content_block_stop", {"type": "content_block_stop", "index": 0}),
                       ("message_delta", {"type": "message_delta",
                                          "delta": {"stop_reason": stop, "stop_sequence": None},
                                          "usage": {"output_tokens": 3}}),
                       ("message_stop", {"type": "message_stop"})]
            body = "".join(f"event: {name}\ndata: {json.dumps(data)}\n\n" for name, data in events).encode()
            self._send(200, "text/event-stream", body)

    return Handler


def serve(port: int, log_path: Path, reply="stub reply", scripts_dir=None, host="127.0.0.1"):
    server = ThreadingHTTPServer((host, port), make_handler(Path(log_path), reply, Scripts(scripts_dir)))
    server.daemon_threads = True
    return server


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--log", default="/tmp/messages.jsonl")
    parser.add_argument("--scripts")
    parser.add_argument("--reply", default="stub reply")
    args = parser.parse_args()
    serve(args.port, Path(args.log), args.reply, args.scripts).serve_forever()


if __name__ == "__main__":
    main()
