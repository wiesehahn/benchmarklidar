# benchmark drives (read/write speed for different hard drives)

source("_setup.R")

# Paths to test
in_network <- dir_ls("Y:/Jens/lidar-benchmark/data/pointclouds/", type = "file", regexp = "*.laz")
to_copy <- lasfiles[!file_exists(in_network)]
file_copy(to_copy, path("Y:/Jens/lidar-benchmark/data/pointclouds/", path_file(to_copy)))

in_local   <- in_laz


in_local   <- in_local[15]
in_network <- in_network[15]


out_network <- path("Y:/Jens/tmp/*.laz")
out_local   <- path(tempdir(), "*.laz")


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

benchmark <-
  run_bench(
    rds_file = "drives_bench.RDS",
    read_local     = read_local,
    read_network = read_network,
    write_local = write_local,
    write_network = write_network
  )

# overwrite fileinfo (only 1 file here)
attr(benchmark, "fileinfo") <- get_fileinfo(in_local)
rds_path <- path(path("data/benchmarks", get_systeminfo()$nodename), "drives_bench.RDS")
saveRDS(benchmark, rds_path)

attr(benchmark, "systeminfo")
attr(benchmark, "fileinfo")
benchmark


unlink(list.files(out_network))
unlink(list.files(out_local))
