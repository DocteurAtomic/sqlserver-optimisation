#!/usr/bin/env bash
# Module 5, the planning team and the mailing job at work. Runs on the lab, after
# 00-setup.sql.
# Duration: DURATION seconds (1800 by default), or until Ctrl+C.
# Sessions, each one a sqlcmd connection that sends one batch after the other:
#   - planning-1: moves sessions 17699 and 17651 from one room to the other and back,
#     through Course.ChangeRoom, one call after the other;
#   - mail-1: the mailing job, sends the joining instructions of the same two sessions
#     through Enrollment.SendJoiningInstructions, one session every two seconds.
# A batch that a deadlock rolls back (error 1205) is lost; the session goes on with the
# next one. The errors are counted in the files planning-1.err and mail-1.err of the
# folder given by LOGDIR (a temporary folder by default), printed at the end.
# Cleanup: on exit (end of DURATION, Ctrl+C), the trap stops the sqlcmd processes in the
# container and the loops, then kills any SQL session left whose host name starts with
# planning- or mail-. The procedures change only flags and rooms of the two sessions.
# Usage: ./demos/module_05/charge.sh
#   With Podman: ENGINE=podman ./demos/module_05/charge.sh
#   DB=<name> runs the load on another copy of the base.
set -euo pipefail
ENGINE=${ENGINE:-docker}
DB=${DB:-PachadataTraining}
DURATION=${DURATION:-1800}
LOGDIR=${LOGDIR:-$(mktemp -d)}
C=sqloptcourse

# One sqlcmd session, fed by its standard input, with a host name that names its role.
# The messages of the server (error 1205 among them) go to <role>.err.
session() {
    $ENGINE exec -i $C /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I -r1 \
        -d "$DB" -H "$1" >/dev/null 2>"$LOGDIR/$1.err"
}

planning() {
    local a=81 b=186
    while :; do
        printf 'EXEC Course.ChangeRoom @SessionId = 17699, @TrainingRoomId = %d;\nGO\n' $a
        printf 'EXEC Course.ChangeRoom @SessionId = 17651, @TrainingRoomId = %d;\nGO\n' $b
        if [ $a -eq 81 ]; then a=80 b=181; else a=81 b=186; fi
    done | session "$1"
}

mailing() {
    while :; do
        printf 'EXEC Enrollment.SendJoiningInstructions @SessionId = 17699;\nWAITFOR DELAY %s;\nGO\n' "'00:00:02'"
        printf 'EXEC Enrollment.SendJoiningInstructions @SessionId = 17651;\nWAITFOR DELAY %s;\nGO\n' "'00:00:02'"
    done | session "$1"
}

cleanup() {
    trap - INT TERM HUP EXIT
    # The sqlcmd processes run inside the container: stop them there, then the loops.
    $ENGINE exec $C pkill -f -- '-H (planning|mail)-[0-9]' 2>/dev/null || true
    kill $(jobs -p) 2>/dev/null || true
    $ENGINE exec -i $C /opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -C -I >/dev/null 2>&1 <<'EOF' || true
DECLARE @k nvarchar(max) = N'';
SELECT @k += N'KILL ' + CAST(session_id AS nvarchar(10)) + N'; '
FROM sys.dm_exec_sessions
WHERE host_name LIKE N'planning-%' OR host_name LIKE N'mail-%';
EXEC (@k);
EOF
    for r in planning-1 mail-1; do
        echo "$r: $(grep -c 'Msg 1205' "$LOGDIR/$r.err" 2>/dev/null || true) deadlock errors (1205)"
    done
    echo "Load stopped. Messages in $LOGDIR."
}
trap cleanup INT TERM HUP EXIT

planning planning-1 &
mailing mail-1 &
echo "Load running on $DB for $DURATION s: planning-1 moves two sessions, mail-1 sends their joining instructions. Ctrl+C stops it."
sleep "$DURATION" &
wait $!
