RUN=$1

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${REPO_ROOT}/config.sh"

# Everything that distinguishes one job from another lives here, as an environment variable with a
# default. Nothing below requires re-staging WCSim.tar.gz -- the tarball is the build, these are the
# instructions. Re-run prep_backtrack_v3.sh only when you change WCSim itself.
#
#   VOLUME        tank (default) | world   which GENIE production to read
#   BEAMON        how many GENIE entries this job reads (per-volume default below)
#   PRODUCTION    output subdir under genie_wcsim_<volume>/  (default productionv2)
#   OUTPUT_FOLDER full output path, overriding PRODUCTION and the usual parent
#   MEMORY / LIFETIME / DISK               grid resource request
#
#   VOLUME=world PRODUCTION=productionv3 sh submit_wcsim_job.sh 0
#   BEAMON=8000 LIFETIME=12h MEMORY=4000MB sh submit_wcsim_job.sh 3
#   OUTPUT_FOLDER=/pnfs/annie/scratch/users/dajana/mytest/ sh submit_wcsim_job.sh 0
#
# genie3 and g4dirt both carry symmetric tank/ and world/ subdirs with identical filenames, so a
# volume switch moves only the two input paths and the output subdir. WCSim and run_job.sh are
# volume-agnostic. What does differ is yield: world interactions happen in the hall and surrounding
# rock and most deposit no tank light, historically ~600 useful events per 20k-interaction file
# (~3%) against ~100% for tank. Hence the larger default BEAMON for world.
#
# Resource defaults are sized for tank at 4000 entries: those jobs ran 1.2-4.0h at 1000 entries and
# were clipping a 4h wall, and output grew ~28MB -> ~112MB. If you change BEAMON substantially,
# change LIFETIME and DISK with it -- they are not derived, because runtime per entry depends on
# the volume as much as the count.

VOLUME="${VOLUME:-tank}"
case "${VOLUME}" in
  tank)  DEFAULT_BEAMON=4000  ;;
  world) DEFAULT_BEAMON=20000 ;;
  *)     echo "VOLUME must be 'tank' or 'world' (got '${VOLUME}')" >&2; exit 1 ;;
esac
BEAMON="${BEAMON:-${DEFAULT_BEAMON}}"
case "${BEAMON}" in ''|*[!0-9]*) echo "BEAMON must be a positive integer (got '${BEAMON}')" >&2; exit 1 ;; esac

MEMORY="${MEMORY:-8000MB}"
LIFETIME="${LIFETIME:-24h}"
DISK="${DISK:-10GB}"

# One staged build serves both volumes -- beamOn is set on the worker, not baked into the tarball.
export INPUT_PATH="${PNFS_SCRATCH}/WCSim_grid/genie_samples/"
export GENIE=/pnfs/annie/persistent/simulations/genie3/G1810a0211a/standardv1.0/${VOLUME}/
export DIRT=/pnfs/annie/persistent/simulations/g4dirt/G1810a0211a/standardv1.0/${VOLUME}/

# tank has 500 GENIE files, world has 4999. Submitting a RUN past the end costs a full queue slot
# before jobsub notices the -f source is missing, so check here instead.
[ -f "${GENIE}/gntp.${RUN}.ghep.root" ] \
  || { echo "no GENIE file ${GENIE}/gntp.${RUN}.ghep.root -- RUN out of range for VOLUME=${VOLUME}?" >&2; exit 1; }
[ -f "${DIRT}/annie_tank_flux.${RUN}.root" ] \
  || { echo "no dirt flux ${DIRT}/annie_tank_flux.${RUN}.root" >&2; exit 1; }

# A run_job.sh staged before BEAMON existed would ignore the argument and silently run the
# tarball's own /run/beamOn -- a world job would read 4000 entries instead of 20000 and produce a
# perfectly believable short file. Cheap to check, impossible to spot afterwards.
grep -q 'BEAMON_ARG_SUPPORTED' "${INPUT_PATH}/run_job.sh" 2>/dev/null \
  || { echo "staged run_job.sh at ${INPUT_PATH} predates the BEAMON argument -- re-run prep_backtrack_v3.sh" >&2; exit 1; }

echo ""
echo "submitting: VOLUME=${VOLUME} RUN=${RUN} beamOn=${BEAMON} PRODUCTION=${PRODUCTION:-productionv2}"
echo "            ${MEMORY} / ${LIFETIME} / ${DISK}"
echo ""

# PRODUCTION sets the subdir under the usual genie_wcsim_<volume>/ parent. OUTPUT_FOLDER overrides
# the whole path when you want output somewhere else entirely; it wins over PRODUCTION.
OUTPUT_FOLDER="${OUTPUT_FOLDER:-${PNFS_PERSISTENT}/output/genie_wcsim_${VOLUME}/${PRODUCTION:-productionv2}/}"
mkdir -p "$OUTPUT_FOLDER" \
  || { echo "cannot create output dir ${OUTPUT_FOLDER}" >&2; exit 1; }
echo "            output -> ${OUTPUT_FOLDER}"

# wrapper script to submit your grid job
jobsub_submit --memory=${MEMORY} --expected-lifetime=${LIFETIME} -G annie --disk=${DISK} --blacklist=Omaha,Swan,Wisconsin,SU-ITS,RAL -f ${INPUT_PATH}/WCSim.tar.gz -f ${INPUT_PATH}/wcsim_container.sh -f ${DIRT}/annie_tank_flux.${RUN}.root -f ${GENIE}/gntp.${RUN}.ghep.root -d OUTPUT $OUTPUT_FOLDER file://${INPUT_PATH}/run_job.sh ${RUN} ${BEAMON}
