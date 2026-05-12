import os
import sys

# -- Submit WCSim jobs that run over the GENIE + flux files
# -- Returns wcsim.root files created from GENIE samples
# -- Author: Steven Doran
# -- July 2025

# There are a total of 5k GENIE + flux files for the WORLD events

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import PNFS_SCRATCH

INPUT_PATH = f'{PNFS_SCRATCH}/WCSim_grid/genie_samples/'  # staging area; set by tar_wcsim.py

print('\nPlease specify the range of genie files you would like to loop over')
min_g = input('\nmin genie file #:    ')    #          (min = 0)
max_g = input('\nmax genie file #:    ')    # 5k total (max = 4999)

files = []
for i in range(int(min_g), int(max_g)+1):
	files.append(i)

print('\nTotal number of jobs = ' + str(len(files)))

print('\nSending job(s)...\n')
for i in range(len(files)):
	print('\n########## ' + str(files[i]) + ' ###########\n')
	os.system('sh submit_wcsim_job.sh ' + str(files[i]))


print('\nJobs sent\n')
