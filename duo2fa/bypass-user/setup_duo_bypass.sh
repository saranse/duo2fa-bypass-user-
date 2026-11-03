#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
DUO_USER=''
BYPASS_USERS=''
ACTION=setup
BACKUP_DIR=''

show_banner() {
  printf '\n%s\n' '========================================' '                 DUO 2FA' '       SSH Two-Factor Authentication' '========================================'
}

show_banner
while (($#)); do
  case "$1" in
    --duo-user) [[ $# -ge 2 ]] || exit 2; DUO_USER=$2; shift 2 ;;
    --bypass-users) [[ $# -ge 2 ]] || exit 2; BYPASS_USERS=$2; shift 2 ;;
    --add-bypass-users) ACTION=add-bypass; shift ;;
    --rollback) ACTION=rollback; shift ;;
    -h|--help) echo "Usage: sudo $0 [--duo-user USER --bypass-users USER1,USER2] [--add-bypass-users|--rollback]"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ $EUID -eq 0 ]] || { echo "Run with sudo: $0" >&2; exit 1; }

if [[ $# -eq 0 && -t 0 && -z "$DUO_USER" && -z "$BYPASS_USERS" && "$ACTION" == setup ]]; then
  printf '\n%s\n' '1) Apply Duo bypass policy using existing Duo installation/config (keeps existing keys)' '2) Add bypass user(s) to existing setup (group change only)' '3) Roll back a previous setup from backup' '0) Exit'
  read -r -p 'Select an option: ' MENU_CHOICE
  case "$MENU_CHOICE" in
    1)
      ACTION=setup
      read -r -p 'This will use existing Duo keys and update group/PAM/SSH settings. Continue? [y/N]: ' CONFIRM_SETUP
      [[ "$CONFIRM_SETUP" =~ ^[Yy]$ ]] || { echo 'Setup cancelled.'; exit 0; }
      ;;
    2) ACTION=add-bypass ;;
    3) ACTION=rollback ;;
    0) echo 'Exit.'; exit 0 ;;
    *) echo 'Invalid menu option.' >&2; exit 2 ;;
  esac
fi

restore_backup() {
  local backup="$1" path name
  [[ -d "$backup" && "$backup" == /root/duo-setup-backup-* ]] || { echo 'Invalid backup directory.' >&2; return 1; }
  for path in /etc/pam.d/sshd /etc/duo/pam_duo.conf /etc/ssh/sshd_config /etc/ssh/sshd_config.d/00-duo-bypass.conf; do
    name=$(basename "$path")
    if [[ -e "$backup/$name" ]]; then mkdir -p "$(dirname "$path")"; cp -a "$backup/$name" "$path"
    elif [[ -e "$backup/$name.absent" ]]; then rm -f "$path"; fi
  done
  if [[ -f "$backup/duo-bypass.members" ]] && getent group duo-bypass >/dev/null; then
    local current user
    current=$(getent group duo-bypass | awk -F: '{print $4}' | tr ',' ' ')
    for user in $current; do
      if ! grep -Fxq "$user" "$backup/duo-bypass.members"; then gpasswd -d "$user" duo-bypass >/dev/null || true; fi
    done
    while IFS= read -r user; do
      [[ -n "$user" ]] && id "$user" >/dev/null 2>&1 && usermod -aG duo-bypass "$user"
    done < "$backup/duo-bypass.members"
  fi
  if [[ -e "$backup/duo-bypass-group.absent" ]] && getent group duo-bypass >/dev/null; then
    [[ -z "$(getent group duo-bypass | awk -F: '{print $4}')" ]] && groupdel duo-bypass || true
  fi
  if command -v sshd >/dev/null && sshd -t >/dev/null 2>&1; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  else
    echo 'Restored files, but sshd config validation failed; inspect before reload.' >&2
    return 1
  fi
  echo "Rollback complete from $backup"
}

if [[ "$ACTION" == rollback ]]; then
  [[ -t 0 ]] || { echo 'Rollback menu requires an interactive terminal.' >&2; exit 2; }
  mapfile -t BACKUPS < <(find /root -maxdepth 1 -type d -name 'duo-setup-backup-*' -printf '%f\n' | sort -r)
  ((${#BACKUPS[@]})) || { echo 'No Duo setup backups found in /root.' >&2; exit 1; }
  printf '\nAvailable backups:\n'
  for i in "${!BACKUPS[@]}"; do printf '%d) /root/%s\n' "$((i+1))" "${BACKUPS[$i]}"; done
  read -r -p 'Select backup number to restore (0 cancels): ' BACKUP_CHOICE
  [[ "$BACKUP_CHOICE" =~ ^[0-9]+$ ]] || { echo 'Invalid selection.' >&2; exit 2; }
  (( BACKUP_CHOICE == 0 )) && { echo 'Rollback cancelled.'; exit 0; }
  (( BACKUP_CHOICE <= ${#BACKUPS[@]} )) || { echo 'Invalid selection.' >&2; exit 2; }
  BACKUP_DIR="/root/${BACKUPS[$((BACKUP_CHOICE-1))]}"
  read -r -p "Restore files and bypass group membership from $BACKUP_DIR? [y/N]: " CONFIRM_ROLLBACK
  [[ "$CONFIRM_ROLLBACK" =~ ^[Yy]$ ]] || { echo 'Rollback cancelled.'; exit 0; }
  restore_backup "$BACKUP_DIR"
  exit $?
fi

if [[ "$ACTION" == add-bypass ]]; then
  getent group duo-bypass >/dev/null || { echo 'Group duo-bypass does not exist. Run setup first.' >&2; exit 1; }
  if [[ -z "$BYPASS_USERS" ]]; then
    [[ -t 0 ]] || { echo 'Specify --bypass-users when running without an interactive terminal.' >&2; exit 2; }
    read -r -p 'Existing Linux user(s) to bypass (comma-separated): ' BYPASS_USERS
  fi
  [[ -n "$BYPASS_USERS" ]] || { echo 'Enter at least one Linux username.' >&2; exit 2; }
  for user in $(echo "$BYPASS_USERS" | tr ',' ' '); do
    id "$user" >/dev/null 2>&1 || { echo "Linux user not found: $user" >&2; exit 1; }
    usermod -aG duo-bypass "$user"
  done
  echo 'Bypass group updated. Verify membership with: getent group duo-bypass'
  echo 'These accounts will skip Duo MFA for SSH. Test a new SSH login.'
  exit 0
fi

if [[ -z "$DUO_USER" || -z "$BYPASS_USERS" ]]; then
  [[ -t 0 ]] || { echo 'Specify --duo-user and --bypass-users when running without an interactive terminal.' >&2; exit 2; }
  [[ -n "$DUO_USER" ]] || read -r -p 'Linux user that must use Duo MFA: ' DUO_USER
  [[ -n "$BYPASS_USERS" ]] || read -r -p 'Linux user(s) to bypass (comma-separated, e.g. root): ' BYPASS_USERS
fi

[[ -n "$DUO_USER" && -n "$BYPASS_USERS" ]] || { echo 'Duo user and bypass users are required.' >&2; exit 2; }
id "$DUO_USER" >/dev/null 2>&1 || { echo "Linux user not found: $DUO_USER" >&2; exit 1; }
for user in $(echo "$BYPASS_USERS" | tr ',' ' '); do
  [[ "$user" != "$DUO_USER" ]] || { echo 'Duo user cannot be bypassed' >&2; exit 1; }
  id "$user" >/dev/null 2>&1 || { echo "Linux user not found: $user" >&2; exit 1; }
done
source /etc/os-release
case "$ID" in
  ubuntu) DISTRO=ubuntu; [[ $(dpkg --print-architecture) == amd64 ]] || { echo 'Ubuntu package instructions require amd64' >&2; exit 1; } ;;
  almalinux) DISTRO=almalinux ;;
  *) echo "Unsupported distribution: $ID; use Ubuntu or AlmaLinux" >&2; exit 1 ;;
esac
if [[ ! -f /etc/duo/pam_duo.conf ]] || ! grep -Eq '^[[:space:]]*ikey[[:space:]]*=[[:space:]]*[^[:space:]]+' /etc/duo/pam_duo.conf || ! grep -Eq '^[[:space:]]*skey[[:space:]]*=[[:space:]]*[^[:space:]]+' /etc/duo/pam_duo.conf || ! grep -Eq '^[[:space:]]*host[[:space:]]*=[[:space:]]*[A-Za-z0-9.-]+\.duosecurity\.com' /etc/duo/pam_duo.conf; then
  echo 'No complete existing Duo config found at /etc/duo/pam_duo.conf. This mode will not ask for or replace Duo keys; configure Duo first or restore its existing config.' >&2
  exit 1
fi
[[ -r /etc/duo/pam_duo.conf ]] || { echo 'Cannot read existing Duo config.' >&2; exit 1; }
if systemctl is-active --quiet ssh; then SSH_SERVICE=ssh
elif systemctl is-active --quiet sshd; then SSH_SERVICE=sshd
else echo 'SSH service is not active; refusing to change authentication config.' >&2; exit 1; fi
BACKUP_DIR=/root/duo-setup-backup-$(date +%Y%m%d-%H%M%S)
mkdir -m 700 "$BACKUP_DIR"
for f in /etc/pam.d/sshd /etc/duo/pam_duo.conf /etc/ssh/sshd_config /etc/ssh/sshd_config.d/00-duo-bypass.conf; do
  if [[ -e "$f" ]]; then cp -a "$f" "$BACKUP_DIR/$(basename "$f")"
  else : > "$BACKUP_DIR/$(basename "$f").absent"; fi
done
if getent group duo-bypass >/dev/null; then getent group duo-bypass | awk -F: '{print $4}' | tr ',' '\n' > "$BACKUP_DIR/duo-bypass.members"
else : > "$BACKUP_DIR/duo-bypass-group.absent"; : > "$BACKUP_DIR/duo-bypass.members"; fi
echo "Backups saved in $BACKUP_DIR"
rollback() {
  status=$?
  (( status == 0 )) && return 0
  local current user
  trap - EXIT ERR
  echo "Setup failed; restoring PAM and SSH files from $BACKUP_DIR" >&2
  for path in /etc/pam.d/sshd /etc/duo/pam_duo.conf /etc/ssh/sshd_config /etc/ssh/sshd_config.d/00-duo-bypass.conf; do
    name=$(basename "$path")
    if [[ -e "$BACKUP_DIR/$name" ]]; then cp -a "$BACKUP_DIR/$name" "$path"
    elif [[ -e "$BACKUP_DIR/$name.absent" ]]; then rm -f "$path"; fi
  done
  if [[ -f "$BACKUP_DIR/duo-bypass.members" ]] && getent group duo-bypass >/dev/null; then
    current=$(getent group duo-bypass | awk -F: '{print $4}' | tr ',' ' ')
    for user in $current; do grep -Fxq "$user" "$BACKUP_DIR/duo-bypass.members" || gpasswd -d "$user" duo-bypass >/dev/null || true; done
    while IFS= read -r user; do [[ -n "$user" ]] && id "$user" >/dev/null 2>&1 && usermod -aG duo-bypass "$user"; done < "$BACKUP_DIR/duo-bypass.members"
  fi
  if [[ -e "$BACKUP_DIR/duo-bypass-group.absent" ]] && getent group duo-bypass >/dev/null; then
    [[ -z "$(getent group duo-bypass | awk -F: '{print $4}')" ]] && groupdel duo-bypass || true
  fi
  if command -v sshd >/dev/null && sshd -t >/dev/null 2>&1; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  fi
  exit "$status"
}
trap rollback EXIT
echo 'Checking existing Duo Unix installation...'
if [[ "$DISTRO" == ubuntu ]]; then
  dpkg-query -W -f='${Status}' duo-unix 2>/dev/null | grep -qx 'install ok installed' || { echo 'Duo Unix is not installed. This existing-config mode will not install packages.' >&2; exit 1; }
  echo 'Duo Unix package is installed; no package changes.'
  MODULE=$(dpkg -L duo-unix | awk '/\/pam_duo\.so$/ {print; exit}')
else
  rpm -q duo_unix >/dev/null 2>&1 || { echo 'Duo Unix is not installed. This existing-config mode will not install packages.' >&2; exit 1; }
  echo 'Duo Unix package is installed; no package changes.'
  MODULE=$(rpm -ql duo_unix | awk '/\/pam_duo\.so$/ {print; exit}')
fi
[[ -n "$MODULE" && -f "$MODULE" ]] || { echo 'pam_duo.so not found in installed package' >&2; exit 1; }
getent group duo-bypass >/dev/null || groupadd duo-bypass
for user in $(echo "$BYPASS_USERS" | tr ',' ' '); do usermod -aG duo-bypass "$user"; done
mkdir -p /etc/duo
TMP_CONFIG=$(mktemp /etc/duo/pam_duo.conf.XXXXXX)
cp -a /etc/duo/pam_duo.conf "$TMP_CONFIG"
if grep -Eq '^[[:space:]]*groups[[:space:]]*=' "$TMP_CONFIG"; then
  sed -i -E 's/^[[:space:]]*groups[[:space:]]*=.*/groups = *,!duo-bypass/' "$TMP_CONFIG"
else printf '\ngroups = *,!duo-bypass\n' >> "$TMP_CONFIG"; fi
chown root:root "$TMP_CONFIG"; chmod 600 "$TMP_CONFIG"; mv -f "$TMP_CONFIG" /etc/duo/pam_duo.conf
if ! grep -Fq "$MODULE" /etc/pam.d/sshd; then
  if [[ "$DISTRO" == ubuntu ]]; then PATTERN='^[[:space:]]*@include[[:space:]]+common-auth([[:space:]]|$)'
  else PATTERN='^[[:space:]]*auth[[:space:]]+substack[[:space:]]+password-auth([[:space:]]|$)'; fi
  grep -Eq "$PATTERN" /etc/pam.d/sshd || { echo 'Expected PAM auth line not found; inspect PAM stack manually' >&2; exit 1; }
  awk -v pattern="$PATTERN" -v module="$MODULE" '{print} $0 ~ pattern && !done {print "auth required " module; done=1} END {if (!done) exit 1}' /etc/pam.d/sshd > /etc/pam.d/sshd.tmp
  cat /etc/pam.d/sshd.tmp > /etc/pam.d/sshd; rm -f /etc/pam.d/sshd.tmp
fi
mkdir -p /etc/ssh/sshd_config.d
if ! grep -Eq '^[[:space:]]*Include[[:space:]].*sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
  { printf 'Include /etc/ssh/sshd_config.d/*.conf\n'; cat /etc/ssh/sshd_config; } > /etc/ssh/sshd_config.tmp
  cat /etc/ssh/sshd_config.tmp > /etc/ssh/sshd_config; rm -f /etc/ssh/sshd_config.tmp
fi
printf '%s\n' '# Managed by setup_duo_bypass.sh' 'UsePAM yes' 'KbdInteractiveAuthentication yes' 'UseDNS no' > /etc/ssh/sshd_config.d/00-duo-bypass.conf
if grep -RqsE '^[[:space:]]*Match[[:space:]]' /etc/ssh/sshd_config.d; then
  echo 'SSH drop-in has a Match block; stop and review SSH config manually' >&2; exit 1
fi
if ! grep -Fq '# BEGIN setup_duo_bypass.sh' /etc/ssh/sshd_config; then
  cat >> /etc/ssh/sshd_config <<EOF

# BEGIN setup_duo_bypass.sh
Match all
Match User $DUO_USER
    AuthenticationMethods keyboard-interactive
    PasswordAuthentication no
EOF
fi
sshd -t
EFFECTIVE=$(sshd -T -C "user=$DUO_USER,host=localhost,addr=127.0.0.1")
grep -qx 'usepam yes' <<<"$EFFECTIVE"
grep -qx 'kbdinteractiveauthentication yes' <<<"$EFFECTIVE"
grep -qx 'authenticationmethods keyboard-interactive' <<<"$EFFECTIVE"
grep -qx 'passwordauthentication no' <<<"$EFFECTIVE"
  systemctl reload "$SSH_SERVICE"
trap - EXIT ERR
echo "Duo policy applied for $DUO_USER using the existing keys; bypass users: $BYPASS_USERS"
echo "Keep the root session open until a new login succeeds. Backups: $BACKUP_DIR"
echo "Test: ssh -o PreferredAuthentications=keyboard-interactive -o PubkeyAuthentication=no $DUO_USER@SERVER"
