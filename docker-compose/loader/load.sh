#!/usr/bin/env bash
set -euo pipefail

: "${DATA_DIR:=/data}"
: "${DUMP_VERSION:?DUMP_VERSION is not set}"
: "${STORE_LOCATION:=/store/db}"
: "${MARKER_DIR:=/store/.loaded}"
: "${GRAPH_URI:=http://ja.dbpedia.org}"
: "${LOAD_LENIENT:=true}"
: "${LOAD_NON_ATOMIC:=true}"
: "${LOAD_BATCH_SIZE:=4}"
: "${RUN_OPTIMIZE:=true}"

dump_dir="${DATA_DIR%/}/${DUMP_VERSION}"
marker_dir="${MARKER_DIR%/}/${DUMP_VERSION}"

if [[ ! -d "${dump_dir}" ]]; then
  echo "[ERROR] Dump directory not found: ${dump_dir}" >&2
  exit 1
fi
mkdir -p "${marker_dir}" "$(dirname "${STORE_LOCATION}")"

# oxigraph guesses the format from the file extension and understands gzip,
# but not bzip2. The downloader turns .bz2 into .gz when RECOMPRESS_BZ2_TO_GZ
# is true; anything still compressed with bzip2 cannot be loaded.
leftover_bz2="$(find "${dump_dir}" -type f -name '*.bz2' | wc -l)"
if [[ "${leftover_bz2}" -gt 0 ]]; then
  echo "[WARN] Skipping ${leftover_bz2} .bz2 file(s): oxigraph cannot read bzip2."
  echo "[WARN] Set RECOMPRESS_BZ2_TO_GZ=true in .env and run the download again."
fi

mapfile -t candidates < <(
  find "${dump_dir}" -type f \
    \( -name '*.ttl' -o -name '*.ttl.gz' -o -name '*.nt' -o -name '*.nt.gz' \) \
    | sort
)

if [[ "${#candidates[@]}" -eq 0 ]]; then
  echo "[ERROR] No loadable file found under ${dump_dir}" >&2
  exit 1
fi

pending=()
for file in "${candidates[@]}"; do
  if [[ -f "${marker_dir}/$(basename "${file}").loaded" ]]; then
    continue
  fi
  pending+=("${file}")
done

echo "[INFO] ${#candidates[@]} loadable file(s), ${#pending[@]} not loaded yet"
if [[ "${#pending[@]}" -eq 0 ]]; then
  echo "[INFO] Nothing new to load"
  exit 0
fi

load_opts=()
if [[ "${LOAD_LENIENT}" == "true" ]]; then
  load_opts+=(--lenient)
fi
if [[ "${LOAD_NON_ATOMIC}" == "true" ]]; then
  load_opts+=(--non-atomic)
fi

# Files passed in one invocation are loaded in parallel. Batching keeps that
# parallelism while still recording progress, so a failure part way through
# does not throw away everything that already went in.
total="${#pending[@]}"
done_count=0
while [[ "${done_count}" -lt "${total}" ]]; do
  batch=("${pending[@]:done_count:LOAD_BATCH_SIZE}")
  echo "[LOAD] $((done_count + 1))-$((done_count + ${#batch[@]})) / ${total}"
  for file in "${batch[@]}"; do
    echo "         $(basename "${file}")"
  done

  oxigraph load \
    --location "${STORE_LOCATION}" \
    --graph "${GRAPH_URI}" \
    "${load_opts[@]}" \
    --file "${batch[@]}"

  for file in "${batch[@]}"; do
    : > "${marker_dir}/$(basename "${file}").loaded"
  done
  done_count=$((done_count + ${#batch[@]}))
done

if [[ "${RUN_OPTIMIZE}" == "true" ]]; then
  echo "[INFO] Optimizing the store for read-heavy use"
  oxigraph optimize --location "${STORE_LOCATION}"
fi

echo "[INFO] Triples in graph <${GRAPH_URI}>:"
oxigraph query \
  --location "${STORE_LOCATION}" \
  --query "SELECT (COUNT(*) AS ?c) WHERE { GRAPH <${GRAPH_URI}> { ?s ?p ?o } }" \
  --results-format tsv

echo "[INFO] Done. The SPARQL endpoint is ready."
