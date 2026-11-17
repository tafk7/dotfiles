"""What a scenario is given: the run's Docker, its images, the commit under test and the agent CLIs.

Scenarios are modules with:

    NAME = "group/name"     # as the gate lists it
    SLOW = False            # True: a real install from the network, run only with --slow
    NETWORK = False         # True: its containers may use Docker's default network
    NEEDS = ("claude",)     # agent binaries it needs; a missing one is an error, never a skip
    INTERFACE = 1           # the results interface it was written for
    def run(ctx) -> str     # the detail line on a pass; raise results.Failure on a fail

Anything else a scenario raises is an `error`.
"""

import hashlib
import re
import subprocess
import threading
from pathlib import Path

from .container import Docker

HERE = Path(__file__).resolve().parent
FAKES = HERE / "fakes"
IMAGES = HERE / "images"

# Base images by digest, as pulled on 2026-11-17. Bump deliberately; the run records them.
BASES = {
    "22.04": "ubuntu@sha256:829f6df217bcbae2b371026e81711d1a787c61b2967ad09d015063663ebafbf7",
    "24.04": "ubuntu@sha256:224a1869083a311ef3f13648a154ba79832fbef6364d31493642ca03082da254",
    "26.04": "ubuntu@sha256:513c074113a871b51a8d16ab445c88779d6452d937a164fb5cc479f32668a41d",
}

MESSAGES_PORT, RESPONSES_PORT = 8765, 8766
AGENT_ENV = {
    "ANTHROPIC_BASE_URL": f"http://127.0.0.1:{MESSAGES_PORT}",
    "ANTHROPIC_API_KEY": "dummy",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1",
    "TESTBED_KEY": "dummy",
}
CODEX_CONFIG = f"""model = "stand-in"
model_provider = "testbed"
[model_providers.testbed]
name = "testbed"
base_url = "http://127.0.0.1:{RESPONSES_PORT}/v1"
env_key = "TESTBED_KEY"
wire_api = "responses"
"""
# Claude's onboarding done and the dummy key approved, as a configured machine has them.
CLAUDE_JSON = '{"hasCompletedOnboarding": true, "customApiKeyResponses": {"approved": ["dummy"], "rejected": []}}'


def codex_package(binary: Path) -> Path | None:
    """The package directory a Codex binary was installed in (its interactive mode needs the whole
    package: bin/, codex-package.json, resources), or None for a bare binary."""
    package = Path(binary).resolve().parent.parent
    return package if (package / "codex-package.json").exists() else None


def tool_version(path: Path) -> str:
    """`VERSION sha256:PREFIX` of an agent binary."""
    digest = hashlib.sha256()
    with open(path, "rb") as binary:
        for chunk in iter(lambda: binary.read(1 << 20), b""):
            digest.update(chunk)
    output = subprocess.run([str(path), "--version"], capture_output=True, text=True, timeout=30,
                            stdin=subprocess.DEVNULL).stdout
    found = re.search(r"\bv?(\d+\.\d+[\w.+-]*)", output)  # "2.1.321 (Claude Code)", "codex-cli 0.169.0", "opencode v2.2.2"
    return f"{found.group(1) if found else '?'} sha256:{digest.hexdigest()[:16]}"


class Context:
    def __init__(self, docker: Docker, *, work: Path, bundle: Path, commit: str, baseline: str | None, repo: Path,
                 binaries: dict, log, image_cache=None, image_lock=None, extras=None):
        self.docker = docker
        self.work = work
        self.bundle = bundle
        self.commit = commit
        self.baseline = baseline
        self.repo = repo
        self.extras = extras or {}  # NAME -> (bundle, commit): other repositories the scenarios clone
        self.binaries = binaries
        self.log = docker.emit  # LOG, with every registered secret redacted
        self._images = image_cache if image_cache is not None else {}
        self._image_lock = image_lock or threading.Lock()

    def image(self, kind: str, release: str = "24.04") -> str:
        """Build (once per run) the image KIND (`agents`, `clean`) on Ubuntu RELEASE; return its tag."""
        key = (kind, release)
        with self._image_lock:
            if key not in self._images:
                tag = f"testbed/{kind}-{release}:{self.docker.run_id}"
                self.docker.build(tag, IMAGES / f"{kind}.Dockerfile", IMAGES, {"BASE": BASES[release]})
                self._images[key] = tag
        return self._images[key]

    def copy_bundle(self, container, repo: str | None = None) -> str:
        """Copy the run's bundle (or REPO's, given with --with) into the container; return its path there."""
        if repo is None:
            container.copy_in(self.bundle, "/tmp/repo.bundle")  # keeps the host's owner; readable by all
            return "/tmp/repo.bundle"
        if repo not in self.extras:
            raise RuntimeError(f"needs the {repo} repository (--with {repo}=PATH[@REV])")
        container.copy_in(self.extras[repo][0], f"/tmp/{repo}.bundle")
        return f"/tmp/{repo}.bundle"

    def file_at(self, path: str) -> Path:
        """PATH as it is in the commit, written on the host and declared, for copy_in."""
        target = self.work / "files" / self.commit[:12] / path
        if not target.exists():
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(subprocess.run(["git", "-C", str(self.repo), "show", f"{self.commit}:{path}"],
                                             capture_output=True, text=True, check=True).stdout)
            target.chmod(0o644)
        self.docker.declare(target)
        return target

    def clone(self, container, user: str, dest: str, rev: str | None = None, repo: str | None = None):
        """Clone the run's bundle (or REPO's) into the container and check out REV (default: its commit)."""
        bundle = self.copy_bundle(container, repo)
        commit = rev or (self.commit if repo is None else self.extras[repo][1])
        container.exec(f"set -e; mkdir -p \"$(dirname {dest})\"; git clone -q {bundle} {dest}; "
                       f"git -C {dest} checkout -q --detach {commit}", user=user)

    def start_agents(self, name: str, *, network="none", configured=True) -> "object":
        """A container of the agents image as `ada`, with the agent CLIs and the stand-in servers
        running. CONFIGURED (default): Claude's onboarding done and Codex pointed at its stand-in;
        False: a clean home, for scenarios that install the configuration themselves."""
        mounts = [(self.binaries[tool], f"/opt/agents/{tool}") for tool in ("claude", "opencode")
                  if tool in self.binaries]
        if "codex" in self.binaries:
            package = codex_package(self.binaries["codex"])
            mounts.append((package, "/opt/codex") if package else (self.binaries["codex"], "/opt/agents/codex"))
        container = self.docker.start(self.image("agents"), name, mounts=mounts, network=network,
                                      network_allowed=network != "none", user="ada",
                                      env={"HOME": "/home/ada", **(AGENT_ENV if configured else {})})
        if configured:
            container.exec(f"echo '{CLAUDE_JSON}' > ~/.claude.json; mkdir -p ~/.codex; "
                           f"cat > ~/.codex/config.toml <<'EOF'\n{CODEX_CONFIG}EOF")
        self.start_stand_ins(container)
        return container

    def start_stand_ins(self, container):
        """The Messages and Responses stand-ins, on MESSAGES_PORT and RESPONSES_PORT, logging to
        /tmp/messages.jsonl and /tmp/responses.jsonl (scripts: /tmp/scripts)."""
        container.copy_in(FAKES, "/testbed-fakes")
        container.background(f"python3 /testbed-fakes/messages.py --port {MESSAGES_PORT} --log /tmp/messages.jsonl "
                             f"--scripts /tmp/scripts > /tmp/messages.out 2>&1")
        container.background(f"python3 /testbed-fakes/responses.py --port {RESPONSES_PORT} --log /tmp/responses.jsonl "
                             f"> /tmp/responses.out 2>&1")
        container.wait_for(f"curl -sf http://127.0.0.1:{MESSAGES_PORT}/ >/dev/null && "
                           f"curl -sf http://127.0.0.1:{RESPONSES_PORT}/ >/dev/null", timeout=20)
