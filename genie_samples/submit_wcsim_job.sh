RUN=$1

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${REPO_ROOT}/config.sh"

# WORLD samples only run ~600 events per 20k GENIE file aka need low grid resources (recommended: 2GB mem, 4h walltime, 5GB disk)

export INPUT_PATH="${PNFS_SCRATCH}/WCSim_grid/genie_samples/"
export GENIE=/pnfs/annie/persistent/simulations/genie3/G1810a0211a/standardv1.0/world/
export DIRT=/pnfs/annie/persistent/simulations/g4dirt/G1810a0211a/standardv1.0/world/

echo ""
echo "submitting job..."
echo ""

OUTPUT_FOLDER="${PNFS_PERSISTENT}/output/genie_wcsim"
mkdir -p $OUTPUT_FOLDER                                                 

# wrapper script to submit your grid job
jobsub_submit --memory=2000MB --expected-lifetime=4h -G annie --disk=5GB --resource-provides=usage_model=OFFSITE --blacklist=Omaha,Swan,Wisconsin,SU-ITS,RAL -f ${INPUT_PATH}/WCSim.tar.gz -f ${INPUT_PATH}/wcsim_container.sh -f ${DIRT}/annie_tank_flux.${RUN}.root -f ${GENIE}/gntp.${RUN}.ghep.root -d OUTPUT $OUTPUT_FOLDER file://${INPUT_PATH}/run_job.sh ${RUN}
