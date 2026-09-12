terraform {
  required_version = ">= 1.6.0"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.25"
    }
  }
}

# CLOUDFLARE_API_TOKEN is read from the environment (mise.toml sets it from
# ../.env). It has to be an API token, not the cf CLI's OAuth token: the zone
# rules need permissions OAuth cannot grant. ../scripts/create-api-token.sh
# creates it with the permission groups it needs.
provider "cloudflare" {}
