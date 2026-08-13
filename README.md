# lidar-benchmark

Evidence base for ALS (airborne laser scanning) tooling and parallelization
decisions before processing **terabytes** of production point-cloud data.
Every script here measures wall-clock processing time under a specific,
controlled comparison, and every result is saved with the system/package
versions that produced it so numbers stay traceable and comparable over
time and across machines.

## What's benchmarked

- **Tool comparison** (`benchmarks/tools_comparison.R`) — lidR vs lasR vs
  PDAL vs LAStools for read+write, COPC conversion, normals, ground
  classification.
- **lasR internal pipeline stages** (`benchmarks/lasr_stages.R`) — read,
  write (LAS/LAZ/COPC), triangulate, rasterize, DTM/DSM, normalize, ground/
  noise classifiers, etc.
- **lidR vs lasR, ground + intensity pipeline** (`benchmarks/lidr-lasr_ground-intensity.R`).
- **Local vs. network drive I/O** (`benchmarks/drives_local-vs-network.R`).
- **Parallelization strategies** (`benchmarks/parallel_strategies.R`) —
  lasR's own internal file-concurrency threading vs. `future.apply` vs.
  `mirai`.
- **`managelidar::raw_to_processed()` worker scaling**
  (`benchmarks/workers_raw-to-processed.R`) — the most direct evidence
  toward the terabyte-scale question: how throughput scales with `workers`
  on real hardware. See [`docs/worker-scaling-findings.md`](docs/worker-scaling-findings.md)
  for the investigation so far.

## Repo layout

```
lidar-benchmark/
├── _setup.R                # bootstrap: source this first in any benchmarks/*.R script
├── R/                       # reusable helpers (harness, tool config, staging, reporting)
├── data-prep/                # one-off scripts to acquire sample data from network shares
├── benchmarks/               # the benchmark scripts themselves
├── report/                   # Quarto report rendering all saved results
├── docs/                     # deeper investigation write-ups
└── data/
    ├── pointclouds/          # sample ALS corpus (gitignored, ~13GB, regenerable)
    └── benchmarks/{nodename}/*.RDS   # saved results — tracked in git
```

## Requirements / setup

R packages: `lidR`, `lasR`, `fs`, `jsonlite`, `benchmarkme`, `future`,
`future.apply`, `mirai`, `ggplot2` (for the report); `managelidar` only for
the worker-scaling benchmark
(`remotes::install_github("nwfva-b4/managelidar")` or a local
`devtools::install()`). External tools: PDAL (via conda) and LAStools —
`configure_lidar_tools()` in `R/external-tools.R` puts both on `PATH`; edit
the `conda_path`/`lastools_path` arguments for your machine.

**No `renv` lockfile, deliberately.** This project's entire purpose is
comparing how tool *versions* perform, possibly differently, across
different machines over time — a shared lockfile would work against that.
Instead, every saved result records the exact R/lidR/lasR/PDAL/LAStools
versions that produced it (`get_pkgversions()` in `R/bench-harness.R`),
which is the right-grained reproducibility mechanism for this use case.

## Sample data

`data/pointclouds/` holds the real ALS tiles used as benchmark input.
Regenerate it with `data-prep/fetch_sample_data.R` (needs access to `L:`/`J:`
network shares — see "known limitations" below). `_setup.R` automatically
stages a local `tempdir()` copy of this corpus on every run via
`stage_sample_data()`, so most benchmarks measure processing time, not
network read latency (the drive-speed benchmark is the deliberate
exception).

## How to run a benchmark

```r
source("_setup.R")
source("benchmarks/tools_comparison.R")  # or any other benchmarks/*.R script
```

Results auto-save to `data/benchmarks/{nodename}/*.RDS`. Re-running a
script is a no-op unless you pass `overwrite = TRUE` to `run_bench()`/
`run_sweep()` or delete the cached RDS file.

## How to view results

Render the report:

```sh
quarto render report/benchmark-report.qmd
```

Or explore interactively from the console:

```r
source("R/report-helpers.R")
results <- load_all_benchmarks()
results$named   # tool/stage comparisons
results$sweep   # parameter sweeps (e.g. worker scaling)
```

## Machine/hardware context

| nodename | CPU | cores | RAM | notes |
|---|---|---|---|---|
| pc069 | Intel Core i5-10600 | 12 | 32GB | dev machine |
| LB-3D2026 | (unrecorded) | 16 | 62GB | |
| PC026 | AMD Threadripper PRO 5975WX | 64 (32c/64t) | 256GB | **production target machine** |

`data/benchmarks/pc069/drives_local-vs-network_alte-leitung.RDS` is a real
before/after data point: network read/write on pc069 was ~2x slower over
an older network cable/line than the current baseline
(`drives_local-vs-network.RDS`) — a concrete example of why network
infrastructure matters as much as tooling for terabyte-scale throughput.

## Known limitations

- `data-prep/fetch_sample_data.R` and `benchmarks/drives_local-vs-network.R`
  hardcode network share paths (`L:`, `J:`, `Y:`) specific to this
  organization's setup — only reproducible from a machine with the same
  mappings.
- Several benchmarks intentionally reduce a multi-file corpus down to one
  deterministically-chosen representative file (`pick_representative_file()`)
  so multi-tool comparisons stay apples-to-apples — see the comment at each
  call site for why.

## Reproducibility notes

Every `run_bench()`/`run_sweep()` result carries `systeminfo`, `fileinfo`
(or `filesetinfo`), and `pkgversions` attributes captured at the moment it
ran — `R/report-helpers.R::load_benchmark()` surfaces all of them.

## Related project

[`managelidar`](https://github.com/nwfva-b4/managelidar) is the production
R package this benchmarking informs — specifically its
`raw_to_processed()` pipeline function. The worker-scaling benchmark here
evaluates that function directly; see
[`docs/worker-scaling-findings.md`](docs/worker-scaling-findings.md) for
the full write-up.
