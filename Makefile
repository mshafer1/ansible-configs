all: dns python install-deps certbot tunnels

dns: objects/dns

certbot: objects/certbot

nginx: objects/nginx

python: objects/python

install-deps: objects/deps_installed

win_settings: objects/win_settings

homelab: objects/homelab

main: objects/main

tunnels: objects/tunnels

sensu: objects/sensu

.PHONY: dns nginx certbot sensu

win-settings:
	ansible-playbook playbooks/win_settings.yml

objects/:
	mkdir objects

objects/deps_installed: requirements.yml objects/
	ansible-galaxy install -r requirements.yml
	touch $@

objects/dns: playbooks/dns.yml $(wildcard playbooks/vars/*) objects/
	ansible-playbook playbooks/dns.yml --ask-become-pass
	touch $@

objects/nginx: playbooks/nginx.yml $(wildcard playbooks/vars/*) objects/ $(wildcard playbooks/roles/nginx/**/*)
	ansible-playbook playbooks/nginx.yml --ask-become-pass
	touch $@

objects/main: playbooks/main.yml $(wildcard playbooks/roles/**/*) objects/
	ansible-playbook playbooks/main.yml
	touch $@

objects/python: playbooks/python.yml $(wildcard playbooks/roles/python/**/*) objects/
	ansible-playbook playbooks/python.yml --ask-become-pass
	touch $@

objects/win_settings: playbooks/win_settings.yml  $(wildcard playbooks/roles/putty/**/*) $(wildcard playbooks/roles/putty/*) objects/
	ansible-playbook playbooks/win_settings.yml
	touch $@

objects/homelab: playbooks/homelab_proxy.yml objects/dns $(wildcard playbooks/vars/*) $(wildcard playbooks/roles/nginx/**/*) $(wildcard playbooks/roles/homelab_proxy/*)
	ansible-playbook playbooks/homelab_proxy.yml
	touch $@

objects/certbot: playbooks/setup_certbot.yml $(wildcard playbooks/roles/certbot/*) playbooks/vars/certbot_managed_certs.yml
	ansible-playbook $< 2>&1 | tee $@.tmp
	mv $@.tmp $@

objects/tunnels: playbooks/tunnel_servers.yml $(wildcard playbooks/roles/cloudflare_tunnel/*) $(wildcard playbooks/roles/docker_watchtower_services/*)
	ansible-playbook $< 2>&1 | tee $@.tmp
	mv $@.tmp $@

objects/sensu: playbooks/sensu.yml $(wildcard playbooks/roles/nginx_minimal/*) $(wildcard playbooks/roles/docker/*) $(wildcard playbooks/roles/sensu_backend/*)
	$(shell unbuffer ansible-playbook $< 2>&1 | tee $@.tmp; exit $$PIPESTATUS[0])
	mv $@.tmp $@
