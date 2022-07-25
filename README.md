## About

This project contains a bunch of scripts 
([Ansible](https://www.ansible.com/) playbooks, in fact)
that help me unfold a self-hosted
[Gitlab](https://about.gitlab.com/) instance and use its CI/CD capabilities
to deploy my projects to a private server within
[Docker](https://www.docker.com/) containers.

## Requirements

- **Ansible** installed on your control node
- **Fedora**  installed on the machines you are configuring
- SSH access  from your control node to the controlled machines

Maybe one day I will take my time and make this thing
more distribution-agnostic. Maybe not.

Anyways, only `01` playbook will need to be edited (probably)
and you should be able to easily adapt it for your particular distribution.

## File structure overview

All the actual work is done through
ansible playbooks (`ansible/playbooks/*.yml`).
You, however, don't need to launch them directly since that would
require remembering and typing a bunch of command-line arguments,
same for each playbook.
Instead, you execute simple shell scripts (`ansible/*.sh`)
that launch playbooks for you.

`ansible/hosts.ini` contains the addresses
resolving to the servers you're configuring
split into two groups: `gitlab` (contains a single host) and `workers`.

For each host, some variables are specified:
```ini
[gitlab]
gitlab.company.example  gitlab_url=gitlab.domain.example registry_port=5050

[workers]
worker1.company.example registration_token=AbRaCaDaBrA
192.168.122.2           registration_token=AbRaCaDaBrA
```

`ansible` directory should contain `user.vault` file.
One can be created with `ansible-vault create ansible/user.vault` command
and edited with `ansible-vault edit ansible/user.vault`.

Its contents are as following:
```
user:     <whateverusername>
password: <whateverpassword>
```

These are the credentials that ansible will be using
when connecting to remote hosts in all playbooks except `00`.
That one logs in as root and creates user with credentials from vault.

(IMO it makes sense to use user with name `ansible`)

## Scripts overview
### `00-first-launch`

It is assumed that a remote server has `root` user with password known to you
and SSH access enabled.

When the script is launched, you are asked for root password
and a password ro decrypt the vault that you should have created earlier.

The playbook creates the admin (`wheel`) user
with credentials (username/password) from `ansible/user.vault` on remote hosts,
takes public key from your control node and authorizes it there.

Password authentication on remote host is then disabled,
as well as root login.

### `01-install-docker`

Logs in with credentials from `ansible/user.vault` to remote host,
installs docker and adds user to `docker` group
(I have not yet bothered with configuring Docker to run rootless).

It is probably the only playbook that needs tweaking
if you run distribution other than Fedora
(see first two tasks in `ansible/playbooks/01-install-docker.yml`,
it's just a small piece of the url that you would need to edit)

### `02-install-gitlab`

It is assumed that ports 80, 443, 2289
and whichever one is specified in `hosts.ini` (`registry_port` variable)
are free on the host in `gitlab` group and, ideally,
the `gitlab` group should contain only one host.

The script simply copies `docker-compose.yml` from `compose-files/gitlab`
to remote host's `~/gitlab` and runs `docker-compose up -d`.
If nothing goes wrong, you should get
a functioning gitlab installation on said host.

It will take several minutes **after** the playbook execution ends
for the gitlab instance to go up.
You should then be able to log in with `root` username
and password that you specified in `ansible/user.vault`.

The container registry should become available
at the same hostname/ip as gitlab instance,
at the `registry_port` you specified in `hosts.ini`.

Both should get a certificate by Let's Encrypt.
If this fails, they will get a self-signed certificate.
Playbook `03.0` will be dealing with the fact that
`docker` and `gitlab-runner`s are not enthusiastic about such certificates.

The data will be persisted in three docker volumes:
`gitlab_config`, `gitlab_logs`, and `gitlab_data`.
`gitlab_data` is the one that you will probably want to back up.

Once you create a project, you can obtain a runner registration token
in  project's `Settings > CI/CD > Runners`.
You will need to place the token in `hosts.ini` **before** you run `03.1`.

### `03.0-make-runner-trust-gitlab-(optional)`

This script is **optional**: you only need to run it if your gitlab instance
uses a self-signed certificate.

The script will try to fetch the certificate from your gitlab instance
(as specified in `hosts.ini`) and store it in two places on each worker host:
`~/gitlab-runner/certs/`
(in `03.1`, this folder is mounted into `gitlab-runner` container)
and `/etc/docker/certs.d/` (this allows to log into registry from worker).

### `03.1-install-gitlab-runner

By this moment, you should obtain a runner registration token (see `02`).
This token is to be placed in `hosts.ini`'s `registration_token` variable
for each runner you are registering.

The script copies `docker-compose.yml` from `compose-files/gitlab-runner`
to remote host's `~/gitlab-runner` and, once again, runs `docker-compose up -d`.

Once the container is up and registered, **a new `gitlab` user is created**
on worker host belonging to `wheel` and `docker` groups and with no password.
For this user, an SSH keypair is generated and the public key is authorized.
Contents of the private key are then printed to your console.
This private key then may allow access to the **worker host**
from **inside the runner container** controlled by gitlab's **CI/CD job**.

You may copy this private key and paste into your gitlab project's `ID_RSA`
variable of type `File`.
Then, in your `.gitlab-ci.yml`, you will be able to spawn new containers
in the following manner
(notice, user-defined `SERVER_USER` and `SERVER_HOST`
variables are used as well):

```yml
variables:
  ...
  TAG_COMMIT: $CI_REGISTRY_IMAGE/$CI_COMMIT_REF_NAME:$CI_COMMIT_SHORT_SHA

deploy:
  ...
  script:
  - >
    ssh -i $ID_RSA -o StrictHostKeyChecking=no $SERVER_USER@$SERVER_HOST
    "docker run -d --name my-app $TAG_COMMIT"
  ...

```

You may want to read the
[DigitalOcean tutorial](https://www.digitalocean.com/community/tutorials/how-to-set-up-a-continuous-deployment-pipeline-with-gitlab-ci-cd-on-ubuntu-18-04)
where I stole this idea from
or see an [example Rails app](#) (coming soon) that I deployed on a local VM
using this technique (in fact, this [me using a network of local VMs] is where
the certificate issues are coming from :D)
