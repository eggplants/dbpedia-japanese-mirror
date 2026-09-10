FROM ghcr.io/oxigraph/oxigraph:0.5.11@sha256:7532c1f9aa5f28c0dc6a4243198f7f6144017fab7429bf6c164a89fec9411767

COPY db /srv/db

EXPOSE 7878

CMD ["serve-read-only", \
     "--location", "/srv/db", \
     "--bind", "0.0.0.0:7878", \
     "--union-default-graph", \
     "--cors", \
     "--timeout-s", "20"]
