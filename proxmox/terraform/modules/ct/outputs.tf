// SPDX-License-Identifier: MIT
// Copyright (c) proxmox-kvm-swissknife contributors

output "vmid" {
  description = "Container ID"
  value       = proxmox_virtual_environment_container.this.vm_id
}

output "hostname" {
  description = "Container hostname"
  value       = proxmox_virtual_environment_container.this.description
}

output "status" {
  description = "Container status"
  value       = proxmox_virtual_environment_container.this.status
}

output "node" {
  description = "Proxmox node name"
  value       = proxmox_virtual_environment_container.this.node_name
}

output "network_interface" {
  description = "Network interface name"
  value       = proxmox_virtual_environment_container.this.network_interface
}
