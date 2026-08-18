# Compare 3 ways of parallelizing lasR over multiple files: lasR's own
# internal file-concurrency threading, future.apply, and mirai. Worker/
# thread count IS the variable this script cares about, so it does NOT
# call set_fixed_thread_baseline().
source("_setup.R")

kernels <- max(1, round(parallel::detectCores(logical = TRUE) / 2))

# Caveat: unlike future_apply/mirai_map below, this hands lasR the whole
# file collection in one exec() call. Per ?lasR::set_exec_options, lasR
# then decides on its own whether/how much buffer to read around each
# file's edges to stay aware of neighboring tiles — work the other two
# strategies never do, since each calls exec() on one fully isolated file
# at a time. So lasr_internal running slower isn't purely a measure of
# the parallelization strategy; part of it is genuinely doing more work.
# (Also make sure the corpus is .lax-indexed before trusting this number —
# see "Known limitations" in the README for why that matters a lot here.)
lasr_internal <- function() {
  out_dir <- fs::file_temp("parallel_lasr_")
  dir.create(out_dir)
  pipeline <- lasR::reader() + lasR::write_las(ofile = fs::path(out_dir, "*.laz"))
  lasR::exec(pipeline, on = in_laz, with = list(ncores = lasR::concurrent_files(kernels)))
}

future_apply <- function() {
  out_dir <- fs::file_temp("parallel_future_")
  dir.create(out_dir)

  process_file <- function(file_path) {
    pipeline <- lasR::reader() + lasR::write_las(ofile = fs::path(out_dir, "*.laz"))
    lasR::exec(pipeline, on = file_path, with = list(ncores = 1))
  }

  future::plan(future::multisession, workers = kernels)
  on.exit(future::plan(future::sequential), add = TRUE)
  future.apply::future_lapply(in_laz, process_file)
}

mirai_map <- function() {
  out_dir <- fs::file_temp("parallel_mirai_")
  dir.create(out_dir)

  process_file <- function(file_path) {
    pipeline <- lasR::reader() + lasR::write_las(ofile = fs::path(out_dir, "*.laz"))
    lasR::exec(pipeline, on = file_path, with = list(ncores = 1))
  }

  mirai::daemons(kernels)
  on.exit(mirai::daemons(0), add = TRUE)
  m <- mirai::mirai_map(in_laz, process_file)
  m[]
}

run_bench(
  "parallel_strategies.RDS",
  lasr_internal = lasr_internal,
  future_apply  = future_apply,
  mirai_map     = mirai_map,
  filesetinfo = get_filesetinfo(in_laz)
)
