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



