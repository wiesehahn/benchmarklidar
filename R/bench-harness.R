# Core benchmark harness: timing, caching, and reproducibility metadata
# shared by every script under benchmarks/.

get_systeminfo <- function() {
  cpu <- benchmarkme::get_cpu()

  list(
    nodename = unname(Sys.info()["nodename"]),
    os       = unname(Sys.info()["sysname"]),
    ram      = benchmarkme::get_ram(),
    cpu      = cpu$model_name,
    cores    = cpu$no_of_cores
  )
}

# Point-in-time resource pressure snapshot — free RAM, CPU load, and how
# many *other* interactive sessions are logged into the machine. Exists to
# test (not just guess at) whether high-worker-count failures on shared
# machines like PC026 correlate with memory pressure or other users'
# concurrent sessions contending for cores, rather than being an
# unexplained tool bug. Windows-only (wmic was dropped from newer Windows
# builds, hence PowerShell/query.exe here); returns NAs elsewhere or on any
# failure, since this is diagnostic and must never break the benchmark
# itself.
get_resource_snapshot <- function() {
  snapshot <- list(free_ram_gb = NA_real_, cpu_load_pct = NA_real_, other_sessions = NA_integer_)
  if (unname(Sys.info()["sysname"]) != "Windows") return(snapshot)

  snapshot$free_ram_gb <- tryCatch({
    kb <- as.numeric(system2("powershell", c("-NoProfile", "-Command",
      "(Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory"), stdout = TRUE))
    round(kb / 1024^2, 2)
  }, error = function(e) NA_real_, warning = function(w) NA_real_)

  snapshot$cpu_load_pct <- tryCatch({
    as.numeric(system2("powershell", c("-NoProfile", "-Command",
      "(Get-CimInstance Win32_Processor | Measure-Object -Property LoadPercentage -Average).Average"),
      stdout = TRUE))
  }, error = function(e) NA_real_, warning = function(w) NA_real_)

  snapshot$other_sessions <- tryCatch({
    # query.exe exits with status 1 even on success (observed on this
    # machine), which system2() turns into a warning unrelated to whether
    # the output is usable — suppress just that, not real failures below.
    # Output is one header row + one row per session (including this one);
    # no other-user sessions is a legitimate 0, not a failure.
    out <- suppressWarnings(system2("query", "user", stdout = TRUE, stderr = TRUE))
    max(0L, length(out) - 2L)
  }, error = function(e) NA_integer_)

  snapshot
}

get_fileinfo <- function(file) {
  list(
    filename = fs::path_file(file),
    size     = fs::file_size(file)
  )
}

get_filesetinfo <- function(files) {
  sizes <- file.info(files)$size
  list(
    n_files         = length(files),
    total_size_bytes = sum(sizes, na.rm = TRUE),
    size_range      = range(sizes, na.rm = TRUE)
  )
}

# Version info for the tools actually under comparison. Recorded per-run
# (not pinned via a lockfile) because the whole point of this repo is
# comparing how these tools perform *as their versions change over time*.
get_pkgversions <- function(pkgs = c("lidR", "lasR", "fs", "jsonlite")) {
  pkg_versions <- lapply(pkgs, function(p) {
    tryCatch(as.character(utils::packageVersion(p)), error = function(e) NA_character_)
  })
  names(pkg_versions) <- pkgs

  get_cli_version <- function(command, args) {
    tryCatch({
      out <- system2(command, args, stdout = TRUE, stderr = TRUE)
      paste(out, collapse = " ")
    }, error = function(e) NA_character_, warning = function(w) NA_character_)
  }

  list(
    r        = as.character(getRversion()),
    packages = pkg_versions,
    pdal     = get_cli_version("pdal", "--version"),
    lastools = get_cli_version("las2las64", "-version")
  )
}

# Deterministically pick one representative file from a set, instead of an
# arbitrary/undocumented index. Used wherever a benchmark needs a single
# input file (e.g. to keep a multi-tool comparison apples-to-apples).
pick_representative_file <- function(files, method = "median_size") {
  method <- match.arg(method, "median_size")
  sizes <- file.info(files)$size
  files[[which.min(abs(sizes - stats::median(sizes, na.rm = TRUE)))]]
}

# Run a set of named, zero-arg benchmark expressions, cache the result to
# data/benchmarks/{nodename}/{rds_file}, and record system/file/package
# info alongside the timings. Re-running is a no-op unless overwrite=TRUE
# or the cached file is deleted. Default overwrite reads the
# "benchmarklidar.overwrite" option, so run_all_benchmarks() (R/run-all.R) can
# force a fresh run of everything without every script needing its own
# overwrite= argument.
run_bench <- function(rds_file, ..., fileinfo = NULL, filesetinfo = NULL,
                       overwrite = getOption("benchmarklidar.overwrite", FALSE)) {
  systeminfo <- get_systeminfo()

  rds_folder <- fs::dir_create(fs::path("data/benchmarks", systeminfo$nodename))
  rds_path <- fs::path(rds_folder, rds_file)
  if (fs::file_exists(rds_path) && !overwrite) {
    message("  [cached] ", rds_file)
    return(readRDS(rds_path))
  }

  exprs <- list(...)
  nms   <- names(exprs)

  timing <- matrix(NA_real_, nrow = length(exprs), ncol = 3)
  colnames(timing) <- c("user", "system", "elapsed")

  message(sprintf("  [running] %s (%d expressions)", rds_file, length(exprs)))
  for (i in seq_along(exprs)) {
    gc()
    message(sprintf("    %d/%d %s ...", i, length(exprs), nms[i]))
    t <- system.time(exprs[[i]]())
    message(sprintf("      done in %.1fs", t[["elapsed"]]))
    timing[i, ] <- unname(t[c("user.self", "sys.self", "elapsed")])
  }

  res <- data.frame(
    expression = nms,
    timing,
    stringsAsFactors = FALSE
  )

  attr(res, "systeminfo") <- systeminfo
  attr(res, "pkgversions") <- get_pkgversions()
  if (!is.null(fileinfo)) attr(res, "fileinfo") <- fileinfo
  if (!is.null(filesetinfo)) attr(res, "filesetinfo") <- filesetinfo

  saveRDS(res, rds_path)
  message("  [ran]    ", rds_file)
  res
}

# Run a single function across a sweep of parameter values (one row per
# value), for benchmarks shaped as "how does time scale with X" rather
# than "compare these named alternatives". `fun(param_value, ...)` is
# timed with Sys.time() and may return a named list of extra columns
# (e.g. n_ok) to attach to that row. Default overwrite reads the same
# "benchmarklidar.overwrite" option as run_bench() — see there.
run_sweep <- function(rds_file, param_name, param_values, fun, ...,
                       fileset = NULL,
                       overwrite = getOption("benchmarklidar.overwrite", FALSE)) {
  systeminfo <- get_systeminfo()

  rds_folder <- fs::dir_create(fs::path("data/benchmarks", systeminfo$nodename))
  rds_path <- fs::path(rds_folder, rds_file)
  if (fs::file_exists(rds_path) && !overwrite) {
    message("  [cached] ", rds_file)
    return(readRDS(rds_path))
  }

  message(sprintf("  [running] %s (%d %s values)", rds_file, length(param_values), param_name))
  rows <- vector("list", length(param_values))
  for (i in seq_along(param_values)) {
    gc()
    message(sprintf("    %d/%d %s = %s ...", i, length(param_values), param_name, param_values[[i]]))
    t0 <- Sys.time()
    extra <- fun(param_values[[i]], ...)
    t1 <- Sys.time()
    secs <- as.numeric(difftime(t1, t0, units = "secs"))
    message(sprintf("      done in %.1fs", secs))

    row <- c(
      list(seconds = secs),
      extra
    )
    row[[param_name]] <- param_values[[i]]
    rows[[i]] <- as.data.frame(row, stringsAsFactors = FALSE)
  }

  res <- do.call(rbind, rows)
  res <- res[, c(param_name, setdiff(names(res), param_name)), drop = FALSE]

  attr(res, "systeminfo") <- systeminfo
  attr(res, "pkgversions") <- get_pkgversions()
  if (!is.null(fileset)) attr(res, "filesetinfo") <- get_filesetinfo(fileset)

  saveRDS(res, rds_path)
  message("  [ran]    ", rds_file)
  res
}
