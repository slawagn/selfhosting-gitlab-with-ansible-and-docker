path="${0%/*}" # directory of the script

ansible-playbook                      \
  -i $path/inventory                  \
  -e @$path/admin-pass                \
    --ask-vault-pass                  \
  $path/playbooks/00-first-launch.yml \
    --ask-pass
