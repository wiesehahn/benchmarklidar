# Sweep managelidar::raw_to_processed()'s `workers` parameter to find a
# good worker count for a given machine/dataset — the most direct evidence
# toward the terabyte-scale processing time question this repo exists to
# answer. See docs/worker-scaling-findings.md for the investigation so far
# (settled: internal lasR threading is NOT worth it vs. more concurrent
# file workers; half of cores is confirmed conservative on most machines;
# settled: PC026's high-worker-count failures are a Windows commit-limit
# (RAM + pagefile) exhaustion, not physical RAM or other users — a
# 2026-08-20 log showed "Die Auslagerungsdatei ist zu klein" (pagefile
# too small) errors while free_ram_gb stayed flat at ~237/256GB;
# per-file logs are kept on disk (see sweep_workers() below) and each
# worker count records free RAM/commit headroom/CPU load/other sessions
# beforehand (get_resource_snapshot(), R/bench-harness.R); open: confirm
# via free_commit_gb_before on the next run, then decide whether to grow
# PC026's pagefile or just cap production worker count at 50% of cores).
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
  # out_dir holds the processed point clouds themselves (large, disposable)
  # and is cleaned up as before. log_dir is kept on disk, separately, so a
  # failure's actual cause survives past this call — the previous version
  # pointed log_dir at out_dir and then deleted it in on.exit(), destroying
  # the only diagnostic evidence for the very failures this sweep exists to
  # catch (e.g. PC026 dropping most files at 75-100% of cores, see
  # docs/worker-scaling-findings.md).
  out_dir <- fs::file_temp("bench_workers_")
  dir.create(out_dir)
  on.exit(unlink(out_dir, recursive = TRUE), add = TRUE)

  # A project-relative, gitignored path rather than tempdir(): R deletes
  # its whole per-session temp directory when the session ends, which
  # would silently destroy these logs again the moment the R console
  # closes, same failure mode as the on.exit(unlink()) bug this replaced.
  nodename <- unname(Sys.info()["nodename"])
  log_dir <- fs::path("logs/workers_raw-to-processed", nodename, sprintf("w%d", workers))
  fs::dir_create(log_dir)
  message(sprintf("    per-file logs for workers=%d kept at: %s", workers, log_dir))

  # Snapshot resource pressure right before the run, to test the RAM/
  # commit-limit/other-users-contending-for-cores hypotheses for the
  # PC026 failures (see docs/worker-scaling-findings.md) instead of just
  # guessing at them.
  before <- get_resource_snapshot()
  message(sprintf(
    "    before run: %.1fGB free RAM, %.1fGB free commit, %.0f%% CPU load, %s other session(s)",
    before$free_ram_gb, before$free_commit_gb, before$cpu_load_pct, before$other_sessions
  ))

  # No suppressWarnings()/suppressMessages() here either, for the same
  # reason: a warning from a failing file is diagnostic signal, not noise.
  # region = NULL: auto-infer from each file's bounding box, rather than
  # hardcoding a region code that only matched the original author's own
  # test files (the sample corpus here is "ni" tiles, not "he").
  res <- raw_to_processed(files, out_dir = out_dir, log_dir = log_dir, region = NULL, verbose = FALSE, workers = workers)

  after <- get_resource_snapshot()

  list(
    n_ok = sum(!vapply(res, is.null, logical(1))), n_total = length(files),
    free_ram_gb_before = before$free_ram_gb, free_ram_gb_after = after$free_ram_gb,
    free_commit_gb_before = before$free_commit_gb, free_commit_gb_after = after$free_commit_gb,
    cpu_load_pct_before = before$cpu_load_pct, other_sessions_before = before$other_sessions
  )
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
