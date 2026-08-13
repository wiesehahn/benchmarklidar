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

in_laz <- stage_sample_data()
configure_lidar_tools()
