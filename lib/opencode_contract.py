#!/usr/bin/env python3
"""Inspect OpenCode V2 runtime and release-matched source contracts."""
import argparse
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile

UPDATE = 'https://opencode.ai/update/api/latest/cli/npm'
REPO = 'anomalyco/opencode'
DOCS = 'services/www/src/docs/content/'


def fetch(url):
    return subprocess.run(['curl', '--proto', '=https', '--tlsv1.2', '--fail', '--silent', '--show-error',
                           '--location', '--connect-timeout', '10', '--max-time', '120', url],
                          check=True, capture_output=True).stdout


def release():
    info = json.loads(fetch(UPDATE))
    version = info['version']
    sha = info['metadata']['github']['sha']
    if not re.fullmatch(r'2\.\d+\.\d+', version) or not re.fullmatch(r'[a-f0-9]{40}', sha):
        raise ValueError('Update feed did not return a stable V2 release and commit')
    return version, sha


def source_files(sha):
    # Read archive members, never extract arbitrary upstream paths.
    archive = tarfile.open(fileobj=io.BytesIO(fetch(f'https://codeload.github.com/{REPO}/tar.gz/{sha}')), mode='r:gz')
    for entry in archive:
        if entry.isfile():
            path = entry.name.partition('/')[2]
            yield path, archive.extractfile(entry)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['runtime', 'schema', 'docs', 'egress'])
    parser.add_argument('directory', nargs='?', type=Path)
    args = parser.parse_args()
    if args.command == 'runtime':
        for flags in [('--version',), ('--help',), ('run', '--help'), ('service', '--help')]:
            subprocess.run(['opencode', *flags], check=True)
        return
    if args.command == 'docs' and args.directory is None:
        parser.error('docs requires an explicit output directory')
    version, sha = release()
    print(f'OpenCode {version}, source {sha}')
    if args.command == 'schema':
        # The published config.json is V1. Inspect authoritative V2 definitions;
        # hashes identify source revisions, they do not validate a user's config.
        for path in ['packages/schema/src/config.ts', 'packages/schema/src/config/provider.ts',
                     'packages/schema/src/config/model.ts', 'packages/schema/src/config/agent.ts',
                     'packages/schema/src/model.ts', 'packages/cli/src/config/schema.ts']:
            url = f'https://raw.githubusercontent.com/{REPO}/{sha}/{path}'
            data = fetch(url)
            if b'Schema.' not in data:
                raise ValueError(f'Not a schema source: {path}')
            print(f'{hashlib.sha256(data).hexdigest()}  {url}')
        print('Source fingerprints only. Use `opencode debug config` to inspect runtime normalization; review warnings.')
        return
    hosts, count = set(), 0
    for path, stream in source_files(sha):
        if args.command == 'docs' and path.startswith(DOCS) and path.endswith(('.md', '.mdx')):
            relative = Path(path.removeprefix(DOCS))
            if relative.is_absolute() or '..' in relative.parts:
                raise ValueError('Unsafe upstream documentation path')
            target = args.directory / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(stream.read())
            count += 1
        elif args.command == 'egress' and path.startswith(('packages/core/', 'packages/cli/', 'packages/client/', 'packages/ai/')) and path.endswith(('.ts', '.tsx')):
            hosts.update(re.findall(rb'https?://([A-Za-z0-9._-]+)', stream.read()))
            count += 1
    if not count:
        raise ValueError('No matching source files in release archive')
    if args.command == 'docs':
        print(f'Mirrored {count} documentation files to {args.directory}')
    else:
        print(f'Literal hosts in {count} source files (not a complete runtime egress audit):')
        for host in sorted(hosts):
            print('  ' + host.decode())


if __name__ == '__main__':
    try:
        main()
    except (ValueError, KeyError, OSError, subprocess.CalledProcessError, tarfile.TarError) as exc:
        raise SystemExit(f'Error: {exc}')
