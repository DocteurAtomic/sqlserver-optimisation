#!/usr/bin/env bash
# Module D3, the new version of the PachaData website. Runs on the lab, after 00-setup.sql.
# Sessions: 8 sqlcmd connections (website-1 to website-8) that send one batch after the
# other, as the website does when a page is displayed. Two pages, picked at random:
#   - the learner's account page: the contact, its company, its address and its city
#     (Contact.Contact, Contact.Company, Contact.Address, Reference.City), for one of the
#     120,140 contacts;
#   - the page a learner reaches from a link in a campaign e-mail: the e-mail, its
#     campaign and the contact (Marketing.Delivery, Marketing.Campaign, Contact.Contact),
#     for one of the 4,018,304 e-mails sent.
#   The website writes the identifier into the text of the query (string concatenation), so
#   each identifier makes a different text. This is the problem of the module.
# Duration: DURATION seconds (600 by default), or until Ctrl+C.
# At the end, it prints the batches the instance received per second during the load, and
# what the container used of its processor quota (cgroup v2, /sys/fs/cgroup/cpu.stat).
# Cleanup: on exit (end of DURATION, Ctrl+C), the trap stops the sqlcmd processes in the
# container and the loops, then kills any SQL session left whose host name starts with
# website-. Nothing is written to the database.
# Usage: ENGINE=podman ./demos/module_d3/charge.sh
#   ENGINE: docker (default) or podman. CONTAINER: sqloptcourse by default (the video uses
#   its throwaway copy, sqlopt-d3). DB=<name> runs the load on another copy of the base.
#   The container provides SQLCMDPASSWORD, as the compose.yaml of the lab sets it.
set -euo pipefail
ENGINE=${ENGINE:-docker}
C=${CONTAINER:-sqloptcourse}
DB=${DB:-PachadataTraining}
DURATION=${DURATION:-600}
SESSIONS=8

# One sqlcmd session, fed by its standard input, with a host name that names its role.
session() {
    $ENGINE exec -i "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I \
        -d "$DB" -H "$1" >/dev/null 2>&1
}

website() {
    local id
    while :; do
        if (( RANDOM % 2 )); then
            id=$(( (RANDOM * 32768 + RANDOM) % 120140 + 1 ))
            printf '%s\n' \
"SELECT c.ContactId, c.FirstName, c.LastName, c.Email, co.Name AS Company, a.Address1, ci.CityName AS City" \
"FROM Contact.Contact AS c" \
"LEFT JOIN Contact.Company AS co ON co.CompanyId = c.CompanyId" \
"JOIN Contact.Address AS a ON a.AddressId = c.PostalAddressId" \
"LEFT JOIN Reference.City AS ci ON ci.CityId = a.CityId" \
"WHERE c.ContactId = $id;" "GO"
        else
            id=$(( (RANDOM * 32768 + RANDOM) % 4018304 + 1 ))
            printf '%s\n' \
"SELECT d.DeliveryId, d.SendDate, d.Opened, ca.Name AS Campaign, ca.CampaignType, c.FirstName, c.LastName" \
"FROM Marketing.Delivery AS d" \
"JOIN Marketing.Campaign AS ca ON ca.CampaignId = d.CampaignId" \
"JOIN Contact.Contact AS c ON c.ContactId = d.ContactId" \
"WHERE d.DeliveryId = $id;" "GO"
        fi
    done | session "$1"
}

cpustat() {  # usage_usec of the container, 0 if unreadable
    $ENGINE exec "$C" cat /sys/fs/cgroup/cpu.stat 2>/dev/null \
        | awk '$1=="usage_usec"{u=$2} END{print u+0}' || echo 0
}

batches() {  # Batch Requests/sec, a cumulative counter
    $ENGINE exec -i "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I -h -1 -W \
        -Q "SET NOCOUNT ON; SELECT cntr_value FROM sys.dm_os_performance_counters WHERE counter_name = N'Batch Requests/sec';" \
        2>/dev/null | tr -d '[:space:]' || echo 0
}

start=$(date +%s)
u0=$(cpustat)
b0=$(batches)

cleanup() {
    trap - INT TERM HUP EXIT
    # The sqlcmd processes run inside the container: stop them there, then the loops.
    $ENGINE exec "$C" pkill -f -- '-H website-[0-9]' 2>/dev/null || true
    kill $(jobs -p) 2>/dev/null || true
    $ENGINE exec -i "$C" /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I >/dev/null 2>&1 <<'SQL' || true
DECLARE @k nvarchar(max) = N'';
SELECT @k += N'KILL ' + CAST(session_id AS nvarchar(10)) + N'; '
FROM sys.dm_exec_sessions
WHERE host_name LIKE N'website-%';
EXEC (@k);
SQL
    u1=$(cpustat); b1=$(batches)
    s=$(( $(date +%s) - start ))
    if [ "$s" -gt 0 ] && [ "${u1:-0}" -gt 0 ]; then
        awk -v u=$(( u1 - u0 )) -v b=$(( b1 - b0 )) -v s=$s 'BEGIN {
            printf "Load stopped after %d s: %.0f batches per second; container CPU %.1f processors on average.\n", s, b/s, u/1e6/s }'
    else
        echo "Load stopped."
    fi
}
trap cleanup INT TERM HUP EXIT

for n in $(seq 1 $SESSIONS); do website "website-$n" & done
echo "Load running on $DB for $DURATION s: $SESSIONS website sessions. Ctrl+C stops it."
sleep "$DURATION" &
wait $!
