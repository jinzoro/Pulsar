// SPDX-License-Identifier: MIT

package proxmox

import (
	"context"
	"encoding/json"
	"fmt"
	"net/url"
)

// SDNZone represents a Software Defined Networking zone.
type SDNZone struct {
	Zone     string `json:"zone"`
	Type     string `json:"type"`
	MTU      int    `json:"mtu,omitempty"`
	VlanAware int   `json:"vlanaware,omitempty"`
	IPAM     string `json:"ipam,omitempty"`
	DNS      string `json:"dns,omitempty"`
	ReverseDNS string `json:"reverse-dns,omitempty"`
	DHCP     string `json:"dhcp,omitempty"`
	ExitNodes string `json:"exitnodes,omitempty"`
}

// SDNVnet represents a virtual network in SDN.
type SDNVnet struct {
	Vnet     string `json:"vnet"`
	Zone     string `json:"zone"`
	Alias    string `json:"alias,omitempty"`
	VLAN     int    `json:"vlan,omitempty"`
}

// SDNSubnet represents a subnet in SDN.
type SDNSubnet struct {
	Vnet     string `json:"vnet"`
	Subnet   string `json:"subnet"`
	Mask     int    `json:"mask,omitempty"`
	Gateway  string `json:"gateway,omitempty"`
	SNAT     int    `json:"snat,omitempty"`
	DHCPRange string `json:"dhcp-range,omitempty"`
}

// ListSDNZones returns all SDN zones.
func (c *Client) ListSDNZones() ([]SDNZone, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/sdn/zones")
	if err != nil {
		return nil, fmt.Errorf("listing SDN zones: %w", err)
	}

	var zones []SDNZone
	if err := decodeJSON(data, &zones); err != nil {
		return nil, fmt.Errorf("decoding SDN zones: %w", err)
	}
	return zones, nil
}

// CreateSDNZone creates a new SDN zone.
func (c *Client) CreateSDNZone(zone SDNZone) error {
	ctx := context.Background()
	_, err := c.Post(ctx, "/api2/json/sdn/zones", zone)
	if err != nil {
		return fmt.Errorf("creating SDN zone %s: %w", zone.Zone, err)
	}
	return nil
}

// DeleteSDNZone deletes an SDN zone.
func (c *Client) DeleteSDNZone(zone string) error {
	ctx := context.Background()
	path := fmt.Sprintf("/api2/json/sdn/zones/%s", url.PathEscape(zone))
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("deleting SDN zone %s: %w", zone, err)
	}
	return nil
}

// GetSDNZone returns a specific SDN zone.
func (c *Client) GetSDNZone(zone string) (*SDNZone, error) {
	ctx := context.Background()
	path := fmt.Sprintf("/api2/json/sdn/zones/%s", url.PathEscape(zone))
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("getting SDN zone %s: %w", zone, err)
	}

	var z SDNZone
	if err := decodeJSON(data, &z); err != nil {
		return nil, fmt.Errorf("decoding SDN zone: %w", err)
	}
	return &z, nil
}

// ListSDNVnets returns all virtual networks.
func (c *Client) ListSDNVnets() ([]SDNVnet, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/sdn/vnets")
	if err != nil {
		return nil, fmt.Errorf("listing SDN vnets: %w", err)
	}

	var vnets []SDNVnet
	if err := decodeJSON(data, &vnets); err != nil {
		return nil, fmt.Errorf("decoding SDN vnets: %w", err)
	}
	return vnets, nil
}

// CreateSDNVnet creates a new virtual network.
func (c *Client) CreateSDNVnet(vnet SDNVnet) error {
	ctx := context.Background()
	_, err := c.Post(ctx, "/api2/json/sdn/vnets", vnet)
	if err != nil {
		return fmt.Errorf("creating SDN vnet %s: %w", vnet.Vnet, err)
	}
	return nil
}

// DeleteSDNVnet deletes a virtual network.
func (c *Client) DeleteSDNVnet(vnet string) error {
	ctx := context.Background()
	path := fmt.Sprintf("/api2/json/sdn/vnets/%s", url.PathEscape(vnet))
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("deleting SDN vnet %s: %w", vnet, err)
	}
	return nil
}

// ListSDNSubnets returns all subnets.
func (c *Client) ListSDNSubnets() ([]SDNSubnet, error) {
	ctx := context.Background()
	data, err := c.Get(ctx, "/api2/json/sdn/subnets")
	if err != nil {
		return nil, fmt.Errorf("listing SDN subnets: %w", err)
	}

	var subnets []SDNSubnet
	if err := decodeJSON(data, &subnets); err != nil {
		return nil, fmt.Errorf("decoding SDN subnets: %w", err)
	}
	return subnets, nil
}

// CreateSDNSubnet creates a new subnet.
func (c *Client) CreateSDNSubnet(vnet, subnet, gateway string) error {
	ctx := context.Background()
	body := map[string]string{
		"vnet":    vnet,
		"subnet":  subnet,
		"gateway": gateway,
	}
	_, err := c.Post(ctx, "/api2/json/sdn/subnets", body)
	if err != nil {
		return fmt.Errorf("creating SDN subnet %s on %s: %w", subnet, vnet, err)
	}
	return nil
}

// DeleteSDNSubnet deletes a subnet.
func (c *Client) DeleteSDNSubnet(vnet, subnet string) error {
	ctx := context.Background()
	path := fmt.Sprintf("/api2/json/sdn/subnets/%s/%s",
		url.PathEscape(vnet), url.PathEscape(subnet))
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("deleting SDN subnet %s: %w", subnet, err)
	}
	return nil
}

// ApplySDN applies pending SDN changes.
func (c *Client) ApplySDN() error {
	ctx := context.Background()
	_, err := c.Post(ctx, "/api2/json/sdn", nil)
	if err != nil {
		return fmt.Errorf("applying SDN changes: %w", err)
	}
	return nil
}

// GetSDNStatus returns the current SDN status.
func (c *Client) GetSDNStatus() (json.RawMessage, error) {
	ctx := context.Background()
	return c.Get(ctx, "/api2/json/sdn")
}
