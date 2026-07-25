// SPDX-License-Identifier: MIT
// Copyright (c) pulsar contributors

resource "proxmox_virtual_environment_container" "this" {
  node_name = var.target_node
  vm_id     = var.vmid > 0 ? var.vmid : null
  description = var.description

  unprivileged = var.unprivileged

  cpu {
    cores = var.cpu_cores
  }

  memory {
    dedicated = var.memory
    swap      = var.swap
  }

  disk {
    datastore_id = var.rootfs_storage
    size         = var.rootfs_size
  }

  dynamic "mount_point" {
    for_each = var.mount_point != "" ? [var.mount_point] : []
    content {
      datastore_id = split(":", mount_point.value)[0]
      path         = split(":", mount_point.value)[1]
      size         = length(split(":", mount_point.value)) > 2 ? split(":", mount_point.value)[2] : "8"
    }
  }

  network_interface {
    bridge  = var.network_bridge
    model   = "virtio"
    enabled = true
  }

  operating_system {
    template_file_id = var.ostemplate
    type             = var.os_type
  }

  features {
    nesting = var.features_nesting
    fuse    = var.features_fuse
    keyctl  = var.features_keyctl
  }

  initialization {
    hostname = var.hostname

    user_account {
      password = var.password
      keys     = var.ssh_keys != "" ? [var.ssh_keys] : []
    }

    dynamic "ip_config" {
      for_each = var.ip_address != "" ? [1] : []
      content {
        ipv4 {
          address = var.ip_address
          gateway = var.ip_gateway
        }
      }
    }

    dns {
      servers = var.dns_nameserver != "" ? [var.dns_nameserver] : []
      domain  = var.dns_domain
    }
  }

  lifecycle {
    ignore_changes = [
      description,
    ]
  }
}
