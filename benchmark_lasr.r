
# compare processing times lasR stages
source("_setup.R")

# stages to test
read <- function() {
  lasR::read_cloud(in_laz)
}

writelas <- function() {
  pipeline <- lasR::write_las(fs::file_temp(ext = ".las"))
  lasR::exec(pipeline, on = las)
}

writelaz <- function() {
  pipeline <- lasR::write_las(fs::file_temp(ext = ".laz"))
  lasR::exec(pipeline, on = las)
}

writecopc <- function() {
  pipeline <- lasR::write_copc(fs::file_temp(ext = ".copc.laz"))
  lasR::exec(pipeline, on = las)
}

sort_points <- function() {
  pipeline <- lasR::sort_points()
  lasR::exec(pipeline, on = las)
}

triangulate <- function() {
  pipeline <- lasR::triangulate(max_edge = 5, filter = lasR::keep_ground())
  lasR::exec(pipeline, on = las)
}

rasterize <- function() {
  pipeline <- lasR::rasterize(res = 1, operators = "max")
  lasR::exec(pipeline, on = las)
}

dtm <- function() {
  # uses triangulate + rasterize
  pipeline <- lasR::dtm()
  lasR::exec(pipeline, on = las)
}

dsm <- function() {
  # uses triangulate + rasterize
  pipeline <- lasR::dsm(tin = TRUE)
  lasR::exec(pipeline, on = las)
}

normalize <- function() {
  # uses triangulate + transform_with
  pipeline <- lasR::normalize()
  lasR::exec(pipeline, on = las)
}

local_maximum <- function() {
  pipeline <- lasR::local_maximum(5)
  lasR::exec(pipeline, on = las)
}

classify_with_csf <- function() {
  pipeline <- lasR::classify_with_csf()
  lasR::exec(pipeline, on = las)
}

classify_with_ivf <- function() {
  pipeline <- lasR::classify_with_ivf()
  lasR::exec(pipeline, on = las)
}

classify_with_sor <- function() {
  pipeline <- lasR::classify_with_sor()
  lasR::exec(pipeline, on = las)
}

classify_with_ipf <- function() {
  pipeline <- lasR::classify_with_ipf()
  lasR::exec(pipeline, on = las)
}

classify_with_ptd <- function() {
  pipeline <- lasR::classify_with_ptd()
  lasR::exec(pipeline, on = las)
}


# ============
# PRE-READ
# ============

# ensure that the files are already in cache to ensure fair
# comparison of all pipelines
pre_read = lasR::reader() + lasR:::nothing(stream = T)
lasR::exec(pre_read, on = in_laz)

# Read point cloud in memory so other stages can be benchmarked separate
las <- lasR::read_cloud(in_laz)

# ============
# BENCHMARK
# ============

benchmark <-
  run_bench(
    rds_file = "lasrstages_bench.RDS",
    read     = read,
    writelas = writelas,
    writelaz = writelaz,
    writecopc = writecopc,
    sort_points = sort_points,
    triangulate = triangulate,
    rasterize = rasterize,
    dtm = dtm,
    dsm = dsm,
    normalize = normalize,
    local_maximum = local_maximum,
    classify_with_csf = classify_with_csf,
    classify_with_ivf = classify_with_ivf,
    classify_with_sor = classify_with_sor,
    classify_with_ipf = classify_with_ipf,
    classify_with_ptd = classify_with_ptd
  )

attr(benchmark, "systeminfo")
attr(benchmark, "fileinfo")
benchmark

# related tests at https://github.com/r-lidar/lasR/blob/main/inst/benchmark-multithread.R

