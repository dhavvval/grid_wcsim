# grid_wcsim

Scripts for submitting WCSim Monte Carlo simulation jobs to the Fermilab grid (HTCondor/jobsub). Covers the four ANNIE MC tuning workflows: AmBe calibration neutrons, Michel electrons from dirt muons, throughgoing muons from GENIE, and GENIE+flux file processing with ToolAnalysis toolchains.

---

## Quick start: what do I need to change?

**One place to edit before running anything:**

Open [`config.py`](config.py) and [`config.sh`](config.sh) at the repo root and set `GRIDUSER` to your Fermilab username. Every other path is derived from it automatically.

```python
GRIDUSER = "dajana"                              # ← your username here
EXP_BASE = f"/exp/annie/app/users/{GRIDUSER}"   # your app/experiment area
WCSIM_LOC = EXP_BASE                            # parent dir of your WCSim/ build
GRID_WCSIM_REPO = f"{EXP_BASE}/grid_wcsim"      # path to this repo on the login node
PNFS_SCRATCH  = f"/pnfs/annie/scratch/users/{GRIDUSER}"
PNFS_PERSISTENT = f"/pnfs/annie/persistent/users/{GRIDUSER}"
```

**Your WCSim build** must live at `${EXP_BASE}/WCSim/` (i.e. a subdirectory called `WCSim` directly under your app area). Scripts tarball it as `tar -C ${EXP_BASE} WCSim`.

**ToolAnalysis-based workflows** (the `*_toolchain` directories) also need `folder_name` set in their `tarball_create_script.py` to the name of your ToolAnalysis installation directory.

---

## Directory overview

### `AmBe_neutrons/`

Submits WCSim jobs simulating AmBe-like neutron sources at five calibration port positions (1–5) and five depths each (−100, −50, 0, +50, +100 cm), matching the 2024 ANNIE AmBe calibration campaign. No AmBe housing is currently simulated. The neutron energy spectrum is in `AmBe_spectrum.dat` (from RATPAC).

| Script | Role |
|--------|------|
| `send.py` | **Entry point.** Creates per-job `WCSim.mac` files, tarballs WCSim, stages to pnfs scratch, then calls `submit_wcsim_job.sh` for each job/label combination |
| `submit_wcsim_job.sh` | Wraps `jobsub_submit` — sets pnfs paths, output folder, and resources |
| `run_job.sh` | Runs on the grid worker: unpacks tarball, starts Singularity, runs WCSim |
| `wcsim_container.sh` | Runs inside Singularity: sources environment, executes `./WCSim`, copies `.root` files to `/srv/` |

**What to change:** Only `config.py`/`config.sh`. The output goes to the scratch area (`PNFS_SCRATCH/output/wcsim/AmBe/...`) — change `submit_wcsim_job.sh` line 13 if you want persistent instead.

**Key parameters in `send.py`:** `QE_tag`, `events_per_job`, `N_jobs`.

---

### `dirt_muons/`

Simulates Michel electrons by propagating their parent dirt muons through the detector. Dirt muons are those from the GENIE WORLD samples originating in soil that pass FMV + tank but miss the MRD. Simulating the parent captures the correct daughter vertex and energy distribution, but is inefficient (~0.5% yield a Michel candidate after selection cuts). Typical production: ~500k events → ~500k individual root files.

| Script | Role |
|--------|------|
| `send_Michels.py` | **Entry point.** Reads `dirt_muons_genie.txt`, randomly samples events, creates `.mac` files, tarballs WCSim, stages everything to pnfs scratch, then submits |
| `submit_wcsim_job.sh` | Wraps `jobsub_submit` |
| `run_job.sh` | Grid worker script |
| `wcsim_container.sh` | Singularity container script |
| `dirt_muons_genie.txt` | Vertex/direction/energy of GENIE WORLD dirt muons passing FMV+tank (missing MRD) |

**Output:** `PNFS_PERSISTENT/output/dirt_muons/<batch>/`

**Key parameters in `send_Michels.py`:** `job_label`, `events_per_job`, `N_jobs`.

#### `dirt_muons/MC_toolchain_dirt_muons/`

Runs a ToolAnalysis MC toolchain over the WCSim root files produced above, batched into grid jobs.

| Script | Role |
|--------|------|
| `main.py` | **Entry point.** Scans `wcsim_file_path` for root files and submits batched toolchain jobs |
| `submit_grid_job.sh` | Wraps `jobsub_submit` for toolchain jobs |
| `tarball_create_script.py` | Tarballs your ToolAnalysis installation — **set `folder_name`** to your TA directory |
| `grid_job.sh` | Grid worker script — **set `TA_folder`** to your ToolAnalysis directory name |
| `run_container_job.sh` | Runs inside Singularity: sets up TA environment, executes toolchain |

**Key parameters in `main.py`:** `wcsim_file_path` (set by config), `events_per_job`, `N_jobs`, `files_per_job`.

---

### `genie_muons/`

Simulates throughgoing muons that traverse the full detector (FMV + tank + MRD). These are selected from GENIE WORLD samples and are used for CC event tuning. More efficient than dirt muons + Michels.

| Script | Role |
|--------|------|
| `send.py` | **Entry point.** Reads `thru_genie_muons.txt`, creates per-job multi-event `.mac` files, stages WCSim tarball and `.mac` files to pnfs scratch via `ifdh`, then submits |
| `submit_wcsim_job.sh` | Wraps `jobsub_submit` |
| `run_job.sh` | Grid worker script |
| `wcsim_container.sh` | Singularity container script |
| `thru_genie_muons.txt` | 40k throughgoing muon events from GENIE WORLD samples (filtered by Johann Martyn) |

**Output:** `PNFS_PERSISTENT/output/genie_muons/<batch>/`

**Key parameters in `send.py`:** `job_label`, `events_per_job`, `N_jobs`.

---

### `genie_samples/`

Runs GENIE + flux file pairs through WCSim on the grid, producing one `.root` file per GENIE file. Optimised for WORLD samples (5k files total).

| Script | Role |
|--------|------|
| `tar_wcsim.py` | **Run first.** Tarballs WCSim and stages it + helper scripts to pnfs scratch via `ifdh` |
| `send.py` | **Entry point.** Prompts for a file number range and calls `submit_wcsim_job.sh` for each |
| `submit_wcsim_job.sh` | Wraps `jobsub_submit`; references the shared GENIE (`/pnfs/annie/persistent/simulations/genie3/...`) and DIRT (`/pnfs/annie/persistent/simulations/g4dirt/...`) paths |
| `run_job.sh` | Grid worker script |
| `wcsim_container.sh` | Singularity container script |

**Output:** `PNFS_PERSISTENT/output/genie_wcsim/`

**Workflow order:** `python3 tar_wcsim.py` → `python3 send.py`

---

### `MC_GENIE_toolchain/`

Runs an AnalysisToolchain on the grid over matched WCSim + GENIE file pairs (produced by `genie_samples/`). Used for mass MC production of ntuples.

| Script | Role |
|--------|------|
| `main.py` | **Entry point.** Scans `wcsim_file_path` for root files, pairs each with its GENIE file, submits jobs |
| `submit_grid_job.sh` | Wraps `jobsub_submit`; receives all paths as arguments from `main.py` — no hardcoded paths here |
| `tarball_create_script.py` | Tarballs your ToolAnalysis installation — **set `folder_name`** |
| `grid_job.sh` | Grid worker script — **set `TA_folder`** |
| `run_container_job.sh` | Runs inside Singularity |
| `config_GENIE.py` | Writes `LoadWCSimConfig` and `PhaseIITreeMakerConfig` for a given run number — executed on the grid |

**What to change in `main.py`:** `min_file`, `max_file` (partition the 5k jobs into manageable batches), and `N_WCSim_files`.

**Output:** `PNFS_PERSISTENT/output/MC_GENIE_toolchain/`

---

### `submit_MC_toolchain/`

Runs an AnalysisToolchain over batches of WCSim files produced by `genie_muons/` (throughgoing) or adaptable for other workflows. Automatically scans available root files and batches them.

| Script | Role |
|--------|------|
| `main.py` | **Entry point.** Scans `wcsim_file_path`, batches into `files_per_job` chunks, submits |
| `submit_grid_job.sh` | Wraps `jobsub_submit` |
| `tarball_create_script.py` | Tarballs your ToolAnalysis installation — **set `folder_name`** |
| `grid_job.sh` | Grid worker script — **set `TA_folder`** |
| `run_container_job.sh` | Runs inside Singularity |

**What to change in `main.py`:** `wcsim_file_path` (set by config pointing to genie_muons output), `files_per_job`.

**Output:** `PNFS_PERSISTENT/output/genie_muons/Trees/`

---

### `sourceme`

Environment setup script that must be **included inside the WCSim tarball** (at `WCSim/sourceme`). It configures ROOT, Geant4, GENIE, and related library paths so the `./WCSim` executable can run inside the Singularity container on grid workers.

---

## Config variables

Defined once in [`config.sh`](config.sh) (sourced by shell scripts) and [`config.py`](config.py) (imported by Python scripts):

| Variable | Description |
|----------|-------------|
| `GRIDUSER` | Your Fermilab grid username |
| `EXP_BASE` | Your app area: `/exp/annie/app/users/<user>` |
| `WCSIM_LOC` | Parent dir of your `WCSim/` build (same as `EXP_BASE` by default) |
| `GRID_WCSIM_REPO` | Path to this repo on the login node |
| `PNFS_SCRATCH` | pnfs scratch area — used for temporary job staging (WCSim tarballs, `.mac` files) |
| `PNFS_PERSISTENT` | pnfs persistent area — all job **output** goes here |

---

## Per-workflow checklist: things to change before running

| Workflow | Files to check | Things to set |
|----------|----------------|---------------|
| All | `config.py`, `config.sh` | `GRIDUSER` |
| AmBe_neutrons | `send.py` | `QE_tag`, `events_per_job`, `N_jobs` |
| dirt_muons | `send_Michels.py` | `job_label`, `events_per_job`, `N_jobs` |
| dirt_muons toolchain | `MC_toolchain_dirt_muons/tarball_create_script.py`, `grid_job.sh` | `folder_name` (your TA dir), `TA_folder` |
| genie_muons | `send.py` | `job_label`, `events_per_job`, `N_jobs` |
| genie_samples | `tar_wcsim.py` first | — |
| MC_GENIE_toolchain | `main.py`, `tarball_create_script.py`, `grid_job.sh` | `min_file`/`max_file`, `folder_name`, `TA_folder` |
| submit_MC_toolchain | `main.py`, `tarball_create_script.py`, `grid_job.sh` | `files_per_job`, `folder_name`, `TA_folder` |

---

## How a job flows through the grid

```
[login node]
  send.py / send_Michels.py
    → creates .mac file(s)
    → tarballs WCSim build
    → stages tarball + scripts to pnfs scratch via ifdh
    → calls submit_wcsim_job.sh (or submit_grid_job.sh)
        → jobsub_submit → HTCondor queue

[grid worker node]
  run_job.sh
    → copies WCSim.tar.gz + .mac from pnfs scratch
    → unpacks WCSim.tar.gz
    → runs:  singularity exec ... wcsim_container.sh

      [inside Singularity]
      wcsim_container.sh
        → source sourceme  (sets up ROOT/Geant4/GENIE environment)
        → ./WCSim WCSim.mac
        → cp wcsim_*.root → /srv/

    → ifdh cp /srv/wcsim_*.root → pnfs persistent output
    → cleanup
```
