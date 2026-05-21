import os,sys
import time

#WCSim_loc = '/pnfs/annie/persistent/users/dajana/'
WCSim_loc = '/exp/annie/app/users/dajana/'

QE_tag = 'QE_1.50'

# AmBe
job_labels = [
    'port1_z0'      + str(QE_tag),
    'port1_z50' + str(QE_tag),
    'port1_zminus50' + str(QE_tag),
    'port1_z100' + str(QE_tag),
    'port1_zminus100' + str(QE_tag),
    'port4_z0' + str(QE_tag),
    'port4_z50' + str(QE_tag),
    'port4_zminus50' + str(QE_tag),
    'port4_z100' + str(QE_tag),
    'port4_zminus100' + str(QE_tag),
    'port5_z0' + str(QE_tag),
    'port5_z50' + str(QE_tag),
    'port5_zminus50' + str(QE_tag),
    'port5_z100' + str(QE_tag),
    'port5_zminus100' + str(QE_tag),
    'port2_z0' + str(QE_tag),
    'port2_z50' + str(QE_tag),
    'port2_zminus50' + str(QE_tag),
    'port2_z100' + str(QE_tag),
    'port2_zminus100' + str(QE_tag),
    'port3_z0' + str(QE_tag),
    'port3_z50' + str(QE_tag),
    'port3_zminus50' + str(QE_tag),
    'port3_z100' + str(QE_tag),
    'port3_zminus100' + str(QE_tag)
]

####################
events_per_job = 1000
####################
N_jobs = 50
####################
total_events = int(N_jobs*events_per_job)

print('\nYou have chosen:\n')
print(' - ' + str(events_per_job) + ' events per job\n')
print(' - ' + str(N_jobs) + ' total jobs to be submitted\n')
print(' - ' + str(total_events) + ' total events across all jobs\n')
print('\nQE_tag: ' + str(QE_tag) + '\n')
time.sleep(3)

def create_macro(WCSim_loc, job_label, events_per_job):

    output_path = WCSim_loc + 'WCSim/build/WCSim.mac'

    os.system('rm -rf ' + output_path)
    f = open(output_path, 'w')

    preamble = """#!/bin/sh
# Sample setup macro with no visualization

/run/verbose 0
/tracking/verbose 0
/hits/verbose 0
/process/em/verbose 0
/process/had/cascade/verbose 0
/process/verbose 0
/process/setVerbose 0
/run/initialize
/vis/disable

# QE Stacking
/WCSim/PMTQEMethod      Multi_Tank_Types
/WCSim/LAPPDQEMethod    Multi_Tank_Types

#turn on or off the collection efficiency
/WCSim/PMTCollEff on

# command to choose save or not save the pi0 info
/WCSim/SavePi0 false

#grab the DAQ options (digitizer type, thresholds, timing windows, etc.)
/control/execute macros/annie_daq.mac

# Select which time window(s) to add dark noise to
/DarkRate/SetDetectorElement tank
/DarkRate/SetDarkMode 1
/DarkRate/SetDarkHigh 100000
/DarkRate/SetDarkLow 0
/DarkRate/SetDarkWindow 4000

/DarkRate/SetDetectorElement mrd
/DarkRate/SetDarkMode 1
/DarkRate/SetDarkHigh 100000
/DarkRate/SetDarkLow 0
/DarkRate/SetDarkWindow 4000

/DarkRate/SetDetectorElement facc
/DarkRate/SetDarkMode 1
/DarkRate/SetDarkHigh 100000
/DarkRate/SetDarkLow 0
/DarkRate/SetDarkWindow 4000

# set the random seed
/control/execute macros/setRandomParameters.mac

#####################################
## PRIMARY SOURCES - AmBe neutrons
#####################################

## AmBe sample
/mygen/generator gps
/gps/particle neutron

# offsets for the source position:
# xshift 0.0
# yshift 14.46469
# zshift -168.1

# AmBe source origin
"""

    f.write(preamble)

    # port 1 (x = 0, z = -75)
    if job_label == 'port1_z0' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 -14.46487518 93.1 cm\n'
    elif job_label == 'port1_z50' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 35.53512482 93.1 cm\n'
    elif job_label == 'port1_z100' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 85.53512482 93.1 cm\n'
    elif job_label == 'port1_zminus50' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 -64.46487518 93.1 cm\n'
    elif job_label == 'port1_zminus100' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 -114.46487518 93.1 cm\n'

    # port 4 (x = -75, z = 0)
    elif job_label == 'port4_z0' + str(QE_tag):
        source_pos = '/gps/pos/centre -75 -14.46487518 168.1 cm\n'
    elif job_label == 'port4_z50' + str(QE_tag):
        source_pos = '/gps/pos/centre -75 35.53512482 168.1 cm\n'
    elif job_label == 'port4_z100' + str(QE_tag):
        source_pos = '/gps/pos/centre -75 85.53512482 168.1 cm\n'
    elif job_label == 'port4_zminus50' + str(QE_tag):
        source_pos = '/gps/pos/centre -75 -64.46487518 168.1 cm\n'
    elif job_label == 'port4_zminus100' + str(QE_tag):
        source_pos = '/gps/pos/centre -75 -114.46487518 168.1 cm\n'

    # port 5 (x = 0, z = 0)
    elif job_label == 'port5_z0' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 -14.46487518 168.1 cm\n'
    elif job_label == 'port5_z50' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 35.53512482 168.1 cm\n'
    elif job_label == 'port5_z100' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 85.53512482 168.1 cm\n'
    elif job_label == 'port5_zminus50' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 -64.46487518 168.1 cm\n'
    elif job_label == 'port5_zminus100' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 -114.46487518 168.1 cm\n'

    # port 2 (x = 0, z = 75)
    elif job_label == 'port2_z0' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 -14.46487518 243.1 cm\n'
    elif job_label == 'port2_z50' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 35.53512482 243.1 cm\n'
    elif job_label == 'port2_z100' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 85.53512482 243.1 cm\n'
    elif job_label == 'port2_zminus50' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 -64.46487518 243.1 cm\n'
    elif job_label == 'port2_zminus100' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 -114.46487518 243.1 cm\n'

    # port 3 (x = 0, z = 102)
    elif job_label == 'port3_z0' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 -14.46487518 270.1 cm\n'
    elif job_label == 'port3_z50' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 35.53512482 270.1 cm\n'
    elif job_label == 'port3_z100' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 85.53512482 270.1 cm\n'
    elif job_label == 'port3_zminus50' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 -64.46487518 270.1 cm\n'
    elif job_label == 'port3_zminus100' + str(QE_tag):
        source_pos = '/gps/pos/centre 0 -114.46487518 270.1 cm\n'
    else:
        raise ValueError('Unknown job_label: ' + job_label)

    print('\n')
    print(job_label)
    print(source_pos)

    f.write('# ' + job_label + '\n')
    f.write(source_pos + '\n')

    ending = """/gps/ang/type iso
/gps/ene/type Arb
/gps/ene/emspec 1
/gps/hist/type energy
/gps/hist/file AmBe_spectrum.dat
/gps/hist/inter Lin

################################

/WCSimIO/RootFile wcsim

"""

    f.write(ending)
    f.write('/run/beamOn ' + str(events_per_job) + '\n')
    f.write('\n')
    f.write('exit\n')
    f.close()

    print('WCSim.mac written\n')
    return


def submit_batch(WCSim_loc, job_label, events_per_job):

    create_macro(WCSim_loc, job_label, events_per_job)

    print('WCSim.mac details:')
    print('------------------')
    os.system('cat ' + WCSim_loc + 'WCSim/build/WCSim.mac')
    print('\n')
    time.sleep(5)
    #'''
    # tar WCSim — write directly to pnfs staging area (grid workers cannot reach /exp/)
    pnfs_hold = '/pnfs/annie/scratch/users/dajana/WCSim_grid/AmBe_neutrons/hold/'
    print('\ntar-ing WCSim for grid submission...\n')
    os.system('mkdir -p ' + pnfs_hold + job_label)
    os.system('rm -rf ' + pnfs_hold + job_label + '/WCSim.tar.gz')
    os.system('tar -czvf WCSim.tar.gz -C ' + WCSim_loc + ' WCSim')
    os.system('mv WCSim.tar.gz ' + pnfs_hold + job_label + '/')
    time.sleep(1)
    #'''
    return


count = 0
for jl in job_labels:

    # uncomment for testing
    #if count > 1:
        #continue
    #count += 1

    submit_batch(WCSim_loc, jl, events_per_job)

    print('\nSending jobs for ' + jl + '...\n')
    for i in range(N_jobs):
        starting_event = i*events_per_job
        ending_event = (i+1)*events_per_job - 1
        print('\n########## ' + str(starting_event) + '_' + str(ending_event) + ' ###########\n')
        os.system('sh submit_wcsim_job.sh ' + str(starting_event) + '_' + str(ending_event) + ' ' + jl)

print('\nJobs sent\n')
