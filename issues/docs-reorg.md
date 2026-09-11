  Audit and reorganize the architectural documentation in this dotfiles repository.

  Repository:
    /home/tkeller/dotfiles

  Objective:
  Create a clear, maintainable documentation architecture that separates:

  1. User instructions and operational guidance
  2. Current system architecture and contracts
  3. Architectural decisions and their rationale
  4. Historical implementation and migration material

  The repository already has substantial documentation, but many architectural
  decisions are embedded in docs/repository-improvement-plan.md rather than
  recorded as durable, individually discoverable decisions. Extract and organize
  those decisions without changing system behavior or losing implementation
  history.

  This is a documentation task. Do not modify shell behavior, installers,
  configuration semantics, services, machine state, or package state.

  Current documentation structure includes:

  - README.md
  - docs/architecture.md
  - docs/concepts.md
  - docs/customization.md
  - docs/repository-improvement-plan.md
  - docs/theme-system.md
  - docs/testing.md
  - docs/supply-chain.md
  - docs/ai-tools-egress.md
  - docs/opencode-contract.md
  - docs/opencode-secure.md
  - docs/THEME_QUICK_START.md
  - issues/*.md
  - plugin-specific README files
  - generated/compatibility/README.md
  - THIRD_PARTY_NOTICES.md

  The completed improvement plan is currently the de facto architectural decision
  log. Preserve it as historical documentation; do not delete it or discard its
  rationale.

  Primary tasks
  =============

  Phase 1: Audit the current documentation
  ----------------------------------------

  Inspect every Markdown file and the relevant implementation files needed to
  verify architectural claims.

  Use the live implementation, tests, and declarative tables as the authority for
  current behavior. Do not assume that every statement in the improvement plan
  still describes the final implementation.

  Build an audit covering:

  - the intended audience and purpose of every document;
  - duplicated information;
  - conflicting or stale statements;
  - architectural decisions that are documented only inside the improvement plan;
  - decisions that are implemented but insufficiently documented;
  - terms that are used without explanation;
  - broken, ambiguous, or circular cross-references;
  - documentation that mixes current-state guidance with implementation history;
  - details that belong in code comments rather than architectural documents;
  - code comments that contradict current documentation;
  - files that should remain unchanged because they serve a distinct purpose.

  Pay particular attention to these architectural areas:

  - adoption of the XDG Base Directory model;
  - separation of repository source, durable state, and rebuildable cache;
  - runtime versus installation boundaries;
  - shell Layers 0, 1, and 2;
  - Bash and Zsh invocation contracts;
  - interactive versus non-interactive and agent shell behavior;
  - cumulative package tiers and orthogonal feature flags;
  - CONFIG_MAP as the configuration ownership source of truth;
  - the component registry shared by setup, verify, reporting, and uninstall;
  - versioned preferences and component ledger;
  - locking, atomic writes, and transaction recovery;
  - ownership-constrained uninstall;
  - portable Git includes and preservation of machine-local identity;
  - theme feature isolation and neutral fallbacks;
  - global/session/window theme resolution;
  - base tmux independence from agent-badge plugins;
  - staged and pinned artifact installation;
  - testing isolation and host-mutation boundaries;
  - supported platforms and the distinction between selection-only and real
    runtime validation;
  - explicit network-listener opt-in for RDP;
  - preservation of externally owned shell functions and configuration.

  For decisions whose rationale is unclear, inspect Git history and nearby tests
  or comments. Do not invent rationale. If a conclusion is inferred rather than
  directly documented, label it as an inference in the audit.

  Before editing, produce a concise internal reorganization map showing:

    current document -> intended role -> planned action

  Then proceed with the documentation changes. Do not stop after the audit unless
  you discover a material contradiction that cannot be resolved from the
  repository.

  Phase 2: Establish a formal ADR collection
  ------------------------------------------

  Create:

    docs/decisions/README.md
    docs/decisions/0000-template.md

  Use a lightweight ADR format:

    # ADR NNNN: Title

    - Status:
    - Date:
    - Scope:
    - Supersedes:
    - Superseded by:

    ## Context
    ## Decision
    ## Alternatives considered
    ## Consequences
    ## Implementation references

  Use “Accepted” only for decisions clearly reflected by the current
  implementation. Use “Historical” or “Superseded” where appropriate. Do not
  fabricate exact decision dates; use an evidence-backed date when available or
  state that the original decision date was not recorded.

  Extract a coherent set of ADRs. Begin with the following candidate list, but
  merge, split, rename, or omit candidates when the repository evidence supports
  a better boundary:

  1. Use XDG directories for configuration, durable state, and cache
  2. Keep the checkout out of the machine-state database
  3. Separate shell startup into runtime layers
  4. Define explicit Bash and Zsh invocation contracts
  5. Use cumulative installation tiers with orthogonal optional features
  6. Use declarative configuration ownership through CONFIG_MAP
  7. Use a shared component registry across the tool lifecycle
  8. Use versioned state, bounded locking, atomic writes, and recovery journals
  9. Restrict uninstall to recorded ownership and allowlisted roots
  10. Preserve user Git configuration through an include-based portable layer
  11. Isolate themes as an optional feature with neutral fallbacks
  12. Resolve themes across global, tmux-session, and tmux-window scopes
  13. Keep base tmux independent from AI agent-badge plugins
  14. Stage and validate managed artifact replacements
  15. Isolate tests from the operator’s HOME, XDG roots, PATH, and tmux server
  16. Keep RDP an explicit opt-in outside --full
  17. Preserve externally owned shell state and functions

  Each ADR should explain why the decision exists, not merely restate what the
  code does. Keep ADRs concise and link to the authoritative implementation and
  detailed operational documentation.

  Phase 3: Give each existing document a clear role
  -------------------------------------------------

  Organize the documentation according to these principles:

  README.md
    Quick start, feature overview, common commands, and a short navigation map.
    Keep it useful to someone installing or using the dotfiles. Avoid turning it
    into a full architecture reference.

  docs/concepts.md
    The approachable mental model: tiers, configuration mapping, registry, state,
    shell layers, and theme cascade. Explain foundational terms such as XDG.

  docs/architecture.md
    The canonical description of the current system. State contracts and
    boundaries, not migration history. Link to ADRs for rationale.

  docs/customization.md
    Task-oriented recipes for safely extending the system.

  docs/theme-system.md
    Detailed theme behavior and scope-resolution reference.

  docs/testing.md
    Test strategy, isolation rules, supported-platform confidence, and manual
    validation boundaries.

  docs/supply-chain.md
    Download, pinning, integrity, staging, and replacement policy.

  docs/ai-tools-egress.md
    AI CLI egress and hardening behavior.

  docs/repository-improvement-plan.md
    Preserve as a completed historical implementation plan. Add a prominent
    status notice stating that the plan has been executed, that current
    architecture is documented elsewhere, and that ADRs contain the durable
    decisions. Do not erase gate history, rationale, or implementation sequence.

  docs/decisions/
    Durable architectural rationale and consequences.

  issues/
    Unresolved, deferred, or environment-specific investigations—not canonical
    architecture.

  Plugin README files
    Installation and operation of the corresponding self-contained plugin.

  Add or improve a small documentation navigation section that helps readers
  choose the correct document.

  Phase 4: Explain XDG from first principles
  ------------------------------------------

  Add a concise explanation of XDG to the appropriate introductory document,
  probably docs/concepts.md, and link to it from architecture.md where needed.

  Cover:

  - that XDG refers to the freedesktop.org Base Directory convention;
  - XDG_CONFIG_HOME, XDG_DATA_HOME, XDG_STATE_HOME, and XDG_CACHE_HOME;
  - their normal default paths;
  - the distinction between durable state and rebuildable cache;
  - how this repository uses each relevant directory;
  - why the Git checkout is not an appropriate durable state store;
  - how environment-variable overrides preserve portability.

  Do not repeat the full explanation in several documents. Establish one
  canonical explanation and link to it.

  Phase 5: Remove ambiguity and excessive duplication
  ---------------------------------------------------

  Where several documents repeat the same architectural explanation:

  - select one canonical source;
  - retain a short context-appropriate summary elsewhere;
  - link to the canonical source;
  - do not remove useful task-oriented examples merely because the underlying
    concept is documented elsewhere.

  Preserve useful redundancy when it helps different audiences, but avoid having
  multiple documents independently define the same contract.

  Resolve stale terminology and inconsistent names. Ensure terms such as the
  following have one stable meaning:

  - Layer 0 / Layer 1 / Layer 2
  - durable state
  - generated state
  - rebuildable cache
  - component ownership
  - feature preference
  - package tier
  - optional or orthogonal feature
  - managed configuration
  - machine-local configuration
  - selection-only architecture validation
  - live-process synchronization

  Phase 6: Cross-link and validate
  --------------------------------

  Update relative links after reorganizing content.

  Ensure that:

  - README.md points to concepts, architecture, customization, testing, themes,
    supply-chain policy, and the ADR index;
  - architecture.md links to relevant ADRs;
  - ADRs link back to implementation files and detailed documentation;
  - the completed improvement plan points to the current architecture and ADR
    index;
  - no document treats checkout-local generated files as the durable source of
    truth;
  - no document implies that --full enables RDP;
  - no document implies that base tmux requires an agent-badge plugin;
  - no document recommends deleting externally owned functions or user
    configuration;
  - no document claims rollback guarantees for package managers or moving vendor
    installers that cannot provide them.

  Validation requirements
  =======================

  Do not run setup.sh or any host-mutating command.

  At minimum:

  1. Run `git diff --check`.
  2. Validate that every relative Markdown link points to an existing target.
  3. Search for stale references to moved or renamed headings/files.
  4. Compare architectural claims against:
     - lib/config.sh
     - lib/registry.sh
     - lib/state.sh
     - shell/env-runtime.sh
     - shell/env.sh
     - shell/init.sh
     - entry/bash.sh
     - entry/zshenv
     - entry/zsh.sh
     - bin/theme-switcher
     - bin/verify
     - bin/uninstall-tool
     - relevant tests
  5. Run any existing non-mutating documentation or repository validation that is
     appropriate for documentation-only changes.
  6. Confirm that no non-documentation behavior changed.
  7. Report the final working-tree diff and any intentionally deferred issues.

  Constraints
  ===========

  - Preserve unrelated user changes.
  - Do not choose a repository license; that remains an owner decision.
  - Do not rewrite or remove THIRD_PARTY_NOTICES.md except to fix an objectively
    broken link.
  - Do not discard historical material from the completed improvement plan.
  - Do not add speculative rationale.
  - Prefer concise documents connected by links over one giant replacement
    document.
  - Keep examples synchronized with actual commands and file paths.
  - Use ASCII diagrams when they materially clarify hierarchy or data flow.
  - Avoid cosmetic churn unrelated to the reorganization.
  - Do not change executable code merely to make documentation easier to write.

  Definition of done
  ==================

  The work is complete when:

  - a new reader can understand what XDG means and how this repository uses it;
  - current architecture has a single authoritative home;
  - major architectural decisions are represented by indexed ADRs;
  - implementation history remains available but is clearly labeled historical;
  - user guides remain concise and task-oriented;
  - duplicated contracts have an identified canonical source;
  - cross-references are valid;
  - documentation agrees with the live implementation and tests;
  - the final report lists:
    - files added, moved, and substantially changed;
    - ADRs created;
    - contradictions or stale claims corrected;
    - decisions that could not be verified;
    - intentionally deferred work;
    - validation commands and their results.


