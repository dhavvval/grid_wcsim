import os
import re
import sys
import time
import glob
import subprocess

# Submit FMVMRD analysis grid jobs over the productionv3 WCSim set, one job per file number.
#
# The grid analog of EB_BC_TA_work/scripts/run_cc_neutrino_fmvmrd_v3_batch.sh (the serial
# batch in the `ccv3_fmvmrd` tmux session). Same toolchain, same per-file recipe, same
# output filenames — one grid job per file number instead of one after another.
#
#   - Inputs live one level DEEPER than productionv2 did: productionv3/tank/, not
#     productionv3/.
#   - Outputs -> productionv3/tank/fmvmrd/ANNIEEvent_cc_neutrino_v3_<N>.root, the SAME dir
#     and SAME filenames the serial batch uses, so there is no merge step and files the
#     batch already finished are skipped automatically.
#   - --min-age defers too-young inputs (upstream WCSim grid jobs may still be landing
#     files; a half-uploaded file would be analysed as a truncated tree).
#   - ⚠ Refuses to submit while the serial batch is RUNNING. Sharing the output dir with a
#     live batch can KILL it: the batch checks "output exists" at the start of each file,
#     then runs Analyse for ~10 min before a bare `mv` onto pnfs. pnfs refuses to overwrite
#     and the batch uses `set -euo pipefail`, so a grid job landing that N mid-Analyse
#     aborts the WHOLE batch. Override with --force.
#
# Output dir and filename tag are derived from the production name by
# submit_analysis_job.sh — this script only passes the name through.
#
# The productionv2 three-tier set (productionv2 / lmoralep collab / testv2 -> gridtest/) is
# NOT active. Its job-list logic is kept, commented out, in the block marked
# "PRODUCTIONV2 (INACTIVE)" below; `-2` exits with a pointer to it. That set is already
# complete, and keeping only one live path means a forgotten flag cannot aim a submission
# at the wrong dataset.
#
# Usage:
#   python3 send_analysis.py                   # tank: everything still missing
#   python3 send_analysis.py 122 126           # restrict to N in [122,126] — test batch
#   python3 send_analysis.py -w                # world volume instead of tank
#   python3 send_analysis.py -w 1 1            # single world test job
#   python3 send_analysis.py --all             # resubmit every N, ignoring existing output
#   python3 send_analysis.py --min-age 0       # do not defer freshly-written inputs
#   python3 send_analysis.py --force           # submit even if the serial batch is running

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from config import PNFS_PERSISTENT

OUT_BASE   = f'{PNFS_PERSISTENT}/output/genie_wcsim_tank'
GENIE_DIR  = '/pnfs/annie/persistent/simulations/genie3/G1810a0211a/standardv1.0/tank'
MAX_N      = 499          # N >= 500 would recycle an already-used GENIE input

WORLD_BASE = f'{PNFS_PERSISTENT}/output/genie_wcsim_world'
SERIAL_BATCH = 'run_cc_neutrino_fmvmrd_v3_batch.sh'
DEFAULT_MIN_AGE_MIN = 15   # matches the serial batch's own default

# Volume selection. Both run the same toolchain and produce the same branches; they differ in
# input dir, GENIE set, and output tag (all resolved by submit_analysis_job.sh from PRODSRC).
VOLUMES = {
    'tank':  {'prodsrc': 'productionv3',
              'in_dir':  f'{OUT_BASE}/productionv3/tank',
              'out_sub': 'fmvmrd',
              'prefix':  'ANNIEEvent_cc_neutrino_v3_'},
    'world': {'prodsrc': 'world',
              'in_dir':  f'{WORLD_BASE}/productionv3/world',
              'out_sub': 'fmvmrd',
              'prefix':  'ANNIEEvent_cc_neutrino_world_'},
}

# ── flags ─────────────────────────────────────────────────────────────────────
args = sys.argv[1:]
flag_all   = '--all'   in args
flag_force = '--force' in args

if '-2' in args or 'productionv2' in args:
    sys.exit('productionv2 mode is currently commented out — see the "PRODUCTIONV2 '
             '(INACTIVE)" block\nin this file to re-enable it. That set is already '
             'complete in gridtest/.')
if '-3' in args:
    args.remove('-3')          # accepted as a no-op; productionv3 is the tank default

# Volume: tank (default) or world. --world / -w selects the world-volume set.
volume = 'tank'
if '--world' in args:
    volume = 'world'; args.remove('--world')
if '-w' in args:
    volume = 'world'; args.remove('-w')
V = VOLUMES[volume]
PRODSRC = V['prodsrc']
IN_DIR  = V['in_dir']
OUT_DIR = f"{IN_DIR}/{V['out_sub']}"
OUT_PREFIX = V['prefix']

min_age_min = DEFAULT_MIN_AGE_MIN
if '--min-age' in args:
    i = args.index('--min-age')
    min_age_min = int(args[i + 1])
    del args[i:i + 2]

range_args = [a for a in args if not a.startswith('-')]


def dir_nums(d, pattern, max_n=MAX_N):
    """File numbers matching pattern in d, restricted to [0, max_n]."""
    nums = set()
    regex = re.compile(pattern.replace('*', r'(\d+)') + r'$')
    for p in glob.glob(os.path.join(d, pattern)):
        m = regex.match(os.path.basename(p))
        if m and int(m.group(1)) <= max_n:
            nums.add(int(m.group(1)))
    return nums


def serial_batch_pids():
    """PIDs of any running instance of the serial v3 batch script."""
    try:
        out = subprocess.run(['pgrep', '-af', SERIAL_BATCH],
                             capture_output=True, text=True).stdout
    except Exception:
        return []
    # Exclude false positives: our own pgrep, and any wrapper shell (e.g. an agent/CI
    # snapshot shell) that merely MENTIONS the script name rather than executing it.
    # Matching on the interpreter prefix is too fragile — the same invocation shows up
    # as both `bash <script>` and `/bin/bash <script>`.
    me = str(os.getpid())
    pids = []
    for line in out.splitlines():
        parts = line.split(None, 1)
        if len(parts) != 2:
            continue
        pid, cmd = parts
        if pid == me or 'pgrep' in cmd or 'shell-snapshots' in cmd or ' -c ' in cmd:
            continue
        pids.append(pid)
    return pids


# ── refuse to run alongside the serial batch (see header) ─────────────────────
# Only the tank output dir is shared with that batch; world has no serial producer.
running = serial_batch_pids() if volume == 'tank' else []
if running:
    print(f'\n*** WARNING: the serial batch appears to be RUNNING '
          f'(PID {", ".join(running)}) ***')
    print(f'    {SERIAL_BATCH}')
    print('    It writes the SAME filenames into the SAME dir this sender targets.')
    print('    pnfs refuses to overwrite, and the batch runs under `set -euo pipefail`,')
    print('    so a grid job landing an N the batch is mid-way through aborts the WHOLE')
    print('    batch.')
    print('\n    Stop it first:  tmux attach -t ccv3_fmvmrd   (Ctrl-C), or  kill '
          + ' '.join(running))
    if not flag_force:
        sys.exit('\nRefusing to submit. Re-run with --force to override.')
    print('\n[--force] Overriding — proceeding with the batch still running.')

# ── build the job list ────────────────────────────────────────────────────────
inputs = dir_nums(IN_DIR, 'wcsim_*.root')
# For tank this dir is shared with the serial batch, so its work is covered automatically.
done_nums = dir_nums(OUT_DIR, OUT_PREFIX + '*.root')

print(f'\n--- productionv3 {volume} inputs ---')
print(f'dir:                           {IN_DIR}')
print(f'wcsim_<N>.root in [0,{MAX_N}]: {len(inputs)}')
print(f'\n--- Existing outputs ({OUT_PREFIX}<N>.root) ---')
print(f'dir:                           {OUT_DIR}')
print(f'already done:                  {len(done_nums)}')

candidates = sorted(inputs if flag_all else (inputs - done_nums))
if flag_all:
    print(f'\n[--all] Ignoring existing outputs: {len(candidates)} candidates.')
else:
    print(f'\n[default] Missing output: {len(candidates)} candidates.')

# Drop candidates with no GENIE partner — submit_analysis_job.sh -f would fail on them.
genie = dir_nums(GENIE_DIR, 'gntp.*.ghep.root')
no_genie = [n for n in candidates if n not in genie]
if no_genie:
    print(f'\nWARNING: {len(no_genie)} input(s) have no gntp.<N>.ghep.root in')
    print(f'  {GENIE_DIR}')
    print(f'  skipping: {no_genie[:20]}{" ..." if len(no_genie) > 20 else ""}')
    candidates = [n for n in candidates if n in genie]

# Defer inputs still being written by the upstream WCSim grid jobs.
if min_age_min > 0:
    cutoff = time.time() - min_age_min * 60
    deferred, keep = [], []
    for n in candidates:
        try:
            if os.path.getmtime(os.path.join(IN_DIR, f'wcsim_{n}.root')) > cutoff:
                deferred.append(n)
            else:
                keep.append(n)
        except OSError:
            deferred.append(n)
    candidates = keep
    if deferred:
        print(f'\nDeferred {len(deferred)} input(s) modified in the last {min_age_min} '
              f'min (may still be uploading): {deferred[:20]}'
              f'{" ..." if len(deferred) > 20 else ""}')
        print('  Re-run this script later to pick them up.')

final = [(n, PRODSRC) for n in candidates]

# ── range restriction, confirm, submit ────────────────────────────────────────
if len(range_args) == 2:
    lo, hi = int(range_args[0]), int(range_args[1])
    final = [(n, s) for (n, s) in final if lo <= n <= hi]
    print(f'\n(restricted to N in [{lo},{hi}] -> {len(final)} jobs)')

print(f'\nTOTAL jobs to submit: {len(final)}')
print(f'Output dir:           {OUT_DIR}')

if not final:
    sys.exit('\nNothing to submit.')

print('\nREMINDER: the worker runs the binary inside the STAGED TARBALL, not your login-node')
print('build. If you rebuilt EB_BC_TA since the last submission, run tar_analysis.py first.')

ans = input(f'\nProceed with submission of {len(final)} job(s)? [y/N]: ').strip().lower()
if ans != 'y':
    sys.exit('aborted.')

print('\nSending job(s)...\n')
for (n, src) in final:
    print(f'\n########## N={n}  ({src}) ##########\n')
    os.system(f'sh submit_analysis_job.sh {n} {src}')

print('\nJobs sent\n')


# ─────────────────────────────────────────────────────────────────────────────
# PRODUCTIONV2 (INACTIVE)
# ─────────────────────────────────────────────────────────────────────────────
# The original three-tier productionv2 job-list logic, kept for reference. That set is
# already complete in gridtest/ (459 outputs), so nothing here runs. submit_analysis_job.sh
# still understands the "productionv2" / "collab" / "testv2" source names and still routes
# them to gridtest/ with untagged ANNIEEvent_cc_neutrino_<N>.root filenames, so re-enabling
# is just a matter of restoring this block and a way to select it.
#
# Source priority (highest to lowest) for each N in [0,499]:
#   1. productionv2  (yours,           any N in [0,499])
#   2. collab        (lmoralep's pnfs, N in [250,499])
#   3. testv2        (fallback,        any N in [0,499])
#
# CAUTION if you do revive it: the default action below submits not just missing numbers but
# every "upgradeable" one too — numbers whose output exists but for which a higher-priority
# source has since appeared. Those resubmissions OVERWRITE existing gridtest/ ntuples. The
# --missing-only flag existed to avoid exactly that.
#
# PROD_DIR   = f'{OUT_BASE}/productionv2'
# COLLAB_DIR = '/pnfs/annie/scratch/users/lmoralep/output/genie_wcsim'
# TEST_DIR   = f'{OUT_BASE}/testv2'
# V2_OUT_DIR = f'{OUT_BASE}/gridtest'
#
# flag_missing_only = '--missing-only' in args
#
# prod   = dir_nums(PROD_DIR,   'wcsim_*.root')
# collab = dir_nums(COLLAB_DIR, 'wcsim_*.root')
# test   = dir_nums(TEST_DIR,   'wcsim_*.root')
#
# # priority assignment: higher overwrites lower
# source = {}
# for n in sorted(test):   source[n] = 'testv2'
# for n in sorted(collab): source[n] = 'collab'
# for n in sorted(prod):   source[n] = 'productionv2'
#
# intended = [(n, source[n]) for n in sorted(source)]
# done_nums = dir_nums(V2_OUT_DIR, 'ANNIEEvent_cc_neutrino_*.root')
#
# print(f'\n--- Input files ---')
# print(f'productionv2 in [0,{MAX_N}]:  {len(prod)}')
# print(f'collab       in [0,{MAX_N}]:  {len(collab)}')
# print(f'testv2       in [0,{MAX_N}]:  {len(test)}')
# print(f'--- Source assignment after priority ---')
# print(f'Using productionv2:  {sum(1 for (_, s) in intended if s == "productionv2")}')
# print(f'Using collab:        {sum(1 for (_, s) in intended if s == "collab")}')
# print(f'Using testv2:        {sum(1 for (_, s) in intended if s == "testv2")}')
# print(f'TOTAL intended jobs: {len(intended)}')
# print(f'\n--- Existing outputs in gridtest/ ---')
# print(f'Already done:        {len(done_nums)}')
# missing = set(n for (n, _) in intended) - done_nums
# print(f'Missing (no output): {len(missing)}')
#
# # Inferred upgrade: if a higher-priority dir also has wcsim_N.root, the prior job may have
# # used a lower-priority source (no submission log is kept, so this is best-effort).
# upgradeable = {}
# for n in done_nums:
#     if n not in source:
#         continue
#     best = source[n]
#     if best == 'productionv2' and (n in test or n in collab):
#         upgradeable[n] = 'productionv2'
#     elif best == 'collab' and n in test:
#         upgradeable[n] = 'collab'
# print(f'Upgradeable (better source now available): {len(upgradeable)}')
#
# if flag_all:
#     final = intended
#     print(f'\n[--all] Resubmitting all {len(final)} jobs.')
# elif flag_missing_only:
#     final = [(n, source[n]) for n in sorted(missing)]
#     print(f'\n[--missing-only] Submitting {len(final)} jobs with no output.')
# else:
#     missing_jobs = [(n, source[n]) for n in sorted(missing)]
#     upgrade_jobs = [(n, src) for n, src in sorted(upgradeable.items())]
#     final = missing_jobs + upgrade_jobs
#     print(f'\n[default] {len(missing_jobs)} missing + {len(upgradeable)} upgradeable '
#           f'= {len(final)} jobs to submit.')
