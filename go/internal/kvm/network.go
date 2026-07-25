// SPDX-License-Identifier: MIT

package kvm

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os/exec"
	"strings"
)

// NetworkOperation provides network management using virsh.
type NetworkOperation struct {
	client *LibvirtClient
}

// NewNetworkOperation creates a new network operation handler.
func NewNetworkOperation(client *LibvirtClient) *NetworkOperation {
	return &NetworkOperation{client: client}
}

// List returns all virtual networks.
func (n *NetworkOperation) List() ([]Network, error) {
	return n.client.ListNetworks()
}

// Create creates a virtual network from XML.
func (n *NetworkOperation) Create(name, xml string) error {
	return n.client.CreateNetwork(name, xml)
}

// Delete deletes a virtual network.
func (n *NetworkOperation) Delete(name string) error {
	return n.client.DeleteNetwork(name)
}

// Start starts a virtual network.
func (n *NetworkOperation) Start(name string) error {
	return n.client.StartNetwork(name)
}

// Stop stops a virtual network.
func (n *NetworkOperation) Stop(name string) error {
	return n.client.StopNetwork(name)
}

// GetInfo returns information about a virtual network.
func (n *NetworkOperation) GetInfo(name string) (*Network, error) {
	output, err := n.client.runVirsh("net-info", name)
	if err != nil {
		return nil, fmt.Errorf("getting network info for %s: %w", name, err)
	}

	net := &Network{Name: name}
	lines := strings.Split(output, "\n")
	for _, line := range lines {
		parts := strings.SplitN(strings.TrimSpace(line), ":", 2)
		if len(parts) == 2 {
			key := strings.TrimSpace(parts[0])
			value := strings.TrimSpace(parts[1])
			switch key {
			case "Active":
				if value == "yes" {
					net.State = "active"
				} else {
					net.State = "inactive"
				}
			case "Bridge":
				net.Bridge = value
			}
		}
	}
	return net, nil
}

// GetXML returns the XML definition of a virtual network.
func (n *NetworkOperation) GetXML(name string) (string, error) {
	cmd := exec.Command("virsh", "-c", n.client.URI, "net-dumpxml", name)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("getting XML for network %s: %w: %s", name, err, stderr.String())
	}
	return stdout.String(), nil
}

// Define defines a virtual network from XML.
func (n *NetworkOperation) Define(xml string) error {
	cmd := exec.Command("virsh", "-c", n.client.URI, "net-define", "-")
	cmd.Stdin = strings.NewReader(xml)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("defining network: %w: %s", err, stderr.String())
	}
	return nil
}

// Undefine undefines a virtual network.
func (n *NetworkOperation) Undefine(name string) error {
	cmd := exec.Command("virsh", "-c", n.client.URI, "net-undefine", name)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("undefining network %s: %w: %s", name, err, stderr.String())
	}
	return nil
}

// IsAlive checks if a virtual network is active.
func (n *NetworkOperation) IsAlive(name string) bool {
	cmd := exec.Command("virsh", "-c", n.client.URI, "net-active", name)
	return cmd.Run() == nil
}

// ListDHCPLeases returns DHCP leases for a network.
func (n *NetworkOperation) ListDHCPLeases(name string) ([]map[string]interface{}, error) {
	cmd := exec.Command("virsh", "-c", n.client.URI, "net-dhcp-leases", name, "--json")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("listing DHCP leases for %s: %w", name, err)
	}

	var leases []map[string]interface{}
	if err := json.Unmarshal(stdout.Bytes(), &leases); err != nil {
		return nil, fmt.Errorf("parsing DHCP leases: %w", err)
	}
	return leases, nil
}

// CreateBridge creates a Linux bridge using ip commands.
func CreateBridge(name, subnet string) error {
	cmd := exec.Command("ip", "link", "add", name, "type", "bridge")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("creating bridge %s: %w", name, err)
	}

	if subnet != "" {
		cmd = exec.Command("ip", "addr", "add", subnet, "dev", name)
		cmd.Stderr = &stderr
		if err := cmd.Run(); err != nil {
			return fmt.Errorf("assigning address to bridge %s: %w", name, err)
		}
	}

	cmd = exec.Command("ip", "link", "set", name, "up")
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("bringing up bridge %s: %w", name, err)
	}

	return nil
}

// ListHostInterfaces lists host network interfaces.
func ListHostInterfaces() ([]string, error) {
	cmd := exec.Command("ip", "-o", "link", "show", "up")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("listing host interfaces: %w", err)
	}

	var ifaces []string
	lines := strings.Split(stdout.String(), "\n")
	for _, line := range lines {
		if strings.Contains(line, ":") {
			parts := strings.SplitN(line, ":", 2)
			if len(parts) == 2 {
				name := strings.TrimSpace(parts[1])
				name = strings.Split(name, "@")[0]
				if name != "" && name != "lo" {
					ifaces = append(ifaces, name)
				}
			}
		}
	}
	return ifaces, nil
}
