## Prerequisites

`hosts.ini` should contain the addresses resolving to the servers you're configuring.

```ini
[server1]
devops.company.example

[server2]
192.168.122.244
```

If the server is not running Fedora (I used 36, YMMV),
playbooks will need to be edited.
Maybe I will do that later to make the playbooks more distribution-agnostic.
Maybe not.

`user.vault` file is expected to exist in the `ansible` folder.
It should contain two key-value pairs:
```
user:     <whateverusername>
password: <whateverpassword>
```

You can create the vault with ```ansible-vault create user.vault```
or edit it with ```ansible-vault edit user.vault```

If root access is enabled, script `00` will:
- create admin (`wheel`) user with credentials from the vault
- deploy your public ssh key
- disable password authentication
- disable root login

Scripts `01` uses these credentials to connect to the remote server
and execute commands as a priviledged user.
It installs Docker and adds user to the `docker` group
(I have not yet bothered with configuriing Docker to run rootless).

Script `02` should copy the files from `app` folder to the remote host
and execute a command that starts your application. I have not yet decided
on how exactly the command should be specified. Right now it just prints
a message into a file
