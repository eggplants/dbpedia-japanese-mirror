// How Terraform resources appear in the diagram. `terraform graph` supplies the
// resources and their dependencies; this file supplies everything the graph
// does not know: which Cloudflare product each resource is, which box it sits
// in, and what to call it. A resource missing from here is still drawn, with
// the Terraform icon and its address as the label, so the diagram cannot go
// quietly stale — an unmapped resource is visible.
//
// Icon names are the `type` values of @cloudflare/component-icon; the full
// list is in its dist/Icon.d.ts.

// Boxes. A group that `represents` resources stands in for them: it is drawn
// as the box its members sit in, not as a node of its own, and the resource's
// dependency edges to the members of its box are implied by the box.
export const groups = [
  {
    id: "workers",
    label: "Workers",
  },
];

// Resources, in the order they are listed within their box.
export const resources = {
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

// Nodes that are not Terraform resources here but make the picture readable:
// where the traffic comes from, and the hostname the egpl.dev repository
// attaches to the Worker together with the zone's rules. `to` is the resource
// address or the extra's id it points at.
export const extras = [
  {
    id: "client",
    icon: "user",
    form: "circle",
    label: "Client",
    to: "egpl_dev",
  },
  {
    id: "egpl_dev",
    icon: "reliability-dns",
    label: "ja-dbpedia.egpl.dev<br/>custom domain and zone rules<br/>eggplants/egpl.dev/terraform",
    to: "cloudflare_worker.sparql",
  },
];
