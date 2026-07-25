// SPDX-License-Identifier: MIT

package kvm

import (
	"bytes"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

// LibvirtClient wraps libvirt/virsh commands.
type LibvirtClient struct {
	URI    string
	closed bool
}

// Domain represents a libvirt domain.
type Domain struct {
	ID     int
	Name   string
	State  string
	Memory int64
	UUID   string
}

// Network represents a libvirt virtual network.
type Network struct {
	Name   string
	State  string
	Bridge string
	UUID   string
}

// DomainSnapshot represents a domain snapshot.
type DomainSnapshot struct {
	Name    string
	State   string
	Created string
	Parent  string
}

// NewLibvirtClient creates a new libvirt client.
func NewLibvirtClient(uri string) (*LibvirtClient, error) {
	if uri == "" {
		uri = "qemu:///system"
	}

	c := &LibvirtClient{URI: uri}

	if err := c.ping(); err != nil {
		return nil, fmt.Errorf("connecting to libvirt at %s: %w", uri, err)
	}

	return c, nil
}

// Close closes the libvirt client.
func (c *LibvirtClient) Close() {
	c.closed = true
}

func (c *LibvirtClient) ping() error {
	_, err := c.runVirsh("list", "--all")
	return err
}

func (c *LibvirtClient) runVirsh(args ...string) (string, error) {
	fullArgs := append([]string{"-c", c.URI}, args...)
	cmd := exec.Command("virsh", fullArgs...)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("virsh %s: %w: %s", strings.Join(args, " "), err, stderr.String())
	}

	return stdout.String(), nil
}

// ListDomains returns all domains (running and stopped).
func (c *LibvirtClient) ListDomains() ([]Domain, error) {
	output, err := c.runVirsh("list", "--all", "--name")
	if err != nil {
		return nil, fmt.Errorf("listing domains: %w", err)
	}

	var domains []Domain
	lines := strings.Split(strings.TrimSpace(output), "\n")

	for _, line := range lines {
		name := strings.TrimSpace(line)
		if name == "" {
			continue
		}

		domain, err := c.GetDomain(name)
		if err != nil {
			continue
		}
		domains = append(domains, *domain)
	}

	return domains, nil
}

// GetDomain returns a domain by name or ID.
func (c *LibvirtClient) GetDomain(nameOrID string) (*Domain, error) {
	output, err := c.runVirsh("dominfo", nameOrID)
	if err != nil {
		return nil, fmt.Errorf("getting domain info for %s: %w", nameOrID, err)
	}

	domain := &Domain{
		Name: nameOrID,
	}

	lines := strings.Split(output, "\n")
	for _, line := range lines {
		line = strings.TrimSpace(line)
		parts := strings.SplitN(line, ":", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		switch key {
		case "Id":
			fmt.Sscanf(value, "%d", &domain.ID)
		case "Name":
			domain.Name = value
		case "State":
			domain.State = value
		case "UUID":
			domain.UUID = value
		}
	}

	return domain, nil
}

// Start starts a domain.
func (d *Domain) Start() error {
	return runDomainCmd("start", d.Name)
}

// Stop stops a domain (forceful).
func (d *Domain) Stop() error {
	return runDomainCmd("shutdown", d.Name)
}

// Destroy force-stops a domain.
func (d *Domain) Destroy() error {
	return runDomainCmd("destroy", d.Name)
}

// Shutdown gracefully shuts down a domain.
func (d *Domain) Shutdown() error {
	return runDomainCmd("shutdown", d.Name)
}

// Undefine removes a domain definition.
func (d *Domain) Undefine() error {
	return runDomainCmd("undefine", d.Name)
}

// ListSnapshots returns all snapshots for a domain.
func (d *Domain) ListSnapshots() ([]DomainSnapshot, error) {
	cmd := exec.Command("virsh", "snapshot-list", d.Name, "--name")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("listing snapshots for %s: %w", d.Name, err)
	}

	var snapshots []DomainSnapshot
	lines := strings.Split(strings.TrimSpace(stdout.String()), "\n")
	for _, line := range lines {
		name := strings.TrimSpace(line)
		if name == "" {
			continue
		}
		snapshots = append(snapshots, DomainSnapshot{
			Name:  name,
			State: "shutoff",
		})
	}

	return snapshots, nil
}

// CreateSnapshot creates a snapshot of the domain.
func (d *Domain) CreateSnapshot(name, description string) error {
	args := []string{"snapshot-create", d.Name, "--name", name}
	if description != "" {
		args = append(args, "--description", description)
	}
	return runDomainCmd(args[0], args[1:]...)
}

// RevertSnapshot reverts a domain to a snapshot.
func (d *Domain) RevertSnapshot(name string) error {
	return runDomainCmd("snapshot-revert", d.Name, name)
}

// DeleteSnapshot deletes a snapshot.
func (d *Domain) DeleteSnapshot(name string) error {
	return runDomainCmd("snapshot-delete", d.Name, name)
}

// Export exports a domain to a file.
func (d *Domain) Export(path, format string) error {
	if format == "" {
		format = "qcow2"
	}
	cmd := exec.Command("virsh", "dumpxml", d.Name)
	output, err := cmd.Output()
	if err != nil {
		return fmt.Errorf("exporting domain %s: %w", d.Name, err)
	}
	return writeFile(path, output)
}

// DefineDomain defines a domain from XML.
func (c *LibvirtClient) DefineDomain(name, xml string) error {
	cmd := exec.Command("virsh", "-c", c.URI, "define", "-")
	cmd.Stdin = strings.NewReader(xml)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("defining domain %s: %w: %s", name, err, stderr.String())
	}
	return nil
}

// ListNetworks returns all virtual networks.
func (c *LibvirtClient) ListNetworks() ([]Network, error) {
	output, err := c.runVirsh("net-list", "--all", "--name")
	if err != nil {
		return nil, fmt.Errorf("listing networks: %w", err)
	}

	var networks []Network
	lines := strings.Split(strings.TrimSpace(output), "\n")
	for _, line := range lines {
		name := strings.TrimSpace(line)
		if name == "" {
			continue
		}

		stateOutput, _ := c.runVirsh("net-info", name)
		net := Network{Name: name}
		infoLines := strings.Split(stateOutput, "\n")
		for _, infoLine := range infoLines {
			parts := strings.SplitN(strings.TrimSpace(infoLine), ":", 2)
			if len(parts) == 2 {
				switch strings.TrimSpace(parts[0]) {
				case "Active":
					if strings.TrimSpace(parts[1]) == "yes" {
						net.State = "active"
					} else {
						net.State = "inactive"
					}
				}
			}
		}

		bridgeOutput, err := c.runVirsh("net-info", name)
		if err == nil {
			for _, bl := range strings.Split(bridgeOutput, "\n") {
				parts := strings.SplitN(strings.TrimSpace(bl), ":", 2)
				if len(parts) == 2 && strings.TrimSpace(parts[0]) == "Bridge" {
					net.Bridge = strings.TrimSpace(parts[1])
				}
			}
		}

		networks = append(networks, net)
	}

	return networks, nil
}

// StartNetwork starts a virtual network.
func (c *LibvirtClient) StartNetwork(name string) error {
	_, err := c.runVirsh("net-start", name)
	if err != nil {
		return fmt.Errorf("starting network %s: %w", name, err)
	}
	return nil
}

// StopNetwork stops a virtual network.
func (c *LibvirtClient) StopNetwork(name string) error {
	_, err := c.runVirsh("net-destroy", name)
	if err != nil {
		return fmt.Errorf("stopping network %s: %w", name, err)
	}
	return nil
}

// DeleteNetwork deletes a virtual network.
func (c *LibvirtClient) DeleteNetwork(name string) error {
	_, err := c.runVirsh("net-undefine", name)
	if err != nil {
		return fmt.Errorf("deleting network %s: %w", name, err)
	}
	return nil
}

// CreateNetwork creates a virtual network from XML.
func (c *LibvirtClient) CreateNetwork(name, xml string) error {
	cmd := exec.Command("virsh", "-c", c.URI, "net-define", "-")
	cmd.Stdin = strings.NewReader(xml)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("creating network %s: %w: %s", name, err, stderr.String())
	}
	return nil
}

func runDomainCmd(args ...string) error {
	cmd := exec.Command("virsh", args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return fmt.Errorf("virsh %s: %w: %s", strings.Join(args, " "), err, stderr.String())
	}
	return nil
}

func writeFile(path string, data []byte) error {
	return os.WriteFile(path, data, 0644)
}
