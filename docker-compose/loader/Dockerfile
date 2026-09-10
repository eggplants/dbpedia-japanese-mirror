ARG OXIGRAPH_VERSION=0.5.11

FROM ghcr.io/oxigraph/oxigraph:${OXIGRAPH_VERSION}@sha256:7532c1f9aa5f28c0dc6a4243198f7f6144017fab7429bf6c164a89fec9411767 AS oxigraph

# The oxigraph image ships no shell, so the binary is copied onto a base that
# has one. It is a glibc build, hence Debian rather than Alpine.
FROM debian:bookworm-slim@sha256:88200866dfff7ea7f5cbcb6ec7c8a701889efe6fe859fe64d6990e4b07ea4171

COPY --from=oxigraph /usr/local/bin/oxigraph /usr/local/bin/oxigraph
COPY load.sh /load.sh
RUN chmod +x /load.sh

ENTRYPOINT ["/bin/bash", "/load.sh"]
