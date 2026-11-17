#!/usr/bin/env bash
# Same as: python scripts/install_mod.py
set -euo pipefail
exec python "$(cd "$(dirname "$0")" && pwd)/install_mod.py" "$@"
