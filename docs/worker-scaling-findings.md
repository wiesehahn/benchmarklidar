# `raw_to_processed()` parallelization: findings

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

## First full-queue sweep result: "half of cores" confirmed conservative (on the 12-core dev machine)

`benchmarks/workers_raw-to-processed.R` run for real on PC069 (12 logical
cores, 32GB RAM) against the full 100-tile sample corpus (~4.5GB, a
reproducible random sample from Lower Saxony's 2016 statewide ALS
campaign — see `data-prep/fetch_sample_data.R`), sweeping `workers` from
half the logical core count up to 2x:

| workers | seconds | vs. workers=6 |
|---|---|---|
| 6 (today's literal default: half of cores) | 2972.5 | baseline |
| 9 (0.75x cores) | 2701.7 | -9.1% |
| 12 (1x cores) | 2654.4 | -10.7% |
| **18 (1.5x cores)** | **2600.7** | **-12.5% — fastest** |
| 24 (2x cores) | 2653.4 | -10.7% |

All 5 configs processed 100/100 files successfully — no failures at any
worker count. **This settles the question for this machine:** `workers=6`
(the current default heuristic) is measurably conservative — `workers=18`
(1.5x logical cores) is ~12.5% faster, with no sign of memory exhaustion
or I/O contention at any tested worker count. Returns diminish and
slightly reverse past 18 workers (24 is marginally slower than 18),
suggesting the plateau on *this* machine sits somewhere around 1.5-2x
logical cores, not at 1x or 0.5x.

**Still open:** this was tested only on the 12-core/32GB dev machine. The
production target — AMD Ryzen Threadripper PRO 5975WX, 32 cores / 64
threads (SMT), 256GB RAM — has a much larger core count and RAM headroom,
so it's not yet known whether the same ~1.5x-cores sweet spot holds there,
or whether I/O (especially reading from shared/network storage) or memory
pressure becomes the bottleneck earlier at that much higher concurrency.
Given the dev-machine result, raising the package's default heuristic
above "half of cores" looks justified in principle — but that's a
separate decision from this benchmarking pass, since it affects *all*
users of the package. Confirming the pattern holds on the Threadripper
(or finding where it breaks down there) should come before changing the
shipped default; a targeted `workers=` override is the safe interim
choice for production runs on that machine.

**Test data:** 100 real ALS tiles (~4.5GB total, ~20-90MB each) from
Lower Saxony's 2016 statewide campaign, fixed random sample (seed 42) via
`data-prep/fetch_sample_data.R`.

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

## Suggested next step

1. Confirm R + `managelidar` (with all deps: `lasR`, `gdalraster`, etc.) is
   installed on PC026 (the Threadripper).
2. Run `benchmarks/workers_raw-to-processed.R` there against the same
   100-tile sample corpus (`data-prep/fetch_sample_data.R`), watching
   memory usage alongside wall-clock time. Consider widening
   `worker_counts` beyond the default half/0.75x/1x/1.5x/2x-cores range —
   at 64 logical cores, 2x is 128 workers, which may need a larger file
   set than 100 to keep the queue non-empty throughout (see the dev-machine
   sizing rationale in `data-prep/fetch_sample_data.R`).
3. Look for the plateau/regression point in the timing curve. If it sits
   meaningfully above 0.5x cores (as it did on the dev machine, at ~1.5x),
   raising the package's default heuristic looks justified — but that's a
   separate decision from this benchmarking pass, since it affects *all*
   users of the package, not just this high-core-count production use
   case; a targeted `workers=` override for this specific production run
   is safer than changing the shipped default without broader validation.
