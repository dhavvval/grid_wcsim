#!/bin/bash 
# James Minock 

PART_NAME=$1

# logfile
touch /srv/logfile_${PART_NAME}.txt 
echo "pwd:" >> /srv/logfile_${PART_NAME}.txt
pwd >> /srv/logfile_${PART_NAME}.txt
echo "" >> /srv/logfile_${PART_NAME}.txt

echo "sourcing script:" >> /srv/logfile_${PART_NAME}.txt
echo "" >> /srv/logfile_${PART_NAME}.txt

# source setup script
source sourceme >> /srv/logfile_${PART_NAME}.txt
chmod +x WCSim
# add cwd so libWCSimRoot.so from the extracted tar is found (pnfs not mounted in container)
export LD_LIBRARY_PATH=$(pwd):$LD_LIBRARY_PATH

echo "" >> /srv/logfile_${PART_NAME}.txt

echo "running WCSim..." >> /srv/logfile_${PART_NAME}.txt

# Run the toolchain, and output verbose to log file (stderr captured too)
./WCSim WCSim.mac >> /srv/logfile_${PART_NAME}.txt 2>&1

echo "" >> /srv/logfile_${PART_NAME}.txt
echo "-----------------------------------------" >> /srv/logfile_${PART_NAME}.txt 
echo "Finished!" >> /srv/logfile_${PART_NAME}.txt 

# log files
echo "" >> /srv/logfile_${PART_NAME}.txt
echo "WCSim directory contents:" >> /srv/logfile_${PART_NAME}.txt
ls -lrth >> /srv/logfile_${PART_NAME}.txt
echo "" >> /srv/logfile_${PART_NAME}.txt

# WCSim creates one file per beamOn call (wcsim_${PART_NAME}_0.root, _1.root, ...).
# Merge them into a single file before staging.
\rm wcsim_*lappd*.root
hadd -f wcsim_${PART_NAME}.root wcsim_${PART_NAME}_*.root >> /srv/logfile_${PART_NAME}.txt 2>&1
\rm wcsim_${PART_NAME}_*.root

# copy any produced files to /srv for extraction
\cp wcsim_${PART_NAME}.root /srv/

# make sure any output files you want to keep are put in /srv or any subdirectory of /srv 

### END ###
