# Preflight check: are the R packages and external tools this repo needs
# actually available on this machine? Run automatically once per session
# by _setup.R, or call directly any time to re-check.
check_environment <- function(
    pkgs = c("lidR", "lasR", "fs", "jsonlite", "benchmarkme",
             "future", "future.apply", "mirai", "ggplot2", "knitr"),
    optional_pkgs = c(managelidar = "needed for benchmarks/workers_raw-to-processed.R"),
    tools = list(
      pdal     = c("pdal", "--version"),
      lastools = c("las2las64", "-version")
    )
) {
  message("Checking R packages...")
  for (p in pkgs) {
    ok <- requireNamespace(p, quietly = TRUE)
    v <- if (ok) as.character(utils::packageVersion(p)) else ""
    message(sprintf("  [%-7s] %-15s %s", if (ok) "OK" else "MISSING", p, v))
  }

  message("Checking optional R packages...")
  for (p in names(optional_pkgs)) {
    ok <- requireNamespace(p, quietly = TRUE)
    v <- if (ok) as.character(utils::packageVersion(p)) else optional_pkgs[[p]]
    message(sprintf("  [%-7s] %-15s %s", if (ok) "OK" else "MISSING", p, v))
  }

  message("Checking external tools on PATH...")
  for (nm in names(tools)) {
    cmd <- tools[[nm]][1]
    args <- tools[[nm]][-1]
    found <- nzchar(Sys.which(cmd))
    if (found) {
      out <- tryCatch(
        paste(system2(cmd, args, stdout = TRUE, stderr = TRUE), collapse = " "),
        error = function(e) "(found on PATH, but --version failed)"
      )
      message(sprintf("  [OK     ] %-15s %s", nm, out))
    } else {
      message(sprintf("  [MISSING] %-15s not found on PATH (see R/external-tools.R::configure_lidar_tools())", nm))
    }
  }

  invisible(TRUE)
}
