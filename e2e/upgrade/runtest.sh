#!/bin/bash
# REPO_URL: yum repo holding the fixed restraint RPMs
MARK=/var/tmp/e2e-upgrade-done
OUT=$(mktemp)
res() { rstrnt-report-result -o "$OUT" "$TEST/$1" "$2" 0; : > "$OUT"; }

if [ "${RSTRNT_REBOOTCOUNT:-0}" -gt 0 ]; then
    { rpm -q restraint restraint-rhts; semodule -l | grep -xE 'restraint|rhts'; } > "$OUT" 2>&1
    cat "$OUT"
    if [ "$(semodule -l | grep -cxE 'restraint|rhts')" = 2 ]; then res after-reboot PASS; else res after-reboot FAIL; fi
    exit 0
fi
if [ -e "$MARK" ]; then     # restraintd restarted and re-ran us before the reboot
    rstrnt-reboot
    exit 0
fi

{
echo "## before"; rpm -q restraint restraint-rhts; semodule -l | grep -xE 'restraint|rhts' || echo "(no restraint/rhts modules loaded)"
printf '[selinuxfix]\nname=selinuxfix\nbaseurl=%s\ngpgcheck=0\n' "$REPO_URL" > /etc/yum.repos.d/selinuxfix.repo
echo "## upgrade"
touch "$MARK"
dnf -y upgrade restraint restraint-rhts 2>&1
echo "## after"; rpm -q restraint restraint-rhts; semodule -l | grep -xE 'restraint|rhts'
} > "$OUT" 2>&1
cat "$OUT"
if [ "$(semodule -l | grep -cxE 'restraint|rhts')" = 2 ] && rpm -q restraint | grep -q selinuxfix; then
    res upgrade PASS
else
    res upgrade FAIL
fi
rstrnt-reboot
