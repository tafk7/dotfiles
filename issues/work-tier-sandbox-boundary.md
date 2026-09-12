# Work tier and sandbox selection

Status: decision deferred; existing CLI behavior is preserved.

`--work` currently includes NVM, Rust, Docker, and sbx/KVM readiness. This is
appropriate for native sandbox hosts but excludes WSL and restricted VMs from
the broader work-tool selection.

Proposal: separate sandbox readiness into an orthogonal selection. Before
implementing it, decide the transition for existing `--work` and `--full` users,
including setup help, verification, documentation, and compatibility tests.
Do not silently change the meaning of either existing flag.
