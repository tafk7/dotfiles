"""Start and drive throwaway Docker containers without letting them touch the host.

Every container and image this module creates carries the label `testbed.run=RUN`, and
`Docker.cleanup()` removes exactly those. A container sees nothing from the host except the
inputs the run declared, mounted read-only; results leave by `docker cp`. The refusals are
checked before `docker` is called, so a scenario cannot ask for more by mistake:

- a mount that is writable, or whose source is not a declared input (or inside one);
- a declared input that is `/`, the caller's home, a parent of it, or a Docker socket;
- `--privileged`, the host's network or PID namespace;
- a network other than `none`, unless the scenario declared it needs one;
- a registered secret anywhere on a docker command line (`-e`, a label, a script).

Secrets: a value given to `Docker.secret()` never reaches a docker command line, so it is in neither
the run's log nor `docker inspect`. `Container.put_secret()` writes it into the container through
`docker exec -i`'s stdin, into a file the container user alone can read; and every line this module
logs, and every error it raises, has each registered secret replaced by `<redacted>`.
"""

import json
import os
import shlex
import subprocess
import time
from pathlib import Path

LABEL = "testbed.run"


class Refused(Exception):
    """A container request broke one of the rules above."""


def _resolved(path) -> Path:
    return Path(os.path.realpath(os.path.expanduser(str(path))))


def check_input(path, home=None) -> Path:
    """A declared input, resolved; refused if it would expose the host."""
    resolved = _resolved(path)
    home = _resolved(home or Path.home())
    if not resolved.exists():
        raise Refused(f"input does not exist: {path}")
    if resolved == Path("/"):
        raise Refused("input is /")
    if resolved == home or home.is_relative_to(resolved):
        raise Refused(f"input is the home folder or contains it: {path}")
    if resolved.name.endswith(".sock") or "docker.sock" in str(resolved):
        raise Refused(f"input is a socket: {path}")
    return resolved


def check_mount(source, inputs, read_only=True) -> Path:
    """A mount's source must be a declared input or inside one, and read-only."""
    if not read_only:
        raise Refused(f"writable mount: {source}")
    resolved = _resolved(source)
    for allowed in inputs:
        if resolved == allowed or resolved.is_relative_to(allowed):
            return resolved
    raise Refused(f"mount source is not a declared input: {source}")


def check_network(network, allowed):
    if network in ("host",) or str(network).startswith("container:"):
        raise Refused(f"network {network} shares the host's or another container's")
    if network != "none" and not allowed:
        raise Refused(f"network {network} for a scenario that declared none")


class Docker:
    """The docker CLI for one run: its label, its declared inputs, what it created."""

    def __init__(self, run_id: str, inputs=(), home=None, docker="docker", log=None):
        self.run_id = run_id
        self.home = home
        self.inputs = [check_input(path, home) for path in inputs]
        self.docker = docker
        self.log = log or (lambda text: None)
        self.images: dict[str, str] = {}
        self.secrets: list[str] = []

    def secret(self, value: str) -> str:
        """Register VALUE as a secret: it is refused on command lines and redacted from the log."""
        if len(value) < 8:
            raise Refused("a secret shorter than 8 characters cannot be told apart from ordinary text")
        if value not in self.secrets:
            self.secrets.append(value)
        return value

    def scrub(self, text: str) -> str:
        for value in self.secrets:
            text = text.replace(value, "<redacted>")
        return text

    def emit(self, text: str) -> None:
        self.log(self.scrub(text))

    def _call(self, args, check=True, timeout=None, input=None):
        if any(value in arg for value in self.secrets for arg in args):
            raise Refused("a secret on a docker command line; use Container.put_secret")
        self.emit("$ docker " + shlex.join(args))
        result = subprocess.run([self.docker, *args], capture_output=True, text=True, timeout=timeout,
                                input=input, stdin=None if input is not None else subprocess.DEVNULL)
        if check and result.returncode != 0:
            raise RuntimeError(self.scrub(f"docker {args[0]} failed ({result.returncode}): {result.stderr.strip()[-2000:]}"))
        return result

    def declare(self, path) -> Path:
        """Add an input after the start (a file made by the run, such as a bundle)."""
        resolved = check_input(path, self.home)
        self.inputs.append(resolved)
        return resolved

    def build(self, tag: str, dockerfile: Path, context: Path, args=None, timeout=1800) -> str:
        """Build an image labelled with this run; the network is used for the build only."""
        command = ["build", "--quiet", "--label", f"{LABEL}={self.run_id}", "-t", tag, "-f", str(dockerfile)]
        for key, value in (args or {}).items():
            command += ["--build-arg", f"{key}={value}"]
        image = self._call(command + [str(context)], timeout=timeout).stdout.strip().splitlines()[-1]
        self.images[tag] = image
        return image

    def start(self, image: str, name: str, *, mounts=(), network="none", network_allowed=False,
              user=None, env=None, sudo=False, cpus=4, memory="8g", workdir=None) -> "Container":
        """A detached container kept alive by `sleep`, to `exec` into."""
        check_network(network, network_allowed)
        command = ["run", "-d", "--init", "--name", f"testbed-{self.run_id}-{name}", "--hostname", "localhost",
                   "--label", f"{LABEL}={self.run_id}", "--network", network,
                   "--cpus", str(cpus), "--memory", memory, "--pids-limit", "4096"]
        if not sudo:
            command += ["--cap-drop", "ALL", "--security-opt", "no-new-privileges"]
        if user:
            command += ["--user", user]
        if workdir:
            command += ["--workdir", workdir]
        for source, target in mounts:
            command += ["--mount", f"type=bind,src={check_mount(source, self.inputs)},dst={target},readonly"]
        for key, value in (env or {}).items():
            command += ["-e", f"{key}={value}"]
        container_id = self._call(command + [image, "sleep", "infinity"]).stdout.strip()
        return Container(self, container_id, name)

    def cleanup(self, keep_images=False) -> list[str]:
        """Remove this run's containers, and its images unless kept; return what was removed."""
        removed = []
        listed = self._call(["ps", "-aq", "--filter", f"label={LABEL}={self.run_id}"], check=False).stdout.split()
        if listed:
            self._call(["rm", "-f", *listed], check=False)
            removed += listed
        if not keep_images:
            for tag in list(self.images):
                labels = self._call(["image", "inspect", "--format", "{{json .Config.Labels}}", tag],
                                    check=False).stdout.strip()
                if labels and json.loads(labels or "null") and json.loads(labels).get(LABEL) == self.run_id:
                    self._call(["rmi", tag], check=False)
                    removed.append(tag)
                self.images.pop(tag)
        return removed


class Container:
    def __init__(self, docker: Docker, container_id: str, name: str):
        self.docker, self.id, self.name = docker, container_id, name

    def exec(self, script: str, *, user=None, env=None, timeout=600, check=True, input=None, workdir=None,
             quiet=False):
        """Run a bash script inside; its output goes to the run's log (QUIET: only its size)."""
        command = ["exec"] + (["-i"] if input is not None else [])
        if user:
            command += ["--user", user]
        if workdir:
            command += ["--workdir", workdir]
        for key, value in (env or {}).items():
            command += ["-e", f"{key}={value}"]
        result = self.docker._call(command + [self.id, "bash", "-c", script], check=False, timeout=timeout,
                                   input=input)
        shown = f"[{len(result.stdout)} bytes of output]" if quiet else result.stdout
        self.docker.emit(shown + (("\n[stderr]\n" + result.stderr) if result.stderr else ""))
        if check and result.returncode != 0:
            raise ExecFailed(script, result, self.docker.scrub)
        return result

    def background(self, script: str, *, user=None, env=None):
        command = ["exec", "-d"]
        if user:
            command += ["--user", user]
        for key, value in (env or {}).items():
            command += ["-e", f"{key}={value}"]
        self.docker._call(command + [self.id, "bash", "-c", script])

    def copy_in(self, source: Path, target: str, owner=None):
        """Copy a declared input into the container (a copy: the container cannot write back)."""
        check_mount(source, self.docker.inputs)
        self.docker._call(["cp", str(source), f"{self.id}:{target}"])
        if owner:
            self.docker._call(["exec", "--user", "root", self.id, "chown", "-R", owner, target])

    def put_secret(self, path: str, value: str, user: str):
        """Write VALUE to PATH in the container, readable by USER alone, through stdin: it is on no
        command line, so neither the log nor `docker inspect` shows it."""
        self.docker.secret(value)
        self.docker._call(["exec", "-i", "--user", user, self.id, "sh", "-c",
                           f"umask 077; mkdir -p \"$(dirname {shlex.quote(path)})\"; cat > {shlex.quote(path)}"],
                          input=value)

    def copy_out(self, source: str, target: Path):
        target.parent.mkdir(parents=True, exist_ok=True)
        self.docker._call(["cp", f"{self.id}:{source}", str(target)], check=False)

    def wait_for(self, script: str, *, user=None, env=None, timeout=60, interval=0.5) -> str:
        """Run SCRIPT until it exits 0; return its output, or raise TimeoutError with the last."""
        deadline = time.monotonic() + timeout
        last = ""
        while True:
            result = self.docker._call(
                ["exec"] + (["--user", user] if user else [])
                + [arg for key, value in (env or {}).items() for arg in ("-e", f"{key}={value}")]
                + [self.id, "bash", "-c", script], check=False, timeout=60)
            last = result.stdout
            if result.returncode == 0:
                return last
            if time.monotonic() > deadline:
                self.docker.emit(f"[wait_for timed out after {timeout}s]\n{last}")
                raise TimeoutError(self.docker.scrub(last))
            time.sleep(interval)


class ExecFailed(Exception):
    def __init__(self, script, result, scrub=lambda text: text):
        tail = (result.stdout + result.stderr).strip().splitlines()[-15:]
        super().__init__(scrub(f"exit {result.returncode}: {script.strip().splitlines()[0][:120]}\n" + "\n".join(tail)))
        self.result = result
