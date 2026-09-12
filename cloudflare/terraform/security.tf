# Zone-level rules.
#
# Note what is deliberately absent: Bot Fight Mode and any browser challenge on
# the endpoint itself. Every legitimate SPARQL client — curl, SPARQLWrapper,
# rdflib, Comunica — is a non-browser client by definition, so a JavaScript
# challenge does not separate abuse from use here, it just breaks the endpoint.
# Abuse is handled by cost: the rate limits below and the per-query buckets in
# the Worker.
#
# A ruleset resource owns its whole phase on the zone. If something else already
# manages these phases, set enable_zone_rules = false and fold these rules into
# whatever does.

locals {
  on_endpoint = "http.host eq \"${var.hostname}\""
}

# Without this, a request for /./sparql, /%2e/sparql or /a/../sparql reaches the
# rules below with the path spelled that way, while the Worker's URL parser
# collapses all of them to /sparql — so a path-matching rule could be sidestepped
# by a request that still gets served. "Normalize incoming URLs" is on by default
# and removes dot segments before the WAF, rate limiting and Workers see the
# request; pinning it here means the deployment does not quietly depend on a zone
# setting nobody set. The Worker routes on the raw path as well, so both layers
# hold on their own.
resource "cloudflare_url_normalization_settings" "this" {
  count = var.enable_zone_rules ? 1 : 0

  zone_id = local.zone_id
  type    = "rfc3986"
  scope   = "incoming"
}

resource "cloudflare_ruleset" "firewall" {
  count = var.enable_zone_rules ? 1 : 0

  zone_id     = local.zone_id
  name        = "dbpedia-ja-sparql firewall"
  description = "Edge rules for the DBpedia Japanese SPARQL mirror"
  kind        = "zone"
  phase       = "http_request_firewall_custom"

  rules = [
    {
      ref         = "block_store_admin_paths"
      description = "Block Oxigraph's own write and dump endpoints"
      expression  = "${local.on_endpoint} and ${var.blocked_paths_expression}"
      action      = "block"
    },
    {
      ref         = "block_empty_user_agent"
      description = "Block requests that do not identify themselves at all"
      expression  = "${local.on_endpoint} and http.user_agent eq \"\""
      action      = "block"
    },
  ]
}

resource "cloudflare_ruleset" "ratelimit" {
  count = var.enable_zone_rules ? 1 : 0

  zone_id     = local.zone_id
  name        = "dbpedia-ja-sparql rate limit"
  description = "Blunt per-IP ceiling in front of the Worker"
  kind        = "zone"
  phase       = "http_ratelimit"

  rules = [
    {
      ref         = "sparql_per_ip"
      description = "Per-IP request ceiling on the whole hostname"
      # Counting on the hostname rather than on a path prefix. The path is
      # attacker-controlled text, and any rule that matches part of it can be
      # sidestepped by spelling the path differently; the hostname cannot.
      expression = local.on_endpoint
      action     = "block"

      ratelimit = {
        characteristics = ["ip.src", "cf.colo.id"]
        # 10 s is the only counting period every plan allows (60 s needs
        # Business), so the ceiling is expressed per 10 s.
        period              = 10
        requests_per_period = var.zone_rate_limit_requests
        mitigation_timeout  = var.zone_rate_limit_mitigation_timeout
      }
    },
  ]
}
