// SPDX-License-Identifier: MIT

package proxmox

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strconv"
)

// VM represents a Proxmox virtual machine.
type VM struct {
	VMID   int    `json:"vmid"`
	Name   string `json:"name"`
	Status string `json:"status"`
	CPUs   int    `json:"cpus"`
	MaxMem int64  `json:"maxmem"`
	MaxDisk int64 `json:"maxdisk"`
	Node   string `json:"node,omitempty"`
	Type   string `json:"type,omitempty"`
}

// VMStatus represents detailed VM status information.
type VMStatus struct {
	VMID      string `json:"vmid"`
	Name      string `json:"name"`
	Status    string `json:"status"`
	CPU       float64 `json:"cpu"`
	CPUs      int    `json:"cpus"`
	Memory    int64  `json:"mem"`
	MaxMem    int64  `json:"maxmem"`
	Disk      int64  `json:"disk"`
	MaxDisk   int64  `json:"maxdisk"`
	Uptime    int64  `json:"uptime"`
	Running   bool   `json:"running"`
	PID       int    `json:"pid,omitempty"`
	Agent     int    `json:"agent,omitempty"`
}

// VMCreateRequest represents a request to create a VM.
type VMCreateRequest struct {
	VMID     string `json:"vmid"`
	Name     string `json:"name,omitempty"`
	CPU      int    `json:"cores,omitempty"`
	Memory   int    `json:"memory,omitempty"`
	Disk     string `json:"scsi0,omitempty"`
	Net0     string `json:"net0,omitempty"`
	OSType   string `json:"ostype,omitempty"`
	ISO      string `json:"ide2,omitempty"`
	Boot     string `json:"boot,omitempty"`
	ScsiHW  string `json:"scsihw,omitempty"`
	Bios     string `json:"bios,omitempty"`
	Machine  string `json:"machine,omitempty"`
}

// CloneRequest represents a VM clone request.
type CloneRequest struct {
	NewID   string `json:"newid"`
	Name    string `json:"name,omitempty"`
	Full    int    `json:"full,omitempty"`
	Target  string `json:"target,omitempty"`
}

// ListVMs returns all virtual machines across all nodes.
func (c *Client) ListVMs() ([]VM, error) {
	return c.ListVMsByNode("")
}

// ListVMsByNode returns all virtual machines on a specific node.
func (c *Client) ListVMsByNode(node string) ([]VM, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/cluster/resources?type=vm")
	if err != nil {
		return nil, fmt.Errorf("listing VMs: %w", err)
	}

	var resources []VM
	if err := decodeJSON(data, &resources); err != nil {
		return nil, fmt.Errorf("decoding VMs: %w", err)
	}

	if node != "" {
		var filtered []VM
		for _, vm := range resources {
			if vm.Node == node && vm.Type == "qemu" {
				filtered = append(filtered, vm)
			}
		}
		return filtered, nil
	}

	var qemu []VM
	for _, vm := range resources {
		if vm.Type == "qemu" {
			qemu = append(qemu, vm)
		}
	}
	return qemu, nil
}

// GetVMStatus returns the status of a specific VM.
func (c *Client) GetVMStatus(vmid string) (*VMStatus, error) {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}

	path := fmt.Sprintf("%s/qemu/%s/status/current", c.nodePath(node, ""), vmid)
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("getting VM %s status: %w", vmid, err)
	}

	var status VMStatus
	if err := decodeJSON(data, &status); err != nil {
		return nil, fmt.Errorf("decoding VM status: %w", err)
	}
	return &status, nil
}

// CreateVM creates a new virtual machine.
func (c *Client) CreateVM(node string, req VMCreateRequest) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/qemu", c.nodePath(node, ""))
	_, err := c.Post(ctx, path, req)
	if err != nil {
		return fmt.Errorf("creating VM: %w", err)
	}
	return nil
}

// DeleteVM deletes a virtual machine and its disks.
func (c *Client) DeleteVM(vmid string) error {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return err
	}

	path := fmt.Sprintf("%s/qemu/%s", c.nodePath(node, ""), vmid)
	_, err = c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("deleting VM %s: %w", vmid, err)
	}
	return nil
}

// StartVM starts a virtual machine.
func (c *Client) StartVM(vmid string) error {
	return c.setVMState(vmid, "start")
}

// StopVM stops a virtual machine (forceful).
func (c *Client) StopVM(vmid string) error {
	return c.setVMState(vmid, "stop")
}

// ShutdownVM gracefully shuts down a virtual machine.
func (c *Client) ShutdownVM(vmid string) error {
	return c.setVMState(vmid, "shutdown")
}

// CloneVM clones a virtual machine.
func (c *Client) CloneVM(vmid string, newid int, name string, full bool) error {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return err
	}

	fullInt := 0
	if full {
		fullInt = 1
	}

	req := CloneRequest{
		NewID: strconv.Itoa(newid),
		Name:  name,
		Full:  fullInt,
	}

	path := fmt.Sprintf("%s/qemu/%s/clone", c.nodePath(node, ""), vmid)
	_, err = c.Post(ctx, path, req)
	if err != nil {
		return fmt.Errorf("cloning VM %s: %w", vmid, err)
	}
	return nil
}

// ResizeVM resizes a VM's disk.
func (c *Client) ResizeVM(vmid, disk, size string) error {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return err
	}

	path := fmt.Sprintf("%s/qemu/%s/resize?disk=%s&size=%s",
		c.nodePath(node, ""), vmid, url.QueryEscape(disk), url.QueryEscape(size))
	_, err = c.Put(ctx, path, nil)
	if err != nil {
		return fmt.Errorf("resizing VM %s disk %s: %w", vmid, disk, err)
	}
	return nil
}

// MonitorVM returns QEMU monitor command output.
func (c *Client) MonitorVM(vmid, command string) (string, error) {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return "", err
	}

	path := fmt.Sprintf("%s/qemu/%s/monitor", c.nodePath(node, ""), vmid)
	body := map[string]string{"command": command}
	data, err := c.Post(ctx, path, body)
	if err != nil {
		return "", fmt.Errorf("monitor command on VM %s: %w", vmid, err)
	}

	var result string
	if err := decodeJSON(data, &result); err != nil {
		return string(data), nil
	}
	return result, nil
}

func (c *Client) setVMState(vmid, action string) error {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return err
	}

	path := fmt.Sprintf("%s/qemu/%s/status/%s", c.nodePath(node, ""), vmid, action)
	_, err = c.Post(ctx, path, nil)
	if err != nil {
		return fmt.Errorf("%s VM %s: %w", action, vmid, err)
	}
	return nil
}

func (c *Client) resolveVMNode(vmid string) (string, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/cluster/resources?type=vm")
	if err != nil {
		return "", fmt.Errorf("resolving VM node: %w", err)
	}

	var resources []VM
	if err := decodeJSON(data, &resources); err != nil {
		return "", fmt.Errorf("decoding cluster resources: %w", err)
	}

	for _, vm := range resources {
		if strconv.Itoa(vm.VMID) == vmid {
			return vm.Node, nil
		}
	}

	return "", fmt.Errorf("VM %s not found", vmid)
}
