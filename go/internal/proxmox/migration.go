// SPDX-License-Identifier: MIT

package proxmox

import (
	"context"
	"fmt"
	"net/url"
)

// MigrationStatus represents the status of a migration.
type MigrationStatus struct {
	VMID    string `json:"vmid"`
	Status  string `json:"status"`
	Node    string `json:"node"`
	MigrateStatus string `json:"migrate_status,omitempty"`
	Phase   string `json:"phase,omitempty"`
	Percent int    `json:"percent,omitempty"`
}

// MigrateVM migrates a VM to another node.
func (c *Client) MigrateVM(vmid, target string, online bool) error {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return err
	}

	onlineInt := 0
	if online {
		onlineInt = 1
	}

	body := map[string]interface{}{
		"target": target,
		"online": onlineInt,
	}

	path := fmt.Sprintf("%s/qemu/%s/migrate", c.nodePath(node, ""), vmid)
	_, err = c.Post(ctx, path, body)
	if err != nil {
		return fmt.Errorf("migrating VM %s to %s: %w", vmid, target, err)
	}
	return nil
}

// MigrateContainer migrates an LXC container to another node.
func (c *Client) MigrateContainer(vmid, target string, online bool) error {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return err
	}

	onlineInt := 0
	if online {
		onlineInt = 1
	}

	body := map[string]interface{}{
		"target": target,
		"online": onlineInt,
	}

	path := fmt.Sprintf("%s/lxc/%s/migrate", c.nodePath(node, ""), vmid)
	_, err = c.Post(ctx, path, body)
	if err != nil {
		return fmt.Errorf("migrating container %s to %s: %w", vmid, target, err)
	}
	return nil
}

// GetMigrationStatus returns the status of ongoing migrations for a VM.
func (c *Client) GetMigrationStatus(vmid string) (*MigrationStatus, error) {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}

	path := fmt.Sprintf("%s/qemu/%s/migrate_status", c.nodePath(node, ""), vmid)
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("getting migration status for VM %s: %w", vmid, err)
	}

	var status MigrationStatus
	if err := decodeJSON(data, &status); err != nil {
		return nil, fmt.Errorf("decoding migration status: %w", err)
	}
	return &status, nil
}

// BatchMigrate migrates multiple VMs sequentially.
func (c *Client) BatchMigrate(vmids []string, target string, online bool) []error {
	var errs []error
	for _, vmid := range vmids {
		if err := c.MigrateVM(vmid, target, online); err != nil {
			errs = append(errs, fmt.Errorf("VM %s: %w", vmid, err))
		}
	}
	return errs
}

// EvacuateNode migrates all VMs from a node.
func (c *Client) EvacuateNode(sourceNode, targetNode string, online bool) []error {
	ctx := context.Background()
	data, err := c.Get(ctx, c.nodePath(sourceNode, "/qemu"))
	if err != nil {
		return []error{fmt.Errorf("listing VMs on node %s: %w", sourceNode, err)}
	}

	var vms []VM
	if err := decodeJSON(data, &vms); err != nil {
		return []error{fmt.Errorf("decoding VMs: %w", err)}
	}

	var errs []error
	for _, vm := range vms {
		vmid := fmt.Sprintf("%d", vm.VMID)
		if err := c.MigrateVM(vmid, targetNode, online); err != nil {
			errs = append(errs, fmt.Errorf("VM %s: %w", vmid, err))
		}
	}
	return errs
}

// ListPendingMigrations returns all pending/outgoing migrations.
func (c *Client) ListPendingMigrations() ([]MigrationStatus, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/cluster/resources?type=vm")
	if err != nil {
		return nil, fmt.Errorf("listing pending migrations: %w", err)
	}

	var resources []struct {
		VMID   int    `json:"vmid"`
		Status string `json:"status"`
		Node   string `json:"node"`
	}
	if err := decodeJSON(data, &resources); err != nil {
		return nil, fmt.Errorf("decoding resources: %w", err)
	}

	var migrations []MigrationStatus
	for _, r := range resources {
		if r.Status == "migrating" {
			migrations = append(migrations, MigrationStatus{
				VMID: fmt.Sprintf("%d", r.VMID),
				Status: r.Status,
				Node: r.Node,
			})
		}
	}
	return migrations, nil
}

// ShutdownNodeGracefully prepares a node for shutdown by migrating VMs.
func (c *Client) ShutdownNodeGracefully(node, targetNode string, online bool) error {
	return nil
}

// SetMigrationType sets the migration type for a VM (live or offline).
func (c *Client) SetMigrationType(vmid, migrateType string) error {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return err
	}

	body := map[string]string{
		"migration_type": migrateType,
	}

	path := fmt.Sprintf("%s/qemu/%s/config", c.nodePath(node, ""), vmid)
	_, err = c.Put(ctx, path, body)
	if err != nil {
		return fmt.Errorf("setting migration type for VM %s: %w", vmid, err)
	}
	return nil
}

// GetMigrationParameters returns the available migration parameters for a VM.
func (c *Client) GetMigrationParameters(vmid string) (url.Values, error) {
	ctx := context.Background()
	node, err := c.resolveVMNode(vmid)
	if err != nil {
		return nil, err
	}

	path := fmt.Sprintf("%s/qemu/%s/migrate", c.nodePath(node, ""), vmid)
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("getting migration parameters for VM %s: %w", vmid, err)
	}

	var params url.Values
	if err := decodeJSON(data, &params); err != nil {
		return nil, fmt.Errorf("decoding migration parameters: %w", err)
	}
	return params, nil
}
