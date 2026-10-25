# Work tier and sandbox selection

Status: decided ([setup redesign](setup-update-redesign.md), decision 4).

`--work` used to require native Ubuntu 24.04/26.04 with KVM, because it
included sbx/KVM readiness, which excluded WSL and Ubuntu 22.04 from the
broader work tools (NVM, Docker, Rust).

Decision: `--work` installs the work tools the platform supports. Where sbx is
not applicable (WSL, Ubuntu 22.04, an unsupported architecture) it records sbx
as not applicable and skips KVM access and the kit builder; verification still
checks Docker readiness and skips the sandbox checks. A native host where sbx
applies but KVM is unusable keeps the previous behavior: install, warn, and
report readiness in verification. `--full` stays exactly `--work --ai`.
