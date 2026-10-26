#!/usr/bin/env bash
# Runs every demo and exercise script of the lab in order, stopping at the first error.
# A script whose first lines contain "-- ci: skip" (several sessions, instance changes, a
# throwaway container) is skipped. The exercises of a module run before its demos'
# 99-cleanup.sql, since they may read what the module's 00-setup.sql created.
# Usage: ./setup/run-scripts.sh [module folder name ...]
set -euo pipefail
cd "$(dirname "$0")/.."
engine=${ENGINE:-docker}
modules=("$@")
if [ ${#modules[@]} -eq 0 ]; then
    modules=($(ls demos exercises 2>/dev/null | grep '^module_' | sort -u || true))
fi
for m in "${modules[@]}"; do
    for f in $(ls demos/$m/*.sql 2>/dev/null | grep -v '/99-' || true) \
             $(ls exercises/$m/*.sql 2>/dev/null || true) \
             $(ls demos/$m/99-*.sql 2>/dev/null || true); do
        if head -5 "$f" | grep -q -- '-- ci: skip'; then echo "skip $f"; continue; fi
        echo "run  $f"
        $engine exec -i sqloptcourse /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -I < "$f" >/dev/null
    done
done
