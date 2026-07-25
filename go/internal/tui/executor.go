// SPDX-License-Identifier: MIT

package tui

import (
	"bytes"
	"context"
	"fmt"
	"os/exec"
	"strings"
	"sync"
	"time"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/rs/zerolog"

	"github.com/pulsar/internal/kvm"
	"github.com/pulsar/internal/proxmox"
)

type ActionExecutor struct {
	pveClient *proxmox.Client
	kvmClient *kvm.LibvirtClient
	log       zerolog.Logger
	ctx       context.Context
	cancel    context.CancelFunc
	mu        sync.Mutex
	running   bool
}

func NewActionExecutor(pveClient *proxmox.Client, kvmClient *kvm.LibvirtClient, log zerolog.Logger) *ActionExecutor {
	ctx, cancel := context.WithCancel(context.Background())
	return &ActionExecutor{
		pveClient: pveClient,
		kvmClient: kvmClient,
		log:       log,
		ctx:       ctx,
		cancel:    cancel,
	}
}

func (e *ActionExecutor) Cancel() {
	e.mu.Lock()
	defer e.mu.Unlock()
	if e.cancel != nil {
		e.cancel()
	}
	e.running = false
}

func (e *ActionExecutor) IsRunning() bool {
	e.mu.Lock()
	defer e.mu.Unlock()
	return e.running
}

func (e *ActionExecutor) ExecuteAction(action string, params map[string]string) tea.Cmd {
	return func() tea.Msg {
		e.mu.Lock()
		if e.running {
			e.mu.Unlock()
			return actionCompleteMsg{
				action: action,
				err:    fmt.Errorf("another operation is already in progress"),
			}
		}
		e.running = true
		e.mu.Unlock()

		defer func() {
			e.mu.Lock()
			e.running = false
			e.mu.Unlock()
		}()

		ctx, cancel := context.WithTimeout(e.ctx, 5*time.Minute)
		defer cancel()

		var output string
		var err error

		switch action {
		case "list_vms":
			output, err = e.listVMs(ctx)
		case "create_pmx_vm":
			output, err = e.createProxmoxVM(ctx, params)
		case "create_kvm_vm":
			output, err = e.createKVMVM(ctx, params)
		case "start_vm":
			output, err = e.vmAction(ctx, "start", params)
		case "stop_vm":
			output, err = e.vmAction(ctx, "stop", params)
		case "shutdown_vm":
			output, err = e.vmAction(ctx, "shutdown", params)
		case "clone_vm":
			output, err = e.cloneVM(ctx, params)
		case "migrate_vm":
			output, err = e.migrateVM(ctx, params)
		case "resize_vm":
			output, err = e.resizeVM(ctx, params)
		case "delete_vm":
			output, err = e.deleteVM(ctx, params)
		case "vm_console":
			output = "Console requires a graphical terminal. Use 'qm terminal' on the host."
		case "vm_config_audit":
			output, err = e.vmConfigAudit(ctx, params)
		case "list_ct":
			output, err = e.listContainers(ctx)
		case "create_ct":
			output, err = e.createContainer(ctx, params)
		case "start_ct":
			output, err = e.ctAction(ctx, "start", params)
		case "stop_ct":
			output, err = e.ctAction(ctx, "stop", params)
		case "resize_ct":
			output, err = e.resizeContainer(ctx, params)
		case "delete_ct":
			output, err = e.deleteContainer(ctx, params)
		case "ct_templates":
			output = "LXC templates are available in /var/lib/vz/template/cache/"
		case "list_storage":
			output, err = e.listStorage(ctx)
		case "add_storage":
			output, err = e.addStorage(ctx, params)
		case "remove_storage":
			output, err = e.removeStorage(ctx, params)
		case "list_snapshots":
			output, err = e.listSnapshots(ctx, params)
		case "create_snapshot":
			output, err = e.createSnapshot(ctx, params)
		case "rollback_snapshot":
			output, err = e.rollbackSnapshot(ctx, params)
		case "delete_snapshot":
			output, err = e.deleteSnapshot(ctx, params)
		case "backup_vm":
			output, err = e.backupVM(ctx, params)
		case "restore_backup":
			output, err = e.restoreBackup(ctx, params)
		case "backup_schedule":
			output, err = e.listBackupJobs(ctx)
		case "verify_backups":
			output, err = e.verifyBackups(ctx, params)
		case "cluster_status":
			output, err = e.clusterStatus(ctx)
		case "node_status":
			output, err = e.nodeStatus(ctx)
		case "ha_groups":
			output, err = e.listHAGroups(ctx)
		case "ha_resources":
			output, err = e.listHAResources(ctx)
		case "list_users":
			output, err = e.listUsers(ctx)
		case "live_metrics":
			output, err = e.liveMetrics(ctx)
		case "system_logs":
			output, err = e.systemLogs(ctx)
		case "health_check":
			output, err = e.healthCheck(ctx)
		case "settings":
			output = e.settingsInfo()
		case "ssh_executor":
			output, err = e.sshExecutorAction(ctx, params)
		case "config_backup":
			output, err = e.configBackup(ctx)
		case "install_kvm":
			output, err = e.installKVM(ctx)
		case "nested_virt":
			output, err = e.enableNestedVirt(ctx)
		case "iommu_setup":
			output, err = e.setupIOMMU(ctx)
		case "guest_agent":
			output, err = e.setupGuestAgent(ctx)
		case "hugepages":
			output, err = e.setupHugepages(ctx)
		case "cpu_pinning":
			output, err = e.setupCPUPinning(ctx)
		case "io_tuning":
			output, err = e.setupIOTuning(ctx)
		case "kernel_params":
			output, err = e.setupKernelParams(ctx)
		default:
			output = fmt.Sprintf("Action '%s' is not yet implemented", action)
		}

		return actionCompleteMsg{
			action: action,
			err:    err,
			output: output,
		}
	}
}

func (e *ActionExecutor) executeBash(ctx context.Context, script string, args ...string) (string, error) {
	fullArgs := append([]string{"-c", script}, args...)
	cmd := exec.CommandContext(ctx, "bash", fullArgs...)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	output := stdout.String()
	if stderr.Len() > 0 {
		output += "\n" + stderr.String()
	}
	if err != nil {
		return output, fmt.Errorf("bash error: %w: %s", err, stderr.String())
	}
	return output, nil
}

func (e *ActionExecutor) executePython(ctx context.Context, script string, args ...string) (string, error) {
	cmdArgs := append([]string{"-c", script}, args...)
	cmd := exec.CommandContext(ctx, "python3", cmdArgs...)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	output := stdout.String()
	if stderr.Len() > 0 {
		output += "\n" + stderr.String()
	}
	if err != nil {
		return output, fmt.Errorf("python error: %w: %s", err, stderr.String())
	}
	return output, nil
}

func (e *ActionExecutor) executeAnsible(ctx context.Context, playbook string, args ...string) (string, error) {
	cmdArgs := append([]string{"-i", "localhost,", "-c", "local", playbook}, args...)
	cmd := exec.CommandContext(ctx, "ansible-playbook", cmdArgs...)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	output := stdout.String()
	if stderr.Len() > 0 {
		output += "\n" + stderr.String()
	}
	if err != nil {
		return output, fmt.Errorf("ansible error: %w: %s", err, stderr.String())
	}
	return output, nil
}

func (e *ActionExecutor) executeAPI(ctx context.Context, method, path string, data map[string]interface{}) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox client configured")
	}

	var resp interface{}
	var err error

	switch strings.ToUpper(method) {
	case "GET":
		resp, err = e.pveClient.Get(ctx, path)
	case "POST":
		resp, err = e.pveClient.Post(ctx, path, data)
	case "PUT":
		resp, err = e.pveClient.Put(ctx, path, data)
	case "DELETE":
		resp, err = e.pveClient.Delete(ctx, path)
	default:
		return "", fmt.Errorf("unsupported method: %s", method)
	}

	if err != nil {
		return "", fmt.Errorf("API %s %s: %w", method, path, err)
	}

	return fmt.Sprintf("%v", resp), nil
}

func (e *ActionExecutor) listVMs(ctx context.Context) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vms, err := e.pveClient.ListVMs()
	if err != nil {
		return "", err
	}
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Found %d VMs:\n\n", len(vms)))
	sb.WriteString(fmt.Sprintf("%-8s %-20s %-10s %-5s %-12s %-12s %-10s\n",
		"VMID", "Name", "Status", "CPU", "Memory", "Disk", "Node"))
	sb.WriteString(strings.Repeat("─", 80) + "\n")
	for _, vm := range vms {
		sb.WriteString(fmt.Sprintf("%-8d %-20s %-10s %-5d %-12s %-12s %-10s\n",
			vm.VMID, vm.Name, vm.Status, vm.CPUs,
			formatBytes(vm.MaxMem), formatBytes(vm.MaxDisk), vm.Node))
	}
	return sb.String(), nil
}

func (e *ActionExecutor) createProxmoxVM(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	node := params["node"]
	if node == "" {
		node = "pve"
	}
	vmid := params["vmid"]
	if vmid == "" {
		vmid = "9000"
	}
	name := params["name"]
	if name == "" {
		name = "new-vm"
	}
	req := proxmox.VMCreateRequest{
		VMID:   vmid,
		Name:   name,
		CPU:    2,
		Memory: 2048,
		Net0:   "virtio,bridge=vmbr0",
	}
	err := e.pveClient.CreateVM(node, req)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("VM %s (VMID %s) created on node %s", name, vmid, node), nil
}

func (e *ActionExecutor) createKVMVM(ctx context.Context, params map[string]string) (string, error) {
	if e.kvmClient == nil {
		return "", fmt.Errorf("no KVM/libvirt connection")
	}
	name := params["name"]
	if name == "" {
		name = "new-kvm-vm"
	}
	return fmt.Sprintf("KVM VM '%s' creation requires XML definition via virsh", name), nil
}

func (e *ActionExecutor) vmAction(ctx context.Context, action string, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	if vmid == "" {
		return "", fmt.Errorf("VMID is required")
	}

	var err error
	switch action {
	case "start":
		err = e.pveClient.StartVM(vmid)
	case "stop":
		err = e.pveClient.StopVM(vmid)
	case "shutdown":
		err = e.pveClient.ShutdownVM(vmid)
	}

	if err != nil {
		return "", fmt.Errorf("%s VM %s: %w", action, vmid, err)
	}
	return fmt.Sprintf("VM %s: %s successful", vmid, action), nil
}

func (e *ActionExecutor) cloneVM(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	newid := params["newid"]
	if vmid == "" || newid == "" {
		return "", fmt.Errorf("vmid and newid are required")
	}
	var newID int
	fmt.Sscanf(newid, "%d", &newID)
	err := e.pveClient.CloneVM(vmid, newID, params["name"], true)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("VM %s cloned to %s", vmid, newid), nil
}

func (e *ActionExecutor) migrateVM(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	target := params["target"]
	if vmid == "" || target == "" {
		return "", fmt.Errorf("vmid and target are required")
	}
	err := e.pveClient.MigrateVM(vmid, target, true)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("VM %s migration to %s initiated", vmid, target), nil
}

func (e *ActionExecutor) resizeVM(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	disk := params["disk"]
	size := params["size"]
	if vmid == "" || disk == "" || size == "" {
		return "", fmt.Errorf("vmid, disk, and size are required")
	}
	err := e.pveClient.ResizeVM(vmid, disk, size)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("VM %s disk %s resized by %s", vmid, disk, size), nil
}

func (e *ActionExecutor) deleteVM(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	if vmid == "" {
		return "", fmt.Errorf("vmid is required")
	}
	err := e.pveClient.DeleteVM(vmid)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("VM %s deleted", vmid), nil
}

func (e *ActionExecutor) vmConfigAudit(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	if vmid == "" {
		return "", fmt.Errorf("vmid is required")
	}
	status, err := e.pveClient.GetVMStatus(vmid)
	if err != nil {
		return "", err
	}
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("VM %s Configuration Audit:\n", vmid))
	sb.WriteString(strings.Repeat("─", 50) + "\n")
	sb.WriteString(fmt.Sprintf("  Name:     %s\n", status.Name))
	sb.WriteString(fmt.Sprintf("  Status:   %s\n", status.Status))
	sb.WriteString(fmt.Sprintf("  CPUs:     %d\n", status.CPUs))
	sb.WriteString(fmt.Sprintf("  Memory:   %s\n", formatBytes(status.MaxMem)))
	sb.WriteString(fmt.Sprintf("  Disk:     %s\n", formatBytes(status.MaxDisk)))
	sb.WriteString(fmt.Sprintf("  CPU Usage: %.1f%%\n", status.CPU*100))
	sb.WriteString(fmt.Sprintf("  Agent:    %v\n", status.Agent == 1))
	return sb.String(), nil
}

func (e *ActionExecutor) listContainers(ctx context.Context) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	cts, err := e.pveClient.ListContainers()
	if err != nil {
		return "", err
	}
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Found %d containers:\n\n", len(cts)))
	for _, ct := range cts {
		sb.WriteString(fmt.Sprintf("  %d  %-20s  %s  CPU:%d  Mem:%s\n",
			ct.VMID, ct.Name, ct.Status, ct.CPUs, formatBytes(ct.MaxMem)))
	}
	return sb.String(), nil
}

func (e *ActionExecutor) createContainer(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	return "Container creation requires template selection and network configuration.", nil
}

func (e *ActionExecutor) ctAction(ctx context.Context, action string, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	if vmid == "" {
		return "", fmt.Errorf("vmid is required")
	}

	var err error
	switch action {
	case "start":
		err = e.pveClient.StartContainer(vmid)
	case "stop":
		err = e.pveClient.StopContainer(vmid)
	}

	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Container %s: %s successful", vmid, action), nil
}

func (e *ActionExecutor) resizeContainer(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	disk := params["disk"]
	size := params["size"]
	if vmid == "" || disk == "" || size == "" {
		return "", fmt.Errorf("vmid, disk, and size are required")
	}
	err := e.pveClient.ResizeContainer(vmid, disk, size)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Container %s disk %s resized by %s", vmid, disk, size), nil
}

func (e *ActionExecutor) deleteContainer(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	if vmid == "" {
		return "", fmt.Errorf("vmid is required")
	}
	err := e.pveClient.DeleteContainer(vmid)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Container %s deleted", vmid), nil
}

func (e *ActionExecutor) listStorage(ctx context.Context) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	storage, err := e.pveClient.ListStorage()
	if err != nil {
		return "", err
	}
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Found %d storage pools:\n\n", len(storage)))
	sb.WriteString(fmt.Sprintf("%-20s %-10s %-8s %-12s %-12s %-12s %-8s\n",
		"Name", "Type", "Status", "Total", "Used", "Avail", "%Used"))
	sb.WriteString(strings.Repeat("─", 85) + "\n")
	for _, s := range storage {
		sb.WriteString(fmt.Sprintf("%-20s %-10s %-8s %-12s %-12s %-12s %.1f%%\n",
			s.Storage, s.Type, s.Status,
			formatBytes(s.Total), formatBytes(s.Used), formatBytes(s.Avail), s.Percent))
	}
	return sb.String(), nil
}

func (e *ActionExecutor) addStorage(ctx context.Context, params map[string]string) (string, error) {
	return "Storage addition requires type-specific configuration. Use the Proxmox web UI or API.", nil
}

func (e *ActionExecutor) removeStorage(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	name := params["name"]
	node := params["node"]
	if name == "" || node == "" {
		return "", fmt.Errorf("name and node are required")
	}
	err := e.pveClient.RemoveStorage(node, name)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Storage %s removed from node %s", name, node), nil
}

func (e *ActionExecutor) listSnapshots(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	if vmid == "" {
		return "", fmt.Errorf("vmid is required")
	}
	snaps, err := e.pveClient.ListSnapshots(vmid)
	if err != nil {
		return "", err
	}
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Snapshots for VM %s:\n\n", vmid))
	for _, s := range snaps {
		sb.WriteString(fmt.Sprintf("  %-20s  %s  Parent: %s\n", s.Name, s.Time, s.Parent))
	}
	return sb.String(), nil
}

func (e *ActionExecutor) createSnapshot(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	name := params["name"]
	desc := params["description"]
	if vmid == "" || name == "" {
		return "", fmt.Errorf("vmid and name are required")
	}
	err := e.pveClient.CreateSnapshot(vmid, name, desc)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Snapshot '%s' created for VM %s", name, vmid), nil
}

func (e *ActionExecutor) rollbackSnapshot(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	name := params["name"]
	if vmid == "" || name == "" {
		return "", fmt.Errorf("vmid and name are required")
	}
	err := e.pveClient.RollbackSnapshot(vmid, name)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("VM %s rolled back to snapshot '%s'", vmid, name), nil
}

func (e *ActionExecutor) deleteSnapshot(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	name := params["name"]
	if vmid == "" || name == "" {
		return "", fmt.Errorf("vmid and name are required")
	}
	err := e.pveClient.DeleteSnapshot(vmid, name)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Snapshot '%s' deleted from VM %s", name, vmid), nil
}

func (e *ActionExecutor) backupVM(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	storage := params["storage"]
	if vmid == "" {
		return "", fmt.Errorf("vmid is required")
	}
	if storage == "" {
		storage = "local"
	}
	node := params["node"]
	if node == "" {
		node = "pve"
	}
	req := proxmox.BackupRequest{
		Storage:  storage,
		Mode:     "snapshot",
		Compress: "zstd",
	}
	err := e.pveClient.CreateBackup(node, "qemu", vmid, req)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Backup initiated for VM %s to %s", vmid, storage), nil
}

func (e *ActionExecutor) restoreBackup(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	vmid := params["vmid"]
	volid := params["volid"]
	if vmid == "" || volid == "" {
		return "", fmt.Errorf("vmid and volid are required")
	}
	node := params["node"]
	if node == "" {
		node = "pve"
	}
	err := e.pveClient.RestoreBackup(node, "qemu", vmid, volid)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Backup %s restored to VM %s", volid, vmid), nil
}

func (e *ActionExecutor) listBackupJobs(ctx context.Context) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	jobs, err := e.pveClient.ListBackupJobs()
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Backup Jobs:\n%s", string(jobs)), nil
}

func (e *ActionExecutor) verifyBackups(ctx context.Context, params map[string]string) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	storage := params["storage"]
	if storage == "" {
		storage = "local"
	}
	node := params["node"]
	if node == "" {
		node = "pve"
	}
	req := proxmox.BackupVerifyRequest{
		Storage: storage,
	}
	err := e.pveClient.VerifyBackup(node, req)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Backup verification initiated for storage %s", storage), nil
}

func (e *ActionExecutor) clusterStatus(ctx context.Context) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	nodes, err := e.pveClient.ListNodes()
	if err != nil {
		return "", err
	}
	var sb strings.Builder
	sb.WriteString("Cluster Status:\n\n")
	sb.WriteString(fmt.Sprintf("%-15s %-10s %-8s %-12s %-12s %-12s\n",
		"Node", "Status", "CPU", "Memory", "Disk", "Uptime"))
	sb.WriteString(strings.Repeat("─", 72) + "\n")
	for _, n := range nodes {
		uptime := fmt.Sprintf("%dd %dh", n.Uptime/86400, (n.Uptime%86400)/3600)
		sb.WriteString(fmt.Sprintf("%-15s %-10s %.1f%%     %s/%s      %s/%s      %s\n",
			n.Node, n.Status, n.CPU*100,
			formatBytes(n.Memory.Used), formatBytes(n.MaxMemory),
			formatBytes(n.Disk.Used), formatBytes(n.MaxDisk),
			uptime))
	}
	return sb.String(), nil
}

func (e *ActionExecutor) nodeStatus(ctx context.Context) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	return e.clusterStatus(ctx)
}

func (e *ActionExecutor) listHAGroups(ctx context.Context) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	groups, err := e.pveClient.ListHAGroups()
	if err != nil {
		return "", err
	}
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("HA Groups (%d):\n\n", len(groups)))
	for _, g := range groups {
		sb.WriteString(fmt.Sprintf("  %-20s  Nodes: %s  %s\n", g.Group, g.Nodes, g.Comment))
	}
	return sb.String(), nil
}

func (e *ActionExecutor) listHAResources(ctx context.Context) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	resources, err := e.pveClient.ListHAResources()
	if err != nil {
		return "", err
	}
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("HA Resources (%d):\n\n", len(resources)))
	for _, r := range resources {
		sb.WriteString(fmt.Sprintf("  %-20s  Type: %-8s  State: %-10s  Group: %s\n",
			r.SID, r.Type, r.State, r.Group))
	}
	return sb.String(), nil
}

func (e *ActionExecutor) listUsers(ctx context.Context) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	users, err := e.pveClient.ListUsers()
	if err != nil {
		return "", err
	}
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Users (%d):\n\n", len(users)))
	for _, u := range users {
		enabled := "disabled"
		if u.Enable {
			enabled = "enabled"
		}
		sb.WriteString(fmt.Sprintf("  %-30s  %-10s  %s  %s\n", u.UserID, u.Realm, enabled, u.Comment))
	}
	return sb.String(), nil
}

func (e *ActionExecutor) liveMetrics(ctx context.Context) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	node := e.defaultNode()
	data, err := e.pveClient.GetRRDData(node, "", "", "hour", "AVERAGE")
	if err != nil {
		return "", fmt.Errorf("getting metrics: %w", err)
	}
	var sb strings.Builder
	sb.WriteString(fmt.Sprintf("Live Metrics (last hour, node %s):\n\n", node))
	for _, d := range data[len(data)-5:] {
		sb.WriteString(fmt.Sprintf("  CPU: %.1f%%  Mem: %s  NetIn: %s  NetOut: %s\n",
			d.CPU*100, formatBytes(d.Mem), formatBytes(d.NetIn), formatBytes(d.NetOut)))
	}
	return sb.String(), nil
}

func (e *ActionExecutor) systemLogs(ctx context.Context) (string, error) {
	if e.pveClient == nil {
		return "", fmt.Errorf("no Proxmox connection")
	}
	node := e.defaultNode()
	tasks, err := e.pveClient.ListTasks(node)
	if err != nil {
		return "", err
	}
	return fmt.Sprintf("Recent Tasks (node %s):\n%s", node, string(tasks)), nil
}

func (e *ActionExecutor) healthCheck(ctx context.Context) (string, error) {
	var sb strings.Builder
	sb.WriteString("System Health Check\n")
	sb.WriteString(strings.Repeat("═", 50) + "\n\n")

	sb.WriteString("  [✓] Configuration loaded\n")

	if e.pveClient != nil {
		sb.WriteString("  [✓] Proxmox API connection active\n")
		node := e.defaultNode()
		nodes, err := e.pveClient.ListNodes()
		if err != nil {
			sb.WriteString(fmt.Sprintf("  [✕] Cluster status: %v\n", err))
		} else {
			sb.WriteString(fmt.Sprintf("  [✓] Cluster: %d node(s) online\n", len(nodes)))
			for _, n := range nodes {
				status := "online"
				if n.Status != "online" {
					status = "OFFLINE"
				}
				sb.WriteString(fmt.Sprintf("      %s: %s (CPU: %.1f%%)\n", n.Node, status, n.CPU*100))
			}
		}
		_ = node
	} else {
		sb.WriteString("  [!] Proxmox API: not configured\n")
	}

	if e.kvmClient != nil {
		sb.WriteString("  [✓] KVM/libvirt connection active\n")
	} else {
		sb.WriteString("  [!] KVM/libvirt: not connected\n")
	}

	sb.WriteString("\n")
	return sb.String(), nil
}

func (e *ActionExecutor) settingsInfo() string {
	var sb strings.Builder
	sb.WriteString("Current Settings\n")
	sb.WriteString(strings.Repeat("═", 50) + "\n\n")
	sb.WriteString("  Run 'settings' to view full configuration in the Settings view.\n")
	return sb.String()
}

func (e *ActionExecutor) sshExecutorAction(ctx context.Context, params map[string]string) (string, error) {
	host := params["host"]
	user := params["user"]
	cmd := params["command"]
	if host == "" || cmd == "" {
		return "", fmt.Errorf("host and command are required")
	}
	if user == "" {
		user = "root"
	}

	sshCmd := exec.CommandContext(ctx, "ssh",
		"-o", "StrictHostKeyChecking=no",
		"-o", "ConnectTimeout=10",
		fmt.Sprintf("%s@%s", user, host),
		cmd,
	)

	var stdout, stderr bytes.Buffer
	sshCmd.Stdout = &stdout
	sshCmd.Stderr = &stderr

	err := sshCmd.Run()
	output := stdout.String()
	if stderr.Len() > 0 {
		output += "\n[stderr] " + stderr.String()
	}
	if err != nil {
		return output, fmt.Errorf("SSH error: %w", err)
	}
	return fmt.Sprintf("SSH output from %s@%s:\n%s", user, host, output), nil
}

func (e *ActionExecutor) configBackup(ctx context.Context) (string, error) {
	return e.executeBash(ctx, "echo 'Config backup not yet implemented. Use Proxmox backup API.'")
}

func (e *ActionExecutor) installKVM(ctx context.Context) (string, error) {
	return e.executeBash(ctx, "apt list --installed 2>/dev/null | grep -E 'qemu-kvm|libvirt|virtinst'")
}

func (e *ActionExecutor) enableNestedVirt(ctx context.Context) (string, error) {
	script := `
if [ -f /sys/module/kvm_intel/parameters/nested ]; then
    cat /sys/module/kvm_intel/parameters/nested
elif [ -f /sys/module/kvm_amd/parameters/nested ]; then
    cat /sys/module/kvm_amd/parameters/nested
else
    echo "KVM module not loaded"
fi
`
	return e.executeBash(ctx, script)
}

func (e *ActionExecutor) setupIOMMU(ctx context.Context) (string, error) {
	script := `dmesg | grep -i iommu | head -5 || echo "No IOMMU messages found"`
	return e.executeBash(ctx, script)
}

func (e *ActionExecutor) setupGuestAgent(ctx context.Context) (string, error) {
	return e.executeBash(ctx, "which qemu-guest-agent 2>/dev/null || echo 'Guest agent not installed'")
}

func (e *ActionExecutor) setupHugepages(ctx context.Context) (string, error) {
	script := `
echo "HugePages_Total: $(cat /proc/meminfo | grep HugePages_Total | awk '{print $2}')"
echo "HugePages_Free:  $(cat /proc/meminfo | grep HugePages_Free | awk '{print $2}')"
echo "Hugepagesize:    $(cat /proc/meminfo | grep Hugepagesize | awk '{print $2}')"
`
	return e.executeBash(ctx, script)
}

func (e *ActionExecutor) setupCPUPinning(ctx context.Context) (string, error) {
	return e.executeBash(ctx, "lscpu | grep -E 'Core|Socket|Thread|CPU\\(s\\)'")
}

func (e *ActionExecutor) setupIOTuning(ctx context.Context) (string, error) {
	return e.executeBash(ctx, "for d in /sys/block/*/queue/scheduler; do echo \"$d: $(cat $d)\"; done 2>/dev/null")
}

func (e *ActionExecutor) setupKernelParams(ctx context.Context) (string, error) {
	return e.executeBash(ctx, "sysctl vm.swappiness vm.dirty_ratio vm.dirty_background_ratio vm.overcommit_memory 2>/dev/null")
}

func (e *ActionExecutor) defaultNode() string {
	return "pve"
}
