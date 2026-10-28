#!/usr/bin/env python3
"""dotfiles bump against recorded releases, in a copy of the repository: each
kind's handler writes the pin for both architectures from its source's own
data, and a release inside the 14-day cool-down is refused unless --security.
No network: lib/lockgen.py serves DOTFILES_FETCH_FIXTURES."""
import datetime as dt
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
import urllib.parse

ROOT = Path(__file__).resolve().parents[1]
NOW = dt.date(2026, 10, 26)


def days_ago(n):
    return (NOW - dt.timedelta(days=n)).isoformat()


def tarball(files, mode="w:gz"):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode=mode) as t:
        for name, data in files.items():
            info = tarfile.TarInfo(name)
            info.size, info.mode = len(data), 0o755
            t.addfile(info, io.BytesIO(data))
    return buf.getvalue()


def sha(data):
    return hashlib.sha256(data).hexdigest()


class BumpTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name) / 'repo'
        self.repo.mkdir()
        subprocess.run(f'tar -C {ROOT} --exclude=.git -cf - . | tar -x -C {self.repo}', shell=True, check=True)
        self.fixtures = Path(self.temp.name) / 'fixtures'
        self.fixtures.mkdir()

    def record(self, url, body, suffix=''):
        data = body if isinstance(body, bytes) else (json.dumps(body) if not isinstance(body, str) else body).encode()
        (self.fixtures / (urllib.parse.quote(url, safe='') + suffix)).write_bytes(data)

    def bump(self, *args, ok=True):
        env = dict(os.environ, DOTFILES_FETCH_FIXTURES=str(self.fixtures), DOTFILES_BUMP_NOW=NOW.isoformat(),
                   GITHUB_TOKEN='fixture', PYTHONDONTWRITEBYTECODE='1')
        result = subprocess.run(['python3', str(self.repo / 'lib/bump.py'), *args], capture_output=True, text=True, env=env)
        self.assertEqual(result.returncode == 0, ok, result.stdout + result.stderr)
        return result

    def lock(self):
        rows = {}
        for line in (self.repo / 'versions.lock').read_text().splitlines():
            if line and not line.startswith('#'):
                f = line.split('\t')
                rows[(f[0], f[1])] = f
        return rows

    def release(self, repo, tag, published, assets):
        """Record a GitHub release with these assets (name -> bytes)."""
        listed = [{'name': n, 'digest': f'sha256:{sha(d)}'} for n, d in assets.items()]
        api = f'https://api.github.com/repos/{repo}/releases'
        body = {'tag_name': tag, 'published_at': f'{published}T00:00:00Z', 'draft': False, 'prerelease': False,
                'assets_url': f'{api}/1/assets', 'assets': listed}
        self.record(f'{api}/tags/{tag}', body, '.json')
        self.record(f'{api}/1/assets?per_page=100&page=1', listed, '.json')
        for name, data in assets.items():
            self.record(f'https://github.com/{repo}/releases/download/{tag}/{name}', data)
        return body

    def direnv_release(self, tag, published):
        assets = {f'direnv.linux-{a}': f'direnv {tag} {a}'.encode() for a in ('amd64', 'arm64')}
        assets['direnv.darwin-amd64'] = b'darwin'
        self.release('direnv/direnv', tag, published, assets)
        return assets

    def test_eget_tool_moves_tag_and_both_rows(self):
        assets = self.direnv_release('v2.99.0', days_ago(20))
        out = self.bump('direnv', 'v2.99.0')
        self.assertIn(f"bumped direnv: {self.original_row('direnv', 'x86_64')[2]} -> v2.99.0", out.stdout)
        self.assertIn('tag = "v2.99.0"', (self.repo / 'eget.toml').read_text())
        rows = self.lock()
        for arch, go in (('x86_64', 'amd64'), ('aarch64', 'arm64')):
            row = rows[('direnv', arch)]
            self.assertEqual(row[2:6], ['v2.99.0', 'direnv/direnv', f'direnv.linux-{go}', sha(assets[f'direnv.linux-{go}'])])
            self.assertEqual(row[7], f'sha256:{sha(assets[f"direnv.linux-{go}"])}')
        self.assertEqual(rows[('fd', 'x86_64')], self.original_row('fd', 'x86_64'), 'another tool changed')

    def original_row(self, component, arch):
        for line in (ROOT / 'versions.lock').read_text().splitlines():
            f = line.split('\t')
            if f[:2] == [component, arch]:
                return f
        return None

    def test_cool_down_refuses_and_security_allows(self):
        self.direnv_release('v2.99.1', days_ago(3))
        before = (self.repo / 'eget.toml').read_text()
        out = self.bump('direnv', 'v2.99.1', ok=False)
        self.assertIn('inside the 14-day cool-down', out.stderr)
        self.assertEqual((self.repo / 'eget.toml').read_text(), before)
        self.assertEqual(self.lock()[('direnv', 'x86_64')], self.original_row('direnv', 'x86_64'))
        self.bump('direnv', 'v2.99.1', '--security')
        self.assertEqual(self.lock()[('direnv', 'x86_64')][2], 'v2.99.1')

    def test_newest_release_outside_the_cool_down(self):
        api = 'https://api.github.com/repos/neovim/neovim/releases'
        bodies = []
        for tag, age in (('v0.13.1', 2), ('v0.13.0', 30)):
            assets = {f'nvim-linux-{a}.tar.gz': tarball({f'nvim-linux-{a}/bin/nvim': f'nvim {tag}'.encode()})
                      for a in ('x86_64', 'arm64')}
            bodies.append(self.release('neovim/neovim', tag, days_ago(age), assets))
        self.record(f'{api}?per_page=30', bodies, '.json')
        self.bump('neovim')
        rows = self.lock()
        self.assertEqual(rows[('neovim', 'aarch64')][2:5], ['v0.13.0', 'neovim/neovim', 'nvim-linux-arm64.tar.gz'])
        self.assertEqual(rows[('neovim', 'x86_64')][7], 'version:0.13.0')

    def test_node_takes_the_lts_and_its_bundled_npm(self):
        index = [{'version': 'v26.13.0', 'date': days_ago(30), 'lts': False, 'npm': '11.21.0'},
                 {'version': 'v24.31.0', 'date': days_ago(5), 'lts': 'Krypton', 'npm': '11.20.1'},
                 {'version': 'v24.30.0', 'date': days_ago(20), 'lts': 'Krypton', 'npm': '11.20.0'}]
        self.record('https://nodejs.org/dist/index.json', index)
        sums, binaries = [], {}
        for a in ('x64', 'arm64'):
            binaries[a] = f'node {a}'.encode()
            data = tarball({f'node-v24.30.0-linux-{a}/bin/node': binaries[a]}, 'w:xz')
            self.record(f'https://nodejs.org/dist/v24.30.0/node-v24.30.0-linux-{a}.tar.xz', data)
            sums.append(f'{sha(data)}  node-v24.30.0-linux-{a}.tar.xz')
        self.record('https://nodejs.org/dist/v24.30.0/SHASUMS256.txt', '\n'.join(sums) + '\n')
        out = self.bump('node')
        self.assertIn('bumped node: v24.22.1 -> v24.30.0; bundled npm 11.20.0', out.stdout)
        rows = self.lock()
        self.assertEqual(rows[('node', 'aarch64')][7], f'sha256:{sha(binaries["arm64"])}')
        self.assertEqual(rows[('npm', 'any')][2], '11.20.0')

    def test_node_refuses_a_tarball_off_its_published_sum(self):
        index = [{'version': 'v24.30.0', 'date': days_ago(20), 'lts': 'Krypton', 'npm': '11.20.0'}]
        self.record('https://nodejs.org/dist/index.json', index)
        for a in ('x64', 'arm64'):
            self.record(f'https://nodejs.org/dist/v24.30.0/node-v24.30.0-linux-{a}.tar.xz', b'tampered')
        self.record('https://nodejs.org/dist/v24.30.0/SHASUMS256.txt',
                    ''.join(f'{"0" * 64}  node-v24.30.0-linux-{a}.tar.xz\n' for a in ('x64', 'arm64')))
        out = self.bump('node', ok=False)
        self.assertIn('SHASUMS256.txt has', out.stderr)
        self.assertEqual(self.lock()[('node', 'x86_64')], self.original_row('node', 'x86_64'))

    def rust_manifest(self, version, date, arm=True):
        targets = {'x86_64-unknown-linux-gnu': {'available': True},
                   'aarch64-unknown-linux-gnu': {'available': arm}}
        lines = [f'date = "{date}"', '[pkg.rustc]', f'version = "{version} (abc {date})"']
        lines += [f'[pkg.rust.target.{t}]\navailable = {str(v["available"]).lower()}' for t, v in targets.items()]
        return '\n'.join(lines) + '\n'

    def test_rust_channel_and_cool_down(self):
        self.record('https://static.rust-lang.org/dist/channel-rust-stable.toml', self.rust_manifest('1.100.0', days_ago(2)))
        out = self.bump('rust', ok=False)
        self.assertIn('name an older version', out.stderr)
        self.record('https://static.rust-lang.org/dist/channel-rust-1.99.1.toml', self.rust_manifest('1.99.1', days_ago(16), arm=False))
        out = self.bump('rust', '1.99.1', ok=False)
        self.assertIn('not available for aarch64-unknown-linux-gnu', out.stderr)
        self.record('https://static.rust-lang.org/dist/channel-rust-1.99.0.toml', self.rust_manifest('1.99.0', days_ago(30)))
        self.bump('rust', '1.99.0')
        self.assertEqual(self.lock()[('rust', 'any')][2:], ['1.99.0', 'rustup', '-', '-', '-', 'version:1.99.0'])

    def test_sbx_takes_a_version_published_for_both_architectures(self):
        base = 'https://download.docker.com/linux/ubuntu'
        stanza = 'Package: docker-sbx\nVersion: {v}-1~ubuntu.24.04~noble\nFilename: pool/stable/{a}/docker-sbx_{v}_{a}.deb\n'
        self.record(f'{base}/dists/noble/stable/binary-amd64/Packages',
                    '\n'.join(stanza.format(v=v, a='amd64') for v in ('0.51.0', '0.50.0')))
        self.record(f'{base}/dists/noble/stable/binary-arm64/Packages', stanza.format(v='0.50.0', a='arm64'))
        self.record(f'{base}/pool/stable/amd64/docker-sbx_0.50.0_amd64.deb',
                    {'Last-Modified': 'Mon, 28 Sep 2026 10:00:00 GMT'}, '.headers')
        out = self.bump('sbx')
        self.assertIn('needs kit validation', out.stdout)
        self.assertEqual(self.lock()[('sbx', 'any')][2], '0.50.0')

    def test_plugin_commit(self):
        sha1 = 'a' * 40
        self.record(f'https://api.github.com/repos/tpope/vim-surround/commits/{sha1}',
                    {'sha': sha1, 'commit': {'committer': {'date': f'{days_ago(40)}T00:00:00Z'}}}, '.json')
        self.bump('vim-surround', sha1)
        self.assertIn(f"Plug 'tpope/vim-surround', {{ 'commit': '{sha1}' }}", (self.repo / 'configs/init.vim').read_text())

    def test_unknown_tool(self):
        self.assertIn('no pin named', self.bump('nothing-here', ok=False).stderr)


if __name__ == '__main__':
    unittest.main(verbosity=1)
