#!/usr/bin/env bash
# Usage: ./build.sh <input.md> [output.html]
set -euo pipefail

INPUT="${1:?usage: build.sh <input.md> [output.html]}"
OUTPUT="${2:-${INPUT%.md}.html}"

pandoc "$INPUT" \
  -o "$OUTPUT" \
  --standalone \
  --css notes.css \
  --lua-filter filter.lua

echo "Built: $OUTPUT"
