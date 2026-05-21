RUN=$1
BATCH=$2

QE_tag="QE_1.50"

export SCRIPT_PATH=/exp/annie/app/users/dajana/grid_wcsim/AmBe_neutrons/
export INPUT_PATH=/pnfs/annie/scratch/users/dajana/WCSim_grid/AmBe_neutrons/

echo ""
echo "submitting job..."
echo ""

OUTPUT_FOLDER=/pnfs/annie/persistent/users/dajana/AmBe_Neutron_ExpSpecturm_WCSim/productionv1/${QE_tag}/${BATCH}/
mkdir -p $OUTPUT_FOLDER                                                 

# default grid resources:
# - 2 GB memory
# - 6 hr lifetime
# - 10 GB disk

# wrapper script to submit your grid job
jobsub_submit --memory=2000MB --expected-lifetime=2h -G annie --disk=2GB --resource-provides=usage_model=OFFSITE --blacklist=Omaha,Swan,Wisconsin,SU-ITS,RAL -f ${INPUT_PATH}/hold/${BATCH}/WCSim.tar.gz -f ${INPUT_PATH}/wcsim_container.sh -d OUTPUT $OUTPUT_FOLDER file://${SCRIPT_PATH}/run_job.sh ${RUN} ${BATCH}

