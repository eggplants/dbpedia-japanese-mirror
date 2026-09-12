# Host DBpedia Japanese SPARQL Endpoint everywhere

[![Website](https://img.shields.io/website?label=ja-dbpedia.egpl.dev&url=https%3A%2F%2Fja-dbpedia.egpl.dev)](https://ja-dbpedia.egpl.dev) [![ci](https://github.com/eggplants/dbpedia-japanese-mirror/actions/workflows/ci.yaml/badge.svg)](https://github.com/eggplants/dbpedia-japanese-mirror/actions/workflows/ci.yaml)

Online deployment on Cloudflare: <https://ja-dbpedia.egpl.dev/>

| On | README |
| - | - |
| Docker Compose | [🔤](./docker-compose/README.md) / [🇯🇵](./docker-compose/README.ja.md) |
| Cloudflare (Workers + Containers) | [🔤](./cloudflare/README.md) / [🇯🇵](./cloudflare/README.ja.md) |

## Development

```bash
mise install
mise generate git-pre-commit --write
```

## License

[MIT License](
  <https://github.com/eggplants/dbpedia-japanese-mirror/blob/master/LICENSE.txt>
)
