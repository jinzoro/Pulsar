// SPDX-License-Identifier: MIT

package kvm

import (
	"bytes"
	"fmt"
	"os/exec"
	"strings"
)

// SnapshotOperation provides snapshot management using virsh.
type SnapshotOperation struct {
	client *LibvirtClient
}

// NewSnapshotOperation creates a new snapshot operation handler.
func NewSnapshotOperation(client *LibvirtClient) *SnapshotOperation {
	return &SnapshotOperation{client: client}
}

// Create creates a snapshot for a domain.
func (s *SnapshotOperation) Create(domain, name, description string) error {
	d, err := s.client.GetDomain(domain)
	if err != nil {
		return err
	}
	return d.CreateSnapshot(name, description)
}

// List returns all snapshots for a domain.
func (s *SnapshotOperation) List(domain string) ([]DomainSnapshot, error) {
	d, err := s.client.GetDomain(domain)
	if err != nil {
		return nil, err
	}
	return d.ListSnapshots()
}

// Revert reverts a domain to a snapshot.
func (s *SnapshotOperation) Revert(domain, name string) error {
	d, err := s.client.GetDomain(domain)
	if err != nil {
		return err
	}
	return d.RevertSnapshot(name)
}

// Delete deletes a snapshot from a domain.
func (s *SnapshotOperation) Delete(domain, name string) error {
	d, err := s.client.GetDomain(domain)
	if err != nil {
		return err
	}
	return d.DeleteSnapshot(name)
}

// GetInfo returns information about a specific snapshot.
func (s *SnapshotOperation) GetInfo(domain, name string) (*DomainSnapshot, error) {
	cmd := exec.Command("virsh", "-c", s.client.URI, "snapshot-info", domain, name)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("getting snapshot info for %s/%s: %w", domain, name, err)
	}

	snap := &DomainSnapshot{
		Name: name,
	}

	lines := strings.Split(stdout.String(), "\n")
	for _, line := range lines {
		parts := strings.SplitN(strings.TrimSpace(line), ":", 2)
		if len(parts) == 2 {
			key := strings.TrimSpace(parts[0])
			value := strings.TrimSpace(parts[1])
			switch key {
			case "Name":
				snap.Name = value
			case "State":
				snap.State = value
			case "Parent":
				snap.Parent = value
			}
		}
	}

	return snap, nil
}

// ListDomains returns all domains with snapshot capability.
func (s *SnapshotOperation) ListDomains() ([]string, error) {
	cmd := exec.Command("virsh", "-c", s.client.URI, "list", "--all", "--name")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("listing domains: %w", err)
	}

	var domains []string
	lines := strings.Split(strings.TrimSpace(stdout.String()), "\n")
	for _, line := range lines {
		if name := strings.TrimSpace(line); name != "" {
			domains = append(domains, name)
		}
	}
	return domains, nil
}

// RevertToLatest reverts a domain to its latest snapshot.
func (s *SnapshotOperation) RevertToLatest(domain string) error {
	d, err := s.client.GetDomain(domain)
	if err != nil {
		return err
	}

	snaps, err := d.ListSnapshots()
	if err != nil {
		return err
	}

	if len(snaps) == 0 {
		return fmt.Errorf("no snapshots found for domain %s", domain)
	}

	latest := snaps[len(snaps)-1]
	return d.RevertSnapshot(latest.Name)
}

// Count returns the number of snapshots for a domain.
func (s *SnapshotOperation) Count(domain string) (int, error) {
	snaps, err := s.List(domain)
	if err != nil {
		return 0, err
	}
	return len(snaps), nil
}
