// SPDX-License-Identifier: MIT
// Copyright (c) pulsar contributors

module "vms" {
  source   = "./modules/vm"
  for_each = var.vms

  target_node    = var.pm_node
  name           = each.value.name
  vmid           = lookup(each.value, "vmid", 0)
  cpu_cores      = lookup(each.value, "cpu_cores", 2)
  cpu_sockets    = lookup(each.value, "cpu_sockets", 1)
  memory         = lookup(each.value, "memory", 2048)
  disk_size      = lookup(each.value, "disk_size", 32)
  disk_storage   = lookup(each.value, "disk_storage", "local-lvm")
  template_id    = each.value.template_id
  clone_full     = lookup(each.value, "clone_full", true)
  ci_user        = lookup(each.value, "ci_user", "")
  ci_password    = lookup(each.value, "ci_password", "")
  ci_ssh_keys    = lookup(each.value, "ci_ssh_keys", "")
  ci_ip          = lookup(each.value, "ci_ip", "")
  ci_gateway     = lookup(each.value, "ci_gateway", "")
  ci_nameserver  = lookup(each.value, "ci_nameserver", "")
  ci_domain      = lookup(each.value, "ci_domain", "")
  network_bridge = lookup(each.value, "network_bridge", "vmbr0")
  network_model  = lookup(each.value, "network_model", "virtio")
  tags           = lookup(each.value, "tags", "")
  description    = lookup(each.value, "description", "")
  agent          = lookup(each.value, "agent", true)
  bios           = lookup(each.value, "bios", "seabios")
  machine_type   = lookup(each.value, "machine_type", "")
}

module "containers" {
  source   = "./modules/ct"
  for_each = var.containers

  target_node      = var.pm_node
  vmid             = lookup(each.value, "vmid", 0)
  hostname         = each.value.hostname
  ostemplate       = each.value.ostemplate
  os_type          = lookup(each.value, "os_type", "ubuntu")
  password         = lookup(each.value, "password", "")
  ssh_keys         = lookup(each.value, "ssh_keys", "")
  unprivileged     = lookup(each.value, "unprivileged", true)
  cpu_cores        = lookup(each.value, "cpu_cores", 1)
  memory           = lookup(each.value, "memory", 512)
  swap             = lookup(each.value, "swap", 512)
  rootfs_size      = lookup(each.value, "rootfs_size", "8")
  rootfs_storage   = lookup(each.value, "rootfs_storage", "local-lvm")
  network_bridge   = lookup(each.value, "network_bridge", "vmbr0")
  ip_address       = lookup(each.value, "ip_address", "")
  ip_gateway       = lookup(each.value, "ip_gateway", "")
  dns_nameserver   = lookup(each.value, "dns_nameserver", "")
  dns_domain       = lookup(each.value, "dns_domain", "")
}

module "networks" {
  source   = "./modules/network"
  for_each = var.networks

  target_node    = var.pm_node
  type           = lookup(each.value, "type", "bridge")
  name           = each.value.name
  comment        = lookup(each.value, "comment", "")
  address        = lookup(each.value, "address", "")
  cidr           = lookup(each.value, "cidr", "")
  gateway        = lookup(each.value, "gateway", "")
  vlan_id        = lookup(each.value, "vlan_id", null)
  vlan_interface = lookup(each.value, "vlan_interface", "")
  bridge_ports   = lookup(each.value, "bridge_ports", "")
  bridge_stp     = lookup(each.value, "bridge_stp", false)
  bridge_fd      = lookup(each.value, "bridge_fd", 0)
  bond_mode      = lookup(each.value, "bond_mode", "balance-rr")
  bond_members   = lookup(each.value, "bond_members", [])
}

module "pools" {
  source   = "./modules/pool"
  for_each = var.pools

  pool_id = each.value.pool_id
  comment = lookup(each.value, "comment", "")
  members = lookup(each.value, "members", [])
}
