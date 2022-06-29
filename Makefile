all: dns python install-deps

dns: objects/dns

python: objects/python

install-deps: objects/deps_installed

main: objects/main

win-settings:
	ansible-playbook playbooks/win_settings.yml

objects/:
	mkdir objects

objects/deps_installed: requirements.yml objects/
	ansible-galaxy install -r requirements.yml
	touch $@

objects/dns: playbooks/dns.yml $(wildcard playbooks/vars/**/*) objects/
	ansible-playbook playbooks/dns.yml --ask-become-pass
	touch $@

objects/main: playbooks/main.yml $(wildcard playbooks/roles/**/*) objects/
	ansible-playbook playbooks/main.yml
	touch $@

objects/python: playbooks/python.yml $(wildcard playbooks/roles/python/**/*) objects/
	ansible-playbook playbooks/python.yml --ask-become-pass
	touch $@
