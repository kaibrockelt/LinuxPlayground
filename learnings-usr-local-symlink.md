# Learnings: `/usr/local` ist ein Symlink — und das killt dein Image

## Das exakte Problem

In bootc/Silverblue-basierten Images ist `/usr/local` **kein echtes Verzeichnis**, sondern ein Symlink:

```
/usr/local -> ../var/usrlocal
```

Das bedeutet: `/usr/local` zeigt auf `/var/usrlocal`.

`/var` ist ein **separates Mount**, das beim Systemstart als leeres Verzeichnis überlagert wird ("overlaid"). Alles, was per `COPY` im Containerfile nach `/usr/local/bin/` geschrieben wird, landet zwar im Image-Layer — aber nach dem Reboot ist es weg, weil `/var` das überschreibt.

### Symptom

```
systemd service schlägt mit EXEC 203 fehl
→ Script nicht gefunden: /usr/local/bin/firefox-flatpak-cert-import.sh
```

Das Script war im Image vorhanden, aber nach dem Reboot nicht mehr erreichbar.

### Fix

Ziel von `/usr/local/bin/` auf `/usr/bin/` ändern — `/usr` ist der unveränderliche, read-only Tree des Images und wird korrekt persistiert.

```dockerfile
# Falsch:
COPY files/firefox/firefox-flatpak-cert-import.sh /usr/local/bin/

# Richtig:
COPY files/firefox/firefox-flatpak-cert-import.sh /usr/bin/
```

Gleiches gilt für den Systemd-Service, der auf den Pfad verweist.

---

## Wo das gleiche Problem noch auftreten kann

Überall, wo Dateien in Pfade geschrieben werden, die über `/var` gemountet oder per Symlink dorthin umgeleitet werden. In bootc/Silverblue-Images betrifft das:

| Pfad | Warum problematisch |
|---|---|
| `/usr/local/bin/` | Symlink → `/var/usrlocal/bin` → nach Reboot leer |
| `/usr/local/lib/` | Gleicher Symlink |
| `/usr/local/share/` | Gleicher Symlink |
| `/usr/local/etc/` | Gleicher Symlink |
| `/var/` direkt | Wird beim Boot als leeres tmpfs/overlay gemountet |
| `/tmp/` | Flüchtig, klar — aber im Containerfile manchmal als Zwischenpfad genutzt |
| `/home/` | Wird nicht im Image-Layer persistiert |
| `/root/` | Ebenfalls über `/var/roothome` oder ähnlich gemountet |
| `/opt/` | Je nach Distro ebenfalls ein Symlink auf `/var` |

### Konkrete Szenarien wo man reintappt

- **Systemd-Services**, die ein Script unter `/usr/local/bin/` aufrufen → EXEC 203
- **Shell-Skripte oder Configs**, die per `COPY` nach `/usr/local/etc/` landen → nach Reboot weg
- **Binaries aus Drittquellen** (z.B. manuell heruntergeladen), die nach `/usr/local/bin/` installiert werden → funktionieren im Build, nicht im laufenden System
- **Homebrew** (`/home/linuxbrew/`) → liegt unter `/home`, das nicht im Image-Layer ist → nur auf dem laufenden System verfügbar, nicht im Image reproduzierbar

---

## Faustregel für bootc-Images

> Alles, was dauerhaft im Image sein soll, muss unter `/usr/` (nicht `/usr/local/`) oder `/etc/` landen — und zwar in Pfaden, die **keine Symlinks auf `/var`** sind.

Zur Sicherheit vor einem `COPY` prüfen:

```bash
# Im laufenden System nachschauen ob ein Pfad ein Symlink ist:
readlink -f /usr/local
# → /var/usrlocal  (= Problem!)

readlink -f /usr/bin
# → /usr/bin  (= OK)
```
