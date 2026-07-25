# TUI Application Guide

The Pulsar TUI (Terminal User Interface) is a rich, interactive dashboard built with [Bubble Tea](https://github.com/charmbracelet/bubbletea) and [Lip Gloss](https://github.com/charmbracelet/lipgloss). It provides real-time monitoring and management of your Proxmox cluster and KVM hosts from a single terminal window.

---

## Installation and Build

### Build from source

```bash
cd pulsar
make build
```

This produces `bin/swissknife.exe` (Windows) or `bin/swissknife` (Linux/macOS).

### Install to PATH

```bash
make install
```

Copies binaries to `/usr/local/bin/`.

### Launch TUI

```bash
# Via Makefile
make tui

# Via binary directly
./bin/swissknife tui

# Or with config override
./bin/swissknife tui --config /path/to/config.yaml

# Or with log level
./bin/swissknife tui --log-level debug
```

---

## First Run and Configuration

### Initial setup

1. Copy `.env.example` to `.env` and fill in your Proxmox API credentials:

```bash
cp .env.example .env
```

2. Edit `config/settings.yaml` with your cluster defaults:

```yaml
defaults:
  node: pve1
  storage: local-lvm
  bridge: vmbr0
```

3. Launch the TUI:

```bash
make tui
```

### Configuration file

The TUI reads configuration from `~/.config/swissknife/config.yaml`:

```yaml
# Theme: default, dark, light, monokai, solarized
theme: dark

# Dashboard auto-refresh interval in seconds
refresh_interval: 5

# Default view on startup
default_view: overview

# Logging level for the TUI
log_level: info
```

### Connection

On first launch, the TUI connects to your Proxmox API using the credentials from:
1. CLI flags (`--api-url`, `--api-token-id`, `--api-token-secret`)
2. Environment variables (`PMX_API_URL`, `PMX_TOKEN_ID`, `PMX_TOKEN_SECRET`)
3. `.env` file in the project root
4. `config/settings.yaml` under the `proxmox.hosts` section

---

## Navigation Guide

### Keyboard Shortcuts

| Key | Action |
|-----|--------|
| `↑` / `k` | Move cursor up |
| `↓` / `j` | Move cursor down |
| `←` / `h` | Previous tab / collapse |
| `→` / `l` / `Enter` | Select item / expand / enter submenu |
| `Tab` | Next tab / next section |
| `Shift+Tab` | Previous tab / previous section |
| `/` | Search / filter |
| `Esc` | Back / close search / deselect |
| `q` / `Ctrl+c` | Quit |
| `?` | Show help overlay |
| `r` | Refresh data |
| `R` | Force hard refresh (clear cache) |

### Action Shortcuts (VM/Container focused)

| Key | Action |
|-----|--------|
| `s` | Start selected VM/CT |
| `S` | Stop selected VM/CT |
| `r` | Restart (reboot) selected VM/CT |
| `b` | Create snapshot of selected VM/CT |
| `B` | Backup selected VM/CT |
| `d` | Delete selected VM/CT (with confirmation) |
| `c` | Clone selected VM/CT |
| `e` | Edit configuration of selected VM/CT |
| `m` | Migrate selected VM/CT |
| `p` | Pause/suspend selected VM/CT |
| `R` | Resume selected VM/CT |
| `i` | Show details/info for selected item |

### Global Shortcuts

| Key | Action |
|-----|--------|
| `1` | Switch to Overview tab |
| `2` | Switch to VMs tab |
| `3` | Switch to Containers tab |
| `4` | Switch to Storage tab |
| `5` | Switch to Networking tab |
| `6` | Switch to Snapshots & Backups tab |
| `7` | Switch to Cluster & HA tab |
| `8` | Switch to Templates & Cloud-Init tab |
| `9` | Switch to Security & Users tab |
| `0` | Switch to Monitoring & Reports tab |
| `F1` | Switch to Performance Tuning tab |
| `F2` | Switch to Host Setup tab |
| `F3` | Switch to Utilities tab |

---

## Menu Tree

```
swissknife TUI
├── Overview
│   ├── Cluster summary (nodes, VMs, storage)
│   ├── Resource gauges (CPU, RAM, disk across cluster)
│   ├── Recent alerts and notifications
│   └── Quick action buttons
│
├── Virtual Machines
│   ├── VM list (sortable by name, node, status, CPU, memory)
│   ├── VM detail panel
│   │   ├── Status, configuration, resource usage
│   │   ├── Console output
│   │   └── Action menu (start, stop, restart, snapshot, backup, migrate, delete)
│   ├── Filter by: node, status, pool, tag
│   └── Bulk actions (select multiple, start/stop/shutdown)
│
├── Containers
│   ├── CT list (sortable)
│   ├── CT detail panel
│   ├── Filter by: node, status, template
│   └── Action menu
│
├── Storage
│   ├── Storage pool list per node
│   ├── Usage per pool (used/total, thin/thick)
│   ├── Content browser (ISOs, templates, backups, VM disks)
│   └── Actions (add, remove, resize)
│
├── Networking
│   ├── Network interface list per node
│   ├── Bridge/VLAN/SDN overview
│   ├── Firewall rule management
│   └── Actions (create bridge, add VLAN, manage rules)
│
├── Snapshots & Backups
│   ├── Snapshot list per VM
│   ├── Backup list per storage
│   ├── Backup schedule view
│   ├── PBS integration status
│   └── Actions (create snapshot, rollback, backup, restore, prune)
│
├── Cluster & HA
│   ├── Cluster status and node list
│   ├── Quorum information
│   ├── HA groups and resources
│   ├── HA state per resource
│   └── Actions (join/remove node, manage HA groups)
│
├── Templates & Cloud-Init
│   ├── Template list per node
│   ├── Cloud-Init configuration editor
│   └── Actions (create template, configure cloud-init)
│
├── Security & Users
│   ├── User list
│   ├── Group and role management
│   ├── API token management
│   ├── ACL viewer
│   └── TFA status
│
├── Monitoring & Reports
│   ├── Node health (CPU, RAM, load, disk)
│   ├── VM performance metrics
│   ├── Ceph health dashboard
│   ├── ZFS pool status
│   ├── Alert history
│   └── Exportable reports (Markdown, HTML, JSON)
│
├── Performance Tuning
│   ├── Hugepages configuration
│   ├── CPU pinning editor
│   ├── NUMA topology view
│   ├── I/O scheduler settings
│   └── Kernel parameter tuning
│
├── Host Setup
│   ├── Node maintenance (enter/exit)
│   ├── Package updates
│   ├── Reboot management
│   ├── Certificate management
│   └── System information
│
└── Utilities
    ├── SSH connection test
    ├── Ping test
    ├── Dry-run mode toggle
    ├── Configuration viewer/editor
    └── Log viewer
```

---

## View Details

### Overview Tab

The overview dashboard displays:

- **Cluster Summary**: Number of nodes online/offline, total VMs running/stopped/paused, storage pools.
- **Resource Gauges**: Cluster-wide CPU, memory, and disk usage as progress bars with percentage labels.
- **Recent Alerts**: Last 10 alerts from the notification system, color-coded by severity (green=info, yellow=warning, red=critical).
- **Quick Actions**: Buttons for common operations — Backup All, Health Check, Capacity Report.

### Virtual Machines View

- **List columns**: VMID, Name, Node, Status, CPU cores, Memory (used/max), Disk usage.
- **Sorting**: Click column headers or use keyboard shortcuts to sort.
- **Filtering**: Press `/` and type a filter string. Filter matches against name, node, or VMID.
- **Detail panel**: Select a VM and press Enter or `i` to expand the detail panel showing:
  - Full configuration (CPU, RAM, disk, network, BIOS, machine type)
  - Real-time resource usage (CPU%, RAM used, disk I/O, network I/O)
  - Recent events (start, stop, migration, backup)
  - Action menu (all lifecycle operations)

### Containers View

Similar to VMs but for LXC containers. Additional fields:
- Template status (is this a template?)
- Mount points and their usage

### Storage View

- **Pool list**: Name, type, status, content types, usage bar.
- **Content browser**: Navigate ISOs, templates, backups, VM images within a storage pool.
- **Capacity**: Shows thin provisioning ratio for thin pools (allocated vs actual usage).

### Networking View

- **Interface list**: Name, type (bridge, bond, VLAN, physical), status, IP address, speed.
- **Firewall tab**: Rules, IP sets, aliases, security groups with drag-to-reorder.
- **SDN tab**: VNet and zone configuration (if SDN is enabled).

### Snapshots & Backups View

- **Snapshot tree**: Hierarchical view of snapshots per VM (parent-child relationships).
- **Backup timeline**: Chronological view of all backups with size and age.
- **Schedule view**: Cron-based backup schedules per VM with next-run preview.
- **PBS integration**: Direct PBS datastore browser if PBS is configured.

### Cluster & HA View

- **Node map**: Visual representation of cluster nodes with status indicators.
- **Quorum**: Current quorum count, votes per node, expected quorum.
- **HA groups**: Group definitions with member nodes and priorities.
- **HA resources**: VMs/CTs managed by HA, their target groups, and current state.

### Configuration Reference

**File**: `~/.config/swissknife/config.yaml`

```yaml
# Theme options: default, dark, light, monokai, solarized
theme: dark

# Dashboard refresh interval in seconds (minimum: 1)
refresh_interval: 5

# Default view shown on startup
# Options: overview, vms, storage, network, backups
default_view: overview

# Log level for TUI output
# Options: trace, debug, info, warn, error
log_level: info

# Show header bar with cluster name and clock
show_header: true

# Show status bar with keybinding hints
show_statusbar: true

# Enable mouse support (may conflict with terminal selection)
mouse: false

# Custom column widths for VM list (percentage of terminal width)
vm_columns:
  vmid: 10
  name: 25
  node: 15
  status: 10
  cpu: 10
  memory: 15
  disk: 15
```

---

## Troubleshooting

### TUI doesn't launch

1. **Check terminal size**: Minimum 80x24 characters. Resize your terminal and try again.
2. **Check Go build**: Run `make build` and verify no errors.
3. **Check config**: Verify `~/.config/swissknife/config.yaml` is valid YAML.
4. **Debug mode**: `./bin/swissknife tui --log-level debug` shows detailed initialization output.

### Cannot connect to Proxmox

1. **Check API URL**: Must include `https://` and port `8006`.
2. **Check API token**: Verify token ID and secret are correct. Tokens are case-sensitive.
3. **Check TLS**: Self-signed certs are accepted by default. If using custom CA, add it to your system trust store.
4. **Check firewall**: Port 8006 must be open on the Proxmox node.
5. **Network test**: Press `?` and navigate to Utilities → SSH connection test.

### TUI is slow or unresponsive

1. **Increase refresh interval**: Set `refresh_interval: 10` or higher in config.
2. **Reduce cluster scope**: If managing many nodes, filter to a subset.
3. **Check network latency**: High latency to the Proxmox API will slow all operations.
4. **Check node load**: If a Proxmox node is overloaded, API responses will be slow.

### Keyboard shortcuts not working

1. **Terminal emulation**: Some terminal emulators capture certain key combinations (e.g., `Ctrl+c` in tmux). Use tmux prefix (`Ctrl+b`) before the key.
2. **SSH tunnel**: If running over SSH, ensure your terminal passes through special keys correctly.
3. **Windows Terminal**: Ensure you're using Windows Terminal, not the legacy conhost. PowerShell with Windows Terminal works best.

### Data not refreshing

1. **Press `r`** to manually trigger a refresh.
2. **Check API connectivity**: Navigate to Overview to verify cluster connection.
3. **Check log level**: `--log-level debug` will show refresh attempt logs.

### Colors look wrong

1. **Set terminal theme**: `theme: dark` works best with dark terminal backgrounds.
2. **True color support**: Ensure your terminal supports 24-bit color (most modern terminals do).
3. **Try monokai**: `theme: monokai` is designed for terminals with limited color support.
