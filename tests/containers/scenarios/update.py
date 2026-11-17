"""dotfiles/update: a machine set up at the deployed commit updates to the candidate with `dotfiles update`.

Setup: the clean image, Docker's default network; a bare repository in the container stands in
for the remote, its `main` at the baseline (the deployed commit, `--baseline`); ~/dev/dotfiles is
cloned from it and installed with `setup.sh --bash --force`. Then the remote's `main` moves to
the candidate.
Checks: the baseline is an ancestor of the candidate (else the scenario cannot run: an error);
`dotfiles update` (fetch, pull --ff-only, apply the profile, verify) exits 0 and leaves the
checkout at the candidate; the install's checks pass. Covers: the deploy itself on a machine
already set up.
"""

from lib.results import Failure

from _install import CHECKOUT, INSTALL_TIMEOUT, check_install, login, start

NAME = "dotfiles/update"
SLOW = True
NETWORK = True
NEEDS = ()
INTERFACE = 1
USES_BASELINE = True
ORIGIN = "/tmp/origin.git"


def run(ctx):
    container = start(ctx, "update")
    bundle = ctx.copy_bundle(container)
    container.exec(f"set -e; git clone -q --bare {bundle} {ORIGIN}; "
                   f"git -C {ORIGIN} update-ref refs/heads/main {ctx.baseline}; "
                   f"git -C {ORIGIN} symbolic-ref HEAD refs/heads/main")
    if container.exec(f"git -C {ORIGIN} merge-base --is-ancestor {ctx.baseline} {ctx.commit}", check=False).returncode:
        raise RuntimeError(f"baseline {ctx.baseline[:12]} is not an ancestor of {ctx.commit[:12]}: no fast-forward")
    container.exec(f"git clone -q {ORIGIN} {CHECKOUT}")
    result = login(container, f"cd {CHECKOUT} && ./setup.sh --bash --force", timeout=INSTALL_TIMEOUT)
    if result.returncode != 0:
        raise Failure(f"installing the baseline {ctx.baseline[:12]} failed ({result.returncode})")
    container.exec(f"git -C {ORIGIN} update-ref refs/heads/main {ctx.commit}")
    result = login(container, f"cd {CHECKOUT} && ./bin/dotfiles update", timeout=INSTALL_TIMEOUT)
    if result.returncode != 0:
        raise Failure(f"dotfiles update exited {result.returncode}: "
                      + " | ".join((result.stdout + result.stderr).strip().splitlines()[-3:]))
    head = container.exec(f"git -C {CHECKOUT} rev-parse HEAD").stdout.strip()
    if head != ctx.commit:
        raise Failure(f"after update the checkout is at {head[:12]}, not {ctx.commit[:12]}")
    check_install(container, "after update")
    return f"updated {ctx.baseline[:12]} -> {ctx.commit[:12]} with dotfiles update; verify passed"
