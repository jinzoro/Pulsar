// SPDX-License-Identifier: MIT

package kvm

import (
	"bytes"
	"fmt"
	"os/exec"
	"strconv"
	"strings"
)

// VMOperation provides high-level VM operations using virsh.
type VMOperation struct {
	client *LibvirtClient
}

// NewVMOperation creates a new VM operation handler.
func NewVMOperation(client *LibvirtClient) *VMOperation {
	return &VMOperation{client: client}
}

// ListVMs returns all virtual machines.
func (v *VMOperation) ListVMs() ([]Domain, error) {
	return v.client.ListDomains()
}

// StartVM starts a virtual machine by name or ID.
func (v *VMOperation) StartVM(name string) error {
	domain, err := v.client.GetDomain(name)
	if err != nil {
		return err
	}
	return domain.Start()
}

// StopVM stops a virtual machine by name or ID.
func (v *VMOperation) StopVM(name string, force bool) error {
	domain, err := v.client.GetDomain(name)
	if err != nil {
		return err
	}
	if force {
		return domain.Destroy()
	}
	return domain.Stop()
}

// DestroyVM force-stops and undefines a virtual machine.
func (v *VMOperation) DestroyVM(name string) error {
	domain, err := v.client.GetDomain(name)
	if err != nil {
		return err
	}
	if err := domain.Destroy(); err != nil {
		return fmt.Errorf("force stopping %s: %w", name, err)
	}
	return domain.Undefine()
}

// CreateVM creates a new VM from an XML definition.
func (v *VMOperation) CreateVM(name, xmlPath string) error {
	cmd := exec.Command("virsh", "-c", v.client.URI, "define", xmlPath)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("creating VM %s: %w: %s", name, err, stderr.String())
	}
	return nil
}

// DefineVM defines a VM from XML string.
func (v *VMOperation) DefineVM(name, xml string) error {
	return v.client.DefineDomain(name, xml)
}

// GetVMInfo returns detailed information about a VM.
func (v *VMOperation) GetVMInfo(name string) (*Domain, error) {
	return v.client.GetDomain(name)
}

// SetVMMemory sets the memory for a VM (requires VM to be shut down).
func (v *VMOperation) SetVMMemory(name string, memoryMB int) error {
	cmd := exec.Command("virsh", "-c", v.client.URI, "setmem", name,
		strconv.Itoa(memoryMB*1024), "--config")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("setting memory for %s: %w: %s", name, err, stderr.String())
	}
	return nil
}

// SetVMCPU sets the number of vCPUs for a VM.
func (v *VMOperation) SetVMCPU(name string, vcpus int) error {
	cmd := exec.Command("virsh", "-c", v.client.URI, "setvcpus", name,
		strconv.Itoa(vcpus), "--config")
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("setting vCPUs for %s: %w: %s", name, err, stderr.String())
	}
	return nil
}

// AttachDevice attaches a device to a VM.
func (v *VMOperation) AttachDevice(name, xmlPath string, live bool) error {
	args := []string{"-c", v.client.URI, "attach-device", name, xmlPath}
	if live {
		args = append(args, "--live")
	} else {
		args = append(args, "--config")
	}
	cmd := exec.Command("virsh", args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("attaching device to %s: %w: %s", name, err, stderr.String())
	}
	return nil
}

// DetachDevice detaches a device from a VM.
func (v *VMOperation) DetachDevice(name, xmlPath string, live bool) error {
	args := []string{"-c", v.client.URI, "detach-device", name, xmlPath}
	if live {
		args = append(args, "--live")
	} else {
		args = append(args, "--config")
	}
	cmd := exec.Command("virsh", args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("detaching device from %s: %w: %s", name, err, stderr.String())
	}
	return nil
}

// GetVMXML returns the XML definition of a VM.
func (v *VMOperation) GetVMXML(name string) (string, error) {
	cmd := exec.Command("virsh", "-c", v.client.URI, "dumpxml", name)
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return "", fmt.Errorf("getting XML for %s: %w: %s", name, err, stderr.String())
	}
	return stdout.String(), nil
}

// MigrateVM migrates a VM to another host.
func (v *VMOperation) MigrateVM(name, destURI string, live bool) error {
	args := []string{"-c", v.client.URI, "migrate", "--desturi", destURI}
	if live {
		args = append(args, "--live")
	}
	args = append(args, name)
	cmd := exec.Command("virsh", args...)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("migrating %s to %s: %w: %s", name, destURI, err, stderr.String())
	}
	return nil
}

// ListAutostartVMs returns VMs with autostart enabled.
func (v *VMOperation) ListAutostartVMs() ([]string, error) {
	cmd := exec.Command("virsh", "-c", v.client.URI, "list", "--autostart", "--name")
	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return nil, fmt.Errorf("listing autostart VMs: %w", err)
	}

	var names []string
	lines := strings.Split(strings.TrimSpace(stdout.String()), "\n")
	for _, line := range lines {
		if name := strings.TrimSpace(line); name != "" {
			names = append(names, name)
		}
	}
	return names, nil
}

// SetAutostart sets the autostart flag for a VM.
func (v *VMOperation) SetAutostart(name string, enabled bool) error {
	action := "disable"
	if enabled {
		action = "enable"
	}
	cmd := exec.Command("virsh", "-c", v.client.URI, "autostart", name, action)
	var stderr bytes.Buffer
	cmd.Stderr = &stderr
	if err := cmd.Run(); err != nil {
		return fmt.Errorf("setting autostart for %s: %w", name, err)
	}
	return nil
}
