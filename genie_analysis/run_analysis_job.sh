#!/bin/bash
# Grid job entry point (runs on the worker node, OUTSIDE the container).
# Mirrors run_job.sh. Copies inputs, untars ToolAnalysis, launches the
# toolanalysis container which actually runs Analyse.

cat <<EOF
condor   dir: $CONDOR_DIR_INPUT
process   id: $PROCESS
output   dir: $CONDOR_DIR_OUTPUT
EOF

PART_NAME=$1            # file number N
TAG=${2:-none}          # output filename tag: "none" (v2 set) or e.g. "v3" (productionv3)

# "none" -> ANNIEEvent_cc_neutrino_<N>.root      (unchanged v2/collab/testv2 behaviour)
# "v3"   -> ANNIEEvent_cc_neutrino_v3_<N>.root   (matches the serial productionv3 batch)
if [[ "${TAG}" == "none" || -z "${TAG}" ]]; then
  TAG_PREFIX=""
else
  TAG_PREFIX="${TAG}_"
fi
OUTPUT_NAME="ANNIEEvent_cc_neutrino_${TAG_PREFIX}${PART_NAME}.root"

DUMMY_OUTPUT_FILE=${CONDOR_DIR_OUTPUT}/${JOBSUBJOBID}_dummy_output
touch ${DUMMY_OUTPUT_FILE}
echo "This dummy file belongs to analysis job ${PART_NAME}" >> ${DUMMY_OUTPUT_FILE}
start_time=$(date +%s)
echo "The job started at: $(date)" >> ${DUMMY_OUTPUT_FILE}

# --- stage inputs onto the worker (/srv) ---
${JSB_TMP}/ifdh.sh cp -D $CONDOR_DIR_INPUT/ToolAnalysis.tar.gz .
${JSB_TMP}/ifdh.sh cp -D $CONDOR_DIR_INPUT/analysis_container.sh .
${JSB_TMP}/ifdh.sh cp -D $CONDOR_DIR_INPUT/gntp.${PART_NAME}.ghep.root .
${JSB_TMP}/ifdh.sh cp -D $CONDOR_DIR_INPUT/wcsim_${PART_NAME}.root .

# --- unpack ToolAnalysis ---
tar -xzf ToolAnalysis.tar.gz
rm ToolAnalysis.tar.gz

echo "current dir: $(pwd)" >> ${DUMMY_OUTPUT_FILE}
ls -v >> ${DUMMY_OUTPUT_FILE}

# --- run inside the toolanalysis container ---
# Bind only /srv: the worker has no /pnfs or /cvmfs mounts (those only exist on login nodes).
# The gntp file was already ifdh-copied to /srv above, and analysis_container.sh sets
# FileDir=/srv so LoadGenieEvent reads it from there.
# NOTE: ifdh cp (line 22) does NOT preserve the executable bit, so /srv/analysis_container.sh
# arrives as rw-r--r--. Running it directly via singularity would exec() a non-executable file
# -> "FATAL: permission denied". Invoke it through bash so no exec bit is required.
singularity exec -B/srv:/srv \
  /cvmfs/singularity.opensciencegrid.org/anniesoft/toolanalysis:latest \
  bash /srv/analysis_container.sh ${PART_NAME} ${TAG} >> ${DUMMY_OUTPUT_FILE} 2>&1

# --- copy outputs back to CONDOR_DIR_OUTPUT ---
# pnfs does not allow overwriting existing files - remove them first if present.
echo "Moving output files to CONDOR OUTPUT..." >> ${DUMMY_OUTPUT_FILE}
${JSB_TMP}/ifdh.sh rm ${CONDOR_DIR_OUTPUT}/${OUTPUT_NAME}                                2>/dev/null || true
${JSB_TMP}/ifdh.sh rm ${CONDOR_DIR_OUTPUT}/analysis_log_${TAG_PREFIX}${PART_NAME}.txt    2>/dev/null || true
${JSB_TMP}/ifdh.sh cp -D /srv/${OUTPUT_NAME}                              $CONDOR_DIR_OUTPUT
${JSB_TMP}/ifdh.sh cp -D /srv/analysis_log_${TAG_PREFIX}${PART_NAME}.txt  $CONDOR_DIR_OUTPUT

echo "" >> ${DUMMY_OUTPUT_FILE}
echo "Output dir contents:" >> ${DUMMY_OUTPUT_FILE}
ls $CONDOR_DIR_OUTPUT >> ${DUMMY_OUTPUT_FILE}

# --- cleanup (worker is ephemeral, but be tidy) ---
rm -rf /srv/EB_BC_TA
rm -f /srv/*.root /srv/*.txt /srv/analysis_container.sh

end_time=$(date +%s)
echo "Job ended at: $(date)" >> ${DUMMY_OUTPUT_FILE}
echo "Script duration (s): $((end_time - start_time))" >> ${DUMMY_OUTPUT_FILE}
### END ###
