# `raw_to_processed()` parallelization: findings

> **2026-08-17 fix, superseded below:** `managelidar::map_las()` used to
> silently clamp any requested `workers` to half of logical cores, no
> matter what was asked for, so the original single-machine sweep result
> that used to be here was an artifact of that clamp, not genuine scaling
> behavior. It's been replaced below with a fresh sweep across all 4
> machines, run after the fix.

Investigation of how to best parallelize `managelidar::raw_to_processed()`
(converts raw ALS LAZ/LAS tiles into quality-controlled, standardized point
clouds: CRS fix, reclassification, noise/ground classification, intensity
normalization, spatial indexing, overview image, VPC metadata, JSON log).
It needs to run over **thousands of files**, so wall-clock throughput
matters a lot. Benchmark script: `benchmarks/workers_raw-to-processed.R`.

## Two parallelization axes that exist

1. **mirai (used today)** — `raw_to_processed(..., workers = N)` spawns `N`
   separate R processes (via `mirai::mirai_map()`, see `managelidar::map_las()`),
   each pulling the next file from a shared queue and running the *entire*
   per-file pipeline independently. Default heuristic (when `workers = NULL`):
   half of `parallel::detectCores(logical = TRUE)`, but *only* kicks in
   automatically when 20+ files are detected — otherwise runs sequentially.
   The "half of cores" choice is explicitly about leaving memory headroom
   too (every worker holds a full point cloud in memory), not just CPU
   contention.
2. **lasR's own internal OpenMP threading (deliberately unused)** — every
   `lasR::exec()` call inside `raw_to_processed_per_file()` is hardcoded to
   `with = list(progress = FALSE, ncores = 1)`, i.e. fully sequential C++
   execution. lasR supports richer strategies via `lasR::concurrent_points(n)`,
   `concurrent_files(n)`, `nested(n, n2)` (see `?lasR::multithreading`).
   **Architectural note:** the code calls `lasR::exec()` on an
   already-loaded, single in-memory point cloud, not on a batch of file
   paths — so `concurrent_files()` does not apply to this usage pattern at
   all. Only `concurrent_points()` (multithreads point-level operations
   *within* one already-loaded file) is relevant here.

## Settled: internal lasR threading is NOT worth adding

Tested on a 12-core/32GB dev machine (Windows) against real ALS tiles (the
package's bundled toy sample data is too small/sparse for meaningful
timing or even reliable classification).

**Step 1 — where does time actually go?** Profiled a single 148MB/33.7M-point
file (`Rprof`, `workers=1`). ~96% of measured time was inside
`lasR::exec()`/`lasR::read_cloud()` (lasR's C++ code); R-level overhead
(GDAL raster stats/translate/webp conversion, VPC/JSON writing) was only a
few seconds out of ~89s measured. This means lasR-level threading *in
principle* targets the actual dominant cost — worth testing seriously.

**Step 2 — grid search, 3-4 real files (~4MB-880MB), varying `workers` and
lasR `ncores`:**

| config | seconds | notes |
|---|---|---|
| workers=1, ncores=1 (sequential baseline) | 298.7 | |
| workers=1, ncores=11 (all lasR threading, no mirai) | 261.1 | only 1.14x — weak |
| workers=3, ncores=1 (mirai only, one worker per file) | 161.7 | 1.85x — strong |
| workers=3, ncores=2 (hybrid, 6 cores total) | 149.0 | |
| workers=3, ncores=4 (hybrid, 12 cores total) | 148.8 | **identical to ncores=2** — saturates fast |

**Step 3 — decisive test: fixed total core budget (12), threading vs. more
workers**, on the full 8-file/1.9GB set:

| config (12 cores total either way) | seconds |
|---|---|
| workers=6, ncores=1 (today's literal default heuristic) | 372.6 |
| workers=6, ncores=2 (hybrid) | 364.8 |
| **workers=12, ncores=1 (all cores as file-concurrency, zero threading)** | **359.5 — fastest** |

**Conclusion:** at a fixed core budget, spending cores on *more concurrent
files* beats spending them on *per-file internal threading*. Not all lasR
pipeline stages are internally parallelizable, so a core reserved for
threading is wasted more often than a core given to an independent
additional file-worker. A tentative `ncores = concurrent_points(2)` default
was implemented, benchmarked, and then reverted. **Do not re-attempt an
internal-threading default without new contradicting evidence.**

## Full-queue sweep, all 4 machines (post-fix)

`benchmarks/workers_raw-to-processed.R` run against the full 100-tile
sample corpus, sweeping `workers` at 50%/75%/100% of each machine's own
logical core count. Full numbers and per-machine caveats are in the
rendered report (`report/benchmark-report.qmd`'s Worker-Count Scaling
section); summary:

| machine | cores | 50% | 75% | 100% |
|---|---|---|---|---|
| LB-3D2026 | 16 | 15.2 s/file | 15.3 s/file | **12.7 s/file** |
| pc069 | 12 | 27.9 s/file | 23.5 s/file | **21.6 s/file** |
| PC166 | 6 | 51.4 s/file | 40.8 s/file | **34.3 s/file** |
| PC026 | 64 | 7.8 s/file (96/100 files) | 2.9 s/file (**only 13/100 files**) | 3.6 s/file (**only 16/100 files**) |

**On the three machines that completed all 100 files at every worker
count**, using 100% of cores is consistently faster than 50-75% — a
genuine, now-trustworthy improvement (12-33% faster at 100% vs. 50%).
`workers=NULL`'s default heuristic (half of cores) is measurably
conservative on all three.

**PC026 is the open question.** It only completed all 100 files at 50%
of cores; at 75% and 100% most files failed outright (13/100 and 16/100
completed). Its fast per-file times there are an artifact of that
failure — most of the corpus never finished — not a real speed
advantage, and should not be read as "PC026 is fastest." This looks like
a stability or resource-contention issue specific to very high
concurrency (48-64 concurrent R worker processes) on that machine, not
a RAM problem (256GB is ample headroom for this workload).

**2026-08-20 reproducibility check:** re-ran the same sweep on PC026 a
second time to rule out a one-off fluke:

| workers (% cores) | run 1 | run 2 |
|---|---|---|
| 32 (50%) | 90/100, 740s | 91/100, 745s |
| 48 (75%) | 20/100, 309s | 12/100, 292s |
| 64 (100%) | 28/100, 879s | 25/100, 367s |

Confirmed reproducible, not noise — 75%/100% reliably tank completion on
both runs. Also notable: even 50% no longer reliably completes all 100
files (90-91/100 now vs. 96/100 in the original run above), so "50% is
safe on PC026" should be treated as provisional, not settled. Wall-clock
at 100% varied a lot between runs (879s vs. 367s) for a similar
completion count, consistent with contention/retries rather than a clean
fast failure.

**Root cause still open.** `sweep_workers()` in
`benchmarks/workers_raw-to-processed.R` used to point `log_dir` at the
same directory it deleted via `on.exit(unlink(...))` right after each
call, and wrapped the whole call in `suppressWarnings()` — so every run
destroyed its own diagnostic evidence before anyone could read it. Fixed
2026-08-20: `log_dir` now lives in a separate, non-deleted temp path
(printed to the console per worker count) and warnings are no longer
suppressed. Next PC026 run should actually surface a failure mode —
check the per-file logs for a consistent pattern (e.g. GDAL/PROJ
contention, process-spawn limits, or antivirus interference under many
concurrent R processes on Windows) before recommending any worker count
above 50% of cores for that machine in production.

## Gotchas hit while benchmarking

1. **mirai workers load the *installed* package, not any `devtools::load_all()`
   in-memory dev version.** `map_las()` spawns daemons with
   `mirai::daemons(n, ..args = list(.expr = quote(library(managelidar))))` —
   a fresh `library()` load in each worker process. If you've been
   iterating via `devtools::load_all()` and then test with `workers > 1`,
   the workers silently run whatever's actually installed (possibly stale),
   not your current edits. Run `devtools::install(quiet = TRUE, upgrade = "never")`
   before any `workers > 1` benchmark if package source has changed since
   the last install.
2. **`options()` set in the main R process do not propagate to mirai's
   worker processes** (separate OS processes, not forks) — only
   environment variables (inherited at process-spawn time) or values
   captured directly in the closure passed to `mirai_map()` propagate
   correctly.
3. Long-running R benchmark commands should run in the background with
   generous timeouts and be checked back on — a single sequential-baseline
   run over ~300MB of real data took ~5 minutes; full grid searches over
   more configs can run well past 10 minutes.
