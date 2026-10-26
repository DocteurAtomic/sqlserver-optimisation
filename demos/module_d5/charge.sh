#!/usr/bin/env bash
# Module D5, the reports and the enrollment screen. Runs on a throwaway container (the video:
# sqlopt-d5) or on your lab, after 00-setup.sql.
# Sessions:
#   - REPORTS sqlcmd connections (8 by default) under the login report_user, host names
#     report-1 to report-8: the reporting tool. Each one runs Report.LapsedReaders, then
#     Report.ActivityByDevice over a year, again and again, one after the other. Both
#     reports are parallel plans.
#   - one sqlcmd connection under the login entry_user, host name entry-1: the enrollment
#     screen of the back office. Five times a second, it enrolls a contact in an upcoming
#     session by Enrollment.EnrollTrainee, inside a transaction that it rolls back (the data
#     stay the same from one run to the next), and writes the duration of the call to
#     dbo.EntryTiming. The pairs of contact and session are drawn from 40 contacts without
#     any enrollment and 25 open sessions, read at the start.
# The clients run inside the container (exec) and take their share of its processors.
# Duration: DURATION seconds (600 by default), or until Ctrl+C; the trap then stops the
# report in progress. The load also stops when the instance shuts down. Every minute, it
# prints what the container used of its processor quota, and how long the kernel held its
# threads back (cgroup v2, /sys/fs/cgroup/cpu.stat).
# At the end, it prints the enrollments of the run and their median, 95th percentile and
# longest duration, read in dbo.EntryTiming, and what the container used of its processor
# quota (cgroup v2, /sys/fs/cgroup/cpu.stat).
# Cleanup: on exit (end of DURATION, Ctrl+C), the trap stops the sqlcmd processes in the
# container, then kills any SQL session left whose host name starts with report- or entry-.
# Nothing is written to the database but the rows of dbo.EntryTiming.
# Usage: ENGINE=podman CONTAINER=sqlopt-d5 ./demos/module_d5/charge.sh
#   ENGINE: docker (default) or podman. CONTAINER: sqloptcourse by default.
#   DB=<name> runs the load on another copy of the base. REPORTS=<n> changes the number
#   of report connections. The container provides SQLCMDPASSWORD (the password of sa), as
#   the compose.yaml of the lab sets it; the two application logins have their own, set in
#   00-setup.sql.
set -uo pipefail
ENGINE=${ENGINE:-docker}
C=${CONTAINER:-sqloptcourse}
DB=${DB:-PachadataTraining}
DURATION=${DURATION:-600}
REPORTS=${REPORTS:-8}
REPORT_PASSWORD='Lab#Reading2026'
ENTRY_PASSWORD='Lab#Typing2026'

sql() {  # a query as sa, its rows without header
    $ENGINE exec -i "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I -h -1 -W \
        -d "$DB" -Q "SET NOCOUNT ON; $1" 2>/dev/null
}

cpustat() {  # usage_usec of the container, 0 if unreadable
    $ENGINE exec "$C" cat /sys/fs/cgroup/cpu.stat 2>/dev/null \
        | awk '$1=="usage_usec"{u=$2} END{print u+0}' || echo 0
}

throttled() {  # throttled_usec of the container: time its threads waited for the quota
    $ENGINE exec "$C" cat /sys/fs/cgroup/cpu.stat 2>/dev/null \
        | awk '$1=="throttled_usec"{u=$2} END{print u+0}' || echo 0
}

# Pairs of session and contact that Enrollment.EnrollTrainee accepts: contacts aged 36 to
# 56, with no enrollment at all (no duplicate, no overlap), whose company does not prepay;
# open public sessions after the date of the data (18 October 2026).
mapfile -t PAIRS < <(sql "
WITH c AS (SELECT TOP (40) c.ContactId, ROW_NUMBER() OVER (ORDER BY c.ContactId) AS n
           FROM Contact.Contact AS c LEFT JOIN Contact.Company AS co ON co.CompanyId = c.CompanyId
           WHERE c.BirthDate BETWEEN '19700101' AND '19901231' AND ISNULL(co.InvoiceBeforeEnrollment, 0) = 0
             AND NOT EXISTS (SELECT 1 FROM Enrollment.Enrollment AS i WHERE i.ContactId = c.ContactId)
           ORDER BY c.ContactId),
     s AS (SELECT TOP (25) s.SessionId, ROW_NUMBER() OVER (ORDER BY s.SessionId) AS n
           FROM Course.Session AS s
           WHERE s.StatusCode = 'OPEN' AND s.IsInHouse = 0 AND s.StartDate > '20261018'
           ORDER BY s.SessionId)
SELECT CONCAT(s.SessionId, ' ', c.ContactId) FROM c JOIN s ON s.n = (c.n - 1) % 25 + 1;")
if [ "${#PAIRS[@]}" -lt 10 ]; then
    echo "No pairs of session and contact found in $DB: play 00-setup.sql first." >&2
    exit 1
fi

reports() {  # one connection of the reporting tool, until the trap stops it
    while true; do
        printf 'EXEC Report.LapsedReaders @Months = 6;\nGO\n'
        printf "EXEC Report.ActivityByDevice @Start = '20250101', @End = '20251231';\nGO\n"
    done | $ENGINE exec -i -e SQLCMDPASSWORD="$REPORT_PASSWORD" "$C" \
        /opt/mssql-tools18/bin/sqlcmd -S localhost -U report_user -C -I -d "$DB" -H "$1" >/dev/null 2>&1
}

entry() {  # the enrollment screen: one enrollment every 200 ms, timed by the server
    local p
    while true; do
        p=${PAIRS[$(( RANDOM % ${#PAIRS[@]} ))]}
        printf 'DECLARE @t datetime2(7) = SYSDATETIME();\nBEGIN TRANSACTION;\nEXEC Enrollment.EnrollTrainee @SessionId = %d, @ContactId = %d;\nIF @@TRANCOUNT > 0 ROLLBACK;\nINSERT dbo.EntryTiming (DurationMs) VALUES (DATEDIFF_BIG(microsecond, @t, SYSDATETIME()) / 1000.0);\nGO\n' ${p% *} ${p#* }
        sleep 0.2
    done | $ENGINE exec -i -e SQLCMDPASSWORD="$ENTRY_PASSWORD" "$C" \
        /opt/mssql-tools18/bin/sqlcmd -S localhost -U entry_user -C -I -d "$DB" -H "$1" >/dev/null 2>&1
}

start=$(date +%s)
first=$(sql "SELECT ISNULL(MAX(CallId), 0) FROM dbo.EntryTiming;" | tr -d '[:space:]')
u0=$(cpustat)

cleanup() {
    trap - INT TERM HUP EXIT
    # The sqlcmd processes run inside the container: stop them there, then the local jobs.
    $ENGINE exec "$C" pkill -f -- '-H (report|entry)-[0-9]' 2>/dev/null || true
    kill $(jobs -p) 2>/dev/null || true
    $ENGINE exec -i "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I >/dev/null 2>&1 <<'SQL' || true
DECLARE @k nvarchar(max) = N'';
SELECT @k += N'KILL ' + CAST(session_id AS nvarchar(10)) + N'; '
FROM sys.dm_exec_sessions
WHERE host_name LIKE N'report-%' OR host_name LIKE N'entry-%';
EXEC (@k);
SQL
    u1=$(cpustat)
    s=$(( $(date +%s) - start ))
    stats=$(sql "SELECT DISTINCT CONCAT(COUNT(*) OVER (), ' enrollments; median ',
        CAST(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY DurationMs) OVER () AS decimal(9, 1)), ' ms, 95th percentile ',
        CAST(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY DurationMs) OVER () AS decimal(9, 1)), ' ms, longest ',
        CAST(MAX(DurationMs) OVER () AS decimal(9, 1)), ' ms')
        FROM dbo.EntryTiming WHERE CallId > ${first:-0};")
    echo "Load stopped after ${s} s. Enrollment screen: ${stats:-no enrollment}."
    if [ "$s" -gt 0 ] && [ "${u1:-0}" -gt 0 ]; then
        awk -v u=$(( u1 - u0 )) -v s=$s 'BEGIN { printf "Container CPU: %.1f processors on average.\n", u/1e6/s }'
    fi
    exit 0
}
trap cleanup INT TERM HUP EXIT

for n in $(seq 1 "$REPORTS"); do reports "report-$n" & done
entry entry-1 &
echo "Load running on $DB for $DURATION s: $REPORTS report sessions, one enrollment screen. Ctrl+C stops it."
# Every minute, what the container used of its four processors, read by the kernel: SQL
# Server counts the time a thread waits for the quota as processor time, the kernel does not.
end=$(( start + DURATION ))
while [ "$(date +%s)" -lt "$end" ]; do
    a=$(cpustat); t=$(throttled); m0=$(date +%s)
    sleep $(( end - m0 < 60 ? end - m0 : 60 )) & wait $!  # in the background: Ctrl+C acts at once
    b=$(cpustat); t1=$(throttled); m1=$(date +%s)
    [ "$m1" -gt "$m0" ] && awk -v u=$(( b - a )) -v t=$(( t1 - t )) -v s=$(( m1 - m0 )) -v at="$(date +%T)" 'BEGIN {
        printf "%s, last %d s: container CPU %.1f processors, threads throttled %.1f s.\n", at, s, u/1e6/s, t/1e6 }'
done
