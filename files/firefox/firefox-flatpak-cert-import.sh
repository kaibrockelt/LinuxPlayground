#!/bin/bash
# Imports the local CA cert into all Flatpak Firefox profiles.
# Run once at login via systemd user service.

CERT="/etc/pki/ca-trust/source/anchors/caddy-horst-root.crt"
CERT_NAME="Caddy Local Authority"
CERTUTIL="/usr/bin/certutil"
FF_DIR="$HOME/.var/app/org.mozilla.firefox/config/mozilla/firefox"

[ -f "$CERT" ] || exit 0
[ -x "$CERTUTIL" ] || exit 1
[ -d "$FF_DIR" ] || exit 0

for profile in "$FF_DIR"/*.default-release "$FF_DIR"/*.default; do
    [ -f "$profile/cert9.db" ] || continue
    # Skip if already imported
    $CERTUTIL -L -d "sql:$profile" | grep -q "$CERT_NAME" && continue
    $CERTUTIL -A -n "$CERT_NAME" -t 'CT,,' -i "$CERT" -d "sql:$profile"
done
