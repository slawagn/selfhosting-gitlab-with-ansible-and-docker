path="${0%/*}" # directory of the script

ansible-playbook                        \
  -i $path/inventory                    \
  -e @$path/admin-pass                  \
    --ask-vault-pass                    \
  $path/playbooks/01-install-docker.yml
