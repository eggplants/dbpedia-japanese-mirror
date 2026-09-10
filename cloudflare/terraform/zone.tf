# egpl.dev is already a zone in the Cloudflare account and its nameservers point
# at Cloudflare, so this looks the zone up rather than creating it. `dig NS
# egpl.dev` answering with *.ns.cloudflare.com is what "already there" means.
#
# manage_zone = true is for the other case: adding a domain to the account for
# the first time. It creates the zone and reports the nameservers to set at the
# registrar in the `name_servers` output. Registrar and DNS stay separate
# concerns — the domain does not have to be registered with Cloudflare, only
# delegated to it.
#
# There is no third path on a Workers Paid plan: a CNAME (partial) setup, which
# would leave DNS elsewhere, needs Business, and subdomain zones are Enterprise.

resource "cloudflare_zone" "this" {
  count = var.manage_zone ? 1 : 0

  account = {
    id = var.account_id
  }
  name = var.zone_name
  type = "full"
}

# Looked up by name so the zone ID does not have to be copied out of the
# dashboard. Set zone_id explicitly to skip the lookup.
data "cloudflare_zone" "this" {
  count = !var.manage_zone && var.zone_id == "" ? 1 : 0

  filter = {
    account = {
      id = var.account_id
    }
    name = var.zone_name
  }
}

locals {
  zone_id = var.manage_zone ? one(cloudflare_zone.this[*].id) : (
    var.zone_id != "" ? var.zone_id : one(data.cloudflare_zone.this[*].id)
  )
}
