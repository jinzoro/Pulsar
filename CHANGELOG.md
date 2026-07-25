# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-07-25

### Added

- **REST API Gateway (`apigateway`)** — New Go binary wrapping the Proxmox client as a secure HTTP/HTTPS REST API on `:8443` with:
  - Full CRUD for VMs, containers, storage, pools, snapshots, backups, firewall rules, and HA groups
  - Cluster, node, and network status/inspection endpoints
  - Real-time cluster and node metrics aggregation
  - Prometheus `/metrics` endpoint with request counters, duration histograms, and active request gauge
  - X-API-Key and Bearer token authentication with CORS enabled
  - Structured zerolog logging with request ID tracing
  - Config via `apigateway.yaml` or env vars (`APIGW_*` prefix)
- **`go/internal/apiserver/` package** — Reusable module with `Server`, `Config`, middleware stack, routing, and handler injection
- **Web UI (**``**web/`)** — New SvelteKit single-page application with PegaProx-inspired dark theme:
  - Dashboard with cluster overview, VM/node summary cards, and tables
  - VM list, detail, and power actions (start/stop/shutdown)
  - Container list and detail views
  - Node list and detail views
  - Storage list with usage bar charts
  - Settings page with API gateway status
  - Vite dev proxy to Go API gateway at `:8443`
  - Static adapter builds to `web/build/` for production deployment
- **Makefile integration** — `apigateway` binary builds alongside existing CLIs via `make build`

### Changed

- **Makefile**: `CMDS` now includes `apigateway` (4 binaries total)
- **Proxmox client**: `GetVMNode` exported as public method (previously unexported `resolveVMNode`)
- **Version**: Bumped from 1.0.0 to 1.1.0

## [1.0.0] - 2024-01-01

### Added

- **Unified CLI (`swissknife`)** — Single entry point wrapping `pmxctl` and `kvmctl` with cluster-wide operations and status overview
- **Proxmox control CLI (`pmxctl`)** — Full lifecycle management of VMs, containers, storage, networking, backups, snapshots, and cluster operations via the Proxmox REST API
- **KVM/libvirt control CLI (`kvmctl`)** — Local hypervisor management through libvirt including VM creation, snapshot, migration, and PCI passthrough
- **Interactive TUI dashboard** — Real-time terminal UI built with Bubble Tea / Lip Gloss showing VM status, resource utilization, quick actions, backup status, and notification log with vim-style keybindings
- **Go API client library** — Type-safe, well-documented Proxmox VE and libvirt client packages with automatic token refresh, retry logic, and connection pooling
- **Packer image templates** — HCL2 templates for Ubuntu 22.04/24.04, Debian 12, Rocky Linux 9, and Windows Server 2022 golden image builds on Proxmox
- **Ansible playbooks and roles** — Idempotent roles for host provisioning, security hardening, user management, package installation, firewall configuration, and post-install automation
- **Terraform modules** — Reusable infrastructure-as-code modules for provisioning Proxmox VMs, virtual networks, and storage from CI/CD pipelines
- **Backup integration** — Proxmox Backup Server (PBS) support for scheduled snapshots, retention policies, restore operations, and backup verification
- **Multi-channel notification engine** — Alerts via Slack, Telegram, email (SMTP), and ntfy for job completions, failures, and resource threshold warnings
- **Structured logging** — JSON-formatted logging with configurable levels, optional file output, and log rotation support
- **Environment-based configuration** — `.env` file support for secrets and credentials with `settings.yaml` for operational defaults
- **Makefile** — Comprehensive build system with targets for building, testing, linting, formatting, installing, and cleaning
- **Test suites** — Bats integration tests, pytest unit tests, and Go test suite with race detection and coverage reporting
- **CI/CD linting** — ShellCheck for Bash, Ruff for Python, golangci-lint for Go, ansible-lint for Ansible, and tflint for Terraform
- **Documentation** — Full README with quick start, architecture guide, API reference, and operational runbooks

### Security

- API token authentication for all Proxmox interactions — no plaintext passwords stored or transmitted
- SSH key-based authentication supported with configurable key paths
- `.env` files excluded from version control via `.gitignore`
- Sensitive credential handling with environment variable precedence over config files
- All API traffic uses HTTPS/TLS with certificate verification enabled by default
- Ansible vault integration ready for encrypted secret management
- Vault pass files and private keys excluded from repository

### Dependencies

- **Go 1.22+** — Runtime and toolchain
- **Python 3.11+** — Ansible, scripts, and pytest
- **Bubble Tea v0.26+** — Terminal UI framework
- **Lip Gloss v0.12+** — Terminal styling
- **Proxmox VE API client library** — Go bindings for the Proxmox REST API
- **libvirt/go bindings** — Go bindings for libvirt
- **Ansible 2.16+** — Configuration management
- **Packer 1.10+** — Image building
- **Terraform 1.7+** — Infrastructure provisioning
- **golangci-lint 1.56+** — Go linting
- **Ruff 0.2+** — Python linting and formatting
- **ShellCheck 0.10+** — Bash linting
- **Bats 1.11+** — Bash testing framework
