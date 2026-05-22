import os
import sys

# -- Submit WCSim jobs that runs over the default wcsim macro.
# -- Returns wcsim.root files created from Default WCSim Macro, which are then used to create the electron swarm files
# -- Author: Steven Doran
# -- July 2025


sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import PNFS_SCRATCH

INPUT_PATH = f'{PNFS_SCRATCH}/WCSim_electron_swarm/'  # staging area; set by tar_wcsim.py

print('\nPlease specify the range of wcsim electron swarm files you would like to loop over')
min_w = input('\nmin wcsim file #:    ')    #          (min = 0)
max_w = input('\nmax wcsim file #:    ')    # 5k total (max = 4999)

files = []
for i in range(int(min_w), int(max_w)+1):
	files.append(i)

print('\nTotal number of jobs = ' + str(len(files)))

print('\nSending job(s)...\n')
for i in range(len(files)):
	print('\n########## ' + str(files[i]) + ' ###########\n')
	os.system('sh submit_wcsim_job.sh ' + str(files[i]))


print('\nJobs sent\n')
