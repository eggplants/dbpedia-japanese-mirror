output "endpoint" {
  value       = "https://${var.hostname}/sparql"
  description = "The SPARQL endpoint."
}

output "landing_page" {
  value       = "https://${var.hostname}/"
  description = "The query editor and the unofficial-mirror notice."
}

output "workers_dev_url" {
  value       = var.enable_workers_dev ? cloudflare_worker.sparql.subdomain.url : null
  description = "The *.workers.dev address, when enable_workers_dev is true. None of the zone rules apply to it."
}

output "worker_name" {
  value       = cloudflare_worker.sparql.name
  description = "Name of the deployed Worker."
}

output "worker_version_id" {
  value       = cloudflare_worker_version.sparql.id
  description = "Version currently receiving 100% of traffic."
}

output "container_application" {
  value       = var.container_app_name
  description = "Container application name. Inspect it with `wrangler containers list`."
}

output "example_request" {
  description = "A query that should come back immediately."
  value       = <<-EOT
    curl -sG https://${var.hostname}/sparql \
      -H 'Accept: application/sparql-results+json' \
      --data-urlencode 'query=SELECT ?o WHERE { <http://ja.dbpedia.org/resource/日本> <http://www.w3.org/2000/01/rdf-schema#label> ?o } LIMIT 10'
  EOT
}
