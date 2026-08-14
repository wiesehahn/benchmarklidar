# Dynamically discover and load every saved benchmark result, instead of
# hardcoding machine/result filenames (the old view_bench.R problem).

discover_benchmark_files <- function() {
  fs::dir_ls("data/benchmarks", recurse = TRUE, glob = "*.RDS")
}

load_benchmark <- function(path) {
  data <- readRDS(path)
  list(
    data        = data,
    systeminfo  = attr(data, "systeminfo"),
    fileinfo    = attr(data, "fileinfo"),
    filesetinfo = attr(data, "filesetinfo"),
    pkgversions = attr(data, "pkgversions"),
    nodename    = fs::path_file(fs::path_dir(path)),
    benchmark   = fs::path_ext_remove(fs::path_file(path))
  )
}

# Zero/NA elapsed times mean the tool wasn't available on that machine (e.g.
# a PDAL system() call failing immediately), not a genuinely fast run, so
# they must not become the baseline for relative time. This treats them as
# missing and adds a `relative` column (1.00 = fastest valid row). With
# reorder = TRUE (named-comparison tables) rows are ranked fastest-first,
# unavailable ones pushed to the bottom; with reorder = FALSE (parameter
# sweeps) the caller's existing row order — e.g. ascending worker count —
# is left untouched since it carries meaning of its own.
add_relative_time <- function(d, time_col, reorder = TRUE) {
  ok <- !is.na(d[[time_col]]) & d[[time_col]] > 0
  d[[time_col]][!ok] <- NA_real_
  baseline <- if (any(ok)) min(d[[time_col]][ok]) else NA_real_
  d$relative <- ifelse(ok, d[[time_col]] / baseline, NA_real_)
  if (reorder) d <- d[order(d[[time_col]], na.last = TRUE), ]
  d
}

# Loads every result under data/benchmarks/ and splits them into the two
# shapes the harness produces: $named (run_bench() — alternatives compared
# by name) and $sweep (run_sweep() — one row per parameter value).
load_all_benchmarks <- function() {
  files <- discover_benchmark_files()
  loaded <- lapply(files, load_benchmark)

  is_sweep <- function(b) "seconds" %in% names(b$data) && !"expression" %in% names(b$data)

  tag <- function(b) {
    d <- b$data
    d$nodename <- b$nodename
    d$benchmark <- b$benchmark
    d
  }

  named <- loaded[!vapply(loaded, is_sweep, logical(1))]
  sweep <- loaded[vapply(loaded, is_sweep, logical(1))]

  list(
    named = if (length(named) > 0) do.call(rbind, lapply(named, tag)) else NULL,
    sweep = if (length(sweep) > 0) do.call(rbind, lapply(sweep, tag)) else NULL,
    meta  = loaded
  )
}
