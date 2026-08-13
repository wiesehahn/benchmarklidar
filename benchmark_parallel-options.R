
# ---------------------------------------------------------------------------------------------------------------------------- #
# ------------------------ test parallel computing --------------------------------------------------------------------------- #
library(lasR)
library(fs)

files <- dir_ls("J:/lidar/als/ni/2024/solling", glob = "*.laz")

length(files)
sum(file_size(files))

kernels <- ncores() / 8


# ---------------------------------------------------------------------------------------------------------------------------- #
# use lasRs internal multithreading engine to process concurrent files

pipeline <- reader() + write_las(ofile = path(path_temp("lasr"), "*.laz"))

time_lasr <-
  system.time(
    internal <- exec(pipeline, on = files, with = list(ncores = concurrent_files(kernels)))
  )


# ---------------------------------------------------------------------------------------------------------------------------- #
# use future.lapply

process_file <- function(file_path) {
  pipeline <- lasR::reader() + lasR::write_las(ofile = fs::path(fs::path_temp("lasr"), "*.laz"))
  ans <- lasR::exec(pipeline, on = file_path, with = list(ncores = 1))
  return(ans)
}

time_future <-
  system.time({
    future::plan(future::multisession, workers = kernels)

    future <- future.apply::future_lapply(files, process_file)
  })


# ---------------------------------------------------------------------------------------------------------------------------- #
# use mirai

process_file <- function(file_path) {
  pipeline <- lasR::reader() + lasR::write_las(ofile = fs::path("C:/Users/jwiesehahn/Downloads/temp/parallel_testing/mirai", "*.laz"))
  ans <- lasR::exec(pipeline, on = file_path, with = list(ncores = 1))
  return(ans)
}

time_mirai <- system.time({
  mirai::daemons(kernels)

  mirai <- mirai::mirai_map(files, process_file)
  results <- mirai[]

  mirai::daemons(0)
})
