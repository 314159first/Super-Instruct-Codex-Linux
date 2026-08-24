#!/usr/bin/env bash
set -euo pipefail

openbox --sm-disable &
wm_pid=$!

cleanup() {
    kill "$wm_pid" 2>/dev/null || true
    wait "$wm_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

/usr/bin/super-instruct &
app_pid=$!
wait "$app_pid"
