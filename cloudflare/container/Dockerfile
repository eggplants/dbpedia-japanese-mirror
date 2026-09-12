FROM ghcr.io/oxigraph/oxigraph:0.5.11@sha256:7532c1f9aa5f28c0dc6a4243198f7f6144017fab7429bf6c164a89fec9411767

# The store is staged into eight directories by scripts/stage-layers.sh so
# that no single image layer exceeds the 5 GiB the Cloudflare registry accepts.
COPY layers/0 /srv/db
COPY layers/1 /srv/db
COPY layers/2 /srv/db
COPY layers/3 /srv/db
COPY layers/4 /srv/db
COPY layers/5 /srv/db
COPY layers/6 /srv/db
COPY layers/7 /srv/db

EXPOSE 7878

CMD ["serve-read-only", \
     "--location", "/srv/db", \
     "--bind", "0.0.0.0:7878", \
     "--union-default-graph", \
     "--cors", \
     "--timeout-s", "20"]
