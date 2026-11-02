FROM ghcr.io/oxigraph/oxigraph:0.5.11@sha256:7532c1f9aa5f28c0dc6a4243198f7f6144017fab7429bf6c164a89fec9411767 AS oxigraph

# The oxigraph image ships no shell, so the binary is copied onto a base that
# has one. It is a glibc build, hence Debian rather than Alpine.
FROM debian:bookworm-slim@sha256:99c0b25c46d0214d5a2091092e7908907dcaecd6a962cde0ac700acee222b6f3

COPY --from=oxigraph /usr/local/bin/oxigraph /usr/local/bin/oxigraph
COPY load.sh /load.sh
RUN chmod +x /load.sh

ENTRYPOINT ["/bin/bash", "/load.sh"]
