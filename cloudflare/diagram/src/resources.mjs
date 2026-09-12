// How Terraform resources appear in the diagram. `terraform graph` supplies the
// resources and their dependencies; this file supplies everything the graph
// does not know: which Cloudflare product each resource is, which box it sits
// in, and what to call it. A resource missing from here is still drawn, with
// the Terraform icon and its address as the label, so the diagram cannot go
// quietly stale — an unmapped resource is visible.
//
// Icon names are the `type` values of @cloudflare/component-icon; the full
// list is in its dist/Icon.d.ts.

// Boxes. A group that `represents` resources stands in for them: the zone is
// drawn as the box the zone-level resources sit in, not as a node of its own,
// and the resource's dependency edges to the members of its box are implied by
// the box. The data source and the managed resource are the same zone, only
// one of them exists at a time (see zone.tf).
export const groups = [
  {
    id: "zone",
    label: "Zone",
    represents: ["cloudflare_zone.this", "data.cloudflare_zone.this"],
  },
  {
    id: "workers",
    label: "Workers",
  },
];

// Resources, in the order they are listed within their box.
export const resources = {
  "cloudflare_workers_custom_domain.sparql": {
    group: "zone",
    icon: "reliability-dns",
    label: "Custom domain",
  },
  "cloudflare_url_normalization_settings.this": {
    group: "zone",
    icon: "cloudflare-ruleset-engine",
    label: "URL normalization",
  },
  "cloudflare_ruleset.firewall": {
    group: "zone",
    icon: "security-waf",
    label: "WAF custom rules",
  },
  "cloudflare_ruleset.ratelimit": {
    group: "zone",
    icon: "reliability-timer-outline",
    label: "Rate limiting",
  },
  "cloudflare_worker.sparql": {
    group: "workers",
    icon: "workers-bundled",
    label: "Worker",
  },
  "terraform_data.worker_bootstrap": {
    group: "workers",
    icon: "workers-durable-objects",
    label: "Durable Object class",
  },
  "cloudflare_worker_version.sparql": {
    group: "workers",
    icon: "version",
    label: "Worker version",
  },
  "cloudflare_workers_deployment.sparql": {
    group: "workers",
    icon: "upload",
    label: "Deployment",
  },
  "terraform_data.container_app": {
    group: "workers",
    icon: "virtual-machine-outline",
    label: "Container",
  },
};

export const fallback = { icon: "terraform" };

// Nodes that are not Terraform resources but make the picture readable: where
// the traffic comes from. `to` is the resource address it points at.
export const extras = [
  {
    id: "client",
    icon: "user",
    form: "circle",
    label: "Client",
    to: "cloudflare_workers_custom_domain.sparql",
  },
];
