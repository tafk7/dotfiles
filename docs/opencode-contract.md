# Tracking OpenCode V2's contract

Dotfiles installs stable OpenCode V2 through `https://opencode.ai/v2/install`.
The executable remains `~/.opencode/bin/opencode`, linked from `~/.local/bin`.
`bin/ai-update opencode` updates deliberately; portable preferences select
`update: "notify"` and `share: "disabled"`.

## Sources of truth

1. The installed binary: `opencode --version`, `opencode --help`, and subcommand help.
2. The stable V2 update feed: `https://opencode.ai/update/api/latest/cli/npm`.
   It contains the version, npm package and exact GitHub source commit.
3. Schema source at that commit: `packages/schema/src/config.ts`, its component
   definitions, and `packages/cli/src/config/schema.ts` for client preferences.
4. V2 docs: `https://opencode.ai/v2/docs/`, with source under
   `services/www/src/docs/content/` at the matching commit.

As checked for 2.0.22, GitHub `releases/latest` still selects V1, and the public
`https://opencode.ai/config.json` still describes V1. Neither validates a native
V2 installation. `/v2/config.json` is not a schema endpoint.

## Inspection

```
bin/opencode-contract runtime
bin/opencode-contract schema
bin/opencode-contract docs /tmp/opencode-docs
bin/opencode-contract egress
```

`runtime` is offline. Other commands explicitly fetch the latest stable V2
contract. `schema` prints matching TypeScript schema source URLs and hashes;
it does not validate user configuration. Inspect normalized configuration with
`opencode debug config` and review runtime warnings. This output redacts common
credential fields, but still treat it as private configuration.

`egress` searches CLI, client, core and provider source for literal hosts. It
cannot enumerate dynamically constructed URLs or prove which hosts execute.

## Migration behavior

The installer upgrades owned V1 copies, leaves existing V2 copies unless forced,
and refuses to shadow an external installation. It verifies the major version
before writing native preferences and restores the previous executable if the
installer or verification fails. `DOTFILES_OPENCODE_VERSION=2.0.22` selects an
explicit stable V2 release. Normal updates follow the stable V2 feed.

`bin/ai-config opencode` retains V1's supported `autoupdate` spelling until a V2
binary is available, then replaces it with `update`. Configuration is backed up
by the normal preferences reconciler. The installer retains a previous binary
in the temporary directory it reports; back up session data separately before
major-version changes. Never run V1 against native V2-only configuration.

V2 normally uses a shared background service. `opencode service set disabled true`
selects private servers for local commands; `opencode service unset disabled`
restores the shared default. Explicit `run --standalone` is suitable for probes.
Updates stop an existing V2 service before replacing its executable.
