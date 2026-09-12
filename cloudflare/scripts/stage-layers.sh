#!/usr/bin/env bash
#
# Stages the Oxigraph store into LAYERS balanced directories under the Docker
# build context so container/Dockerfile can COPY each one as its own image
# layer. The Cloudflare registry writes every layer with a single R2 put,
# which caps a layer at 5 GiB; the store is one flat directory of ~16 GB.
#
# Usage: stage-layers.sh <store db dir> <context dir>
#
# Files are hardlinked into the context when it is on the same filesystem as
# the store and copied otherwise. LAYERS must match the COPY lines in
# container/Dockerfile.
set -euo pipefail

src="${1:?store db dir}"
dst="${2:?context dir}"
LAYERS=8

if [[ -n "$(find "${src}" -mindepth 1 -type d -print -quit)" ]]; then
  echo "[ERROR] ${src} has subdirectories; stage-layers.sh only handles a flat store" >&2
  exit 1
fi

rm -rf "${dst}"
for ((i = 0; i < LAYERS; i++)); do
  mkdir -p "${dst}/layers/${i}"
done

link() {
  ln "$1" "$2" 2>/dev/null || cp "$1" "$2"
}

# Largest file first, each into the currently lightest layer.
find "${src}" -maxdepth 1 -type f -printf '%s\t%f\n' | sort -rn |
  awk -F '\t' -v n="${LAYERS}" '
    {
      min = 0
      for (i = 1; i < n; i++) if (size[i] < size[min]) min = i
      size[min] += $1
      print min "\t" $2
    }
    END {
      for (i = 0; i < n; i++) printf "[INFO] layer %d: %.2f GB\n", i, size[i] / 1e9 > "/dev/stderr"
    }' |
  while IFS=$'\t' read -r layer name; do
    link "${src}/${name}" "${dst}/layers/${layer}/${name}"
  done
