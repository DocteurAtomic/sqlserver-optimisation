#!/usr/bin/env bash
# Module D4, the trainers' portal. Runs on the lab, after 00-setup.sql.
# Sessions: 20 sqlcmd connections (portal-1 to portal-20), the application servers of the
# trainers' portal. Each one sends Course.GetAttendanceSheet, one call per batch, one batch
# after the other, for a session drawn at random among the 19,300 sessions of the catalog.
# The clients run inside the container (exec) and take their share of its processors.
# Play 00b-presize-tempdb.sql before the load: its header says why.
# Duration: DURATION seconds (600 by default), or until Ctrl+C. At the natural end, each
# connection still runs the calls already written into its pipe (about thirty seconds).
# The load also stops when the instance shuts down (clip D4.3 restarts it: start the load
# again afterwards).
# At the end, it prints the calls per second during the load, read in
# sys.dm_exec_procedure_stats (no rate when the procedure was changed or the instance
# restarted during the load: 02b-measure-load.sql measures each state), and what the
# container used of its processor quota (cgroup v2, /sys/fs/cgroup/cpu.stat).
# Cleanup: on exit (end of DURATION, Ctrl+C), the trap stops the sqlcmd processes in the
# container, then kills any SQL session left whose host name starts with portal-. Nothing
# is written to the database: the temporary tables disappear with their calls.
# Usage: ENGINE=podman ./demos/module_d4/charge.sh
#   ENGINE: docker (default) or podman. CONTAINER: sqloptcourse by default (the video uses
#   its throwaway copy, sqlopt-d4). DB=<name> runs the load on another copy of the base.
#   SESSIONS=<n> changes the number of connections (20 by default).
#   The container provides SQLCMDPASSWORD, as the compose.yaml of the lab sets it.
set -uo pipefail
ENGINE=${ENGINE:-docker}
C=${CONTAINER:-sqloptcourse}
DB=${DB:-PachadataTraining}
DURATION=${DURATION:-600}
SESSIONS=${SESSIONS:-20}

sql() {  # one value from a query, empty if the instance does not answer
    $ENGINE exec -i "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I -h -1 -W \
        -d "$DB" -Q "SET NOCOUNT ON; $1" 2>/dev/null | tr -d '[:space:]'
}

calls() {  # executions of the procedure since its plan was cached, and when it was cached
    sql "SELECT CONCAT(ISNULL(SUM(execution_count), 0), ',', CONVERT(varchar(23), MIN(cached_time), 126)) FROM sys.dm_exec_procedure_stats WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Course.GetAttendanceSheet');"
}

cpustat() {  # usage_usec of the container, 0 if unreadable
    $ENGINE exec "$C" cat /sys/fs/cgroup/cpu.stat 2>/dev/null \
        | awk '$1=="usage_usec"{u=$2} END{print u+0}' || echo 0
}

portal() {  # one application server: one call per batch, as a page of the portal sends it
    local end=$(( $(date +%s) + DURATION ))
    while [ "$(date +%s)" -lt "$end" ]; do
        for k in 1 2 3 4 5 6 7 8 9 10; do
            printf 'EXEC Course.GetAttendanceSheet @SessionId = %d;\nGO\n' \
                $(( (RANDOM * 32768 + RANDOM) % 19300 + 1 ))
        done
    done | $ENGINE exec -i "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I \
        -d "$DB" -H "$1" >/dev/null 2>&1
}

start=$(date +%s)
c0=$(calls); u0=$(cpustat)

cleanup() {
    trap - INT TERM HUP EXIT
    # The sqlcmd processes run inside the container: stop them there, then the local jobs.
    $ENGINE exec "$C" pkill -f -- '-H portal-[0-9]' 2>/dev/null || true
    kill $(jobs -p) 2>/dev/null || true
    $ENGINE exec -i "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I >/dev/null 2>&1 <<'SQL' || true
DECLARE @k nvarchar(max) = N'';
SELECT @k += N'KILL ' + CAST(session_id AS nvarchar(10)) + N'; '
FROM sys.dm_exec_sessions
WHERE host_name LIKE N'portal-%';
EXEC (@k);
SQL
    c1=$(calls); u1=$(cpustat)
    s=$(( $(date +%s) - start ))
    # Same plan at the start and at the end (same cached_time): the difference is the calls.
    if [ "$s" -gt 0 ] && [ -n "$c0" ] && [ "${c0#*,}" = "${c1#*,}" ] && [ "${u1:-0}" -gt 0 ]; then
        awk -v c=$(( ${c1%%,*} - ${c0%%,*} )) -v u=$(( u1 - u0 )) -v s=$s 'BEGIN {
            printf "Load stopped after %d s: %.0f calls per second; container CPU %.1f processors on average.\n", s, c/s, u/1e6/s }'
    else
        echo "Load stopped after ${s} s (the procedure or the instance changed during the load: no rate)."
    fi
}
trap cleanup INT TERM HUP EXIT

for n in $(seq 1 "$SESSIONS"); do portal "portal-$n" & done
echo "Load running on $DB for $DURATION s: $SESSIONS portal sessions. Ctrl+C stops it."
wait
