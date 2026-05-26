#!/bin/bash
# =============================================================================
# Splunk Universal Forwarder - Install / Upgrade Script
# Secureon d.o.o.
#
# Supports: fresh install and in-place upgrade
# Package:  local binary only (no internet access required)
# OS:       Debian/Ubuntu (.deb) and RHEL/CentOS/Rocky (.rpm)
# Run as:   root
# =============================================================================

set -euo pipefail

### Variables — edit before deploying
SPLUNK_UF_VERSION_RPM="splunkforwarder-10.0.4-5ea723e837ec.x86_64.rpm"
SPLUNK_UF_VERSION_DEB="splunkforwarder-10.0.4-5ea723e837ec-linux-amd64.deb"
DEPLOYMENT_SERVER="10.220.64.10"     # IP or hostname of your Splunk Deployment Server
DEPLOYMENT_PORT="8089"
INSTALL_DIR="/opt"
SPLUNK_TEMPADMINPASS="StrongPassword123."  # Used only on fresh install, deleted after start
RECONCILE_CONFIG=1                 # 1 = re-assert deploymentclient.conf even when version matches
### End variables


# =============================================================================
# Internals — do not edit below this line
# =============================================================================
SPLUNK_HOME="$INSTALL_DIR/splunkforwarder"
SPLUNK_BIN="$SPLUNK_HOME/bin/splunk"
LOG_FILE="/var/log/splunkuf-install.log"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Redirect all output to log file AND stdout.
exec > >(tee -a "$LOG_FILE") 2>&1

echo ""
echo "============================================"
echo " Splunk UF Install/Upgrade Script"
echo " $(date '+%Y-%m-%d %H:%M:%S')"
echo " Host: $(hostname)"
echo "============================================"

# --- Central failure handler -------------------------------------------------
fail() {
    echo "ERROR: $*" >&2
    exit 1
}

# --- Sanity guard for destructive paths --------------------------------------
case "$SPLUNK_HOME" in
    ""|"/"|"/opt"|"/usr"|"/var"|"/etc"|"/home")
        fail "Refusing to run: SPLUNK_HOME resolves to a dangerous path ('$SPLUNK_HOME')."
        ;;
esac
[ "${SPLUNK_HOME#/}" != "$SPLUNK_HOME" ] || fail "SPLUNK_HOME must be an absolute path ('$SPLUNK_HOME')."

# --- Root check ---
[ "$(id -u)" = "0" ] || fail "This script must be run as root."

# --- Detect OS package manager and set binary path ---
if command -v dpkg > /dev/null 2>&1; then
    PKG_TYPE="deb"
    PKG_FILE="$SCRIPT_DIR/$SPLUNK_UF_VERSION_DEB"
elif command -v rpm > /dev/null 2>&1; then
    PKG_TYPE="rpm"
    PKG_FILE="$SCRIPT_DIR/$SPLUNK_UF_VERSION_RPM"
else
    fail "Unsupported OS — neither dpkg nor rpm found."
fi
echo "INFO: Detected package type: $PKG_TYPE"

# --- Verify binary exists next to the script ---
[ -f "$PKG_FILE" ] || fail "Package file not found: $PKG_FILE. Place the installer in the same directory as this script."
echo "INFO: Package file found: $PKG_FILE"

# --- Detect init system (systemd vs init.d) ---
INIT_PROC="$(ps --no-headers -o comm 1 2>/dev/null || true)"
if [ "$INIT_PROC" = "systemd" ]; then
    USE_SYSTEMD=1
    echo "INFO: Init system detected: systemd"
else
    USE_SYSTEMD=0
    echo "INFO: Init system detected: init.d (SysV)"
fi

# --- Extract target version/build from package filename ---
TARGET_VERSION="$(echo "$PKG_FILE" | grep -oP 'splunkforwarder-\K[0-9]+\.[0-9]+\.[0-9]+' || true)"
TARGET_BUILD="$(echo "$PKG_FILE"   | grep -oP 'splunkforwarder-[0-9.]+-\K[a-f0-9]+' || true)"
[ -n "$TARGET_VERSION" ] || fail "Could not parse target version from package filename."
[ -n "$TARGET_BUILD" ]   || fail "Could not parse target build from package filename."
echo "INFO: Target version: $TARGET_VERSION  build: $TARGET_BUILD"


# --- Helper functions --------------------------------------------------------
write_deploymentclient() {
    install -d -m 755 "$SPLUNK_HOME/etc/system/local"
    cat > "$SPLUNK_HOME/etc/system/local/deploymentclient.conf" <<EOF
[target-broker:deploymentServer]
targetUri = ${DEPLOYMENT_SERVER}:${DEPLOYMENT_PORT}
EOF
    echo "INFO: deploymentclient.conf set -> ${DEPLOYMENT_SERVER}:${DEPLOYMENT_PORT}"
}

stop_splunk() {
    echo "INFO: Stopping Splunk UF..."
    if [ "$USE_SYSTEMD" = "1" ] && systemctl is-active SplunkForwarder >/dev/null 2>&1; then
        systemctl stop SplunkForwarder || echo "WARNING: systemctl stop failed, attempting binary fallback."
    fi
    "$SPLUNK_BIN" stop || echo "WARNING: 'splunk stop' returned non-zero (may already be stopped)."
    sleep 2
}

start_splunk() {
    echo "INFO: Starting Splunk UF..."
    if [ "$USE_SYSTEMD" = "1" ]; then
        # Accept license and handle initialization via CLI first
        "$SPLUNK_BIN" start --no-prompt --accept-license --answer-yes || fail "Failed initialization via CLI."
        systemctl start SplunkForwarder || fail "Splunk UF failed to start via systemd."
    else
        "$SPLUNK_BIN" start --no-prompt --accept-license --answer-yes || fail "Splunk UF failed to start."
    fi
}

enable_boot_start() {
    if [ "$USE_SYSTEMD" = "1" ]; then
        if [ -f /etc/systemd/system/SplunkForwarder.service ]; then
            echo "INFO: systemd unit already present — skipping boot-start regeneration."
        else
            "$SPLUNK_BIN" enable boot-start -systemd-managed 1 --no-prompt --accept-license --answer-yes
        fi
        systemctl daemon-reload
        systemctl enable SplunkForwarder 2>/dev/null || true
    else
        "$SPLUNK_BIN" enable boot-start -systemd-managed 0 --no-prompt --accept-license --answer-yes
    fi
}


# --- Determine fresh install vs upgrade ---
IS_FRESH_INSTALL=1
IS_UPGRADE=0
VERSION_MATCH=0

if [ -f "$SPLUNK_BIN" ]; then
    MANIFEST="$(find "$SPLUNK_HOME" -maxdepth 1 -name '*-manifest' 2>/dev/null | head -1)"
    if [ -n "$MANIFEST" ]; then
        MANIFEST_NAME="$(basename "$MANIFEST")"
        CURRENT_VERSION="$(echo "$MANIFEST_NAME" | grep -oP 'splunkforwarder-\K[0-9]+\.[0-9]+\.[0-9]+' || true)"
        CURRENT_BUILD="$(echo "$MANIFEST_NAME" | grep -oP 'splunkforwarder-[0-9.]+-\K[a-f0-9]+' || true)"
        echo "INFO: Currently installed version: ${CURRENT_VERSION:-unknown}  build: ${CURRENT_BUILD:-unknown}"

        if [ -n "$CURRENT_VERSION" ] && [ -n "$CURRENT_BUILD" ] \
           && [ "$CURRENT_VERSION" = "$TARGET_VERSION" ] && [ "$CURRENT_BUILD" = "$TARGET_BUILD" ]; then
            echo "INFO: Target version matches the currently deployed binary version."
            if [ "$RECONCILE_CONFIG" = "1" ]; then
                echo "INFO: Configuration reconciliation enabled (RECONCILE_CONFIG=1)."
                VERSION_MATCH=1
                IS_FRESH_INSTALL=0
            else
                echo "INFO: Nothing to do. Exiting."
                exit 0
            fi
        else
            echo "INFO: Upgrade required: ${CURRENT_VERSION:-unknown} --> $TARGET_VERSION"
            IS_FRESH_INSTALL=0
            IS_UPGRADE=1
        fi
    else
        echo "WARNING: Splunk binary found but manifest is missing — handling as an upgrade to safeguard state."
        IS_FRESH_INSTALL=0
        IS_UPGRADE=1
    fi
else
    echo "INFO: No existing Splunk UF installation found. Running fresh install."
fi


# =============================================================================
# PATH 1: CONFIG RECONCILE ONLY
# =============================================================================
if [ "$VERSION_MATCH" = "1" ]; then
    write_deploymentclient
    echo "INFO: Restarting UF to apply configuration updates."
    if [ "$USE_SYSTEMD" = "1" ]; then
        systemctl restart SplunkForwarder || fail "Failed to restart Splunk via systemd."
    else
        "$SPLUNK_BIN" restart || fail "Failed to restart Splunk via binary."
    fi
    echo "INFO: Config reconcile complete successfully."
    exit 0
fi


# =============================================================================
# PATH 2: UPGRADE
# =============================================================================
if [ "$IS_UPGRADE" = "1" ]; then
    echo ""
    echo "--- Upgrade: Stopping current daemon safely ---"
    stop_splunk

    echo "--- Upgrade: Installing package updates ---"
    if [ "$PKG_TYPE" = "deb" ]; then
        dpkg -i "$PKG_FILE" || fail "Package upgrade failed (dpkg)."
    else
        rpm -Uvh --replacepkgs "$PKG_FILE" || fail "Package upgrade failed (rpm)."
    fi

    echo "--- Upgrade: Applying consistent ownership metrics ---"
    chown -R root:root "$SPLUNK_HOME"

    echo "--- Upgrade: Starting modern binaries ---"
    start_splunk

    echo "--- Upgrade: Verifying system boot hooks ---"
    enable_boot_start
fi


# =============================================================================
# PATH 3: FRESH INSTALLATION
# =============================================================================
if [ "$IS_FRESH_INSTALL" = "1" ]; then
    echo ""
    echo "--- Fresh install: Executing package deploy ---"
    if [ "$PKG_TYPE" = "deb" ]; then
        dpkg -i "$PKG_FILE" || fail "Package installation failed (dpkg)."
    else
        rpm -ivh "$PKG_FILE" || fail "Package installation failed (rpm)."
    fi

    echo "--- Fresh install: Setting core configurations ---"
    write_deploymentclient

    echo "--- Fresh install: Injecting transient user-seed configuration ---"
    cat > "$SPLUNK_HOME/etc/system/local/user-seed.conf" <<EOF
[user_info]
USERNAME = admin
PASSWORD = ${SPLUNK_TEMPADMINPASS}
EOF
    chmod 600 "$SPLUNK_HOME/etc/system/local/user-seed.conf"

    echo "--- Fresh install: Restricting directory path permissions ---"
    chown -R root:root "$SPLUNK_HOME"

    echo "--- Fresh install: Starting daemon ---"
    start_splunk

    echo "--- Fresh install: Removing user-seed credentials ---"
    rm -f "$SPLUNK_HOME/etc/system/local/user-seed.conf"

    echo "--- Fresh install: Configuring boot persistent scripts ---"
    enable_boot_start
fi


# =============================================================================
# FINAL FUNCTIONAL SANITY VERIFICATION
# =============================================================================
echo ""
echo "--- Performing runtime status validation ---"
sleep 5

STATUS_OUT="$("$SPLUNK_BIN" status 2>&1 || true)"
echo "$STATUS_OUT"

if echo "$STATUS_OUT" | grep -qiE 'splunkd .*(is running|running \()' \
   || pgrep -f "$SPLUNK_HOME/bin/splunkd" > /dev/null 2>&1; then
    echo ""
    echo "============================================"
    if [ "$IS_UPGRADE" = "1" ]; then
        echo " Splunk UF upgraded successfully."
    else
        echo " Splunk UF installed successfully."
    fi
    echo " Version Target: $TARGET_VERSION"
    echo " Deployment Server: ${DEPLOYMENT_SERVER}:${DEPLOYMENT_PORT}"
    echo " System Engine: $([ "$USE_SYSTEMD" -eq 1 ] && echo 'systemd' || echo 'init.d')"
    echo " Log Output Saved: $LOG_FILE"
    echo "============================================"
else
    fail "Splunk UF daemon failed to register as active following script procedures."
fi