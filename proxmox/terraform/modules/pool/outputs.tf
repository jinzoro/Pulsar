// SPDX-License-Identifier: MIT
// Copyright (c) pulsar contributors

output "pool_id" {
  description = "Pool ID"
  value       = proxmox_virtual_environment_pool.this.pool_id
}

output "comment" {
  description = "Pool comment"
  value       = proxmox_virtual_environment_pool.this.comment
}

output "member_ids" {
  description = "List of member VM/container IDs"
  value       = var.members
}
