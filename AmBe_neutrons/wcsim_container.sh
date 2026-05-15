#!/bin/bash 
# James Minock 

# execute WCSim events on the grid

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

# Replace hardcoded RPATH (points to /exp/ which is not mounted in the container)
# with $ORIGIN so the loader finds libWCSimRoot.so next to the binary itself.
patchelf --set-rpath '$ORIGIN' WCSim >> /srv/logfile_${PART_NAME}.txt 2>&1

# Run the toolchain, and output verbose to log file (stderr captured too)
./WCSim WCSim.mac >> /srv/logfile_${PART_NAME}.txt 2>&1

# Abort the job loudly if WCSim produced no output, rather than silently
# falling through and copying a stale file.
if [ ! -f wcsim_0.root ]; then
    echo "ERROR: WCSim did not produce wcsim_0.root — aborting job" >> /srv/logfile_${PART_NAME}.txt
    exit 1
fi

echo "" >> /srv/logfile_${PART_NAME}.txt
echo "-----------------------------------------" >> /srv/logfile_${PART_NAME}.txt 
echo "Finished!" >> /srv/logfile_${PART_NAME}.txt 

# log files
echo "" >> /srv/logfile_${PART_NAME}.txt
echo "WCSim directory contents:" >> /srv/logfile_${PART_NAME}.txt
ls -lrth >> /srv/logfile_${PART_NAME}.txt
echo "" >> /srv/logfile_${PART_NAME}.txt

# copy any produced files to /srv for extraction
cp wcsim_0.root /srv/wcsim_${PART_NAME}.root 
cp wcsim_lappd_0.root /srv/wcsim_lappd_${PART_NAME}.root

# make sure any output files you want to keep are put in /srv or any subdirectory of /srv 

### END ###
