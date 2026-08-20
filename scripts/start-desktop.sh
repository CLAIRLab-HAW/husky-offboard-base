#!/usr/bin/env bash
# Gemeinsamer noVNC-Desktop-Start (ausgelagert aus husky-offboard/entrypoint.sh
# und husky-offboard-lite/entrypoint.sh, dort bisher byte-identisch).
#
# Startet den virtuellen X-Server + WM + VNC + noVNC-Web-Client, sodass RViz/
# MoveIt im Browser (http://localhost:6080/vnc.html) laufen. Liegt im
# husky-offboard-base-Image und wird von beiden finalen Entrypoints aufgerufen.
#
#   start-desktop.sh [prefix]   prefix = Log-Zeilenprefix (z.B. offboard|lite)
#
# Lies DISPLAY/NOVNC_WIDTH/NOVNC_HEIGHT/VNC_PASSWORD aus dem Environment
# (Defaults: :1 / 1600 / 900 / leer). NOVNC_WIDTH/NOVNC_HEIGHT sind die einzige Quelle fuer die
# Desktop-Aufloesung; die RViz-Window-Geometry wird im jeweiligen Finalimage
# auf dieselben Werte gepatcht, damit das RViz-Fenster nie ueber den Screen
# hinausragt.
set -uo pipefail

if [ -r /usr/local/bin/clearlog.sh ]; then
    . /usr/local/bin/clearlog.sh
else
    log_debug() { :; }
    # shellcheck disable=SC2059
    log_info()  { if [ "$#" -gt 1 ]; then printf "$@" >&2; else printf '%s' "${1:-}" >&2; fi; echo >&2; }
    log_warn()  { log_info "$@"; }
    log_error() { log_info "$@"; }
    log_phase() { log_info "$@"; }
    clearlog_name() { :; }
fi
clearlog_name base.desktop

_prefix="${1:-desktop}"

export DISPLAY="${DISPLAY:-:1}"
export NOVNC_WIDTH="${NOVNC_WIDTH:-1600}"
export NOVNC_HEIGHT="${NOVNC_HEIGHT:-900}"
log_info "[%s] starte virtuellen Desktop auf %s (noVNC :6080, %sx%s)" "${_prefix}" "${DISPLAY}" "${NOVNC_WIDTH}" "${NOVNC_HEIGHT}"

Xvfb "${DISPLAY}" -screen 0 "${NOVNC_WIDTH}x${NOVNC_HEIGHT}x24" -ac >/tmp/xvfb.log 2>&1 &
sleep 1
fluxbox >/tmp/fluxbox.log 2>&1 &

# --- VNC-Authentifizierung --------------------------------------------------
# Ohne Passwort bietet x11vnc genau EINEN Security-Typ an: 1 = "None". Das hat
# zwei Folgen, die zusammen wie ein Netzwerkfehler aussehen und keiner sind:
#
#   * Apples Bildschirmfreigabe (und die "Entfernte Verwaltung") verweigert
#     "None" und meldet nur "Verbindung fehlgeschlagen: Vergewissere dich,
#     dass die Bildschirmfreigabe ... aktiviert ist" -- eine Meldung ueber den
#     ENTFERNTEN Rechner, die in Wahrheit den Handshake meint.
#   * Auf dem Roboter (network_mode: host) bindet x11vnc dann an 127.0.0.1,
#     nicht an 0.0.0.0 -- von aussen also "Connection refused". Am 2026-08-20
#     an a200-0553 gemessen: 6080 offen, 5900 nur auf loopback.
#
# Mit VNC_PASSWORD bietet x11vnc Typ 2 ("VNC Auth") an und lauscht explizit auf
# allen Interfaces. Ohne bleibt alles wie gehabt -- noVNC auf 6080 braucht kein
# Passwort, weil websockify containerintern auf localhost:5900 geht.
# VNC-Passwoerter sind protokollbedingt auf 8 Zeichen begrenzt.
if [ -n "${VNC_PASSWORD:-}" ]; then
    mkdir -p /root/.vnc
    x11vnc -storepasswd "${VNC_PASSWORD}" /root/.vnc/passwd >/dev/null 2>&1
    _vnc_auth=(-rfbauth /root/.vnc/passwd -listen 0.0.0.0)
    log_info "[%s] VNC mit Passwort (Security-Typ 'VNC Auth') -> nativer Viewer/Bildschirmfreigabe moeglich." "${_prefix}"
else
    _vnc_auth=(-nopw)
    log_info "[%s] VNC ohne Passwort (Security-Typ 'None'). Fuer einen nativen Viewer VNC_PASSWORD setzen." "${_prefix}"
fi

x11vnc -display "${DISPLAY}" "${_vnc_auth[@]}" -forever -shared -rfbport 5900 -bg -quiet \
    >/tmp/x11vnc.log 2>&1 || true
# noVNC-Web-Client auf 6080 -> 5900
websockify --web=/usr/share/novnc 6080 localhost:5900 >/tmp/novnc.log 2>&1 &

echo "[${_prefix}] Desktop bereit: http://localhost:6080/vnc.html"
