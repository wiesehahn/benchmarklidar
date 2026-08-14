# Thin bootstrap sourced at the top of every benchmarks/*.R script.
# Loads reusable helpers and stages sample data; does NOT set any global
# lasR options as a side effect (see R/lasr-options.R — each script opts
# in explicitly if it needs a fixed thread baseline).
library(fs)

source("R/bench-harness.R")
source("R/external-tools.R")
source("R/stage-sample-data.R")
source("R/lasr-options.R")
source("R/report-helpers.R")
source("R/run-all.R")
source("R/check-environment.R")

configure_lidar_tools()

# _setup.R is sourced repeatedly (every benchmarks/*.R script sources it,
# and run_all_benchmarks() sources it again on top of that). Both
# check_environment() and stage_sample_data()/configure_lidar_tools()
# already stay quiet on their own once there's nothing new to report, so
# nothing here needs its own once-per-session guard except the (louder,
# multi-line) environment check. Must run AFTER configure_lidar_tools()
# so pdal/LAStools are actually on PATH to find.
if (!isTRUE(getOption("lidarbench.setup_done"))) {
  check_environment()
  options(lidarbench.setup_done = TRUE)
}

in_laz <- stage_sample_data()
