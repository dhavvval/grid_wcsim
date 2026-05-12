# MC toolchain production using WCSim + GENIE files on the grid
# Author: Steven Doran

import os, re, time, sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
from config import PNFS_SCRATCH, PNFS_PERSISTENT

#
#
#

'''@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@'''

''' Please modify the following to reflect your working directory '''

wcsim_file_path = f'{PNFS_PERSISTENT}/output/genie_wcsim/'     # generated wcsim root files from the grid
genie_file_path = '/pnfs/annie/persistent/simulations/genie3/G1810a0211a/standardv1.0/world/'    # GENIE samples (shared, do not change)

INPUT_PATH = f'{PNFS_SCRATCH}/WCSim_grid/MC_GENIE_toolchain/'    # input path for submission scripts
OUTPUT_FOLDER = f'{PNFS_PERSISTENT}/output/MC_GENIE_toolchain/'    # grid output

                        # how many WCSim and GENIE files do you expect to have
N_WCSim_files = 5000    # for WORLD samples, we expect ~5000 WCSim files for the 5000 GENIE files

min_file = 1000       # partition the jobs (will only submit jobs from min to max)
max_file = 1999


file_pattern = re.compile(r"wcsim_(\d+).root")   # Pattern to extract N from generated wcsim files (this will change for the tank-only samples)

# submission script command
submission_script = "sh submit_grid_job.sh"

'''@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@'''

#
#
#
#
#

os.system('chmod +x submit_grid_job.sh')   # allow script to be executable


# Efficiently scan the directory and cache valid filenames

valid_files = []; run_numbers = []; total_count = 0
with os.scandir(wcsim_file_path) as entries:
    count = 0
    for entry in entries:
        if entry.is_file() and entry.name.endswith(".root"):
            match = file_pattern.match(entry.name)
            if match:
                run_number = int((match.group(1)))
                total_count += 1
                if max_file >= run_number >= min_file:
                    full_path = os.path.join(wcsim_file_path, entry.name)
                    valid_files.append(full_path)
                    run_numbers.append(run_number)
                    count += 1

# sort the files + run numbers by N
sorted_pairs = sorted(zip(run_numbers, valid_files), key=lambda x: x[0])
run_numbers, valid_files = zip(*sorted_pairs)
run_numbers = list(run_numbers)
valid_files = list(valid_files)

print(valid_files[0:10])

print('\nTotal files available: ' + str(total_count) + '/' + str(N_WCSim_files) + ' (~' + str(660*total_count) + ' total world events)')
print('\nFor this batch: ' + str(min_file) + ':' + str(max_file) + ' (' + str(len(valid_files)) + ' files, ~' + str(660*len(valid_files)) + ' events)')
print('\nSubmitting jobs...\n')

# Batch into N jobs
for i in range(len(valid_files)):

    wcsim_file = valid_files[i]
    genie_file = genie_file_path + 'gntp.' + str(run_numbers[i]) + '.ghep.root'

    # Call submission script
    print(f"\n*************************************************\nSubmitting job for file {run_numbers[i]}")
    os.system(submission_script + ' ' + str(run_numbers[i]) + ' ' + INPUT_PATH + ' ' + OUTPUT_FOLDER + ' ' + wcsim_file + ' ' + genie_file)
    print('Submission script arguments:\n' + str(run_numbers[i]) + ' ' + INPUT_PATH + ' ' + OUTPUT_FOLDER + ' ' + wcsim_file + ' ' + genie_file)
    time.sleep(0.1)   # in case you screw up and need to kill the loop (Ctrl+C)


# finish up
print('\nAll jobs sent!\n')
print('Exiting...\n')
