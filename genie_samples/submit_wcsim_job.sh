RUN=$1

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${REPO_ROOT}/config.sh"

# ---------------------------------------------------------------- edit me ----
VOLUME=world                     # tank | world -- sets the GENIE, dirt and output paths together
BEAMON=20000                     # GENIE entries per job.  tank: 4000    world: 20000
PRODUCTION=productionv3/world         # output subdir

MEMORY=3000MB
LIFETIME=4h
DISK=5GB
OUTPUT_FOLDER="${PNFS_PERSISTENT}/output/genie_wcsim_${VOLUME}/${PRODUCTION}/"
# ------------------------------------------------------------------------------

export INPUT_PATH="${PNFS_SCRATCH}/WCSim_grid/genie_samples/"
export GENIE=/pnfs/annie/persistent/simulations/genie3/G1810a0211a/standardv1.0/${VOLUME}/
export DIRT=/pnfs/annie/persistent/simulations/g4dirt/G1810a0211a/standardv1.0/${VOLUME}/

# tank has 500 GENIE files, world has 4999. An out-of-range RUN otherwise burns a queue slot
# before jobsub notices the -f source is missing.
[ -f "${GENIE}/gntp.${RUN}.ghep.root" ] \
  || { echo "no GENIE file for RUN=${RUN} in ${GENIE}" >&2; exit 1; }

# A run_job.sh staged before BEAMON existed ignores it and silently runs the tarball's own
# /run/beamOn, shipping a short file that looks normal. Re-run prep_backtrack_v3.sh if this trips.
grep -q 'BEAMON_ARG_SUPPORTED' "${INPUT_PATH}/run_job.sh" 2>/dev/null \
  || { echo "staged run_job.sh is stale -- re-run prep_backtrack_v3.sh" >&2; exit 1; }

echo ""
echo "submitting: ${VOLUME} RUN=${RUN} beamOn=${BEAMON} -> ${OUTPUT_FOLDER}"
echo ""

mkdir -p $OUTPUT_FOLDER

# wrapper script to submit your grid job
jobsub_submit --memory=${MEMORY} --expected-lifetime=${LIFETIME} -G annie --disk=${DISK} --blacklist=Omaha,Swan,Wisconsin,SU-ITS,RAL -f ${INPUT_PATH}/WCSim.tar.gz -f ${INPUT_PATH}/wcsim_container.sh -f ${DIRT}/annie_tank_flux.${RUN}.root -f ${GENIE}/gntp.${RUN}.ghep.root -d OUTPUT $OUTPUT_FOLDER file://${INPUT_PATH}/run_job.sh ${RUN} ${BEAMON}
