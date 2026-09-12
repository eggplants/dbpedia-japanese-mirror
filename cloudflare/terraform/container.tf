# The container application — image, instance size, instance count — is the one
# piece of this stack the Cloudflare Terraform provider does not model. As of
# provider v5.24 there is no `cloudflare_container*` resource: `worker_version`
# can attach a container to a Durable Object class (see main.tf) but cannot say
# which image that container runs.
#
# So it is driven through the REST API instead, wrapped in a terraform_data
# resource so that it still participates in plan/apply/destroy and still
# re-runs when the image or the sizing changes.
#
#   GET    /accounts/{account}/containers/applications
#   POST   /accounts/{account}/containers/applications
#   PATCH  /accounts/{account}/containers/applications/{id}
#   POST   /accounts/{account}/containers/applications/{id}/rollouts
#   DELETE /accounts/{account}/containers/applications/{id}
#
# If Cloudflare ships a first-class resource later, this file is the only thing
# that needs to change.

resource "terraform_data" "container_app" {
  triggers_replace = {
    account_id    = var.account_id
    app_name      = var.container_app_name
    worker_name   = cloudflare_worker.sparql.name
    class_name    = var.container_class_name
    image         = var.container_image
    max_instances = var.container_max_instances
    sizing = jsonencode({
      vcpu       = var.container_vcpu
      memory_mib = var.container_memory_mib
      disk_mb    = var.container_disk_mb
    })
    # A new Worker version can create a new Durable Object namespace, so the
    # application has to be reconciled after every deployment.
    worker_version = cloudflare_worker_version.sparql.id
    script         = filesha256("${path.module}/scripts/container-app.sh")
  }

  provisioner "local-exec" {
    command     = "${path.module}/scripts/container-app.sh apply"
    interpreter = ["/usr/bin/env", "bash", "-c"]
    environment = {
      CF_ACCOUNT_ID    = self.triggers_replace.account_id
      CF_APP_NAME      = self.triggers_replace.app_name
      CF_WORKER_NAME   = self.triggers_replace.worker_name
      CF_CLASS_NAME    = self.triggers_replace.class_name
      CF_IMAGE         = self.triggers_replace.image
      CF_MAX_INSTANCES = self.triggers_replace.max_instances
      CF_VCPU          = var.container_vcpu
      CF_MEMORY_MIB    = var.container_memory_mib
      CF_DISK_MB       = var.container_disk_mb
    }
  }

  provisioner "local-exec" {
    when        = destroy
    command     = "${path.module}/scripts/container-app.sh destroy"
    interpreter = ["/usr/bin/env", "bash", "-c"]
    on_failure  = continue
    environment = {
      CF_ACCOUNT_ID = self.triggers_replace.account_id
      CF_APP_NAME   = self.triggers_replace.app_name
    }
  }

  depends_on = [cloudflare_workers_deployment.sparql]
}
