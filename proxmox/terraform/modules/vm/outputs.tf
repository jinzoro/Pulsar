// SPDX-License-Identifier: MIT
// Copyright (c) pulsar contributors

output "vmid" {
  description = "Proxmox VM ID"
  value       = proxmox_virtual_environment_vm.this.vm_id
}

output "name" {
  description = "VM name"
  value       = proxmox_virtual_environment_vm.this.name
}

output "status" {
  description = "VM status"
  value       = proxmox_virtual_environment_vm.this.status
}

output "ip_address" {
  description = "VM IP address from guest agent"
  value       = proxmox_virtual_environment_vm.this.ipv4_addresses
}

output "node" {
  description = "Proxmox node name"
  value       = proxmox_virtual_environment_vm.this.node_name
}
