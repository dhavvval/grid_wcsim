RUN=$1

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${REPO_ROOT}/config.sh"

# Tank samples read 4000 GENIE entries/job (/run/beamOn 4000), ~4x the work of the old 1000-event jobs.
# At 1000 events jobs ran ~1.2-4.0h and were clipping the 4h wall; 4x that needs much more headroom.
# Output ROOT also grows ~4x (~28MB -> ~112MB), so disk is bumped too.
#
# VOLUME=tank (default) or VOLUME=world selects which GENIE production to read. genie3 and g4dirt
# both carry symmetric tank/ and world/ subdirs with identical filenames, so only these three paths
# change -- run_job.sh and WCSim itself are volume-agnostic. World interactions happen in the hall
# and surrounding rock, so most entries deposit no tank light: the historical yield is ~600 useful
# events per 20k-interaction file (~3%), against ~100% for tank. Budget accordingly, and note that
# the two volumes must NOT share a staging dir -- prep_backtrack_v3.sh stages a volume-specific
# WCSim.tar.gz (different /run/beamOn), and one would silently overwrite the other.

VOLUME="${VOLUME:-tank}"
case "${VOLUME}" in
  tank)  export INPUT_PATH="${PNFS_SCRATCH}/WCSim_grid/genie_samples/" ;;
  world) export INPUT_PATH="${PNFS_SCRATCH}/WCSim_grid/genie_samples_world/" ;;
  *)     echo "VOLUME must be 'tank' or 'world' (got '${VOLUME}')" >&2; exit 1 ;;
esac
export GENIE=/pnfs/annie/persistent/simulations/genie3/G1810a0211a/standardv1.0/${VOLUME}/
export DIRT=/pnfs/annie/persistent/simulations/g4dirt/G1810a0211a/standardv1.0/${VOLUME}/

# tank has 500 GENIE files, world has 4999. Submitting a RUN past the end costs a full queue slot
# before jobsub notices the -f source is missing, so check here instead.
[ -f "${GENIE}/gntp.${RUN}.ghep.root" ] \
  || { echo "no GENIE file ${GENIE}/gntp.${RUN}.ghep.root -- RUN out of range for VOLUME=${VOLUME}?" >&2; exit 1; }
[ -f "${DIRT}/annie_tank_flux.${RUN}.root" ] \
  || { echo "no dirt flux ${DIRT}/annie_tank_flux.${RUN}.root" >&2; exit 1; }

echo ""
echo "submitting job... (VOLUME=${VOLUME} RUN=${RUN} PRODUCTION=${PRODUCTION:-productionv2})"
echo ""

# Override the output subdir with PRODUCTION=... ; default unchanged.
OUTPUT_FOLDER="${PNFS_PERSISTENT}/output/genie_wcsim_${VOLUME}/${PRODUCTION:-productionv2}/"
mkdir -p $OUTPUT_FOLDER

# wrapper script to submit your grid job
jobsub_submit --memory=8000MB --expected-lifetime=24h -G annie --disk=10GB --blacklist=Omaha,Swan,Wisconsin,SU-ITS,RAL -f ${INPUT_PATH}/WCSim.tar.gz -f ${INPUT_PATH}/wcsim_container.sh -f ${DIRT}/annie_tank_flux.${RUN}.root -f ${GENIE}/gntp.${RUN}.ghep.root -d OUTPUT $OUTPUT_FOLDER file://${INPUT_PATH}/run_job.sh ${RUN}
