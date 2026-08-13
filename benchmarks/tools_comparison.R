# Compare processing times between tools (lidR, lasR, PDAL, LAStools) for
# a set of common operations. All four tools run against the SAME single
# representative file (not the full sample corpus) so the comparison is
# apples-to-apples: lidR::readALS()/lasR::exec(on=) happily batch multiple
# files, but the PDAL/LAStools system() calls below do not, so a shared
# input vector would silently make PDAL/LAStools run only the first file
# while lidR/lasR ran the whole corpus.
source("_setup.R")

bench_file <- pick_representative_file(in_laz)

# Fixed thread count so tool comparisons aren't confounded by different
# default parallelism between tools.
set_fixed_thread_baseline(cores = 4)

#------------------------------------ read + write ------------------------------------#
lidr_rw <- function() {
  las <- lidR::readALS(bench_file)
  lidR::writeLAS(las, fs::file_temp(ext = ".laz"))
}

lasr_rw <- function() {
  pipeline <- lasR::reader() + lasR::write_las(fs::file_temp(ext = ".laz"))
  lasR::exec(pipeline, on = bench_file)
}

pdal_rw <- function() {
  command <- paste("pdal translate", bench_file, fs::file_temp(ext = ".laz"))
  system(command, wait = TRUE)
}

lastools_rw <- function() {
  command <- paste("las2las64.exe", "-i", bench_file, "-o", fs::file_temp(ext = ".laz"))
  system(command, wait = TRUE)
}


run_bench(
  "tools_rw.RDS",
  lidR     = lidr_rw,
  lasR     = lasr_rw,
  PDAL     = pdal_rw,
  LAStools = lastools_rw,
  fileinfo = get_fileinfo(bench_file)
)


#------------------------------------ convert to COPC ------------------------------------#
# lidR: not supported, omitted.

lasr_copc <- function() {
  pipeline <- lasR::reader() + lasR::write_copc(fs::file_temp(ext = ".copc.laz"))
  lasR::exec(pipeline, on = bench_file)
}

pdal_copc <- function() {
  command <- paste("pdal translate", bench_file, fs::file_temp(ext = ".copc.laz"))
  system(command, wait = TRUE)
}

lastools_copc <- function() {
  command <- paste("lascopcindex64.exe", "-i", bench_file, "-o", fs::file_temp(ext = ".copc.laz"))
  system(command, wait = TRUE)
}


run_bench(
  "tools_copc.RDS",
  lasR     = lasr_copc,
  PDAL     = pdal_copc,
  LAStools = lastools_copc,
  fileinfo = get_fileinfo(bench_file)
)


#------------------------------------ read + normals + write --------------------------------#
lasr_normals <- function() {
  pipeline <- lasR::reader() + lasR::geometry_features(k = 20, features = "n") + lasR::write_las(fs::file_temp(ext = ".laz"))
  lasR::exec(pipeline, on = bench_file)
}

pdal_normals <- function() {
  out_laz <- fs::file_temp(ext = ".laz")

  pipeline <- list(
    list(
      type = "readers.las",
      filename = bench_file
    ),
    list(
      type = "filters.normal",
      knn = 10,
      always_up = FALSE
    ),
    list(
      type = "writers.las",
      filename = out_laz,
      extra_dims = "all"
    )
  )

  pipeline_file <- fs::file_temp(ext = ".json")
  jsonlite::write_json(pipeline, pipeline_file, auto_unbox = TRUE, pretty = TRUE)

  system(
    command = paste("pdal pipeline", pipeline_file),
    wait = TRUE
  )
}


run_bench(
  rds_file = "tools_normals.RDS",
  lasR     = lasr_normals,
  PDAL     = pdal_normals,
  fileinfo = get_fileinfo(bench_file)
)

#------------------------------------ read + classify ground + write --------------------------------#
lidr_groundcsf <- function() {
  las <- lidR::readALS(bench_file)
  las <- lidR::classify_ground(las,
                               algorithm = lidR::csf(
    sloop_smooth = FALSE,
    class_threshold = 0.5,
    cloth_resolution = 0.5,
    rigidness = 1L,
    iterations = 500L,
    time_step = 0.65
  ))
  lidR::writeLAS(las, fs::file_temp(ext = ".laz"))
}

lasr_groundcsf <- function() {
  pipeline <- lasR::reader() + lasR::classify_with_csf(
    slope_smooth = FALSE,
    class_threshold = 0.5,
    cloth_resolution = 0.5,
    rigidness = 1L,
    iterations = 500L,
    time_step = 0.65
  ) + lasR::write_las(fs::file_temp(ext = ".laz"))
  lasR::exec(pipeline, on = bench_file)
}

pdal_groundcsf <- function() {
  out_laz <- fs::file_temp(ext = ".laz")

  pipeline <- list(
    list(
      type = "readers.las",
      filename = bench_file
    ),
    list(
      type = "filters.csf",
      smooth = FALSE,
      threshold = 0.5,
      resolution = 0.5,
      rigidness = 1,
      iterations = 500,
      step = 0.65
    ),
    list(
      type = "writers.las",
      filename = out_laz,
      extra_dims = "all"
    )
  )

  pipeline_file <- fs::file_temp(ext = ".json")
  jsonlite::write_json(pipeline, pipeline_file, auto_unbox = TRUE, pretty = TRUE)

  system(
    command = paste("pdal pipeline", pipeline_file),
    wait = TRUE
  )
}

lasr_groundptd <- function() {
  pipeline <- lasR::reader() + lasR::classify_with_ptd(
    res = 10,
    angle = 30,
    distance = 2,
    spacing = 0.25
  ) + lasR::write_las(fs::file_temp(ext = ".laz"))
  lasR::exec(pipeline, on = bench_file)
}

lastools_ground <- function() {
  command <- paste("lasground_new64.exe", "-i", bench_file, "-o", fs::file_temp(ext = ".laz"), "-all_returns -step 10")
  system(command, wait = TRUE)
}


run_bench(
  "tools_ground.RDS",
  lidr_groundcsf = lidr_groundcsf,
  lasr_groundcsf = lasr_groundcsf,
  pdal_groundcsf = pdal_groundcsf,
  lasr_groundptd = lasr_groundptd,
  lastools_ground = lastools_ground,
  fileinfo = get_fileinfo(bench_file)
)
