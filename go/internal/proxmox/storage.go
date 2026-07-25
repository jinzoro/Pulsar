// SPDX-License-Identifier: MIT

package proxmox

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
)

// Storage represents a Proxmox storage pool.
type Storage struct {
	Storage  string `json:"storage"`
	Type     string `json:"type"`
	Status   string `json:"status"`
	Content  string `json:"content"`
	Active   int    `json:"active"`
	Enabled  int    `json:"enabled"`
	Total    int64  `json:"total"`
	Used     int64  `json:"used"`
	Avail    int64  `json:"avail"`
	Percent  float64 `json:"percent"`
}

// StorageStatus represents detailed storage status.
type StorageStatus struct {
	Storage string        `json:"storage"`
	Type    string        `json:"type"`
	Status  string        `json:"status"`
	Active  bool          `json:"active"`
	Content []string      `json:"content"`
	Total   int64         `json:"total"`
	Used    int64         `json:"used"`
	Avail   int64         `json:"avail"`
	Plugins json.RawMessage `json:"plugins,omitempty"`
}

// StorageContent represents content within a storage pool.
type StorageContent struct {
	Subdir  string `json:"subdir,omitempty"`
	Content string `json:"content,omitempty"`
	Volid   string `json:"volid,omitempty"`
	Size    int64  `json:"size,omitempty"`
	Format  string `json:"format,omitempty"`
	Ctime   int64  `json:"ctime,omitempty"`
	FormatInfo string `json:"format-info,omitempty"`
}

// StorageCreateRequest represents a request to create storage.
type StorageCreateRequest struct {
	Storage  string            `json:"storage"`
	Type     string            `json:"type"`
	Content  string            `json:"content,omitempty"`
	Path     string            `json:"path,omitempty"`
	Server   string            `json:"server,omitempty"`
	Export   string            `json:"export,omitempty"`
	Pool     string            `json:"pool,omitempty"`
	Bridge   string            `json:"bridge,omitempty"`
	VGName   string            `json:"vgname,omitempty"`
	Disable  bool              `json:"disable,omitempty"`
	Options  map[string]string `json:"options,omitempty"`
}

// ListStorage returns all storage pools across all nodes.
func (c *Client) ListStorage() ([]Storage, error) {
	return c.ListStorageByNode("")
}

// ListStorageByNode returns storage pools on a specific node.
func (c *Client) ListStorageByNode(node string) ([]Storage, error) {
	ctx := context.Background()

	var path string
	if node != "" {
		path = c.nodePath(node, "/storage")
	} else {
		path = "/api2/json/cluster/resources?type=storage"
	}

	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("listing storage: %w", err)
	}

	var storage []Storage
	if err := decodeJSON(data, &storage); err != nil {
		return nil, fmt.Errorf("decoding storage: %w", err)
	}
	return storage, nil
}

// GetStorageStatus returns detailed status for a storage pool.
func (c *Client) GetStorageStatus(node, storageName string) (*StorageStatus, error) {
	ctx := context.Background()
	path := fmt.Sprintf("%s/storage/%s/status", c.nodePath(node, ""), url.PathEscape(storageName))
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("getting storage %s status: %w", storageName, err)
	}

	var status StorageStatus
	if err := decodeJSON(data, &status); err != nil {
		return nil, fmt.Errorf("decoding storage status: %w", err)
	}
	return &status, nil
}

// GetStorageContent returns the content of a storage pool.
func (c *Client) GetStorageContent(node, storageName string) ([]StorageContent, error) {
	ctx := context.Background()
	path := fmt.Sprintf("%s/storage/%s/content", c.nodePath(node, ""), url.PathEscape(storageName))
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("getting storage %s content: %w", storageName, err)
	}

	var content []StorageContent
	if err := decodeJSON(data, &content); err != nil {
		return nil, fmt.Errorf("decoding storage content: %w", err)
	}
	return content, nil
}

// AddStorage creates a new storage pool.
func (c *Client) AddStorage(node string, req StorageCreateRequest) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/storage", c.nodePath(node, ""))
	_, err := c.Post(ctx, path, req)
	if err != nil {
		return fmt.Errorf("creating storage %s: %w", req.Storage, err)
	}
	return nil
}

// RemoveStorage deletes a storage pool.
func (c *Client) RemoveStorage(node, storageName string) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/storage/%s", c.nodePath(node, ""), url.PathEscape(storageName))
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("removing storage %s: %w", storageName, err)
	}
	return nil
}

// MoveDisk moves a disk from one storage to another.
func (c *Client) MoveDisk(node, vmtype, vmid, disk, targetStorage string, delete bool) error {
	ctx := context.Background()
	deleteInt := 0
	if delete {
		deleteInt = 1
	}

	params := url.Values{}
	params.Set("disk", disk)
	params.Set("storage", targetStorage)
	params.Set("delete", fmt.Sprintf("%d", deleteInt))

	path := fmt.Sprintf("%s/%s/%s/move_disk?%s",
		c.nodePath(node, ""), vmtype, vmid, params.Encode())
	_, err := c.Post(ctx, path, nil)
	if err != nil {
		return fmt.Errorf("moving disk %s on %s %s: %w", disk, vmtype, vmid, err)
	}
	return nil
}

// ResizeDisk resizes a disk on a VM/container.
func (c *Client) ResizeDisk(node, vmtype, vmid, disk, size string) error {
	ctx := context.Background()
	params := url.Values{}
	params.Set("disk", disk)
	params.Set("size", size)

	path := fmt.Sprintf("%s/%s/%s/resize?%s",
		c.nodePath(node, ""), vmtype, vmid, params.Encode())
	_, err := c.Put(ctx, path, nil)
	if err != nil {
		return fmt.Errorf("resizing disk %s on %s %s: %w", disk, vmtype, vmid, err)
	}
	return nil
}
