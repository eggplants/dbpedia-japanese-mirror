terraform {
  required_version = ">= 1.6.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.24"
    }
  }
}

# CLOUDFLARE_API_TOKEN is read from the environment. The token needs:
#   Account : Workers Scripts:Edit, Workers R2 Storage:Edit (optional),
#             Containers:Edit (called "Cloudflare Containers" in the UI)
#   Zone    : Zone:Read, Zone Settings:Edit, Cache Rules:Edit, Firewall Services:Edit
provider "cloudflare" {}
