#!/usr/bin/env bash
# Module D1, the peak hour of the PachaData server. Runs on the lab, after 00-setup.sql.
# Two loads, one at a time:
#   ./demos/module_d1/charge.sh reports    4 sessions (report-1 to report-4) run the
#       e-learning report Report.ActivityByDevice in a loop, each on a random year: hash
#       aggregations and sorts over Elearning.Activity (7.8 million rows), that ask for a
#       memory grant.
#   ./demos/module_d1/charge.sh dashboard  8 sessions (dashboard-1 to dashboard-8) send the
#       query of the billing dashboard in a loop, through sp_executesql: the invoice lines of
#       a learner, by last name, a scan of Enrollment.InvoiceLine whose plan costs about 5.4.
# Duration: DURATION seconds (600 by default), or until Ctrl+C.
# At the end, it prints what the container used of its processor quota during the load, and
# how long the kernel held it back (cgroup v2, /sys/fs/cgroup/cpu.stat in the container).
# Cleanup: on exit (end of DURATION, Ctrl+C), the trap stops the sqlcmd processes in the
# container and the loops, then kills any SQL session left whose host name starts with
# report- or dashboard-. Nothing is written to the database.
# Usage: ENGINE=podman ./demos/module_d1/charge.sh reports
#   ENGINE: docker (default) or podman. CONTAINER: sqloptcourse by default (the video uses
#   its throwaway copy, sqlopt-d1). DB=<name> runs the load on another copy of the base.
set -euo pipefail
ENGINE=${ENGINE:-docker}
C=${CONTAINER:-sqloptcourse}
DB=${DB:-PachadataTraining}
DURATION=${DURATION:-600}
MODE=${1:-}
case "$MODE" in
    reports|dashboard) ;;
    *) echo "Usage: $0 reports|dashboard" >&2; exit 2 ;;
esac

# One sqlcmd session, fed by its standard input, with a host name that names its role.
session() {
    $ENGINE exec -i "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I \
        -d "$DB" -H "$1" >/dev/null 2>&1
}

# Last names of learners: each one has a few dozen contacts in the base.
names=(Friedrich Green Walker Griffiths Gomez Keller Scholz Herrmann Moreau Marini
       Durand Ricci Lewis Dubois Dupont Sanchez Krause)

dashboard() {
    while :; do
        n=${names[$(( RANDOM % ${#names[@]} ))]}
        printf "EXEC sys.sp_executesql N'SELECT LineTypeCode, COUNT(*) AS Lines, SUM(NetAmount) AS Amount FROM Enrollment.InvoiceLine WHERE Label LIKE @pattern GROUP BY LineTypeCode;', N'@pattern varchar(200)', @pattern = '%%%s';\nGO\n" "$n"
    done | session "$1"
}

report() {
    while :; do
        y=$(( 2019 + RANDOM % 7 )); m=$(( 1 + 3 * (RANDOM % 4) ))
        printf "EXEC Report.ActivityByDevice @Start = '%04d%02d01', @End = '%04d%02d01';\nGO\n" \
            $y $m $(( y + 1 )) $m
    done | session "$1"
}

cpustat() {  # usage_usec and throttled_usec of the container, 0 0 if unreadable
    $ENGINE exec "$C" cat /sys/fs/cgroup/cpu.stat 2>/dev/null \
        | awk '$1=="usage_usec"{u=$2} $1=="throttled_usec"{t=$2} END{print u+0, t+0}' \
        || echo "0 0"
}

start=$(date +%s)
read -r u0 t0 < <(cpustat)

cleanup() {
    trap - INT TERM HUP EXIT
    # The sqlcmd processes run inside the container: stop them there, then the loops.
    $ENGINE exec "$C" pkill -f -- '-H (report|dashboard)-[0-9]' 2>/dev/null || true
    kill $(jobs -p) 2>/dev/null || true
    $ENGINE exec -i "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I >/dev/null 2>&1 <<'EOF' || true
DECLARE @k nvarchar(max) = N'';
SELECT @k += N'KILL ' + CAST(session_id AS nvarchar(10)) + N'; '
FROM sys.dm_exec_sessions
WHERE host_name LIKE N'report-%' OR host_name LIKE N'dashboard-%';
EXEC (@k);
EOF
    read -r u1 t1 < <(cpustat)
    s=$(( $(date +%s) - start ))
    if [ "$u1" -gt 0 ] && [ "$s" -gt 0 ]; then
        awk -v u=$(( u1 - u0 )) -v t=$(( t1 - t0 )) -v s=$s 'BEGIN {
            printf "Load stopped after %d s. Container CPU: %.0f s used (%.1f processors on average), %.0f s held back by the quota.\n", s, u/1e6, u/1e6/s, t/1e6 }'
    else
        echo "Load stopped."
    fi
}
trap cleanup INT TERM HUP EXIT

if [ "$MODE" = reports ]; then
    for n in 1 2 3 4; do report "report-$n" & done
    echo "Load running on $DB for $DURATION s: 4 report sessions. Ctrl+C stops it."
else
    for n in 1 2 3 4 5 6 7 8; do dashboard "dashboard-$n" & done
    echo "Load running on $DB for $DURATION s: 8 dashboard sessions. Ctrl+C stops it."
fi
sleep "$DURATION" &
wait $!
