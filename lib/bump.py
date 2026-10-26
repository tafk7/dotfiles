#!/usr/bin/env python3
"""dotfiles bump: move one pin to a release, through that source's own trust.

    dotfiles bump TOOL [VERSION] [--security]
    dotfiles bump --refresh

Edits versions.lock (and eget.toml for eget tools, configs/init.vim for
Neovim plugins), checks both architectures before writing anything, and never
commits. Without VERSION it takes the newest release outside the 14-day
cool-down; --security allows a newer one, for a release that fixes an advisory
affecting the current pin. --refresh rewrites the eget rows for eget.toml's
tags as they stand.

Handlers, by kind:
  eget tools          GitHub release; eget.toml's tag; assets selected per
                      architecture and checked against GitHub's digests
  neovim, eget, tmux  GitHub release assets (or tmux's source archive)
  nvm                 the tag's install.sh
  node                nodejs.org's index and SHASUMS256.txt; the bundled npm
  rust                the channel manifest, available on both architectures
  aws-cli             the versioned archives and their AWS signatures
  vim-plug, plugins   the resolved commit (and plug.vim's digest)
  sbx                 the APT version Docker publishes for both architectures
"""
from __future__ import annotations

import argparse
import datetime as dt
import email.utils
import hashlib
import json
import lzma
import os
import re
import subprocess
import sys
import tarfile
import tempfile
import tomllib
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import lockgen  # noqa: E402
from lockgen import ROOT, fetch, github_get, github_token, head, read_lock, write_lock  # noqa: E402

COOL_DOWN = dt.timedelta(days=14)
ARCHES = {"x86_64": {"node": "x64", "go": "amd64", "deb": "amd64", "nvim": "x86_64", "rust": "x86_64-unknown-linux-gnu"},
          "aarch64": {"node": "arm64", "go": "arm64", "deb": "arm64", "nvim": "arm64", "rust": "aarch64-unknown-linux-gnu"}}
SBX_SUITE = "noble"


class Refused(Exception):
    """The bump would break a rule; nothing was written."""


def now() -> dt.datetime:
    override = os.environ.get("DOTFILES_BUMP_NOW")
    return dt.datetime.fromisoformat(override).replace(tzinfo=dt.timezone.utc) if override else dt.datetime.now(dt.timezone.utc)


def parse_time(value: str) -> dt.datetime:
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        return dt.datetime.fromisoformat(value).replace(tzinfo=dt.timezone.utc)
    if value[:1].isdigit():
        return dt.datetime.fromisoformat(value.replace("Z", "+00:00"))
    return email.utils.parsedate_to_datetime(value)


def cooled(label: str, when: dt.datetime, security: bool) -> None:
    age = now() - when
    if age < COOL_DOWN and not security:
        raise Refused(f"{label} is {age.days} day(s) old, inside the {COOL_DOWN.days}-day cool-down "
                      "(--security takes it for a fix to an advisory affecting the pin)")


def sha256(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def set_rows(component: str, rows: list[dict]) -> None:
    header, lock = read_lock()
    for key in [k for k in lock if k[0] == component]:
        del lock[key]
    for row in rows:
        lock[(component, row["arch"])] = {"component": component, **row}
    write_lock(header, lock)


def current_want(component: str) -> str:
    _, lock = read_lock()
    wants = {row["want"] for key, row in lock.items() if key[0] == component}
    return wants.pop() if len(wants) == 1 else "?"


def report(component: str, before: str, after: str, note: str = "") -> None:
    print(f"bumped {component}: {before} -> {after}{'; ' + note if note else ''}")


# --- GitHub releases ------------------------------------------------------------

def gh_release(repo: str, tag: str | None, security: bool) -> dict:
    token = github_token()
    if tag:
        release = github_get(f"https://api.github.com/repos/{repo}/releases/tags/{tag}", token)
        cooled(f"{repo} {tag}", parse_time(release["published_at"]), security)
        return release
    releases = github_get(f"https://api.github.com/repos/{repo}/releases?per_page=30", token)
    for release in releases:
        if release.get("draft") or release.get("prerelease"):
            continue
        if security or now() - parse_time(release["published_at"]) >= COOL_DOWN:
            return release
    raise Refused(f"{repo}: no release outside the {COOL_DOWN.days}-day cool-down")


def gh_asset(release: dict, name: str, repo: str) -> bytes:
    """The asset's bytes, checked against the digest GitHub publishes."""
    assets = {a["name"]: a for a in release.get("assets", [])}
    if name not in assets:
        raise Refused(f"{repo} {release['tag_name']} has no asset {name}")
    data = fetch(lockgen.download_url(repo, release["tag_name"], name))
    published = assets[name].get("digest") or ""
    if published and published != f"sha256:{sha256(data)}":
        raise Refused(f"{name}: downloaded sha256 {sha256(data)}, GitHub publishes {published}")
    return data


def bump_eget_tool(name: str, tag: str | None, security: bool) -> None:
    manifest = lockgen.load_manifest()
    rows = {r["name"]: r for r in lockgen.registry_rows()}
    repo = rows[name]["repo"] or next((r for r in manifest if r.rsplit("/", 1)[1] == name), "")
    if repo not in manifest:
        raise Refused(f"{name}: no eget.toml entry")
    release = gh_release(repo, tag, security)
    before, after = manifest[repo]["tag"], release["tag_name"]
    path = ROOT / "eget.toml"
    original = path.read_text()
    section = re.escape(f'["{repo}"]')
    updated, count = re.subn(rf'({section}\n(?:[^\[\n].*\n|\n)*?tag = ")[^"]*(")', rf"\g<1>{after}\g<2>", original)
    if count != 1:
        raise Refused(f"{repo}: could not find its tag in eget.toml")
    path.write_text(updated)
    if lockgen.refresh(lockgen.load_manifest()) != 0:
        path.write_text(original)
        raise Refused(f"{name}: the lock rows could not be made for {after}; eget.toml restored")
    report(name, before, after)


def bump_neovim(version: str | None, security: bool) -> None:
    release = gh_release("neovim/neovim", version, security)
    tag = release["tag_name"]
    rows = []
    for arch, names in ARCHES.items():
        asset = f"nvim-linux-{names['nvim']}.tar.gz"
        data = gh_asset(release, asset, "neovim/neovim")
        member = f"nvim-linux-{names['nvim']}/bin/nvim"
        lockgen.member_bytes(data, asset, member)
        rows.append({"arch": arch, "want": tag, "source": "neovim/neovim", "artifact": asset,
                     "sha256": sha256(data), "member": member, "identity": f"version:{tag.removeprefix('v')}"})
    before = current_want("neovim")
    set_rows("neovim", rows)
    report("neovim", before, tag)


def bump_eget_bootstrap(version: str | None, security: bool) -> None:
    release = gh_release("zyedidia/eget", version, security)
    tag = release["tag_name"]
    plain = tag.removeprefix("v")
    rows = []
    for arch, names in ARCHES.items():
        asset = f"eget-{plain}-linux_{names['go']}.tar.gz"
        data = gh_asset(release, asset, "zyedidia/eget")
        member = f"eget-{plain}-linux_{names['go']}/eget"
        rows.append({"arch": arch, "want": tag, "source": "zyedidia/eget", "artifact": asset, "sha256": sha256(data),
                     "member": member, "identity": f"sha256:{sha256(lockgen.member_bytes(data, asset, member))}"})
    before = current_want("eget")
    set_rows("eget", rows)
    report("eget", before, tag, "re-verify lib/lockgen.py's detector (detect.go) for this eget release")


def bump_tmux(version: str | None, security: bool) -> None:
    release = gh_release("tmux/tmux", version, security)
    tag = release["tag_name"]
    asset = f"tmux-{tag}.tar.gz"
    data = gh_asset(release, asset, "tmux/tmux")
    before = current_want("tmux")
    set_rows("tmux", [{"arch": "any", "want": tag, "source": "tmux/tmux", "artifact": asset,
                       "sha256": sha256(data), "member": "-", "identity": f"version:{tag}"}])
    report("tmux", before, tag)


def bump_nvm(version: str | None, security: bool) -> None:
    release = gh_release("nvm-sh/nvm", version, security)
    tag = release["tag_name"]
    data = fetch(f"https://raw.githubusercontent.com/nvm-sh/nvm/{tag}/install.sh")
    if not data.startswith(b"#!"):
        raise Refused(f"nvm {tag}: install.sh is not a script")
    before = current_want("nvm")
    set_rows("nvm", [{"arch": "any", "want": tag, "source": "nvm-sh/nvm", "artifact": "install.sh",
                      "sha256": sha256(data), "member": "-", "identity": f"version:{tag.removeprefix('v')}"}])
    report("nvm", before, tag)


# --- Node ------------------------------------------------------------------------

def bump_node(version: str | None, security: bool) -> None:
    index = json.loads(fetch("https://nodejs.org/dist/index.json"))
    if version:
        wanted = "v" + version.removeprefix("v")
        entry = next((e for e in index if e["version"] == wanted), None)
        if not entry:
            raise Refused(f"node {wanted} is not in nodejs.org's index")
        if not entry.get("lts"):
            raise Refused(f"node {wanted} is not an LTS release")
        cooled(f"node {wanted}", parse_time(entry["date"]), security)
    else:
        entry = next((e for e in index if e.get("lts") and (security or now() - parse_time(e["date"]) >= COOL_DOWN)), None)
        if not entry:
            raise Refused("node: no LTS release outside the cool-down")
    tag = entry["version"]
    sums = {}
    for line in fetch(f"https://nodejs.org/dist/{tag}/SHASUMS256.txt").decode().splitlines():
        digest, _, name = line.partition("  ")
        sums[name.strip()] = digest
    rows = []
    for arch, names in ARCHES.items():
        asset = f"node-{tag}-linux-{names['node']}.tar.xz"
        if asset not in sums:
            raise Refused(f"node {tag}: SHASUMS256.txt lists no {asset}")
        data = fetch(f"https://nodejs.org/dist/{tag}/{asset}")
        if sha256(data) != sums[asset]:
            raise Refused(f"{asset}: downloaded sha256 {sha256(data)}, SHASUMS256.txt has {sums[asset]}")
        member = f"node-{tag}-linux-{names['node']}/bin/node"
        binary = lockgen.member_bytes(data, asset, member)
        rows.append({"arch": arch, "want": tag, "source": "nodejs.org", "artifact": asset,
                     "sha256": sums[asset], "member": member, "identity": f"sha256:{sha256(binary)}"})
    before = current_want("node")
    set_rows("node", rows)
    set_rows("npm", [{"arch": "any", "want": entry["npm"], "source": "node", "artifact": "-",
                      "sha256": "-", "member": "-", "identity": f"version:{entry['npm']}"}])
    report("node", before, tag, f"bundled npm {entry['npm']}")


# --- Rust --------------------------------------------------------------------------

def bump_rust(version: str | None, security: bool) -> None:
    channel = version or "stable"
    manifest = tomllib.loads(fetch(f"https://static.rust-lang.org/dist/channel-rust-{channel}.toml").decode())
    found = re.match(r"(\d+\.\d+\.\d+)", manifest["pkg"]["rustc"]["version"])
    if not found:
        raise Refused(f"rust {channel}: the manifest names no version")
    release = found.group(1)
    try:
        cooled(f"rust {release}", parse_time(manifest["date"]), security)
    except Refused:
        if version:
            raise
        raise Refused(f"rust {release} (stable) is inside the {COOL_DOWN.days}-day cool-down; name an older version")
    for names in ARCHES.values():
        target = manifest["pkg"]["rust"]["target"].get(names["rust"], {})
        if not target.get("available"):
            raise Refused(f"rust {release} is not available for {names['rust']}")
    before = current_want("rust")
    set_rows("rust", [{"arch": "any", "want": release, "source": "rustup", "artifact": "-",
                       "sha256": "-", "member": "-", "identity": f"version:{release}"}])
    report("rust", before, release)


# --- AWS CLI -----------------------------------------------------------------------

def bump_aws(version: str | None, security: bool) -> None:
    if not version:
        changelog = fetch("https://raw.githubusercontent.com/aws/aws-cli/v2/CHANGELOG.rst").decode()
        candidates = re.findall(r"^(2\.\d+\.\d+)$", changelog, re.M)
    else:
        candidates = [version]
    for candidate in candidates:
        url = f"https://awscli.amazonaws.com/awscli-exe-linux-x86_64-{candidate}.zip"
        published = parse_time(head(url)["last-modified"])
        if version:
            cooled(f"aws-cli {candidate}", published, security)
        elif not security and now() - published < COOL_DOWN:
            continue
        break
    else:
        raise Refused("aws-cli: no release outside the cool-down")
    keyring = Path(tempfile.mkdtemp()) / "aws.gpg"
    subprocess.run(["gpg", "--batch", "--dearmor", "--output", str(keyring), str(ROOT / "installers/aws-cli-signing-key.asc")],
                   check=True, capture_output=True)
    rows = []
    for arch in ARCHES:
        asset = f"awscli-exe-linux-{arch}-{candidate}.zip"
        data = fetch(f"https://awscli.amazonaws.com/{asset}")
        signature = fetch(f"https://awscli.amazonaws.com/{asset}.sig")
        with tempfile.TemporaryDirectory() as work:
            (Path(work) / "a.zip").write_bytes(data)
            (Path(work) / "a.zip.sig").write_bytes(signature)
            if subprocess.run(["gpgv", "--keyring", str(keyring), f"{work}/a.zip.sig", f"{work}/a.zip"],
                              capture_output=True).returncode != 0:
                raise Refused(f"{asset}: the AWS CLI Team signature does not verify")
        rows.append({"arch": arch, "want": candidate, "source": "awscli.amazonaws.com", "artifact": asset,
                     "sha256": sha256(data), "member": "-", "identity": f"version:{candidate}"})
    before = current_want("aws-cli")
    set_rows("aws-cli", rows)
    report("aws-cli", before, candidate)


# --- Commits: vim-plug and Neovim plugins -------------------------------------------

def resolved_commit(repo: str, commit: str | None, security: bool) -> str:
    data = github_get(f"https://api.github.com/repos/{repo}/commits/{commit or 'HEAD'}", github_token())
    when = parse_time(data["commit"]["committer"]["date"])
    if commit:
        cooled(f"{repo} {commit[:12]}", when, security)
    elif not security and now() - when < COOL_DOWN:
        raise Refused(f"{repo}: its newest commit is inside the {COOL_DOWN.days}-day cool-down; name an older commit")
    return data["sha"]


def bump_vim_plug(commit: str | None, security: bool) -> None:
    sha = resolved_commit("junegunn/vim-plug", commit, security)
    data = fetch(f"https://raw.githubusercontent.com/junegunn/vim-plug/{sha}/plug.vim")
    if b"function! plug#begin" not in data:
        raise Refused(f"vim-plug {sha[:12]}: plug.vim does not define plug#begin")
    before = current_want("vim-plug")
    set_rows("vim-plug", [{"arch": "any", "want": sha, "source": "junegunn/vim-plug", "artifact": "plug.vim",
                           "sha256": sha256(data), "member": "-", "identity": "-"}])
    report("vim-plug", before[:12], sha[:12])


PLUG_LINE = re.compile(r"^(\s*Plug '([^']+)',\s*\{\s*'commit':\s*')([0-9a-f]{40})(')", re.M)


def plugin_repos() -> dict[str, str]:
    return {m.group(2).rsplit("/", 1)[1]: m.group(2) for m in PLUG_LINE.finditer((ROOT / "configs/init.vim").read_text())}


def bump_plugin(name: str, commit: str | None, security: bool) -> None:
    repo = plugin_repos()[name]
    sha = resolved_commit(repo, commit, security)
    path = ROOT / "configs/init.vim"
    text = path.read_text()
    before = next(m.group(3) for m in PLUG_LINE.finditer(text) if m.group(2) == repo)
    path.write_text(PLUG_LINE.sub(lambda m: m.group(1) + sha + m.group(4) if m.group(2) == repo else m.group(0), text))
    report(name, before[:12], sha[:12])


# --- sbx ----------------------------------------------------------------------------

def sbx_versions(deb_arch: str) -> dict[str, str]:
    """docker-sbx versions Docker's repository publishes: upstream version -> .deb path."""
    base = f"https://download.docker.com/linux/ubuntu/dists/{SBX_SUITE}/stable/binary-{deb_arch}/Packages"
    text = fetch(base).decode()
    out = {}
    for stanza in text.split("\n\n"):
        fields = dict(line.split(": ", 1) for line in stanza.splitlines() if ": " in line)
        if fields.get("Package") == "docker-sbx":
            out[fields["Version"].split("-", 1)[0]] = fields["Filename"]
    return out


def bump_sbx(version: str | None, security: bool) -> None:
    amd64, arm64 = sbx_versions("amd64"), sbx_versions("arm64")
    common = sorted(set(amd64) & set(arm64), key=lambda v: [int(p) for p in re.findall(r"\d+", v)], reverse=True)
    if version:
        if version not in common:
            raise Refused(f"docker-sbx {version} is not published for both architectures")
        common = [version]
    for candidate in common:
        published = parse_time(head(f"https://download.docker.com/linux/ubuntu/{amd64[candidate]}")["last-modified"])
        if version:
            cooled(f"docker-sbx {candidate}", published, security)
        elif not security and now() - published < COOL_DOWN:
            continue
        before = current_want("sbx")
        set_rows("sbx", [{"arch": "any", "want": candidate, "source": "apt:docker-sbx", "artifact": "-",
                          "sha256": "-", "member": "-", "identity": f"apt:{candidate}"}])
        report("sbx", before, candidate, "needs kit validation: build the kits (kits/README.md) with it")
        return
    raise Refused("docker-sbx: no version outside the cool-down")


# --- dispatch -----------------------------------------------------------------------

HANDLERS = {"neovim": bump_neovim, "eget": bump_eget_bootstrap, "tmux": bump_tmux, "nvm": bump_nvm,
            "node": bump_node, "rust": bump_rust, "aws-cli": bump_aws, "vim-plug": bump_vim_plug, "sbx": bump_sbx}


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="dotfiles bump", description=__doc__.split("\n\n")[0])
    parser.add_argument("tool", nargs="?")
    parser.add_argument("version", nargs="?")
    parser.add_argument("--security", action="store_true",
                        help="allow a release inside the cool-down that fixes an advisory affecting the pin")
    parser.add_argument("--refresh", action="store_true", help="rewrite the eget rows for eget.toml's tags")
    args = parser.parse_args(argv)
    try:
        if args.refresh:
            return lockgen.refresh(lockgen.load_manifest())
        if not args.tool:
            parser.error("name a tool (or --refresh)")
        eget_tools = {r["name"] for r in lockgen.registry_rows()}
        if args.tool in HANDLERS:
            HANDLERS[args.tool](args.version, args.security)
        elif args.tool in eget_tools:
            bump_eget_tool(args.tool, args.version, args.security)
        elif args.tool in plugin_repos():
            bump_plugin(args.tool, args.version, args.security)
        else:
            parser.error(f"no pin named {args.tool}")
    except Refused as exc:
        print(f"bump refused: {exc}", file=sys.stderr)
        return 1
    except (OSError, ValueError, KeyError, lzma.LZMAError, tarfile.TarError) as exc:
        print(f"bump failed: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
