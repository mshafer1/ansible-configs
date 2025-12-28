#!/bin/bash
set -euo pipefail
trap 'echo "Error occurred on line $LINENO"; exit 1' ERR

mkdir -p /var/tmp/multistreamer
chmod 777 /var/tmp/multistreamer
pushd /var/tmp/multistreamer

clear_routes() {
    # cleanup any from last time
    routes=$(ip route | grep "scope link" | grep -v -e " src " -e "/" | grep -v -E -e "^10\." -e "^172\.1[6-9]\." -e "^172\.2\d\." -e "^172\.3[01]\." -e "^192.168."; exit 0)
    if [[ -z "${routes}" ]]; then
      echo "No old routes identified"
      return
    fi

    echo "$routes" | sed -e 's/ link linkdown/ link/g' -e 's/ $//g' | xargs -I{} bash -c "ip route delete {}"
}


#----------------------------------------------------------
# clear routes from any previous runs
#----------------------------------------------------------
clear_routes

#----------------------------------------------------------
# get IPs for pushes and set routes
#----------------------------------------------------------
update_routes() {
ip_links=$(ip --json link show | jq -r '.[] | .ifname')
# TODO: this only works if devices are already connected..., i.e., needs to run on slow schedule
{% for push in _multistream_fail_over__pushes %}
ip_addresses=$(nslookup `echo "{{ push.url }}" \
    | sed -r -e 's;^.*://;;' -e 's;/.*$;;g'` \
    | sed -n -e '/answer:/,$p' \
    | grep Address \
    | cut -d' ' -f2
)

if [[ -n '{{ push.interface_grep | default("") }}' ]]; then
    interface=$(echo ${ip_links} | tr ' ' '\n' | grep -E '{{ push.interface_grep | default(".*") }}')
    gateway=$(ip route | grep 'default via' | grep -E '{{ push.interface_grep | default(".*") }}' | sed -E -e 's/^.* via //g' -e 's/ dev .*$//g'; exit 0)
    if [[ -n "${gateway}" ]]; then
      echo "${ip_addresses}" | tr ' ' '\n' | xargs -I {} bash -c "ip route add {} via ${gateway} dev ${interface} || true"
    fi
fi


{% endfor %}
}

update_routes

# setup interval
(
  while true; do
    update_routes
    sleep 30
  done
) &

#----------------------------------------------------------
# main loop, stream to first URL. 
#  If it fails, stream to second, then monitor for first to come back.
#  When/if first comes back for min_stable_time, kill second
#----------------------------------------------------------
{% set alphabet = "abcdefghijklmnopqrstuvwxyz" %}
{% for push in _multistream_fail_over__pushes %}
prog_{{ alphabet[loop.index0] }}='ffmpeg -i rtmp://localhost/live -c:a copy -c:v libx264 -preset veryfast -tune zerolatency -g 60 -keyint_min 60 -sc_threshold 0 -vf scale={{ push.scale }} -f flv -probesize 32 -analyzeduration 0 {{ push.url }}'
{% endfor %}

cleanup() {
    echo "Shutting down..."
    kill $(jobs -p) 2>/dev/null
    exit
}
trap cleanup SIGINT SIGTERM

A_PID=""
B_PID=""

while true; do
    if [[ -z "$A_PID" ]] || ( ! kill -0 $A_PID 2>/dev/null); then
      echo "Starting A..."
      $prog_a 2> /dev/null >&1 &
      A_PID=$!
      echo "A PID: $A_PID"
      A_Started=$SECONDS
      sleep 1
    fi

    DURATION=$(( SECONDS - A_Started ))
    if (kill -0 $A_PID 2>/dev/null); then # A is alive
      # shut down B  if it's still going
      if [[ "$DURATION" -ge 10 ]] && [[ -n "$B_PID" ]] &&  ! (kill -0 $B_PID 2>/dev/null); then
        echo "A is stable. Stopping B..."
        kill -9 "$B_PID" 2>/dev/null
        B_PID=""
      fi
    else
      if [[ -z "$B_PID" ]] || ( ! kill -0 $B_PID 2>/dev/null); then
        echo "Starting B..."
        $prog_b > /dev/null 2>&1 &
        B_PID=$!
        echo "B PID: $B_PID"
      fi
    fi

    # Small delay before trying to restart A
    sleep 1
done
