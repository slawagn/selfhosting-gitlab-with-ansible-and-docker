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
split into three groups:
- `gitlab`:
  a single host where Gitlab instance will be deployed
- `runners`:
  one or more hosts running containers inside of which
  commands from `.gitlab-ci.yml` are executed.
  I tend to place a single runner on the same host as my Gitlab instance
  since that is more than enough for my CI/CD needs.
  You might want to have dedicated servers running these containers
- `managed-servers`:
  servers that will ultimately be hosting your applications.
  Notice that they all will be accessible with the same private key.
  You might see this as a security concern.
  The idea is that when you log into your Gitlab instance as a root user,
  you create an instance environment variable containing private key
  that will be available in all projects on that instance.
  Then, for each project, you will be creating a `HOSTS` environment variable
  containing the list of hosts to which the app is to be deployed.
  The commands from `.gitlab-ci.yml` file will be executed on every single
  host from `HOSTS` variable
  with the help of [`pssh`](https://linux.die.net/man/1/pssh) utility.

Example `ansible/hosts.ini`:
```ini
[gitlab]
gitlab.company.example  gitlab_url=gitlab.domain.example registry_port=5050

[runners]
runner1.company.example registration_token=AbRaCaDaBrA
192.168.122.2           registration_token=AbRaCaDaBrA

[managed-servers]
server1.company.example
192.168.122.4
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

(IMO it makes sense to use the user with `ansible` username)

## Scripts overview
### `00-first-launch`

Affects `all` hosts

It is assumed that a remote server has `root` user with password known to you
and SSH access enabled.

When the script is launched, you are asked for root password
and a password to decrypt the vault that you should have created earlier.

The playbook creates the admin (`wheel`) user
with credentials (username/password) from `ansible/user.vault` on remote hosts,
takes public key from your control node and authorizes it there.

Password authentication on remote host is then disabled,
as well as root login.

### `01-install-docker`

Affects all hosts

Logs in with credentials from `ansible/user.vault` to remote host,
installs docker and adds user to `docker` group
(I have not yet bothered with configuring Docker to run rootless).

It is probably the only playbook that needs tweaking
if you run distribution other than Fedora
(see the first two tasks in `ansible/playbooks/01-install-docker.yml`,
it's just a small piece of url that you would need to edit)

### `02-install-gitlab`

Affects `gitlab` host

It is assumed that ports 80, 443, 2289
and whichever one is specified in `hosts.ini` (`registry_port` variable)
are free on the host from `gitlab` group and, ideally,
the `gitlab` group should contain only one host.

The script simply copies `docker-compose.yml` from `compose-files/gitlab`
to remote host's `~/gitlab` and runs `docker-compose up -d`.
If nothing goes wrong, you should get
a functioning gitlab installation on said host.

It will take several minutes **after** the playbook execution ends
for the gitlab instance to go up.
You should then be able to log in with `root` username
and password that you specified in `ansible/user.vault`
to Gitlab's Web UI.

The container registry should become available
at the same hostname/ip as gitlab instance,
at the `registry_port` you specified in `hosts.ini`.

Both should get a certificate by Let's Encrypt.
If this fails, they will get a self-signed certificate.
Playbook `03.0` will be dealing with the fact that
`docker` and `gitlab-runner`s are not enthusiastic about such certificates.

The data will be persisted in three docker volumes:
`gitlab_config`, `gitlab_logs`, and `gitlab_data`.
`gitlab_data` is the one that you will probably want to back up regularly.

### `03-configure-managed-servers`

Affects `gitlab` and `managed-servers`

Creates `gitlab` user with no password and belonging
to `docker` and `wheel` groups on all affected hosts.

The SSH keypair is then created and public key from the pair is authorized
on every `managed-server` for `gitlab` user
(if there already was an authorized key for `gitlab` user, it is erased.
You can use this script to deprecate an old key regularly).
This makes possible logging in as `gitlab` user to every single `managed-server`
using the same private key.

The private key will be printed to your console.
You need to copy it, strip of indentation and paste into
Gitlab's instance-level `ID_RSA` environment variable.
To create it, you need to log into the web UI as `root` user and go to
`Menu > Admin > Settings > CI/CD > Variables`.
Make sure the variable has `File` type.
You will then be able to use it in you CI/CD jobs.

### `04.0-trust-self-signed-certificate--optional`

Affects `runners` and `managed-servers`

This script is **optional**: you only need to run it if your gitlab instance
or registry uses a self-signed certificate for some reason.

The script will try to fetch the certificate from your gitlab instance
(as specified in `hosts.ini`) and store it in two places on each runner host:
`~/gitlab-runner/certs/`
(in `04.1`, this folder is mounted into `gitlab-runner` container)
and `/etc/docker/certs.d/` (this allows to log into registry from inside runner
when CI/CD job is executed).

On `managed-servers`, the script will fetch the certificate for the registry
and store it in /etc/docker/certs.d/, making it possible to log into registry
when the `docker login` command is executed on the server **directly**
(through the SSH) rather than in runner container.

### `04.1-register-new-runner`

Affects `runners`

Once you create a project in web UI, you can obtain a runner registration token
in project's `Settings > CI/CD > Runners`.
You will need to place the token in `hosts.ini`'s `registration_token` variable
for each runner you are registering **before** you run the script.

The script copies `docker-compose.yml` from `compose-files/gitlab-runner`
to remote host's `~/gitlab-runner`, once again runs `docker-compose up -d`
and registers the runner.
It will the be possible to execute CI/CD jobs using this runner.

## CI/CD in Gitlab

Assuming that:
- Your Gitlab instance is up and running (as well as container registry)
  and is hosting a project
- At least one Runner is registered with your project
- It is possible to SSH into any of your deployment servers
  with `gitlab` username and a private key that you conveniently store
  in an **istance-wide** `ID_RSA` environment variable of type `File`
  available to all projects in your Gitlab instance
- `HOSTS` **project-specific** environment variable of type `File`
  contains a list of deployment servers,
  each on its own line in `[user@]host[:port]` form
- A valid Dockerfile is present in project's root directory

In your `.gitlab-ci.yml` that you will check into source control,
you can configure a pipeline consisting of several jobs
that will be executed in succession within a runner container
when you push your changes to one of the branches

### Build job

Start by defining the building stage of your application
that will only be triggered on main branch:

```yml
stages:
  - build

variables:
  TAG_LATEST: $CI_REGISTRY_IMAGE/$CI_COMMIT_REF_NAME:latest
  TAG_COMMIT: $CI_REGISTRY_IMAGE/$CI_COMMIT_REF_NAME:$CI_COMMIT_SHORT_SHA

build:
  image: docker:latest
  stage: build
  tags:
    - building
  services:
    - name: docker:dind
  script:
    - docker build -t $TAG_COMMIT -t $TAG_LATEST .
    - docker login -u gitlab-ci-token -p $CI_BUILD_TOKEN $CI_REGISTRY
    - docker push $TAG_COMMIT
    - docker push $TAG_LATEST
  rules:
    - if: $CI_COMMIT_BRANCH == $CI_DEFAULT_BRANCH
```

Since you specify `building` tag to your job in the pipeline,
you need to assign this tag to the runner (`Settings > CI/CD > Runners`).
An alternative is to allow the runner picking up any jobs.

It is also worth noting that the `docker` commands
you are running in the `script` section are run inside a gitlab-runner
container, hence the `dind` (docker-in-docker).

The first command builds the image and gives it two tags:
`latest` and another one, based on a commit hash.
These are constructed from environment variables
`$CI_REGISTRY_IMAGE`, `$CI_COMMIT_REF_NAME` and `$CI_COMMIT_SHORT_SHA`
provided by Gitlab rather than defined by us.

The second command logs in to the registry corresponding to repository.
If you're using a self-signed certificate, you will need to edit
your script slightly (see below).

The last two commands push the built image into the registry.

The rule in the end specifies that the pipeline is to be triggered
when commit to the default branch (main/master/etc) occurs.
Notice that it will also be triggered if you merge a commit
from some other branch.

Push some commit to another branch to make sure the pipeline is not triggered.
Switch to master and merge this previous commit into it and look
whether the pipeline is going to be triggered

### Deploy to production job

```yml
stages:
  - build
  - deploy_production

...

deploy_production:
  image: alpine:latest
  stage: deploy_production
  tags:
    - deployment
  before_script:
    - alias pssh_servers='pssh --inline -h $HOSTS -x "-i $ID_RSA" -x "-o StrictHostKeyChecking=no"'
  script:
    - chmod og= $ID_RSA
    - apk update && apk add pssh
    - >
      pssh_servers \
        docker login -u gitlab-ci-token -p $CI_BUILD_TOKEN $CI_REGISTRY
    - >
      pssh_servers \
        docker pull $TAG_COMMIT
    - >
      pssh_servers \
        docker container rm -f rails-app || true
    - >
      pssh_servers                              \
        docker run -d -p 80:3000                \
          --name rails-app                      \
          -e RAILS_MASTER_KEY=$RAILS_MASTER_KEY \
          $TAG_COMMIT
  environment:
    name: production
    url:  http://production.company.example
  when: manual
```

A minimal `alpine` image is used in deploy stage since all we need to do here
is to ssh into our managed server and execute commands there.

However, we might want to deploy to several hosts at the same time.
In order to do this, we install `pssh` package.
Since we don't want to pass whole lot of arguments every single time
we call `pssh` command, we create an alias before we get to the script itself.
You may want tolook into [`pssh` documentation](https://linux.die.net/man/1/pssh)
to figure out all the arguments I passed to the command

The first command in the scripts revokes permissions
for everyone except the owner from `$ID_RSA` that is represented as a file.
Apk cache is then updated and `pssh` package is installed
(everything happens inside a container within runner container)

The following `pssh` commands are executed on all hosts
specified in `$HOSTS`.

First, we log into the registry and pull the image that we pushed
during the build stage.
We then remove the container based on the previous version of the image
and instantiate a new one.
My dockerized application is actually
a blank [Rails](https://rubyonrails.org/) app.
I map its `3000` port that it listens to by default to port `80` on host
and also pass it the master key that I store as project's environment variable.

The job is assigned an environment. You can access you environments
in project's `Deployments > Environment`
(yep, we're barely scratching the CI/CD surface).

`when: manual` specifies that manual intervention is required to
actually launch the job. This will come in handy later when we add more stages

### Registry with self-signed certificate in pipeline

If your registry is using a self-signed certificate, 
you will encounter an error when trying to log in:
`x509: certificate signed by unknown authority`.

There is a workaround (as if a separate playbook wasn't enough!)

First, you need to obtain a certificate from you registry.
Run following commands in your terminal:

```bash
$ export GITLAB_INSTANCE_URL=gitlab.company.example
$ export REGISTRY_PORT=5050
$ openssl s_client -connect $GITLAB_INSTANCE_URL:443 -servername https://$GITLAB_INSTANCE_URL:$REGISTRY_PORT | openssl x509
```

You will get a certificate:
``
-----BEGIN CERTIFICATE-----
...
-----END CERTIFICATE-----
``

Create `CA_CERTIFICATE` environment variable
(another instance-wide one will be suitable in this case)
and paste the certificate in there.

Then, in your `.gitlab-ci.yml` make corresponding edits:

```yml
...
variables:
  ...
  DOCKER_TLS_CERTDIR: ""
  CA_CERTIFICATE: "$CA_CERTIFICATE"

build:
  ...
  services:
    - name: docker:dind
      command:
        - /bin/sh
        - -c
        - >
          echo "$CA_CERTIFICATE"
          > /usr/local/share/ca-certificates/my-ca.crt
          && update-ca-certificates
          && dockerd-entrypoint.sh
          || exit
  ...
```

## Other resources

You may want to read the
[DigitalOcean tutorial](https://www.digitalocean.com/community/tutorials/how-to-set-up-a-continuous-deployment-pipeline-with-gitlab-ci-cd-on-ubuntu-18-04)
where I stole some ideas from
