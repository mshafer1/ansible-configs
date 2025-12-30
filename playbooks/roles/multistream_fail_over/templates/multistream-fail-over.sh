#!/bin/bash
set -euo pipefail
trap 'echo "Error occurred on line $LINENO"; exit 1' ERR

mkdir -p /var/tmp/multistreamer
chmod 777 /var/tmp/multistreamer || true
pushd /var/tmp/multistreamer

#----------------------------------------------------------
# main loop, stream to first URL. 
#  If it fails, stream to second, then monitor for first to come back.
#  When/if first comes back for min_stable_time, kill second
#----------------------------------------------------------
{% set alphabet = "abcdefghijklmnopqrstuvwxyz" %}
{% for push in _multistream_fail_over__pushes %}

{% set bandwidth_arg = '' %}
{% if 'bandwidth' in push %}
{% set bandwidth_arg = push.bandwidth %}
{% endif %}

{% set fps_arg = 30 %}
{% if 'framerate' in push %}
{% set fps_arg = push.framerate %}
{% endif %}

{% if 'scale' not in push %}
{% set scale_args = 'copy' %}
{% else %}
{% set scale_args %}libx264 -crf {{ fps_arg }} -vf scale={{ push.scale }} -preset veryfast -tune zerolatency -g {{ fps_arg * 2 }} -keyint_min {{ fps_arg * 4 }} -sc_threshold 0 {% endset %}
{% endif %}
prog_{{ alphabet[loop.index0] }}='ffmpeg -i rtmp://localhost/live -c:a copy -c:v {{ scale_args }} -f flv -probesize 32 -analyzeduration 0 -fflags nobuffer -rw_timeout 50000 -progress ./progress_{{ alphabet[loop.index0] }} {{ push.url }}'
# these don't help?? -stats_period 1 -reconnect 1 -reconnect_streamed 1 -reconnect_delay_max 5
{% endfor %}

cleanup() {
    echo "Shutting down..."
    kill $(jobs -p) 2>/dev/null
    # also clean up any rogue ffmpeg streams
    ps -aux | grep ffmpeg | grep -v grep | sed -e 's/  */ /g' | cut -d' ' -f2 | xargs -I{} bash -c 'kill -9 {}'
    exit
}
trap cleanup SIGINT SIGTERM TERM


get_a_progress_time() {
modify_timestamp=$(stat progress_a | grep Modify; exit 0);
echo "${modify_timestamp}"
}


A_PID=""
B_PID=""
last_a_progress=""
a_is_running=""
DURATION=0
a_is_old_counter=0

while true; do
    if [[ -z "$A_PID" ]]; then
      echo "Starting A..."
      $prog_a 2> _log_a >&1 &
      A_PID=$!
      echo "A PID: $A_PID"
      A_Started=$SECONDS
      sleep 2
      last_a_progress=$(get_a_progress_time)
      a_is_old_counter=0
    fi

    current_a_progress=$(get_a_progress_time)
    echo "Current is ${current_a_progress}"
    echo "Last    is ${last_a_progress}"
    DURATION=$(( SECONDS - A_Started ))
    echo "Duration is $DURATION"
    if [[ "${last_a_progress}" == "${current_a_progress}" ]] && [[ "$DURATION" -gt 10 ]]; then
      a_is_old_counter=$(( a_is_old_counter + 1))
    else
      a_is_old_counter=0
    fi
    if [[ -n "${current_a_progress}" ]] && [ "${a_is_old_counter}" -gt "5" ]; then
      echo "A is hung, killing it"
      kill -9 "$A_PID" || true # don't die if we fail to kill
      A_PID=""
    fi
    if [[ -n "$A_PID" ]] && (kill -0 $A_PID 2>/dev/null) && [[ "${a_is_old_counter}" -lt "5" ]]; then # A is alive
      # shut down B  if it's still going
      echo "Checking if should shut down B -> $B_PID"
      if [[ "$DURATION" -ge 15 ]] && [[ -n "$B_PID" ]] && (kill -0 $B_PID 2>/dev/null); then
        echo "A is stable. Stopping B..."
        kill -9 "$B_PID" || true
        B_PID=""
      fi
    else
      echo "A is dead, checking to start B"
      if [[ -z "$B_PID" ]] || ( ! kill -0 $B_PID 2>/dev/null ); then
        echo "Starting B..."
        $prog_b > _log_b 2>&1 &
        B_PID=$!
        echo "B PID: $B_PID"
      fi
    fi
    last_a_progress="${current_a_progress}"

    # Small delay before trying to restart A
    echo "sleeping for a moment"
    sleep 1
done
