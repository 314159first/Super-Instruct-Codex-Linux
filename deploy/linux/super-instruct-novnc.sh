#!/usr/bin/env bash
set -euo pipefail

source /etc/super-instruct/server.env
auth_file=/etc/super-instruct/novnc.auth
test -s "$auth_file"

export PYTHONPATH=/usr/local/libexec${PYTHONPATH:+:$PYTHONPATH}

exec /usr/bin/websockify \
    --web=/usr/share/novnc \
    --web-auth \
    --auth-plugin=super_instruct_auth.FileHTTPAuth \
    --auth-source="$auth_file" \
    --heartbeat=30 \
    "$NOVNC_PORT" "127.0.0.1:$VNC_PORT"
