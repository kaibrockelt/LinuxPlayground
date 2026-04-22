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

## Status History

### 2026-04-21, ~23:16
- Firefox verhält sich korrekt ✓ (Cert manuell in beide Profile importiert als Sofort-Fix)
- Bestätigt: `/usr/local/bin/firefox-flatpak-cert-import.sh` fehlt im laufenden System → Image ist älter als Commit `75e7f91`
- Systemd user service schlägt mit EXEC 203 fehl (Script nicht gefunden)
- **Fix committed & gepusht**:
  - `build_files/build.sh`: `nss-tools` wird jetzt per RPM installiert → `certutil` unter `/usr/bin/certutil`
  - `files/firefox/firefox-flatpak-cert-import.sh`: Pfad von brew-`certutil` auf `/usr/bin/certutil` geändert

### 2026-04-21, ~23:41
- Push von oben hat nicht funktioniert (upgrade zeigte keine Verbesserung)
- **Root cause gefunden**: `files/flatpak/overrides/org.mozilla.firefox` war korrupt — enthielt `filesystems=/etc/pki/ca-trust/source/anchors:ro;User id: 1000` → Flatpak hat den Override ignoriert
- **Fix**: Datei bereinigt auf:
  ```
  [Context]
  filesystems=/etc/pki/ca-trust/source/anchors:ro
  ```
- **Nächster Schritt**: Commit & push → GitHub Actions Build abwarten → `sudo bootc upgrade` → reboot → prüfen ob Service sauber läuft

### 2026-04-22, ~00:07
- Nach reboot: Service schlägt weiterhin mit EXEC 203 fehl — `/usr/local/bin/firefox-flatpak-cert-import.sh` nicht gefunden
- **Root cause gefunden**: `/usr/local` ist ein Symlink auf `../var/usrlocal` → wird beim Boot als leeres `/var`-Mount überlagert → alles was per `COPY` dorthin geschrieben wird, ist nach dem Reboot weg
- **Fix**: Script-Ziel von `/usr/local/bin/` auf `/usr/bin/` geändert (liegt im unveränderlichen `/usr`-Tree, wird korrekt im Image persistiert)
- Geänderte Dateien: `Containerfile`, `files/firefox/firefox-flatpak-cert-import.service`

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

---

# Branding: Horst_OS!

## Ziel
Eigenes Logo in Boot-Screen (Plymouth) und KDE Splash Screen einbauen, OS-Name auf `Horst_OS!` ändern.

## Dateien

### `files/branding/watermark.png`
- 400x100 PNG, generiert aus `files/horst logo.png` (1080x589) via ImageMagick
- Ziel im Image: `/usr/share/plymouth/themes/spinner/watermark.png`
- Erscheint unten mittig beim Boot-Spinner (Plymouth, `WatermarkVerticalAlignment=.96`)

### `files/branding/horst_logo.svgz`
- 375x375 SVGZ (PNG base64 in SVG, dann gzip), generiert aus `files/horst logo.png`
- Ziel im Image (beide Themes):
  - `/usr/share/plasma/look-and-feel/dev.getaurora.aurora.desktop/contents/splash/images/aurora_logo.svgz`
  - `/usr/share/plasma/look-and-feel/dev.getaurora.auroralight.desktop/contents/splash/images/aurora_logo.svgz`
- Erscheint zentriert im KDE Splash Screen nach Passwort-Eingabe

### `files/os-release`
- Überschreibt `/usr/lib/os-release` (Symlink-Ziel von `/etc/os-release`)
- `PRETTY_NAME="Horst_OS!"` → taucht in GRUB, `bootc status`, `fastfetch`, KDE About auf
- `DEFAULT_HOSTNAME="horst"`
- `ID=aurora` bewusst beibehalten → Aurora-Scripts/Updates laufen weiter

## Containerfile-Blöcke (in dieser Reihenfolge, vor dem lint)
```dockerfile
### OS IDENTITY
COPY files/os-release /usr/lib/os-release

### BRANDING
COPY files/branding/watermark.png /usr/share/plymouth/themes/spinner/watermark.png
COPY files/branding/horst_logo.svgz /usr/share/plasma/look-and-feel/dev.getaurora.aurora.desktop/contents/splash/images/aurora_logo.svgz
COPY files/branding/horst_logo.svgz /usr/share/plasma/look-and-feel/dev.getaurora.auroralight.desktop/contents/splash/images/aurora_logo.svgz
```

## Wichtige Pfad-Notizen
- `/usr/lib/os-release` liegt im unveränderlichen `/usr`-Tree → kein `/var`-Symlink-Problem
- Plymouth-Watermark hat keine feste Größenbeschränkung im Theme-Config, wird in Originalgröße gerendert
- Das Acer-Logo beim Boot kommt vom UEFI-Firmware → nicht anfassbar
- **Plymouth watermark.png muss `-alpha off` haben** — transparente PNGs werden von Plymouth nicht gerendert, es fällt auf das eingebaute Distro-Logo zurück
- GRUB-Eintragstitel kommt **nicht** aus `os-release PRETTY_NAME`, sondern aus dem OCI-Label `org.opencontainers.image.title` im Containerfile
- KDE About This System liest aus `/usr/share/kde-settings/kde-profile/default/xdg/kcm-about-distrorc`, nicht aus os-release

## Status

### 2026-04-22, ~08:42
- `horst_logo.svgz` auf 750x750 verdoppelt (war 375x375) → KDE Splash Logo war zu klein
- `watermark.png` war **komplett transparent** (Alpha-Kanal, alle Pixel alpha=0) → Plymouth zeigte Aurora-Fallback
  - Fix: neu generiert mit `-alpha off -background black` → Logo jetzt sichtbar auf schwarzem Hintergrund
- OCI-Label `org.opencontainers.image.title="Horst_OS!"` im Containerfile ergänzt → GRUB-Eintrag-Titel
- `files/branding/kcm-about-distrorc` neu erstellt → deployed nach `/usr/share/kde-settings/kde-profile/default/xdg/kcm-about-distrorc` → überschreibt hardcoded `Name=Aurora` in KDE About This System
- Commit `04732ec` gepusht → GitHub Actions Build abwarten → `sudo bootc upgrade` + Reboot
- Nach Reboot prüfen:
  - GRUB zeigt "Horst_OS!" im Boot-Menü
  - Plymouth zeigt Horst-Logo unten beim Spinner (nicht mehr transparent)
  - KDE Splash zeigt Horst-Logo größer nach Login
  - KDE About This System zeigt "Horst_OS!" statt "Aurora"
