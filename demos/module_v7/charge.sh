#!/usr/bin/env bash
# Module V7, the accounting team and the customer area at work. Runs on the lab, after
# 00-setup.sql.
# Duration: DURATION seconds (300 by default), or until Ctrl+C.
# Sessions, each one a sqlcmd connection that sends one batch after the other:
#   - billing-1 and billing-2: two accountants who cancel invoices of 2026 through
#     Enrollment.IssueCreditNote, then wait a second, billing-1 from FA2026-007500
#     downward and billing-2 from FA2026-006500 downward;
#   - reminders-1: the reminders screen of the accounting team, the invoices of 2026 that
#     have been reminded, refreshed every second;
#   - web-1 and web-2: the customer area of the website, one invoice of 2026 displayed by
#     its number, five pages a second each.
# At the end, it prints for the reminders screen and the customer area the number of
# queries run, their mean duration and their mean processor time, and for the two
# accountants the credit notes issued and the errors received (2627: duplicate key).
# Messages of the server are in the files <role>.err of the folder given by LOGDIR (a
# temporary folder by default).
# Cleanup: on exit (end of DURATION, Ctrl+C), the trap stops the sqlcmd processes in the
# container and the loops, then kills any SQL session left whose host name starts with
# billing-, reminders- or web-. The credit notes issued stay in the base: 00-setup.sql
# restores it.
# Usage: ENGINE=podman ./demos/module_v7/charge.sh
#   ENGINE: docker (default) or podman. DB=<name> runs the load on another copy of the
#   base. The container provides SQLCMDPASSWORD, as the compose.yaml of the lab sets it.
set -euo pipefail
ENGINE=${ENGINE:-docker}
C=${CONTAINER:-sqloptcourse}
DB=${DB:-PachadataTraining}
DURATION=${DURATION:-300}
LOGDIR=${LOGDIR:-$(mktemp -d)}

# One sqlcmd session, fed by its standard input, with a host name that names its role.
session() {
    $ENGINE exec -i "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I -r1 \
        -d "$DB" -H "$1" >"$LOGDIR/$1.out" 2>"$LOGDIR/$1.err"
}

billing() {  # usage: billing <role> <first invoice number>
    local n=$2
    while :; do
        printf "EXEC Enrollment.IssueCreditNote @InvoiceCode = 'FA2026-%06d', @Reason = 'Goodwill gesture';\nWAITFOR DELAY '00:00:01';\nGO\n" "$n"
        n=$(( n - 1 ))
    done | session "$1"
}

reminders() {
    while :; do
        printf '%s\n' \
"SELECT InvoiceCode, InvoiceDate, DueDate, GrossAmount, ReminderLevel, ReminderDate" \
"FROM Enrollment.Invoice" \
"WHERE InvoiceCode LIKE 'FA2026-%' AND ReminderLevel > 0" \
"ORDER BY DueDate;" \
"WAITFOR DELAY '00:00:01';" "GO"
    done | session "$1"
}

web() {
    local n
    while :; do
        n=$(( RANDOM % 7500 + 1 ))
        printf "EXEC sp_executesql N'SELECT InvoiceCode, InvoiceDate, DueDate, GrossAmount, ReminderLevel FROM Enrollment.Invoice WHERE InvoiceCode = @c;', N'@c varchar(50)', @c = 'FA2026-%06d';\nWAITFOR DELAY '00:00:00.200';\nGO\n" "$n"
    done | session "$1"
}

# Executions, elapsed and processor time (microseconds) of the screen and the page so far.
stats() {
    $ENGINE exec -i "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I -h -1 -W -d "$DB" \
        -Q "SET NOCOUNT ON;
SELECT q, SUM(execution_count), SUM(total_elapsed_time), SUM(total_worker_time), MAX(max_elapsed_time)
FROM (SELECT CASE WHEN t.text LIKE N'%ReminderLevel > 0%' THEN 'reminders'
                  WHEN t.text LIKE N'%InvoiceCode = @c%' THEN 'web' END AS q,
             qs.execution_count, qs.total_elapsed_time, qs.total_worker_time, qs.max_elapsed_time
      FROM sys.dm_exec_query_stats AS qs
      CROSS APPLY sys.dm_exec_sql_text(qs.sql_handle) AS t
      WHERE t.text NOT LIKE N'%dm_exec_query_stats%') AS s
WHERE q IS NOT NULL
GROUP BY q;" \
        2>/dev/null || true
}

s0=$(stats)

cleanup() {
    trap - INT TERM HUP EXIT
    # The sqlcmd processes run inside the container: stop them there, then the loops.
    $ENGINE exec "$C" pkill -f -- '-H (billing|reminders|web)-[0-9]' 2>/dev/null || true
    kill $(jobs -p) 2>/dev/null || true
    $ENGINE exec -i "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I >/dev/null 2>&1 <<'SQL' || true
DECLARE @k nvarchar(max) = N'';
SELECT @k += N'KILL ' + CAST(session_id AS nvarchar(10)) + N'; '
FROM sys.dm_exec_sessions
WHERE host_name LIKE N'billing-%' OR host_name LIKE N'reminders-%' OR host_name LIKE N'web-%';
EXEC (@k);
SQL
    s1=$(stats)
    for q in reminders web; do
        read -r _ e0 d0 w0 _ <<<"$(grep "^$q " <<<"$s0" || echo "$q 0 0 0 0")"
        read -r _ e1 d1 w1 m1 <<<"$(grep "^$q " <<<"$s1" || echo "$q 0 0 0 0")"
        e=$(( e1 - e0 ))
        if (( e > 0 )); then
            echo "$q: $e queries, mean duration $(( (d1 - d0) / e / 1000 )) ms, mean processor $(( (w1 - w0) / e )) us, longest since the plan was cached $(( m1 / 1000 )) ms"
        fi
    done
    for r in billing-1 billing-2; do
        echo "$r: $(grep -c 'AV20' "$LOGDIR/$r.out" 2>/dev/null || true) credit notes," \
             "$(grep -c 'Msg 2627' "$LOGDIR/$r.err" 2>/dev/null || true) duplicate key errors (2627)"
    done
    echo "Load stopped. Messages in $LOGDIR."
}
trap cleanup INT TERM HUP EXIT

billing billing-1 7500 &
sleep 1.5
billing billing-2 6500 &
reminders reminders-1 &
web web-1 &
web web-2 &
echo "Load running on $DB for $DURATION s: billing-1 and billing-2 issue credit notes, reminders-1 refreshes the reminders screen, web-1 and web-2 display invoices. Ctrl+C stops it."
sleep "$DURATION" &
wait $!
