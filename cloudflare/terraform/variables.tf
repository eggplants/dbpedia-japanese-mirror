variable "account_id" {
  type        = string
  description = "Cloudflare account ID that owns the Worker and the container."
}

variable "hostname" {
  type        = string
  default     = "ja-dbpedia.egpl.dev"
  description = <<-EOT
    Hostname the endpoint and the landing page answer on. Only the outputs use
    it: the egpl.dev repository attaches it to the Worker
    (terraform/workers.tf) and holds the zone's rules for it.
  EOT
}

variable "enable_workers_dev" {
  type        = bool
  default     = false
  description = <<-EOT
    Also serve the Worker on its *.workers.dev hostname.

    Useful before the hostname is attached, and as the equivalent of a
    *.pages.dev URL. Understand what it costs: workers.dev is not a zone you
    own, so none of the zone's rules (terraform/security.tf in the egpl.dev
    repository) apply to it — no WAF rules, no zone rate limiting, no URL
    normalization. The Worker's own rate limiting bindings and query checks
    are all that is left, and the hostname is a second, unfiltered door to the
    same container. Leave it off in production.
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

variable "suspended" {
  type        = bool
  default     = false
  description = <<-EOT
    Retire the mirror without tearing the stack down. The container application
    is deleted, which stops every instance and its billing, and the Worker
    serves a notice pointing at the official endpoint (https://ja.dbpedia.org/sparql)
    on / and a 503 on /sparql. The Durable Object class stays, and so does the
    hostname attached from the egpl.dev repository, so setting this back to
    false brings the mirror back with a plain apply.
  EOT
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
# number configured here. The zone-level rule (terraform/security.tf in the
# egpl.dev repository) is the blunt instrument that catches a flood before it
# reaches the Worker at all.

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
