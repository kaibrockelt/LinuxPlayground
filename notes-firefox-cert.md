# Firefox Flatpak + Custom CA Certificate

## Goal
Get Flatpak Firefox to trust the local Caddy root CA (`caddy-horst-root.crt`) out of the box on Aurora (Fedora Silverblue-based immutable system).

## What's Already in the Image
- Cert installed at: `/etc/pki/ca-trust/source/anchors/caddy-horst-root.crt`
- `update-ca-trust` runs in the Containerfile → system trusts it
- `policies.json` copied to `/usr/lib64/firefox/distribution/policies.json` → covers RPM Firefox
- Current `policies.json` content:
  ```json
  {
    "policies": {
      "ImportEnterpriseRoots": true
    }
  }
  ```

## Why Flatpak Firefox Didn't Work
- Flatpak Firefox is sandboxed — it cannot see `/etc/pki/` by default
- `policies.json` at `/usr/lib64/firefox/distribution/` is not visible to the Flatpak sandbox
- The user config path `~/.var/app/org.mozilla.firefox/config/mozilla/firefox/policies.json` is NOT a valid policies location for Firefox

## What Was Done Live (on current running system)

### 1. Flatpak filesystem override
Grants Firefox read access to the cert path:
```bash
flatpak override --user --filesystem=/etc/pki/ca-trust/source/anchors:ro org.mozilla.firefox
```
To undo:
```bash
flatpak override --user --nofilesystem=/etc/pki/ca-trust/source/anchors org.mozilla.firefox
```

### 2. policies.json in user config (turned out not to be the fix)
```bash
# Written to: ~/.var/app/org.mozilla.firefox/config/mozilla/firefox/policies.json
# Content includes Certificates.Install pointing to the cert
# This location is NOT read by Firefox — can be ignored/removed
```

### 3. Cert imported directly into profile cert9.db (the actual fix)
Used `certutil` from brew (`nss` package) to import the cert:
```bash
CERTUTIL=/home/linuxbrew/.linuxbrew/bin/certutil
$CERTUTIL -A -n 'Caddy Local Authority' -t 'CT,,' \
  -i /etc/pki/ca-trust/source/anchors/caddy-horst-root.crt \
  -d sql:~/.var/app/org.mozilla.firefox/config/mozilla/firefox/q3icjnv3.default-release/
```
Both profiles updated:
- `q3icjnv3.default-release`
- `3dqnr6u6.default`

To verify:
```bash
/home/linuxbrew/.linuxbrew/bin/certutil -L \
  -d sql:~/.var/app/org.mozilla.firefox/config/mozilla/firefox/q3icjnv3.default-release/ | grep -i caddy
```

To remove (rollback):
```bash
$CERTUTIL -D -n 'Caddy Local Authority' \
  -d sql:~/.var/app/org.mozilla.firefox/config/mozilla/firefox/q3icjnv3.default-release/
```

## Tools Installed
- `brew install nss` → provides `certutil` at `/home/linuxbrew/.linuxbrew/bin/certutil`

## Baked-in Solution (current state in image)

### Files added to repo
- `files/firefox/firefox-flatpak-cert-import.sh` → copied to `/usr/local/bin/`
  - Runs `certutil` to import the cert into all Firefox Flatpak profiles on login
  - Skips if cert already present (idempotent)
- `files/firefox/firefox-flatpak-cert-import.service` → copied to `/usr/lib/systemd/user/`
  - Enabled globally via `systemctl --global enable` in Containerfile
  - Runs the script once per user session
- `files/flatpak/overrides/org.mozilla.firefox` → copied to `/etc/flatpak/overrides/`
  - Grants Flatpak Firefox read access to `/etc/pki/ca-trust/source/anchors`

### Live changes removed before build
- Cert removed from `cert9.db` in both profiles
- User-level Flatpak override removed
- Stray `~/.var/app/org.mozilla.firefox/config/mozilla/firefox/policies.json` removed

### To rollback
Revert the Containerfile to before the "4. flatpak firefox" block and remove the three files above.
