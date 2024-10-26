# Cloudflare DDNS

This role sets up a service to run every fifteen minutes that uses the Cloudflare API to update a DNS record to point at the current machine's IP.

NOTE: by default, it uses online services to retrieve the public IP; however, setting the value of `cloudflareddns__store_public_ip` to `False` (it is role defaulted to `True`, see [the docs](https://docs.ansible.com/ansible/latest/playbook_guide/playbooks_variables.html) for how/where to over-write best) will cause it to utilize `ip a` to identify the local IP of the machine.

# Status

In development