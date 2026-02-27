###############################################################################
# BEGIN fix (279 / 296) for 'xccdf_org.ssgproject.content_rule_sshd_disable_empty_passwords'
###############################################################################
(>&2 echo "Remediating rule 279/296: 'xccdf_org.ssgproject.content_rule_sshd_disable_empty_passwords'")
# Remediation is applicable only in certain platforms
if rpm --quiet -q kernel-default || rpm --quiet -q kernel-default-base; then

if [ -e "/etc/ssh/sshd_config" ] ; then
    
    LC_ALL=C sed -i "/^\s*PermitEmptyPasswords\s\+/Id" "/etc/ssh/sshd_config"
else
    touch "/etc/ssh/sshd_config"
fi
# make sure file has newline at the end
sed -i -e '$a\' "/etc/ssh/sshd_config"

cp "/etc/ssh/sshd_config" "/etc/ssh/sshd_config.bak"
# Insert at the beginning of the file
printf '%s\n' "PermitEmptyPasswords no" > "/etc/ssh/sshd_config"
cat "/etc/ssh/sshd_config.bak" >> "/etc/ssh/sshd_config"
# Clean up after ourselves.
rm "/etc/ssh/sshd_config.bak"

else
    >&2 echo 'Remediation is not applicable, nothing was done'
fi

# END fix for 'xccdf_org.ssgproject.content_rule_sshd_disable_empty_passwords'

###############################################################################
# BEGIN fix (14 / 296) for 'xccdf_org.ssgproject.content_rule_ensure_gpgcheck_globally_activated'
###############################################################################
(>&2 echo "Remediating rule 14/296: 'xccdf_org.ssgproject.content_rule_ensure_gpgcheck_globally_activated'")
# Remediation is applicable only in certain platforms
if rpm --quiet -q zypper; then

# Strip any search characters in the key arg so that the key can be replaced without
# adding any search characters to the config file.
stripped_key=$(sed 's/[\^=\$,;+]*//g' <<< "^gpgcheck")

# shellcheck disable=SC2059
printf -v formatted_output "%s = %s" "$stripped_key" "1"

# If the key exists, change it. Otherwise, add it to the config_file.
# We search for the key string followed by a word boundary (matched by \>),
# so if we search for 'setting', 'setting2' won't match.
if LC_ALL=C grep -q -m 1 -i -e "^gpgcheck\\>" "/etc/zypp/zypp.conf"; then
    escaped_formatted_output=$(sed -e 's|/|\\/|g' <<< "$formatted_output")
    LC_ALL=C sed -i --follow-symlinks "s/^gpgcheck\\>.*/$escaped_formatted_output/gi" "/etc/zypp/zypp.conf"
else
    if [[ -s "/etc/zypp/zypp.conf" ]] && [[ -n "$(tail -c 1 -- "/etc/zypp/zypp.conf" || true)" ]]; then
        LC_ALL=C sed -i --follow-symlinks '$a'\\ "/etc/zypp/zypp.conf"
    fi
    cce="CCE-83290-7"
    printf '# Per %s: Set %s in %s\n' "${cce}" "${formatted_output}" "/etc/zypp/zypp.conf" >> "/etc/zypp/zypp.conf"
    printf '%s\n' "$formatted_output" >> "/etc/zypp/zypp.conf"
fi

else
    >&2 echo 'Remediation is not applicable, nothing was done'
fi

# END fix for 'xccdf_org.ssgproject.content_rule_ensure_gpgcheck_globally_activated'

###############################################################################
# BEGIN fix (15 / 296) for 'xccdf_org.ssgproject.content_rule_ensure_gpgcheck_never_disabled'
###############################################################################
(>&2 echo "Remediating rule 15/296: 'xccdf_org.ssgproject.content_rule_ensure_gpgcheck_never_disabled'")

sed -i 's/gpgcheck\s*=.*/gpgcheck=1/g' /etc/zypp/repos.d/*

# END fix for 'xccdf_org.ssgproject.content_rule_ensure_gpgcheck_never_disabled'

###############################################################################
# BEGIN fix (9 / 296) for 'xccdf_org.ssgproject.content_rule_enable_dconf_user_profile'
###############################################################################
(>&2 echo "Remediating rule 9/296: 'xccdf_org.ssgproject.content_rule_enable_dconf_user_profile'")
# Remediation is applicable only in certain platforms
if rpm --quiet -q gdm && { rpm --quiet -q kernel-default || rpm --quiet -q kernel-default-base; }; then

echo -e 'user-db:user\nsystem-db:gdm' > /etc/dconf/profile/gdm

else
    >&2 echo 'Remediation is not applicable, nothing was done'
fi

# END fix for 'xccdf_org.ssgproject.content_rule_enable_dconf_user_profile'

###############################################################################
# BEGIN fix (88 / 296) for 'xccdf_org.ssgproject.content_rule_grub2_password'
###############################################################################
(>&2 echo "Remediating rule 88/296: 'xccdf_org.ssgproject.content_rule_grub2_password'")
(>&2 echo "FIX FOR THIS RULE 'xccdf_org.ssgproject.content_rule_grub2_password' IS MISSING!")

# END fix for 'xccdf_org.ssgproject.content_rule_grub2_password'

###############################################################################
# BEGIN fix (89 / 296) for 'xccdf_org.ssgproject.content_rule_grub2_uefi_password'
###############################################################################
(>&2 echo "Remediating rule 89/296: 'xccdf_org.ssgproject.content_rule_grub2_uefi_password'")
(>&2 echo "FIX FOR THIS RULE 'xccdf_org.ssgproject.content_rule_grub2_uefi_password' IS MISSING!")

# END fix for 'xccdf_org.ssgproject.content_rule_grub2_uefi_password'

###############################################################################
# BEGIN fix (279 / 296) for 'xccdf_org.ssgproject.content_rule_sshd_disable_empty_passwords'
###############################################################################
(>&2 echo "Remediating rule 279/296: 'xccdf_org.ssgproject.content_rule_sshd_disable_empty_passwords'")
# Remediation is applicable only in certain platforms
if rpm --quiet -q kernel-default || rpm --quiet -q kernel-default-base; then

if [ -e "/etc/ssh/sshd_config" ] ; then
    
    LC_ALL=C sed -i "/^\s*PermitEmptyPasswords\s\+/Id" "/etc/ssh/sshd_config"
else
    touch "/etc/ssh/sshd_config"
fi
# make sure file has newline at the end
sed -i -e '$a\' "/etc/ssh/sshd_config"

cp "/etc/ssh/sshd_config" "/etc/ssh/sshd_config.bak"
# Insert at the beginning of the file
printf '%s\n' "PermitEmptyPasswords no" > "/etc/ssh/sshd_config"
cat "/etc/ssh/sshd_config.bak" >> "/etc/ssh/sshd_config"
# Clean up after ourselves.
rm "/etc/ssh/sshd_config.bak"

else
    >&2 echo 'Remediation is not applicable, nothing was done'
fi

# END fix for 'xccdf_org.ssgproject.content_rule_sshd_disable_empty_passwords'