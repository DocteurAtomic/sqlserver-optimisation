#!/usr/bin/env bash
# Module 1, background load of the PachaData server. Runs on the lab, after 00-setup.sql.
# Duration: DURATION seconds (1800 by default), or until Ctrl+C.
# Sessions, each one a sqlcmd connection that sends one batch after the other:
#   - reports-1 to reports-3: the reports of the Report schema, in a loop, each session
#     starting at a different report;
#   - website-1 and website-2: the list of the enrollees of a session, as the website sends
#     it, through sp_executesql, for a random session, in a loop.
# Cleanup: on exit (end of DURATION, Ctrl+C), the trap stops the sqlcmd processes in the
# container and the loops, then kills any SQL session left whose host name starts with
# reports- or website-. Nothing is written to the database.
# Usage: ./demos/module_01/charge.sh
#   With Podman: ENGINE=podman ./demos/module_01/charge.sh
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
    while :; do
        id=$(( (RANDOM * 32768 + RANDOM) % 19300 + 1 ))
        cat <<EOF
EXEC sys.sp_executesql N'SELECT e.EnrollmentId, c.LastName, c.FirstName, c.Email,
       e.CreationDate, e.WaitingList
FROM Enrollment.Enrollment AS e
JOIN Contact.Contact AS c ON c.ContactId = e.ContactId
WHERE e.SessionId = @SessionId
  AND e.CancellationDate IS NULL
ORDER BY c.LastName, c.FirstName;', N'@SessionId int', @SessionId = $id;
GO
EOF
    done | session "$1"
}

reports=(
    "EXEC Report.MonthlyRevenue @Start = '20250101', @End = '20251231';"
    "EXEC Report.OverduePayments;"
    "EXEC Report.CampaignPerformance @Start = '20260101', @End = '20260630';"
    "EXEC Report.TrainerRanking @Year = 2025;"
    "EXEC Report.SessionFillRate @Year = 2025;"
    "EXEC Report.ElearningEngagement @CourseId = 169;"
)

report_loop() {  # host name, first report
    local i=$2
    while :; do
        printf '%s\nGO\n' "${reports[$(( i % ${#reports[@]} ))]}"
        i=$(( i + 1 ))
    done | session "$1"
}

cleanup() {
    trap - INT TERM HUP EXIT
    # The sqlcmd processes run inside the container: stop them there, then the loops.
    $ENGINE exec $C pkill -f -- '-H (reports|website)-[0-9]' 2>/dev/null || true
    kill $(jobs -p) 2>/dev/null || true
    $ENGINE exec -i $C /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I >/dev/null 2>&1 <<'EOF' || true
DECLARE @k nvarchar(max) = N'';
SELECT @k += N'KILL ' + CAST(session_id AS nvarchar(10)) + N'; '
FROM sys.dm_exec_sessions
WHERE host_name LIKE N'reports-%' OR host_name LIKE N'website-%';
EXEC (@k);
EOF
    echo "Load stopped."
}
trap cleanup INT TERM HUP EXIT

for n in 1 2 3; do report_loop "reports-$n" $(( (n - 1) * 2 )) & done
for n in 1 2; do website "website-$n" & done
echo "Load running on $DB for $DURATION s: 3 report sessions, 2 website sessions. Ctrl+C stops it."
sleep "$DURATION" &
wait $!
