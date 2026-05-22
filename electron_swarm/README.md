# electron_swarm

Submitting WCSim grid jobs to generate an isotropic Michel electron swarm within the ANNIE tank. Each job simulates electrons drawn from a Michel electron energy spectrum using the Geant4 GPS source, with a unique random seed per job.

## Overview

- This is a pure GPS simulation.
- Each job produces one `wcsim_*.root` output file.
- The energy spectrum is a Michel electron spectrum (0–52.8 MeV), with linear interpolation between histogram points.

## Files

| File | Description |
|------|-------------|
| `tar_wcsim.py` | Tar-balls the WCSim directory and stages it (+ scripts) to pnfs scratch. Run once before submitting jobs. |
| `send.py` | Loops over a range of job indices and calls `submit_wcsim_job.sh` for each. |
| `submit_wcsim_job.sh` | Calls `jobsub_submit` with the appropriate resources and input files. |
| `run_job.sh` | Wrapper script that runs on the grid node: unpacks the tarball, sets a random seed, and launches the Singularity container. |
| `wcsim_container.sh` | Runs inside the Singularity container: sources the WCSim environment and runs `./WCSim WCSim.mac`. |

## Usage

Set up `WCSim.mac` with the electron swarm GPS block:

```
/mygen/generator laser
/gps/particle e-
/gps/pos/type Volume
/gps/pos/shape Cylinder
/gps/pos/radius 1.5 m
/gps/pos/halfz 1.95 m
/gps/pos/rot1 1 0 0
/gps/pos/rot2 0 0 1
/gps/pos/centre 0 -14.46 168.1 cm
/gps/ang/type iso
/gps/ene/type Arb
/gps/ene/min 0 MeV
/gps/ene/max 52.8 MeV
/gps/hist/type arb
/gps/hist/point 0    0.000
/gps/hist/point 5    0.023
/gps/hist/point 10   0.083
/gps/hist/point 15   0.164
/gps/hist/point 20   0.256
/gps/hist/point 25   0.352
/gps/hist/point 30   0.444
/gps/hist/point 35   0.527
/gps/hist/point 40   0.592
/gps/hist/point 45   0.626
/gps/hist/point 50   0.608
/gps/hist/point 52.8 0.500
/gps/hist/inter Lin
```


