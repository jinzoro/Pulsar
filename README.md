# proxmox-kvm-swissknife

![Version](https://img.shields.io/badge/version-1.0.0-blue)
![License](https://img.shields.io/badge/license-MIT-green)
![Go](https://img.shields.io/badge/go-1.22+-00ADD8?logo=go&logoColor=white)
![Python](https://img.shields.io/badge/python-3.11+-3776AB?logo=python&logoColor=white)
![Bash](https://img.shields.io/badge/bash-5+-4EAA25?logo=gnubash&logoColor=white)
![Proxmox](https://img.shields.io/badge/proxmox-VE%208+-E57000?logo=proxmox&logoColor=white)

A comprehensive, opinionated automation suite for managing Proxmox VE clusters, KVM virtual machines, Packer image builds, and Ansible orchestration — all from a unified CLI with a rich terminal UI.

## Features

- **Unified CLI** — Single `swissknife` binary wrapping `pmxctl` and `kvmctl` subcommands
- **Rich TUI** — Interactive terminal dashboard built with Bubble Tea / Lip Gloss for real-time VM monitoring, resource overview, and quick actions
- **Proxmox API Client** — Full lifecycle management of VMs, containers, storage, networking, backups, and cluster operations via the Proxmox REST API
- **KVM/libvirt Toolkit** — Local hypervisor management through libvirt, including VM creation, snapshot, migration, and PCI passthrough configuration
- **Packer Templates** — Pre-configured HCL2 templates for building golden images (Ubuntu, Debian, Rocky, Windows Server) on Proxmox
- **Ansible Playbooks** — Idempotent roles for host provisioning, security hardening, package management, user setup, and post-install automation
- **Terraform Modules** — Reusable infrastructure-as-code modules for provisioning Proxmox VMs, networks, and storage from CI/CD pipelines
- **Backup & Restore** — Tight integration with Proxmox Backup Server (PBS) for scheduled snapshots, retention policies, and disaster recovery
- **Notification Engine** — Multi-channel alerts (Slack, Telegram, email, ntfy) for job completions, failures, and resource threshold warnings
- **Observability** — Structured JSON logging, optional Prometheus metrics endpoint, and exportable audit trails
- **Test Suite** — Bats, pytest, and Go test coverage for all modules with CI-ready configurations
- **Makefile-Driven** — Consistent developer experience with lint, build, test, and install targets

## Quick Start

### Prerequisites

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| Go | 1.22 | Building CLI binaries |
| Python | 3.11 | Ansible playbooks and scripts |
| Packer | 1.10 | Building VM images |
| Ansible | 2.16 | Configuration management |
| Terraform | 1.7 | Infrastructure provisioning |
| Proxmox VE | 8.x | Target hypervisor cluster |
| jq | 1.7 | JSON processing in scripts |
| shellcheck | 0.10 | Bash linting |

### Clone & Configure

```bash
git clone https://github.com/yourorg/proxmox-kvm-swissknife.git
cd proxmox-kvm-swissknife

cp .env.example .env
# Edit .env with your Proxmox API credentials and preferences
```

### First Run

```bash
# Build all binaries
make build

# Run the interactive TUI
make tui

# Or use the CLI directly
./bin/swissknife status
./bin/pmxctl vm list --node pve1
./bin/kvmctl list
```

## Directory Structure

```
proxmox-kvm-swissknife/
├── config/                  # Default configuration files
│   ├── settings.yaml        # Global settings
│   └── templates/           # Packer and Terraform variable templates
├── docs/                    # Documentation
│   ├── architecture.md      # System architecture overview
│   ├── api-reference.md     # CLI command reference
│   └── runbooks/            # Operational runbooks
├── go/                      # Go source code
│   ├── cmd/                 # CLI entry points
│   │   ├── swissknife/      # Main unified CLI
│   │   ├── pmxctl/          # Proxmox control CLI
│   │   └── kvmctl/          # KVM/libvirt control CLI
│   ├── internal/            # Internal packages
│   │   ├── pmx/             # Proxmox API client
│   │   ├── kvm/             # libvirt/libkvm client
│   │   ├── tui/             # Bubble Tea TUI components
│   │   ├── notify/          # Notification dispatcher
│   │   ├── config/          # Config loader
│   │   └── logging/         # Structured logging
│   ├── pkg/                 # Public reusable packages
│   ├── go.mod               # Go module definition
│   └── go.sum               # Go module checksums
├── kvm/                     # KVM/libvirt helper scripts and templates
├── packer/                  # Packer HCL2 templates
│   ├── ubuntu/              # Ubuntu image builds
│   ├── debian/              # Debian image builds
│   ├── rocky/               # Rocky Linux image builds
│   └── windows/             # Windows Server image builds
├── proxmox/                 # Proxmox-specific configs and scripts
├── shared/                  # Shared utilities and libraries
├── tests/                   # Test suites
│   ├── bats/                # Bash automated testing system tests
│   ├── pytest/              # Python test suite
│   └── go/                  # Go test suite
├── .env.example             # Environment variable template
├── .gitignore               # Git ignore rules
├── Makefile                 # Build and task automation
├── CHANGELOG.md             # Release changelog
├── LICENSE                  # MIT License
└── README.md                # This file
```

## Modules

### `pmxctl` — Proxmox Control CLI

A purpose-built command-line tool for Proxmox VE operations.

```bash
pmxctl vm list --node pve1
pmxctl vm create --name web-01 --node pve1 --template ubuntu-2204 --cores 4 --memory 8192
pmxctl vm snapshot create --vmid 101 --name pre-upgrade
pmxctl vm backup --vmid 101 --storage local --mode snapshot
pmxctl cluster status
pmxctl storage list --node pve1
pmxctl network list --node pve1
```

### `kvmctl` — KVM/libvirt Control CLI

Local hypervisor management via libvirt.

```bash
kvmctl list --all
kvmctl create --name dev-vm --cpus 4 --ram 8G --disk 50G --iso /var/lib/libvirt/images/ubuntu-22.04.iso
kvmctl snapshot --name dev-vm --label daily
kvmctl migrate --name dev-vm --dest pve2
kvmctl pci-list --node pve1
```

### `swissknife` — Unified CLI

Wraps both `pmxctl` and `kvmctl` with a consistent interface and adds cluster-wide operations.

```bash
swissknife status              # Overview of all nodes
swissknife vm list             # List VMs across all nodes
swissknife backups list        # List recent backups
swissknife alerts              # Check notification channels
swissknife tui                 # Launch interactive dashboard
```

### TUI Dashboard

The interactive terminal UI provides:

- Real-time VM status and resource utilization (CPU, RAM, disk, network)
- Node health overview with load averages and uptime
- Quick actions: start, stop, restart, snapshot, backup
- Backup status and next scheduled run
- Notification log with recent alerts
- Keyboard-driven navigation with vim-style bindings

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and fill in your credentials:

```bash
cp .env.example .env
```

Key variables:

| Variable | Description | Required |
|----------|-------------|----------|
| `PMX_API_URL` | Proxmox VE API endpoint (e.g., `https://pve1.example.com:8006`) | Yes |
| `PMX_USER` | API authentication user (e.g., `root@pam`) | Yes |
| `PMX_TOKEN_ID` | API token identifier | Yes |
| `PMX_TOKEN_SECRET` | API token secret | Yes |
| `PMX_NODE` | Default Proxmox node name | Yes |
| `SSH_USER` | SSH username for remote operations | No |
| `SSH_KEY_PATH` | Path to SSH private key | No |
| `SLACK_WEBHOOK_URL` | Slack incoming webhook URL | No |
| `TELEGRAM_BOT_TOKEN` | Telegram bot API token | No |
| `TELEGRAM_CHAT_ID` | Telegram chat ID for notifications | No |

### `settings.yaml`

Located at `config/settings.yaml`. Controls default behaviors:

```yaml
defaults:
  node: pve1
  storage: local-lvm
  bridge: vmbr0
  ostype: l26

backup:
  enabled: true
  storage: local
  mode: snapshot
  retention:
    daily: 7
    weekly: 4
    monthly: 6

notifications:
  enabled: false
  channels:
    - type: slack
      enabled: false
    - type: telegram
      enabled: false
    - type: email
      enabled: false
    - type: ntfy
      enabled: false

logging:
  level: info
  format: json
  output: stdout
  file: /var/log/swissknife.log

tui:
  refresh_interval: 5
  theme: dark
  show_header: true
```

## TUI Usage

```bash
# Launch the TUI dashboard
make tui
# or
./bin/swissknife tui

# Keyboard shortcuts:
#   j/k       Navigate up/down
#   Enter     Select / expand
#   s         Start selected VM
#   S         Stop selected VM
#   r         Restart selected VM
#   b         Create snapshot
#   /         Search / filter
#   ?         Show help
#   q/Esc     Quit
```

## Makefile Targets

Run `make help` to see all available targets:

| Target | Description |
|--------|-------------|
| `make help` | Display all available targets (default) |
| `make build` | Build all Go binaries (`swissknife`, `pmxctl`, `kvmctl`) |
| `make tui` | Build and launch the interactive TUI |
| `make test` | Run the full test suite (bats, pytest, Go) |
| `make lint` | Run all linters (shellcheck, ruff, golangci-lint, ansible-lint, tflint) |
| `make install` | Install Go binaries to `/usr/local/bin` |
| `make clean` | Remove build artifacts and cache directories |
| `make packer-build` | Build all Packer image templates |
| `make ansible-check` | Syntax-check all Ansible playbooks |
| `make fmt` | Format all source code (gofmt, black, shfmt) |
| `make tidy` | Run `go mod tidy` and pip-compile |

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/my-feature`)
3. Make your changes with tests
4. Run the full test and lint suite: `make test && make lint`
5. Commit your changes (`git commit -am 'Add my feature'`)
6. Push to the branch (`git push origin feature/my-feature`)
7. Open a Pull Request

### Development Guidelines

- Follow [Effective Go](https://go.dev/doc/effective-go) conventions for Go code
- Use [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html) for Python
- Run `shellcheck` on all Bash scripts before committing
- Ansible roles must pass `ansible-lint` with zero warnings
- All Packer templates must validate with `packer validate`
- Write tests for new functionality and update this README

### Commit Convention

Use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat(pmxctl): add VM migration command
fix(notify): resolve Slack webhook timeout
docs(readme): update installation steps
chore(deps): bump go dependencies
```

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.
