import os
import sys

# Script to tar-ball WCSim directory for the grid and stage to pnfs scratch
# Run this once before submitting jobs with send.py

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import WCSIM_LOC, PNFS_SCRATCH

BASE_DIR = os.path.dirname(os.path.abspath(__file__))
INPUT_PATH = f'{PNFS_SCRATCH}/WCSim_grid/genie_samples/'
LOCAL_TARBALL = os.path.join(BASE_DIR, 'WCSim.tar.gz')

print('\ntar-ing WCSim for grid submission...\n')
os.system('rm -rf ' + LOCAL_TARBALL)
os.system('tar -czvf ' + LOCAL_TARBALL + ' -C ' + WCSIM_LOC + ' WCSim')

print('\nStaging to pnfs scratch...\n')
os.system('ifdh mkdir_p ' + INPUT_PATH)
os.system('ifdh cp ' + LOCAL_TARBALL + ' ' + INPUT_PATH + 'WCSim.tar.gz')
os.system('ifdh cp ' + BASE_DIR + '/wcsim_container.sh ' + INPUT_PATH + 'wcsim_container.sh')
os.system('ifdh cp ' + BASE_DIR + '/run_job.sh ' + INPUT_PATH + 'run_job.sh')

print('\ndone!\n')
