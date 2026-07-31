# genie_analysis — grid-parallel FMVMRD analysis

Runs the `CC_MC_RECO_ntuple_neutrino_FMVMRDTEST` toolchain over the **productionv3**
WCSim set, one grid job per file number. The grid analog of
`EB_BC_TA_work/scripts/run_cc_neutrino_fmvmrd_v3_batch.sh` (the serial batch in the
`ccv3_fmvmrd` tmux session).

Each `wcsim_<N>.root` -> `ANNIEEvent_cc_neutrino_v3_<N>.root` is independent, so the
files run in parallel instead of one after another — the serial batch measured ~10 min
each, i.e. ~63 h for the ~380 remaining. Mirrors the WCSim grid scripts in
`../genie_samples/`.

## Selection
- `productionv3/tank/wcsim_<N>.root`, N in [0,499]. Note the extra `tank/` level —
  productionv2 and testv2 held their files one dir higher.
- N >= 500 would recycle an already-used GENIE input -> ignored.
- Numbers already present in the output dir are skipped, whichever producer made them.

The older **productionv2** three-tier set (productionv2 / lmoralep collab / testv2 ->
`gridtest/`) is **inactive**: it is already complete, and its job-list logic sits
commented out in the `PRODUCTIONV2 (INACTIVE)` block at the bottom of
`send_analysis.py`. Passing `-2` exits with a pointer to it. `submit_analysis_job.sh`
still understands those source names, so reviving it is a matter of restoring that block.

## Workflow

1. **Build Analyse yourself** against the FMVMRDTEST toolchain (with your patches):
   ```
   cd /exp/annie/app/users/dajana/EB_BC_TA
   <singularity> bash -c "source Setup.sh && make CC_MC_RECO_ntuple_neutrino_FMVMRDTEST"
   ```

2. **Tar + stage ToolAnalysis** (once per build — re-run whenever you rebuild):
   ```
   cd /exp/annie/app/users/dajana/grid_wcsim/genie_analysis
   python3 tar_analysis.py
   ```
   Packs the built `EB_BC_TA` tree (binary + UserTools + configfiles + ToolDAQ libs)
   to `$PNFS_SCRATCH/Analysis_grid/genie_analysis/ToolAnalysis.tar.gz` and copies the
   worker scripts alongside it.

3. **Submit** (prints the counts, asks for confirmation):
   ```
   python3 send_analysis.py            # everything still missing
   python3 send_analysis.py 122 126    # restrict to N in [122,126] — test batch
   ```
   Pick a test range that is actually missing: low numbers like `0 4` are already done
   and would yield zero jobs.

4. **Outputs** land in
   `$PNFS_PERSISTENT/output/genie_wcsim_tank/productionv3/tank/fmvmrd/`
   as `ANNIEEvent_cc_neutrino_v3_<N>.root` (+ `analysis_log_v3_<N>.txt` per job).

   This is the SAME dir and the SAME filenames the serial batch uses, so nothing needs
   merging afterwards — but see the warning below about running both at once.

   Too-young inputs are deferred (`--min-age`, default 15 min), mirroring the serial
   script, since upstream WCSim grid jobs may still be uploading. Re-run the sender at
   the end to sweep up latecomers.

## Files
- `tar_analysis.py`        — tar + stage the built ToolAnalysis (run once per build)
- `send_analysis.py`       — pick the missing file numbers, submit one job per N
- `submit_analysis_job.sh` — jobsub_submit wrapper for a single (N, production)
- `run_analysis_job.sh`    — worker entry point (copies inputs, untars TA, launches container)
- `analysis_container.sh`  — runs inside toolanalysis:latest: patches configs, runs Analyse

## ⚠ Never run the serial batch and these grid jobs at once

The batch checks "output already exists" at the START of each file's iteration, then
spends ~10 min in `Analyse` before a BARE `mv` onto pnfs (batch script line 176). pnfs
refuses to overwrite an existing file, and the batch runs under `set -euo pipefail` — so a
grid job landing that same N mid-`Analyse` makes the `mv` fail and aborts the WHOLE batch,
not just that file. `send_analysis.py` detects a running batch and refuses to submit
unless `--force` is passed. Stop the tmux session first.

Output filenames come from a TAG threaded `submit_ -> run_ -> analysis_container.sh`.
`productionv3` sets `TAG=v3`; the inactive v2 path used `TAG=none`, which keeps the
untagged `ANNIEEvent_cc_neutrino_<N>.root` names.

## Skip behaviour — where it lives

The **grid job does not skip**. `run_analysis_job.sh` always runs `Analyse` and `ifdh rm`s
the destination before copying back, so resubmitting an N overwrites its output. All
skip-if-done logic is in `send_analysis.py`, evaluated once at submit time — so if the
serial batch is somehow still running, numbers it finishes after submission get redone.

## Wall time

Measured from the serial productionv3 batch's per-file logs: median ~10 min/file
(~145MB, 4000 events). `submit_analysis_job.sh` requests `--expected-lifetime=4h`
(was 12h) — ~20x headroom, and it queues considerably better.

## Why no `make` on the grid (matches your "build once, then process" workflow)
The job runs your PREBUILT `Analyse` — it never compiles, and ships nothing but your
ToolAnalysis tree. Two dependencies resolve from the container itself, so they are NOT
shipped:

1. **`EB_BC_TA/ToolDAQ` -> `/ToolAnalysis/ToolDAQ`** — a symlink to an absolute path
   baked into `toolanalysis:latest` (ROOT, GENIE, boost, CLHEP, Pythia6, ...). The job
   runs in the SAME image, so the symlink resolves identically on the worker.
2. **`libWCSimRoot.so` — CORRECTION, this one IS shipped.** An earlier version of this
   README claimed the container's `ToolDAQ/WCSimLib/` copy was fine. It is NOT: it is a
   DIFFERENT build than the one that wrote our `wcsim_*.root` files, so it deserializes
   our WCSim objects incorrectly and yields garbage ntuples (silently — no error, just
   wrong/untraced ancestry). `tar_analysis.py` packs the 3 runtime artifacts
   (`libWCSimRoot.so`, `WCSimRootDict_rdict.pcm`, `libWCSimRoot.rootmap`) from the
   local WCSim build into `EB_BC_TA/grid_wcsimlib/`, and `analysis_container.sh`
   PREPENDS that dir to `LD_LIBRARY_PATH` after `source Setup.sh` — mirroring
   line 34 of the local batch script. Do not remove either half of that.

So the flow is: build ToolAnalysis ONCE on the login node (your usual tmux recipe),
`tar_analysis.py` captures it, every job runs straight through.

- **If you hit missing-`.so` errors on the worker:** run one job, read
  `analysis_log_<N>.txt`. Re-tar after any rebuild — the worker runs the tarball's
  binary, not your login-node build.
- **Test small first:** submit a 5-number range, confirm the outputs come back and a log
  looks clean, THEN submit the full set. Pick numbers that are actually missing — e.g. for
  productionv3, `0 4` is already done and would yield zero jobs.
- **Wall time / disk:** ~112MB (v2) to ~145MB (v3) per file, 4000 events; jobs request
  4h and 15GB disk. Tune in `submit_analysis_job.sh` if real timings drift.
- **Re-tar after every rebuild** — the worker runs whatever binary is in the tarball,
  not your login-node build.
