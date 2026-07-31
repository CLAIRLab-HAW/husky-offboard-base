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
_prefix="${1:-container}"

if [ "${RMW_IMPLEMENTATION:-}" != "rmw_zenoh_cpp" ]; then
    echo "[${_prefix}] RMW=${RMW_IMPLEMENTATION:-unset} (kein Zenoh) -> kein Router."
elif [ "${ZENOH_LOCAL:-0}" = "1" ]; then
    echo "[${_prefix}] nutze robot-lokalen Zenoh-Router (localhost:7447) -> kein eigener Router."
elif [ "${ZENOH_STANDALONE:-0}" = "1" ]; then
    echo "[${_prefix}] starte rmw_zenohd (standalone, isolierter Graph, :7447)"
    ros2 run rmw_zenoh_cpp rmw_zenohd >/tmp/zenohd.log 2>&1 &
    sleep 3
elif [ -n "${ROBOT_ZENOH_ENDPOINT:-}" ]; then
    cat > /tmp/router_config.json5 <<EOF
{ mode: "router", connect: { endpoints: ["${ROBOT_ZENOH_ENDPOINT}"] } }
EOF
    export ZENOH_ROUTER_CONFIG_URI=/tmp/router_config.json5
    echo "[${_prefix}] starte rmw_zenohd -> ${ROBOT_ZENOH_ENDPOINT}"
    ros2 run rmw_zenoh_cpp rmw_zenohd >/tmp/zenohd.log 2>&1 &
    sleep 3
else
    echo "[${_prefix}] WARN: ROBOT_ZENOH_ENDPOINT nicht gesetzt -> keine Verbindung zum Roboter."
fi
