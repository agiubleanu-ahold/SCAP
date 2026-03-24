comment_targetpw_in_sudoers:
  file.replace:
    - name: /etc/sudoers
    - pattern: '^Defaults\s+targetpw'
    - repl: '# Defaults targetpw'
    - backup: .bak

lock_root_password:
  cmd.run:
    - name: passwd -l root
    - unless: "passwd -S root | grep -q '^root L'"

set_root_shell_false:
  user.present:
    - name: root
    - shell: /bin/false
