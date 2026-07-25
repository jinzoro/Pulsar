// SPDX-License-Identifier: MIT
// Copyright (c) proxmox-kvm-swissknife contributors

output "bridge_id" {
  description = "Linux bridge interface ID"
  value       = var.type == "bridge" ? proxmox_virtual_environment_network_linux_bridge.this[0].id : null
}

output "bond_id" {
  description = "Linux bond interface ID"
  value       = var.type == "bond" ? proxmox_virtual_environment_network_linux_bond.this[0].id : null
}

output "vlan_id" {
  description = "Linux VLAN interface ID"
  value       = var.type == "vlan" ? proxmox_virtual_environment_network_linux_vlan.this[0].id : null
}

output "name" {
  description = "Interface name"
  value       = var.name
}

output "type" {
  description = "Network interface type"
  value       = var.type
}

output "address" {
  description = "Configured IP address"
  value       = var.address
}
