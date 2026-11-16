#!/bin/bash
# E2E check for restraint SELinux modules.
#   EXPECT_RELEASE: substring the installed restraint release must contain
#                   (empty = do not check)

FAILS=0
report() {  # name PASS|FAIL [score]
    local name=$1 res=$2
    [ "$res" = PASS ] || FAILS=$((FAILS + 1))
    echo "### $name: $res"
    rstrnt-report-result -o "$OUTPUTFILE" "$TEST/$name" "$res" 0
    : > "$OUTPUTFILE"
}
OUTPUTFILE=$(mktemp)
log() { echo "$@" | tee -a "$OUTPUTFILE"; }
run() { log "\$ $*"; "$@" >> "$OUTPUTFILE" 2>&1; local rc=$?; cat "$OUTPUTFILE" | tail -n +2; return $rc; }

# 1. packages
run rpm -q restraint restraint-rhts redhat-release libsepol policycoreutils selinux-policy-targeted
NVR=$(rpm -q --qf '%{VERSION}-%{RELEASE}' restraint)
if [ -n "$EXPECT_RELEASE" ] && [[ "$NVR" != *"$EXPECT_RELEASE"* ]]; then
    log "restraint is $NVR, expected release containing '$EXPECT_RELEASE'"
    report packages FAIL
else
    report packages PASS
fi

# 2. enforcing
run getenforce
[ "$(getenforce)" = Enforcing ] && report enforcing PASS || report enforcing FAIL

# 3. installed module files have a loadable format for this RHEL .0
MAJOR=$(rpm -E %rhel)
mkdir -p /tmp/ppcheck/selinux
for m in restraint rhts; do
    cp /usr/share/selinux/packages/restraint/$m.pp /tmp/ppcheck/selinux/$m.el$MAJOR.pp
done
log "\$ check-prebuilt-modules.py (installed modules as el$MAJOR)"
python3 - "$PWD/check-prebuilt-modules.py" >> "$OUTPUTFILE" 2>&1 <<'PY'
import importlib.util, sys
spec = importlib.util.spec_from_file_location("c", sys.argv[1])
c = importlib.util.module_from_spec(spec); spec.loader.exec_module(c)
c.ROOT = "/tmp/ppcheck"; c.PATTERNS = ("selinux/*.el*.pp",)
sys.exit(c.main())
PY
rc=$?; cat "$OUTPUTFILE"
[ $rc -eq 0 ] && report module-format PASS || report module-format FAIL

# 4. both modules are loaded
run semodule -l
for m in restraint rhts; do
    if semodule -l | grep -qx "$m"; then report module-loaded-$m PASS; else report module-loaded-$m FAIL; fi
done

# 5. task runs in unconfined_t (restraint's 20_unconfined runcon worked)
run id -Z
if id -Z | grep -q ':unconfined_r:unconfined_t:'; then report task-context PASS; else report task-context FAIL; fi

# 6. runcon from restraintd's domain is allowed by policy
run sesearch --allow -s unconfined_service_t -t unconfined_t -c process -p transition 2>/dev/null || true
PID=$(systemctl show -p MainPID --value restraintd)
run ps -o pid,label,cmd -p "$PID"
if command -v sesearch >/dev/null; then
    sesearch --allow -s unconfined_service_t -t unconfined_t -c process -p transition | grep -q transition \
        && report policy-transition PASS || report policy-transition FAIL
fi

# 7. no runcon / unconfined_service_t AVC denials since boot
run ausearch -m AVC,USER_AVC -ts boot -i
if ausearch -m AVC -ts boot 2>/dev/null | grep -q 'scontext=system_u:system_r:unconfined_service_t'; then
    report no-avc FAIL
else
    report no-avc PASS
fi

echo "failures: $FAILS"
exit 0
