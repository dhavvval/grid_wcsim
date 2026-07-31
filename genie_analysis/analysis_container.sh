#!/bin/bash
# Runs INSIDE the toolanalysis:latest container on the worker node.
# Mirrors wcsim_container.sh. Patches the FMVMRDTEST configs for this file
# number, runs Analyse, leaves the output in /srv for run_analysis_job.sh to copy.

PART_NAME=$1            # file number N
TAG=${2:-none}          # output filename tag: "none" (v2 set) or e.g. "v3" (productionv3)

# Must match run_analysis_job.sh, which copies these names back to CONDOR_DIR_OUTPUT.
if [[ "${TAG}" == "none" || -z "${TAG}" ]]; then
  TAG_PREFIX=""
else
  TAG_PREFIX="${TAG}_"
fi

LOG=/srv/analysis_log_${TAG_PREFIX}${PART_NAME}.txt
touch ${LOG}

REPO=/srv/EB_BC_TA
# Toolchain config dir depends on the volume. Both run the same 17 tools with identical
# BackTracker/EventSelector/SimpleReconstruction/ANNIEEventTreeMaker settings, so the ntuples
# carry the same branches and cuts; they differ only in the GENIE set and how it is matched.
if [[ "${TAG}" == "world" ]]; then
  CFG=${REPO}/configfiles/CC_MC_RECO_ntuple_bt_world
else
  CFG=${REPO}/configfiles/CC_MC_RECO_ntuple_neutrino_FMVMRDTEST
fi
STAGE=${REPO}/wcsim_staging_cc_neutrino
mkdir -p "${STAGE}"

echo "pwd: $(pwd)"            >> ${LOG}
echo "PART_NAME=${PART_NAME}" >> ${LOG}
echo "TAG=${TAG}"             >> ${LOG}

cd "${REPO}"
source Setup.sh >> ${LOG} 2>&1
# CRITICAL — match the local batch script (run_cc_neutrino_fmvmrd_batch.sh line 25).
# Setup.sh appends the CONTAINER's WCSim lib (ToolDAQ/WCSimLib) to LD_LIBRARY_PATH, but that
# is a different build than the one that wrote our wcsim_*.root files. The local run prepends
# the user's OWN WCSim build dir so its libWCSimRoot wins; without this, the container's lib
# deserializes our WCSim objects incorrectly -> garbage ntuples. tar_analysis.py packs the
# 3 artifacts (libWCSimRoot.so, WCSimRootDict_rdict.pcm, libWCSimRoot.rootmap) here:
export LD_LIBRARY_PATH="${REPO}/grid_wcsimlib:${LD_LIBRARY_PATH:-}"
echo "WCSim lib dir prepended: ${REPO}/grid_wcsimlib" >> ${LOG}
ls -l "${REPO}/grid_wcsimlib" >> ${LOG} 2>&1

# --- stage the LoadWCSim-parseable symlink: wcsim_0.<N>.0.root -> /srv/wcsim_<N>.root ---
staged="${STAGE}/wcsim_0.${PART_NAME}.0.root"
ln -sf /srv/wcsim_${PART_NAME}.root "${staged}"

# --- patch configs for this file number ---
patch_config() {  # file key value
  local f="$1" k="$2" v="$3"
  if ! grep -qE "^[[:space:]]*${k}[[:space:]]" "${f}"; then
    echo "${k} ${v}" >> "${f}"
  else
    sed -i "s|^\([[:space:]]*${k}[[:space:]]\+\).*|\1${v}|" "${f}"
  fi
}
output_name="ANNIEEvent_cc_neutrino_${TAG_PREFIX}${PART_NAME}.root"
# Workers have no /pnfs mount, so point FileDir at /srv where run_analysis_job.sh ifdh-copied
# the gntp file. That applies to both volumes.
patch_config "${CFG}/LoadWCSimConfig"           "InputFile"      "${staged}"
patch_config "${CFG}/LoadGenieEventConfig"      "FileDir"        "/srv"
patch_config "${CFG}/ANNIEEventTreeMakerConfig" "OutputFile"     "${output_name}"

# FilePattern MUST NOT be patched for world: it stays "LoadWCSimTool" so LoadGenieEvent takes
# the GENIE entry per event from the CStore. Only ~3% of world events light the tank, so saved
# events sit at scattered entries (700/700 mismatched vs 0/5000 for tank) -- patching a
# gntp.<N> pattern would silently restore sequential matching and misalign every event.
if [[ "${TAG}" != "world" ]]; then
  patch_config "${CFG}/LoadGenieEventConfig"    "FilePattern"    "gntp.${PART_NAME}.ghep.root"
fi
echo "config dir: ${CFG}" >> ${LOG}
grep -E '^[[:space:]]*(FilePattern|FileDir|ManualFileMatching)' \
  "${CFG}/LoadGenieEventConfig" >> ${LOG} 2>&1

echo "running Analyse..." >> ${LOG}
./Analyse "${CFG}/ToolChainConfig" >> ${LOG} 2>&1
rc=$?
echo "Analyse exit code: ${rc}" >> ${LOG}

# --- move the output to /srv for extraction ---
if [[ -f "${REPO}/${output_name}" ]]; then
  cp "${REPO}/${output_name}" /srv/${output_name}
  echo "output produced: ${output_name}" >> ${LOG}
else
  echo "ERROR: ${output_name} not produced" >> ${LOG}
fi
### END ###
