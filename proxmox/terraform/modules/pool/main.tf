// SPDX-License-Identifier: MIT
// Copyright (c) proxmox-kvm-swissknife contributors

resource "proxmox_virtual_environment_pool" "this" {
  pool_id = var.pool_id
  comment = var.comment

  dynamic "members" {
    for_each = var.members
    content {
      vm_id = members.value
    }
  }
}
