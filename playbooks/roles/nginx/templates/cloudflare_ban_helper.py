#!/usr/bin/env python3
import argparse
import contextlib
import functools
import http.client
import json
import pathlib
import time
import typing


def _parse_args(argv):
    parser = argparse.ArgumentParser()
    parser.add_argument("--cf-email", help="User email", required=True)
    parser.add_argument("--cf-token", help="User API token", required=True)
    parser.add_argument("--ban-ip", help="The new IP to ban")
    parser.add_argument("--unban-ip", help="IP to unban")
    parser.add_argument(
        "--require-country",
        help="(optional) If provided, a 'not ip.geoip.country in ...' condition will be added",
        nargs="+",
        action="extend",
    )
    parser.add_argument(
        "--zone",
        dest="zones",
        help="The Zone id to apply to",
        nargs="+",
        action="extend",
    )
    args = parser.parse_args(argv)

    if not args.ban_ip and not args.unban_ip:
        raise ValueError(
            "Error: At least one of --ban-ip or --unban-ip must be specified"
        )
    return args


@contextlib.contextmanager
def _micro_db(file="/etc/fail2ban/action.d/_ban_zones.json"):
    _db_file = pathlib.Path(file)
    if _db_file.is_file():
        data = json.loads(_db_file.read_text())
    else:
        data = {}
    try:
        yield data
    finally:
        if data:
            with _db_file.open("w") as fout:
                json.dump(data, fout, indent=4)

def _rate_limit(wrapped, minimum_time_between_calls_ms=250):
    def _limit(func):
        _limit.last_called_time = time.time_ns() # Note: this likely makes this decorator only work for one method.
        @functools.wraps(func)
        def wrapped_func(*args, **kwargs):
            time_since_last_called = (time.time_ns() - _limit.last_called_time) / 1000
            while time_since_last_called < minimum_time_between_calls_ms:
                time.sleep(.01) # 10 milliseconds
                time_since_last_called = (time.time_ns() - _limit.last_called_time) / 1000
            _limit.last_called_time = time.time_ns()
            return wrapped(*args, **kwargs)
        return wrapped_func
    return _limit(wrapped)

@_rate_limit
def _send_rule_update(
    zone_id,
    ruleset_id,
    rule_id,
    email,
    token,
    required_country_codes: typing.Collection[str],
    blocked_ips: typing.Collection[str],
):
    print("Updating rule for zone:", zone_id, ruleset_id, rule_id)
    conn = http.client.HTTPSConnection("api.cloudflare.com")
    headers = {
        "X-Auth-Email": email,
        "X-Auth-Key": token,
        "Content-Type": "application/json",
    }

    # consider options to integrate this??
    # maybe as second rule??
    # (http.request.full_uri contains "wp-includes") or (http.request.full_uri contains "wp-admin")
    expression = ""
    if required_country_codes:
        expression = (
            "(not ip.geoip.country in {"
            + " ".join([f'"{country}"' for country in required_country_codes])
            + "}) or "
        )
    expression += "(ip.src in {" + " ".join(blocked_ips) + "})"

    conn.request(
        "PUT",
        f"/client/v4/zones/{zone_id}/rulesets/{ruleset_id}",
        json.dumps(
            {
                "description": "My ruleset to execute managed rulesets",
                "name": "Block bad actors",
                "kind": "zone",
                "phase": "http_request_firewall_custom",
                "rules": [
                    {
                        "action": "block",
                        "id": rule_id,
                        "description": "Block bad actors",
                        "enabled": True,
                        "expression": expression,
                        "ref": "my_ref",
                    }
                ],
            }
        ),
        headers,
    )
    response = conn.getresponse()
    if response.status != 200:
        raise Exception(f"Error talking to CloudFlare: {response.read()}")


def _create_zone_rule(zone_id, email, token):
    print("Creating ruleset for zone:", zone_id)
    conn = http.client.HTTPSConnection("api.cloudflare.com")
    headers = {
        "X-Auth-Email": email,
        "X-Auth-Key": token,
        "Content-Type": "application/json",
    }

    json_data = {
        'description': 'My custom block rules',
        'name': "Block bad actors",
        'kind': 'zone',
        'phase': 'http_request_firewall_custom',
        'rules': [
            {
                'action': 'block',
                'description': 'Block bad actors (setup rule)',
                'enabled': True,
                'expression': 'ip.src eq 127.255.255.254',
                'ref': 'my_ref',
            },
        ],
    }

    conn.request(
        'POST',
        f'/client/v4/zones/{zone_id}/rulesets',
        json.dumps(json_data),
        headers
    )

    response = conn.getresponse()
    if response.status != 200:
        raise Exception(f"Error talking to CloudFlare: {response.read()}")
    
    result = response.read()
    data = json.loads(result)
    # rulesetId=$(cat out.json | jq '.result.id')
    # ruleId=$(cat out.json | jq '.result.rules[] | .id')
    return (data['result']['id'], data['result']['rules'][0]['id'])

def _main(argv):
    args = _parse_args(argv)

    with _micro_db('/etc/fail2ban/action.d/_banned_ips.json') as db:
        currently_banned = db

        if args.ban_ip:
            currently_banned[args.ban_ip] = True
        if args.unban_ip and args.unban_ip in currently_banned:
            currently_banned[args.unban_ip] = False
            del currently_banned[args.unban_ip]
    
    # 127.0.0.0/8 is reserved for "loopback addresses" on "this host".
    # this means that there will never be legitimate traffic coming "from" this address
    # through CloudFlare. Making this value always be present ensures a valid "not in" syntax.
    currently_banned['127.255.255.254'] = True


    currently_banned = list(sorted(currently_banned.keys()))

    with _micro_db() as db:
        for zone in args.zones:
            if zone in db:
                ruleset_id, rule_id = db[zone]
            else:
                # creating, post without IDs, then save into db
                ruleset_id, rule_id = _create_zone_rule(zone_id=zone, email=args.cf_email, token=args.cf_token)
                db[zone] = [ruleset_id, rule_id] # pretending this is a Tuple, but using Lists for Json

            _send_rule_update(
                blocked_ips=currently_banned,
                email=args.cf_email,
                required_country_codes=args.require_country,
                rule_id=rule_id,
                ruleset_id=ruleset_id,
                token=args.cf_token,
                zone_id=zone,
            )


if __name__ == "__main__":
    import sys

    _main(sys.argv[1:])
