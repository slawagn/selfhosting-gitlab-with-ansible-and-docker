path="${0%/*}" # directory of the script

ansible-playbook       \
  -i  $path/hosts.ini  \
  -e @$path/user.vault \
    --ask-vault-pass   \
  $path/playbooks/03.0-make-runner-trust-gitlab-(optional).yml
