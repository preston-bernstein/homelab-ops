#!/bin/bash
# Detects Synology ContainerManager going down, attempts an auto-restart,
# and notifies ntfy at every state transition. Runs as root via cron every
# 5 minutes on the NAS. See ../README.md for the full pipeline this feeds.
set -u

NTFY_URL="http://10.0.0.250:8090/nas-infra"
STATE_FILE="/var/services/homes/agent/.cm-watchdog.state"
LOCK_FILE="/var/services/homes/agent/.cm-watchdog.lock"
STILL_DOWN_REMINDER_SECS=1800   # 30 min between repeat "still down" alerts
SYNOPKG=/usr/syno/bin/synopkg

exec 200>"$LOCK_FILE"
flock -n 200 || exit 0   # a previous run is still in flight, skip this tick

# --- state ---
LAST_STATUS="unknown"
INCIDENT_ID=""
LAST_ALERT_TS=0
RESTART_ATTEMPTED=0
# shellcheck disable=SC1090
[ -f "$STATE_FILE" ] && source "$STATE_FILE"

save_state() {
    cat > "$STATE_FILE" <<EOF
LAST_STATUS="$LAST_STATUS"
INCIDENT_ID="$INCIDENT_ID"
LAST_ALERT_TS=$LAST_ALERT_TS
RESTART_ATTEMPTED=$RESTART_ATTEMPTED
EOF
}

notify() {
    # notify TITLE MESSAGE TAGS [PRIORITY]
    local title="$1" message="$2" tags="$3" priority="${4:-default}"
    curl -sS -m 10 \
        -H "Title: ${title}" \
        -H "Tags: ${tags}" \
        -H "Priority: ${priority}" \
        -d "${message}" \
        "$NTFY_URL" >/dev/null 2>&1
}

notify_incident_detected() {
    # Machine-readable trigger the desktop poller filters on via ?tags=incident-detected.
    local incident_id="$1"
    curl -sS -m 10 \
        -H "Title: ContainerManager incident $incident_id" \
        -H "Tags: incident-detected" \
        -H "Priority: high" \
        -d "{\"event\":\"incident-detected\",\"incident_id\":\"${incident_id}\",\"host\":\"nas\",\"summary\":\"ContainerManager auto-stopped, restart attempted\"}" \
        "$NTFY_URL" >/dev/null 2>&1
}

current_status() {
    "$SYNOPKG" status ContainerManager 2>/dev/null | grep -o '"status":"[a-z]*"' | head -1 | cut -d'"' -f4
}

now() { date +%s; }

STATUS="$(current_status)"
[ -z "$STATUS" ] && STATUS="stop"   # treat unparseable output as down, safest default

if [ "$STATUS" = "running" ]; then
    if [ "$LAST_STATUS" != "running" ] && [ -n "$INCIDENT_ID" ]; then
        notify "✅ ContainerManager restored" \
            "Back up after incident ${INCIDENT_ID}." \
            "white_check_mark"
    fi
    LAST_STATUS="running"
    INCIDENT_ID=""
    RESTART_ATTEMPTED=0
    LAST_ALERT_TS=0
    save_state
    exit 0
fi

# STATUS is down/starting/anything-not-running
if [ "$LAST_STATUS" = "running" ] || [ -z "$INCIDENT_ID" ]; then
    # fresh incident
    INCIDENT_ID="$(now)"
    LAST_ALERT_TS="$(now)"
    notify "⚠️ ContainerManager down on NAS" \
        "Detected status=${STATUS}. Attempting auto-restart (incident ${INCIDENT_ID})." \
        "warning" "high"
    notify_incident_detected "$INCIDENT_ID"
    "$SYNOPKG" start ContainerManager >/dev/null 2>&1 &
    disown
    RESTART_ATTEMPTED=1
    LAST_STATUS="$STATUS"
    save_state
    exit 0
fi

# ongoing incident, still down — debounced reminder only
ELAPSED=$(( $(now) - LAST_ALERT_TS ))
if [ "$ELAPSED" -ge "$STILL_DOWN_REMINDER_SECS" ]; then
    notify "❌ ContainerManager still down" \
        "Incident ${INCIDENT_ID} still unresolved (status=${STATUS}). May need manual help." \
        "x" "high"
    LAST_ALERT_TS="$(now)"
fi
LAST_STATUS="$STATUS"
save_state
