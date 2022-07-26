path="${0%/*}" # directory of the script

ansible-playbook                \
  -i  $path/hosts.ini           \
  -e @$path/user.vault          \
    --ask-vault-pass            \
  $path/playbooks/03-configure-managed-servers.yml
