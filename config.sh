#!/bin/bash
# User-specific configuration for grid_wcsim scripts.
# Edit GRIDUSER to match your Fermilab username — all paths are derived from it.
# Shell scripts source this file at runtime instead of hardcoding paths.

GRIDUSER="dajana"

EXP_BASE="/exp/annie/app/users/${GRIDUSER}"
WCSIM_LOC="${EXP_BASE}"                       # parent dir of WCSim/ build (tar packs WCSim/ from here)
GRID_WCSIM_REPO="${EXP_BASE}/grid_wcsim"      # path to this repo on the login node

PNFS_SCRATCH="/pnfs/annie/scratch/users/${GRIDUSER}"
PNFS_PERSISTENT="/pnfs/annie/persistent/users/${GRIDUSER}"
