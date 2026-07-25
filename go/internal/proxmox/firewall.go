// SPDX-License-Identifier: MIT

package proxmox

import (
	"context"
	"fmt"
	"net/url"
)

// FirewallRule represents a firewall rule.
type FirewallRule struct {
	Pos     int    `json:"pos"`
	Type    string `json:"type,omitempty"`
	Action  string `json:"action"`
	Proto   string `json:"proto,omitempty"`
	Dest    string `json:"dest,omitempty"`
	Source  string `json:"source,omitempty"`
	DPort   string `json:"dport,omitempty"`
	SPort   string `json:"sport,omitempty"`
	Macro   string `json:"macro,omitempty"`
	Enable  int    `json:"enable,omitempty"`
	Log     string `json:"log,omitempty"`
	Comment string `json:"comment,omitempty"`
}

// IPSec represents an IP set.
type IPSec struct {
	Name    string `json:"name"`
	CIDR    string `json:"cidr,omitempty"`
}

// FirewallCreateRequest represents a request to add a firewall rule.
type FirewallCreateRequest struct {
	Action  string `json:"action,omitempty"`
	Proto   string `json:"proto,omitempty"`
	Dest    string `json:"dest,omitempty"`
	Source  string `json:"source,omitempty"`
	DPort   string `json:"dport,omitempty"`
	SPort   string `json:"sport,omitempty"`
	Macro   string `json:"macro,omitempty"`
	Enable  int    `json:"enable,omitempty"`
	Log     string `json:"log,omitempty"`
	Comment string `json:"comment,omitempty"`
}

// ListFirewallRules returns all firewall rules for a host.
func (c *Client) ListFirewallRules() ([]FirewallRule, error) {
	return c.ListHostFirewallRules("localhost")
}

// ListHostFirewallRules returns all firewall rules for a specific node.
func (c *Client) ListHostFirewallRules(node string) ([]FirewallRule, error) {
	ctx := context.Background()
	path := fmt.Sprintf("%s/firewall/rules", c.nodePath(node, ""))
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("listing firewall rules: %w", err)
	}

	var rules []FirewallRule
	if err := decodeJSON(data, &rules); err != nil {
		return nil, fmt.Errorf("decoding firewall rules: %w", err)
	}
	return rules, nil
}

// ListVMFirewallRules returns firewall rules for a VM.
func (c *Client) ListVMFirewallRules(node, vmid string) ([]FirewallRule, error) {
	ctx := context.Background()
	path := fmt.Sprintf("%s/qemu/%s/firewall/rules", c.nodePath(node, ""), vmid)
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("listing VM firewall rules: %w", err)
	}

	var rules []FirewallRule
	if err := decodeJSON(data, &rules); err != nil {
		return nil, fmt.Errorf("decoding VM firewall rules: %w", err)
	}
	return rules, nil
}

// AddFirewallRule adds a firewall rule.
func (c *Client) AddFirewallRule(node string, req FirewallCreateRequest) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/firewall/rules", c.nodePath(node, ""))
	_, err := c.Post(ctx, path, req)
	if err != nil {
		return fmt.Errorf("adding firewall rule: %w", err)
	}
	return nil
}

// AddVMFirewallRule adds a firewall rule to a VM.
func (c *Client) AddVMFirewallRule(node, vmid string, req FirewallCreateRequest) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/qemu/%s/firewall/rules", c.nodePath(node, ""), vmid)
	_, err := c.Post(ctx, path, req)
	if err != nil {
		return fmt.Errorf("adding VM firewall rule: %w", err)
	}
	return nil
}

// DeleteFirewallRule deletes a firewall rule by position.
func (c *Client) DeleteFirewallRule(node string, pos int) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/firewall/rules/%d", c.nodePath(node, ""), pos)
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("deleting firewall rule at pos %d: %w", pos, err)
	}
	return nil
}

// DeleteVMFirewallRule deletes a firewall rule from a VM.
func (c *Client) DeleteVMFirewallRule(node, vmid string, pos int) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/qemu/%s/firewall/rules/%d", c.nodePath(node, ""), vmid, pos)
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("deleting VM firewall rule at pos %d: %w", pos, err)
	}
	return nil
}

// EnableFirewall enables the firewall on a node.
func (c *Client) EnableFirewall(node string) error {
	return c.setFirewallState(node, 1)
}

// DisableFirewall disables the firewall on a node.
func (c *Client) DisableFirewall(node string) error {
	return c.setFirewallState(node, 0)
}

func (c *Client) setFirewallState(node string, enable int) error {
	ctx := context.Background()
	body := map[string]int{
		"enable": enable,
	}
	path := fmt.Sprintf("%s/firewall/options", c.nodePath(node, ""))
	_, err := c.Put(ctx, path, body)
	if err != nil {
		state := "enable"
		if enable == 0 {
			state = "disable"
		}
		return fmt.Errorf("%sing firewall on %s: %w", state, node, err)
	}
	return nil
}

// ListIPSets returns all IP sets.
func (c *Client) ListIPSets(node string) ([]IPSet, error) {
	ctx := context.Background()
	path := fmt.Sprintf("%s/firewall/ipset", c.nodePath(node, ""))
	data, err := c.Get(ctx, path)
	if err != nil {
		return nil, fmt.Errorf("listing IP sets: %w", err)
	}

	var ipsSets []IPSet
	if err := decodeJSON(data, &ipsSets); err != nil {
		return nil, fmt.Errorf("decoding IP sets: %w", err)
	}
	return ipsSets, nil
}

// IPSet represents an IP set.
type IPSet struct {
	Name    string `json:"name"`
	Comment string `json:"comment,omitempty"`
}

// AddToIPSet adds an IP/CIDR to an IP set.
func (c *Client) AddToIPSet(node,setName, cidr, comment string) error {
	ctx := context.Background()
	body := map[string]string{
		"cidr":    cidr,
		"comment": comment,
	}
	path := fmt.Sprintf("%s/firewall/ipset/%s", c.nodePath(node, ""), url.PathEscape(setName))
	_, err := c.Post(ctx, path, body)
	if err != nil {
		return fmt.Errorf("adding %s to IP set %s: %w", cidr, setName, err)
	}
	return nil
}

// RemoveFromIPSet removes an IP/CIDR from an IP set.
func (c *Client) RemoveFromIPSet(node, setName, cidr string) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/firewall/ipset/%s/%s",
		c.nodePath(node, ""), url.PathEscape(setName), url.PathEscape(cidr))
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("removing %s from IP set %s: %w", cidr, setName, err)
	}
	return nil
}

// CreateIPSet creates a new IP set.
func (c *Client) CreateIPSet(node, name, comment string) error {
	ctx := context.Background()
	body := map[string]string{
		"name":    name,
		"comment": comment,
	}
	path := fmt.Sprintf("%s/firewall/ipset", c.nodePath(node, ""))
	_, err := c.Post(ctx, path, body)
	if err != nil {
		return fmt.Errorf("creating IP set %s: %w", name, err)
	}
	return nil
}

// DeleteIPSet deletes an IP set.
func (c *Client) DeleteIPSet(node, name string) error {
	ctx := context.Background()
	path := fmt.Sprintf("%s/firewall/ipset/%s", c.nodePath(node, ""), url.PathEscape(name))
	_, err := c.Delete(ctx, path)
	if err != nil {
		return fmt.Errorf("deleting IP set %s: %w", name, err)
	}
	return nil
}
