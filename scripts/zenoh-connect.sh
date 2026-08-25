#!/usr/bin/env bash
# zenoh-connect.sh <role> — THE one zenoh router logic for every container in deploy/.
#
# Every container speaks zenoh, mock included, so this file does not decide WHETHER there is a router but WHICH
# graph it joins:
#
#   ZENOH_LOCAL=1                 -> no router of our own: the container runs ON the robot (network_mode: host)
#                                    and uses the robot's router on localhost:7447 (a second one would collide on
#                                    port 7447)
#   ZENOH_STANDALONE=1            -> a local rmw_zenohd WITHOUT connect endpoints: an isolated graph.  This is what
#                                    stands in for the robot in the mock profile, and it is what ISOLATES it --
#                                    measured 2026-08-25 with three containers on one compose bridge: a router
#                                    with connect endpoints saw the standalone router's topic, a second standalone
#                                    router on the same bridge saw nothing but /rosout and /parameter_events.
#   ROBOT_ZENOH_ENDPOINT set      -> a local rmw_zenohd that connects to that router: the real robot over LAN or
#                                    netbird, or the mock-robot container in the mock profile.  Same topology in
#                                    both cases, only the host differs -- which is the point.
#   otherwise                     -> WARN, no router.  Nodes still start (rmw_zenoh_cpp says so itself: "Proceeding
#                                    with initialization but other peers will not discover ...") and see nobody.
#
# The isolation above rests on multicast scouting being OFF.  It is off by default -- the shipped
# DEFAULT_RMW_ZENOH_ROUTER_CONFIG.json5 says `enabled: false` with the comment "ROS setting: disable multicast
# discovery by default" -- but a default that a safety property depends on gets written down rather than inherited,
# so both configs below state it. deploy/husky-offboard/tests/test_zenoh_isolation.py pins that down.
#
# Sourced OR executed (starts the router as a background process; log: /tmp/zenohd.log). ROS must already be
# sourced (ros2 CLI).

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
# The role of the calling container, in the NAME column rather than in front of
# every message -- see the same block in start-desktop.sh. The default keeps
# the previous name for a caller that passes nothing.
_prefix="${1:-base}"
clearlog_name "${_prefix}.zenoh"

# Wait for OUR OWN router to accept connections.  A fixed sleep would be either too short -- nodes start, find no
# router, log "Proceeding with initialization" and then never discover anything -- or wasted time.  A remote PEER
# coming up later is a different problem and not this file's: zenoh retries a configured connect endpoint
# indefinitely, so the link forms whenever the other side appears.
_await_router() {
    local i
    for i in $(seq 1 "${ZENOH_ROUTER_WAIT_S:-20}"); do
        # The connect attempt runs in a SUBSHELL, so the descriptor never reaches the caller -- this file is
        # sourced as often as it is executed, and a stray fd 3 in an entrypoint outlives everything it starts.
        if (exec 3<>/dev/tcp/127.0.0.1/7447) 2>/dev/null; then
            log_debug "local router accepting on :7447 after %ss" "$i"
            return 0
        fi
        sleep 1
    done
    log_warn "local rmw_zenohd did not accept on :7447 within %ss -- see /tmp/zenohd.log." \
        "${ZENOH_ROUTER_WAIT_S:-20}"
    return 1
}

if [ "${RMW_IMPLEMENTATION:-}" != "rmw_zenoh_cpp" ]; then
    # Not a supported mode any more, but worth saying out loud rather than starting a router nobody talks to.
    log_warn "RMW=%s is not zenoh -> no router started. This container will not see the rest of the stack." \
        "${RMW_IMPLEMENTATION:-unset}"
elif [ "${ZENOH_LOCAL:-0}" = "1" ]; then
    log_info "using the robot-local zenoh router (localhost:7447) -> no router of our own."
elif [ "${ZENOH_STANDALONE:-0}" = "1" ]; then
    cat > /tmp/router_config.json5 <<EOF
{ mode: "router", scouting: { multicast: { enabled: false } } }
EOF
    export ZENOH_ROUTER_CONFIG_URI=/tmp/router_config.json5
    log_info "starting rmw_zenohd (standalone, isolated graph, :7447)"
    ros2 run rmw_zenoh_cpp rmw_zenohd >/tmp/zenohd.log 2>&1 &
    _await_router
elif [ -n "${ROBOT_ZENOH_ENDPOINT:-}" ]; then
    cat > /tmp/router_config.json5 <<EOF
{ mode: "router", connect: { endpoints: ["${ROBOT_ZENOH_ENDPOINT}"] }, scouting: { multicast: { enabled: false } } }
EOF
    export ZENOH_ROUTER_CONFIG_URI=/tmp/router_config.json5
    log_info "starting rmw_zenohd -> %s" "${ROBOT_ZENOH_ENDPOINT}"
    ros2 run rmw_zenoh_cpp rmw_zenohd >/tmp/zenohd.log 2>&1 &
    _await_router
else
    log_warn "neither ZENOH_LOCAL, ZENOH_STANDALONE nor ROBOT_ZENOH_ENDPOINT is set -> no router, no peers."
fi
