// SPDX-License-Identifier: MIT
// Copyright (c) pulsar contributors

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
  #   key            = "pulsar/terraform.tfstate"
  #   region         = "us-east-1"
  #   dynamodb_table = "terraform-locks"
  #   encrypt        = true
  # }
}
