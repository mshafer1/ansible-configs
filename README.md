# Ansible-configs

This is a collection of [Ansible](https://docs.ansible.com/ansible/latest/getting_started/index.html) playbooks and supporting documents that I use to configure servers quickly. Some of these may be useful to others, so I share them.

## Bootstrapping an nginx server:

**NOTE**: This only sets up Nginx and a few security options, it does not setup a website:

### PREREQUISITES:
* [Git](https://git-scm.com/downloads) installed
* A text editor installed (to create a config file) -> [Let me Google that for you](https://www.google.com/search?q=linux+console+text+editors&rlz=1C1GCEA_enUS1012US1012&sxsrf=APwXEdcWzTFj03j8fyh7jqjCnFsnF4WeTw%3A1680383561573&ei=SZ4oZIHCIpquqtsPjLSa6AE&ved=0ahUKEwjBipjKzIn-AhUal2oFHQyaBh0Q4dUDCBA&uact=5&oq=linux+console+text+editors&gs_lcp=Cgxnd3Mtd2l6LXNlcnAQAzIFCAAQgAQyBggAEBYQHjIGCAAQFhAeMgYIABAWEB4yBggAEBYQHjIGCAAQFhAeMgYIABAWEB4yBggAEBYQHjIGCAAQFhAeMgYIABAWEB46BwgAEIoFEEM6BggAEAcQHjoICAAQigUQkQI6BAgjECc6CAgAEIAEELEDOg4ILhCABBCxAxDHARDRAzoKCAAQgAQQFBCHAjoLCAAQFhAeEA8Q8QRKBAhBGABQAFjGI2DIJGgAcAF4AIABfYgB1BCSAQQxOC41mAEAoAEBwAEB&sclient=gws-wiz-serp). If you're not familiar with any, [Nano](https://www.howtogeek.com/42980/the-beginners-guide-to-nano-the-linux-command-line-text-editor/#:~:text=Running%20Nano&text=To%20open%20nano%20with%20an,nano%E2%80%9D%20at%20the%20command%20prompt.&text=Nano%20will%20follow%20the%20path,at%20the%20default%20nano%20screen.) is easy to pickup, or (if you have a desktop environment) [gedit](https://itsfoss.com/install-gedit-ubuntu/) is simple to use with a window.

<br/>

### Steps:

1. Clone the repo

    `git clone https://github.com/mshafer1/ansible-configs.git`

1. change-directory into the repo

    `cd ansible-configs`

1. Create a `hosts` file.

    On Linux, the majority of configuration is stored in the `/etc` directory. Ansible is no exception to this. Create `/etc/ansible/hosts` file containing:
    ```toml
    [nginx]
    localhost ansible_connection=local SSH_PORT=22
    ```

    **NOTE**: the SSH_PORT is used to adjust SSHD and firewalld to only allow ssh on that port. [While 22 is the default, many people recommend choosing a non-standard port for security-through-obscurity](https://www.howtogeek.com/443156/the-best-ways-to-secure-your-ssh-server/#:~:text=are%20being%20rejected.-,Avoid%20Port%2022,-Port%2022%20is)

1. Use `_bootstrap.sh` to install Ansible and Python (required to install Ansible)

    `./_bootstrap.sh`

    It will prompt to confirm before installing:
    ```
    After this operation, 290 MB of additional disk space will be used.
    Do you want to continue? [Y/n]
    ```
    The 'Y/n' syntax means that it wants a yes or no, but if you put nothing (and press enter) it will default to "yes" (denoted by the capital Y)

1. Once that has finished, close an re-open your shell to load in the changes to environment variables (if connected via SSH, disconnect and reconnect; if using a terminal window, close and re-open).

1. Check that it worked by running

    `which ansible`

    You should see an output like:

    `/root/.local/bin/ansible`
    (where "`root`" may be "`/home/<your username>`")

1. Use `ansible-playbook` to run the nginx playbook

    `ansible-playbook playbooks/nginx.yml`

    This should:
    * Install:
        - [`nginx`](https://www.nginx.com/), the web server
        - [`fail2ban`](https://www.fail2ban.org/wiki/index.php/Main_Page), a configurable daemon that monitors logs for bad actors and blocks them via the system firewall
        - [`mailutils`](https://packages.debian.org/stretch/mailutils), a standard mail program for Linux (this is for fail2ban to be able to log messages to root about bans)
    * [Configure firewalld to allow HTTP (port 80),  HTTPS (port 443), and whatever you set SSH_PORT to through (blocking others)](https://github.com/mshafer1/ansible-configs/blob/master/playbooks/roles/nginx/tasks/main.yml#L8)
    * [Configure nginx to return status code 444 for HTTP and HTTP requests on the default server](https://github.com/mshafer1/ansible-configs/blob/master/playbooks/roles/nginx/tasks/main.yml#L37) -> using a self-signed cert for "example.com"


            This is because nginx will default serve the first cert it finds when asked for https on the default site. Because it is assumed that anyone requesting a site from the server via IP address is a bad-actor doing web scanning. 
            
            Blocking them and not telling them what website(s) are actually hosted on this server seems like a good idea.
    
    * Configure fail2ban to flag and block [a number of situations](https://github.com/mshafer1/ansible-configs/blob/master/playbooks/roles/nginx/tasks/main.yml#:~:text=%2D%20name%3A-,Configure%20fail2ban,-become%3A%20true)



### **How do I check that it worked**?
Since we removed the default "Welcome to nginx" page (or, default site), we did also add a `/status` route that will report the server status - BUT ONLY FOR REQUESTS WITHIN LOCALHOST.

So, we can check if it worked by running 

`curl http://localhost/status`

Should get a response like:
```
Active connections: 1
server accepts handled requests
 1 1 1
Reading: 0 Writing: 1 Waiting: 0
```

([may need to install curl if this is a completely new server](https://command-not-found.com/curl))


## Using CloudFlare 0 Trust tunnel and fail2ban

<details>
<summary>Why? (click to expand if you want background)</summary>

I started working on using Fail2Ban's built-in Cloudflare action and got it working (and found how to validate) only to be met with a header saying:

> The Firewall Rules API and the associated Cloudflare Filters API are now deprecated. These APIs will stop working on 2025-01-15. You must migrate any automation based on the Firewall Rules API or Cloudflare Filters API to the Rulesets API before this date to prevent any issues.
>
>[source](https://web.archive.org/web/20240817201327/https://developers.cloudflare.com/waf/reference/migration-guides/firewall-rules-to-custom-rules/#relevant-changes-for-api-users)

So, ... I set to work figuring out how to adapt the concept to work with the [Rulesets API](https://web.archive.org/web/20240818003927/https://developers.cloudflare.com/waf/custom-rules/create-api/#example-b).

The result was this:
* A logging config that sets nginx logs to show [the forwarded IP]()
* a custom `cloufdflare-ban` action that is generated using `zone` IDs ([roughly equivalent to domain names](https://web.archive.org/web/20240808031659/https://developers.cloudflare.com/fundamentals/setup/find-account-and-zone-ids/))
* a Python helper script that handles the posting the current block rule ([idempotent](https://en.wikipedia.org/wiki/Idempotence)) 
</details>

If using the nginx role (see section above), you can configure [fail2ban]() to use firewall rules in [CloudFlare](https://www.cloudflare.com/) to ban bad actors coming in over the [CloudFlare 0 Trust Tunnel](https://developers.cloudflare.com/cloudflare-one/). The actual source IP will be logged and banned.

A few variables are required to be set to enable this:
* `cloudflare_token` [your token](https://developers.cloudflare.com/fundamentals/api/get-started/keys/#:~:text=your%20API%20key%3A-,Log%20in%20to%20the%20Cloudflare%20dashboard%20Open%20external%20link,to%20My%20Profile%20%3E%20API%20Tokens.) (used by the script to authenticate)
* `cloudflare_email` your email (used as "username" in conjunction with the token to authenticate)
* `cloudflare_zones` list of [zone IDs](https://developers.cloudflare.com/fundamentals/setup/find-account-and-zone-ids/) to apply the rules to (note, this setup will ban for all zones regardless of offending domain)
* `enable_cloud_flare_block` set this to "true" to enable the action (without this, default is to template the action file if other vars are present, but leave the fail2ban action as `iptables`). Enabling [nginx's 'ngx_http_realip_module'](https://nginx.org/en/docs/http/ngx_http_realip_module.html) is also triggered with this variable (this tells nginx to look at the `X-Forwarded-For` header for the IP of the requestor - not Cloudflare - and use in logs for fail2ban to pick up).


Optional variables for further control:
* `required_country_codes` list of [county abbreviations](https://developers.cloudflare.com/waf/custom-rules/use-cases/allow-traffic-from-specific-countries/) to require the source IP is from (i.e., always block if NOT from one of these. This may be useful if you only anticipate users from your home country are legitimate users, and you don't mind if VPN users are unable to access your site)
* `nginx_real_ip_sources` list of IPs for nginx to examine the `X-Forwarded-For` IP and replace in logs as the source IP. (Note: this defaults to a list containing: (1) `127.0.0.1/8` to handle cloudflared running on localhost, (2) `172.17.0.0/16` to handle [cloudflared running in Docker](https://support.hyperglance.com/knowledge/changing-the-default-docker-subnet#:~:text=By%20default%2C%20Docker%20uses%20172.17.0.0/16.), and (3) `192.168.1.1/24` to handle cloudflared running on another host in a home-lab environment. If your use does not fit one of these, you will likely need to set this as a [host](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html#adding-variables-to-inventory) or [group](https://docs.ansible.com/ansible/latest/inventory_guide/intro_inventory.html#assigning-a-variable-to-many-machines-group-variables) var)

### Example yaml ansible hosts file:
```yaml
#/etc/ansible/hosts
all:
  hosts:
    server_1:
      ansible_user: service_account
      ansible_host: 127.0.0.1
      # ...
      enable_cloud_flare_block: true
      cloudflare_token: 'token_value'
      cloudflare_email: 'user@example.com'
      cloudflare_zones:
        - deadbeef # domain 1
        # ...
      required_country_codes:
        - US # USA
        - MX # Mexico
        - CA # Canada
  nginx:
    hosts:
      server_1: {} # add server_1 to the nginx group
```

### Validating

1. Get some IPs blocked

  Option a: let the rules get hit
  
  Option b: `fail2ban-client set nginx-nohome banip 192.168.1.0` (bans 192.168.1.0 under the `nginx-nohome` jail defined in the nginx role)
  
1. Log into [CloudFlare](https://www.cloudflare.com/) dashboard and navigate to:

    A. `Websites` -> `{your domain}` -> `Security` -> `WAF`

    B. Click on on "Custom rules"

    C. Should see a rule named "Block bad actors", click on it

    D. Should see that it is set to block IP addresses in:
      - `127.255.255.254`
      - `192.168.1.0` (assuming followed step above)
      
      Note: if `required_country_codes`, full rule syntax should in include `ip.src in ...` OR `not ip.geoip.country in {...}` such that IPs that are NOT from specified countries OR are in the naughty list will be blocked (via "Choose action" -> "Block")

1. Unban user

    `fail2ban-client unban 192.168.1.0`

1. Refresh Cloudflare dashboard -> IP should be removed from list of blocked (note, `127.255.255.254` will always be included to provide a simpler syntax and keep the expression valid)
