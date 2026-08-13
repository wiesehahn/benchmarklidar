# compare processing times between tools (lidR, lasR, pdal, lastools)
source("_setup.R")


#------------------------------------ read + write ------------------------------------#
lidr_rw <- function() {
  las <- lidR::readALS(in_laz)
  lidR::writeLAS(las, fs::file_temp(ext = ".laz"))
}

lasr_rw <- function() {
  pipeline <- lasR::reader() + lasR::write_las(fs::file_temp(ext = ".laz"))
  lasR::exec(pipeline, on = in_laz)
}

pdal_rw <- function() {
  command <- paste("pdal translate", in_laz, fs::file_temp(ext = ".laz"))
  system(command, wait = TRUE)
}

lastools_rw <- function() {
  command <- paste("las2las64.exe", "-i", in_laz, "-o", fs::file_temp(ext = ".laz"))
  system(command, wait = TRUE)
}


run_bench(
  "rw_bench.RDS",
  lidR     = lidr_rw(),
  lasR     = lasr_rw(),
  PDAL     = pdal_rw(),
  LAStools = lastools_rw()
)


#------------------------------------ convert to COPC ------------------------------------#
lidr_copc <- function() {
  # not supported
}

lasr_copc <- function() {
  pipeline <- lasR::reader() + lasR::write_copc(file_temp(ext = ".copc.laz"))
  lasR::exec(pipeline, on = in_laz)
}

pdal_copc <- function() {
  command <- paste("pdal translate", in_laz, file_temp(ext = ".copc.laz"))
  system(command, wait = TRUE)
}

lastools_copc <- function() {
  command <- paste("lascopcindex64.exe", "-i", in_laz, "-o", file_temp(ext = ".copc.laz"))
  system(command, wait = TRUE)
}


run_bench(
  "copc_bench.RDS",
    lasR     = lasr_copc(),
    PDAL     = pdal_copc(),
    LAStools = lastools_copc()
)


#------------------------------------ read + normals + write --------------------------------#
lasr_normals <- function() {
  pipeline <- lasR::reader() + lasR::geometry_features(k = 20, features = "n") + lasR::write_las(fs::file_temp(ext = ".laz"))
  lasR::exec(pipeline, on = in_laz)
}

pdal_normals <- function() {
  out_laz <- fs::file_temp(ext = ".laz")

  pipeline <- list(
    list(
      type = "readers.las",
      filename = in_laz
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
    rds_file = "normals_bench.RDS",
    lasR     = lasr_normals,
    PDAL     = pdal_normals
  )

#------------------------------------ read + classify ground + write --------------------------------#
lidr_groundcsf <- function() {
  las <- lidR::readALS(in_laz)
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
  lasR::exec(pipeline, on = in_laz)
}

pdal_groundcsf <- function() {
  out_laz <- fs::file_temp(ext = ".laz")

  pipeline <- list(
    list(
      type = "readers.las",
      filename = in_laz
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
  lasR::exec(pipeline, on = in_laz)
}

lastools_ground <- function() {
  command <- paste("lasground_new64.exe", "-i", in_laz, "-o", fs::file_temp(ext = ".laz"), "-all_returns -step 10")
  system(command, wait = TRUE)
}


run_bench(
  "ground_bench.RDS",
  lidr_groundcsf = lidr_groundcsf,
  lasr_groundcsf = lasr_groundcsf,
  pdal_groundcsf = pdal_groundcsf,
  lasr_groundptd = lasr_groundptd,
  lastools_ground = lastools_ground
)
