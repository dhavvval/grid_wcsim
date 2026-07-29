#!/bin/bash
# Stage the save-on-demand WCSim build for grid submission (productionv3).
#
# Why this script exists: the grid job runs `cd WCSim/build && ./WCSim WCSim.mac`, and
# build/macros/primaries_directory.mac must use RELATIVE globs (./gntp.*.ghep.root) because
# the worker container is bind-mounted -B/srv:/srv only -- /pnfs is not visible inside it.
# But local A/B running needs the ABSOLUTE /pnfs paths. So the macro is swapped to grid mode,
# tarred, and swapped back, with the tarball's copy verified before the swap-back is trusted.
#
# Run once before send.py / submit_wcsim_job.sh. Idempotent.
#
# VOLUME=tank (default) or VOLUME=world picks which sample this tarball is for. The two differ ONLY
# in /run/beamOn, but that is enough that they cannot share a staging dir: world interactions are
# spread through the hall and rock and only ~3% of entries put light in the tank, so a world job
# reads the whole 20k-interaction file to yield ~600 events where a tank job gets 4000 from 4000.
# Staging both to the same INPUT_PATH would leave whichever ran last serving both submissions --
# silently, since the tarballs are otherwise identical. Hence genie_samples/ vs genie_samples_world/,
# matching the same split in submit_wcsim_job.sh.
#
#   VOLUME=world sh prep_backtrack_v3.sh        # stage the world tarball (beamOn 20000)
#   BEAMON=8000 sh prep_backtrack_v3.sh         # override the entry count for either volume

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${REPO_ROOT}/config.sh"

VOLUME="${VOLUME:-tank}"
case "${VOLUME}" in
  tank)  DEFAULT_BEAMON=4000  ; STAGE_SUBDIR="genie_samples"       ;;
  world) DEFAULT_BEAMON=20000 ; STAGE_SUBDIR="genie_samples_world" ;;
  *)     echo "FAIL: VOLUME must be 'tank' or 'world' (got '${VOLUME}')" >&2; exit 1 ;;
esac
BEAMON="${BEAMON:-${DEFAULT_BEAMON}}"
case "${BEAMON}" in ''|*[!0-9]*) echo "FAIL: BEAMON must be a positive integer" >&2; exit 1 ;; esac

BUILD="${WCSIM_LOC}/WCSim/build"
MAC="${BUILD}/macros/primaries_directory.mac"
LOCAL_BACKUP="${MAC}.localmode"
WCMAC="${BUILD}/WCSim.mac"
WCMAC_BACKUP="${WCMAC}.localmode"
STAGE_TMP=""

echo "staging VOLUME=${VOLUME}  /run/beamOn ${BEAMON}  -> ${STAGE_SUBDIR}/"

fail() { echo "FAIL: $*" >&2; exit 1; }

# If we die anywhere between the grid-mode swap and the restore, put the local-mode macros back --
# otherwise the next local A/B run silently reads ./gntp.*.ghep.root from the build dir and finds
# no primaries, and WCSim.mac is left on whatever beamOn the last staging wanted. Step 5 removes
# both backups on success, making this a no-op.
cleanup() {
  rc=$?
  if [ -f "${LOCAL_BACKUP}" ]; then
    mv -f "${LOCAL_BACKUP}" "${MAC}"
    echo "cleanup: restored ${MAC} to local absolute-path mode" >&2
  fi
  if [ -f "${WCMAC_BACKUP}" ]; then
    mv -f "${WCMAC_BACKUP}" "${WCMAC}"
    echo "cleanup: restored ${WCMAC} to its pre-staging /run/beamOn" >&2
  fi
  if [ -n "${STAGE_TMP}" ] && [ -d "${STAGE_TMP}" ]; then
    rm -rf "${STAGE_TMP}"
  fi
  exit $rc
}
trap cleanup EXIT

echo "=== 1. preflight ==="

[ -x "${BUILD}/WCSim" ] || fail "no WCSim executable at ${BUILD}/WCSim"

# The executable must actually contain the save-on-demand messenger command, else every job
# silently produces historical-save output that looks fine and is 34% untraced.
# NOTE: -a is required. Without it GNU grep's binary handling reports no match even though
# the string is present, which reads as "the binary is stale" and sends you into a needless rebuild.
grep -aq "/WCSimIO/SaveTracksOnDemand" "${BUILD}/WCSim" \
  || fail "${BUILD}/WCSim has no /WCSimIO/SaveTracksOnDemand command -- rebuild it (WCSim container)"
echo "  ok: WCSim executable knows /WCSimIO/SaveTracksOnDemand"

grep -qE "^/WCSimIO/SaveTracksOnDemand[[:space:]]+true" "${BUILD}/WCSim.mac" \
  || fail "${BUILD}/WCSim.mac does not set /WCSimIO/SaveTracksOnDemand true"
# beamOn is now SET by step 2 rather than asserted, so all we require here is that exactly one
# active /run/beamOn line exists to rewrite. Two would make the second silently win.
[ "$(grep -cE '^/run/beamOn[[:space:]]+[0-9]+' "${BUILD}/WCSim.mac")" = "1" ] \
  || fail "${BUILD}/WCSim.mac must have exactly one active /run/beamOn line"
grep -qE "^/mygen/generator[[:space:]]+beam" "${BUILD}/WCSim.mac" \
  || fail "${BUILD}/WCSim.mac is not using /mygen/generator beam"
echo "  ok: WCSim.mac has SaveTracksOnDemand true, one /run/beamOn line, generator beam"

# wcsim_container.sh:50 copies wcsim_0.root out unconditionally. A stale one means a crashed
# job still ships a plausible-looking file.
if [ -e "${BUILD}/wcsim_0.root" ]; then
  fail "stale ${BUILD}/wcsim_0.root -- move it away first (a failed job would ship it as if it succeeded)"
fi
echo "  ok: no stale wcsim_0.root in build dir"

echo "=== 2. switch primaries macro to grid mode (relative globs) ==="
cp -p "${MAC}" "${LOCAL_BACKUP}"
python3 - "$MAC" <<'PY'
import re, sys
p = sys.argv[1]
lines = open(p).read().splitlines(True)
out = []
for ln in lines:
    # comment out any ACTIVE absolute-path directive
    if re.match(r'^/mygen/(neutrinos|primaries)directory\s+/', ln):
        ln = '#' + ln
    # uncomment the relative-glob pair
    elif re.match(r'^#\s*/mygen/neutrinosdirectory\s+\./gntp\.\*\.ghep\.root', ln):
        ln = '/mygen/neutrinosdirectory ./gntp.*.ghep.root\n'
    elif re.match(r'^#\s*/mygen/primariesdirectory\s+\./annie_tank_flux\.\*\.root', ln):
        ln = '/mygen/primariesdirectory ./annie_tank_flux.*.root\n'
    out.append(ln)
open(p, 'w').writelines(out)
PY

# neutrinosdirectory MUST be set before primariesdirectory (WCSim builds the TChain in order)
ACTIVE=$(grep -nE '^/mygen/(neutrinos|primaries)directory' "${MAC}" || true)
echo "${ACTIVE}"
[ "$(grep -cE '^/mygen/neutrinosdirectory[[:space:]]+\./gntp' "${MAC}")" = "1" ] \
  || fail "grid-mode neutrinosdirectory not set exactly once"
[ "$(grep -cE '^/mygen/primariesdirectory[[:space:]]+\./annie_tank_flux' "${MAC}")" = "1" ] \
  || fail "grid-mode primariesdirectory not set exactly once"
[ "$(grep -cE '^/mygen/(neutrinos|primaries)directory[[:space:]]+/' "${MAC}")" = "0" ] \
  || fail "an absolute-path directive is still active"
NLINE=$(grep -nE '^/mygen/neutrinosdirectory' "${MAC}" | cut -d: -f1)
PLINE=$(grep -nE '^/mygen/primariesdirectory' "${MAC}" | cut -d: -f1)
[ "${NLINE}" -lt "${PLINE}" ] || fail "neutrinosdirectory (line ${NLINE}) must precede primariesdirectory (line ${PLINE})"
echo "  ok: grid-mode macro valid, ordering correct"

echo "=== 2b. set /run/beamOn for VOLUME=${VOLUME} ==="
# Same swap-tar-restore discipline as the primaries macro: the build dir keeps whatever beamOn the
# user had for local running, and only the tarball carries the grid value.
cp -p "${WCMAC}" "${WCMAC_BACKUP}"
python3 - "${WCMAC}" "${BEAMON}" <<'PY'
import re, sys
p, n = sys.argv[1], sys.argv[2]
lines = open(p).read().splitlines(True)
out = [re.sub(r'^/run/beamOn\s+[0-9]+', '/run/beamOn ' + n, ln) for ln in lines]
open(p, 'w').writelines(out)
PY
grep -qE "^/run/beamOn[[:space:]]+${BEAMON}\$" "${WCMAC}" \
  || fail "failed to set /run/beamOn ${BEAMON} in ${WCMAC}"
echo "  ok: $(grep -E '^/run/beamOn' "${WCMAC}")"

echo "=== 3. tar + stage to pnfs scratch ==="
# Deliberately NOT calling tar_wcsim.py: it packs the whole WCSim/ tree, which now includes a
# 178 MB WCSim/WCSim/.git and the 4.4 MB bt_artifacts_20ev/ A/B keep-dir. None of that is needed
# at runtime and all of it would be transferred to every one of ~251 worker nodes. Same staging
# destination and same three files as tar_wcsim.py, just with excludes.
INPUT_PATH="${PNFS_SCRATCH}/WCSim_grid/${STAGE_SUBDIR}/"
STAGE_TMP="$(mktemp -d)"

tar -czf "${STAGE_TMP}/WCSim.tar.gz" -C "${WCSIM_LOC}" \
    --exclude='WCSim/WCSim/.git' \
    --exclude='WCSim/bt_artifacts_20ev' \
    --exclude='*.bak' \
    --exclude='__pycache__' \
    WCSim
echo "  built $(du -h "${STAGE_TMP}/WCSim.tar.gz" | cut -f1) tarball"

mkdir -p "${INPUT_PATH}"
cp "${STAGE_TMP}/WCSim.tar.gz" "${INPUT_PATH}/WCSim.tar.gz"
cp "$(dirname "$0")/wcsim_container.sh" "${INPUT_PATH}/wcsim_container.sh"
cp "$(dirname "$0")/run_job.sh"         "${INPUT_PATH}/run_job.sh"
echo "  staged to ${INPUT_PATH}"

echo "=== 4. verify the TARBALL's copy is grid mode ==="
# Content is read from the local copy (cheap); the staged /pnfs copy is confirmed by byte size,
# since dCache reads of a ~300 MB archive are slow and the two are a plain cp apart.
TARBALL="${STAGE_TMP}/WCSim.tar.gz"
[ -f "${TARBALL}" ] || fail "tarball not found at ${TARBALL}"
LOCAL_SZ=$(stat -c%s "${TARBALL}")
STAGED_SZ=$(stat -c%s "${INPUT_PATH}/WCSim.tar.gz")
[ "${LOCAL_SZ}" = "${STAGED_SZ}" ] \
  || fail "staged tarball size ${STAGED_SZ} != local ${LOCAL_SZ} -- the copy to pnfs was truncated"
echo "  ok: staged copy is ${STAGED_SZ} bytes, matches local"
TARRED_MAC=$(tar -xzOf "${TARBALL}" WCSim/build/macros/primaries_directory.mac)
echo "${TARRED_MAC}" | grep -qE '^/mygen/neutrinosdirectory[[:space:]]+\./gntp\.\*\.ghep\.root' \
  || fail "tarball's primaries_directory.mac is NOT in grid mode"
if echo "${TARRED_MAC}" | grep -qE '^/mygen/(neutrinos|primaries)directory[[:space:]]+/'; then
  fail "tarball's primaries_directory.mac still has an active absolute path"
fi
TARRED_WCMAC=$(tar -xzOf "${TARBALL}" WCSim/build/WCSim.mac)
echo "${TARRED_WCMAC}" | grep -qE '^/WCSimIO/SaveTracksOnDemand[[:space:]]+true' \
  || fail "tarball's WCSim.mac does not set SaveTracksOnDemand true"
# The whole point of the volume split -- a world tarball carrying tank's beamOn would run and
# produce a believable file with 1/5 the entries read.
echo "${TARRED_WCMAC}" | grep -qE "^/run/beamOn[[:space:]]+${BEAMON}\$" \
  || fail "tarball's WCSim.mac is not at /run/beamOn ${BEAMON} (VOLUME=${VOLUME})"
if tar -tzf "${TARBALL}" | grep -q '^WCSim/build/wcsim_0\.root$'; then
  fail "tarball contains a stale wcsim_0.root"
fi
echo "  ok: tarball verified (grid-mode primaries, SaveTracksOnDemand true, beamOn ${BEAMON}, no stale output)"
echo "  tarball size: $(du -h "${TARBALL}" | cut -f1)"

echo "=== 5. restore local mode ==="
mv -f "${LOCAL_BACKUP}" "${MAC}"
[ "$(grep -cE '^/mygen/(neutrinos|primaries)directory[[:space:]]+/' "${MAC}")" = "2" ] \
  || fail "restore did not leave exactly 2 active absolute-path directives in ${MAC}"
grep -E '^/mygen/(neutrinos|primaries)directory' "${MAC}"
echo "  ok: ${MAC} restored to local absolute-path mode"
mv -f "${WCMAC_BACKUP}" "${WCMAC}"
echo "  ok: ${WCMAC} restored ($(grep -E '^/run/beamOn' "${WCMAC}"))"

MAXRUN=$([ "${VOLUME}" = "world" ] && echo 4998 || echo 499)
cat <<EOF

Staged VOLUME=${VOLUME} (beamOn ${BEAMON}) to ${INPUT_PATH}
To submit (needs a valid token -- run 'htgettoken -i annie -a htvaultprod.fnal.gov' first):

  # pilot, one job:
  VOLUME=${VOLUME} PRODUCTION=productionv3 sh ${REPO_ROOT}/genie_samples/submit_wcsim_job.sh 0

  # fan out after the pilot passes (RUN index max for ${VOLUME} is ${MAXRUN}):
  for i in \$(seq 1 250); do VOLUME=${VOLUME} PRODUCTION=productionv3 sh ${REPO_ROOT}/genie_samples/submit_wcsim_job.sh \$i; done

Output lands in \${PNFS_PERSISTENT}/output/genie_wcsim_${VOLUME}/productionv3/

EOF
