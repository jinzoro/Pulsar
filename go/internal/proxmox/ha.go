// SPDX-License-Identifier: MIT

package proxmox

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
)

// HAGroup represents a High Availability group.
type HAGroup struct {
	Group    string   `json:"group"`
	Nodes    string   `json:"nodes"`
	Type     string   `json:"type,omitempty"`
	Comment  string   `json:"comment,omitempty"`
}

// HAResource represents a High Availability resource.
type HAResource struct {
	SID     string `json:"sid"`
	Type    string `json:"type"`
	State   string `json:"state"`
	Group   string `json:"group,omitempty"`
	MaxRelocate int `json:"max_relocate,omitempty"`
	MaxRestart  int `json:"max_restart,omitempty"`
	Comment string `json:"comment,omitempty"`
}

// HAStatus represents the overall HA status.
type HAStatus struct {
	Groups    int `json:"groups"`
	Resources int `json:"resources"`
}

// ListHAGroups returns all HA groups.
func (c *Client) ListHAGroups() ([]HAGroup, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/cluster/ha/groups")
	if err != nil {
		return nil, fmt.Errorf("listing HA groups: %w", err)
	}

	var groups []HAGroup
	if err := decodeJSON(data, &groups); err != nil {
		return nil, fmt.Errorf("decoding HA groups: %w", err)
	}
	return groups, nil
}

// CreateHAGroup creates a new HA group.
func (c *Client) CreateHAGroup(name, nodes, comment string) error {
	ctx := context.Background()
	body := map[string]string{
		"group":   name,
		"nodes":   nodes,
		"comment": comment,
	}
	_, err := c.Post(ctx, "/api2/json/cluster/ha/groups", body)
	if err != nil {
		return fmt.Errorf("creating HA group %s: %w", name, err)
	}
	return nil
}

// DeleteHAGroup deletes an HA group.
func (c *Client) DeleteHAGroup(name string) error {
	ctx := context.Background()
	path := fmt.Sprintf("/api2/json/cluster/ha/groups/%s", url.PathEscape(name))
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("deleting HA group %s: %w", name, err)
	}
	return nil
}

// UpdateHAGroup updates an existing HA group.
func (c *Client) UpdateHAGroup(name, nodes, comment string) error {
	ctx := context.Background()
	body := map[string]string{
		"nodes":   nodes,
		"comment": comment,
	}
	path := fmt.Sprintf("/api2/json/cluster/ha/groups/%s", url.PathEscape(name))
	_, err := c.Put(ctx, path, body)
	if err != nil {
		return fmt.Errorf("updating HA group %s: %w", name, err)
	}
	return nil
}

// ListHAResources returns all HA resources.
func (c *Client) ListHAResources() ([]HAResource, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/cluster/ha/resources")
	if err != nil {
		return nil, fmt.Errorf("listing HA resources: %w", err)
	}

	var resources []HAResource
	if err := decodeJSON(data, &resources); err != nil {
		return nil, fmt.Errorf("decoding HA resources: %w", err)
	}
	return resources, nil
}

// AddHAResource adds a resource to HA management.
func (c *Client) AddHAResource(sid, group, haType string, maxRelocate, maxRestart int) error {
	ctx := context.Background()
	body := map[string]interface{}{
		"sid":           sid,
		"group":         group,
		"type":          haType,
		"max_relocate":  maxRelocate,
		"max_restart":   maxRestart,
	}
	_, err := c.Post(ctx, "/api2/json/cluster/ha/resources", body)
	if err != nil {
		return fmt.Errorf("adding HA resource %s: %w", sid, err)
	}
	return nil
}

// RemoveHAResource removes a resource from HA management.
func (c *Client) RemoveHAResource(sid string) error {
	ctx := context.Background()
	path := fmt.Sprintf("/api2/json/cluster/ha/resources/%s", url.PathEscape(sid))
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("removing HA resource %s: %w", sid, err)
	}
	return nil
}

// SetHAState sets the desired state of an HA resource.
func (c *Client) SetHAState(sid, state string) error {
	ctx := context.Background()
	body := map[string]string{
		"state": state,
	}
	path := fmt.Sprintf("/api2/json/cluster/ha/resources/%s", url.PathEscape(sid))
	_, err := c.Put(ctx, path, body)
	if err != nil {
		return fmt.Errorf("setting HA resource %s state to %s: %w", sid, state, err)
	}
	return nil
}

// GetHAGroup returns a specific HA group.
func (c *Client) GetHAGroup(name string) (*HAGroup, error) {
	ctx := context.Background()
	path := fmt.Sprintf("/api2/json/cluster/ha/groups/%s", url.PathEscape(name))
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("getting HA group %s: %w", name, err)
	}

	var group HAGroup
	if err := decodeJSON(data, &group); err != nil {
		return nil, fmt.Errorf("decoding HA group: %w", err)
	}
	return &group, nil
}

// GetHAResource returns a specific HA resource.
func (c *Client) GetHAResource(sid string) (*HAResource, error) {
	ctx := context.Background()
	path := fmt.Sprintf("/api2/json/cluster/ha/resources/%s", url.PathEscape(sid))
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("getting HA resource %s: %w", sid, err)
	}

	var resource HAResource
	if err := decodeJSON(data, &resource); err != nil {
		return nil, fmt.Errorf("decoding HA resource: %w", err)
	}
	return &resource, nil
}

// GetHAStatus returns overall HA status summary.
func (c *Client) GetHAStatus() (*HAStatus, error) {
	groups, err := c.ListHAGroups()
	if err != nil {
		return nil, err
	}
	resources, err := c.ListHAResources()
	if err != nil {
		return nil, err
	}
	return &HAStatus{
		Groups:    len(groups),
		Resources: len(resources),
	}, nil
}

// EncodeHAGroupForAPI encodes an HA group for the API (JSON format).
func (c *Client) EncodeHAGroupForAPI(group HAGroup) (string, error) {
	data, err := json.Marshal(group)
	if err != nil {
		return "", err
	}
	return string(data), nil
}
