// SPDX-License-Identifier: MIT

package proxmox

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
	"strconv"
)

// Container represents an LXC container.
type Container struct {
	VMID   int    `json:"vmid"`
	Name   string `json:"name"`
	Status string `json:"status"`
	CPUs   int    `json:"cpus"`
	MaxMem int64  `json:"maxmem"`
	MaxDisk int64 `json:"maxdisk"`
	Node   string `json:"node,omitempty"`
	Type   string `json:"type,omitempty"`
}

// ContainerStatus represents detailed container status information.
type ContainerStatus struct {
	VMID    string  `json:"vmid"`
	Name    string  `json:"name"`
	Status  string  `json:"status"`
	CPU     float64 `json:"cpu"`
	CPUs    int     `json:"cpus"`
	Memory  int64   `json:"mem"`
	MaxMem  int64   `json:"maxmem"`
	Swap    int64   `json:"swap"`
	MaxSwap int64   `json:"maxswap"`
	Disk    int64   `json:"disk"`
	MaxDisk int64   `json:"maxdisk"`
	Uptime  int64   `json:"uptime"`
	PID     int     `json:"pid,omitempty"`
	IPs     []string `json:"ip,omitempty"`
}

// ContainerCreateRequest represents a request to create an LXC container.
type ContainerCreateRequest struct {
	VMID     string            `json:"vmid"`
	Hostname string            `json:"hostname,omitempty"`
	OSTemplate string          `json:"ostemplate,omitempty"`
	Storage  string            `json:"storage,omitempty"`
	Memory   int               `json:"memory,omitempty"`
	Swap     int               `json:"swap,omitempty"`
	CPU      float64           `json:"cpu,omitempty"`
	Cores    int               `json:"cores,omitempty"`
	RootFS   string            `json:"rootfs,omitempty"`
	Net0     string            `json:"net0,omitempty"`
	Password string            `json:"password,omitempty"`
	Unprivileged bool          `json:"unprivileged,omitempty"`
	Features map[string]string `json:"features,omitempty"`
}

// ListContainers returns all LXC containers.
func (c *Client) ListContainers() ([]Container, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/cluster/resources?type=vm")
	if err != nil {
		return nil, fmt.Errorf("listing containers: %w", err)
	}

	var resources []Container
	if err := decodeJSON(data, &resources); err != nil {
		return nil, fmt.Errorf("decoding containers: %w", err)
	}

	var lxc []Container
	for _, ct := range resources {
		if ct.Type == "lxc" {
			lxc = append(lxc, ct)
		}
	}
	return lxc, nil
}

// GetContainerStatus returns the status of a specific container.
func (c *Client) GetContainerStatus(vmid string) (*ContainerStatus, error) {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}

	path := fmt.Sprintf("%s/lxc/%s/status/current", c.nodePath(node, ""), vmid)
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("getting container %s status: %w", vmid, err)
	}

	var status ContainerStatus
	if err := decodeJSON(data, &status); err != nil {
		return nil, fmt.Errorf("decoding container status: %w", err)
	}
	return &status, nil
}

// CreateContainer creates a new LXC container.
func (c *Client) CreateContainer(node string, req ContainerCreateRequest) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/lxc", c.nodePath(node, ""))
	_, err := c.Post(ctx, path, req)
	if err != nil {
		return fmt.Errorf("creating container: %w", err)
	}
	return nil
}

// DeleteContainer deletes an LXC container.
func (c *Client) DeleteContainer(vmid string) error {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return err
	}

	path := fmt.Sprintf("%s/lxc/%s", c.nodePath(node, ""), vmid)
	_, err = c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("deleting container %s: %w", vmid, err)
	}
	return nil
}

// StartContainer starts an LXC container.
func (c *Client) StartContainer(vmid string) error {
	return c.setContainerState(vmid, "start")
}

// StopContainer stops an LXC container.
func (c *Client) StopContainer(vmid string) error {
	return c.setContainerState(vmid, "stop")
}

// ShutdownContainer gracefully shuts down an LXC container.
func (c *Client) ShutdownContainer(vmid string) error {
	return c.setContainerState(vmid, "shutdown")
}

// ResizeContainer resizes a container's rootfs.
func (c *Client) ResizeContainer(vmid, disk, size string) error {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return err
	}

	path := fmt.Sprintf("%s/lxc/%s/resize?disk=%s&size=%s",
		c.nodePath(node, ""), vmid, url.QueryEscape(disk), url.QueryEscape(size))
	_, err = c.Put(ctx, path, nil)
	if err != nil {
		return fmt.Errorf("resizing container %s disk %s: %w", vmid, disk, err)
	}
	return nil
}

// ExecContainer executes a command inside a container.
func (c *Client) ExecContainer(vmid string, command []string) (int, error) {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return 0, err
	}

	body := map[string]interface{}{
		"command": command,
	}

	path := fmt.Sprintf("%s/lxc/%s/enter", c.nodePath(node, ""), vmid)
	data, err := c.Post(ctx, path, body)
	if err != nil {
		return 0, fmt.Errorf("executing command in container %s: %w", vmid, err)
	}

	var result struct {
		ExitCode int `json:"exitcode"`
	}
	if err := decodeJSON(data, &result); err != nil {
		return 0, nil
	}
	return result.ExitCode, nil
}

func (c *Client) setContainerState(vmid, action string) error {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return err
	}

	path := fmt.Sprintf("%s/lxc/%s/status/%s", c.nodePath(node, ""), vmid, action)
	_, err = c.Post(ctx, path, nil)
	if err != nil {
		return fmt.Errorf("%s container %s: %w", action, vmid, err)
	}
	return nil
}

// resolveContainerNode finds the node hosting a container.
func (c *Client) resolveContainerNode(vmid string) (string, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/cluster/resources?type=vm")
	if err != nil {
		return "", fmt.Errorf("resolving container node: %w", err)
	}

	var resources []struct {
		VMID   int    `json:"vmid"`
		Node   string `json:"node"`
		Type   string `json:"type"`
	}
	if err := decodeJSON(data, &resources); err != nil {
		return "", fmt.Errorf("decoding resources: %w", err)
	}

	for _, r := range resources {
		if strconv.Itoa(r.VMID) == vmid && r.Type == "lxc" {
			return r.Node, nil
		}
	}

	return "", fmt.Errorf("container %s not found", vmid)
}
