// SPDX-License-Identifier: MIT
// Copyright (c) proxmox-kvm-swissknife contributors

terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.68.0"
    }
  }

  required_version = ">= 1.5.0"
}

provider "proxmox" {
  endpoint = var.pm_api_url
  api_token = "${var.pm_api_token_id}=${var.pm_api_token_secret}"

  insecure = var.pm_api_tls_insecure

  ssh {
    agent    = false
    username = var.pm_ssh_user
    password = var.pm_ssh_password
  }
}
