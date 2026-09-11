#!/usr/bin/env bash
set -euo pipefail

: "${DUMP_BASE_URL:=https://ja.dbpedia.org/dumps}"
: "${DUMP_VERSION:?DUMP_VERSION is not set}"
: "${DATA_DIR:=/data}"
: "${DUMP_PROFILE:=core}"
: "${DUMP_INCLUDE_REGEX:=}"
: "${DUMP_EXCLUDE_REGEX:=}"
: "${DUMP_EXTRA_FILES:=}"
: "${DOWNLOAD_PARALLEL:=4}"
: "${RECOMPRESS_BZ2_TO_GZ:=false}"

index_url="${DUMP_BASE_URL%/}/${DUMP_VERSION}/"
target_dir="${DATA_DIR%/}/${DUMP_VERSION}"
lock_file="${DATA_DIR%/}/download.lck"

urldecode() {
  local s="${1//+/ }"
  printf '%b' "${s//%/\\x}"
}

fix_iri_escapes() {
  sed -E ':a
s/^((<[^>]*> ){0,2}<([^>\\]|\\[uU])*)\\[nrt]/\1/
s/^((<[^>]*> ){0,2}<([^>\\]|\\[uU])*)\\"/\1%22/
s/^((<[^>]*> ){0,2}<([^>\\]|\\[uU])*)\\\\/\1%5C/
ta'
}

if [[ "${1:-}" == "--fetch" ]]; then
  href="$2"; name="$3"; size="$4"
  out="${target_dir}/${name}"
  gz_out="${out%.bz2}.gz"

  if [[ "${RECOMPRESS_BZ2_TO_GZ}" == "true" && "${out}" == *.bz2 && -s "${gz_out}" ]]; then
    echo "[SKIP] ${name} (compressed)"
    exit 0
  fi
  if [[ -f "${out}" && "$(stat -c %s "${out}")" == "${size}" ]]; then
    echo "[SKIP] ${name} (downloaded)"
    exit 0
  fi

  if [[ -f "${out}" && "$(stat -c %s "${out}")" -gt "${size}" ]]; then
    rm -f "${out}"
  fi

  echo "[GET ] ${name} ($((size / 1024 / 1024)) MiB)"
  curl -fL --no-progress-meter -S --retry 10 --retry-delay 5 --retry-connrefused -C - \
       -o "${out}" "${index_url}${href}"

  actual="$(stat -c %s "${out}")"
  if [[ "${actual}" != "${size}" ]]; then
    echo "[ERROR] ${name}: Size is not matched (expected ${size}, got ${actual})" >&2
    exit 1
  fi
  chmod 0644 "${out}"

  if [[ "${RECOMPRESS_BZ2_TO_GZ}" == "true" && "${out}" == *.bz2 ]]; then
    echo "[GZIP] ${name} -> $(basename "${gz_out}")"
    bzcat "${out}" | fix_iri_escapes | pigz -c > "${gz_out}.part"
    mv "${gz_out}.part" "${gz_out}"
    chmod 0644 "${gz_out}"
    rm -f "${out}"
  fi
  exit 0
fi

# --- Profile --------------------------------------------------------------------
case "${DUMP_PROFILE}" in
  core) profile_include='_lang=ja[._]'
        profile_exclude='^(nif-|raw-tables|wikilinks|article-templates)' ;;
  ja)   profile_include='_lang=ja[._]'
        profile_exclude='^$' ;;
  full) profile_include='.'
        profile_exclude='^$' ;;
  *)    echo "[ERROR] Invalid DUMP_PROFILE: '${DUMP_PROFILE}' (core|ja|full)" >&2; exit 1 ;;
esac
include_regex="${DUMP_INCLUDE_REGEX:-${profile_include}}"
exclude_regex="${DUMP_EXCLUDE_REGEX:-${profile_exclude}}"

mkdir -p "${target_dir}"
: > "${lock_file}"
trap 'rm -f "${lock_file}"' EXIT

echo "[INFO] Fetching index: ${index_url}"
listing="$(mktemp)"
curl -fsSL --retry 10 --retry-delay 5 "${index_url}" \
  | tr -d '\r' \
  | awk 'match($0, /href="[^"]+"/) {
           h = substr($0, RSTART + 6, RLENGTH - 7);
           n = split($0, f, " "); s = f[n];
           if (h !~ /\/$/ && s ~ /^[0-9]+$/) print h, s;
         }' > "${listing}"

if [[ ! -s "${listing}" ]]; then
  echo "[ERROR] Could not read the file list from ${index_url}" >&2
  exit 1
fi
echo "[INFO] Index lists $(wc -l < "${listing}") file(s) for ${DUMP_VERSION}"

# --- Filter ---------------------------------------------------------------------
is_extra() {
  local candidate="$1" f
  for f in ${DUMP_EXTRA_FILES}; do
    [[ "${f}" == "${candidate}" ]] && return 0
  done
  return 1
}

manifest="$(mktemp)"
while read -r href size; do
  name="$(urldecode "${href}")"
  if ! is_extra "${name}"; then
    grep -qE -- "${include_regex}" <<<"${name}" || continue
    grep -qE -- "${exclude_regex}" <<<"${name}" && continue
  fi
  printf '%s %s %s\n' "${href}" "${name}" "${size}"
done < "${listing}" > "${manifest}"

count="$(wc -l < "${manifest}")"
total="$(awk '{s += $3} END {print s + 0}' "${manifest}")"
if [[ "${count}" -eq 0 ]]; then
  echo "[ERROR] No file matched the filter (profile=${DUMP_PROFILE})" >&2
  exit 1
fi
echo "[INFO] Target: ${count} file(s) / $((total / 1024 / 1024)) MiB (profile=${DUMP_PROFILE})"

export DUMP_VERSION DATA_DIR RECOMPRESS_BZ2_TO_GZ DUMP_BASE_URL
xargs -a "${manifest}" -n 3 -P "${DOWNLOAD_PARALLEL}" bash "$0" --fetch

echo "[INFO] Finish: ${target_dir}"
du -sh "${target_dir}"
