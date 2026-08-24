#!/usr/bin/env bash
set -Eeuo pipefail

[[ ${EUID} -eq 0 ]] || {
    printf 'error: run this uninstaller with sudo or as root\n' >&2
    exit 1
}

systemctl disable --now \
    super-instruct-novnc.service \
    super-instruct-vnc.service \
    super-instruct-gui.service \
    super-instruct-xvfb.service 2>/dev/null || true

for unit in xvfb gui vnc novnc; do
    rm -f "/etc/systemd/system/super-instruct-$unit.service"
done

rm -f \
    /usr/local/libexec/super-instruct-desktop-inner \
    /usr/local/libexec/super-instruct-novnc \
    /usr/local/libexec/super-instruct-restore-codex \
    /usr/local/libexec/super_instruct_auth.py \
    /usr/bin/super-instruct

if [[ ${PURGE:-0} == 1 ]]; then
    rm -rf /etc/super-instruct /var/lib/super-instruct
else
    printf 'Preserved /etc/super-instruct and /var/lib/super-instruct. Set PURGE=1 to remove them.\n'
fi

systemctl daemon-reload
printf 'Super-Instruct server services removed.\n'
