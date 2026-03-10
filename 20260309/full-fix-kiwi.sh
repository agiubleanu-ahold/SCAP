# ==============================================================================
# FIX (1) - Disable Prelink
# ==============================================================================
echo "Remediating: content_rule_disable_prelink"
if [ -e /etc/sysconfig/prelink ]; then
    sed -i 's/^PRELINKING.*/PRELINKING=no/' /etc/sysconfig/prelink 2>/dev/null || true
fi


# ==============================================================================
# FIX (2, 3) - AIDE Installation & Database
# ==============================================================================
echo "Remediating: aide_build_database"
if [ -x /usr/bin/aide ]; then
    /usr/bin/aide --init
    cp -p /var/lib/aide/aide.db.new /var/lib/aide/aide.db
fi

# ==============================================================================
# FIX (4) - AIDE Systemd Timer
# ==============================================================================
echo "Remediating: aide_periodic_checking_systemd_timer"
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

mkdir -p /etc/systemd/system/multi-user.target.wants
ln -sf /etc/systemd/system/aidecheck.timer /etc/systemd/system/multi-user.target.wants/aidecheck.timer

# ==============================================================================
# FIX (8, 9) - DCONF Settings
# ==============================================================================
echo "Remediating: dconf settings"
if [ -d /etc/dconf/profile ]; then
    echo -e 'user-db:user\nsystem-db:gdm' > /etc/dconf/profile/gdm
    dconf update || true
fi

# ==============================================================================
# FIX (11 & 12) - Sudo Configuration (use_pty & logfile)
# ==============================================================================
echo "Remediating: sudo_add_use_pty and sudo_custom_logfile"
if [ -f /etc/sudoers ]; then
    cp /etc/sudoers /etc/sudoers.bak

    if ! grep -q "Defaults.*use_pty" /etc/sudoers; then
        echo "Defaults use_pty" >> /etc/sudoers
    fi
    
    var_sudo_logfile='/var/log/sudo.log'
    if ! grep -q "Defaults.*logfile=" /etc/sudoers; then
        echo "Defaults logfile=${var_sudo_logfile}" >> /etc/sudoers
    else
        sed -i "s|Defaults.*logfile=.*|Defaults logfile=${var_sudo_logfile}|" /etc/sudoers
    fi
    
    if /usr/sbin/visudo -qcf /etc/sudoers; then
        rm -f /etc/sudoers.bak
    else
        echo "Sudoers validation failed, reverting."
        mv /etc/sudoers.bak /etc/sudoers
    fi
fi

# ==============================================================================
# FIX (14 & 15) - Zypper GPG Check
# ==============================================================================
echo "Remediating: zypper_gpgcheck_globally_activated"
if [ -f /etc/zypp/zypp.conf ]; then
    if grep -q "^#\?[\s]*gpgcheck" /etc/zypp/zypp.conf; then
        sed -i "s/^#\?[\s]*gpgcheck.*/gpgcheck = 1/" /etc/zypp/zypp.conf
    else
        echo "gpgcheck = 1" >> /etc/zypp/zypp.conf
    fi
fi

if [ -d /etc/zypp/repos.d ]; then
    sed -i 's/gpgcheck\s*=.*/gpgcheck=1/g' /etc/zypp/repos.d/*.repo 2>/dev/null || true
fi

# ==============================================================================
# FIX (17) - Banner /etc/issue
# ==============================================================================
echo "Remediating: banner_etc_issue"
BANNER_TEXT="Authorized users only. All activity may be monitored and reported."

mkdir -p /etc/issue.d
cat <<EOF >/etc/issue.d/99-oscap-setting
$BANNER_TEXT
EOF

if [ -d /etc/systemd/system ]; then
    mkdir -p /etc/systemd/system/multi-user.target.wants
    ln -sf /usr/lib/systemd/system/issue-generator.service /etc/systemd/system/multi-user.target.wants/issue-generator.service
fi

# ==============================================================================
# FIX (19) - MOTD Banner
# ==============================================================================
echo "Remediating: banner_etc_motd"
BANNER_TEXT="Authorized users only. All activity may be monitored and reported."
echo "$BANNER_TEXT" > /etc/motd

# ==============================================================================
# FIX (20-25) - Ownership for Banners (issue, issue.net, motd)
# ==============================================================================
echo "Remediating: Ownership for issue and motd files"

if [ -d /etc/issue.d ]; then
    find /etc/issue.d/ -type f -exec chown root:root {} +
    find /etc/issue.d/ -type f -exec chmod 0644 {} +
fi

# /etc/issue.net
if [ -f /etc/issue.net ]; then
    chown root:root /etc/issue.net
    chmod 0644 /etc/issue.net
fi

# /etc/issue
if [ -f /etc/issue ]; then
    chown root:root /etc/issue.net
    chmod 0644 /etc/issue.net
fi

# /etc/motd
if [ -f /etc/motd ]; then
    chown root:root /etc/motd
    chmod 0644 /etc/motd
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

# ==============================================================================
# FIX (72) - Session Timeout (TMOUT=900)
# ==============================================================================
echo "Remediating: accounts_tmout"
TMOUT_FILE="/etc/profile.d/autologout.sh"
cat <<EOF > "$TMOUT_FILE"
# Set TMOUT per security requirements
TMOUT=900
readonly TMOUT
export TMOUT
EOF
chmod 0644 "$TMOUT_FILE"

# ==============================================================================
# FIX (73, 74, 75, 76) - Home Directories Management
# ==============================================================================
echo "Remediating: Home directories permissions and existence"
USERS_DATA=$(awk -F':' '{ if ($3 >= 1000 && $3 != 65534 && $6 != "/") print $1":"$6 }' /etc/passwd)

for entry in $USERS_DATA; do
    user=$(echo $entry | cut -d: -f1)
    home=$(echo $entry | cut -d: -f2)

    if [ ! -d "$home" ]; then
        mkhomedir_helper "$user" 0077 2>/dev/null || mkdir -p "$home"
    fi

    chmod 0700 "$home" 2>/dev/null
    chown "$user" "$home" 2>/dev/null

    if [ -f "$home/.netrc" ]; then
        chmod 0600 "$home/.netrc"
    fi
done

# ==============================================================================
# FIX (79) - Global UMASK in bashrc
# ==============================================================================
echo "Remediating: accounts_umask_etc_bashrc"
BASHRC="/etc/bash.bashrc"
if [ -f "$BASHRC" ]; then
    sed -i '/^umask/d' "$BASHRC"
    echo "umask 027" >> "$BASHRC"
fi

# ==============================================================================
# FIX (81) - Global UMASK in /etc/profile
# ==============================================================================
echo "Remediating: accounts_umask_etc_profile"
V_UMASK="027"
PROFILE_FILES=$(find /etc/profile.d/ -type f \( -name "*.sh" -o -name "sh.local" \) 2>/dev/null)

for file in $PROFILE_FILES /etc/profile; do
    if [ -f "$file" ]; then
        sed -i -E "s/^\s*umask\s+[0-7]+/umask $V_UMASK/g" "$file"
    fi
done

if ! grep -qE '^[^#]*umask' /etc/profile; then
    echo "umask $V_UMASK" >> /etc/profile
fi

# ==============================================================================
# FIX (82, 83, 84) - AppArmor Installation and Configuration
# ==============================================================================
echo "Remediating: apparmor_configured"

if [ -d /etc/systemd/system ]; then
    mkdir -p /etc/systemd/system/multi-user.target.wants
    ln -sf /usr/lib/systemd/system/apparmor.service /etc/systemd/system/multi-user.target.wants/apparmor.service
fi

# ==============================================================================
# FIX (85, 86) - GRUB2 Configuration Ownership (root:root)
# ==============================================================================
echo "Remediating: file_owner_grub2_cfg"
GRUB_CFG=""
[ -f /boot/grub2/grub.cfg ] && GRUB_CFG="/boot/grub2/grub.cfg"
[ -f /boot/efi/EFI/sles/grub.cfg ] && GRUB_CFG="/boot/efi/EFI/sles/grub.cfg"

if [ -n "$GRUB_CFG" ]; then
    chown root:root "$GRUB_CFG"
    chmod 0600 "$GRUB_CFG"
fi

# ==============================================================================
# FIX (87) - GRUB2 Config Permissions
# ==============================================================================
echo "Remediating: file_permissions_grub2_cfg"
GRUB_PATHS=("/boot/grub2/grub.cfg" "/boot/efi/EFI/sles/grub.cfg" "/boot/efi/EFI/opensuse/grub.cfg")

for cfg_path in "${GRUB_PATHS[@]}"; do
    if [ -f "$cfg_path" ]; then
        chmod 0600 "$cfg_path"
        chown root:root "$cfg_path"
    fi
done

# ==============================================================================
# FIX (90, 91) - RSYSLOG Installation and Activation
# ==============================================================================
echo "Remediating: service_rsyslog_enabled"

if [ -x /usr/sbin/rsyslogd ]; then
    rm -f /etc/systemd/system/rsyslog.service
    mkdir -p /etc/systemd/system/multi-user.target.wants
    ln -sf /usr/lib/systemd/system/rsyslog.service /etc/systemd/system/multi-user.target.wants/rsyslog.service
fi

# ==============================================================================
# FIX (92) - RSYSLOG Log Files Group Ownership
# ==============================================================================
echo "Remediating: rsyslog_files_groupownership"

if [ -f /etc/rsyslog.conf ]; then
    LOG_FILES=$(grep -E "^[a-z.*]+\s+/?var/log/" /etc/rsyslog.conf | awk '{print $NF}' | sed 's/^-//')
    
    LOG_FILES="$LOG_FILES /var/log/messages /var/log/mail /var/log/warn /var/log/syslog"

    for log_f in $LOG_FILES; do
        if [ -f "$log_f" ]; then
            chgrp root "$log_f"
            chmod 0640 "$log_f"
        fi
    done
fi

# ==============================================================================
# FIX (92, 93, 94) - RSYSLOG Log Files Security (Owner, Group, Permissions)
# ==============================================================================
echo "Remediating: rsyslog_files_security (consolidated)"

if [ -f /etc/rsyslog.conf ]; then

    LOG_FILES_FROM_CONF=$(grep -E "^[a-z.*]+\s+/?var/log/" /etc/rsyslog.conf | awk '{print $NF}' | sed 's/^-//')
    
    ALL_LOG_FILES="$LOG_FILES_FROM_CONF /var/log/messages /var/log/mail /var/log/warn /var/log/syslog /var/log/secure"

    for log_f in $ALL_LOG_FILES; do
        if [ -f "$log_f" ]; then
            chown root:root "$log_f"
            chmod 0640 "$log_f"
        fi
    done

    if grep -q "^\$FileCreateMode" /etc/rsyslog.conf; then
        sed -i 's/^\$FileCreateMode.*/$FileCreateMode 0640/' /etc/rsyslog.conf
    else
        echo '$FileCreateMode 0640' >> /etc/rsyslog.conf
    fi
fi

# ==============================================================================
# FIX (96, 97, 98) - Journald Security Configuration (Consolidated)
# ==============================================================================
echo "Remediating: journald_compress, forward_to_syslog and storage"

JOURNAL_HARDENING="/etc/systemd/journald.conf.d/complianceascode_hardening.conf"

mkdir -p /etc/systemd/journald.conf.d/

cat <<EOF > "$JOURNAL_HARDENING"
[Journal]
Compress=yes
ForwardToSyslog=yes
Storage=persistent
EOF

if [ -f /etc/systemd/journald.conf ]; then
    sed -i -E 's/^\s*#?\s*(Compress|ForwardToSyslog|Storage)=.*/# \1 set in drop-in/' /etc/systemd/journald.conf
fi

# ==============================================================================
# FIX (99, 100, 101) - Logrotate Installation and Activation
# ==============================================================================
echo "Remediating: logrotate_activated"

if [ -f /etc/logrotate.conf ]; then
    sed -i '/^\s*\(weekly\|monthly\|yearly\)/d' /etc/logrotate.conf
    if ! grep -q "^daily" /etc/logrotate.conf; then
        sed -i '1i daily' /etc/logrotate.conf
    fi
fi

if [ -d /etc/systemd/system ]; then
    mkdir -p /etc/systemd/system/timers.target.wants
    ln -sf /usr/lib/systemd/system/logrotate.timer /etc/systemd/system/timers.target.wants/logrotate.timer
fi

# ==============================================================================
# FIX (103) - Firewalld Backend (nftables)
# ==============================================================================
echo "Remediating: firewalld_backend"
FW_CONF="/etc/firewalld/firewalld.conf"

if [ -f "$FW_CONF" ]; then
    sed -i '/^FirewallBackend=/d' "$FW_CONF"
    echo "FirewallBackend=nftables" >> "$FW_CONF"
else
    mkdir -p /etc/firewalld
    echo "FirewallBackend=nftables" > "$FW_CONF"
fi

# ==============================================================================
# CONFIG FIREWALL FIX (107, 110, 111, 112)
# ==============================================================================
V_NETWORK_SERVICE='firewalld'

echo "Remediating: Firewall service configuration (Target: $V_NETWORK_SERVICE)"

if [ "$V_NETWORK_SERVICE" == "firewalld" ]; then

    if [ -f /usr/lib/systemd/system/firewalld.service ]; then
        rm -f /etc/systemd/system/firewalld.service
        
        mkdir -p /etc/systemd/system/multi-user.target.wants
        ln -sf /usr/lib/systemd/system/firewalld.service /etc/systemd/system/multi-user.target.wants/firewalld.service
        echo "Firewalld enabled."
    fi


# ==============================================================================
# FIX (121-144) sysctl tunables
# ==============================================================================
echo "Remediating: sysctl tunables"
SYS_FILE="/etc/sysctl.d/net_ipv6_conf_all_accept_ra.conf"
mkdir -p /etc/sysctl.d

sed -i '/net.ipv6.conf.all.accept_ra/d' /etc/sysctl.conf
echo "net.ipv6.conf.all.accept_ra = 0" > "$SYS_FILE"

IPv6_SYSCTL="/etc/sysctl.d/60-ipv6-hardening.conf"

sed -i -E '/net\.ipv6\.conf\.all\.(accept_redirects|accept_source_route|forwarding)/d' /etc/sysctl.conf
sed -i -E '/net\.ipv6\.conf\.default\.(accept_ra|accept_redirects|accept_source_route)/d' /etc/sysctl.conf

cat <<EOF > "$IPv6_SYSCTL"
# Per security requirements (CCE-85708-6, CCE-85649-2)
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.all.forwarding = 0
# Per security requirements (CCE-92474-6, CCE-85722-7, CCE-85723-5)
net.ipv6.conf.default.accept_ra = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.default.accept_source_route = 0
EOF

IPv4_SYSCTL="/etc/sysctl.d/60-ipv4-hardening.conf"

sed -i -E '/net\.ipv4\.conf\.all\.(accept_redirects|accept_source_route)/d' /etc/sysctl.conf
sed -i -E '/net\.ipv4\.conf\.all\.(log_martians|rp_filter|secure_redirects)/d' /etc/sysctl.conf
sed -i -E '/net\.ipv4\.conf\.default\.(accept_redirects|accept_source_route|log_martians)/d' /etc/sysctl.conf
sed -i -E '/net\.ipv4\.conf\.default\.(rp_filter|secure_redirects)/d' /etc/sysctl.conf
sed -i -E '/net\.ipv4\.(icmp_echo_ignore_broadcasts|icmp_ignore_bogus_error_responses|tcp_syncookies)/d' /etc/sysctl.conf
sed -i -E '/net\.ipv4\.(conf\.all\.send_redirects|conf\.default\.send_redirects|ip_forward)/d' /etc/sysctl.conf


cat <<EOF >> "$IPv4_SYSCTL"
# Per security requirements (CCE-85651-8, CCE-85648-4)
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
# Per security requirements (CCE-91222-0, CCE-91218-8, CCE-85652-6)
net.ipv4.conf.all.log_martians = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.all.secure_redirects = 0
# Per security requirements (CCE-85652-6, CCE-85650-0, CCE-91221-2)
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.default.log_martians = 1
# Per security requirements (CCE-91219-6, CCE-91221-2)
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.default.secure_redirects = 0
# Per security requirements (CCE-91243-6, CCE-91224-6, CCE-91225-3)
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1
net.ipv4.tcp_syncookies = 1
# Per security requirements (CCE-85655-9, CCE-85654-2, CCE-85709-4)
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.ip_forward = 0
EOF

# ==============================================================================
# FIX (154) - Sticky Bits on World-Writable Directories
# ==============================================================================
echo "Remediating: world_writable_sticky_bits"
find / -xdev -type d \( -perm -0002 -a ! -perm -1000 \) 2>/dev/null \
    -not -path "/proc/*" -not -path "/sys/*" -not -path "/dev/*" \
    -exec chmod a+t {} +

# ==============================================================================
# FIX (155) - Remove World-Writable Permissions from Files
# ==============================================================================
echo "Remediating: unauthorized_world_writable files"
find / -xdev -type f -perm -002 \
    -not -path "/proc/*" -not -path "/sys/*" -not -path "/dev/*" \
    -exec chmod o-w {} \; 2>/dev/null

# ==============================================================================
# FIX (158, 159) - Log Permissions & Backup File Ownership
# ==============================================================================
echo "Remediating: log permissions and etc backup ownership"

if [ -d /var/log ]; then
    find -P /var/log/ -xdev -type f \
        ! -name '*[bw]tmp' ! -name '*lastlog' \
        -exec chmod u-xs,g-xws,o-xwrt {} \; 2>/dev/null
fi

if [ -f /etc/group- ]; then
    chown root:root /etc/group-
    chmod 0600 /etc/group-
fi

# ==============================================================================
# FIX (160 - 168) - Ownership of Identity Files and Backups
# ==============================================================================
echo "Remediating: Ownership of identity files and their backups"


for f in /etc/group /etc/group- /etc/gshadow /etc/gshadow- /etc/passwd /etc/passwd-; do
    if [ -f "$f" ]; then
        chown root:root "$f"
    fi
done


for f in /etc/shadow /etc/shadow-; do
    if [ -f "$f" ]; then
        if getent group shadow >/dev/null; then
            chgrp shadow "$f"
        else
            chgrp 15 "$f" 2>/dev/null || chgrp 0 "$f"
        fi
        chown root "$f"
    fi
done

# ==============================================================================
# FIX (169 - 182) - Ownership and Permissions of Identity Files & Backups
# ==============================================================================
echo "Remediating: Final ownership and permissions for identity files"


for f in /etc/passwd /etc/passwd- /etc/group /etc/group- /etc/shadow /etc/shadow- /etc/gshadow /etc/gshadow-; do
    if [ -f "$f" ]; then
        chown root "$f"
    fi
done

for f in /etc/passwd /etc/passwd- /etc/group /etc/group-; do
    [ -f "$f" ] && chmod 0644 "$f"
done

for f in /etc/shadow /etc/shadow- /etc/gshadow /etc/gshadow-; do
    [ -f "$f" ] && chmod 0000 "$f"
done

chgrp shadow /etc/shadow /etc/shadow- 2>/dev/null || chgrp 15 /etc/shadow /etc/shadow- 2>/dev/null || true

# ==============================================================================
# FIX (183) - Disable UDF Kernel Module
# ==============================================================================
echo "Remediating: kernel_module_udf_disabled"
UDF_CONF="/etc/modprobe.d/udf.conf"

if [ -f "$UDF_CONF" ]; then
    sed -i 's/^install udf.*/install udf /bin/false/g' "$UDF_CONF"
else
    mkdir -p /etc/modprobe.d
    echo -e "install udf /bin/false\nblacklist udf" > "$UDF_CONF"
fi

# ==============================================================================
# FIX (184, 185, 186) - Secure /dev/shm Mount Options (nodev, noexec, nosuid)
# ==============================================================================
echo "Remediating: /dev/shm mount options"
FSTAB="/etc/etc/fstab"


V_OPTS="nodev,noexec,nosuid"

if [ -f /etc/fstab ]; then
    if grep -q "[[:space:]]/dev/shm[[:space:]]" /etc/fstab; then
        for opt in nodev noexec nosuid; do
            if ! grep "[[:space:]]/dev/shm[[:space:]]" /etc/fstab | grep -q "$opt"; then
                sed -i "s|\([[:space:]]/dev/shm[[:space:]][^[:space:]]*[[:space:]][^[:space:]]*\s*\)|\1,$opt|" /etc/fstab
            fi
        done
        sed -i 's/defaults,,/defaults,/g; s/,,/,/g' /etc/fstab
    else
        echo "tmpfs /dev/shm tmpfs defaults,${V_OPTS} 0 0" >> /etc/fstab
    fi
fi


# ==============================================================================
# SECURING MOUNT POINTS (187 - 191)
# ==============================================================================
echo "Remediating: Mount options for /home, /tmp and removable media"
FSTAB="/etc/fstab"

update_fstab_option() {
    local mount_point=$1
    local option=$2
    if grep -q "[[:space:]]${mount_point}[[:space:]]" "$FSTAB"; then
        if ! grep "[[:space:]]${mount_point}[[:space:]]" "$FSTAB" | awk '{print $4}' | grep -q "$option"; then
            sed -i "s|\([[:space:]]${mount_point}[[:space:]][^[:space:]]*[[:space:]]\)\([^[:space:]]*\)|\1\2,${option}|" "$FSTAB"
            sed -i 's/defaults,,/defaults,/g; s/,,/,/g' "$FSTAB"
        fi
    fi
}

if [ -f "$FSTAB" ]; then
    update_fstab_option "/home" "nodev"

    for opt in nodev noexec nosuid; do
        update_fstab_option "/dev/cdrom" "$opt"
    done

    update_fstab_option "/tmp" "nodev"
fi

# ==============================================================================
# SECURING MOUNT POINTS (192 - 194)
# ==============================================================================
echo "Remediating: Mount options for /tmp and /var/tmp"
FSTAB="/etc/fstab"

update_fstab_option() {
    local mount_point=$1
    local option=$2
    if grep -q "[[:space:]]${mount_point}[[:space:]]" "$FSTAB"; then
        if ! grep "[[:space:]]${mount_point}[[:space:]]" "$FSTAB" | awk '{print $4}' | grep -q "$option"; then
            sed -i "s|\([[:space:]]${mount_point}[[:space:]][^[:space:]]*[[:space:]]\)\([^[:space:]]*\)|\1\2,${option}|" "$FSTAB"
            sed -i 's/defaults,,/defaults,/g; s/,,/,/g' "$FSTAB"
        fi
    fi
}

if [ -f "$FSTAB" ]; then
    update_fstab_option "/tmp" "noexec"

    update_fstab_option "/tmp" "nosuid"

    update_fstab_option "/var/tmp" "nodev"
fi


# ==============================================================================
# FIX (196) - Secure /var/tmp Mount Options (nosuid)
# ==============================================================================
echo "Remediating: /var/tmp mount options (nosuid)"
FSTAB="/etc/fstab"

if [ -f "$FSTAB" ] && grep -q "[[:space:]]/var/tmp[[:space:]]" "$FSTAB"; then
    if ! grep "[[:space:]]/var/tmp[[:space:]]" "$FSTAB" | awk '{print $4}' | grep -q "nosuid"; then
        sed -i "s|\([[:space:]]/var/tmp[[:space:]][^[:space:]]*[[:space:]]\)\([^[:space:]]*\)|\1\2,nosuid|" "$FSTAB"
        sed -i 's/defaults,,/defaults,/g; s/,,/,/g' "$FSTAB"
    fi
fi

# ==============================================================================
# FIX (197, 198) - Disable Systemd Coredumps (Consolidated)
# ==============================================================================
echo "Remediating: systemd coredump disable (197, 198)"
COREDUMP_DROPIN="/etc/systemd/coredump.conf.d/complianceascode_hardening.conf"
mkdir -p /etc/systemd/coredump.conf.d/

cat <<EOF > "$COREDUMP_DROPIN"
[Coredump]
ProcessSizeMax=0
Storage=none
EOF

# ==============================================================================
# FIX (199) - Disable User Coredumps (limits.conf)
# ==============================================================================
echo "Remediating: disable_users_coredumps"
LIMITS_DROPIN="/etc/security/limits.d/10-ssg-hardening.conf"
mkdir -p /etc/security/limits.d/

echo "*     hard   core    0" > "$LIMITS_DROPIN"

if [ -f /etc/security/limits.conf ]; then
    sed -i '/^[[:space:]]*\*[[:space:]]\+hard[[:space:]]\+core/ s/^/#/' /etc/security/limits.conf
fi

# ==============================================================================
# FIX (200) for 'xccdf_org.ssgproject.content_rule_sysctl_fs_suid_dumpable'
# ==============================================================================

echo "Remediating rule 200/296: fs.suid_dumpable"

    for f in /etc/sysctl.d/*.conf /usr/local/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf; do
        [ -e "$f" ] || continue
        if [[ "$(readlink -f "$f")" == "/etc/sysctl.conf" ]]; then continue; fi
        
        matching_list=$(grep -P '^(?!#).*[\s]*fs.suid_dumpable.*$' $f | uniq || true)
        if [ -n "$matching_list" ]; then
            while IFS= read -r entry; do
                escaped_entry=$(sed -e 's|/|\\/|g' <<< "$entry")
                sed -i --follow-symlinks "s/^${escaped_entry}$/# &/g" $f
            done <<< "$matching_list"
        fi
    done

    SYSCONFIG_FILE='/etc/sysctl.d/fs_suid_dumpable.conf'
    mkdir -p /etc/sysctl.d/
    
    sed -i "/^fs.suid_dumpable/d" /etc/sysctl.conf || true

    printf "# Rule 200/296: Set fs.suid_dumpable in %s\n" "${SYSCONFIG_FILE}" > "${SYSCONFIG_FILE}"
    printf "fs.suid_dumpable = 0\n" >> "${SYSCONFIG_FILE}"


# ==============================================================================
# FIX (201) for 'xccdf_org.ssgproject.content_rule_sysctl_kernel_randomize_va_space'
# ==============================================================================

echo "Remediating rule 201/296: kernel.randomize_va_space"

    for f in /etc/sysctl.d/*.conf /usr/local/lib/sysctl.d/*.conf /lib/sysctl.d/*.conf; do
        [ -e "$f" ] || continue
        if [[ "$(readlink -f "$f")" == "/etc/sysctl.conf" ]]; then continue; fi

        matching_list=$(grep -P '^(?!#).*[\s]*kernel.randomize_va_space.*$' $f | uniq || true)
        if [ -n "$matching_list" ]; then
            while IFS= read -r entry; do
                escaped_entry=$(sed -e 's|/|\\/|g' <<< "$entry")
                sed -i --follow-symlinks "s/^${escaped_entry}$/# &/g" $f
            done <<< "$matching_list"
        fi
    done

    SYSCONFIG_FILE='/etc/sysctl.d/kernel_randomize_va_space.conf'
    mkdir -p /etc/sysctl.d/
    
    sed -i "/^kernel.randomize_va_space/d" /etc/sysctl.conf || true

    printf "# Rule 201/296: Set kernel.randomize_va_space in %s\n" "${SYSCONFIG_FILE}" > "${SYSCONFIG_FILE}"
    printf "kernel.randomize_va_space = 2\n" >> "${SYSCONFIG_FILE}"


# ==============================================================================
# FIX CRON Permissions Remediation (Rules 206 - 212)
# ==============================================================================


    if getent group "0" >/dev/null 2>&1; then
        TARGET_GRP="0"
    else
        echo "Warning: Group GID 0 not found. Skipping group ownership fixes." >&2
        TARGET_GRP=""
    fi

    if id "0" >/dev/null 2>&1; then
        TARGET_USR="0"
    else
        echo "Warning: User UID 0 not found. Skipping owner fixes." >&2
        TARGET_USR=""
    fi

    if [ -n "$TARGET_GRP" ] && [ -d /etc/cron.d ]; then
        echo "Remediating rule 206/296: file_groupowner_cron_d"
        find -P /etc/cron.d/ -maxdepth 0 -type d ! -group 0 -exec chgrp --no-dereference "$TARGET_GRP" {} \;
    fi

    if [ -n "$TARGET_GRP" ] && [ -d /etc/cron.daily ]; then
        echo "Remediating rule 207/296: file_groupowner_cron_daily"
        find -P /etc/cron.daily/ -maxdepth 0 -type d ! -group 0 -exec chgrp --no-dereference "$TARGET_GRP" {} \;
    fi

    if [ -n "$TARGET_GRP" ] && [ -d /etc/cron.hourly ]; then
        echo "Remediating rule 208/296: file_groupowner_cron_hourly"
        find -P /etc/cron.hourly/ -maxdepth 0 -type d ! -group 0 -exec chgrp --no-dereference "$TARGET_GRP" {} \;
    fi

    if [ -n "$TARGET_GRP" ] && [ -d /etc/cron.monthly ]; then
        echo "Remediating rule 209/296: file_groupowner_cron_monthly"
        find -P /etc/cron.monthly/ -maxdepth 0 -type d ! -group 0 -exec chgrp --no-dereference "$TARGET_GRP" {} \;
    fi

    if [ -n "$TARGET_GRP" ] && [ -d /etc/cron.weekly ]; then
        echo "Remediating rule 210/296: file_groupowner_cron_weekly"
        find -P /etc/cron.weekly/ -maxdepth 0 -type d ! -group 0 -exec chgrp --no-dereference "$TARGET_GRP" {} \;
    fi

    if [ -n "$TARGET_GRP" ] && [ -f /etc/crontab ]; then
        echo "Remediating rule 211/296: file_groupowner_crontab"
        if ! stat -c "%g" "/etc/crontab" | grep -q "^0$"; then
            chgrp --no-dereference "$TARGET_GRP" /etc/crontab
        fi
    fi

    if [ -n "$TARGET_USR" ] && [ -d /etc/cron.d ]; then
        echo "Remediating rule 212/296: file_owner_cron_d"
        find -P /etc/cron.d/ -maxdepth 0 -type d ! -user 0 -exec chown --no-dereference "$TARGET_USR" {} \;
    fi


# ==============================================================================
# FIX CRON Owner and Permissions Remediation (Rules 213 - 222)
# ==============================================================================


    if id "0" >/dev/null 2>&1; then
        TARGET_USR="0"
    else
        echo "Warning: User UID 0 not found. Skipping ownership fixes." >&2
        TARGET_USR=""
    fi


    if [ -n "$TARGET_USR" ]; then
        [ -d /etc/cron.daily ] && { echo "Remediating rule 213/296"; find -P /etc/cron.daily/ -maxdepth 0 -type d ! -user 0 -exec chown --no-dereference "$TARGET_USR" {} \; ; }
        
        [ -d /etc/cron.hourly ] && { echo "Remediating rule 214/296"; find -P /etc/cron.hourly/ -maxdepth 0 -type d ! -user 0 -exec chown --no-dereference "$TARGET_USR" {} \; ; }
        
        [ -d /etc/cron.monthly ] && { echo "Remediating rule 215/296"; find -P /etc/cron.monthly/ -maxdepth 0 -type d ! -user 0 -exec chown --no-dereference "$TARGET_USR" {} \; ; }
        
        [ -d /etc/cron.weekly ] && { echo "Remediating rule 216/296"; find -P /etc/cron.weekly/ -maxdepth 0 -type d ! -user 0 -exec chown --no-dereference "$TARGET_USR" {} \; ; }
        
        if [ -f /etc/crontab ]; then
            echo "Remediating rule 217/296"
            if ! stat -c "%u" "/etc/crontab" | grep -q "^0$"; then
                chown --no-dereference "$TARGET_USR" /etc/crontab
            fi
        fi
    fi

    [ -d /etc/cron.d ] && { echo "Remediating rule 218/296"; find -H /etc/cron.d/ -maxdepth 0 -perm /u+s,g+xwrs,o+xwrt -type d -exec chmod u-s,g-xwrs,o-xwrt {} \; ; }

    [ -d /etc/cron.daily ] && { echo "Remediating rule 219/296"; find -H /etc/cron.daily/ -maxdepth 0 -perm /u+s,g+xwrs,o+xwrt -type d -exec chmod u-s,g-xwrs,o-xwrt {} \; ; }

    [ -d /etc/cron.hourly ] && { echo "Remediating rule 220/296"; find -H /etc/cron.hourly/ -maxdepth 0 -perm /u+s,g+xwrs,o+xwrt -type d -exec chmod u-s,g-xwrs,o-xwrt {} \; ; }

    [ -d /etc/cron.monthly ] && { echo "Remediating rule 221/296"; find -H /etc/cron.monthly/ -maxdepth 0 -perm /u+s,g+xwrs,o+xwrt -type d -exec chmod u-s,g-xwrs,o-xwrt {} \; ; }

    [ -d /etc/cron.weekly ] && { echo "Remediating rule 222/296"; find -H /etc/cron.weekly/ -maxdepth 0 -perm /u+s,g+xwrs,o+xwrt -type d -exec chmod u-s,g-xwrs,o-xwrt {} \; ; }


# ==============================================================================
#  FIX Cron/At Security and Package Clean-up (Rules 223 - 232)
# ==============================================================================



    TARGET_GRP="0"
    TARGET_USR="0"

    if [ -f /etc/crontab ]; then
        echo "Remediating rule 223/296: file_permissions_crontab"
        chmod u-xs,g-xwrs,o-xwrt /etc/crontab
    fi

    if [ -f /etc/at.deny ]; then
        echo "Remediating rule 224/296: file_at_deny_not_exist"
        rm -f /etc/at.deny
    fi

    if [ -f /etc/cron.deny ]; then
        echo "Remediating rule 225/296: file_cron_deny_not_exist"
        rm -f /etc/cron.deny
    fi

    if [ -f /etc/at.allow ]; then
        echo "Remediating rules 226, 228, 230: at.allow security"
        chown --no-dereference "$TARGET_USR" /etc/at.allow
        chgrp --no-dereference "$TARGET_GRP" /etc/at.allow
        chmod u-xs,g-xws,o-xwrt /etc/at.allow
    fi

    if [ -f /etc/cron.allow ]; then
        echo "Remediating rules 227, 229, 231: cron.allow security"
        chown --no-dereference "$TARGET_USR" /etc/cron.allow
        chgrp --no-dereference "$TARGET_GRP" /etc/cron.allow
        chmod u-xs,g-xws,o-xwrt /etc/cron.allow
    fi


# ==============================================================================
# FIX Time Sync and Legacy Services (Rules 250 - 257)
# ==============================================================================


        echo "Remediating rule 251/296: chronyd_configure_pool_and_server"
        CHRONY_CONF="/etc/chrony.conf"
        [ ! -f "$CHRONY_CONF" ] && touch "$CHRONY_CONF"
        
        SERVERS=("0.suse.pool.ntp.org" "1.suse.pool.ntp.org" "2.suse.pool.ntp.org" "3.suse.pool.ntp.org")
        for srv in "${SERVERS[@]}"; do
            if ! grep -q "server $srv" "$CHRONY_CONF"; then
                echo "server $srv iburst" >> "$CHRONY_CONF"
            fi
            if ! grep -q "pool $srv" "$CHRONY_CONF"; then
                echo "pool $srv iburst" >> "$CHRONY_CONF"
            fi
        done

        echo "Remediating rule 252/296: chronyd_run_as_chrony_user"
        CHRONY_SYSCONFIG="/etc/sysconfig/chronyd"
        mkdir -p /etc/sysconfig
        if [ -f "$CHRONY_SYSCONFIG" ] && grep -q 'OPTIONS=.*' "$CHRONY_SYSCONFIG"; then
            sed -i -E -e 's/\s*-u\s*\w+\s*/ /' -e 's/^([\s]*OPTIONS=["]?[^"]*)("?)/\1 -u chrony\2/' "$CHRONY_SYSCONFIG"
        else
            echo 'OPTIONS="-u chrony"' >> "$CHRONY_SYSCONFIG"
        fi


        echo "Remediating rule 253/296: service_timesyncd_root_distance_configured"
        TIMESYNC_DROPIN_DIR="/usr/lib/systemd/timesyncd.conf.d"
        mkdir -p "$TIMESYNC_DROPIN_DIR"
        
        find /etc/systemd/timesyncd.conf /usr/lib/systemd/timesyncd.conf.d/ -type f 2>/dev/null | xargs -r sed -i 's/^RootDistanceMax/#&/g'
        
        echo "[Time]" > "$TIMESYNC_DROPIN_DIR/oscap-remedy.conf"
        echo "RootDistanceMax=1" >> "$TIMESYNC_DROPIN_DIR/oscap-remedy.conf"


# ==============================================================================
# FIX SSH Server Configuration (Rules 269 - 276)
# ==============================================================================


    SSHD_CONFIG="/etc/ssh/sshd_config"
    if [ -f "$SSHD_CONFIG" ]; then
        echo "Remediating rules 271, 272, 273: sshd_config permissions"
        chown 0:0 "$SSHD_CONFIG"
        chmod u-xs,g-xwrs,o-xwrt "$SSHD_CONFIG"
    fi

    echo "Remediating rule 274/296: sshd_private_key_permissions"
    for keyfile in /etc/ssh/*_key; do
        [ -f "$keyfile" ] || continue
        if [ "$(stat -c "%U:%G" "$keyfile")" = "root:root" ]; then
            chmod u-xs,g-xws,o-xwrt "$keyfile"
        fi
    done

    echo "Remediating rule 275/296: sshd_pub_key_permissions"
    find -P /etc/ssh/ -maxdepth 1 -type f -name "*.pub" -exec chmod u-xs,g-xws,o-xwt {} \;

    if [ -f "$SSHD_CONFIG" ]; then
        echo "Remediating rule 276/296: sshd_set_keepalive"
        sed -i "/^\s*ClientAliveCountMax/Id" "$SSHD_CONFIG"
        sed -i -e '$a\' "$SSHD_CONFIG"
        echo "ClientAliveCountMax 0" >> "$SSHD_CONFIG"
    fi

# ==============================================================================
# FIX SSH Server Hardening (Rules 277 - 296)
# ==============================================================================


    SSHD_CONFIG="/etc/ssh/sshd_config"
    
    if [ ! -f "$SSHD_CONFIG" ]; then
        mkdir -p /etc/ssh
        touch "$SSHD_CONFIG"
    fi

    set_sshd_param() {
        local param=$1
        local value=$2
        sed -i "/^\s*${param}\s\+/Id" "$SSHD_CONFIG"
        echo "${param} ${value}" >> "$SSHD_CONFIG"
    }

    echo "Applying SSHD hardening rules 277-290..."

    set_sshd_param "ClientAliveInterval" "300"

    set_sshd_param "HostbasedAuthentication" "no"

    set_sshd_param "PermitEmptyPasswords" "no"

    set_sshd_param "IgnoreRhosts" "yes"

    set_sshd_param "PermitRootLogin" "no"

    set_sshd_param "X11Forwarding" "no"

    set_sshd_param "PermitUserEnvironment" "no"

    set_sshd_param "UsePAM" "yes"

    set_sshd_param "Banner" "/etc/issue"

    echo "Warning: Rule 286/296 (sshd_limit_user_access) has no defined fix. Skipping."

    set_sshd_param "LoginGraceTime" "60"

    set_sshd_param "LogLevel" "VERBOSE"

    set_sshd_param "MaxAuthTries" "4"

    set_sshd_param "MaxSessions" "10"

    echo "Applying final SSHD crypto hardening rules 291-296..."

    set_sshd_param "MaxStartups" "10:30:60"

    CIPHERS_LIST="chacha20-poly1305@openssh.com,aes256-gcm@openssh.com,aes128-gcm@openssh.com,aes256-ctr,aes192-ctr,aes128-ctr"
    set_sshd_param "Ciphers" "$CIPHERS_LIST" "CCE-91337-6: Approved Ciphers"

    MACS_LIST="hmac-sha2-512-etm@openssh.com,hmac-sha2-256-etm@openssh.com,umac-128-etm@openssh.com,hmac-sha2-512,hmac-sha2-256"
    set_sshd_param "MACs" "$MACS_LIST" "CCE-91338-4: Approved MACs"

    KEX_LIST="curve25519-sha256,curve25519-sha256@libssh.org,diffie-hellman-group14-sha256,diffie-hellman-group16-sha512,diffie-hellman-group18-sha512,ecdh-sha2-nistp521,ecdh-sha2-nistp384,ecdh-sha2-nistp256,diffie-hellman-group-exchange-sha256"
    set_sshd_param "KexAlgorithms" "$KEX_LIST" "Strong Kex Algorithms"

    sed -i -e '$a\' "$SSHD_CONFIG"


