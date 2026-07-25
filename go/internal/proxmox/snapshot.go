// SPDX-License-Identifier: MIT

package proxmox

import (
	"context"
	"fmt"
	"net/url"
)

// Snapshot represents a VM snapshot.
type Snapshot struct {
	ID      int    `json:"id"`
	Name    string `json:"name"`
	Time    string `json:"time"`
	VMSize  int64  `json:"vmstate,omitempty"`
	CPU     int64  `json:"cpu,omitempty"`
	Memory  int64  `json:"mem,omitempty"`
	Parent  string `json:"parent,omitempty"`
}

// SnapshotCreateRequest represents a request to create a snapshot.
type SnapshotCreateRequest struct {
	Name        string `json:"snapname"`
	Description string `json:"description,omitempty"`
	VMState     int    `json:"vmstate,omitempty"`
}

// ListSnapshots returns all snapshots for a VM.
func (c *Client) ListSnapshots(vmid string) ([]Snapshot, error) {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}

	path := fmt.Sprintf("%s/qemu/%s/snapshot", c.nodePath(node, ""), vmid)
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("listing snapshots for VM %s: %w", vmid, err)
	}

	var snapshots []Snapshot
	if err := decodeJSON(data, &snapshots); err != nil {
		return nil, fmt.Errorf("decoding snapshots: %w", err)
	}
	return snapshots, nil
}

// CreateSnapshot creates a snapshot of a VM.
func (c *Client) CreateSnapshot(vmid, name, description string) error {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return err
	}

	req := SnapshotCreateRequest{
		Name:        name,
		Description: description,
		VMState:     1,
	}

	path := fmt.Sprintf("%s/qemu/%s/snapshot", c.nodePath(node, ""), vmid)
	_, err = c.Post(ctx, path, req)
	if err != nil {
		return fmt.Errorf("creating snapshot %s on VM %s: %w", name, vmid, err)
	}
	return nil
}

// DeleteSnapshot deletes a snapshot from a VM.
func (c *Client) DeleteSnapshot(vmid, name string) error {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return err
	}

	path := fmt.Sprintf("%s/qemu/%s/snapshot/%s",
		c.nodePath(node, ""), vmid, url.PathEscape(name))
	_, err = c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("deleting snapshot %s from VM %s: %w", name, vmid, err)
	}
	return nil
}

// RollbackSnapshot rolls back a VM to a specific snapshot.
func (c *Client) RollbackSnapshot(vmid, name string) error {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return err
	}

	path := fmt.Sprintf("%s/qemu/%s/snapshot/%s/rollback",
		c.nodePath(node, ""), vmid, url.PathEscape(name))
	_, err = c.Post(ctx, path, nil)
	if err != nil {
		return fmt.Errorf("rolling back VM %s to snapshot %s: %w", vmid, name, err)
	}
	return nil
}

// GetSnapshot returns details of a specific snapshot.
func (c *Client) GetSnapshot(vmid, name string) (*Snapshot, error) {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}

	path := fmt.Sprintf("%s/qemu/%s/snapshot/%s",
		c.nodePath(node, ""), vmid, url.PathEscape(name))
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("getting snapshot %s for VM %s: %w", name, vmid, err)
	}

	var snapshot Snapshot
	if err := decodeJSON(data, &snapshot); err != nil {
		return nil, fmt.Errorf("decoding snapshot: %w", err)
	}
	return &snapshot, nil
}
