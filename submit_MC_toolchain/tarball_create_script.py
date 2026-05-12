import os, sys, time

# script to create tar-ball for grid submission scripts
# usage: python3 tarball_create_script.py

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..'))
from config import EXP_BASE

tarball_name = 'MyToolAnalysis_grid.tar.gz'
folder_path = EXP_BASE + '/'
folder_name = 'MC_waveform_sim/'   # adjust to your ToolAnalysis directory name

tar_command = 'tar -czvf ' + tarball_name + ' -C ' + folder_path + ' ' + folder_name

print('\nTar-ing folder (details below)')
print(' - tar-ball name: ' + tarball_name)
print(' - folder path:   ' + folder_path)
print(' - folder name:   ' + folder_name)
print('\n')
print('Full command: ' + tar_command)
print('\n')

time.sleep(3)

os.system(tar_command)

print('\ndone')
