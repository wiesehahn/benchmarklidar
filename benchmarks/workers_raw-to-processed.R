# Sweep managelidar::raw_to_processed()'s `workers` parameter to find a
# good worker count for a given machine/dataset — the most direct evidence
# toward the terabyte-scale processing time question this repo exists to
# answer. See docs/worker-scaling-findings.md for the investigation so far
# (settled: internal lasR threading is NOT worth it vs. more concurrent
# file workers; open: whether "half of cores" is too conservative on
# high-core-count machines).
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
# ends). Defaults to the full staged sample corpus; override with a larger/
# more representative set for a real sweep (see docs/worker-scaling-findings.md
# "Suggested next step").
files <- in_laz

if (length(files) == 0) {
  stop("No files staged. Check data/pointclouds/ and _setup.R::stage_sample_data().")
}

cat(sprintf("Benchmark set: %d files, %.2f GB total\n\n",
            length(files), sum(file.info(files)$size, na.rm = TRUE) / 1024^3))

# ---------------------------------------------------------------------------
# 2. Worker counts to sweep.
# ---------------------------------------------------------------------------
# Includes the current default heuristic's value (half of logical cores)
# as a baseline, then spans up to and beyond the full logical core count to
# see where returns flatten or reverse.
total_cores <- parallel::detectCores(logical = TRUE)
worker_counts <- unique(pmax(1, round(c(total_cores / 2, total_cores * 0.75, total_cores, total_cores * 1.5, total_cores * 2))))

cat("Logical cores detected:", total_cores, "\n")
cat("Worker counts to test:", paste(worker_counts, collapse = ", "), "\n\n")

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

cat("\n=== Summary (sorted by time) ===\n")
print(results[order(results$seconds), ], row.names = FALSE)
