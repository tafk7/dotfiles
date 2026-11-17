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


def tool_version(path: Path) -> str:
    """`VERSION sha256:PREFIX` of an agent binary."""
    digest = hashlib.sha256()
    with open(path, "rb") as binary:
        for chunk in iter(lambda: binary.read(1 << 20), b""):
            digest.update(chunk)
    version = subprocess.run([str(path), "--version"], capture_output=True, text=True, timeout=30,
                             stdin=subprocess.DEVNULL).stdout.strip().split()
    return f"{version[-1] if version and version[0].endswith('codex-cli') else (version[0] if version else '?')}" \
           f" sha256:{digest.hexdigest()[:16]}"


class Context:
    def __init__(self, docker: Docker, *, work: Path, bundle: Path, commit: str, baseline: str | None,
                 binaries: dict, log, image_cache=None, image_lock=None):
        self.docker = docker
        self.work = work
        self.bundle = bundle
        self.commit = commit
        self.baseline = baseline
        self.binaries = binaries
        self.log = log
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

    def clone(self, container, user: str, dest: str, rev: str | None = None):
        """Clone the run's bundle into the container and check out REV (default: the commit)."""
        container.copy_in(self.bundle, "/tmp/repo.bundle")
        container.exec(f"chmod 0644 /tmp/repo.bundle", user="root")
        container.exec(f"set -e; mkdir -p \"$(dirname {dest})\"; git clone -q /tmp/repo.bundle {dest}; "
                       f"git -C {dest} checkout -q --detach {rev or self.commit}", user=user)

    def start_agents(self, name: str, *, network="none") -> "object":
        """A container of the agents image as `ada`, with the agent CLIs, the stand-in servers
        running, Claude's onboarding done and Codex pointed at its stand-in."""
        mounts = [(self.binaries[tool], f"/opt/agents/{tool}") for tool in ("claude", "codex")
                  if tool in self.binaries]
        container = self.docker.start(self.image("agents"), name, mounts=mounts, network=network,
                                      network_allowed=network != "none", user="ada",
                                      env={"HOME": "/home/ada", **AGENT_ENV})
        container.copy_in(FAKES, "/testbed-fakes")
        container.exec(f"echo '{CLAUDE_JSON}' > ~/.claude.json; mkdir -p ~/.codex; "
                       f"cat > ~/.codex/config.toml <<'EOF'\n{CODEX_CONFIG}EOF")
        container.background(f"python3 /testbed-fakes/messages.py --port {MESSAGES_PORT} --log /tmp/messages.jsonl "
                             f"--scripts /tmp/scripts > /tmp/messages.out 2>&1")
        container.background(f"python3 /testbed-fakes/responses.py --port {RESPONSES_PORT} --log /tmp/responses.jsonl "
                             f"> /tmp/responses.out 2>&1")
        container.wait_for(f"curl -sf http://127.0.0.1:{MESSAGES_PORT}/ >/dev/null && "
                           f"curl -sf http://127.0.0.1:{RESPONSES_PORT}/ >/dev/null", timeout=20)
        return container
