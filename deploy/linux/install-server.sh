#!/usr/bin/env bash
set -Eeuo pipefail

REPO_ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)

APP_USER=${APP_USER:-${SUDO_USER:-$(id -un)}}
APP_GROUP=${APP_GROUP:-$(id -gn "$APP_USER")}
APP_HOME=${APP_HOME:-$(getent passwd "$APP_USER" | cut -d: -f6)}
PROXY_PORT=${PROXY_PORT:-18080}
VNC_PORT=${VNC_PORT:-5900}
NOVNC_PORT=${NOVNC_PORT:-6080}
DISPLAY_NUMBER=${DISPLAY_NUMBER:-99}
SCREEN_GEOMETRY=${SCREEN_GEOMETRY:-1280x800x24}
NOVNC_USER=${NOVNC_USER:-superadmin}
CODEX_HOME=${CODEX_HOME:-$APP_HOME/.codex}
RELAY_URL=${RELAY_URL:-}

usage() {
    cat <<'EOF'
Usage: sudo [VARIABLE=value ...] bash deploy/linux/install-server.sh

Variables:
  APP_USER          Linux user that owns the Codex config (default: SUDO_USER/root)
  PROXY_PORT        Local MITM proxy port (default: 18080)
  VNC_PORT          Localhost VNC port (default: 5900)
  NOVNC_PORT        Public noVNC HTTP port (default: 6080)
  DISPLAY_NUMBER    Xvfb display number (default: 99)
  SCREEN_GEOMETRY   Virtual screen, e.g. 1280x800x24
  NOVNC_USER        HTTP Basic Auth username (default: superadmin)
  RELAY_URL         Optional upstream API URL
  SKIP_BUILD=1      Install an existing src-tauri/target/release binary
EOF
}

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

need_root() {
    [[ ${EUID} -eq 0 ]] || die "run this installer with sudo or as root"
}

valid_uint() {
    [[ "$1" =~ ^[0-9]+$ ]] && (( 1 <= 10#$1 && 10#$1 <= 65535 ))
}

valid_user() {
    [[ "$1" =~ ^[a-z_][a-z0-9_-]*$ ]]
}

escape_sed() {
    printf '%s' "$1" | sed 's/[&|\\]/\\&/g'
}

render_unit() {
    local source=$1 destination=$2
    sed \
        -e "s|@APP_USER@|$(escape_sed "$APP_USER")|g" \
        -e "s|@APP_GROUP@|$(escape_sed "$APP_GROUP")|g" \
        -e "s|@APP_HOME@|$(escape_sed "$APP_HOME")|g" \
        -e "s|@CODEX_HOME@|$(escape_sed "$CODEX_HOME")|g" \
        -e "s|@PROXY_PORT@|$(escape_sed "$PROXY_PORT")|g" \
        -e "s|@VNC_PORT@|$(escape_sed "$VNC_PORT")|g" \
        -e "s|@NOVNC_PORT@|$(escape_sed "$NOVNC_PORT")|g" \
        -e "s|@DISPLAY_NUMBER@|$(escape_sed "$DISPLAY_NUMBER")|g" \
        -e "s|@SCREEN_GEOMETRY@|$(escape_sed "$SCREEN_GEOMETRY")|g" \
        "$source" > "$destination"
}

install_packages() {
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y \
        build-essential curl file libssl-dev patchelf \
        libwebkit2gtk-4.1-dev libgtk-3-dev \
        libayatana-appindicator3-dev librsvg2-dev libxdo-dev \
        xvfb openbox x11vnc novnc websockify dbus-x11 \
        openssl python3 git
}

install_node() {
    local node_major=0
    if command -v node >/dev/null 2>&1; then
        node_major=$(node --version | sed -E 's/^v([0-9]+).*/\1/')
    fi
    if (( node_major >= 18 )); then
        command -v npm >/dev/null 2>&1 || apt-get install -y npm
        return
    fi
    local nodesource_tmp
    nodesource_tmp=$(mktemp)
    curl -fsSL https://deb.nodesource.com/setup_20.x -o "$nodesource_tmp"
    chmod 700 "$nodesource_tmp"
    bash "$nodesource_tmp"
    rm -f "$nodesource_tmp"
    apt-get install -y nodejs
    command -v npm >/dev/null 2>&1 || die "npm was not installed with Node.js"
}

install_rust() {
    if [[ -x "$APP_HOME/.cargo/bin/cargo" ]]; then
        return
    fi
    local rustup_tmp
    rustup_tmp=$(mktemp)
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs -o "$rustup_tmp"
    chown "$APP_USER":"$APP_GROUP" "$rustup_tmp"
    chmod 700 "$rustup_tmp"
    runuser -u "$APP_USER" -- env HOME="$APP_HOME" sh "$rustup_tmp" -y --profile minimal --default-toolchain stable
    rm -f "$rustup_tmp"
}

build_and_install() {
    if [[ ${SKIP_BUILD:-0} != 1 ]]; then
        command -v npm >/dev/null 2>&1 || die "npm was not installed"
        runuser -u "$APP_USER" -- test -w "$REPO_ROOT" || \
            die "repository must be writable by APP_USER ($APP_USER): $REPO_ROOT"
        runuser -u "$APP_USER" -- env \
            HOME="$APP_HOME" \
            PATH="$APP_HOME/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
            bash -lc "cd $(printf '%q' "$REPO_ROOT") && npm ci && CI=true npx tauri build --no-bundle"
    fi
    [[ -x "$REPO_ROOT/src-tauri/target/release/super-instruct" ]] || \
        die "release binary not found; remove SKIP_BUILD=1 or build it first"
    install -m 0755 "$REPO_ROOT/src-tauri/target/release/super-instruct" /usr/bin/super-instruct
}

write_auth() {
    local auth_file=/etc/super-instruct/novnc.auth
    if [[ ! -s "$auth_file" ]]; then
        local password
        password=$(openssl rand -hex 18)
        printf '%s:%s\n' "$NOVNC_USER" "$password" > "$auth_file"
        printf 'Generated noVNC credentials: %s:%s\n' "$NOVNC_USER" "$password"
    else
        printf 'Keeping existing noVNC credentials in %s\n' "$auth_file"
    fi
    chown root:"$APP_GROUP" "$auth_file"
    chmod 0640 "$auth_file"
}

main() {
    if [[ ${1:-} == --help || ${1:-} == -h ]]; then
        usage
        exit 0
    fi
    [[ $# -eq 0 ]] || die "unknown argument: $1"
    need_root
    [[ -r /etc/os-release ]] || die "unsupported Linux distribution"
    . /etc/os-release
    [[ ${ID:-} == ubuntu || ${ID_LIKE:-} == *debian* ]] || \
        die "this installer currently supports Ubuntu/Debian systems"
    id "$APP_USER" >/dev/null 2>&1 || die "unknown APP_USER: $APP_USER"
    valid_user "$APP_USER" || die "unsupported APP_USER name: $APP_USER"
    [[ -n "$APP_HOME" && -d "$APP_HOME" ]] || die "could not resolve APP_HOME for $APP_USER"
    for port in "$PROXY_PORT" "$VNC_PORT" "$NOVNC_PORT"; do
        valid_uint "$port" || die "invalid port: $port"
    done
    [[ "$DISPLAY_NUMBER" =~ ^[0-9]+$ ]] || die "invalid DISPLAY_NUMBER: $DISPLAY_NUMBER"
    [[ "$SCREEN_GEOMETRY" =~ ^[0-9]+x[0-9]+x(8|16|24|32)$ ]] || die "invalid SCREEN_GEOMETRY: $SCREEN_GEOMETRY"
    [[ "$NOVNC_USER" =~ ^[A-Za-z0-9_.-]+$ ]] || die "invalid NOVNC_USER"

    install_packages
    install_node
    install_rust
    build_and_install

    install -d -m 0750 -o "$APP_USER" -g "$APP_GROUP" /var/lib/super-instruct
    install -d -m 0750 -o root -g "$APP_GROUP" /etc/super-instruct
    install -d -m 0755 /usr/local/libexec
    install -m 0755 "$REPO_ROOT/deploy/linux/super-instruct-desktop-inner.sh" \
        /usr/local/libexec/super-instruct-desktop-inner
    install -m 0755 "$REPO_ROOT/deploy/linux/super-instruct-novnc.sh" \
        /usr/local/libexec/super-instruct-novnc
    install -m 0644 "$REPO_ROOT/deploy/linux/super_instruct_auth.py" \
        /usr/local/libexec/super_instruct_auth.py
    install -m 0755 "$REPO_ROOT/deploy/linux/super-instruct-restore-codex.py" \
        /usr/local/libexec/super-instruct-restore-codex

    write_auth
    cat > /etc/super-instruct/server.env <<EOF
PROXY_PORT=$PROXY_PORT
VNC_PORT=$VNC_PORT
NOVNC_PORT=$NOVNC_PORT
DISPLAY_NUMBER=$DISPLAY_NUMBER
EOF
    chown root:"$APP_GROUP" /etc/super-instruct/server.env
    chmod 0640 /etc/super-instruct/server.env

    for unit in xvfb gui vnc novnc; do
        render_unit "$REPO_ROOT/deploy/linux/systemd/super-instruct-$unit.service.in" \
            "/etc/systemd/system/super-instruct-$unit.service"
    done

    if [[ -n "$RELAY_URL" ]]; then
        [[ -f "$CODEX_HOME/config.toml" ]] || die "RELAY_URL was supplied but $CODEX_HOME/config.toml does not exist"
        install -d -m 0700 -o "$APP_USER" -g "$APP_GROUP" "$CODEX_HOME"
        printf '%s\n' "$RELAY_URL" > "$CODEX_HOME/relay_url.txt"
        chown "$APP_USER":"$APP_GROUP" "$CODEX_HOME/relay_url.txt"
        chmod 0600 "$CODEX_HOME/relay_url.txt"
    fi

    systemctl daemon-reload
    systemctl enable super-instruct-xvfb.service super-instruct-gui.service \
        super-instruct-vnc.service super-instruct-novnc.service
    systemctl restart super-instruct-novnc.service

    printf '\nSuper-Instruct server installation complete.\n'
    printf 'Browser URL: http://SERVER_IP:%s/vnc.html?autoconnect=1&resize=remote&path=websockify\n' "$NOVNC_PORT"
    printf 'Credentials file: /etc/super-instruct/novnc.auth\n'
    printf 'Proxy listener: 127.0.0.1:%s\n' "$PROXY_PORT"
    printf 'Services: systemctl status super-instruct-xvfb super-instruct-gui super-instruct-vnc super-instruct-novnc\n'
}

main "$@"
