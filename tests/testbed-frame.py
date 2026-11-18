#!/usr/bin/env python3
"""The container testbed's frame, without Docker: its refusals, its result format and its stand-ins.

The scenarios themselves need Docker and run separately (tests/containers/README.md).
"""

import importlib.util
import json
import subprocess
import sys
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
CONTAINERS = ROOT / "tests" / "containers"
sys.path.insert(0, str(CONTAINERS))
sys.path.insert(0, str(CONTAINERS / "scenarios"))  # their shared helpers (`_install`)

from lib import results  # noqa: E402
from lib.container import Container, Docker, ExecFailed, Refused, check_input, check_mount, check_network  # noqa: E402
from lib.fakes import messages, responses  # noqa: E402


def load(path: Path):
    spec = importlib.util.spec_from_file_location(path.stem, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class Refusals(unittest.TestCase):
    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="testbed-frame-"))
        self.home = self.tmp / "home"
        (self.home / "work").mkdir(parents=True)
        self.input = self.home / "work" / "repo.bundle"
        self.input.write_text("bundle")

    def tearDown(self):
        subprocess.run(["rm", "-rf", str(self.tmp)])

    def test_inputs_never_expose_the_home_or_root(self):
        for path in ("/", self.home, self.tmp):
            with self.assertRaises(Refused):
                check_input(path, home=self.home)
        socket = self.home / "work" / "docker.sock"
        socket.write_text("")
        with self.assertRaises(Refused):
            check_input(socket, home=self.home)
        with self.assertRaises(Refused):
            check_input(self.home / "missing", home=self.home)
        self.assertEqual(check_input(self.input, home=self.home), self.input.resolve())

    def test_mounts_are_read_only_declared_inputs(self):
        inputs = [check_input(self.home / "work", home=self.home)]
        self.assertEqual(check_mount(self.input, inputs), self.input.resolve())
        with self.assertRaises(Refused):
            check_mount(self.input, inputs, read_only=False)
        with self.assertRaises(Refused):
            check_mount(self.home, inputs)
        with self.assertRaises(Refused):
            check_mount("/etc", inputs)
        link = self.home / "work" / "escape"
        link.symlink_to(self.home)
        with self.assertRaises(Refused):
            check_mount(link, inputs)

    def test_networks(self):
        check_network("none", False)
        check_network("bridge", True)
        for network, allowed in (("host", True), ("container:abc", True), ("bridge", False)):
            with self.assertRaises(Refused):
                check_network(network, allowed)

    def test_start_refuses_before_calling_docker(self):
        docker = Docker("frame", inputs=[self.input], home=self.home, docker="/bin/false")
        with self.assertRaises(Refused):
            docker.start("image", "x", mounts=[(self.home, "/h")])
        with self.assertRaises(Refused):
            docker.start("image", "x", network="host", network_allowed=True)
        with self.assertRaises(RuntimeError):  # allowed: reaches docker, which here is /bin/false
            docker.start("image", "x", mounts=[(self.input, "/in/repo.bundle")])


FAKE_DOCKER = """#!/bin/sh
# Records its arguments; `exec -i` keeps its stdin; any other exec prints what was kept (a command that
# reads the secret back), and fails if its script says so.
dir=$(dirname "$0")
printf '%s\\n' "$*" >> "$dir/calls.log"
case " $* " in
    *" exec -i "*) cat > "$dir/stdin.txt" ;;
    *" exec "*) cat "$dir/stdin.txt" 2>/dev/null; case "$*" in *fail-now*) exit 3 ;; esac ;;
    *) echo container-id ;;
esac
"""


class Secrets(unittest.TestCase):
    SECRET = "s3cr3t-value-for-the-frame-test"

    def setUp(self):
        self.tmp = Path(tempfile.mkdtemp(prefix="testbed-secrets-"))
        self.fake = self.tmp / "docker"
        self.fake.write_text(FAKE_DOCKER)
        self.fake.chmod(0o755)
        self.logged = []
        self.docker = Docker("secrets", docker=str(self.fake), log=self.logged.append)
        self.container = Container(self.docker, "cid", "x")

    def tearDown(self):
        subprocess.run(["rm", "-rf", str(self.tmp)])

    def test_a_secret_reaches_the_container_but_no_command_line_or_log(self):
        self.container.put_secret("/home/ada/.key", self.SECRET, "ada")
        self.assertEqual((self.tmp / "stdin.txt").read_text(), self.SECRET)
        self.container.exec("cat ~/.key")
        with self.assertRaises(ExecFailed) as failed:
            self.container.exec("cat ~/.key; fail-now")
        self.assertNotIn(self.SECRET, str(failed.exception))
        self.assertNotIn(self.SECRET, (self.tmp / "calls.log").read_text())
        log = "\n".join(self.logged)
        self.assertNotIn(self.SECRET, log)
        self.assertIn("<redacted>", log)

    def test_a_secret_on_a_command_line_is_refused(self):
        self.docker.secret(self.SECRET)
        with self.assertRaises(Refused):
            self.docker.start("image", "x", env={"KEY": self.SECRET})
        with self.assertRaises(Refused):
            self.container.exec(f"echo {self.SECRET}")
        self.assertFalse((self.tmp / "calls.log").exists())

    def test_short_secrets_are_refused(self):
        with self.assertRaises(Refused):
            self.docker.secret("abc")


class Results(unittest.TestCase):
    def test_round_trip_and_summary(self):
        with tempfile.TemporaryDirectory() as tmp:
            path = Path(tmp) / "results.jsonl"
            lines = [results.scenario_line("a/b", "pass", 1.23, "ok", "logs/a-b.log"),
                     results.scenario_line("a/c", "error", 2, "boom", "logs/a-c.log")]
            results.write(path, {"repo": "dotfiles", "commit": "f" * 40}, lines)
            header, read = results.read(path)
            self.assertEqual(header["interface"], results.INTERFACE)
            self.assertEqual(read, lines)
            self.assertEqual(results.summary("dotfiles", "f" * 40, read),
                             "testbed dotfiles: 1 pass, 0 fail, 1 error (dotfiles@ffffffffffff)")
            path.write_text(json.dumps({"interface": 999}) + "\n")
            with self.assertRaises(ValueError):
                results.read(path)

    def test_no_skip(self):
        with self.assertRaises(ValueError):
            results.scenario_line("a/b", "skip", 0, "", "")


class Stand_ins(unittest.TestCase):
    def serve(self, server):
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(server.server_close)
        self.addCleanup(server.shutdown)
        return f"http://127.0.0.1:{server.server_address[1]}"

    def post(self, url, body, headers=None):
        request = urllib.request.Request(url, json.dumps(body).encode(),
                                         {"content-type": "application/json", **(headers or {})})
        with urllib.request.urlopen(request, timeout=10) as reply:
            return reply.headers.get("content-type"), reply.read().decode()

    def test_messages_text_scripted_and_redacted(self):
        with tempfile.TemporaryDirectory() as tmp:
            scripts = Path(tmp) / "scripts"
            scripts.mkdir()
            (scripts / "worker").write_text("echo one\necho two\n")
            log = Path(tmp) / "log.jsonl"
            url = self.serve(messages.serve(0, log, "hello", scripts)) + "/v1/messages?beta=true"
            kind, body = self.post(url, {"model": "m", "messages": [{"role": "user", "content": "hi"}]},
                                   {"x-api-key": "secret-value"})
            self.assertEqual(json.loads(body)["content"][0]["text"], "hello")
            brief = [{"role": "user", "content": [{"type": "text", "text": "do it [[testbed:worker]]"}]}]
            session = {"X-Claude-Code-Session-Id": "s1"}
            commands = []
            for _ in range(3):
                kind, body = self.post(url, {"model": "m", "stream": True, "tools": [{"name": "Bash"}],
                                             "messages": brief}, session)
                self.assertEqual(kind, "text/event-stream")
                deltas = [json.loads(line[6:]) for line in body.splitlines() if line.startswith("data: ")]
                partial = [d["delta"].get("partial_json") for d in deltas if d.get("type") == "content_block_delta"]
                commands.append(json.loads(partial[0])["command"] if partial[0] else None)
            self.assertEqual(commands, ["echo one", "echo two", None])
            answered = brief + [{"role": "user", "content": [{"type": "tool_result", "content": "one"}]}]
            kind, body = self.post(url, {"model": "m", "tools": [{"name": "Bash"}], "messages": answered}, session)
            self.assertEqual(json.loads(body)["stop_reason"], "end_turn")
            text = log.read_text()
            self.assertNotIn("secret-value", text)
            self.assertIn('"scripted": "echo one"', text)

    def test_responses(self):
        with tempfile.TemporaryDirectory() as tmp:
            log = Path(tmp) / "log.jsonl"
            url = self.serve(responses.serve(0, log, "hello")) + "/v1/responses"
            kind, body = self.post(url, {"model": "m", "input": []}, {"authorization": "Bearer secret-value"})
            events = [json.loads(line[6:]) for line in body.splitlines() if line.startswith("data: ")]
            self.assertEqual([e["type"] for e in events],
                             ["response.created", "response.output_item.done", "response.completed"])
            self.assertEqual(events[1]["item"]["content"][0]["text"], "hello")
            self.assertNotIn("secret-value", log.read_text())
            brief = {"model": "m", "input": [{"role": "user", "content": 'go [[testbed:fail:too many "images"]]'}]}
            with self.assertRaises(urllib.error.HTTPError) as refused:
                self.post(url, brief)
            self.assertEqual(refused.exception.code, 400)
            self.assertEqual(json.loads(refused.exception.read())["error"]["message"], 'too many "images"')


class Scenarios(unittest.TestCase):
    def test_listing_and_interface(self):
        listed = subprocess.run([sys.executable, str(CONTAINERS / "run.py"), "--list"], capture_output=True,
                                text=True, check=True).stdout.splitlines()
        names = [line.split("\t")[0] for line in listed]
        self.assertIn("dotfiles/dry-run", names)
        for path in (CONTAINERS / "scenarios").glob("*.py"):
            if path.name.startswith("_"):
                continue  # a helper the scenarios share, not a scenario (run.py skips it too)
            module = load(path)
            self.assertEqual(module.INTERFACE, results.INTERFACE, path.name)

    def test_dry_run_allows_only_its_log(self):
        dry_run = load(CONTAINERS / "scenarios" / "dry_run.py")
        home = ("d", "750", "4096", "1")
        before = {"/home/test": home, "/etc/hosts": ("f", "644", "10", "1")}
        after = {"/home/test": ("d", "750", "4096", "2"), "/etc/hosts": ("f", "644", "10", "1"),
                 "/home/test/.local": ("d", "700", "4096", "2"),
                 "/home/test/.local/state": ("d", "700", "4096", "2"),
                 "/home/test/.local/state/dotfiles": ("d", "700", "4096", "2"),
                 dry_run.LOGS: ("d", "700", "4096", "2"),
                 dry_run.LOGS + "/setup-x-dry-run.log": ("f", "600", "3000", "2")}
        self.assertEqual(dry_run.unexpected_changes(before, after), [])
        after["/home/test/.bashrc"] = ("l", "777", "30", "2")
        after["/home/test"] = ("d", "755", "4096", "2")
        changed = dry_run.unexpected_changes(before, after)
        self.assertEqual(len(changed), 2, changed)


if __name__ == "__main__":
    unittest.main(verbosity=1)
