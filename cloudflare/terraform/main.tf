locals {
  worker_bundle = "${path.module}/../worker/dist/index.mjs"
  bundle_sha    = filesha256(local.worker_bundle)
}

resource "cloudflare_worker" "sparql" {
  account_id = var.account_id
  name       = var.worker_name

  observability = {
    enabled            = true
    head_sampling_rate = 1
  }

  # The workers.dev hostname answers without passing through any of the zone
  # rules in security.tf, so it is off unless asked for. Preview URLs are the
  # same hole with a version prefix, and stay off either way.
  subdomain = {
    enabled          = var.enable_workers_dev
    previews_enabled = false
  }
}

resource "cloudflare_worker_version" "sparql" {
  account_id = var.account_id
  worker_id  = cloudflare_worker.sparql.id

  main_module         = "index.mjs"
  compatibility_date  = var.compatibility_date
  compatibility_flags = ["nodejs_compat"]

  modules = [{
    name         = "index.mjs"
    content_type = "application/javascript+module"
    content_file = local.worker_bundle
  }]

  # Containers are only reachable through a Durable Object, and a Durable Object
  # that backs a container has to be SQLite-backed.
  migrations = {
    new_tag            = "v1"
    new_sqlite_classes = [var.container_class_name]
  }

  containers = [{
    class_name = var.container_class_name
  }]

  bindings = concat(
    [
      {
        type       = "durable_object_namespace"
        name       = "OXIGRAPH"
        class_name = var.container_class_name
      },
      {
        type = "plain_text"
        name = "DATASET_VERSION"
        text = var.dataset_version
      },
      {
        type = "plain_text"
        name = "SOURCE_REPOSITORY"
        text = var.source_repository
      },
      {
        type = "plain_text"
        name = "CACHE_TTL"
        text = tostring(var.cache_ttl_seconds)
      },
      {
        type = "plain_text"
        name = "BROWSER_TTL"
        text = tostring(var.browser_ttl_seconds)
      },
      {
        type = "plain_text"
        name = "MAX_QUERY_BYTES"
        text = tostring(var.max_query_bytes)
      },
      {
        type = "plain_text"
        name = "CONTAINER_POOL_SIZE"
        text = tostring(var.container_pool_size)
      },
      {
        type = "plain_text"
        name = "CONTAINER_SLEEP_AFTER"
        text = var.container_sleep_after
      },
    ],
    [
      {
        type         = "ratelimit"
        name         = "RL_BURST"
        namespace_id = "1001"
        simple = {
          limit  = var.rate_limit_burst
          period = 10
        }
      },
      {
        type         = "ratelimit"
        name         = "RL_SUSTAINED"
        namespace_id = "1002"
        simple = {
          limit  = var.rate_limit_sustained
          period = 60
        }
      },
      {
        type         = "ratelimit"
        name         = "RL_HEAVY"
        namespace_id = "1003"
        simple = {
          limit  = var.rate_limit_heavy
          period = 60
        }
      },
    ],
  )

  limits = {
    cpu_ms = 30000
  }

  annotations = {
    workers_message = "dataset ${var.dataset_version}, image ${var.container_image}"
    workers_tag     = substr(local.bundle_sha, 0, 16)
  }
}

resource "cloudflare_workers_deployment" "sparql" {
  account_id  = var.account_id
  script_name = cloudflare_worker.sparql.name
  strategy    = "percentage"

  versions = [{
    version_id = cloudflare_worker_version.sparql.id
    percentage = 100
  }]

  annotations = {
    workers_message = "dataset ${var.dataset_version}"
  }
}

resource "cloudflare_workers_custom_domain" "sparql" {
  account_id = var.account_id
  zone_id    = local.zone_id
  zone_name  = var.zone_name
  hostname   = var.hostname
  service    = cloudflare_worker.sparql.name

  depends_on = [cloudflare_workers_deployment.sparql]
}
