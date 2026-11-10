#!/usr/bin/env bash
# Headless tests. `tests/run.sh` runs the free ones; `tests/run.sh live` also calls OpenRouter (3 tiny requests, <0.01 USD).
set -u
cd "$(dirname "$0")/.." || exit 1
export PLUGIN_DIR=$PWD
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
run() { echo "--- $1"; cp tests/sample.md "$tmp/sample.md"; SAMPLE=$tmp/sample.md timeout 60 nvim --headless -i NONE -n -u NONE -l "tests/$1.lua" 2>&1 | tail -${2:-6}; }
run tidy 3
run offline 6
if [ "${1:-}" = live ]; then run live 14; fi
if [ -f ~/.config/nvim/init.lua ]; then
  echo "--- lazyvim (your real config)"; cp tests/sample.md "$tmp/sample.md"
  SAMPLE=$tmp/sample.md timeout 60 nvim --headless -n -u ~/.config/nvim/init.lua -l tests/lazyvim.lua 2>&1 | tail -6
fi
