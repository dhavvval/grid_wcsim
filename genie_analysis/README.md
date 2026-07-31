# genie_analysis — grid-parallel FMVMRD analysis

Runs the `CC_MC_RECO_ntuple_neutrino_FMVMRDTEST` toolchain over the deduped
dual-production WCSim set, one grid job per file number. The grid analog of
`EB_BC_TA/run_cc_neutrino_fmvmrd_batch.sh`.

Each `wcsim_<N>.root` -> `ANNIEEvent_cc_neutrino_<N>.root` is independent, so all
~370 files run in parallel instead of serially. Mirrors the WCSim grid scripts in
`../genie_samples/`.

## Selection (dedup) — same rule as the serial batch
- All productionv2 files in [0,499].
- testv2 files in [0,499] whose number is ABSENT from productionv2 (gap-fill).
- testv2 N >= 500 reuse an already-used GENIE input -> ignored.
Computed live from the directory listings by `send_analysis.py`.

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

3. **Submit** (prints the counts, asks for confirmation). The input set must be named
   explicitly — there is NO default, since the two sets write different filenames into
   different dirs and a forgotten flag would silently aim at the wrong dataset:
   ```
   python3 send_analysis.py -3            # productionv3, everything still missing
   python3 send_analysis.py -3 122 126    # restrict to N in [122,126] — test batch
   python3 send_analysis.py -2            # the v2 three-tier set -> gridtest/
   ```
   Careful with `-2`: its default action also resubmits every "upgradeable" number,
   overwriting ntuples already in `gridtest/`. Use `-2 --missing-only` to avoid that.

4. **Outputs** land in
   `$PNFS_PERSISTENT/output/genie_wcsim_tank/gridtest/`
   as `ANNIEEvent_cc_neutrino_<N>.root` (+ `analysis_log_<N>.txt` per job).

   NOTE: this is a SEPARATE dir from the local serial batch
   (`run_cc_neutrino_fmvmrd_batch.sh`), which writes to `productionv2/fmvmrd/`.
   Keeping them apart avoids grid-vs-local conflicts when both run at once.
   The grid job has NO "skip if output exists" logic, so if you re-submit an N
   whose `gridtest/ANNIEEvent_cc_neutrino_<N>.root` already exists, the new job's
   copy-back overwrites it.

## Files
- `tar_analysis.py`        — tar + stage the built ToolAnalysis (run once per build)
- `send_analysis.py`       — submit one job per N; both input sets, via `--production`
- `submit_analysis_job.sh` — jobsub_submit wrapper for a single (N, production)
- `run_analysis_job.sh`    — worker entry point (copies inputs, untars TA, launches container)
- `analysis_container.sh`  — runs inside toolanalysis:latest: patches configs, runs Analyse

## productionv3

`send_analysis.py -3` (or `--production productionv3`) is the grid analog of the serial
`EB_BC_TA_work/scripts/run_cc_neutrino_fmvmrd_v3_batch.sh` (tmux session `ccv3_fmvmrd`).

```
python3 send_analysis.py -3 122 126     # test batch FIRST
python3 send_analysis.py -3             # then the rest
```

- Inputs:  `productionv3/tank/wcsim_<N>.root` — note the extra `tank/` level, which
  productionv2 and testv2 do not have.
- Outputs: `productionv3/tank/fmvmrd/ANNIEEvent_cc_neutrino_v3_<N>.root` — the SAME dir
  and filenames the serial batch uses, so there is no merge step, and files the batch
  already produced are skipped automatically.
- Too-young inputs are deferred (`--min-age`, default 15 min), mirroring the serial
  script, since upstream WCSim grid jobs may still be uploading.

### ⚠ Never run the serial batch and these grid jobs at once

The batch checks "output already exists" at the START of each file's iteration, then
spends ~10 min in `Analyse` before a BARE `mv` onto pnfs (batch script line 176). pnfs
refuses to overwrite an existing file, and the batch runs under `set -euo pipefail` — so a
grid job landing that same N mid-`Analyse` makes the `mv` fail and aborts the WHOLE batch,
not just that file. `send_analysis.py -3` detects a running batch and refuses to submit
unless `--force` is passed. Stop the tmux session first.

Output filenames are controlled by a TAG threaded `submit_ -> run_ -> analysis_container.sh`.
`TAG=none` (what the productionv2 mode produces) keeps the original
`ANNIEEvent_cc_neutrino_<N>.root` names, so the v2 path is unchanged.

## Skip behaviour — where it lives

The **grid job does not skip**. `run_analysis_job.sh` always runs `Analyse` and `ifdh rm`s
the destination before copying back, so resubmitting an N overwrites its output. All
skip-if-done logic is in the SENDERS, evaluated at submit time.

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
