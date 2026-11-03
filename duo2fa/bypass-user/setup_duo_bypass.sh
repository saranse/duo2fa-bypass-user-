#!/usr/bin/env bash
set -Eeuo pipefail
umask 077
DUO_USER=''
BYPASS_USERS=''
while (($#)); do
  case "$1" in
    --duo-user) [[ $# -ge 2 ]] || exit 2; DUO_USER=$2; shift 2 ;;
    --bypass-users) [[ $# -ge 2 ]] || exit 2; BYPASS_USERS=$2; shift 2 ;;
    -h|--help) echo "Usage: sudo $0 --duo-user duo-user --bypass-users root,serviceuser"; exit 0 ;;
    *) echo "Unknown option: $1" >&2; exit 2 ;;
  esac
done
[[ $EUID -eq 0 ]] || { echo "Run with sudo: $0 --duo-user duo-user --bypass-users root" >&2; exit 1; }
[[ -n "$DUO_USER" && -n "$BYPASS_USERS" ]] || { echo 'Specify --duo-user and --bypass-users' >&2; exit 2; }
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
read -r -p 'Duo Integration Key (ikey): ' DUO_IKEY
read -r -s -p 'Duo Secret Key (skey): ' DUO_SKEY; printf '\n'
read -r -p 'Duo API hostname: ' DUO_HOST
[[ -n "$DUO_IKEY" && -n "$DUO_SKEY" && "$DUO_HOST" =~ ^[A-Za-z0-9.-]+\.duosecurity\.com$ ]] || { echo 'Invalid Duo credentials or API hostname' >&2; exit 1; }
BACKUP_DIR=/root/duo-setup-backup-$(date +%Y%m%d-%H%M%S)
mkdir -m 700 "$BACKUP_DIR"
for f in /etc/pam.d/sshd /etc/duo/pam_duo.conf /etc/ssh/sshd_config /etc/ssh/sshd_config.d/00-duo-bypass.conf; do
  if [[ -e "$f" ]]; then cp -a "$f" "$BACKUP_DIR/$(basename "$f")"
  else : > "$BACKUP_DIR/$(basename "$f").absent"; fi
done
echo "Backups saved in $BACKUP_DIR"
rollback() {
  status=$?
  trap - ERR
  echo "Setup failed; restoring PAM and SSH files from $BACKUP_DIR" >&2
  for path in /etc/pam.d/sshd /etc/duo/pam_duo.conf /etc/ssh/sshd_config /etc/ssh/sshd_config.d/00-duo-bypass.conf; do
    name=$(basename "$path")
    if [[ -e "$BACKUP_DIR/$name" ]]; then cp -a "$BACKUP_DIR/$name" "$path"
    elif [[ -e "$BACKUP_DIR/$name.absent" ]]; then rm -f "$path"; fi
  done
  if command -v sshd >/dev/null && sshd -t >/dev/null 2>&1; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  fi
  exit "$status"
}
trap rollback ERR
echo 'Installing Duo Unix...'
if [[ "$DISTRO" == ubuntu ]]; then
  curl -fsSL https://duo.com/DUO-GPG-PUBLIC-KEY.asc | gpg --dearmor --yes -o /etc/apt/trusted.gpg.d/duo.gpg
  printf 'deb [arch=amd64] https://pkg.duosecurity.com/Ubuntu %s main\n' "$VERSION_CODENAME" > /etc/apt/sources.list.d/duosecurity.list
  apt-get update
  DEBIAN_FRONTEND=noninteractive apt-get install -y duo-unix
  MODULE=$(dpkg -L duo-unix | awk '/\/pam_duo\.so$/ {print; exit}')
else
  rpm --import https://duo.com/DUO-GPG-PUBLIC-KEY.asc
  mkdir -p /etc/yum.repos.d
  printf '%s\n' '[duosecurity]' 'name=Duo Security Repository' 'baseurl=https://pkg.duosecurity.com/RedHat/$releasever/$basearch' 'enabled=1' 'gpgcheck=1' > /etc/yum.repos.d/duosecurity.repo
  dnf makecache --refresh
  dnf install -y duo_unix
  MODULE=$(rpm -ql duo_unix | awk '/\/pam_duo\.so$/ {print; exit}')
fi
[[ -n "$MODULE" && -f "$MODULE" ]] || { echo 'pam_duo.so not found in installed package' >&2; exit 1; }
getent group duo-bypass >/dev/null || groupadd duo-bypass
for user in $(echo "$BYPASS_USERS" | tr ',' ' '); do usermod -aG duo-bypass "$user"; done
mkdir -p /etc/duo
TMP_CONFIG=$(mktemp /etc/duo/pam_duo.conf.XXXXXX)
cat > "$TMP_CONFIG" <<EOF
[duo]
ikey = $DUO_IKEY
skey = $DUO_SKEY
host = $DUO_HOST
groups = *,!duo-bypass
failmode = secure
EOF
chown root:root "$TMP_CONFIG"; chmod 600 "$TMP_CONFIG"; mv -f "$TMP_CONFIG" /etc/duo/pam_duo.conf
unset DUO_SKEY
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
if systemctl is-active --quiet ssh; then systemctl reload ssh
elif systemctl is-active --quiet sshd; then systemctl reload sshd
else echo 'SSH service is not active' >&2; exit 1; fi
trap - ERR
echo "Duo enabled for $DUO_USER; bypass users: $BYPASS_USERS"
echo "Keep the root session open until a new login succeeds. Backups: $BACKUP_DIR"
echo "Test: ssh -o PreferredAuthentications=keyboard-interactive -o PubkeyAuthentication=no $DUO_USER@SERVER"
