FROM ghcr.io/oxigraph/oxigraph:0.5.13@sha256:260454ee29c091d2cdb99dd156212594ff3127850627adb4cfdcd9b1e425d480 AS oxigraph

# The oxigraph image ships no shell, so the binary is copied onto a base that
# has one. It is a glibc build, hence Debian rather than Alpine.
FROM debian:bookworm-slim@sha256:99c0b25c46d0214d5a2091092e7908907dcaecd6a962cde0ac700acee222b6f3

COPY --from=oxigraph /usr/local/bin/oxigraph /usr/local/bin/oxigraph
COPY load.sh /load.sh
RUN chmod +x /load.sh

ENTRYPOINT ["/bin/bash", "/load.sh"]
