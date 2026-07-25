// SPDX-License-Identifier: MIT

package proxmox

import (
	"context"
	"encoding/json"
	"fmt"
	"time"
)

// RRDData represents a single RRD data point.
type RRDData struct {
	Time   int64   `json:"time"`
	CPU    float64 `json:"cpu,omitempty"`
	Mem    int64   `json:"mem,omitempty"`
	MaxMem int64   `json:"maxmem,omitempty"`
	Disk   int64   `json:"disk,omitempty"`
	MaxDisk int64  `json:"maxdisk,omitempty"`
	NetIn  int64   `json:"netin,omitempty"`
	NetOut int64   `json:"netout,omitempty"`
}

// ClusterResource represents a resource in the cluster.
type ClusterResource struct {
	ID     string  `json:"id"`
	Type   string  `json:"type"`
	Status string  `json:"status"`
	Node   string  `json:"node"`
	CPU    float64 `json:"cpu,omitempty"`
	Mem    int64   `json:"mem,omitempty"`
	MaxMem int64   `json:"maxmem,omitempty"`
	Disk   int64   `json:"disk,omitempty"`
	MaxDisk int64  `json:"maxdisk,omitempty"`
	Uptime int64   `json:"uptime,omitempty"`
}

// PrometheusMetrics holds exported Prometheus metrics.
type PrometheusMetrics struct {
	CPUUsage     float64
	MemoryUsage  float64
	MemoryTotal  int64
	DiskUsage    float64
	DiskTotal    int64
	NetworkIn    int64
	NetworkOut   int64
	VMCount      int
	ContainerCount int
	UpSince      time.Time
}

// GetRRDData returns RRD data for a node or VM.
func (c *Client) GetRRDData(node, vmtype, vmid, timeframe, cf string) ([]RRDData, error) {
	ctx := context.Background()

	var path string
	if vmid != "" && vmtype != "" {
		path = fmt.Sprintf("%s/%s/%s/rrddata?timeframe=%s&cf=%s",
			c.nodePath(node, ""), vmtype, vmid, timeframe, cf)
	} else {
		path = fmt.Sprintf("%s/rrddata?timeframe=%s&cf=%s",
			c.nodePath(node, ""), timeframe, cf)
	}

	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("getting RRD data: %w", err)
	}

	var rrdData []RRDData
	if err := decodeJSON(data, &rrdData); err != nil {
		return nil, fmt.Errorf("decoding RRD data: %w", err)
	}
	return rrdData, nil
}

// GetClusterResources returns all cluster resources.
func (c *Client) GetClusterResources() ([]ClusterResource, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/cluster/resources")
	if err != nil {
		return nil, fmt.Errorf("getting cluster resources: %w", err)
	}

	var resources []ClusterResource
	if err := decodeJSON(data, &resources); err != nil {
		return nil, fmt.Errorf("decoding cluster resources: %w", err)
	}
	return resources, nil
}

// ExportPrometheus exports cluster metrics in Prometheus format.
func (c *Client) ExportPrometheus() (string, error) {
	resources, err := c.GetClusterResources()
	if err != nil {
		return "", fmt.Errorf("getting resources for prometheus export: %w", err)
	}

	var metrics []string

	for _, r := range resources {
		if r.Type == "qemu" || r.Type == "lxc" {
			metrics = append(metrics, fmt.Sprintf(
				`proxmox_vm_cpu_usage{vmid="%s",name="%s",node="%s",type="%s"} %f`,
				r.ID, r.ID, r.Node, r.Type, r.CPU,
			))
			metrics = append(metrics, fmt.Sprintf(
				`proxmox_vm_memory_usage{vmid="%s",name="%s",node="%s",type="%s"} %d`,
				r.ID, r.ID, r.Node, r.Type, r.Mem,
			))
			metrics = append(metrics, fmt.Sprintf(
				`proxmox_vm_memory_max{vmid="%s",name="%s",node="%s",type="%s"} %d`,
				r.ID, r.ID, r.Node, r.Type, r.MaxMem,
			))
			metrics = append(metrics, fmt.Sprintf(
				`proxmox_vm_disk_usage{vmid="%s",name="%s",node="%s",type="%s"} %d`,
				r.ID, r.ID, r.Node, r.Type, r.Disk,
			))
			metrics = append(metrics, fmt.Sprintf(
				`proxmox_vm_disk_max{vmid="%s",name="%s",node="%s",type="%s"} %d`,
				r.ID, r.ID, r.Node, r.Type, r.MaxDisk,
			))
		}
		if r.Type == "node" {
			status := 0.0
			if r.Status == "online" {
				status = 1.0
			}
			metrics = append(metrics, fmt.Sprintf(
				`proxmox_node_up{node="%s"} %f`,
				r.Node, status,
			))
			metrics = append(metrics, fmt.Sprintf(
				`proxmox_node_cpu_usage{node="%s"} %f`,
				r.Node, r.CPU,
			))
			metrics = append(metrics, fmt.Sprintf(
				`proxmox_node_memory_usage{node="%s"} %d`,
				r.Node, r.Mem,
			))
			metrics = append(metrics, fmt.Sprintf(
				`proxmox_node_memory_max{node="%s"} %d`,
				r.Node, r.MaxMem,
			))
		}
	}

	result := ""
	for _, m := range metrics {
		result += m + "\n"
	}

	return result, nil
}

// GetNodeStatistics returns detailed statistics for a node.
func (c *Client) GetNodeStatistics(node string) (json.RawMessage, error) {
	ctx := context.Background()
	path := fmt.Sprintf("%s/status", c.nodePath(node, ""))
	return c.Get(ctx, path)
}

// GetVMStatistics returns detailed statistics for a VM.
func (c *Client) GetVMStatistics(vmid string) (json.RawMessage, error) {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}
	path := fmt.Sprintf("%s/qemu/%s/status/current", c.nodePath(node, ""), vmid)
	return c.Get(ctx, path)
}

// GetStorageStatistics returns statistics for a storage pool.
func (c *Client) GetStorageStatistics(node, storage string) (json.RawMessage, error) {
	ctx := context.Background()
	path := fmt.Sprintf("%s/storage/%s/status", c.nodePath(node, ""), storage)
	return c.Get(ctx, path)
}

// GetTaskStatus returns the status of a running task.
func (c *Client) GetTaskStatus(node, upid string) (json.RawMessage, error) {
	ctx := context.Background()
	path := fmt.Sprintf("%s/tasks/%s/status", c.nodePath(node, ""), upid)
	return c.Get(ctx, path)
}

// ListTasks returns all tasks on a node.
func (c *Client) ListTasks(node string) (json.RawMessage, error) {
	ctx := context.Background()
	path := fmt.Sprintf("%s/tasks", c.nodePath(node, ""))
	return c.Get(ctx, path)
}
