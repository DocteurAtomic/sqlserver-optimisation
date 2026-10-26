#!/usr/bin/env bash
# Module V2, the customer area of the website at its busy hour. Runs on the lab, after
# 00-setup.sql.
# Duration: DURATION seconds (1800 by default), or until Ctrl+C.
# Sessions, each one a sqlcmd connection that sends one call after the other:
#   - website-1 to website-3: the page of the invoices of a company,
#     EXEC Enrollment.GetCompanyInvoices, for a random company among the 2,000. Each session
#     first asks for company 100 (10 invoices), so that the plan of these sessions is
#     compiled for a company of usual size, as in 00-setup.sql.
# Cleanup: on exit (end of DURATION, Ctrl+C), the trap stops the sqlcmd processes in the
# container and the loops, then kills any SQL session left whose host name starts with
# website-. Nothing is written to the database.
# Usage: ./demos/module_v2/charge.sh
#   With Podman: ENGINE=podman ./demos/module_v2/charge.sh
#   DB=<name> runs the load on another copy of the base.
set -euo pipefail
ENGINE=${ENGINE:-docker}
DB=${DB:-PachadataTraining}
DURATION=${DURATION:-1800}
C=sqloptcourse

# One sqlcmd session, fed by its standard input, with a host name that names its role.
session() {
    $ENGINE exec -i $C /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I \
        -d "$DB" -H "$1" >/dev/null 2>&1
}

website() {
    {
        printf 'EXEC Enrollment.GetCompanyInvoices @CompanyId = 100;\nGO\n'
        while :; do
            id=$(( RANDOM % 2000 + 1 ))
            printf 'EXEC Enrollment.GetCompanyInvoices @CompanyId = %d;\nGO\n' "$id"
        done
    } | session "$1"
}

cleanup() {
    trap - INT TERM HUP EXIT
    # The sqlcmd processes run inside the container: stop them there, then the loops.
    $ENGINE exec $C pkill -f -- '-H website-[0-9]' 2>/dev/null || true
    kill $(jobs -p) 2>/dev/null || true
    $ENGINE exec -i $C /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I >/dev/null 2>&1 <<'EOF' || true
DECLARE @k nvarchar(max) = N'';
SELECT @k += N'KILL ' + CAST(session_id AS nvarchar(10)) + N'; '
FROM sys.dm_exec_sessions
WHERE host_name LIKE N'website-%';
EXEC (@k);
EOF
    echo "Load stopped."
}
trap cleanup INT TERM HUP EXIT

for n in 1 2 3; do website "website-$n" & done
echo "Load running on $DB for $DURATION s: 3 website sessions. Ctrl+C stops it."
sleep "$DURATION" &
wait $!
