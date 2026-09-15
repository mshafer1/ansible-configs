#!/bin/bash
set -euo pipefail
trap 'echo "Error occurred on line $LINENO"; exit 1' ERR

mkdir -p /var/tmp/multistreamer
chmod 777 /var/tmp/multistreamer || true
pushd /var/tmp/multistreamer

#----------------------------------------------------------
# get IPs for pushes and set routes
#----------------------------------------------------------
update_routes() {
ip_links=$(ip --json link show | jq -r '.[] | .ifname')
declare -a all_ips=()

# clear the file
echo '' > _route_changes
echo '' > _new_routes

old_routes=$(ip route | grep "via" | grep -v -e " src " -e "/" | grep -v -E -e "^10\." -e "^172\.1[6-9]\." -e "^172\.2\d\." -e "^172\.3[01]\." -e "^192\.168\." | sed -E -e 's/via .*$//g' -e 's/ /|/g' | tr -d '\n' | sed -e 's/|$//g'; exit 0)
echo "old routes is: ${old_routes}"

{% for push in _multistream_fail_over__pushes %}
domain_name=$(echo "{{ push.url }}" | sed -r -e 's;^.*://;;' -e 's;/.*$;;g')
multistream-ip-routes.py -d "${domain_name}" -i "{{ push.interface_grep | default("invalid-interface") }}"
{% endfor %}
}

# called on schedule as service
update_routes
