# Puts PDAL and LAStools on PATH for this R session. Defaults are this
# repo's dev setup — override both args for your own machine (see README).
configure_lidar_tools <- function(
    conda_path = "C:/miniconda3",
    lastools_path = "C:/LAStools/bin"
) {
  paths <- strsplit(Sys.getenv("PATH"), .Platform$path.sep)[[1]]

  add_path <- function(p) {
    if (!is.null(p) && !p %in% paths) {
      paths <<- c(p, paths)
      message("  added to PATH: ", p)
    }
  }

  add_path(file.path(conda_path, "Scripts"))
  add_path(file.path(conda_path, "Library", "bin"))
  add_path(lastools_path)

  Sys.setenv(PATH = paste(paths, collapse = .Platform$path.sep))
  invisible(TRUE)
}
