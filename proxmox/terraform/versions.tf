// SPDX-License-Identifier: MIT
// Copyright (c) proxmox-kvm-swissknife contributors

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = ">= 0.68.0"
    }
  }

  # backend "s3" {
  #   bucket         = "terraform-state"
  #   key            = "proxmox-kvm-swissknife/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}
