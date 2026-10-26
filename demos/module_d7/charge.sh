#!/usr/bin/env bash
# Module D7, the night of the PachaData server, then the day after. Runs on the lab, after
# 00-setup.sql.
# Usage:
#   ENGINE=podman ./demos/module_d7/charge.sh         the night (DURATION seconds, 360 by default)
#   ENGINE=podman ./demos/module_d7/charge.sh day     the day after the fix (DURATION, 120 by default)
#   ENGINE=podman ./demos/module_d7/charge.sh stop    ends the two sessions the night leaves behind
#   ENGINE: docker (default) or podman. DB=<name> runs the load on another copy of the base.
#   The container provides SQLCMDPASSWORD, as the compose.yaml of the lab sets it.
# The night. Sessions, each one a sqlcmd connection named by its host name:
#   - accounting-ssms: the accountant postpones by 30 days the due date of the invoices of
#     October 2026, in a transaction, then leaves her SSMS window open without committing.
#     The session stays open after the night: it is the one the morning has to find.
#   - payments-import: the import of the bank file, which records the payments of October
#     and September through Enrollment.RecordPayment, one after the other. It stays blocked
#     on the first invoice the accountant changed, and stays there after the night.
#   - web-pay-1, web-pay-2: the customer area, where customers pay an unpaid invoice of September
#     or October, with the 30-second command timeout of the application: a blocked payment is
#     abandoned after 30 s ("Timeout expired") and the next customer comes.
#   - elearning-import: the import of the e-learning events, 30,000 rows into
#     Elearning.Activity every 3 seconds, in their own transactions.
#   - backoffice-1: the back office looks for contacts by last name
#     (Contact.GetContactByName), rare names, a call every 50 ms.
#   - maintenance: after 90 seconds, the night maintenance rebuilds the indexes of
#     Contact.Contact, then the deduplication job looks for N'Simon' first. The back office
#     pauses for these few seconds, so that the order of the calls is the same on every run.
# The day after (argument "day"): the same back office, customer area and e-learning import,
# without the accountant, the import of the bank file or the maintenance.
# At the end, it prints the calls of the back office and their mean reads, the payments
# made and abandoned, the e-learning batches, and the log of the database.
# Messages of the server are in the files <role>.out and <role>.err of LOGDIR (a temporary
# folder by default).
# Cleanup: at the end of the night or of the day (or on Ctrl+C), the trap stops the loops of
# this run. After the night, accounting-ssms and payments-import keep running on purpose;
# "charge.sh stop" ends them (the accountant's transaction is rolled back), as does the KILL
# of demos/module_d7/03a-the-fix.sql. The rows written stay in the base: 00-setup.sql
# restores it.
set -euo pipefail
ENGINE=${ENGINE:-docker}
C=${CONTAINER:-sqloptcourse}
DB=${DB:-PachadataTraining}
MODE=${1:-night}
LOGDIR=${LOGDIR:-$(mktemp -d)}
mkdir -p "$LOGDIR"

sql() {  # usage: sql <host name> [sqlcmd options]: one session fed by its standard input
    local h=$1; shift
    $ENGINE exec -i "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I -r1 \
        -d "$DB" -H "$h" "$@"
}

if [ "$MODE" = stop ]; then
    $ENGINE exec "$C" pkill -f -- '-H (accounting-ssms|payments-import)' 2>/dev/null || true
    pkill -f "charge-d7-hold" 2>/dev/null || true
    sql d7-stop -h -1 -W -Q "SET NOCOUNT ON;
DECLARE @k nvarchar(max) = N'';
SELECT @k += N'KILL ' + CAST(session_id AS nvarchar(10)) + N'; '
FROM sys.dm_exec_sessions WHERE host_name IN (N'accounting-ssms', N'payments-import');
EXEC (@k);
SELECT COUNT(*) AS sessions_left FROM sys.dm_exec_sessions
WHERE host_name IN (N'accounting-ssms', N'payments-import');" 2>/dev/null || true
    exit 0
fi

if [ "$MODE" = night ]; then DURATION=${DURATION:-360}; else DURATION=${DURATION:-120}; fi

# The accountant's window: the batch runs, then the session waits, transaction open, for as
# long as the background "sleep" keeps its standard input open (a long time).
accounting() {
    { printf '%s\n' \
"BEGIN TRANSACTION;" \
"UPDATE Enrollment.Invoice SET DueDate = DATEADD(DAY, 30, DueDate)" \
"WHERE InvoiceDate >= '20261001' AND DocumentType = 'I';" \
"GO"
      exec -a charge-d7-hold sleep 86400; } | sql accounting-ssms >"$LOGDIR/accounting-ssms.out" 2>&1
}

# The bank file: the unpaid invoices of September and October, oldest first.
payments_import() {
    printf '%s\n' \
"SET NOCOUNT ON;" \
"DECLARE @c varchar(50);" \
"DECLARE bank CURSOR LOCAL FAST_FORWARD FOR" \
"    SELECT InvoiceCode FROM Enrollment.vInvoiceBalance" \
"    WHERE InvoiceDate >= '20260901' AND Status IN ('UNPAID', 'PENDING', 'PARTIAL')" \
"    ORDER BY InvoiceDate, InvoiceCode;" \
"OPEN bank; FETCH NEXT FROM bank INTO @c;" \
"WHILE @@FETCH_STATUS = 0" \
"BEGIN" \
"    EXEC Enrollment.RecordPayment @InvoiceCode = @c, @Amount = 1.00," \
"         @PaymentMethodCode = 'WIRE', @PaymentDate = '20261018';" \
"    FETCH NEXT FROM bank INTO @c;" \
"END;" \
"CLOSE bank; DEALLOCATE bank;" \
"GO" | sql payments-import >"$LOGDIR/payments-import.out" 2>"$LOGDIR/payments-import.err"
}

# The customer area: one payment, then the next customer. 30 s timeout per command.
web_pay() {  # usage: web_pay <role> <seed>
    local n=$2
    while :; do
        printf "DECLARE @c varchar(50) = (SELECT InvoiceCode FROM Enrollment.vInvoiceBalance WHERE InvoiceDate >= '20260901' AND Status IN ('UNPAID', 'PENDING', 'PARTIAL') ORDER BY InvoiceCode OFFSET %d ROWS FETCH NEXT 1 ROWS ONLY);\nEXEC Enrollment.RecordPayment @InvoiceCode = @c, @Amount = 1.00, @PaymentMethodCode = 'CARD', @PaymentDate = '20261018';\nGO\n" \
            $(( (n * 7919) % 800 ))
        n=$(( n + 1 ))
        sleep 0.5
    done | sql "$1" -t 30 >"$LOGDIR/$1.out" 2>"$LOGDIR/$1.err"
}

elearning() {
    local b=0
    while :; do
        printf '%s\n' \
"SET NOCOUNT ON;" \
"DECLARE @base bigint = (SELECT MAX(ActivityId) FROM Elearning.Activity);" \
"INSERT Elearning.Activity (ActivityId, EventTime, ContactId, EnrollmentId, ModuleId," \
"       EventTypeCode, Step, DurationSeconds, Score, Device)" \
"SELECT @base + ROW_NUMBER() OVER (ORDER BY ActivityId), DATEADD(YEAR, 1, EventTime)," \
"       ContactId, EnrollmentId, ModuleId, EventTypeCode, Step, DurationSeconds, Score, Device" \
"FROM Elearning.Activity" \
"WHERE ActivityId > $(( b * 30000 )) AND ActivityId <= $(( (b + 1) * 30000 ));" \
"PRINT 'batch';" \
"WAITFOR DELAY '00:00:03';" "GO"
        b=$(( b + 1 ))
    done | sql elearning-import >"$LOGDIR/elearning-import.out" 2>"$LOGDIR/elearning-import.err"
}

# The names the back office looks for: 400 rare names, as in module 4.
backoffice() {  # usage: backoffice <role> <seconds>
    {
        printf '%s\n' "SET NOCOUNT ON; SET ARITHABORT ON;" \
"CREATE TABLE #Names (n int IDENTITY PRIMARY KEY, LastName nvarchar(50));" \
"INSERT #Names (LastName) SELECT TOP (400) LastName FROM Contact.Contact" \
"GROUP BY LastName HAVING COUNT(*) <= 3 ORDER BY LastName;" \
"CREATE TABLE #Sink (LastName varchar(50), FirstName varchar(50), Email varchar(150)," \
"                    Phone varchar(15), Fax varchar(15));" \
"GO"
        local end=$(( SECONDS + $2 )) i=0
        while (( SECONDS < end )); do
            printf "DECLARE @name nvarchar(50) = (SELECT LastName FROM #Names WHERE n = %d);\nINSERT #Sink EXEC Contact.GetContactByName @LastName = @name;\nTRUNCATE TABLE #Sink;\nWAITFOR DELAY '00:00:00.050';\nGO\n" $(( i % 400 + 1 ))
            i=$(( i + 1 ))
        done
    } | sql "$1" >"$LOGDIR/$1.out" 2>"$LOGDIR/$1.err"
}

maintenance() {
    printf '%s\n' "SET NOCOUNT ON; SET ARITHABORT ON;" \
"ALTER INDEX ALL ON Contact.Contact REBUILD;" \
"PRINT 'indexes rebuilt';" \
"GO" \
"CREATE TABLE #Sink (LastName varchar(50), FirstName varchar(50), Email varchar(150)," \
"                    Phone varchar(15), Fax varchar(15));" \
"INSERT #Sink EXEC Contact.GetContactByName @LastName = N'Simon';" \
"PRINT 'deduplication: Simon';" \
"GO" | sql maintenance >"$LOGDIR/maintenance.out" 2>&1
}

stats() {  # calls and mean reads of the back office, log of the base
    sql d7-stats -h -1 -W -Q "SET NOCOUNT ON;
SELECT 'backoffice', ISNULL(SUM(execution_count), 0), ISNULL(SUM(total_logical_reads), 0)
FROM sys.dm_exec_procedure_stats
WHERE database_id = DB_ID() AND object_id = OBJECT_ID(N'Contact.GetContactByName');
SELECT 'log', CAST(total_log_size_in_bytes / 1048576 AS int), CAST(used_log_space_in_percent AS int)
FROM sys.dm_db_log_space_usage;
SELECT 'reuse', log_reuse_wait_desc, 0 FROM sys.databases WHERE name = DB_NAME();" 2>/dev/null || true
}

cleanup() {
    trap - INT TERM HUP EXIT
    $ENGINE exec "$C" pkill -f -- '-H (web-pay|elearning-import|backoffice|maintenance)' 2>/dev/null || true
    for j in $(jobs -p); do kill "$j" 2>/dev/null || true; done
    s1=$(stats)
    read -r _ e0 r0 <<<"$(grep '^backoffice ' <<<"$s0")"
    read -r _ e1 r1 <<<"$(grep '^backoffice ' <<<"$s1")"
    # The plan cache restarts its counters when the plan is recompiled (the rebuild).
    if (( e1 >= e0 )); then e=$(( e1 - e0 )); r=$(( r1 - r0 )); else e=$e1; r=$r1; fi
    echo "backoffice: $e calls in the plan cached now, mean reads $(( e > 0 ? r / e : 0 ))"
    for w in web-pay-1 web-pay-2; do
        echo "$w: $(grep -c 'PaymentId' "$LOGDIR/$w.out" 2>/dev/null || true) payments," \
             "$(grep -c 'Timeout expired' "$LOGDIR/$w.err" 2>/dev/null || true) abandoned after 30 s"
    done
    echo "elearning-import: $(grep -c '^batch' "$LOGDIR/elearning-import.err" 2>/dev/null || true) batches of 30,000 rows"
    read -r _ size used <<<"$(grep '^log ' <<<"$s1")"
    echo "log: $size MB, $used % used, waiting for: $(grep '^reuse ' <<<"$s1" | awk '{print $2}')"
    if [ "$MODE" = night ]; then
        echo "Left running on purpose: accounting-ssms (transaction open) and payments-import."
        echo "End them with: ENGINE=$ENGINE ./demos/module_d7/charge.sh stop"
    fi
    echo "Messages in $LOGDIR."
}

s0=$(stats)
trap cleanup INT TERM HUP EXIT

if [ "$MODE" = night ]; then
    (accounting &) ; sleep 2
    (payments_import &) ; sleep 1
fi
web_pay web-pay-1 1 &
web_pay web-pay-2 500 &
elearning &
if [ "$MODE" = night ]; then
    echo "The night on $DB for $DURATION s: accounting-ssms, payments-import, web-pay-1 and 2, elearning-import, backoffice-1; maintenance after 90 s."
    backoffice backoffice-1 90
    maintenance
    s0=$(stats)
    backoffice backoffice-1 $(( DURATION - 95 )) &
else
    echo "The day on $DB for $DURATION s: web-pay-1 and 2, elearning-import, backoffice-1."
    backoffice backoffice-1 "$DURATION" &
fi
wait $!
