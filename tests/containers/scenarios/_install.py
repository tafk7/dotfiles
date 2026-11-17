"""What the slow scenarios share: a clean container on the network, and the checks of an install."""

from lib.results import Failure

HOME = "/home/test"
CHECKOUT = f"{HOME}/dev/dotfiles"
INSTALL_TIMEOUT = 2700


def start(ctx, name: str, image_kind: str = "clean"):
    """A container of IMAGE_KIND on Ubuntu 24.04 as the sudo user `test`, with Docker's default network."""
    return ctx.docker.start(ctx.image(image_kind), name, sudo=True, user="test", env={"HOME": HOME},
                            network="bridge", network_allowed=True, cpus=8, memory="16g")


def login(container, script: str, **kwargs):
    """SCRIPT in a login shell of `test`, as `su - test` would run it."""
    return container.exec(f"bash -lc {quote(script)}", check=False, **kwargs)


def quote(text: str) -> str:
    return "'" + text.replace("'", "'\"'\"'") + "'"


def check_install(container, label: str) -> None:
    """The checks CI makes after its install: the profile, `dotfiles verify -v`, the legacy `verify`;
    then a login and an interactive shell start cleanly."""
    for script, what in ((f"cd {CHECKOUT} && ./bin/dotfiles profile && ./bin/dotfiles verify -v", "dotfiles verify -v"),
                         (f"cd {CHECKOUT} && ./bin/verify --tier bash >/dev/null", "bin/verify --tier bash"),
                         ("exit 0", "a login shell"),
                         ("bash -ic 'exit 0'", "an interactive shell")):
        result = login(container, script, timeout=600)
        if result.returncode != 0:
            tail = (result.stdout + result.stderr).strip().splitlines()[-3:]
            raise Failure(f"{label}: {what} exited {result.returncode}: {' | '.join(tail)}")
