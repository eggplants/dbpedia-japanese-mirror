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

# The Durable Object class is created outside the version resources, for two
# reasons the API imposes. A version cannot bind to a class whose migration has
# not been deployed yet (error 100123), so the migration has to land before
# the version below. And a namespace is only container-enabled when the upload
# whose migration creates the class also lists it under `containers`, which
# only the legacy script upload API honours — the versions API the provider
# uses ignores it, and nothing can enable a namespace afterwards (the container
# application then fails with DURABLE_OBJECT_NOT_CONTAINER_ENABLED). So the
# class is created once through that API by scripts/worker-bootstrap.sh; the
# script is a no-op while the namespace exists, and recreating the Worker
# (which drops the namespace) runs it again through triggers_replace.
# https://developers.cloudflare.com/workers/platform/infrastructure-as-code/#considerations-with-durable-objects
resource "terraform_data" "worker_bootstrap" {
  triggers_replace = {
    worker_id  = cloudflare_worker.sparql.id
    class_name = var.container_class_name
  }

  provisioner "local-exec" {
    command     = "${path.module}/scripts/worker-bootstrap.sh"
    interpreter = ["/usr/bin/env", "bash", "-c"]
    environment = {
      CF_ACCOUNT_ID         = var.account_id
      CF_WORKER_NAME        = cloudflare_worker.sparql.name
      CF_CLASS_NAME         = var.container_class_name
      CF_BUNDLE             = local.worker_bundle
      CF_COMPATIBILITY_DATE = var.compatibility_date
    }
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
        name = "DATASET_PROFILE"
        text = var.dataset_profile
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

  depends_on = [terraform_data.worker_bootstrap]

  # The provider reads computed binding fields (database_id, namespace_id,
  # script_name, an empty `simple` on non-ratelimit bindings) back into state
  # in a shape that never matches the config, and any binding diff forces a
  # new version — so without this every plan replaces the version and its
  # deployment (cloudflare/terraform-provider-cloudflare#7281, #7345). A new
  # bundle, dataset or image still replaces the version through modules and
  # annotations. After changing only a binding value (a rate limit, pool
  # size, TTL), force it with:
  #   terraform apply -replace=cloudflare_worker_version.sparql
  lifecycle {
    ignore_changes = [bindings]
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
