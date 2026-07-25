// SPDX-License-Identifier: MIT

package proxmox

import (
	"context"
	"encoding/json"
	"fmt"
)

// ClusterStatus represents the overall cluster status.
type ClusterStatus struct {
	Name   string        `json:"name"`
	Type   string        `json:"type"`
	Nodes  []ClusterNode `json:"nodes,omitempty"`
	Quorate int          `json:"quorate,omitempty"`
}

// ClusterNode represents a node in the cluster.
type ClusterNode struct {
	Name   string `json:"name"`
	Status string `json:"status"`
	ID     int    `json:"id"`
	IP     string `json:"ip,omitempty"`
}

// ClusterConfig represents cluster configuration.
type ClusterConfig struct {
	ClusterName string `json:"cluster_name,omitempty"`
	ClusterNetwork string `json:"cluster_network,omitempty"`
}

// GetClusterStatus returns the cluster status.
func (c *Client) GetClusterStatus() (*ClusterStatus, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/cluster/status")
	if err != nil {
		return nil, fmt.Errorf("getting cluster status: %w", err)
	}

	var statuses []ClusterStatus
	if err := decodeJSON(data, &statuses); err != nil {
		return nil, fmt.Errorf("decoding cluster status: %w", err)
	}

	for _, s := range statuses {
		if s.Type == "cluster" {
			return &s, nil
		}
	}

	if len(statuses) > 0 {
		return &statuses[0], nil
	}

	return &ClusterStatus{}, nil
}

// GetClusterNodes returns all nodes in the cluster.
func (c *Client) GetClusterNodes() ([]ClusterNode, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/cluster/status")
	if err != nil {
		return nil, fmt.Errorf("getting cluster nodes: %w", err)
	}

	var statuses []ClusterStatus
	if err := decodeJSON(data, &statuses); err != nil {
		return nil, fmt.Errorf("decoding cluster status: %w", err)
	}

	for _, s := range statuses {
		if s.Type == "cluster" {
			return s.Nodes, nil
		}
	}

	return nil, nil
}

// ListNodes returns detailed node information.
func (c *Client) ListNodes() ([]NodeInfo, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/nodes")
	if err != nil {
		return nil, fmt.Errorf("listing nodes: %w", err)
	}

	var nodes []NodeInfo
	if err := decodeJSON(data, &nodes); err != nil {
		return nil, fmt.Errorf("decoding nodes: %w", err)
	}
	return nodes, nil
}

// NodeInfo represents a Proxmox node.
type NodeInfo struct {
	Node      string     `json:"node"`
	Status    string     `json:"status"`
	CPU       float64    `json:"cpu"`
	MaxCPU    int        `json:"maxcpu"`
	Memory    NodeMemory `json:"mem"`
	MaxMemory int64      `json:"maxmem"`
	Disk      NodeDisk   `json:"disk"`
	MaxDisk   int64      `json:"maxdisk"`
	Uptime    int64      `json:"uptime"`
	ID        string     `json:"id,omitempty"`
	SSLFingerprint string `json:"ssl_fingerprint,omitempty"`
}

// NodeMemory represents node memory usage.
type NodeMemory struct {
	Used  int64 `json:"used"`
	Total int64 `json:"total"`
	Free  int64 `json:"free"`
}

// NodeDisk represents node disk usage.
type NodeDisk struct {
	Used  int64 `json:"used"`
	Total int64 `json:"total"`
	Free  int64 `json:"free"`
}

// GetNodeStatus returns detailed status of a specific node.
func (c *Client) GetNodeStatus(node string) (*NodeInfo, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, c.nodePath(node, "/status"))
	if err != nil {
		return nil, fmt.Errorf("getting node %s status: %w", node, err)
	}

	var status NodeInfo
	if err := decodeJSON(data, &status); err != nil {
		return nil, fmt.Errorf("decoding node status: %w", err)
	}
	return &status, nil
}

// GetClusterResources returns all cluster resources.
func (c *Client) GetClusterResources(resourceType string) (json.RawMessage, error) {
	ctx := context.Background()
	path := "/api2/json/cluster/resources"
	if resourceType != "" {
		path += "?type=" + resourceType
	}
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("getting cluster resources: %w", err)
	}
	return data, nil
}

// GetClusterConfig returns cluster join configuration.
func (c *Client) GetClusterConfig() (*ClusterConfig, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/cluster/config")
	if err != nil {
		return nil, fmt.Errorf("getting cluster config: %w", err)
	}

	var config ClusterConfig
	if err := decodeJSON(data, &config); err != nil {
		return nil, fmt.Errorf("decoding cluster config: %w", err)
	}
	return &config, nil
}

// JoinCluster joins a node to the cluster.
func (c *Client) JoinCluster(node, address, peerAddress, fingerprint string) error {
	ctx := context.Background()
	body := map[string]string{
		"address":      address,
		"peer_address": peerAddress,
		"fingerprint":  fingerprint,
	}
	path := fmt.Sprintf("%s/cluster/join", c.nodePath(node, ""))
	_, err := c.Post(ctx, path, body)
	if err != nil {
		return fmt.Errorf("joining cluster: %w", err)
	}
	return nil
}

// RemoveNodeFromCluster removes a node from the cluster.
func (c *Client) RemoveNodeFromCluster(nodeID string) error {
	ctx := context.Background()
	path := fmt.Sprintf("/api2/json/cluster/config/nodes/%s", nodeID)
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("removing node %s from cluster: %w", nodeID, err)
	}
	return nil
}

// GetClusterQuorum returns quorum information.
func (c *Client) GetClusterQuorum() (json.RawMessage, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/cluster/ha/resources")
	if err != nil {
		return nil, fmt.Errorf("getting quorum info: %w", err)
	}
	return data, nil
}
