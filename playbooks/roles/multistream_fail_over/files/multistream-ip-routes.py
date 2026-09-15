#!/usr/bin/env python3
"""Route the IPs a domain resolves to out a chosen interface, via that interface's default gateway."""
import argparse
import fnmatch
import json
import socket
import subprocess
import sys


def parse_args():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-d", "--domain", required=True, help="Domain to resolve and route")
    parser.add_argument("-i", "--interface", required=True, help="Glob pattern matching the interface name (e.g. 'eth*', or 'wlo*')")
    parser.add_argument("--dry-run", action="store_true", help="Print the route commands instead of running them")
    return parser.parse_args()


def resolve_domain_ips(domain):
    _, _, ip_addresses = socket.gethostbyname_ex(domain)
    return sorted(set(ip_addresses))


def list_interfaces():
    output = subprocess.run(["ip", "-json", "link", "show"], check=True, capture_output=True, text=True).stdout
    return [link["ifname"] for link in json.loads(output)]


def pick_interface(pattern, interfaces):
    matches = sorted(fnmatch.filter(interfaces, pattern))
    if not matches:
        print(f"Warning: no interface matched pattern '{pattern}'", file=sys.stderr)
        return None
    if len(matches) > 1:
        print(f"Warning: multiple interfaces matched '{pattern}': {matches}; using '{matches[0]}'", file=sys.stderr)
    return matches[0]


def find_gateway(interface):
    output = subprocess.run(["ip", "-json", "route", "show", "default"], check=True, capture_output=True, text=True).stdout
    for route in json.loads(output):
        if route.get("dev") == interface and route.get("gateway"):
            return route["gateway"]
    return None


def list_routes():
    output = subprocess.run(["ip", "-json", "route", "show"], check=True, capture_output=True, text=True).stdout
    return json.loads(output)


def build_commands(domain_ips, interface, gateway, routes):
    commands = []

    if gateway is not None:
        for ip in domain_ips:
            commands.append(["ip", "route", "replace", ip, "via", gateway, "dev", interface])
    else:
        print(f"Warning: no default gateway found for interface '{interface}'; not adding routes", file=sys.stderr)

    for route in routes:
        dst = route.get("dst")
        if dst not in domain_ips:
            continue
        if route.get("dev") == interface:
            continue
        # remove existing route to the same destination via a different interface
        commands.append(["ip", "route", "del", dst, "dev", route["dev"]])

    return commands


def main():
    args = parse_args()

    domain_ips = resolve_domain_ips(args.domain)
    interfaces = list_interfaces()
    interface = pick_interface(args.interface, interfaces)
    if interface is None:
        sys.exit(0)

    gateway = find_gateway(interface)
    routes = list_routes()
    commands = build_commands(domain_ips, interface, gateway, routes)

    for command in commands:
        print(" ".join(command))
        if not args.dry_run:
            subprocess.run(command, check=True)


if __name__ == "__main__":
    main()
