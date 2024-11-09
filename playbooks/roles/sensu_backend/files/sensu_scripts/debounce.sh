#!/bin/sh
set -eu
# set -o xtrace
event_info=$(cat -)
echo "${event_info}"
exit 0

resource_namespace=$(echo "${event_info}" | jq -r '.entity.metadata.namespace')
resource_name=$(echo "${event_info}" | jq -r '.entity.metadata.name')
if { [ -n "$resource_namespace" ] && [ "$resource_namespace" != "default" ] ;}; then
    resource_name="${resource_namespace}:${resource_name}"
fi
resource_debounce_n=$(echo "${event_info}" | jq -r '.entity.metadata.labels.debounce_n  // 5')
resource_track_n=$(( $resource_debounce_n * 2 ))

check_name=$(echo "${event_info}" | jq -r '.check.metadata.name')
check_command=$(echo "${event_info}" | jq -r '.check.command')
check_state=$(echo "${event_info}" | jq -r '.check.state')
check_output=$(echo "${event_info}" | jq -r '.check.output')

DB_FILE="/var/log/sensu_debounce_history_${resource_name}:${check_name}.json"

if test -f "$DB_FILE"; then
    current_data=$(cat "$DB_FILE")
else
    current_data="{}"
fi

_history=$(echo "${current_data}" | jq -c '.history')
_history=$(echo "${_history}" | jq -c ". + [\"${check_state}\"] | .[-${resource_track_n}:]")
_current_state=$(echo "${current_data}" | jq -r '.state // ""')

# all_passing=$(echo "${_history}" | jq 'map(select(. != "passing")) | length == 0')
n_events=$(echo "${_history}" | jq -r '.[] | length')
n_passing=$(echo "${_history}" | jq -r 'map(select(. == "passing")) | length')
n_failing=$(( n_events - n_passing ))
# none_passing=$(echo "${_history}" | jq 'map(select(. == "passing")) | length == 0')

resource_unstable_n=$(( resource_debounce_n / 2))

changed=0
message=""
new_state="${_current_state}"
if [ "${_current_state}" = "passing" ]; then
    if [ "${n_passing}" -lt "${resource_unstable_n}" ]; then
        changed=1
        message="${check_name} has become unstable - failing ${n_failing} out of the last ${n_events}"
        new_state="unstable"
    elif [ "${n_passing}" -ge "${resource_debounce_n}" ]; then
        changed=1
        message="${check_name} is now failing - failing ${n_failing} out of the last ${n_events}"
        new_state="failing"
    fi
elif [ "${_current_state}" = "unstable" ]; then
    if [ "${n_passing}" -ge "${resource_debounce_n}" ]; then
        changed=1
        message="${check_name} is now passing and stable - passing ${n_passing} out of the last ${n_events}"
        new_state="passing"
    elif [ "${n_passing}" = "0" ]; then
        changed=1
        message="${check_name} is now failing - failing ${n_failing} out of the last ${n_events}"
        new_state="failing"
    fi
elif [ "${_current_state}" = "failing" ]; then
    if [ "${n_passing}" -ge "${resource_unstable_n}" ]; then
        changed=1
        message="${check_name} is now passing but unstable - passing ${n_passing} out of the last ${n_events}"
        new_state="unstable"
    elif [ "${n_failing}" = "0" ]; then
        changed=1
        message="${check_name} is now passing and stable - failing ${n_failing} out of the last ${n_events}"
        new_state="passing"
    fi
fi

echo "{\"history\": ${_history}, \"state\": ${new_state} }" > DB_FILE

echo "$event_info" | jq -c ". + {\"debounce\": {\"message\": \"${message}\", \"changed\": ${changed}, \"state\": \"${new_state}\"}}"
