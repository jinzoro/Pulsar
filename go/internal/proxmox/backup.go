// SPDX-License-Identifier: MIT

package proxmox

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
)

// Backup represents a VZDump backup.
type Backup struct {
	Volid      string `json:"volid"`
	Size       int64  `json:"size"`
	Format     string `json:"format"`
	Ctime      int64  `json:"ctime"`
	Mtime      int64  `json:"mtime"`
	Subdir     string `json:"subdir,omitempty"`
	Content    string `json:"content,omitempty"`
	VMID       string `json:"vmid,omitempty"`
}

// BackupStatus represents the status of a backup job.
type BackupStatus struct {
	Status  string `json:"status"`
	VMID    string `json:"vmid"`
	Storage string `json:"storage"`
	StartTime int64 `json:"starttime,omitempty"`
}

// BackupRequest represents a request to create a backup.
type BackupRequest struct {
	Storage    string `json:"storage"`
	Mode       string `json:"mode,omitempty"`
	Compress   string `json:"compress,omitempty"`
	Exclude    string `json:"exclude,omitempty"`
	Include    string `json:"include,omitempty"`
	Note       string `json:"note,omitempty"`
	Remove     int    `json:"remove,omitempty"`
}

// BackupVerifyRequest represents a backup verification request.
type BackupVerifyRequest struct {
	Storage  string `json:"storage"`
	Volid    string `json:"volid,omitempty"`
	Force    int    `json:"force,omitempty"`
}

// BackupPruneRequest represents a backup prune request.
type BackupPruneRequest struct {
	Storage       string `json:"storage"`
	KeepLast      int    `json:"keep-last,omitempty"`
	KeepDaily     int    `json:"keep-daily,omitempty"`
	KeepWeekly    int    `json:"keep-weekly,omitempty"`
	KeepMonthly   int    `json:"keep-monthly,omitempty"`
	KeepYearly    int    `json:"keep-yearly,omitempty"`
	KeepHourly    int    `json:"keep-hourly,omitempty"`
}

// ListBackups lists backups in a storage pool.
func (c *Client) ListBackups(storageName string) ([]Backup, error) {
	ctx := context.Background()
	nodes, err := c.GetClusterNodes()
	if err != nil {
		return nil, fmt.Errorf("getting nodes for backup list: %w", err)
	}

	var allBackups []Backup
	for _, node := range nodes {
		path := fmt.Sprintf("%s/storage/%s/content?content=vzdump",
			c.nodePath(node.Name, ""), url.PathEscape(storageName))
		data, err := c.Get(ctx, path)
		if err != nil {
			continue
		}
		var backups []Backup
		if err := decodeJSON(data, &backups); err != nil {
			continue
		}
		allBackups = append(allBackups, backups...)
	}
	return allBackups, nil
}

// CreateBackup starts a VZDump backup job.
func (c *Client) CreateBackup(node, vmtype, vmid string, req BackupRequest) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/%s/%s/backup",
		c.nodePath(node, ""), vmtype, vmid)
	_, err := c.Post(ctx, path, req)
	if err != nil {
		return fmt.Errorf("creating backup for %s %s: %w", vmtype, vmid, err)
	}
	return nil
}

// RestoreBackup restores a backup to a VM/container.
func (c *Client) RestoreBackup(node, vmtype, vmid, volid string) error {
	ctx := context.Background()
	params := url.Values{}
	params.Set("volid", volid)

	path := fmt.Sprintf("%s/%s/%s/restore?%s",
		c.nodePath(node, ""), vmtype, vmid, params.Encode())
	_, err := c.Post(ctx, path, nil)
	if err != nil {
		return fmt.Errorf("restoring backup %s: %w", volid, err)
	}
	return nil
}

// VerifyBackup verifies the integrity of a backup.
func (c *Client) VerifyBackup(node string, req BackupVerifyRequest) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/backup/verify", c.nodePath(node, ""))
	_, err := c.Post(ctx, path, req)
	if err != nil {
		return fmt.Errorf("verifying backup: %w", err)
	}
	return nil
}

// PruneBackups prunes old backups based on retention policy.
func (c *Client) PruneBackups(node string, req BackupPruneRequest) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/backup/prune", c.nodePath(node, ""))
	_, err := c.Post(ctx, path, req)
	if err != nil {
		return fmt.Errorf("pruning backups: %w", err)
	}
	return nil
}

// DeleteBackup deletes a specific backup.
func (c *Client) DeleteBackup(node, storageName, volid string) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/storage/%s/content/%s",
		c.nodePath(node, ""), url.PathEscape(storageName), url.PathEscape(volid))
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("deleting backup %s: %w", volid, err)
	}
	return nil
}

// GetBackupStatus returns the status of running backup jobs.
func (c *Client) GetBackupStatus(node string) ([]BackupStatus, error) {
	ctx := context.Background()
	path := fmt.Sprintf("%s/backup/status", c.nodePath(node, ""))
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("getting backup status: %w", err)
	}

	var statuses []BackupStatus
	if err := decodeJSON(data, &statuses); err != nil {
		return nil, fmt.Errorf("decoding backup status: %w", err)
	}
	return statuses, nil
}

// ListBackupJobs returns all configured backup jobs.
func (c *Client) ListBackupJobs() (json.RawMessage, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/cluster/backup")
	if err != nil {
		return nil, fmt.Errorf("listing backup jobs: %w", err)
	}
	return data, nil
}
