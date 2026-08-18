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

# Zero/negative elapsed times mean the tool failed or wasn't available on
# that machine (e.g. a PDAL system() call erroring out immediately), not a
# genuinely fast run. Blank them out so they show as missing rather than
# winning a "fastest" comparison.
na_if_unavailable <- function(x) ifelse(!is.na(x) & x > 0, x, NA_real_)

# Blanks out elapsed times for PDAL/LAStools rows on machines where that
# CLI tool wasn't actually found on PATH at benchmark time (recorded in
# pkgversions$pdal/pkgversions$lastools — NA if get_pkgversions()'s
# system2() call errored, see R/bench-harness.R). A failed system() call
# can still report a small nonzero elapsed time (process-spawn overhead
# before it errors out), which na_if_unavailable()'s `> 0` check alone
# won't catch — this keys off actual tool availability instead of the
# timing magnitude. Matches rows by tool name in `expression` (case-
# insensitive substring, e.g. "PDAL", "pdal_rw", "pdal_groundcsf" all
# match "pdal"), and only touches machines we have positive evidence
# about — a machine this benchmark never ran on is left untouched.
mask_missing_external_tools <- function(d, meta, benchmark) {
  is_unavailable <- function(tool) {
    entries <- Filter(function(m) m$benchmark == benchmark && !is.null(m$pkgversions), meta)
    if (length(entries) == 0) return(function(nodenames) rep(FALSE, length(nodenames)))
    ok <- setNames(
      vapply(entries, function(m) {
        v <- m$pkgversions[[tool]]
        !is.null(v) && !is.na(v) && nzchar(v)
      }, logical(1)),
      vapply(entries, function(m) m$nodename, character(1))
    )
    function(nodenames) nodenames %in% names(ok) & !ok[nodenames]
  }

  pdal_unavailable <- is_unavailable("pdal")
  lastools_unavailable <- is_unavailable("lastools")

  d$elapsed[grepl("pdal", d$expression, ignore.case = TRUE) & pdal_unavailable(d$nodename)] <- NA_real_
  d$elapsed[grepl("lastools", d$expression, ignore.case = TRUE) & lastools_unavailable(d$nodename)] <- NA_real_
  d
}

# Reshape a (id, key, value) long data frame to wide: one row per id, one
# column per unique key value. Used by the report to turn "one row per
# (stage, machine)" into "one row per stage, one column per machine" —
# otherwise a single long table mixes two different comparisons (which
# stage is slower on a given machine vs. which machine is faster for a
# given stage) into one ambiguous ranking.
pivot_wide <- function(d, id_col, key_col, value_col) {
  ids <- unique(d[[id_col]])
  out <- data.frame(ids, stringsAsFactors = FALSE)
  names(out) <- id_col
  for (k in unique(d[[key_col]])) {
    sub <- d[d[[key_col]] == k, c(id_col, value_col)]
    out[[k]] <- sub[[value_col]][match(out[[id_col]], sub[[id_col]])]
  }
  out
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
