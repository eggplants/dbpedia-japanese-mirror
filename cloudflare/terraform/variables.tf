variable "account_id" {
  type        = string
  description = "Cloudflare account ID that owns the Worker and the container."
}

variable "manage_zone" {
  type        = bool
  default     = false
  description = <<-EOT
    Create the zone in this Cloudflare account. Leave it false when the zone is
    already there — it is then looked up by zone_name. Creating the zone does not
    move the domain's registration; after the first apply, point the domain's
    nameservers at the ones in the `name_servers` output.
  EOT
}

variable "zone_id" {
  type        = string
  default     = ""
  description = <<-EOT
    Pin the zone by ID instead of looking it up by name. Rarely needed. Ignored
    when manage_zone is true.
  EOT
}

variable "zone_name" {
  type        = string
  description = "Zone apex, e.g. egpl.dev."
}

variable "hostname" {
  type        = string
  description = "Hostname the endpoint and the landing page answer on, e.g. ja-dbpedia.egpl.dev. Must be inside zone_name."
}

variable "enable_workers_dev" {
  type        = bool
  default     = false
  description = <<-EOT
    Also serve the Worker on its *.workers.dev hostname.

    Useful before the zone's nameservers have moved, and as the equivalent of a
    *.pages.dev URL. Understand what it costs: workers.dev is not a zone you
    own, so none of the rules in security.tf apply to it — no WAF rules, no
    zone rate limiting, no URL normalization. The Worker's own rate limiting
    bindings and query checks are all that is left, and the hostname is a
    second, unfiltered door to the same container. Leave it off in production.
  EOT
}

variable "source_repository" {
  type        = string
  default     = ""
  description = "Repository link shown in the landing page footer."
}

variable "worker_name" {
  type        = string
  default     = "dbpedia-ja-sparql"
  description = "Name of the Worker script."
}

# --- Container ---------------------------------------------------------------

variable "container_image" {
  type        = string
  description = <<-EOT
    Image reference for the Oxigraph container, e.g. dbpedia-ja-oxigraph:20221201.
    A bare name:tag is resolved against the Cloudflare managed registry
    (registry.cloudflare.com/<account_id>/...). Push it first with `make push`.
  EOT
}

variable "container_app_name" {
  type        = string
  default     = "dbpedia-ja-oxigraph"
  description = "Name of the container application."
}

variable "container_class_name" {
  type        = string
  default     = "OxigraphContainer"
  description = "Durable Object class the container is attached to. Must match the class exported by the Worker."
}

variable "container_vcpu" {
  type        = number
  default     = 1
  description = "vCPU per instance. Maximum 4."
}

variable "container_memory_mib" {
  type        = number
  default     = 9216
  description = <<-EOT
    Memory per instance in MiB. Maximum 12288, at least 3072 per vCPU, and at
    least half of container_disk_mb (custom instance types allow at most 2 GB
    of disk per 1 GiB of memory), which is what sets the default.
    Oxigraph itself needs very little (a 34M-triple store serves point lookups
    at ~64 MB RSS); the rest buys page cache for the store.
  EOT
}

variable "container_disk_mb" {
  type        = number
  default     = 18000
  description = <<-EOT
    Disk per instance in MB. Must exceed the unpacked image size (the pushed
    size is smaller because layers are compressed). Maximum 20000.
    The core profile in a named graph unpacks to around 16.3 GB; loading into
    the default graph instead roughly halves that. The `ja` and `full` profiles
    do not fit under the 20 GB ceiling at all.
  EOT
}

variable "container_max_instances" {
  type        = number
  default     = 3
  description = "Upper bound on simultaneously running instances."
}

variable "container_sleep_after" {
  type        = string
  default     = "20m"
  description = <<-EOT
    Idle time before an instance is stopped. Longer keeps the store warm and
    avoids paying the cold-start cost twice; shorter cuts the bill on a quiet
    endpoint. Memory and disk are billed for as long as an instance runs.
  EOT
}

variable "container_pool_size" {
  type        = number
  default     = 1
  description = <<-EOT
    How many container instances the Worker spreads queries over. Every instance
    holds an identical read-only store. Keep this at 1 until traffic is high
    enough to keep several instances warm — a cold instance has to fault the
    store in from the image before it answers.
  EOT
}

# --- Worker behaviour --------------------------------------------------------

variable "dataset_version" {
  type        = string
  description = "DUMP_VERSION of the loaded dataset, e.g. 20221201. Part of the cache key: bumping it invalidates every cached answer."
}

variable "dataset_profile" {
  type        = string
  default     = "core"
  description = "DUMP_PROFILE the store was built with (core / ja / full). Shown on the landing page."

  validation {
    condition     = contains(["core", "ja", "full"], var.dataset_profile)
    error_message = "dataset_profile must be one of core, ja, full."
  }
}

variable "compatibility_date" {
  type        = string
  default     = "2026-09-01"
  description = "Workers runtime compatibility date."
}

variable "cache_ttl_seconds" {
  type        = number
  default     = 86400
  description = "Edge TTL for a successful query result. The dataset is immutable, so this can be long."
}

variable "browser_ttl_seconds" {
  type        = number
  default     = 300
  description = "max-age handed to clients."
}

variable "max_query_bytes" {
  type        = number
  default     = 8192
  description = "Longest accepted query text."
}

# --- Rate limits -------------------------------------------------------------
#
# These are the Workers rate limiting bindings: no extra cost, but the counters
# are per Cloudflare location, so the effective global limit is higher than the
# number configured here. The zone-level rule in security.tf is the blunt
# instrument that catches a flood before it reaches the Worker at all.

variable "rate_limit_burst" {
  type        = number
  default     = 30
  description = "Requests per 10 s per IP, per colo."
}

variable "rate_limit_sustained" {
  type        = number
  default     = 120
  description = "Requests per 60 s per IP, per colo."
}

variable "rate_limit_heavy" {
  type        = number
  default     = 10
  description = "Requests per 60 s per IP, per colo, for queries with no LIMIT or with an aggregate/regex."
}

variable "zone_rate_limit_requests" {
  type        = number
  default     = 50
  description = "Zone-level rate limiting rule: requests per 10 s per IP, per colo, before the rule blocks."
}

variable "zone_rate_limit_mitigation_timeout" {
  type        = number
  default     = 10
  description = <<-EOT
    How long the block lasts once the zone rate limit trips, in seconds. The
    Free plan only allows 10; Pro allows up to an hour, Business up to a day.
  EOT
}

# --- Optional pieces ---------------------------------------------------------

variable "enable_zone_rules" {
  type        = bool
  default     = true
  description = <<-EOT
    Manage the zone-level WAF and rate limiting rulesets. Set to false if
    something else already owns those phases on this zone — a ruleset resource
    takes over the whole phase and would drop rules it does not know about.
  EOT
}

variable "blocked_paths_expression" {
  type        = string
  default     = "(http.request.uri.path in {\"/update\" \"/store\"} or starts_with(http.request.uri.path, \"/store/\"))"
  description = <<-EOT
    Requests blocked at the edge. Oxigraph's own /update and /store endpoints are
    never reachable through the Worker, but blocking them at the zone keeps a
    stray route or a future misconfiguration from exposing them: a bare
    GET /store streams the entire dataset.
  EOT
}
