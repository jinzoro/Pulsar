// SPDX-License-Identifier: MIT
// Copyright (c) pulsar contributors

resource "proxmox_virtual_environment_vm" "this" {
  node_name = var.target_node
  vm_id     = var.vmid > 0 ? var.vmid : null
  name      = var.name
  description = var.description

  tags = var.tags != "" ? var.tags : null

  agent {
    enabled = var.agent
  }

  bios = var.bios

  machine_type = var.machine_type != "" ? var.machine_type : null

  cpu {
    cores  = var.cpu_cores
    sockets = var.cpu_sockets
    type   = "host"
  }

  memory {
    dedicated = var.memory
  }

  clone {
    datastore_id = var.disk_storage
    vm_id        = var.template_id
    full         = var.clone_full
    retries      = 3
  }

  disk {
    datastore_id = var.disk_storage
    interface    = "scsi0"
    size         = var.disk_size
    file_format  = "raw"
    iothread     = true
    ssd          = true
  }

  network_device {
    bridge  = var.network_bridge
    model   = var.network_model
    firewall = false
  }

  operating_system {
    type = "l26"
  }

  initialization {
    datastore_id = var.disk_storage

    dynamic "user_account" {
      for_each = var.ci_user != "" ? [1] : []
      content {
        username = var.ci_user
        password = var.ci_password
        keys     = var.ci_ssh_keys != "" ? [var.ci_ssh_keys] : []
      }
    }

    dynamic "ip_config" {
      for_each = var.ci_ip != "" ? [1] : []
      content {
        ipv4 {
          address = var.ci_ip
          gateway = var.ci_gateway
        }
      }
    }

    dns {
      servers = var.ci_nameserver != "" ? [var.ci_nameserver] : []
      domain  = var.ci_domain
    }
  }

  features {
    enabled_virtiofs = false
    fuse             = false
    nesting          = false
  }

  lifecycle {
    ignore_changes = [
      tags,
      description,
    ]
  }
}
