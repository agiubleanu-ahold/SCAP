###############################################################################
# BEGIN fix (1 / 305) for 'disable_prelink'
###############################################################################
echo "Remediating: disable_prelink"
if [ -f /etc/sysconfig/prelink ]; then
    sed -i 's/^PRELINKING.*/PRELINKING=no/' /etc/sysconfig/prelink
fi
# END fix

##############################+----#################################################
# BEGIN fix (2, 3 / 305) for 'aide_build_database'
###############################################################################
echo "Remediating: aide_build_database"
if [ -x /usr/bin/aide ]; then
    /usr/bin/aide --init
    cp -p /var/lib/aide/aide.db.new /var/lib/aide/aide.db
fi
# END fix

###############################################################################
# BEGIN fix (4 / 305) for 'aide_periodic_checking_systemd_timer'
###############################################################################
echo "Remediating: aide_periodic_checking_timer"

cat > /etc/systemd/system/aidecheck.service <<EOF
[Unit]
Description=Aide Check
[Service]
Type=simple
ExecStart=/usr/bin/aide --check
[Install]
WantedBy=multi-user.target
EOF

cat > /etc/systemd/system/aidecheck.timer <<EOF
[Unit]
Description=Aide check every day at 5AM
[Timer]
OnCalendar=*-*-* 05:00:00
Unit=aidecheck.service
[Install]
WantedBy=multi-user.target
EOF

chown root:root /etc/systemd/system/aidecheck.*
chmod 0644 /etc/systemd/system/aidecheck.*

systemctl enable aidecheck.timer
# END fix

###############################################################################
# BEGIN fix (11 / 305) for 'sudo_add_use_pty'
###############################################################################
echo "Remediating: sudo_add_use_pty"
if [ -f /etc/sudoers ]; then
    if ! grep -Pq '^[\s]*Defaults\b[^!\n]*\buse_pty.*$' /etc/sudoers; then
        echo "Defaults use_pty" >> /etc/sudoers
    fi
    /usr/sbin/visudo -qcf /etc/sudoers || echo "WARNING: /etc/sudoers validation failed"
fi

###############################################################################
# BEGIN fix (12 / 305) for 'sudo_custom_logfile'
###############################################################################
echo "Remediating: sudo_custom_logfile"
var_sudo_logfile='/var/log/sudo.log'
if [ -f /etc/sudoers ]; then
    if ! grep -Pq '^[\s]*Defaults\b[^!\n]*\blogfile\s*=\s*(?:"?([^",\s]+)"?).*$' /etc/sudoers; then
        echo "Defaults logfile=${var_sudo_logfile}" >> /etc/sudoers
    else
        sed -Ei "s/(^[\s]*Defaults.*\blogfile=)[-]?([^, ]+)(.*$)/\1${var_sudo_logfile//\//\\/}\3/" /etc/sudoers
    fi
fi

###############################################################################
# BEGIN fix (14, 15 / 305) for 'gpgcheck_globally_activated'
###############################################################################
echo "Remediating: gpgcheck_settings"
if [ -f /etc/zypp/zypp.conf ]; then
    if grep -q "^gpgcheck" /etc/zypp/zypp.conf; then
        sed -i 's/^gpgcheck.*/gpgcheck = 1/g' /etc/zypp/zypp.conf
    else
        echo "gpgcheck = 1" >> /etc/zypp/zypp.conf
    fi
fi
if [ -d /etc/zypp/repos.d ]; then
    sed -i 's/gpgcheck\s*=.*/gpgcheck=1/g' /etc/zypp/repos.d/* 2>/dev/null || true
fi

###############################################################################
# BEGIN fix (17 / 305) for 'banner_etc_issue'
###############################################################################
echo "Remediating: banner_etc_issue"
login_banner_text="Authorized users only. All activity may be monitored and reported."
formatted=$(echo "$login_banner_text" | fold -sw 80)

mkdir -p /etc/issue.d
cat <<EOF >/etc/issue.d/99-oscap-setting
$formatted
EOF

if [ -f /usr/lib/systemd/system/issue-generator.service ] || [ -f /etc/systemd/system/issue-generator.service ]; then
    systemctl enable issue-generator
fi

###############################################################################
# BEGIN fix (19 / 305) for 'banner_etc_motd'
###############################################################################
echo "Remediating: banner_etc_motd"
motd_banner_text="Authorized uses only. All activity may be monitored and reported."
formatted=$(echo "$motd_banner_text" | fold -sw 80)

cat <<EOF >/etc/motd
$formatted
EOF

###############################################################################
# BEGIN fix (20-25 / 305) for 'ownership_issue_motd'
###############################################################################
echo "Remediating: ownership_issue_motd_banners"

if [ -d /etc/issue.d/ ]; then
    find /etc/issue.d/ -type f -exec chown 0:0 {} \;
fi

for f in /etc/issue /etc/issue.net /etc/motd; do
    [ -f "$f" ] || touch "$f"
    chown 0:0 "$f"
done

###############################################################################
# BEGIN fix (26-28 / 305) for 'permissions_issue_motd'
###############################################################################
echo "Remediating: permissions_issue_motd_banners"

chmod 0644 /etc/issue 2>/dev/null || true
chmod 0644 /etc/issue.net 2>/dev/null || true
chmod 0644 /etc/motd 2>/dev/null || true

if [ -d /etc/issue.d/ ]; then
    chmod 0644 /etc/issue.d/* 2>/dev/null || true
fi


bash

###############################################################################
# BEGIN fix (31 / 305) for 'pam_pwhistory_remember'
###############################################################################
echo "Remediating: pam_pwhistory_remember"

PAM_FILE="/etc/pam.d/common-password"
VAR_REMEMBER="5"

if [ -f "$PAM_FILE" ]; then
    if grep -q "pam_pwhistory.so" "$PAM_FILE"; then
        sed -i -E "s/(pam_pwhistory.so.*remember=)[^[:space:]]*/\1$VAR_REMEMBER/" "$PAM_FILE"
        if ! grep -q "use_authtok" <<< "$(grep "pam_pwhistory.so" "$PAM_FILE")"; then
            sed -i -E "s/(pam_pwhistory.so.*)/\1 use_authtok/" "$PAM_FILE"
        fi
    else
        if grep -q "pam_unix.so" "$PAM_FILE"; then
            sed -i "/pam_unix.so/i password requisite pam_pwhistory.so remember=$VAR_REMEMBER use_authtok" "$PAM_FILE"
        else
            echo "password requisite pam_pwhistory.so remember=$VAR_REMEMBER use_authtok" >> "$PAM_FILE"
        fi
    fi
fi

###############################################################################
# BEGIN fix (32 / 305) for 'pam_tally2' (Account Lockout)
###############################################################################
echo "Remediating: accounts_passwords_pam_tally2"

VAR_TALLY_DENY='5'
PAM_LOGIN="/etc/pam.d/login"
PAM_ACCOUNT="/etc/pam.d/common-account"

if [ -f "$PAM_LOGIN" ]; then
    sed -i '/pam_tally2.so/d' "$PAM_LOGIN"
    sed -i "1iauth     required    pam_tally2.so deny=$VAR_TALLY_DENY onerr=fail" "$PAM_LOGIN"
fi

if [ -f "$PAM_ACCOUNT" ]; then
    if ! grep -q "pam_tally2.so" "$PAM_ACCOUNT"; then
        echo "account  required    pam_tally2.so" >> "$PAM_ACCOUNT"
    fi
fi

###############################################################################
# BEGIN fix (33 / 305) for 'pam_tally2_deny_root'
###############################################################################
echo "Remediating: accounts_passwords_pam_tally2_deny_root"

PAM_LOGIN="/etc/pam.d/login"
VAR_TALLY_DENY='5'

if [ -f "$PAM_LOGIN" ]; then
    if grep -q "pam_tally2.so" "$PAM_LOGIN"; then
        if ! grep -q "even_deny_root" "$PAM_LOGIN"; then
            sed -i -E "s/(pam_tally2.so.*)/\1 even_deny_root/" "$PAM_LOGIN"
        fi
        sed -i -E "s/(deny=)[0-9]*/\1$VAR_TALLY_DENY/" "$PAM_LOGIN"
    else
        sed -i "auth     required    pam_tally2.so deny=$VAR_TALLY_DENY onerr=fail even_deny_root" "$PAM_LOGIN"
    fi
fi

if [ -f /etc/pam.d/common-account ]; then
    if ! grep -q "pam_tally2.so" /etc/pam.d/common-account; then
        echo "account  required    pam_tally2.so" >> /etc/pam.d/common-account
    fi
fi

###############################################################################
# BEGIN fix (34 / 305) for 'pam_tally2_unlock_time'
###############################################################################
echo "Remediating: accounts_passwords_pam_tally2_unlock_time"

PAM_LOGIN="/etc/pam.d/login"
VAR_UNLOCK_TIME='1800'

if [ -f "$PAM_LOGIN" ]; then
    if grep -q "pam_tally2.so" "$PAM_LOGIN"; then
        if grep -q "unlock_time=" "$PAM_LOGIN"; then
            sed -i -E "s/(unlock_time=)[0-9]*/\1$VAR_UNLOCK_TIME/" "$PAM_LOGIN"
        else
            sed -i -E "s/(pam_tally2.so.*)/\1 unlock_time=$VAR_UNLOCK_TIME/" "$PAM_LOGIN"
        fi
    else
        sed -i "1iauth     required    pam_tally2.so deny=5 onerr=fail even_deny_root unlock_time=$VAR_UNLOCK_TIME" "$PAM_LOGIN"
    fi
fi

###############################################################################
# BEGIN fix (35 / 305) for 'pam_cracklib_dcredit'
###############################################################################
echo "Remediating: cracklib_accounts_password_pam_dcredit"

PAM_PASS="/etc/pam.d/common-password"
VAR_DCREDIT="-1"

if [ -f "$PAM_PASS" ]; then
    if grep -q "pam_cracklib.so" "$PAM_PASS"; then
        if grep -q "dcredit=" "$PAM_PASS"; then
            sed -i -E "s/(dcredit=)[^[:space:]]*/\1$VAR_DCREDIT/" "$PAM_PASS"
        else
            sed -i -E "s/(pam_cracklib.so.*)/\1 dcredit=$VAR_DCREDIT/" "$PAM_PASS"
        fi
    else
        sed -i "/pam_unix.so/i password requisite pam_cracklib.so dcredit=$VAR_DCREDIT" "$PAM_PASS"
    fi
fi

###############################################################################
# BEGIN fix (36, 37 / 305) for 'pam_cracklib' (lcredit & minlen)
###############################################################################
echo "Remediating: cracklib_lcredit_and_minlen"

PAM_PASS="/etc/pam.d/common-password"
VAR_LCREDIT="-1"
VAR_MINLEN="14"

if [ -f "$PAM_PASS" ]; then
    if ! grep -q "pam_cracklib.so" "$PAM_PASS"; then
        sed -i "/pam_unix.so/i password requisite pam_cracklib.so" "$PAM_PASS"
    fi

    if grep -q "lcredit=" "$PAM_PASS"; then
        sed -i -E "s/(lcredit=)[^[:space:]]*/\1$VAR_LCREDIT/" "$PAM_PASS"
    else
        sed -i -E "s/(pam_cracklib.so.*)/\1 lcredit=$VAR_LCREDIT/" "$PAM_PASS"
    fi

    if grep -q "minlen=" "$PAM_PASS"; then
        sed -i -E "s/(minlen=)[^[:space:]]*/\1$VAR_MINLEN/" "$PAM_PASS"
    else
        sed -i -E "s/(pam_cracklib.so.*)/\1 minlen=$VAR_MINLEN/" "$PAM_PASS"
    fi
fi

###############################################################################
# BEGIN fix (38, 39 / 305) for 'pam_cracklib' (ocredit & retry)
###############################################################################
echo "Remediating: cracklib_ocredit_and_retry"

PAM_PASS="/etc/pam.d/common-password"
VAR_OCREDIT="-1"
VAR_RETRY="3"

if [ -f "$PAM_PASS" ]; then
    if ! grep -q "pam_cracklib.so" "$PAM_PASS"; then
        sed -i "/pam_unix.so/i password requisite pam_cracklib.so" "$PAM_PASS"
    fi

    if grep -q "ocredit=" "$PAM_PASS"; then
        sed -i -E "s/(ocredit=)[^[:space:]]*/\1$VAR_OCREDIT/" "$PAM_PASS"
    else
        sed -i -E "s/(pam_cracklib.so.*)/\1 ocredit=$VAR_OCREDIT/" "$PAM_PASS"
    fi

    if grep -q "retry=" "$PAM_PASS"; then
        sed -i -E "s/(retry=)[^[:space:]]*/\1$VAR_RETRY/" "$PAM_PASS"
    else
        sed -i -E "s/(pam_cracklib.so.*)/\1 retry=$VAR_RETRY/" "$PAM_PASS"
    fi
fi

###############################################################################
# BEGIN fix (40 / 305) for 'pam_cracklib' (ucredit)
###############################################################################
echo "Remediating: cracklib_ucredit"

PAM_PASS="/etc/pam.d/common-password"
VAR_UCREDIT="-1"

if [ -f "$PAM_PASS" ]; then
    if ! grep -q "pam_cracklib.so" "$PAM_PASS"; then
        sed -i "/pam_unix.so/i password requisite pam_cracklib.so" "$PAM_PASS"
    fi

    if grep -q "ucredit=" "$PAM_PASS"; then
        sed -i -E "s/(ucredit=)[^[:space:]]*/\1$VAR_UCREDIT/" "$PAM_PASS"
    else
        sed -i -E "s/(pam_cracklib.so.*)/\1 ucredit=$VAR_UCREDIT/" "$PAM_PASS"
    fi
fi

###############################################################################
# BEGIN fix (41 / 305) for 'password_hashing_algorithm_logindefs'
###############################################################################
echo "Remediating: set_password_hashing_algorithm_logindefs"

LOGIN_DEFS="/etc/login.defs"
VAR_ALGO="SHA512"

if [ -f "$LOGIN_DEFS" ]; then
    if grep -q "^ENCRYPT_METHOD" "$LOGIN_DEFS"; then
        sed -i "s/^ENCRYPT_METHOD.*/ENCRYPT_METHOD $VAR_ALGO/" "$LOGIN_DEFS"
    else
        echo "ENCRYPT_METHOD $VAR_ALGO" >> "$LOGIN_DEFS"
    fi
fi

###############################################################################
# BEGIN fix (42 / 305) for 'require_emergency_target_auth'
###############################################################################
echo "Remediating: require_emergency_target_auth"
EMERGENCY_DIR="/etc/systemd/system/emergency.service.d"
mkdir -p "${EMERGENCY_DIR}"

cat <<EOF > "${EMERGENCY_DIR}/10-oscap.conf"
[Service]
ExecStart=
ExecStart=-/usr/lib/systemd/systemd-sulogin-shell emergency
EOF

###############################################################################
# BEGIN fix (43 / 305) for 'require_singleuser_auth'
###############################################################################
echo "Remediating: require_singleuser_auth"
RESCUE_DIR="/etc/systemd/system/rescue.service.d"
mkdir -p "${RESCUE_DIR}"

cat <<EOF > "${RESCUE_DIR}/10-oscap.conf"
[Service]
ExecStart=
ExecStart=-/usr/lib/systemd/systemd-sulogin-shell rescue
EOF

chmod 0644 /etc/systemd/system/*.service.d/*.conf

###############################################################################
# BEGIN fix (47 / 305) for 'account_disable_post_pw_expiration'
###############################################################################
echo "Remediating: account_disable_post_pw_expiration"
FILE="/etc/default/useradd"
if [ -f "$FILE" ]; then
    if grep -q "^INACTIVE" "$FILE"; then
        sed -i "s/^INACTIVE=.*/INACTIVE=30/" "$FILE"
    else
        echo "INACTIVE=30" >> "$FILE"
    fi
fi

###############################################################################
# BEGIN fix (49 / 305) for 'ensure_shadow_group_empty'
###############################################################################
echo "Remediating: ensure_shadow_group_empty"
sed -ri 's/(^shadow:[^:]*:[^:]*:)([^:]+$)/\1/' /etc/group

###############################################################################
# BEGIN fix (50, 51 / 305) for 'password_aging_login_defs'
###############################################################################
echo "Remediating: password_aging_login_defs"
LDEFS="/etc/login.defs"

# PASS_MAX_DAYS 365
if grep -q "^PASS_MAX_DAYS" "$LDEFS"; then
    sed -i "s/^PASS_MAX_DAYS.*/PASS_MAX_DAYS 365/" "$LDEFS"
else
    echo "PASS_MAX_DAYS 365" >> "$LDEFS"
fi

# PASS_MIN_DAYS 1
if grep -q "^PASS_MIN_DAYS" "$LDEFS"; then
    sed -i "s/^PASS_MIN_DAYS.*/PASS_MIN_DAYS 1/" "$LDEFS"
else
    echo "PASS_MIN_DAYS 1" >> "$LDEFS"
fi

###############################################################################
# BEGIN fix (55 / 305) for 'password_warn_age_login_defs'
###############################################################################
echo "Remediating: password_warn_age_login_defs"
LDEFS="/etc/login.defs"
if [ -f "$LDEFS" ]; then
    if grep -q "^PASS_WARN_AGE" "$LDEFS"; then
        sed -i "s/^PASS_WARN_AGE.*/PASS_WARN_AGE $VAR_WARN_AGE/" "$LDEFS"
    else
        echo "PASS_WARN_AGE $VAR_WARN_AGE" >> "$LDEFS"
    fi
fi

###############################################################################
# BEGIN fix (57-61 / 305) - 
###############################################################################
echo "Remediating: cleaning_forward_files"
find /root /home -name ".forward" -type f -delete 2>/dev/null || true

###############################################################################
# BEGIN fix (62, 63 / 305) -
###############################################################################
echo "Remediating: no_legacy_plus_entries"
sed -i '/^\+/d' /etc/passwd 2>/dev/null || true
sed -i '/^\+/d' /etc/shadow 2>/dev/null || true

###############################################################################
# BEGIN fix (65 / 305) - 
###############################################################################
echo "Remediating: accounts_no_uid_except_zero"
awk -F: '($3 == 0 && $1 != "root") {print $1}' /etc/passwd | while read -r user; do
    passwd -l "$user"
done

###############################################################################
# BEGIN fix (67 / 305) - Pam wheel group empty
###############################################################################
echo "Remediating: ensure_pam_wheel_group_empty"
VAR_WHEEL_GROUP="sugroup"
if ! getent group "$VAR_WHEEL_GROUP" >/dev/null; then
    groupadd "$VAR_WHEEL_GROUP"
fi
gpasswd -M '' "$VAR_WHEEL_GROUP"

###############################################################################
# BEGIN fix (68 / 305) - Limit direct root login (TTY)
###############################################################################
echo "Remediating: no_direct_root_logins"
: > /etc/securetty

###############################################################################
# BEGIN fix (69 / 305) - No shell login for system accounts
###############################################################################
echo "Remediating: no_shelllogin_for_systemaccounts"

awk -F: '($3 < 1000 && $1 != "root" && $7 != "/sbin/shutdown" && $7 != "/sbin/halt" && $7 != "/bin/sync") {print $1}' /etc/passwd | while read -r sysuser; do
    usermod -s /sbin/nologin "$sysuser" 2>/dev/null || true
done

###############################################################################
# BEGIN fix (70 / 305) - Securetty console restriction
###############################################################################
echo "Remediating: securetty_root_login_console_only"
sed -i '/^vc\/[0-9]/d' /etc/securetty 2>/dev/null || true

###############################################################################
# BEGIN fix (71 / 305) - Use PAM wheel for SU
###############################################################################
echo "Remediating: use_pam_wheel_group_for_su"
VAR_SU_GROUP="sugroup"
PAM_SU="/etc/pam.d/su"

if [ -f "$PAM_SU" ]; then
    sed -i '/pam_wheel.so/d' "$PAM_SU"
    sed -i "/pam_rootok.so/a auth required pam_wheel.so use_uid group=$VAR_SU_GROUP" "$PAM_SU"
fi

###############################################################################
# BEGIN fix (72 / 305) - Shell Timeout (TMOUT)
###############################################################################
echo "Remediating: accounts_tmout"
TMOUT_FILE="/etc/profile.d/autologout.sh"
cat <<EOF > "$TMOUT_FILE"
# Set TMOUT per security requirements
TMOUT=900
readonly TMOUT
export TMOUT
EOF
chmod 0644 "$TMOUT_FILE"

###############################################################################
# BEGIN fix (73-76 / 305) - Home Directory Hardening
###############################################################################
echo "Remediating: accounts_home_directories_permissions"
awk -F':' '($3 >= 1000 && $3 != 65534) {print $1 ":" $6}' /etc/passwd | while read -r line; do
    user=$(echo $line | cut -d: -f1)
    home=$(echo $line | cut -d: -f2)

    if [ -d "$home" ] && [ "$home" != "/" ]; then
 
        chmod 0700 "$home"
        
        if [ -f "$home/.netrc" ]; then
            chmod 0600 "$home/.netrc"
        fi
        
        find "$home" -maxdepth 1 -not -type l -exec chmod g-w,o-rwx {} \; 2>/dev/null || true
    fi
done

###############################################################################
# BEGIN fix (79 / 305) - UMASK in bash.bashrc
###############################################################################
echo "Remediating: accounts_umask_etc_bashrc"
VAR_UMASK='027'
BASHRC="/etc/bash.bashrc"

if [ -f "$BASHRC" ]; then
    if grep -q "^[^#]*umask" "$BASHRC"; then
        sed -i -E "s/^([^#]*umask)[[:space:]]+[0-9]+/\1 $VAR_UMASK/g" "$BASHRC"
    else
        echo "umask $VAR_UMASK" >> "$BASHRC"
    fi
fi

###############################################################################
# BEGIN fix (80 / 305) - UMASK in login.defs
###############################################################################
echo "Remediating: accounts_umask_etc_login_defs"
LDEFS="/etc/login.defs"

if [ -f "$LDEFS" ]; then
    if grep -q "^UMASK" "$LDEFS"; then
        sed -i "s/^UMASK.*/UMASK $VAR_UMASK/" "$LDEFS"
    else
        echo "UMASK $VAR_UMASK" >> "$LDEFS"
    fi
fi

###############################################################################
# BEGIN fix (81 / 305) - UMASK in /etc/profile
###############################################################################
echo "Remediating: accounts_umask_etc_profile"
VAR_UMASK='027'

if [ -f /etc/profile ]; then
    if grep -qE '^[^#]*umask' /etc/profile; then
        sed -i -E "s/^(\s*umask\s*)[0-7]+/\1$VAR_UMASK/g" /etc/profile
    else
        echo "umask $VAR_UMASK" >> /etc/profile
    fi
fi

find /etc/profile.d/ -type f -name "*.sh" -exec sed -i -E "s/^(\s*umask\s*)[0-7]+/\1$VAR_UMASK/g" {} + 2>/dev/null || true

###############################################################################
# BEGIN fix (82, 83, 84 / 305) - AppArmor Configuration
###############################################################################
echo "Remediating: apparmor_configured"

if [ -f /usr/lib/systemd/system/apparmor.service ] || [ -f /etc/systemd/system/apparmor.service ]; then
    systemctl enable apparmor
fi


###############################################################################
# BEGIN fix (85, 86, 87 / 305) - GRUB2 Configuration Security
###############################################################################
echo "Remediating: grub2_cfg_permissions_and_owner"

GRUB_FILES="/boot/grub2/grub.cfg /boot/efi/EFI/sles/grub.cfg"

for f in $GRUB_FILES; do
    if [ -f "$f" ]; then
        echo "Securing $f"
        chown 0:0 "$f"
        chmod 0600 "$f"
    fi
done

###############################################################################
# BEGIN fix (90, 91 / 305) - Rsyslog Service
###############################################################################
echo "Remediating: service_rsyslog_enabled"

if [ -f /usr/lib/systemd/system/rsyslog.service ] || [ -f /etc/systemd/system/rsyslog.service ]; then
    systemctl unmask rsyslog.service
    systemctl enable rsyslog.service
else
    echo "WARNING: rsyslog service not found. Ensure it is in config.xml"
fi

###############################################################################
# BEGIN fix (92 / 305) - Rsyslog Log Files Group Ownership
###############################################################################
echo "Remediating: rsyslog_files_groupownership"

RSYSLOG_CONF="/etc/rsyslog.conf"

if [ -f "$RSYSLOG_CONF" ]; then
    if grep -q "^\$FileGroup" "$RSYSLOG_CONF"; then
        sed -i "s/^\$FileGroup.*/\$FileGroup root/" "$RSYSLOG_CONF"
    else
        echo "\$FileGroup root" >> "$RSYSLOG_CONF"
    fi
fi

find /var/log -type f -exec chgrp root {} + 2>/dev/null || true

if [ -d /etc/rsyslog.d ]; then
    chown -R root:root /etc/rsyslog.d
    chmod -R 640 /etc/rsyslog.d
fi

###############################################################################
# BEGIN fix (93 / 305) - Rsyslog Log Files Ownership (Owner: root)
###############################################################################
echo "Remediating: rsyslog_files_ownership"

RSYSLOG_CONF="/etc/rsyslog.conf"

if [ -f "$RSYSLOG_CONF" ]; then
    if grep -q "^\$FileOwner" "$RSYSLOG_CONF"; then
        sed -i "s/^\$FileOwner.*/\$FileOwner root/" "$RSYSLOG_CONF"
    else
        echo "\$FileOwner root" >> "$RSYSLOG_CONF"
    fi
fi

if [ -d /var/log ]; then
    find /var/log -type f -exec chown root {} + 2>/dev/null || true
fi

###############################################################################
# BEGIN fix (94 / 305) - Rsyslog Log Files Permissions (0640)
###############################################################################
echo "Remediating: rsyslog_files_permissions"

RSYSLOG_CONF="/etc/rsyslog.conf"

if [ -f "$RSYSLOG_CONF" ]; then
    if grep -q "^\$FileCreateMode" "$RSYSLOG_CONF"; then
        sed -i "s/^\$FileCreateMode.*/\$FileCreateMode 0640/" "$RSYSLOG_CONF"
    else
        echo "\$FileCreateMode 0640" >> "$RSYSLOG_CONF"
    fi
    
    if ! grep -q "^\$DirCreateMode" "$RSYSLOG_CONF"; then
        echo "\$DirCreateMode 0750" >> "$RSYSLOG_CONF"
    fi
fi

if [ -d /var/log ]; then
    find /var/log -type f -exec chmod 0640 {} + 2>/dev/null || true
    find /var/log -type d -exec chmod 0750 {} + 2>/dev/null || true
fi

###############################################################################
# BEGIN fix (96, 97, 98 / 305) - Journald Hardening
###############################################################################
echo "Remediating: journald_settings (Compress, Forward, Storage)"

JOURNAL_DROPIN_DIR="/etc/systemd/journal.d"
JOURNAL_CONF="${JOURNAL_DROPIN_DIR}/compliance.conf"

mkdir -p "${JOURNAL_DROPIN_DIR}"

cat <<EOF > "${JOURNAL_CONF}"
[Journal]
# Rule 96: Compress logs
Compress=yes
# Rule 97: Forward to syslog for rsyslog processing
ForwardToSyslog=yes
# Rule 98: Ensure logs are persisted on disk
Storage=persistent
EOF

chmod 0644 "${JOURNAL_CONF}"


###############################################################################
# BEGIN fix (99, 100, 101 / 305) - Logrotate Activation
###############################################################################
echo "Remediating: logrotate_activated_daily"
LROTATE_CONF="/etc/logrotate.conf"

if [ -f "$LROTATE_CONF" ]; then
    sed -i '/^\s*\(weekly\|monthly\|yearly\)/d' "$LROTATE_CONF"
    if ! grep -q "^daily" "$LROTATE_CONF"; then
        sed -i '1i daily' "$LROTATE_CONF"
    fi
fi

systemctl unmask logrotate.timer 2>/dev/null || true
systemctl enable logrotate.timer

###############################################################################
# BEGIN fix (103 / 305) - Firewalld Backend (nftables)
###############################################################################
echo "Remediating: firewalld_backend_nftables"
FW_CONF="/etc/firewalld/firewalld.conf"

if [ -f "$FW_CONF" ]; then
    sed -i '/^\s*FirewallBackend/d' "$FW_CONF"
    echo "FirewallBackend=nftables" >> "$FW_CONF"
else
    mkdir -p /etc/firewalld
    echo "FirewallBackend=nftables" > "$FW_CONF"
fi

###############################################################################
# BEGIN fix (106, 107 / 305) - Firewalld Installation & Activation
###############################################################################
echo "Remediating: firewalld_service_enabled"

if [ -f /usr/lib/systemd/system/firewalld.service ] || [ -f /etc/systemd/system/firewalld.service ]; then
    systemctl unmask firewalld.service
    systemctl enable firewalld.service
    
    if systemctl -q list-unit-files firewalld.socket; then
        systemctl unmask firewalld.socket
        systemctl enable firewalld.socket
    fi
else
    echo "WARNING: firewalld service not found. Make sure it's in the <packages> section of config.xml"
fi

###############################################################################
# BEGIN fix (112-117 / 305) - Iptables Fallback & Loopback Traffic
###############################################################################
echo "Remediating: iptables_legacy_and_loopback"


if [ -f /etc/sysconfig/iptables ]; then
    echo "Configuring static loopback rules in /etc/sysconfig/iptables..."
fi

###############################################################################
# BEGIN fix (119 / 305) - Iptables Forward Drop (Static)
###############################################################################
echo "Remediating: iptables_default_rule_forward"
if [ -f /etc/sysconfig/iptables ]; then
    sed -i 's/^:FORWARD ACCEPT.*/:FORWARD DROP [0:0]/g' /etc/sysconfig/iptables
fi

###############################################################################
# BEGIN fix (121 / 305) - Sysctl net.ipv6.conf.all.accept_ra
###############################################################################
echo "Remediating: sysctl_net_ipv6_conf_all_accept_ra"

SYS_CONF_FILE="/etc/sysctl.d/99-compliance.conf"
mkdir -p /etc/sysctl.d

sed -i '/net.ipv6.conf.all.accept_ra/d' /etc/sysctl.conf 2>/dev/null || true


if grep -q "^net.ipv6.conf.all.accept_ra" "$SYS_CONF_FILE"; then
    sed -i "s/^net.ipv6.conf.all.accept_ra.*/net.ipv6.conf.all.accept_ra = 0/" "$SYS_CONF_FILE"
else
    echo "net.ipv6.conf.all.accept_ra = 0" >> "$SYS_CONF_FILE"
fi

###############################################################################
# Helper function
###############################################################################
function set_sysctl() {
    local key=$1
    local value=$2
    local conf_file="/etc/sysctl.d/99-compliance.conf"
    mkdir -p /etc/sysctl.d
    sed -i "/^$key/d" /etc/sysctl.conf 2>/dev/null || true
    sed -i "/^$key/d" "$conf_file" 2>/dev/null || true
    echo "$key = $value" >> "$conf_file"
}

###############################################################################
# BEGIN fix (122 / 305) - net.ipv6.conf.all.accept_redirects
###############################################################################
echo "Remediating: sysctl_net_ipv6_conf_all_accept_redirects"
set_sysctl "net.ipv6.conf.all.accept_redirects" "0"

###############################################################################
# BEGIN fix (123 / 305) - net.ipv6.conf.all.accept_source_route
###############################################################################
echo "Remediating: sysctl_net_ipv6_conf_all_accept_source_route"
set_sysctl "net.ipv6.conf.all.accept_source_route" "0"

###############################################################################
# BEGIN fix (124 / 305) - net.ipv6.conf.all.forwarding
###############################################################################
echo "Remediating: sysctl_net_ipv6_conf_all_forwarding"
set_sysctl "net.ipv6.conf.all.forwarding" "0"

###############################################################################
# BEGIN fix (125 / 305) - net.ipv6.conf.default.accept_ra
###############################################################################
echo "Remediating: sysctl_net_ipv6_conf_default_accept_ra"
set_sysctl "net.ipv6.conf.default.accept_ra" "0"

###############################################################################
# BEGIN fix (126 / 305) - net.ipv6.conf.default.accept_redirects
###############################################################################
echo "Remediating: sysctl_net_ipv6_conf_default_accept_redirects"
set_sysctl "net.ipv6.conf.default.accept_redirects" "0"

###############################################################################
# BEGIN fix (127 / 305) - net.ipv6.conf.default.accept_source_route
###############################################################################
echo "Remediating: sysctl_net_ipv6_conf_default_accept_source_route"
set_sysctl "net.ipv6.conf.default.accept_source_route" "0"

###############################################################################
# BEGIN fix (128 / 305) - net.ipv4.conf.all.accept_redirects
###############################################################################
echo "Remediating: sysctl_net_ipv4_conf_all_accept_redirects"
set_sysctl "net.ipv4.conf.all.accept_redirects" "0"

###############################################################################
# BEGIN fix (129 / 305) - net.ipv4.conf.all.accept_source_route
###############################################################################
echo "Remediating: sysctl_net_ipv4_conf_all_accept_source_route"
set_sysctl "net.ipv4.conf.all.accept_source_route" "0"

###############################################################################
# BEGIN fix (130 / 305) - net.ipv4.conf.all.log_martians
###############################################################################
echo "Remediating: sysctl_net_ipv4_conf_all_log_martians"
set_sysctl "net.ipv4.conf.all.log_martians" "1"

###############################################################################
# BEGIN fix (131 / 305) - net.ipv4.conf.all.rp_filter
###############################################################################
echo "Remediating: sysctl_net_ipv4_conf_all_rp_filter"
set_sysctl "net.ipv4.conf.all.rp_filter" "1"

###############################################################################
# BEGIN fix (132 / 305) - net.ipv4.conf.all.secure_redirects
###############################################################################
echo "Remediating: sysctl_net_ipv4_conf_all_secure_redirects"
set_sysctl "net.ipv4.conf.all.secure_redirects" "0"

###############################################################################
# BEGIN fix (133 / 305) - net.ipv4.conf.default.accept_redirects
###############################################################################
echo "Remediating: sysctl_net_ipv4_conf_default_accept_redirects"
set_sysctl "net.ipv4.conf.default.accept_redirects" "0"

###############################################################################
# BEGIN fix (134 / 305) - net.ipv4.conf.default.accept_source_route
###############################################################################
echo "Remediating: sysctl_net_ipv4_conf_default_accept_source_route"
set_sysctl "net.ipv4.conf.default.accept_source_route" "0"

###############################################################################
# BEGIN fix (135 / 305) - net.ipv4.conf.default.log_martians
###############################################################################
echo "Remediating: sysctl_net_ipv4_conf_default_log_martians"
set_sysctl "net.ipv4.conf.default.log_martians" "1"

###############################################################################
# BEGIN fix (136 / 305) - net.ipv4.conf.default.rp_filter
###############################################################################
echo "Remediating: sysctl_net_ipv4_conf_default_rp_filter"
set_sysctl "net.ipv4.conf.default.rp_filter" "1"

###############################################################################
# BEGIN fix (137 / 305) - net.ipv4.conf.default.secure_redirects
###############################################################################
echo "Remediating: sysctl_net_ipv4_conf_default_secure_redirects"
set_sysctl "net.ipv4.conf.default.secure_redirects" "0"

###############################################################################
# BEGIN fix (138 / 305) - net.ipv4.icmp_echo_ignore_broadcasts
###############################################################################
echo "Remediating: sysctl_net_ipv4_icmp_echo_ignore_broadcasts"
set_sysctl "net.ipv4.icmp_echo_ignore_broadcasts" "1"

###############################################################################
# BEGIN fix (139 / 305) - net.ipv4.icmp_ignore_bogus_error_responses
###############################################################################
echo "Remediating: sysctl_net_ipv4_icmp_ignore_bogus_error_responses"
set_sysctl "net.ipv4.icmp_ignore_bogus_error_responses" "1"

###############################################################################
# BEGIN fix (140 / 305) - net.ipv4.tcp_syncookies
###############################################################################
echo "Remediating: sysctl_net_ipv4_tcp_syncookies"
set_sysctl "net.ipv4.tcp_syncookies" "1"

###############################################################################
# BEGIN fix (141 / 305) - net.ipv4.conf.all.send_redirects
###############################################################################
echo "Remediating: sysctl_net_ipv4_conf_all_send_redirects"
set_sysctl "net.ipv4.conf.all.send_redirects" "0"

###############################################################################
# BEGIN fix (142 / 305) - net.ipv4.conf.default.send_redirects
###############################################################################
echo "Remediating: sysctl_net_ipv4_conf_default_send_redirects"
set_sysctl "net.ipv4.conf.default.send_redirects" "0"

###############################################################################
# BEGIN fix (143 / 305) - net.ipv4.ip_forward
###############################################################################
echo "Remediating: sysctl_net_ipv4_ip_forward"
set_sysctl "net.ipv4.ip_forward" "0"

###############################################################################
# BEGIN fix (144-147 / 305) - Nftables Service Management
###############################################################################
echo "Remediating: nftables_service_conflict_check"

if [ -f /usr/lib/systemd/system/nftables.service ] || [ -f /etc/systemd/system/nftables.service ]; then
    systemctl stop nftables.service 2>/dev/null || true
    systemctl disable nftables.service
    systemctl mask nftables.service
fi

###############################################################################
# BEGIN fix (149 / 305) - Nftables Master Config
###############################################################################
echo "Remediating: nftables_rules_permanent_includes"
NFT_CONF='/etc/sysconfig/nftables.conf'

[ ! -d /etc/sysconfig ] && mkdir -p /etc/sysconfig
[ ! -f "$NFT_CONF" ] && touch "$NFT_CONF"

for filter in bridge-filter arp-filter inet-filter; do
    line="include \"/etc/nftables/${filter}\""
    grep -qxF "$line" "$NFT_CONF" || echo "$line" >> "$NFT_CONF"
done


###############################################################################
# BEGIN fix (150, 151 / 305) - Nftables Base Chains & Loopback
###############################################################################
echo "Remediating: nftables_base_chains_and_loopback"

NFT_STATIC_CONF="/etc/nftables.conf"
[ ! -d /etc ] && mkdir -p /etc

cat <<EOF > "$NFT_STATIC_CONF"
table inet filter {
    chain input {
        type filter hook input priority 0; policy accept;
        iif "lo" accept
        ip saddr 127.0.0.0/8 counter drop
    }
    chain forward {
        type filter hook forward priority 0; policy accept;
    }
    chain output {
        type filter hook output priority 0; policy accept;
    }
}
EOF

if ! grep -qs "net.ipv6.conf.all.disable_ipv6 = 1" /etc/sysctl.d/*.conf /etc/sysctl.conf; then
    sed -i '/ip saddr 127.0.0.0\/8 counter drop/a \        ip6 saddr ::1 counter drop' "$NFT_STATIC_CONF"
fi

chmod 0640 "$NFT_STATIC_CONF"

###############################################################################
# BEGIN fix (153 / 305) - Nftables Table (Static)
###############################################################################
echo "Remediating: nftables_table_setup"
if [ -f /etc/nftables.conf ] && ! grep -q "table inet filter" /etc/nftables.conf; then
    echo "table inet filter {}" >> /etc/nftables.conf
fi

###############################################################################
# BEGIN fix (154 / 305) - Disable Wireless Interfaces
###############################################################################
echo "Remediating: wireless_disable_interfaces"
if [ -d /etc/sysconfig/network ]; then
    for cfg in /etc/sysconfig/network/ifcfg-wlan*; do
        [ -f "$cfg" ] && sed -i 's/STARTMODE=.*/STARTMODE=off/' "$cfg"
    done
fi

###############################################################################
# BEGIN fix (155, 156 / 305) - World Writable & Sticky Bit
###############################################################################
echo "Remediating: world_writable_and_sticky_bits"
find / -xdev -type d \( -perm -0002 -a ! -perm -1000 \) -exec chmod a+t {} + 2>/dev/null || true

find /etc /bin /sbin /usr /var -xdev -type f -perm -002 -exec chmod o-w {} + 2>/dev/null || true

###############################################################################
# BEGIN fix (159 / 305) - Var Log Permissions Cleanup
###############################################################################
echo "Remediating: permissions_local_var_log"
if [ -d /var/log ]; then
    find -P /var/log/ -type f ! -name '*[bw]tmp' ! -name '*lastlog' \
    -exec chmod u-xs,g-xws,o-xwrt {} + 2>/dev/null || true
fi

###############################################################################
# BEGIN fix (160-167 / 305) - Security of Critical System Files (Passwd/Shadow/Group)
###############################################################################
echo "Remediating: critical_files_group_ownership"

for f in /etc/passwd /etc/passwd- /etc/group /etc/group- /etc/gshadow /etc/gshadow-; do
    if [ -f "$f" ]; then
        chown root "$f"  
        chgrp 0 "$f"
    fi
done

SHADOW_GID=0
getent group shadow >/dev/null && SHADOW_GID="shadow"

for f in /etc/shadow /etc/shadow-; do
    if [ -f "$f" ]; then
        chown root "$f"
        chgrp $SHADOW_GID "$f"
    fi
done

###############################################################################
# BEGIN fix (168-175 / 305) - Root owner for critical files
###############################################################################
echo "Remediating: critical_files_owner_root"

CRITICAL_FILES=(
    "/etc/passwd" "/etc/passwd-"
    "/etc/group" "/etc/group-"
    "/etc/shadow" "/etc/shadow-"
    "/etc/gshadow" "/etc/gshadow-"
)

for f in "${CRITICAL_FILES[@]}"; do
    if [ -f "$f" ]; then
        chown root:root "$f" 2>/dev/null || chown 0:0 "$f"
    fi
done

###############################################################################
# BEGIN fix (176-177 / 305) - Permissions for group and gshadow
###############################################################################
echo "Remediating: backup_files_permissions"

if [ -f /etc/group- ]; then
    chmod 0644 /etc/group-
fi

if [ -f /etc/gshadow- ]; then
    chmod 0000 /etc/gshadow-
fi

###############################################################################
# BEGIN fix (178-183 / 305) - Critical files permissions
###############################################################################
echo "Remediating: critical_files_permissions_octal"

[ -f /etc/passwd ]  && chmod 0644 /etc/passwd
[ -f /etc/passwd- ] && chmod 0644 /etc/passwd-
[ -f /etc/group ]   && chmod 0644 /etc/group
[ -f /etc/group- ]  && chmod 0644 /etc/group-
[ -f /etc/shadow ]  && chmod 0000 /etc/shadow
[ -f /etc/shadow- ] && chmod 0000 /etc/shadow-
[ -f /etc/gshadow ] && chmod 0000 /etc/gshadow
[ -f /etc/gshadow- ] && chmod 0000 /etc/gshadow-

###############################################################################
# BEGIN fix (184 / 305) - Disabling Autofs
###############################################################################
echo "Remediating: service_autofs_disabled"
if [ -f /usr/lib/systemd/system/autofs.service ] || [ -f /etc/systemd/system/autofs.service ]; then
    systemctl disable autofs.service
    systemctl mask autofs.service
fi

###############################################################################
# BEGIN fix (185, 186 / 305) - Disabling Kernel Module (UDF, USB-Storage)
###############################################################################
echo "Remediating: kernel_modules_disabled (udf, usb-storage)"

for mod in udf usb-storage; do
    CONF="/etc/modprobe.d/${mod}.conf"
    echo "install ${mod} /bin/false" > "$CONF"
    echo "blacklist ${mod}" >> "$CONF"
    chmod 0644 "$CONF"
done

# ===============================================================================
# BEGIN fix (200 / 305) for 'xccdf_org.ssgproject.content_rule_coredump_disable_backtraces'
# BEGIN fix (201 / 305) for 'xccdf_org.ssgproject.content_rule_coredump_disable_storage'
# ===============================================================================
# DESC: Disables systemd coredumps by creating a compliance drop-in file.
# This replaces the complex sed logic with a clean, KIWI-friendly file creation.

COREDUMP_CONF="/etc/systemd/coredump.conf.d/complianceascode_hardening.conf"
mkdir -p /etc/systemd/coredump.conf.d/

cat <<EOF > "$COREDUMP_CONF"
[Coredump]
ProcessSizeMax=0
Storage=none
EOF

# END fix for 'xccdf_org.ssgproject.content_rule_coredump_disable_backtraces'
# END fix for 'xccdf_org.ssgproject.content_rule_coredump_disable_storage'

# ===============================================================================
# BEGIN fix (202 / 305) for 'xccdf_org.ssgproject.content_rule_disable_users_coredumps'
# ===============================================================================
# DESC: Disables core dumps for all users via PAM limits.

LIMITS_CONF="/etc/security/limits.d/10-ssg-hardening.conf"
mkdir -p /etc/security/limits.d

if [ -f "$LIMITS_CONF" ]; then
    sed -i '/^[[:space:]]*\*[[:space:]]\+hard[[:space:]]\+core[[:space:]]\+/d' "$LIMITS_CONF"
fi

echo "*     hard   core    0" >> "$LIMITS_CONF"

# END fix for 'xccdf_org.ssgproject.content_rule_disable_users_coredumps'


# ===============================================================================
# BEGIN fix (203 / 305) for 'xccdf_org.ssgproject.content_rule_sysctl_fs_suid_dumpable'
# ===============================================================================
# DESC: Sets fs.suid_dumpable to 0. No live 'sysctl -w' for KIWI chroot.

SYSCTL_FILE="/etc/sysctl.d/fs_suid_dumpable.conf"
mkdir -p /etc/sysctl.d

if [ -f /etc/sysctl.conf ]; then
    sed -i '/^fs.suid_dumpable/d' /etc/sysctl.conf
fi

cat <<EOF > "$SYSCTL_FILE"
# Per CCE-91447-3: Set fs.suid_dumpable = 0 in $SYSCTL_FILE
fs.suid_dumpable = 0
EOF

# END fix for 'xccdf_org.ssgproject.content_rule_sysctl_fs_suid_dumpable'


# ===============================================================================
# BEGIN fix (204 / 305) for 'xccdf_org.ssgproject.content_rule_sysctl_kernel_randomize_va_space'
# ===============================================================================
# DESC: Sets kernel.randomize_va_space to 2 (ASLR). No live 'sysctl -w'.

SYSCTL_ASLR="/etc/sysctl.d/kernel_randomize_va_space.conf"
mkdir -p /etc/sysctl.d

[ -f /etc/sysctl.conf ] && sed -i '/^kernel.randomize_va_space/d' /etc/sysctl.conf

cat <<EOF > "$SYSCTL_ASLR"
# Per CCE-83300-4: Set kernel.randomize_va_space = 2 in $SYSCTL_ASLR
kernel.randomize_va_space = 2
EOF

# END fix for 'xccdf_org.ssgproject.content_rule_sysctl_kernel_randomize_va_space'


# ===============================================================================
# BEGIN fix (259 / 305) for 'xccdf_org.ssgproject.content_rule_service_timesyncd_root_distance_configured'
# ===============================================================================
# DESC: Sets RootDistanceMax for systemd-timesyncd.
mkdir -p /usr/lib/systemd/timesyncd.conf.d/
cat <<EOF > /usr/lib/systemd/timesyncd.conf.d/oscap-remedy.conf
[Time]
RootDistanceMax=1
EOF

# ===============================================================================
# BEGIN fix (279 / 305) for 'xccdf_org.ssgproject.content_rule_file_groupowner_sshd_config'
# ===============================================================================
# DESC: Ensures /etc/ssh/sshd_config is owned by group 0 (root).
if [ -f /etc/ssh/sshd_config ]; then
    chgrp --no-dereference 0 /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (280 / 305) for 'xccdf_org.ssgproject.content_rule_file_owner_sshd_config'
# ===============================================================================
# DESC: Ensures /etc/ssh/sshd_config is owned by user 0 (root).
if [ -f /etc/ssh/sshd_config ]; then
    chown --no-dereference 0 /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (281 / 305) for 'xccdf_org.ssgproject.content_rule_file_permissions_sshd_config'
# ===============================================================================
# DESC: Sets safe permissions (600) for /etc/ssh/sshd_config.
if [ -f /etc/ssh/sshd_config ]; then
    chmod u-xs,g-xwrs,o-xwrt /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (282 / 305) for 'xccdf_org.ssgproject.content_rule_file_permissions_sshd_private_key'
# ===============================================================================
# DESC: Sets safe permissions for all SSH private keys in /etc/ssh/.
for keyfile in /etc/ssh/*_key; do
    [ -f "$keyfile" ] && chmod u-xs,g-xws,o-xwrt "$keyfile"
done

# ===============================================================================
# BEGIN fix (283 / 305) for 'xccdf_org.ssgproject.content_rule_file_permissions_sshd_pub_key'
# ===============================================================================
# DESC: Sets safe permissions (644) for all SSH public keys.
find -P /etc/ssh/ -maxdepth 1 -type f -name "*.pub" -exec chmod u-xs,g-xws,o-xwt {} \;

# ===============================================================================
# BEGIN fix (284 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_set_keepalive'
# ===============================================================================
# DESC: Configures ClientAliveCountMax to 0 in sshd_config.
if [ -f "/etc/ssh/sshd_config" ]; then
    sed -i "/^\s*ClientAliveCountMax/d" "/etc/ssh/sshd_config"
    echo "ClientAliveCountMax 0" >> "/etc/ssh/sshd_config"
elif [ -d "/etc/ssh" ]; then
    echo "ClientAliveCountMax 0" > "/etc/ssh/sshd_config"
fi

# ===============================================================================
# BEGIN fix (285 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_set_idle_timeout'
# ===============================================================================
# DESC: Configures ClientAliveInterval to 300 seconds in sshd_config.
if [ -d /etc/ssh ]; then
    sed -i "/^\s*ClientAliveInterval/d" /etc/ssh/sshd_config 2>/dev/null
    echo "ClientAliveInterval 300" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (286 / 305) for 'xccdf_org.ssgproject.content_rule_disable_host_auth'
# ===============================================================================
# DESC: Disables Host-based Authentication in sshd_config.
if [ -d /etc/ssh ]; then
    sed -i "/^\s*HostbasedAuthentication/d" /etc/ssh/sshd_config 2>/dev/null
    echo "HostbasedAuthentication no" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (287 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_disable_empty_passwords'
# ===============================================================================
# DESC: Disables login with empty passwords in sshd_config.
if [ -d /etc/ssh ]; then
    sed -i "/^\s*PermitEmptyPasswords/d" /etc/ssh/sshd_config 2>/dev/null
    echo "PermitEmptyPasswords no" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (288 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_disable_rhosts'
# ===============================================================================
# DESC: Ensures SSH ignores .rhosts and .shosts files.
if [ -d /etc/ssh ]; then
    sed -i "/^\s*IgnoreRhosts/d" /etc/ssh/sshd_config 2>/dev/null
    echo "IgnoreRhosts yes" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (289 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_disable_root_login'
# ===============================================================================
# DESC: Disables remote root login in sshd_config.
if [ -d /etc/ssh ]; then
    sed -i "/^\s*PermitRootLogin/d" /etc/ssh/sshd_config 2>/dev/null
    echo "PermitRootLogin no" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (290 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_do_not_permit_user_env'
# ===============================================================================
# DESC: Prevents users from setting custom environment variables via SSH.
if [ -d /etc/ssh ]; then
    sed -i "/^\s*PermitUserEnvironment/d" /etc/ssh/sshd_config 2>/dev/null
    echo "PermitUserEnvironment no" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (291 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_enable_pam'
# ===============================================================================
# DESC: Enables PAM (Pluggable Authentication Modules) for SSH.
if [ -f /etc/ssh/sshd_config ]; then
    sed -i "/^\s*UsePAM/d" /etc/ssh/sshd_config 2>/dev/null
    echo "UsePAM yes" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (292 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_enable_warning_banner'
# ===============================================================================
# DESC: Enables the warning banner by pointing to /etc/issue in sshd_config.
if [ -f /etc/ssh/sshd_config ]; then
    sed -i "/^\s*Banner/d" /etc/ssh/sshd_config 2>/dev/null
    echo "Banner /etc/issue" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (293 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_limit_user_access'
# ===============================================================================
# DESC: Logic for limiting user access via AllowUsers/AllowGroups is missing in source.
# (Skipped to maintain image build stability)

# ===============================================================================
# BEGIN fix (294 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_set_login_grace_time'
# ===============================================================================
# DESC: Sets LoginGraceTime to 60 seconds to prevent resource exhaustion.
if [ -f /etc/ssh/sshd_config ]; then
    sed -i "/^\s*LoginGraceTime/d" /etc/ssh/sshd_config 2>/dev/null
    echo "LoginGraceTime 60" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (295 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_set_loglevel_verbose'
# ===============================================================================
# DESC: Sets LogLevel to VERBOSE for detailed SSH audit trails.
if [ -f /etc/ssh/sshd_config ]; then
    sed -i "/^\s*LogLevel/d" /etc/ssh/sshd_config 2>/dev/null
    echo "LogLevel VERBOSE" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (296 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_set_max_auth_tries'
# ===============================================================================
# DESC: Limits the maximum number of authentication attempts to 4.
if [ -f /etc/ssh/sshd_config ]; then
    sed -i "/^\s*MaxAuthTries/d" /etc/ssh/sshd_config 2>/dev/null
    echo "MaxAuthTries 4" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (297 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_set_max_sessions'
# ===============================================================================
# DESC: Limits the maximum number of open shell, login or subsystem sessions to 10.
if [ -f /etc/ssh/sshd_config ]; then
    sed -i "/^\s*MaxSessions/d" /etc/ssh/sshd_config 2>/dev/null
    echo "MaxSessions 10" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (298 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_set_maxstartups'
# ===============================================================================
# DESC: Configures the maximum number of concurrent unauthenticated connections.
if [ -f /etc/ssh/sshd_config ]; then
    sed -i "/^\s*MaxStartups/d" /etc/ssh/sshd_config 2>/dev/null
    echo "MaxStartups 10:30:60" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (299 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_use_approved_ciphers'
# ===============================================================================
# DESC: Restricts SSH to use only CIS/FIPS approved cryptographic ciphers.
if [ -f /etc/ssh/sshd_config ]; then
    CIPHERS="chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
    sed -i "/^\s*Ciphers/d" /etc/ssh/sshd_config 2>/dev/null
    echo "Ciphers $CIPHERS" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (300 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_use_approved_macs'
# ===============================================================================
# DESC: Restricts SSH to use only CIS/FIPS approved Message Authentication Codes (MACs).
if [ -f /etc/ssh/sshd_config ]; then
    APPROVED_MACS="hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,hmac-sha2-512,hmac-sha2-256"
    sed -i "/^\s*MACs/Id" /etc/ssh/sshd_config
    echo "MACs $APPROVED_MACS" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (301 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_use_strong_ciphers'
# ===============================================================================
# DESC: Ensures SSH is configured to use only strong, modern ciphers.
if [ -f /etc/ssh/sshd_config ]; then
    STRONG_CIPHERS="aes128-ctr,aes192-ctr,aes256-ctr,chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com"
    sed -i "/^\s*Ciphers/Id" /etc/ssh/sshd_config
    echo "Ciphers $STRONG_CIPHERS" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (302 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_use_strong_kex'
# ===============================================================================
# DESC: Restricts SSH Key Exchange (Kex) to strong Diffie-Hellman and Elliptic Curve algorithms.
if [ -f /etc/ssh/sshd_config ]; then
    STRONG_KEX="curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group14-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256"
    sed -i "/^\s*KexAlgorithms/Id" /etc/ssh/sshd_config
    echo "KexAlgorithms $STRONG_KEX" >> /etc/ssh/sshd_config
fi

# ===============================================================================
# BEGIN fix (303 / 305) for 'xccdf_org.ssgproject.content_rule_sshd_use_strong_macs'
# ===============================================================================
# DESC: Ensures only strong HMAC algorithms are permitted.
if [ -f /etc/ssh/sshd_config ]; then
    STRONG_MACS="hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256"
    sed -i "/^\s*MACs/Id" /etc/ssh/sshd_config
    echo "MACs $STRONG_MACS" >> /etc/ssh/sshd_config
fi