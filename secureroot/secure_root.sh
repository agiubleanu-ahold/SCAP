#!/bin/bash
set -euo pipefail
 
# --- Color output helpers ----------------------------------------------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color
 
info()    { echo -e "${GREEN}[INFO]${NC}  $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC}  $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1"; exit 1; }
 
# --- Root check --------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
  error "This script must be run as root or via sudo."
fi
 
echo "============================================================"
echo "         Secure Root Hardening Script"
echo "============================================================"
echo ""
 
# =============================================================================
# METHOD 1: Comment out 'Defaults targetpw' in /etc/sudoers
# =============================================================================
info "Method 1: Commenting out 'Defaults targetpw' in /etc/sudoers..."
 
SUDOERS_FILE="/etc/sudoers"
SUDOERS_BACKUP="/etc/sudoers.bak.$(date +%Y%m%d%H%M%S)"
 
if grep -qE '^\s*Defaults\s+targetpw' "$SUDOERS_FILE"; then
  # Backup first
  cp "$SUDOERS_FILE" "$SUDOERS_BACKUP"
  info "Backup of sudoers created at: $SUDOERS_BACKUP"
 
  # Use a temp file + visudo -c to validate before applying
  TMPFILE=$(mktemp)
  sed -E 's/^(\s*Defaults\s+targetpw)/# \1/' "$SUDOERS_FILE" > "$TMPFILE"
 
  # Validate the modified sudoers file before applying
  if visudo -c -f "$TMPFILE" &>/dev/null; then
    cp "$TMPFILE" "$SUDOERS_FILE"
    info "'Defaults targetpw' has been commented out successfully."
  else
    rm -f "$TMPFILE"
    error "Modified sudoers file failed validation. No changes were made."
  fi
  rm -f "$TMPFILE"
else
  warn "'Defaults targetpw' not found or already commented out. Skipping."
fi
 
echo ""
 
# =============================================================================
# METHOD 2: Lock the root password
# =============================================================================
info "Method 2: Locking the root password..."
 
if passwd -S root | grep -q '^root L'; then
  warn "Root password is already locked. Skipping."
else
  passwd -l root
  info "Root password locked successfully (! prepended to hash in /etc/shadow)."
fi
 
echo ""
 
# =============================================================================
# METHOD 3: Set root shell to /bin/false
# =============================================================================
info "Method 3: Setting root shell to /bin/false..."
 
CURRENT_SHELL=$(getent passwd root | cut -d: -f7)
 
if [[ "$CURRENT_SHELL" == "/bin/false" ]]; then
  warn "Root shell is already set to /bin/false. Skipping."
else
  usermod -s /bin/false root
  info "Root shell changed from '$CURRENT_SHELL' to '/bin/false'."
fi
 
echo ""
 
# =============================================================================
# Summary
# =============================================================================
echo "============================================================"
info "Hardening complete. Summary:"
echo ""
echo "  sudoers targetpw : $(grep -E 'Defaults\s+targetpw' /etc/sudoers || echo '(not found / commented out)')"
echo "  root passwd lock : $(passwd -S root | awk '{print $2}')"
echo "  root shell       : $(getent passwd root | cut -d: -f7)"
echo ""
warn "IMPORTANT: 'sudo su -' is now blocked due to /bin/false shell."
warn "Admins should use 'sudo -i' or 'sudo -s' or 'sudo <command>' instead."
echo "============================================================"