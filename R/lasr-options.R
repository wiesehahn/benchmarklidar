# A fixed, documented lasR thread count for benchmarks where thread/worker
# count is NOT the variable under test (e.g. comparing tools or pipeline
# stages) — gives every such comparison the same, fair baseline instead of
# lasR's default. Call this explicitly at the top of a script; it is never
# invoked implicitly by _setup.R.
#
# Do NOT call this in scripts where thread/worker count IS the thing being
# measured: benchmarks/parallel_strategies.R, benchmarks/workers_raw-to-processed.R,
# benchmarks/drives_local-vs-network.R.
set_fixed_thread_baseline <- function(cores = 4) {
  lasR::set_exec_options(progress = FALSE, ncores = lasR::concurrent_points(cores))
}
