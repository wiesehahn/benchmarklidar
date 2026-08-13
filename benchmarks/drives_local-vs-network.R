# Benchmark local vs. network drive read/write speed. The repo itself
# lives on a network share (Y:), so data/pointclouds/ IS the network-drive
# source; in_laz (from _setup.R's stage_sample_data()) is the same corpus
# copied to a local tempdir. Re-run with overwrite = TRUE whenever network
# infrastructure changes (see data/benchmarks/pc069/drives_local-vs-network_alte-leitung.RDS
# for a real before/after example: ~2x slower reads over an old network
# cable/line ("alte Leitung")).
source("_setup.R")

# Network path is hardcoded to this repo's own share location — only
# reproducible from a machine with the same Y: mapping.
network_dir <- "Y:/Jens/lidar-benchmark/data/pointclouds/"

in_local   <- pick_representative_file(in_laz)
in_network <- fs::path(network_dir, fs::path_file(in_local))

out_local_dir   <- fs::file_temp("drives_local_")
out_network_dir <- "Y:/Jens/tmp"
fs::dir_create(out_local_dir)
fs::dir_create(out_network_dir)

out_local   <- fs::path(out_local_dir, "*.laz")
out_network <- fs::path(out_network_dir, "*.laz")


read_network <- function() {
  lasR::read_cloud(in_network)
}

read_local <- function() {
  lasR::read_cloud(in_local)
}


write_network <- function() {
  pipeline <- lasR::write_las(out_network)
  lasR::exec(pipeline, on = las)
}

write_local <- function() {
  pipeline <- lasR::write_las(out_local)
  lasR::exec(pipeline, on = las)
}


# ============
# PRE-READ
# ============

# ensure that the files are already in cache to ensure fair
# comparison of all pipelines
pre_read = lasR::reader() + lasR:::nothing(stream = T)
lasR::exec(pre_read, on = c(in_local, in_network))

# Read point cloud in memory so other stages can be benchmarked separate
las <- lasR::read_cloud(in_local)

# ============
# BENCHMARK
# ============

run_bench(
  "drives_local-vs-network.RDS",
  read_local     = read_local,
  read_network   = read_network,
  write_local    = write_local,
  write_network  = write_network,
  fileinfo       = get_fileinfo(in_local),
  overwrite      = TRUE
)

fs::file_delete(fs::dir_ls(out_local_dir, type = "file"))
fs::file_delete(fs::dir_ls(out_network_dir, type = "file"))
