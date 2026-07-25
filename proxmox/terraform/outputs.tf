// SPDX-License-Identifier: MIT
// Copyright (c) proxmox-kvm-swissknife contributors

output "vm_details" {
  description = "Created VM details"
  value = {
    for k, v in module.vms : k => {
      vmid      = v.vmid
      name      = v.name
      status    = v.status
      ip_address = v.ip_address
      node      = v.node
    }
  }
}

output "container_details" {
  description = "Created container details"
  value = {
    for k, v in module.containers : k => {
      vmid     = v.vmid
      status   = v.status
      node     = v.node
    }
  }
}

output "network_details" {
  description = "Created network interface details"
  value = {
    for k, v in module.networks : k => {
      name    = v.name
      type    = v.type
      address = v.address
    }
  }
}

output "pool_details" {
  description = "Created pool details"
  value = {
    for k, v in module.pools : k => {
      pool_id    = v.pool_id
      comment    = v.comment
      member_ids = v.member_ids
    }
  }
}
