#!/usr/bin/env bash
# Downloads the two backups, checks them, starts the lab and restores the databases.
# Usage: ./setup/install.sh
#   With Podman: COMPOSE="podman compose" ENGINE=podman ./setup/install.sh
set -euo pipefail
cd "$(dirname "$0")/.."
compose=${COMPOSE:-docker compose}
engine=${ENGINE:-docker}
c=sqloptcourse
mkdir -p setup/backup

fetch() {  # name, url, sha256
    local f=setup/backup/$1
    if [ ! -f "$f" ]; then
        echo "Downloading $1..."
        curl -fL --retry 3 -o "$f.part" "$2"
        mv "$f.part" "$f"
    fi
    local got
    if command -v sha256sum >/dev/null; then got=$(sha256sum "$f" | cut -d' ' -f1)
    else got=$(shasum -a 256 "$f" | cut -d' ' -f1); fi
    if [ "$got" != "$3" ]; then
        echo "Checksum mismatch for $f: delete it and run this script again." >&2
        exit 1
    fi
}
fetch PachadataTraining-2026-10.bak \
    'https://files.pachadata.com/public/api/raw?hash=tAsyC50c6kfVadBp3zc6TQ&file=/PachadataTraining/SqlServer/PachadataTraining-2026-10.bak' \
    1d05970d8e0576cd0c57bddba64c2ba8a583845ad4744adeb75d2ea4a3f7d44e
fetch LuminaQuant.bak \
    'https://files.pachadata.com/public/api/raw?hash=tAsyC50c6kfVadBp3zc6TQ&file=/sqlserver/LuminaQuant.bak' \
    24778159a8eadf20d01ed9adbec23b55e575c2b4eed42af965197843f2ce5efc

$compose up -d --wait
$engine exec -u 0 $c mkdir -p /var/opt/mssql/backup
for f in PachadataTraining-2026-10.bak LuminaQuant.bak; do
    $engine cp setup/backup/$f $c:/var/opt/mssql/backup/$f
    $engine exec -u 0 $c chown mssql /var/opt/mssql/backup/$f
done
$engine exec -i $c /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -b -I < setup/restore.sql
