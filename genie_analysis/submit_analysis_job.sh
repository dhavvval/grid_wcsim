#!/bin/bash
# Submit ONE FMVMRD analysis grid job for file number N.
#   usage: sh submit_analysis_job.sh <N> <production>
#   where <production> is "productionv2" / "collab" / "testv2" (decided by
#   send_analysis.py's dedup) or "productionv3" (from send_analysis.py -3).
#
# Mirrors submit_wcsim_job.sh. One job: copies wcsim_N.root + gntp.N.ghep.root onto the
# worker, runs Analyse (FMVMRDTEST toolchain), copies ANNIEEvent_cc_neutrino_N.root back.
set -euo pipefail

RUN=$1            # file number N
PRODSRC=$2        # productionv2 | collab | testv2 | productionv3

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "${REPO_ROOT}/config.sh"

# Keep ALL jobsub working/cache state OFF /nashome (home quota is full). jobsub_lite
# writes its sandbox under $XDG_CACHE_HOME/jobsub_lite (defaults to ~/.cache -> /nashome).
# Redirect it to pnfs scratch so submission never touches the home dir.
export XDG_CACHE_HOME="${PNFS_SCRATCH}/Analysis_grid/.cache"
export TMPDIR="${PNFS_SCRATCH}/Analysis_grid/.tmp"
mkdir -p "${XDG_CACHE_HOME}" "${TMPDIR}"

# Staging area populated by tar_analysis.py
export INPUT_PATH="${PNFS_SCRATCH}/Analysis_grid/genie_analysis/"

# GENIE files (LoadGenieEvent still reads gntp.N for truth matching) — same dir both productions use
export GENIE=/pnfs/annie/persistent/simulations/genie3/G1810a0211a/standardv1.0/tank/

# The WCSim input for THIS number comes from whichever source send_analysis.py picked.
# NOTE productionv3 nests its files one level deeper (productionv3/tank/), unlike
# productionv2/testv2 which hold wcsim_*.root directly.
if [[ "${PRODSRC}" == "collab" ]]; then
  WCSIM_DIR="/pnfs/annie/scratch/users/lmoralep/output/genie_wcsim"
elif [[ "${PRODSRC}" == "productionv3" ]]; then
  WCSIM_DIR="${PNFS_PERSISTENT}/output/genie_wcsim_tank/productionv3/tank"
else
  WCSIM_DIR="${PNFS_PERSISTENT}/output/genie_wcsim_tank/${PRODSRC}"
fi
WCSIM_FILE="${WCSIM_DIR}/wcsim_${RUN}.root"

# Output dir + filename tag.
#   productionv2/collab/testv2 -> gridtest/ANNIEEvent_cc_neutrino_<N>.root      (TAG=none)
#   productionv3               -> productionv3/tank/fmvmrd/
#                                 ANNIEEvent_cc_neutrino_v3_<N>.root            (TAG=v3)
#
# v3 writes into the SAME dir as the serial batch (run_cc_neutrino_fmvmrd_v3_batch.sh), so
# there is no merge step — identical filenames, one home for the ntuples.
#
# ⚠ DO NOT run the serial batch and these grid jobs at the same time. The batch checks
# "output already exists" at the START of each file's iteration, then spends ~10 min in
# Analyse before a BARE `mv` onto pnfs (batch script line 176). pnfs refuses to overwrite an
# existing file, and the batch runs under `set -euo pipefail` — so a grid job landing that
# same N mid-Analyse makes the mv fail and aborts the WHOLE batch, not just that file.
# Stop the `ccv3_fmvmrd` tmux session before submitting.
if [[ "${PRODSRC}" == "productionv3" ]]; then
  OUTPUT_FOLDER="${PNFS_PERSISTENT}/output/genie_wcsim_tank/productionv3/tank/fmvmrd/"
  TAG="v3"
else
  OUTPUT_FOLDER="${PNFS_PERSISTENT}/output/genie_wcsim_tank/gridtest/"
  TAG="none"
fi
mkdir -p "$OUTPUT_FOLDER"

echo ""
echo "submitting analysis job: N=${RUN} src=${PRODSRC} tag=${TAG}"
echo "  wcsim:  ${WCSIM_FILE}"
echo "  output: ${OUTPUT_FOLDER}"
echo ""

# productionv2 ROOT is ~112MB and 4000 events ⇒ Analyse is the heavy step here.
# productionv3 is ~145MB/file. Measured wall time from the serial v3 batch's per-file logs:
# median ~10 min (min 1, max 12). 4h is ~20x headroom for a slow worker and queues far
# better than the original 12h request. Raise it again if jobs start hitting the limit.
jobsub_submit \
  --memory=4000MB \
  --expected-lifetime=4h \
  --disk=15GB \
  -G annie \
  --blacklist=Omaha,Swan,Wisconsin,SU-ITS,RAL \
  -f "${INPUT_PATH}/ToolAnalysis.tar.gz" \
  -f "${INPUT_PATH}/analysis_container.sh" \
  -f "${WCSIM_FILE}" \
  -f "${GENIE}/gntp.${RUN}.ghep.root" \
  -d OUTPUT "$OUTPUT_FOLDER" \
  file://"${INPUT_PATH}/run_analysis_job.sh" "${RUN}" "${TAG}"
