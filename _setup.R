# setup for benchmarks
library(fs)

# file(s) to process
# lasfile <- "data/lasfilez_594000_5843000_laz.laz"
# in_laz <- path(tempdir(), "in_laz.laz")
# if(!file_exists(in_laz)) {file_copy(lasfile, in_laz)}

# copy files from repository (Y: = network) to local (temp)
lasfiles <- dir_ls("data/pointclouds/", type = "file", regexp = "*.laz")
in_laz <- path(tempdir(), path_file(lasfiles))
to_copy <- lasfiles[!file_exists(in_laz)]
file_copy(to_copy, path(tempdir(), path_file(to_copy)))

# copy laxfiles also
laxfiles <- dir_ls("data/pointclouds/", type = "file", regexp = "*.lax")
to_copy <- laxfiles[!file_exists(path(tempdir(), path_file(laxfiles)))]
file_copy(to_copy, path(tempdir(), path_file(to_copy)))


# get external tools running from R
source("_external-tools.R")
configure_lidar_tools(conda_path = "C:/Users/jwiesehahn/AppData/Local/miniconda3",
                      lastools_path = "C:/LAStools/bin")


# get system info
get_systeminfo <- function() {
  cpu <- benchmarkme::get_cpu()

  list(
    nodename = unname(Sys.info()["nodename"]),
    os       = unname(Sys.info()["sysname"]),
    ram      = benchmarkme::get_ram(),
    cpu      = cpu$model_name,
    cores    = cpu$no_of_cores
  )
}

get_fileinfo <- function(file = in_laz) {
  list(
    filename = fs::path_file(file),
    size     = fs::file_size(file)
  )
}

run_bench <- function(rds_file, ...) {


    systeminfo <- get_systeminfo()

    # save output under data/{pcname}/
    rds_folder <- dir_create(path("data/benchmarks", systeminfo$nodename))
    rds_path <- path(rds_folder, rds_file)
    if (file_exists(rds_path)) return(readRDS(rds_path))


    exprs <- list(...)
    nms   <- names(exprs)

    timing <- matrix(NA_real_, nrow = length(exprs), ncol = 3)
    colnames(timing) <- c("user", "system", "elapsed")

    for (i in seq_along(exprs)) {
      gc()
      t <- system.time(exprs[[i]]())
      timing[i, ] <- unname(t[c("user.self", "sys.self", "elapsed")])
    }

    res <- data.frame(
      expression = nms,
      timing,
      stringsAsFactors = FALSE
    )

  # add system and file info
  attr(res, "systeminfo") <- systeminfo
  attr(res, "fileinfo") <- get_fileinfo()

  saveRDS(res, rds_path)
  res
}



# set default lasR parallel processing option
cores <- 4
lasR::set_exec_options(progress = FALSE, ncores = lasR::concurrent_points(cores))
