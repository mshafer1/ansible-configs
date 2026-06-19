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
echo "Getting IP addresses for ${domain_name}"
ip_addresses=$(nslookup ${domain_name} | sed -n -e '/answer:/,$p' | grep Address | cut -d' ' -f2 | grep -v ":" | sort; exit 0)
echo "IP lines count: `echo ${ip_addresses} | wc -l`"
# echo "IP address: ${ip_addresses}"

for ip in ${ip_addresses}; do
all_ips+=("$ip")
done

if [[ -n '{{ push.interface_grep | default("") }}' ]]; then
    echo 'Determining interface gateway for {{ push.interface_grep }}'
    interface=$(echo "${ip_links}" | tr ' ' '\n' | grep -E '{{ push.interface_grep }}' || true)
    if [[ -n "${interface}" ]]; then
      gateway=$(ip route | grep 'default via' | grep "${interface}" | sed -E -e 's/^.* via //g' -e 's/ dev .*$//g' || true)
      if [[ -n "${gateway}" ]]; then
        echo "Configuring to send all traffic destined for ${domain_name} out ${interface} via ${gateway}"
        echo "-- ${ip_addresses}"
        (echo "${ip_addresses}" | sed -e 's/^/ip route add /g' -e "s/\$/ via ${gateway} dev ${interface}/g" | tee -a _new_routes | sed -e '/^$/d' | grep -E -v "${old_routes:-/}" | tee -a _route_changes || true)
      else
        echo "No gateway found for ${interface}, skipping"
      fi
    else
      echo "No interface matching {{ push.interface_grep }} found, skipping"
    fi
else
  echo "No interface specified for push"
fi

echo "finished with ${domain_name}"

{% endfor %}

# cleanup any from last time
pattern=$(IFS="|"; echo "${all_ips[*]}")
echo "pattern is ${pattern}"
old_routes_to_remove=$(ip route | grep "via" | grep -v -e " src " -e "/" | grep -v -E -e "^10\." -e "^172\.1[6-9]\." -e "^172\.2\d\." -e "^172\.3[01]\." -e "^192\.168\." | grep -v -E "$pattern"; exit 0)

if [[ -z "${old_routes_to_remove}" ]]; then
    echo "No old routes identified"
else
    echo "Removing routes that no longer match: ${old_routes_to_remove}"
    echo "$old_routes_to_remove" | sed -e 's/ link linkdown/ link/g' -e 's/ $//g' | sed -e 's/^/ip route delete /g' | tee -a _route_changes
fi

# echo "Would apply"
cat _route_changes
bash _route_changes
}

# called on schedule as service
update_routes
