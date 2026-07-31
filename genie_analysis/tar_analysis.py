import os
import sys

# Tar-ball the BUILT ToolAnalysis (EB_BC_TA) for the grid and stage to pnfs scratch.
# Run this ONCE after you have built Analyse against CC_MC_RECO_ntuple_neutrino_FMVMRDTEST
# (the binary + UserTools/configfiles/ToolDAQ libs all get packed).
#
# Mirrors tar_wcsim.py. Author: adapted from Steven Doran's WCSim grid scripts.

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import EXP_BASE, PNFS_SCRATCH

TA_PARENT = EXP_BASE            # parent of EB_BC_TA  (/exp/annie/app/users/<user>)
TA_DIRNAME = 'EB_BC_TA'         # the prebuilt ToolAnalysis working dir to pack
#
# Ship your prebuilt ToolAnalysis PLUS your own WCSim ROOT-I/O artifacts.
# Most dependencies resolve from the container (toolanalysis:latest) via Setup.sh and are
# NOT shipped:  EB_BC_TA/ToolDAQ -> /ToolAnalysis/ToolDAQ (ROOT, GENIE, boost, CLHEP, ...).
#
# EXCEPTION — libWCSimRoot. The container ships its OWN WCSim lib at ToolDAQ/WCSimLib, but
# it is a DIFFERENT build than the one that wrote our wcsim_*.root files. Loading the
# container's lib deserializes our WCSim objects incorrectly -> garbage ntuples. The local
# batch script (run_cc_neutrino_fmvmrd_batch.sh) avoids this by PREPENDING the user's own
# WCSim build dir to LD_LIBRARY_PATH so its libWCSimRoot.so wins. We replicate that on the
# grid: pack the 3 runtime artifacts (.so + ROOT dict .pcm + .rootmap) into the tarball under
# EB_BC_TA/grid_wcsimlib/, and analysis_container.sh prepends that dir to LD_LIBRARY_PATH
# after sourcing Setup.sh — exactly mirroring the local run.
WCSIM_LIB_DIR = os.path.join(EXP_BASE, 'WCSim', 'WCSim')  # local WCSim build (matches batch script line 25)
WCSIM_ARTIFACTS = ['libWCSimRoot.so', 'WCSimRootDict_rdict.pcm', 'libWCSimRoot.rootmap']
PACKED_WCSIMLIB = os.path.join(TA_PARENT, TA_DIRNAME, 'grid_wcsimlib')  # staged into the tree before tar-ing

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
INPUT_PATH = f'{PNFS_SCRATCH}/Analysis_grid/genie_analysis/'
LOCAL_TARBALL = os.path.join(BASE_DIR, 'ToolAnalysis.tar.gz')

print('\nSanity check: prebuilt Analyse binary present?')
analyse = os.path.join(TA_PARENT, TA_DIRNAME, 'Analyse')
if not os.path.isfile(analyse):
    sys.exit(f'  ERROR: {analyse} not found. Build it first:\n'
             f'    make CC_MC_RECO_ntuple_neutrino_FMVMRDTEST')
print(f'  found {analyse}')

# Stage the user's WCSim ROOT-I/O artifacts into EB_BC_TA/grid_wcsimlib/ so they ride in the
# tarball. analysis_container.sh prepends this dir to LD_LIBRARY_PATH (mirrors batch line 25),
# guaranteeing the SAME libWCSimRoot that wrote the .root files is the one Analyse loads.
print('\nSanity check: WCSim ROOT-I/O artifacts present?')
os.system('rm -rf ' + PACKED_WCSIMLIB)
os.makedirs(PACKED_WCSIMLIB, exist_ok=True)
for a in WCSIM_ARTIFACTS:
    src = os.path.join(WCSIM_LIB_DIR, a)
    if not os.path.isfile(src):
        sys.exit(f'  ERROR: {src} not found. Build WCSim first (the local batch script '
                 f'prepends this dir to LD_LIBRARY_PATH).')
    os.system(f'cp -p {src} {PACKED_WCSIMLIB}/')
    print(f'  packed {a}')

print('\ntar-ing ToolAnalysis for grid submission (large, be patient)...\n')
os.system('rm -rf ' + LOCAL_TARBALL)
# Exclude heavy/irrelevant stuff: prior outputs, logs, .git, staged symlinks, and ALL
# .root files (~920MB of test outputs bloat the tree, e.g. a 672MB AmBeWaveforms file
# plus many ANNIEEvent_MC_*). In GNU tar '*' matches '/', so 'EB_BC_TA/*.root' excludes
# .root at every depth — including 3 nested runtime-asset .root (LAPPDSim/
# pulsecharacteristics.root and configfiles/Classification/pdfs/*.root). The FMVMRDTEST
# toolchain does NOT load any of those, so dropping them is safe. If you later ship a
# toolchain that needs them (LAPPDSim, Classification), copy them onto the worker
# separately or relax this exclude.
# -h NOT used: we WANT EB_BC_TA/ToolDAQ to stay a symlink (resolves in-container).
EXCLUDES = ' '.join([
    "--exclude='EB_BC_TA/.git'",
    "--exclude='EB_BC_TA/logs_*'",
    "--exclude='EB_BC_TA/wcsim_staging_*'",
    "--exclude='EB_BC_TA/ProcessedData_*'",
    "--exclude='EB_BC_TA/TrigOverlap_*'",
    "--exclude='EB_BC_TA/*.root'",         # all .root (recursive: * matches /)
])
# Progress + speed:
#   --checkpoint / --checkpoint-action=echo  -> prints a live line every 1000 files,
#       so you can SEE it working instead of staring at a silent terminal.
#   --use-compress-program=pigz              -> parallel gzip (all cores); falls back
#       to plain gzip (-z) if pigz is missing. pigz output is a normal .gz.
import shutil
COMPRESS = '--use-compress-program=pigz' if shutil.which('pigz') else '-z'
PROGRESS = "--checkpoint=1000 --checkpoint-action=echo='  tar: %u files, %T total...'"
tar_cmd = f'tar {EXCLUDES} {PROGRESS} {COMPRESS} -cf {LOCAL_TARBALL} -C {TA_PARENT} {TA_DIRNAME}'
print('  running: ' + tar_cmd + '\n')
os.system(tar_cmd)

# Drop the temporary WCSim-lib staging dir now that it's inside the tarball.
os.system('rm -rf ' + PACKED_WCSIMLIB)

print('\nStaging to pnfs scratch...\n')
os.system('mkdir -p ' + INPUT_PATH)
# dCache/pnfs does NOT allow overwriting an existing file (plain cp/mv onto an existing
# path -> "Operation not permitted", and os.system does not surface that). Re-staging would
# then silently keep the STALE copy. Always rm the destination first, then copy.
def stage(src, dst):
    os.system('rm -f ' + dst)
    rc = os.system('cp ' + src + ' ' + dst)
    if rc != 0:
        sys.exit(f'  ERROR: failed to stage {dst} (rc={rc}).')
    print(f'  staged {os.path.basename(dst)}')

stage(LOCAL_TARBALL,                          INPUT_PATH + 'ToolAnalysis.tar.gz')
os.system('rm -f ' + LOCAL_TARBALL)           # cp (not mv) above so a stage failure leaves the local tarball intact
stage(BASE_DIR + '/analysis_container.sh',    INPUT_PATH + 'analysis_container.sh')
stage(BASE_DIR + '/run_analysis_job.sh',      INPUT_PATH + 'run_analysis_job.sh')

print('\ndone! Tarball + scripts staged to ' + INPUT_PATH + '\n')
