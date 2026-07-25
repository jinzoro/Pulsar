<div align="center">

<img src="Public/logos/Logo.png" alt="Pulsar" width="400" style="border-radius:16px;" />

*Unified automation suite for Proxmox VE clusters, KVM/libvirt, and golden-image pipelines*

[![Version](https://img.shields.io/badge/Release-1.1.0-14b8a6?style=for-the-badge&logo=github&logoColor=white)](CHANGELOG.md)
[![License](https://img.shields.io/badge/License-MIT-3b82f6?style=for-the-badge)](LICENSE)
[![PRs](https://img.shields.io/badge/PRs-Welcome-22c55e?style=for-the-badge&logo=github&logoColor=white)](https://github.com/yourorg/pulsar/pulls)

[![Go](https://img.shields.io/badge/Go-1.22%2B-00ADD8?style=for-the-badge&logo=go&logoColor=white)](/go)
[![Python](https://img.shields.io/badge/Python-3.11%2B-3776AB?style=for-the-badge&logo=python&logoColor=white)](/tests/pytest)
[![Svelte](https://img.shields.io/badge/Svelte-5-FF3E00?style=for-the-badge&logo=svelte&logoColor=white)](/web)
[![TypeScript](https://img.shields.io/badge/TypeScript-5-3178C6?style=for-the-badge&logo=typescript&logoColor=white)](/web/src)
[![Bash](https://img.shields.io/badge/Bash-5%2B-4EAA25?style=for-the-badge&logo=gnubash&logoColor=white)](/proxmox)
[![Ansible](https://img.shields.io/badge/Ansible-2.16%2B-EE0000?style=for-the-badge&logo=ansible&logoColor=white)](https://github.com/ansible/ansible)
[![Terraform](https://img.shields.io/badge/Terraform-1.7%2B-7B42BC?style=for-the-badge&logo=terraform&logoColor=white)](https://github.com/hashicorp/terraform)
[![Packer](https://img.shields.io/badge/Packer-1.10%2B-02A8EF?style=for-the-badge&logo=packer&logoColor=white)](/packer)

[![Proxmox](https://img.shields.io/badge/Proxmox_VE_8-E57000?style=for-the-badge&logo=proxmox&logoColor=white)](https://www.proxmox.com)
[![Prometheus](https://img.shields.io/badge/Metrics-Prometheus-E6522C?style=for-the-badge&logo=prometheus&logoColor=white)](/go/internal/apiserver)
[![Bubble Tea](https://img.shields.io/badge/TUI-Bubble_Tea-FF6B6B?style=for-the-badge)](https://github.com/charmbracelet/bubbletea)
[![adapter-static](https://img.shields.io/badge/SPA-SvelteKit-000000?style=for-the-badge&logo=svelte&logoColor=white)](/web)

</div>

---

## 📦 Features

| Layer | Description |
|-------|-------------|
| 🌐 **Web UI** | SvelteKit 5 SPA with dark theme — dashboard, VM/CT/node/storage views, power actions, dev proxy |
| 🔌 **REST API** | Go gateway on `:8443` with 40+ endpoints, X-API-Key/Bearer auth, CORS, Prometheus metrics |
| 🖥 **TUI** | Bubble Tea interactive dashboard — real-time VM status, sparklines, vim-style keyboard navigation |
| 🛠 **CLI** | Single `swissknife` binary wrapping `pmxctl` + `kvmctl` with consistent interface |
| 🖼 **Packer** | HCL2 templates for Ubuntu, Debian, Rocky, Windows Server golden images on Proxmox |
| 📋 **Ansible** | 23 idempotent roles + 15 playbooks for fleet provisioning, hardening, and automation |
| 🏗 **Terraform** | Reusable IaC modules for VMs, networks, storage from CI/CD pipelines |
| 💾 **Backup** | PBS integration with scheduled snapshots, retention policies, disaster recovery |
| 🔔 **Notifications** | Multi-channel alerts — Slack, Telegram, email, ntfy |
| 📊 **Observability** | Structured JSON logging, Prometheus metrics, audit trails |

---

## 🚀 Quick Start

```bash
git clone https://github.com/yourorg/pulsar.git
cd pulsar
cp .env.example .env   # Edit with your Proxmox credentials
make build             # Build all Go binaries
```

| Command | What it does |
|---------|-------------|
| `make tui` | Launch interactive TUI dashboard |
| `./bin/apigateway.exe` | Start REST API gateway on `:8443` |
| `cd web && npm run dev` | Start SvelteKit dev server (proxies `/api` → `:8443`) |
| `./bin/swissknife status` | Cluster overview |
| `./bin/pmxctl vm list -n pve1` | List VMs on node |
| `./bin/kvmctl list --all` | List local libvirt domains |

> **Prerequisites:** Go 1.22+, Python 3.11+, Packer 1.10+, Ansible 2.16+, Terraform 1.7+, Proxmox VE 8.x

---

## 📁 Structure

```
pulsar/
├── config/           # Settings, templates
├── docs/             # Architecture, API ref, runbooks
├── go/               # Go source (CLI, API, TUI, client libs)
│   ├── cmd/          # Entry points
│   ├── internal/     # apiserver, pmx, kvm, tui, notify, config
│   └── pkg/          # Public packages
├── kvm/              # libvirt helpers
├── packer/           # HCL2 image templates
├── proxmox/          # Proxmox scripts
├── tests/            # BATS, pytest, Go test suites
└── web/              # SvelteKit SPA
```

---

## 🧩 Modules

<details>
<summary><strong>pmxctl</strong> — Proxmox CLI</summary>

```bash
pmxctl vm list --node pve1
pmxctl vm create --name web-01 --node pve1 --template ubuntu-2204 --cores 4 --memory 8192
pmxctl vm snapshot create --vmid 101 --name pre-upgrade
pmxctl vm backup --vmid 101 --storage local --mode snapshot
pmxctl cluster status
```
</details>

<details>
<summary><strong>kvmctl</strong> — KVM/libvirt CLI</summary>

```bash
kvmctl list --all
kvmctl create --name dev-vm --cpus 4 --ram 8G --disk 50G
kvmctl snapshot --name dev-vm --label daily
kvmctl migrate --name dev-vm --dest pve2
```
</details>

<details>
<summary><strong>swissknife</strong> — Unified CLI + TUI</summary>

```bash
swissknife status          # Cluster overview
swissknife vm list         # VMs across all nodes
swissknife backups list    # Recent backups
swissknife tui             # Launch interactive dashboard
```

**TUI hotkeys:** `j/k` navigate · `Enter` select · `s` start · `S` stop · `r` restart · `b` snapshot · `/` search · `?` help · `q` quit
</details>

<details>
<summary><strong>apigateway</strong> — REST API server</summary>

```
GET/POST   /api/v1/vms                  List / create VMs
GET/DELETE /api/v1/vms/{vmid}           VM detail / delete
POST       /api/v1/vms/{vmid}/start     Power on
POST       /api/v1/vms/{vmid}/stop      Power off
POST       /api/v1/vms/{vmid}/shutdown  Graceful shutdown
POST       /api/v1/vms/{vmid}/clone     Clone VM
POST       /api/v1/vms/{vmid}/resize    Resize VM
POST       /api/v1/vms/{vmid}/migrate   Migrate VM
GET/POST   /api/v1/vms/{vmid}/snapshots Snapshot management
GET/POST   /api/v1/containers           Container operations
GET        /api/v1/nodes                Node list / detail
GET        /api/v1/cluster/status       Cluster health
GET        /api/v1/storage              Storage status
GET/POST   /api/v1/backups              Backup operations
GET/POST   /api/v1/pools                Pool management
GET        /api/v1/ha/groups            HA group status
GET        /api/v1/firewall/rules        FW rules
GET        /api/v1/metrics              Prometheus metrics
```

Configure with env prefix `APIGW_` or `apigateway.yaml`.
</details>

---

## ⚙️ Configuration

| Variable | Required | Description |
|----------|----------|-------------|
| `PMX_API_URL` | ✅ | Proxmox API endpoint |
| `PMX_USER` | ✅ | Auth user (e.g. `root@pam`) |
| `PMX_TOKEN_ID` | ✅ | API token ID |
| `PMX_TOKEN_SECRET` | ✅ | API token secret |
| `PMX_NODE` | ✅ | Default target node |
| `SSH_USER` | ❌ | SSH username |

Full config reference in [`config/settings.yaml`](config/settings.yaml).

---

## 🔨 Makefile

| Target | Description |
|--------|-------------|
| `build` | Build all Go binaries |
| `tui` | Build + launch TUI |
| `test` | Full test suite (bats, pytest, Go) |
| `lint` | All linters (shellcheck, ruff, golangci-lint, ansible-lint, tflint) |
| `install` | Install binaries to `/usr/local/bin` |
| `clean` | Remove build artifacts |
| `packer-build` | Build all Packer images |
| `ansible-check` | Syntax-check playbooks |
| `fmt` | Format all code |

---

## 🤝 Contributing

```bash
git checkout -b feature/my-feature
# make changes with tests
make test && make lint
git commit -m "feat(pmxctl): add my feature"
git push origin feature/my-feature
```

Follow [Effective Go](https://go.dev/doc/effective-go) and [Google Python Style Guide](https://google.github.io/styleguide/pyguide.html). Use [Conventional Commits](https://www.conventionalcommits.org/).

---

<div align="center">

<sub>Built with ❤️ for Proxmox administrators · MIT License</sub>

</div>
