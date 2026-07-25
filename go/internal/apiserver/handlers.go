package apiserver

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"

	"github.com/proxmox-kvm-swissknife/internal/proxmox"
)

// --- Health ---

func (s *Server) handleHealth(w http.ResponseWriter, r *http.Request) {
	s.writeJSON(w, http.StatusOK, map[string]interface{}{
		"status": "ok",
		"time":   r.Context().Value("request_time"),
	})
}

// --- Cluster ---

func (s *Server) handleClusterStatus(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return s.client.Get(r.Context(), "/api2/json/cluster/status")
}

func (s *Server) handleClusterResources(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	rtype := r.URL.Query().Get("type")
	path := "/api2/json/cluster/resources"
	if rtype != "" {
		path += "?type=" + rtype
	}
	return s.client.Get(r.Context(), path)
}

func (s *Server) handleClusterLog(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return s.client.Get(r.Context(), "/api2/json/cluster/log")
}

func (s *Server) handleClusterOptions(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return s.client.Get(r.Context(), "/api2/json/cluster/options")
}

// --- Nodes ---

func (s *Server) handleListNodes(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return s.client.Get(r.Context(), "/api2/json/nodes")
}

func (s *Server) handleGetNode(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	node := s.node(r)
	return s.client.Get(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/status", node))
}

func (s *Server) handleGetNodeStatus(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	node := s.node(r)
	return s.client.Get(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/status", node))
}

func (s *Server) handleNodeServices(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return s.client.Get(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/services", s.node(r)))
}

func (s *Server) handleListNodeNetwork(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return s.client.Get(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/network", s.node(r)))
}

func (s *Server) handleCreateNetwork(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	body := make(map[string]interface{})
	if err := parseBody(r, &body); err != nil {
		return nil, fmt.Errorf("invalid request body: %w", err)
	}
	return nil, s.client.Post(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/network", s.node(r)), body)
}

// --- VMs ---

func (s *Server) handleListVMs(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	node := r.URL.Query().Get("node")
	return s.client.Get(r.Context(), fmt.Sprintf("/api2/json/cluster/resources?type=vm"))
}

func (s *Server) handleGetVM(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	vmid := s.vmid(r)
	node, err := s.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}
	return s.client.Get(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/qemu/%s/status/current", node, vmid))
}

func (s *Server) handleCreateVM(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	var req proxmox.VMCreateRequest
	if err := parseBody(r, &req); err != nil {
		return nil, fmt.Errorf("invalid request body: %w", err)
	}
	node := r.URL.Query().Get("node")
	if node == "" {
		node = "localhost"
	}
	return nil, s.client.CreateVM(node, req)
}

func (s *Server) handleDeleteVM(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return nil, s.client.DeleteVM(s.vmid(r))
}

func (s *Server) handleStartVM(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return nil, s.client.StartVM(s.vmid(r))
}

func (s *Server) handleStopVM(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return nil, s.client.StopVM(s.vmid(r))
}

func (s *Server) handleShutdownVM(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return nil, s.client.ShutdownVM(s.vmid(r))
}

func (s *Server) handleCloneVM(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	var req struct {
		NewID int    `json:"newid"`
		Name  string `json:"name"`
		Full  bool   `json:"full"`
	}
	if err := parseBody(r, &req); err != nil {
		return nil, fmt.Errorf("invalid request body: %w", err)
	}
	return nil, s.client.CloneVM(s.vmid(r), req.NewID, req.Name, req.Full)
}

func (s *Server) handleResizeVM(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	var req struct {
		Disk string `json:"disk"`
		Size string `json:"size"`
	}
	if err := parseBody(r, &req); err != nil {
		return nil, fmt.Errorf("invalid request body: %w", err)
	}
	return nil, s.client.ResizeVM(s.vmid(r), req.Disk, req.Size)
}

func (s *Server) handleMigrateVM(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	var req struct {
		Target  string `json:"target"`
		Online  bool   `json:"online"`
		Restart bool   `json:"restart"`
	}
	if err := parseBody(r, &req); err != nil {
		return nil, fmt.Errorf("invalid request body: %w", err)
	}

	vmid := s.vmid(r)
	node, err := s.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}

	migrateReq := map[string]interface{}{
		"target":  req.Target,
		"online":  strconv.FormatBool(req.Online),
		"restart": strconv.FormatBool(req.Restart),
	}
	return nil, s.client.Post(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/qemu/%s/migrate", node, vmid), migrateReq)
}

func (s *Server) handleGetVMConfig(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	vmid := s.vmid(r)
	node, err := s.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}
	return s.client.Get(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/qemu/%s/config", node, vmid))
}

func (s *Server) handleSetVMConfig(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	vmid := s.vmid(r)
	node, err := s.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}

	var body map[string]interface{}
	if err := parseBody(r, &body); err != nil {
		return nil, fmt.Errorf("invalid request body: %w", err)
	}
	return nil, s.client.Put(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/qemu/%s/config", node, vmid), body)
}

func (s *Server) handleMonitorVM(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	var req struct {
		Command string `json:"command"`
	}
	if err := parseBody(r, &req); err != nil {
		return nil, fmt.Errorf("invalid request body: %w", err)
	}
	return s.client.MonitorVM(s.vmid(r), req.Command)
}

// --- Snapshots ---

func (s *Server) handleListSnapshots(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	vmid := s.vmid(r)
	node, err := s.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}
	return s.client.Get(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/qemu/%s/snapshot", node, vmid))
}

func (s *Server) handleCreateSnapshot(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	vmid := s.vmid(r)
	node, err := s.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}

	var req struct {
		Name    string `json:"name"`
		Desc    string `json:"description,omitempty"`
		VMState bool   `json:"vmstate,omitempty"`
	}
	if err := parseBody(r, &req); err != nil {
		return nil, fmt.Errorf("invalid request body: %w", err)
	}

	body := map[string]interface{}{
		"snapname": req.Name,
	}
	if req.Desc != "" {
		body["description"] = req.Desc
	}
	if req.VMState {
		body["vmstate"] = "1"
	}
	return nil, s.client.Post(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/qemu/%s/snapshot", node, vmid), body)
}

func (s *Server) handleDeleteSnapshot(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	vmid := s.vmid(r)
	node, err := s.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}
	snapname := r.PathValue("snapname")
	return nil, s.client.Delete(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/qemu/%s/snapshot/%s", node, vmid, snapname))
}

func (s *Server) handleRollbackSnapshot(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	vmid := s.vmid(r)
	node, err := s.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}
	snapname := r.PathValue("snapname")
	return nil, s.client.Post(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/qemu/%s/snapshot/%s/rollback", node, vmid, snapname), nil)
}

// --- Containers ---

func (s *Server) handleListContainers(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return s.client.Get(r.Context(), "/api2/json/cluster/resources?type=lxc")
}

func (s *Server) handleGetContainer(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	ctid := r.PathValue("ctid")
	raw, err := s.client.Get(r.Context(), "/api2/json/cluster/resources?type=lxc")
	if err != nil {
		return nil, err
	}

	var containers []proxmox.VM
	if err := json.Unmarshal(raw, &containers); err != nil {
		return nil, fmt.Errorf("decoding containers: %w", err)
	}
	for _, ct := range containers {
		if strconv.Itoa(ct.VMID) == ctid {
			return ct, nil
		}
	}
	return nil, fmt.Errorf("container %s not found", ctid)
}

func (s *Server) handleCreateContainer(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	var req proxmox.ContainerCreateRequest
	if err := parseBody(r, &req); err != nil {
		return nil, fmt.Errorf("invalid request body: %w", err)
	}
	node := r.URL.Query().Get("node")
	if node == "" {
		node = "localhost"
	}
	return nil, s.client.CreateContainer(node, req)
}

func (s *Server) handleDeleteContainer(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return nil, s.client.DeleteContainer(r.PathValue("ctid"))
}

func (s *Server) handleStartContainer(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return nil, s.client.StartContainer(r.PathValue("ctid"))
}

func (s *Server) handleStopContainer(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return nil, s.client.StopContainer(r.PathValue("ctid"))
}

func (s *Server) handleShutdownContainer(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return nil, s.client.ShutdownContainer(r.PathValue("ctid"))
}

// --- Storage ---

func (s *Server) handleListStorage(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return s.client.Get(r.Context(), "/api2/json/storage")
}

func (s *Server) handleStorageContent(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return s.client.Get(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/storage/%s/content", s.node(r), r.PathValue("storage")))
}

func (s *Server) handleAddStorage(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	var body map[string]interface{}
	if err := parseBody(r, &body); err != nil {
		return nil, fmt.Errorf("invalid request body: %w", err)
	}
	return nil, s.client.Post(r.Context(), "/api2/json/storage", body)
}

func (s *Server) handleRemoveStorage(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return nil, s.client.Delete(r.Context(), fmt.Sprintf("/api2/json/storage/%s", r.PathValue("storage")))
}

// --- Pools ---

func (s *Server) handleListPools(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return s.client.Get(r.Context(), "/api2/json/pools")
}

func (s *Server) handleCreatePool(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	var body map[string]interface{}
	if err := parseBody(r, &body); err != nil {
		return nil, fmt.Errorf("invalid request body: %w", err)
	}
	return nil, s.client.Post(r.Context(), "/api2/json/pools", body)
}

func (s *Server) handleDeletePool(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return nil, s.client.Delete(r.Context(), fmt.Sprintf("/api2/json/pools/%s", r.PathValue("poolid")))
}

// --- Backups ---

func (s *Server) handleListBackups(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return s.client.Get(r.Context(), "/api2/json/cluster/backup")
}

func (s *Server) handleBackupNow(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	vmid := s.vmid(r)
	node, err := s.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}
	return nil, s.client.Post(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/qemu/%s/backup", node, vmid), nil)
}

// --- Firewall ---

func (s *Server) handleFirewallRules(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return s.client.Get(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/firewall/rules", s.node(r)))
}

func (s *Server) handleAddFirewallRule(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	var body map[string]interface{}
	if err := parseBody(r, &body); err != nil {
		return nil, fmt.Errorf("invalid request body: %w", err)
	}
	return nil, s.client.Post(r.Context(), fmt.Sprintf("/api2/json/nodes/%s/firewall/rules", s.node(r)), body)
}

// --- HA ---

func (s *Server) handleHAGroups(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return s.client.Get(r.Context(), "/api2/json/cluster/ha/groups")
}

func (s *Server) handleCreateHAGroup(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	var body map[string]interface{}
	if err := parseBody(r, &body); err != nil {
		return nil, fmt.Errorf("invalid request body: %w", err)
	}
	return nil, s.client.Post(r.Context(), "/api2/json/cluster/ha/groups", body)
}

func (s *Server) handleHAResources(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	return s.client.Get(r.Context(), "/api2/json/cluster/ha/resources")
}

// --- Metrics ---

func (s *Server) handleNodeMetrics(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	raw, err := s.client.Get(r.Context(), "/api2/json/cluster/resources")
	if err != nil {
		return nil, err
	}

	var resources []map[string]interface{}
	if err := json.Unmarshal(raw, &resources); err != nil {
		return nil, fmt.Errorf("decoding resources: %w", err)
	}

	nodes := make(map[string]int)
	totalCPU := 0
	totalMem := int64(0)
	totalDisk := int64(0)

	for _, res := range resources {
		if res["type"] == "node" {
			nodes[fmt.Sprintf("%v", res["node"])]++
			if cpu, ok := res["cpu"].(float64); ok {
				totalCPU++
				_ = cpu
			}
			if mem, ok := res["mem"].(float64); ok {
				totalMem += int64(mem)
			}
			if disk, ok := res["disk"].(float64); ok {
				totalDisk += int64(disk)
			}
		}
	}

	return map[string]interface{}{
		"nodes":       len(nodes),
		"node_list":   nodes,
		"total_cpu":   totalCPU,
		"total_mem":   totalMem,
		"total_disk":  totalDisk,
		"raw":         resources,
	}, nil
}

func (s *Server) handleClusterMetrics(w http.ResponseWriter, r *http.Request) (interface{}, error) {
	status, err := s.client.Get(r.Context(), "/api2/json/cluster/status")
	if err != nil {
		return nil, err
	}
	resources, err := s.client.Get(r.Context(), "/api2/json/cluster/resources")
	if err != nil {
		return nil, err
	}
	return map[string]interface{}{
		"status":    status,
		"resources": resources,
	}, nil
}

// --- helpers ---

// resolveVMNode is a helper since the handler already does this inline for some routes.
func (s *Server) resolveVMNode(vmid string) (string, error) {
	return s.client.GetVMNode(vmid)
}
