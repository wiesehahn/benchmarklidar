# Single entry point: run every benchmarks/*.R script on this machine.
#
# Each script's own run_bench()/run_sweep() calls already cache results to
# data/benchmarks/{nodename}/*.RDS, so simply sourcing every script is
# cheap when results already exist — each individual sub-benchmark (e.g.
# tools_comparison.R's rw/copc/normals/ground) is skipped independently if
# its RDS is already there, and only missing/new ones actually run.
# overwrite = TRUE forces every sub-benchmark to re-run regardless — worth
# doing periodically for benchmarks/drives_local-vs-network.R in
# particular, since network/drive speed can drift over time (see
# data/benchmarks/*/drives_local-vs-network_alte-leitung.RDS for a real
# example: ~2x slower reads over an old network cable/line).
run_all_benchmarks <- function(overwrite = FALSE) {
  source("_setup.R")

  old_opt <- getOption("lidarbench.overwrite")
  options(lidarbench.overwrite = overwrite)
  on.exit(options(lidarbench.overwrite = old_opt))

  scripts <- c(
    "benchmarks/tools_comparison.R",
    "benchmarks/lasr_stages.R",
    "benchmarks/lidr-lasr_ground-intensity.R",
    "benchmarks/drives_local-vs-network.R",
    "benchmarks/parallel_strategies.R",
    "benchmarks/workers_raw-to-processed.R"
  )

  results <- data.frame(script = scripts, status = NA_character_, seconds = NA_real_)

  for (i in seq_along(scripts)) {
    s <- scripts[i]
    message(sprintf("[%s] START %s", format(Sys.time(), "%H:%M:%S"), s))
    t0 <- Sys.time()

    status <- tryCatch({
      source(s)
      "done"
    }, error = function(e) {
      message("  ERROR: ", conditionMessage(e))
      "failed"
    })

    secs <- round(as.numeric(difftime(Sys.time(), t0, units = "secs")), 1)
    results$status[i] <- status
    results$seconds[i] <- secs
    message(sprintf("[%s] %s %s - %.1fs\n", format(Sys.time(), "%H:%M:%S"), toupper(status), s, secs))
  }

  message("=== run_all_benchmarks() summary ===")
  print(results, row.names = FALSE)
  invisible(results)
}
