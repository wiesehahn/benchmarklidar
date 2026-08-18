# Sweep managelidar::raw_to_processed()'s `workers` parameter to find a
# good worker count for a given machine/dataset — the most direct evidence
# toward the terabyte-scale processing time question this repo exists to
# answer. See docs/worker-scaling-findings.md for the investigation so far
# (settled: internal lasR threading is NOT worth it vs. more concurrent
# file workers; half of cores is confirmed conservative on most machines;
# open: why the production machine (PC026) fails to complete most files
# above 50% of cores).
#
# Does NOT call set_fixed_thread_baseline() — worker count is the variable
# under test, and raw_to_processed() already hardcodes ncores=1 internally
# (per the settled finding above).
source("_setup.R")

# mirai workers always load the *installed* managelidar package, never an
# in-memory devtools::load_all() version (see docs/worker-scaling-findings.md,
# gotcha #1) — run devtools::install() first if package source has changed.
library(managelidar)

# ---------------------------------------------------------------------------
# 1. Pick a representative file set.
# ---------------------------------------------------------------------------
# Enough files to keep every worker busy at the highest tested worker count
# (ideally 2-3x that many, so the queue doesn't run dry before the run
# ends). Defaults to the full staged sample corpus.
files <- in_laz

if (length(files) == 0) {
  stop("No files staged. Check data/pointclouds/ and _setup.R::stage_sample_data().")
}

message(sprintf("Benchmark set: %d files, %.2f GB total\n",
                 length(files), sum(file.info(files)$size, na.rm = TRUE) / 1024^3))

# ---------------------------------------------------------------------------
# 2. Worker counts to sweep.
# ---------------------------------------------------------------------------
# 50/75/100% of logical cores. Until 2026-08-17, managelidar's map_las()
# silently clamped any requested `workers` to half of logical cores no
# matter what was asked for, which made every value above that a no-op —
# see docs/worker-scaling-findings.md and the fix upstream in managelidar.
# Now that an explicit `workers=` is actually honored up to the full core
# count, this sweep can show a real scaling curve; 150%/200% are left out
# since managelidar warns (not clamps) above half of cores due to each
# worker holding a full point cloud in memory (RAM headroom), and going
# past 100% of cores is unlikely to help once CPU is saturated.
total_cores <- parallel::detectCores(logical = TRUE)
worker_counts <- unique(pmax(1, round(c(total_cores * 0.5, total_cores * 0.75, total_cores))))

message("Logical cores detected: ", total_cores)
message("Worker counts to test: ", paste(worker_counts, collapse = ", "))

# ---------------------------------------------------------------------------
# 3. Run the sweep.
# ---------------------------------------------------------------------------
sweep_workers <- function(workers, files) {
  out_dir <- fs::file_temp("bench_workers_")
  dir.create(out_dir)
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  res <- suppressMessages(suppressWarnings(
    # region = NULL: auto-infer from each file's bounding box, rather than
    # hardcoding a region code that only matched the original author's own
    # test files (the sample corpus here is "ni" tiles, not "he").
    raw_to_processed(files, out_dir = out_dir, log_dir = out_dir, region = NULL, verbose = FALSE, workers = workers)
  ))

  list(n_ok = sum(!vapply(res, is.null, logical(1))), n_total = length(files))
}

results <- run_sweep(
  "workers_raw-to-processed.RDS",
  param_name   = "workers",
  param_values = worker_counts,
  fun          = sweep_workers,
  files        = files,
  fileset      = files
)

message("\n=== Summary (sorted by time) ===")
print(results[order(results$seconds), ], row.names = FALSE)
