// SPDX-License-Identifier: MIT

package proxmox

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
)

// NetworkInterface represents a network interface on a node.
type NetworkInterface struct {
	Name    string `json:"name"`
	Type    string `json:"type"`
	Address string `json:"address,omitempty"`
	Netmask string `json:"netmask,omitempty"`
	Gateway string `json:"gateway,omitempty"`
	BridgePorts string `json:"bridge-ports,omitempty"`
	BridgeSTP   string `json:"bridge-stp,omitempty"`
	BridgeFD    string `json:"bridge-fd,omitempty"`
	Comment string `json:"comment,omitempty"`
	Active  bool   `json:"active"`
	Autostart bool `json:"autostart"`
}

// NetworkCreateRequest represents a request to create a network interface.
type NetworkCreateRequest struct {
	Iface  string `json:"iface"`
	Type   string `json:"type"`
	Comment string `json:"comment,omitempty"`
	Address string `json:"cidr,omitempty"`
	Gateway string `json:"gateway,omitempty"`
	BridgePorts string `json:"bridge-ports,omitempty"`
	BridgeSTP   string `json:"bridge-stp,omitempty"`
	BridgeFD    string `json:"bridge-fd,omitempty"`
	BondPrimary string `json:"bond-primary,omitempty"`
	BondMode    string `json:"bond-mode,omitempty"`
}

// ListInterfaces returns all network interfaces on a node.
func (c *Client) ListInterfaces(node string) ([]NetworkInterface, error) {
	ctx := context.Background()
	path := fmt.Sprintf("%s/network", c.nodePath(node, ""))
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("listing interfaces on %s: %w", node, err)
	}

	var ifaces []NetworkInterface
	if err := decodeJSON(data, &ifaces); err != nil {
		return nil, fmt.Errorf("decoding interfaces: %w", err)
	}
	return ifaces, nil
}

// GetInterface returns details of a specific network interface.
func (c *Client) GetInterface(node, name string) (*NetworkInterface, error) {
	ctx := context.Background()
	path := fmt.Sprintf("%s/network/%s", c.nodePath(node, ""), url.PathEscape(name))
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("getting interface %s on %s: %w", name, node, err)
	}

	var iface NetworkInterface
	if err := decodeJSON(data, &iface); err != nil {
		return nil, fmt.Errorf("decoding interface: %w", err)
	}
	return &iface, nil
}

// CreateBridge creates a Linux bridge interface.
func (c *Client) CreateBridge(node, name, bridgePorts string) error {
	req := NetworkCreateRequest{
		Iface:       name,
		Type:        "bridge",
		BridgePorts: bridgePorts,
	}
	return c.createInterface(node, req)
}

// DeleteBridge deletes a bridge interface.
func (c *Client) DeleteBridge(node, name string) error {
	return c.deleteInterface(node, name)
}

// CreateBond creates a network bond.
func (c *Client) CreateBond(node, name, mode string, slaves []string) error {
	slaveStr := ""
	for i, s := range slaves {
		if i > 0 {
			slaveStr += ","
		}
		slaveStr += s
	}

	req := NetworkCreateRequest{
		Iface:    name,
		Type:     "bond",
		BondMode: mode,
		Comment:  slaveStr,
	}
	return c.createInterface(node, req)
}

// DeleteBond deletes a bond interface.
func (c *Client) DeleteBond(node, name string) error {
	return c.deleteInterface(node, name)
}

// CreateVLAN creates a VLAN interface.
func (c *Client) CreateVLAN(node, name, parent string, vlanID int) error {
	req := NetworkCreateRequest{
		Iface:   name,
		Type:    "vlan",
		Comment: fmt.Sprintf("%s.%d", parent, vlanID),
	}
	return c.createInterface(node, req)
}

// ApplyNetworkChanges applies pending network changes.
func (c *Client) ApplyNetworkChanges(node string) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/network/apply", c.nodePath(node, ""))
	_, err := c.Post(ctx, path, nil)
	if err != nil {
		return fmt.Errorf("applying network changes on %s: %w", node, err)
	}
	return nil
}

// ReloadNetworkConfig reloads the network configuration from disk.
func (c *Client) ReloadNetworkConfig(node string) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/network/reload", c.nodePath(node, ""))
	_, err := c.Post(ctx, path, nil)
	if err != nil {
		return fmt.Errorf("reloading network config on %s: %w", node, err)
	}
	return nil
}

// SetInterfaceIP sets an IP address on an interface.
func (c *Client) SetInterfaceIP(node, name, cidr string) error {
	ctx := context.Background()
	body := map[string]string{
		"cidr": cidr,
	}
	path := fmt.Sprintf("%s/network/%s", c.nodePath(node, ""), url.PathEscape(name))
	_, err := c.Put(ctx, path, body)
	if err != nil {
		return fmt.Errorf("setting IP on interface %s: %w", name, err)
	}
	return nil
}

func (c *Client) createInterface(node string, req NetworkCreateRequest) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/network", c.nodePath(node, ""))
	_, err := c.Post(ctx, path, req)
	if err != nil {
		return fmt.Errorf("creating interface %s: %w", req.Iface, err)
	}
	return nil
}

func (c *Client) deleteInterface(node, name string) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/network/%s", c.nodePath(node, ""), url.PathEscape(name))
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("deleting interface %s: %w", name, err)
	}
	return nil
}

// GetNetworkConfigRaw returns raw network configuration.
func (c *Client) GetNetworkConfigRaw(node string) (json.RawMessage, error) {
	ctx := context.Background()
	path := fmt.Sprintf("%s/network", c.nodePath(node, ""))
	return c.Get(ctx, path)
}
