# DBpedia Japanese SPARQL Endpoint on Cloudflare

*日本語版: [README.ja.md](README.ja.md)*

## Overview

```mermaid
flowchart TD
    subgraph build["Build"]
        direction LR
        store["../docker-compose/store/db<br/>oxigraph load + optimize"]
        image["dbpedia-ja-oxigraph:DUMP_VERSION"]
        registry["registry.cloudflare.com"]
        store -->|"docker build -f container/Dockerfile"| image
        image -->|"wrangler containers push"| registry
    end

    client(["client"])

    subgraph cf["Cloudflare"]
        direction TB
        edge["ja-dbpedia.egpl.dev (egpl.dev repository)<br/>custom domain, WAF custom rules<br/>zone rate limiting"]
        worker["Worker"]
        page["/<br/>editor + unofficial mirror notice"]
        sparql["/sparql<br/>1. reject SPARQL Update and SERVICE<br/>2. Cache API, keyed by the query hash<br/>3. rate limit per IP only on a miss"]
        do["Durable Object"]
        container["Container: oxigraph serve-read-only<br/>sleeps when idle, image = the store"]

        edge --> worker
        worker --> page
        worker --> sparql
        sparql -->|"cache miss"| do
        do --> container
    end

    client --> edge
    build -.->|"terraform apply"| cf
```

![The Terraform resources: the Worker, its Durable Object class, version, deployment and container in Workers, behind the hostname the egpl.dev repository attaches](diagram/architecture.svg)

This Terraform manages only what lives in the account. The hostname `ja-dbpedia.egpl.dev`, and the zone's WAF and rate limiting rules for it, are in [eggplants/egpl.dev](https://github.com/eggplants/egpl.dev) (`terraform/workers.tf`, `terraform/security.tf`), which owns the `egpl.dev` zone. The state lives in that repository's R2 bucket, under `dbpedia-japanese-mirror/terraform.tfstate`.

## Requirements

- A Cloudflare account on the **Workers Paid** plan
- The R2 bucket `terraform-state`, made by `scripts/create-state-bucket.sh` in the egpl.dev repository
- [mise](https://mise.jdx.dev/) / Docker / `curl` / `jq`
- A loaded store under `../docker-compose/store/db`
  - `cd ../docker-compose && docker compose up --build`

| Scope | Permission |
| --- | --- |
| Account | Workers Scripts Write, Workers Containers Write |
| R2 bucket `terraform-state` | Workers R2 Storage Bucket Item Write |

## Quickstart

```bash
cd cloudflare
mise trust
cf auth login
scripts/create-api-token.sh <account id> # writes the token and the R2 credentials to .env
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
$EDITOR terraform/terraform.tfvars

mise run lint
mise run test
mise run init
mise run plan

mise run deploy
# then attach the hostname from the egpl.dev repository, the first time only

# check
time rqw -e https://ja-dbpedia.egpl.dev/sparql -Q 'SELECT ?o WHERE {
  <http://ja.dbpedia.org/resource/日本> <http://www.w3.org/2000/01/rdf-schema#label> ?o
} LIMIT 10'
```

## Operations

### Updating the dataset

```bash
cd ../docker-compose
$EDITOR .env # DUMP_VERSION=<new version>
docker compose up -d download && docker compose up load

cd ../cloudflare
mise run deploy # the image is tagged with DUMP_VERSION
```

### Cost

| | Always on | `sleep_after = 20m`, 20%/d |
| --- | ---: | ---: |
| Memory (9 GiB, $0.081/h) | $58.32 | $11.66 |
| Disk (18 GB, $0.0045/h) | $3.63 | $0.73 |
| CPU (1 vCPU, $0.072/h active, assuming 10% active) | $5.18 | $1.04 |
| Workers Paid | $5.00 | $5.00 |
| **Total** | **~$72/mo** | **~$18/mo** |

### Suspending the mirror

Set `suspended = true` in `terraform/terraform.tfvars` and run `mise run apply`. The container application is deleted, which stops its instances, and the Worker answers `/` with a notice pointing at the official endpoint (<https://ja.dbpedia.org/sparql>) and `/sparql` with a 503. The Durable Object class stays, and so does the hostname attached from the egpl.dev repository, so setting `suspended = false` and applying again brings the mirror back.

### Teardown

Detach the hostname in the egpl.dev repository first (`terraform/workers.tf`), then:

```bash
mise run destroy
wrangler containers images delete
```

## Troubleshooting

### `No Durable Object namespace for class 'OxigraphContainer'`

The container application ran before the Worker version was deployed. Run `terraform apply` again. `depends_on` normally orders the two, but a half-applied state can end up here.

### The first query after a quiet period takes several seconds

Cold start. Raise `container_sleep_after`, or keep an instance warm with a cron trigger that sends a cheap query.

### Every query returns an empty result

The data was loaded into a named graph but the server is running without `--union-default-graph`, or the other way round. `container/Dockerfile` and `GRAPH_URI` in `../docker-compose/.env` have to agree.

### `disk size exceeds instance limit` when the container starts

The image is larger than `container_disk_mb`. `mise run image` prints the unpacked size (the pushed size is smaller because layers are compressed); check it against the 20000 ceiling and keep `container_memory_mib` at least half of it.

### 429 during ordinary use

Queries without a `LIMIT`, and queries containing `COUNT` or `REGEX`, are drawn from `rate_limit_heavy` (10 per minute by default). Add a `LIMIT`, or raise that variable.

## License

DBpedia data is provided under [CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/) and the [GNU FDL](https://www.gnu.org/licenses/fdl-1.3.html).
