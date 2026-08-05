#!/usr/bin/env bash
# zenoh-connect.sh <log-prefix> — DIE eine Stelle fuer die Zenoh-Router-Logik
# aller Container (offboard, offboard-lite, app-runner/Demos).
#
# Verhalten (Superset der vier historischen Entrypoint-Bloecke):
#   RMW_IMPLEMENTATION != rmw_zenoh_cpp  -> kein Router (lokaler DDS-Graph, mock)
#   ZENOH_LOCAL=1                        -> kein eigener Router: der Container
#                                           laeuft AUF dem Roboter (network_mode
#                                           host) und nutzt dessen Router auf
#                                           localhost:7447 (zweiter Router wuerde
#                                           mit Port 7447 kollidieren)
#   ZENOH_STANDALONE=1                   -> lokalen rmw_zenohd OHNE connect-
#                                           Endpoints starten: isolierter
#                                           Zenoh-Graph (mock/dev auf derselben
#                                           Middleware wie der Roboter; Workstation-
#                                           Clients joinen via tcp/localhost:7447,
#                                           wenn der Port gepublished ist)
#   ROBOT_ZENOH_ENDPOINT gesetzt         -> lokalen rmw_zenohd starten, der sich
#                                           zum Roboter-Router verbindet (LAN
#                                           oder netbird-Overlay)
#   sonst                                -> WARN, keine Verbindung
#
# Wird gesourct ODER ausgefuehrt (startet den Router als Hintergrundprozess;
# Log: /tmp/zenohd.log). ROS muss bereits gesourct sein (ros2-CLI).

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
clearlog_name base.zenoh

_prefix="${1:-container}"

if [ "${RMW_IMPLEMENTATION:-}" != "rmw_zenoh_cpp" ]; then
    log_info "[%s] RMW=%s (kein Zenoh) -> kein Router." "${_prefix}" "${RMW_IMPLEMENTATION:-unset}"
elif [ "${ZENOH_LOCAL:-0}" = "1" ]; then
    log_info "[%s] nutze robot-lokalen Zenoh-Router (localhost:7447) -> kein eigener Router." "${_prefix}"
elif [ "${ZENOH_STANDALONE:-0}" = "1" ]; then
    log_info "[%s] starte rmw_zenohd (standalone, isolierter Graph, :7447)" "${_prefix}"
    ros2 run rmw_zenoh_cpp rmw_zenohd >/tmp/zenohd.log 2>&1 &
    sleep 3
elif [ -n "${ROBOT_ZENOH_ENDPOINT:-}" ]; then
    cat > /tmp/router_config.json5 <<EOF
{ mode: "router", connect: { endpoints: ["${ROBOT_ZENOH_ENDPOINT}"] } }
EOF
    export ZENOH_ROUTER_CONFIG_URI=/tmp/router_config.json5
    log_info "[%s] starte rmw_zenohd -> %s" "${_prefix}" "${ROBOT_ZENOH_ENDPOINT}"
    ros2 run rmw_zenoh_cpp rmw_zenohd >/tmp/zenohd.log 2>&1 &
    sleep 3
else
    log_warn "[%s] ROBOT_ZENOH_ENDPOINT nicht gesetzt -> keine Verbindung zum Roboter." "${_prefix}"
fi
