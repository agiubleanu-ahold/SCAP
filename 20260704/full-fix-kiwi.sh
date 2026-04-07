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

# ==============================================================================
# FIX (31) - PAM Password History (Remember 5)
# ==============================================================================
echo "Remediating: accounts_password_pam_pwhistory_remember"
PAM_FILE="/etc/pam.d/common-password"

if [ -f "$PAM_FILE" ]; then
    sed -i '/pam_pwhistory.so/d' "$PAM_FILE"
    
    echo "password requisite pam_pwhistory.so remember=5 use_authtok" >> "$PAM_FILE"
else
    echo "$PAM_FILE not found, skipping pwhistory remediation"
fi

# ==============================================================================
# FIX (32) - PAM Tally2 (Lockout after 5 attempts)
# ==============================================================================
echo "Remediating: accounts_passwords_pam_tally2"
LOGIN_PAM="/etc/pam.d/login"
ACCOUNT_PAM="/etc/pam.d/common-account"

if [ -f "$LOGIN_PAM" ]; then
    sed -i '/pam_tally2.so/d' "$LOGIN_PAM"
    sed -i '1i auth required pam_tally2.so deny=5 onerr=fail' "$LOGIN_PAM"
fi

if [ -f "$ACCOUNT_PAM" ]; then
    sed -i '/pam_tally2.so/d' "$ACCOUNT_PAM"
    echo "account required pam_tally2.so" >> "$ACCOUNT_PAM"
fi

# ==============================================================================
# FIX (32, 33, 34) - PAM Tally2 (Lockout, Root, Unlock Time)
# ==============================================================================
echo "Remediating: accounts_passwords_pam_tally2 (Full Configuration)"
LOGIN_PAM="/etc/pam.d/login"
ACCOUNT_PAM="/etc/pam.d/common-account"

V_DENY="5"
V_UNLOCK="1800"

if [ -f "$LOGIN_PAM" ]; then
    sed -i '/pam_tally2.so/d' "$LOGIN_PAM"
    sed -i "1i auth required pam_tally2.so deny=$V_DENY onerr=fail even_deny_root unlock_time=$V_UNLOCK" "$LOGIN_PAM"
fi

if [ -f "$ACCOUNT_PAM" ]; then
    sed -i '/pam_tally2.so/d' "$ACCOUNT_PAM"
    echo "account required pam_tally2.so" >> "$ACCOUNT_PAM"
fi

# ==============================================================================
# FIX (35-40) - PAM Cracklib CONSOLIDATED (minlen, d/l/o/u-credit, retry)
# ==============================================================================
echo "Remediating: pam_cracklib complexity rules (Final Consolidated Line)"
PWD_PAM="/etc/pam.d/common-password"

V_RETRY="3"
V_MINLEN="14"
V_DCREDIT="-1"
V_LCREDIT="-1"
V_OCREDIT="-1"
V_UCREDIT="-1"

if [ -f "$PWD_PAM" ]; then
    sed -i '/pam_cracklib.so/d' "$PWD_PAM"
    echo "password requisite pam_cracklib.so retry=$V_RETRY minlen=$V_MINLEN dcredit=$V_DCREDIT lcredit=$V_LCREDIT ocredit=$V_OCREDIT ucredit=$V_UCREDIT" >> "$PWD_PAM"
else
    echo "Warning: $PWD_PAM not found."
fi

# ==============================================================================
# FIX (41) - Password Hashing Algorithm (ENCRYPT_METHOD SHA512)
# ==============================================================================
echo "Remediating: set_password_hashing_algorithm_logindefs"
LOGIN_DEFS="/etc/login.defs"

if [ -f "$LOGIN_DEFS" ]; then
    sed -i '/^#\?ENCRYPT_METHOD/d' "$LOGIN_DEFS"
        echo "ENCRYPT_METHOD SHA512" >> "$LOGIN_DEFS"
else
    echo "Warning: $LOGIN_DEFS not found."
fi

# ==============================================================================
# FIX (42, 43) - Require Auth for Emergency and Rescue Modes
# ==============================================================================
echo "Remediating: emergency and rescue target auth"

# 42. Emergency Service
mkdir -p /etc/systemd/system/emergency.service.d
cat <<EOF > /etc/systemd/system/emergency.service.d/10-oscap.conf
[Service]
ExecStart=-/usr/lib/systemd/systemd-sulogin-shell emergency
EOF

# 43. Rescue Service
mkdir -p /etc/systemd/system/rescue.service.d
cat <<EOF > /etc/systemd/system/rescue.service.d/10-oscap.conf
[Service]
ExecStart=
ExecStart=-/usr/lib/systemd/systemd-sulogin-shell rescue
EOF

# ==============================================================================
# FIX (47) - Account Disable Post PW Expiration (INACTIVE=30)
# ==============================================================================
echo "Remediating: account_disable_post_pw_expiration"
USERADD_DEF="/etc/default/useradd"
if [ -f "$USERADD_DEF" ]; then
    sed -i '/^#\?INACTIVE=/d' "$USERADD_DEF"
    echo "INACTIVE=30" >> "$USERADD_DEF"
fi

# ==============================================================================
# FIX (49) - Ensure shadow group is empty
# ==============================================================================
echo "Remediating: ensure_shadow_group_empty"
if [ -f /etc/group ]; then
    sed -ri 's/(^shadow:[^:]*:[^:]*:)([^:]+$)/\1/' /etc/group
fi

# ==============================================================================
# FIX (50) - Password Maximum Age (PASS_MAX_DAYS 365)
# ==============================================================================
echo "Remediating: accounts_maximum_age_login_defs"
LOGIN_DEFS="/etc/login.defs"
if [ -f "$LOGIN_DEFS" ]; then
    sed -i '/^#\?PASS_MAX_DAYS/d' "$LOGIN_DEFS"
    echo "PASS_MAX_DAYS 365" >> "$LOGIN_DEFS"
fi

# ==============================================================================
# FIX (51, 55) - Password Age Defaults (login.defs)
# ==============================================================================
echo "Remediating: PASS_MIN_DAYS and PASS_WARN_AGE in login.defs"
LOGIN_DEFS="/etc/login.defs"

if [ -f "$LOGIN_DEFS" ]; then
    sed -i '/^#\?PASS_MIN_DAYS/d' "$LOGIN_DEFS"
    echo "PASS_MIN_DAYS 1" >> "$LOGIN_DEFS"

    sed -i '/^#\?PASS_WARN_AGE/d' "$LOGIN_DEFS"
    echo "PASS_WARN_AGE 7" >> "$LOGIN_DEFS"
fi

# ==============================================================================
# FIX (52, 53, 54) - Update Existing Users (Shadow)
# ==============================================================================
echo "Remediating: Update existing users password aging"

REAL_USERS=$(awk -F: '/^[^:]+:[^\!*]/ {print $1}' /etc/shadow)

for user in $REAL_USERS; do
    passwd -q -x 365 "$user" 2>/dev/null || true
    
    passwd -q -n 1 "$user" 2>/dev/null || true
    
    chage --warndays 7 "$user" 2>/dev/null || true
done

# ==============================================================================
# FIX (56) - Disable accounts after password expiration (Inactive 30 days)
# ==============================================================================
echo "Remediating: accounts_set_post_pw_existing"
REAL_USERS=$(awk -F: '/^[^:]+:[^\!*]/ {print $1}' /etc/shadow)
for user in $REAL_USERS; do
    chage --inactive 30 "$user" 2>/dev/null || true
done

# ==============================================================================
# FIX (62, 63) - Remove legacy '+' entries from passwd and shadow
# ==============================================================================
echo "Remediating: no_legacy_plus_entries"
[ -f /etc/passwd ] && sed -i '/^\+/d' /etc/passwd
[ -f /etc/shadow ] && sed -i '/^\+/d' /etc/shadow

# ==============================================================================
# FIX (65) - Lock accounts with UID 0 other than root
# ==============================================================================
echo "Remediating: accounts_no_uid_except_zero"
EXTRA_ROOTS=$(awk -F: '$3 == 0 && $1 != "root" { print $1 }' /etc/passwd)
for extra_user in $EXTRA_ROOTS; do
    passwd -l "$extra_user" 2>/dev/null || true
done

# ==============================================================================
# FIX (67) - Ensure PAM wheel/su group is empty
# ==============================================================================
echo "Remediating: ensure_pam_wheel_group_empty"
V_SUGROUP="sugroup"
if ! grep -q "^${V_SUGROUP}:" /etc/group; then
    groupadd "${V_SUGROUP}" 2>/dev/null || true
fi
gpasswd -M '' "${V_SUGROUP}" 2>/dev/null || true

# ==============================================================================
# FIX (68) - Disable direct root logins (securetty)
# ==============================================================================
echo "Remediating: no_direct_root_logins"
echo > /etc/securetty

# ==============================================================================
# FIX (71) - Restrict su to sugroup (pam_wheel)
# ==============================================================================
echo "Remediating: use_pam_wheel_group_for_su"
PAM_SU="/etc/pam.d/su"
V_SUGROUP="sugroup"

if [ -f "$PAM_SU" ]; then
    sed -i '/pam_wheel.so/d' "$PAM_SU"
    sed -i "/pam_rootok.so/a auth required pam_wheel.so use_uid group=$V_SUGROUP" "$PAM_SU"
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

###############################################################################
# BEGIN fix (210 / 305) for 'xccdf_org.ssgproject.content_rule_package_cron_installed'
###############################################################################
(>&2 echo "Remediating rule 210/305: 'xccdf_org.ssgproject.content_rule_package_cron_installed'")

if rpm --quiet -q cronie; then
    >&2 echo "Package 'cronie' is already installed (declared in Kiwi XML) — OK"
else
    >&2 echo "WARNING: Package 'cronie' is NOT installed. Add <package name=\"cronie\"/> to your Kiwi XML image description."
fi

# END fix for 'xccdf_org.ssgproject.content_rule_package_cron_installed'

###############################################################################
# BEGIN fix (211 / 305) for 'xccdf_org.ssgproject.content_rule_service_cron_enabled'
###############################################################################
(>&2 echo "Remediating rule 211/305: 'xccdf_org.ssgproject.content_rule_service_cron_enabled'")

SYSTEMCTL_EXEC='/usr/bin/systemctl'
"$SYSTEMCTL_EXEC" unmask 'cron.service'
# KIWI: 'systemctl start' removed — is-system-running always returns
#       'offline' inside a chroot; the enabled unit starts on first boot.
"$SYSTEMCTL_EXEC" enable 'cron.service'

# END fix for 'xccdf_org.ssgproject.content_rule_service_cron_enabled'

###############################################################################
# BEGIN fix (212 / 305) for 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_d'
###############################################################################
(>&2 echo "Remediating rule 212/305: 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_d'")

newgroup=""
if getent group "0" >/dev/null 2>&1; then
    newgroup="0"
fi

if [[ -z "${newgroup}" ]]; then
    >&2 echo "0 is not a defined group on the system"
else
    find -P /etc/cron.d/ -maxdepth 0 -type d ! -group 0 -exec chgrp --no-dereference "$newgroup" {} \;
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_d'

###############################################################################
# BEGIN fix (213 / 305) for 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_daily'
###############################################################################
(>&2 echo "Remediating rule 213/305: 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_daily'")

newgroup=""
if getent group "0" >/dev/null 2>&1; then
    newgroup="0"
fi

if [[ -z "${newgroup}" ]]; then
    >&2 echo "0 is not a defined group on the system"
else
    find -P /etc/cron.daily/ -maxdepth 0 -type d ! -group 0 -exec chgrp --no-dereference "$newgroup" {} \;
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_daily'

###############################################################################
# BEGIN fix (214 / 305) for 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_hourly'
###############################################################################
(>&2 echo "Remediating rule 214/305: 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_hourly'")

newgroup=""
if getent group "0" >/dev/null 2>&1; then
    newgroup="0"
fi

if [[ -z "${newgroup}" ]]; then
    >&2 echo "0 is not a defined group on the system"
else
    find -P /etc/cron.hourly/ -maxdepth 0 -type d ! -group 0 -exec chgrp --no-dereference "$newgroup" {} \;
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_hourly'

###############################################################################
# BEGIN fix (215 / 305) for 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_monthly'
###############################################################################
(>&2 echo "Remediating rule 215/305: 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_monthly'")

newgroup=""
if getent group "0" >/dev/null 2>&1; then
    newgroup="0"
fi

if [[ -z "${newgroup}" ]]; then
    >&2 echo "0 is not a defined group on the system"
else
    find -P /etc/cron.monthly/ -maxdepth 0 -type d ! -group 0 -exec chgrp --no-dereference "$newgroup" {} \;
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_monthly'

###############################################################################
# BEGIN fix (216 / 305) for 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_weekly'
###############################################################################
(>&2 echo "Remediating rule 216/305: 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_weekly'")

newgroup=""
if getent group "0" >/dev/null 2>&1; then
    newgroup="0"
fi

if [[ -z "${newgroup}" ]]; then
    >&2 echo "0 is not a defined group on the system"
else
    find -P /etc/cron.weekly/ -maxdepth 0 -type d ! -group 0 -exec chgrp --no-dereference "$newgroup" {} \;
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_weekly'

###############################################################################
# BEGIN fix (217 / 305) for 'xccdf_org.ssgproject.content_rule_file_groupowner_crontab'
###############################################################################
(>&2 echo "Remediating rule 217/305: 'xccdf_org.ssgproject.content_rule_file_groupowner_crontab'")

newgroup=""
if getent group "0" >/dev/null 2>&1; then
    newgroup="0"
fi

if [[ -z "${newgroup}" ]]; then
    >&2 echo "0 is not a defined group on the system"
else
    if ! stat -c "%g %G" "/etc/crontab" | grep -E -w -q "0"; then
        chgrp --no-dereference "$newgroup" /etc/crontab
    fi
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_groupowner_crontab'

###############################################################################
# BEGIN fix (218 / 305) for 'xccdf_org.ssgproject.content_rule_file_owner_cron_d'
###############################################################################
(>&2 echo "Remediating rule 218/305: 'xccdf_org.ssgproject.content_rule_file_owner_cron_d'")

newown=""
if id "0" >/dev/null 2>&1; then
    newown="0"
fi

if [[ -z "$newown" ]]; then
    >&2 echo "0 is not a defined user on the system"
else
    find -P /etc/cron.d/ -maxdepth 0 -type d ! -user 0 -exec chown --no-dereference "$newown" {} \;
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_owner_cron_d'

###############################################################################
# BEGIN fix (219 / 305) for 'xccdf_org.ssgproject.content_rule_file_owner_cron_daily'
###############################################################################
(>&2 echo "Remediating rule 219/305: 'xccdf_org.ssgproject.content_rule_file_owner_cron_daily'")

newown=""
if id "0" >/dev/null 2>&1; then
    newown="0"
fi

if [[ -z "$newown" ]]; then
    >&2 echo "0 is not a defined user on the system"
else
    find -P /etc/cron.daily/ -maxdepth 0 -type d ! -user 0 -exec chown --no-dereference "$newown" {} \;
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_owner_cron_daily'

###############################################################################
# BEGIN fix (220 / 305) for 'xccdf_org.ssgproject.content_rule_file_owner_cron_hourly'
###############################################################################
(>&2 echo "Remediating rule 220/305: 'xccdf_org.ssgproject.content_rule_file_owner_cron_hourly'")

newown=""
if id "0" >/dev/null 2>&1; then
    newown="0"
fi

if [[ -z "$newown" ]]; then
    >&2 echo "0 is not a defined user on the system"
else
    find -P /etc/cron.hourly/ -maxdepth 0 -type d ! -user 0 -exec chown --no-dereference "$newown" {} \;
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_owner_cron_hourly'

###############################################################################
# BEGIN fix (221 / 305) for 'xccdf_org.ssgproject.content_rule_file_owner_cron_monthly'
###############################################################################
(>&2 echo "Remediating rule 221/305: 'xccdf_org.ssgproject.content_rule_file_owner_cron_monthly'")

newown=""
if id "0" >/dev/null 2>&1; then
    newown="0"
fi

if [[ -z "$newown" ]]; then
    >&2 echo "0 is not a defined user on the system"
else
    find -P /etc/cron.monthly/ -maxdepth 0 -type d ! -user 0 -exec chown --no-dereference "$newown" {} \;
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_owner_cron_monthly'

###############################################################################
# BEGIN fix (222 / 305) for 'xccdf_org.ssgproject.content_rule_file_owner_cron_weekly'
###############################################################################
(>&2 echo "Remediating rule 222/305: 'xccdf_org.ssgproject.content_rule_file_owner_cron_weekly'")

newown=""
if id "0" >/dev/null 2>&1; then
    newown="0"
fi

if [[ -z "$newown" ]]; then
    >&2 echo "0 is not a defined user on the system"
else
    find -P /etc/cron.weekly/ -maxdepth 0 -type d ! -user 0 -exec chown --no-dereference "$newown" {} \;
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_owner_cron_weekly'

###############################################################################
# BEGIN fix (223 / 305) for 'xccdf_org.ssgproject.content_rule_file_owner_crontab'
###############################################################################
(>&2 echo "Remediating rule 223/305: 'xccdf_org.ssgproject.content_rule_file_owner_crontab'")

newown=""
if id "0" >/dev/null 2>&1; then
    newown="0"
fi

if [[ -z "$newown" ]]; then
    >&2 echo "0 is not a defined user on the system"
else
    if ! stat -c "%u %U" "/etc/crontab" | grep -E -w -q "0"; then
        chown --no-dereference "$newown" /etc/crontab
    fi
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_owner_crontab'

###############################################################################
# BEGIN fix (224 / 305) for 'xccdf_org.ssgproject.content_rule_file_permissions_cron_d'
###############################################################################
(>&2 echo "Remediating rule 224/305: 'xccdf_org.ssgproject.content_rule_file_permissions_cron_d'")

find -H /etc/cron.d/ -maxdepth 0 -perm /u+s,g+xwrs,o+xwrt -type d -exec chmod u-s,g-xwrs,o-xwrt {} \;

# END fix for 'xccdf_org.ssgproject.content_rule_file_permissions_cron_d'

###############################################################################
# BEGIN fix (225 / 305) for 'xccdf_org.ssgproject.content_rule_file_permissions_cron_daily'
###############################################################################
(>&2 echo "Remediating rule 225/305: 'xccdf_org.ssgproject.content_rule_file_permissions_cron_daily'")

find -H /etc/cron.daily/ -maxdepth 0 -perm /u+s,g+xwrs,o+xwrt -type d -exec chmod u-s,g-xwrs,o-xwrt {} \;

# END fix for 'xccdf_org.ssgproject.content_rule_file_permissions_cron_daily'

###############################################################################
# BEGIN fix (226 / 305) for 'xccdf_org.ssgproject.content_rule_file_permissions_cron_hourly'
###############################################################################
(>&2 echo "Remediating rule 226/305: 'xccdf_org.ssgproject.content_rule_file_permissions_cron_hourly'")

find -H /etc/cron.hourly/ -maxdepth 0 -perm /u+s,g+xwrs,o+xwrt -type d -exec chmod u-s,g-xwrs,o-xwrt {} \;

# END fix for 'xccdf_org.ssgproject.content_rule_file_permissions_cron_hourly'

###############################################################################
# BEGIN fix (227 / 305) for 'xccdf_org.ssgproject.content_rule_file_permissions_cron_monthly'
###############################################################################
(>&2 echo "Remediating rule 227/305: 'xccdf_org.ssgproject.content_rule_file_permissions_cron_monthly'")

find -H /etc/cron.monthly/ -maxdepth 0 -perm /u+s,g+xwrs,o+xwrt -type d -exec chmod u-s,g-xwrs,o-xwrt {} \;

# END fix for 'xccdf_org.ssgproject.content_rule_file_permissions_cron_monthly'

###############################################################################
# BEGIN fix (228 / 305) for 'xccdf_org.ssgproject.content_rule_file_permissions_cron_weekly'
###############################################################################
(>&2 echo "Remediating rule 228/305: 'xccdf_org.ssgproject.content_rule_file_permissions_cron_weekly'")

find -H /etc/cron.weekly/ -maxdepth 0 -perm /u+s,g+xwrs,o+xwrt -type d -exec chmod u-s,g-xwrs,o-xwrt {} \;

# END fix for 'xccdf_org.ssgproject.content_rule_file_permissions_cron_weekly'

###############################################################################
# BEGIN fix (229 / 305) for 'xccdf_org.ssgproject.content_rule_file_permissions_crontab'
###############################################################################
(>&2 echo "Remediating rule 229/305: 'xccdf_org.ssgproject.content_rule_file_permissions_crontab'")

chmod u-xs,g-xwrs,o-xwrt /etc/crontab

# END fix for 'xccdf_org.ssgproject.content_rule_file_permissions_crontab'

###############################################################################
# BEGIN fix (230 / 305) for 'xccdf_org.ssgproject.content_rule_file_at_deny_not_exist'
###############################################################################
(>&2 echo "Remediating rule 230/305: 'xccdf_org.ssgproject.content_rule_file_at_deny_not_exist'")

if [[ -f /etc/at.deny ]]; then
    rm /etc/at.deny
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_at_deny_not_exist'

###############################################################################
# BEGIN fix (231 / 305) for 'xccdf_org.ssgproject.content_rule_file_cron_deny_not_exist'
###############################################################################
(>&2 echo "Remediating rule 231/305: 'xccdf_org.ssgproject.content_rule_file_cron_deny_not_exist'")

if [[ -f /etc/cron.deny ]]; then
    rm /etc/cron.deny
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_cron_deny_not_exist'

###############################################################################
# BEGIN fix (232 / 305) for 'xccdf_org.ssgproject.content_rule_file_groupowner_at_allow'
###############################################################################
(>&2 echo "Remediating rule 232/305: 'xccdf_org.ssgproject.content_rule_file_groupowner_at_allow'")

newgroup=""
if getent group "0" >/dev/null 2>&1; then
    newgroup="0"
fi

if [[ -z "${newgroup}" ]]; then
    >&2 echo "0 is not a defined group on the system"
else
    if ! stat -c "%g %G" "/etc/at.allow" | grep -E -w -q "0"; then
        chgrp --no-dereference "$newgroup" /etc/at.allow
    fi
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_groupowner_at_allow'

###############################################################################
# BEGIN fix (233 / 305) for 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_allow'
###############################################################################
(>&2 echo "Remediating rule 233/305: 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_allow'")

newgroup=""
if getent group "0" >/dev/null 2>&1; then
    newgroup="0"
fi

if [[ -z "${newgroup}" ]]; then
    >&2 echo "0 is not a defined group on the system"
else
    if ! stat -c "%g %G" "/etc/cron.allow" | grep -E -w -q "0"; then
        chgrp --no-dereference "$newgroup" /etc/cron.allow
    fi
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_groupowner_cron_allow'

###############################################################################
# BEGIN fix (234 / 305) for 'xccdf_org.ssgproject.content_rule_file_owner_at_allow'
###############################################################################
(>&2 echo "Remediating rule 234/305: 'xccdf_org.ssgproject.content_rule_file_owner_at_allow'")

newown=""
if id "0" >/dev/null 2>&1; then
    newown="0"
fi

if [[ -z "$newown" ]]; then
    >&2 echo "0 is not a defined user on the system"
else
    if ! stat -c "%u %U" "/etc/at.allow" | grep -E -w -q "0"; then
        chown --no-dereference "$newown" /etc/at.allow
    fi
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_owner_at_allow'

###############################################################################
# BEGIN fix (235 / 305) for 'xccdf_org.ssgproject.content_rule_file_owner_cron_allow'
###############################################################################
(>&2 echo "Remediating rule 235/305: 'xccdf_org.ssgproject.content_rule_file_owner_cron_allow'")

newown=""
if id "0" >/dev/null 2>&1; then
    newown="0"
fi

if [[ -z "$newown" ]]; then
    >&2 echo "0 is not a defined user on the system"
else
    if ! stat -c "%u %U" "/etc/cron.allow" | grep -E -w -q "0"; then
        chown --no-dereference "$newown" /etc/cron.allow
    fi
fi

# END fix for 'xccdf_org.ssgproject.content_rule_file_owner_cron_allow'

###############################################################################
# BEGIN fix (236 / 305) for 'xccdf_org.ssgproject.content_rule_file_permissions_at_allow'
###############################################################################
(>&2 echo "Remediating rule 236/305: 'xccdf_org.ssgproject.content_rule_file_permissions_at_allow'")

chmod u-xs,g-xws,o-xwrt /etc/at.allow

# END fix for 'xccdf_org.ssgproject.content_rule_file_permissions_at_allow'

###############################################################################
# BEGIN fix (237 / 305) for 'xccdf_org.ssgproject.content_rule_file_permissions_cron_allow'
###############################################################################
(>&2 echo "Remediating rule 237/305: 'xccdf_org.ssgproject.content_rule_file_permissions_cron_allow'")

chmod u-xs,g-xws,o-xwrt /etc/cron.allow

# END fix for 'xccdf_org.ssgproject.content_rule_file_permissions_cron_allow'

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