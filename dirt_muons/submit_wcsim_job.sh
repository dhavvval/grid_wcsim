RUN=$1
BATCH=$2

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${REPO_ROOT}/config.sh"

export INPUT_PATH="${PNFS_SCRATCH}/WCSim_grid/dirt_muons/"

echo ""
echo "submitting job..."
echo ""

OUTPUT_FOLDER="${PNFS_PERSISTENT}/output/dirt_muons/${BATCH}"
mkdir -p $OUTPUT_FOLDER                                                 

# wrapper script to submit your grid job
jobsub_submit --memory=2000MB --expected-lifetime=6h -G annie --disk=3GB --resource-provides=usage_model=OFFSITE --blacklist=Omaha,Swan,Wisconsin,SU-ITS,RAL -f ${INPUT_PATH}/WCSim.tar.gz -f ${INPUT_PATH}/wcsim_container.sh -f ${INPUT_PATH}/submit/${RUN}/WCSim.mac -d OUTPUT $OUTPUT_FOLDER file://${INPUT_PATH}/run_job.sh ${RUN} ${BATCH}

