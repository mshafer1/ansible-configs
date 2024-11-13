#!/bin/sh
set -eu
# set -o xtrace

event_info=$(cat -)

channels=$(echo "${event_info}" | jq -r '.entity.metadata.labels["ntfy_channels"]  // env.NTFY_DEFAULT_CHANNELS')
resource_namespace=$(echo "${event_info}" | jq -r '.entity.metadata.namespace')
resource_name=$(echo "${event_info}" | jq -r '.entity.metadata.name')
if { [ -n "$resource_namespace" ] && [ "$resource_namespace" != "default" ] ;}; then
    resource_name="${resource_namespace}:${resource_name}"
fi

check_name=$(echo "${event_info}" | jq -r '.check.metadata.name')
check_command=$(echo "${event_info}" | jq -r '.check.command')
check_state=$(echo "${event_info}" | jq -r '.check.state')
check_output=$(echo "${event_info}" | jq -r '.check.output')


tmp_file=$(echo -n "/tmp/ntfy-message-"; uuidgen)
cat > "$tmp_file" << EOF
${check_name} for ${resource_name} is $check_state


    > ${check_command}
    ${check_output}

EOF

original_args="$@"

IFS=, set -- "${channels}"
for c in $@; do

curl -H "Title: ${check_name} for ${resource_name} is $check_state" \
    -H "Authorization: Bearer ${NTFY_TOKEN}" \
    --data-binary "@${tmp_file}" \
    "${NTFY_SERVER}/${c}" >> /var/log/ntfy_notifications

done
rm -f "${tmp_file}"

set -- "$original_args"
