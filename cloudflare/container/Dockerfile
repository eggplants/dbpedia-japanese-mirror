FROM ghcr.io/oxigraph/oxigraph:0.5.13@sha256:260454ee29c091d2cdb99dd156212594ff3127850627adb4cfdcd9b1e425d480

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
