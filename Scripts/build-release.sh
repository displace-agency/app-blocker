#!/bin/bash
# Public release: build with PUBLIC_BUILD, then package. Exports nothing itself; run it
# from a clean `git archive HEAD` export, never the working tree.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
FOCUSGUARD_PUBLIC=1 bash "$SCRIPT_DIR/build.sh"
bash "$SCRIPT_DIR/create-pkg.sh"
