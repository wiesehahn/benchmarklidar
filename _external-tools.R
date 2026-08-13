# configuration to make PDAL and LAStools work
# add to path


configure_lidar_tools <- function(
    conda_path = "C:/Users/jwiesehahn/AppData/Local/miniconda3",
    lastools_path = "C:/LAStools/bin"
) {
  paths <- strsplit(Sys.getenv("PATH"), .Platform$path.sep)[[1]]

  add_path <- function(p) {
    if (!is.null(p) && !p %in% paths)
      paths <<- c(p, paths)
  }

  add_path(file.path(conda_path, "Scripts"))
  add_path(file.path(conda_path, "Library", "bin"))
  add_path(lastools_path)

  Sys.setenv(PATH = paste(paths, collapse = .Platform$path.sep))
  invisible(TRUE)
}


# make pdal and lastools work
# install miniconda
# install pdal (run `conda install -c conda-forge pdal` from anaconda prompt)
# install lastools
# configure_lidar_tools()
#
# Test if it works
# system("pdal --version")
# system("las2las64.exe -version")
