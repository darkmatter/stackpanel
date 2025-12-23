#!/usr/bin/env bash
# Usage: container-size [path-to-json]
# Defaults to .devenv/gc/container-web-derivation

json="${1:-.devenv/gc/container-web-derivation}"

if [[ ! -f "$json" ]]; then
  echo "File not found: $json" >&2
  exit 1
fi

echo "=== Container Size Analysis ==="
echo

# Total size from layers
total=$(jq '[.layers[].size] | add' "$json")
echo "Total compressed size: $(numfmt --to=iec-i --suffix=B $total)"

# Per-layer breakdown
echo
echo "Layer breakdown:"
jq -r '.layers[] | "\(.size)\t\(.paths[0].path // "base")"' "$json" | \
  while IFS=$'\t' read -r size path; do
    hr=$(numfmt --to=iec-i --suffix=B "$size")
    short=$(basename "$path" | cut -c1-50)
    printf "  %10s  %s\n" "$hr" "$short"
  done

# Largest layers
echo
echo "Top 5 largest layers:"
jq -r '.layers | sort_by(-.size) | .[0:5][] | "\(.size)\t\(.paths[0].path // "unknown")"' "$json" | \
  while IFS=$'\t' read -r size path; do
    hr=$(numfmt --to=iec-i --suffix=B "$size")
    short=$(basename "$path")
    printf "  %10s  %s\n" "$hr" "$short"
  done