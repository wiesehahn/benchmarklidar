# Preflight check: are the R packages and external tools this repo needs
# actually available on this machine? Run automatically once per session
# by _setup.R, or call directly any time to re-check. Missing R packages
# are installed automatically (from CRAN, r-universe for lasR, or GitHub
# for managelidar) rather than just reported.
check_environment <- function(
    pkgs = c("lidR", "RCSF", "fs", "jsonlite", "benchmarkme",
             "future", "future.apply", "mirai", "gt", "knitr"),
    special_pkgs = list(lasR = list(repos = "https://r-lidar.r-universe.dev")),
    optional_pkgs = list(managelidar = list(github = "nwfva-b4/managelidar")),
    tools = list(
      pdal     = c("pdal", "--version"),
      lastools = c("las2las64", "-version")
    )
) {
  message("Checking R packages...")
  for (p in pkgs) ensure_package(p)
  for (p in names(special_pkgs)) ensure_package(p, repos = special_pkgs[[p]]$repos)

  message("Checking optional R packages...")
  for (p in names(optional_pkgs)) ensure_package(p, github = optional_pkgs[[p]]$github)

  message("Checking external tools on PATH...")
  for (nm in names(tools)) {
    cmd <- tools[[nm]][1]
    args <- tools[[nm]][-1]
    found <- nzchar(Sys.which(cmd))
    if (found) {
      out <- tryCatch(
        paste(system2(cmd, args, stdout = TRUE, stderr = TRUE), collapse = " "),
        error = function(e) "(found on PATH, but --version failed)"
      )
      message(sprintf("  [OK     ] %-15s %s", nm, out))
    } else {
      message(sprintf("  [MISSING] %-15s not found on PATH (see R/external-tools.R::configure_lidar_tools())", nm))
    }
  }

  invisible(TRUE)
}

# Installs `pkg` if not already available, then reports OK/MISSING with
# version. `repos` installs from a non-default CRAN-like repo (e.g.
# r-universe); `github` installs via remotes::install_github().
ensure_package <- function(pkg, repos = NULL, github = NULL) {
  ok <- requireNamespace(pkg, quietly = TRUE)
  if (!ok) {
    message(sprintf("  [INSTALL] %-15s not found, installing...", pkg))
    if (!is.null(github)) {
      if (!requireNamespace("remotes", quietly = TRUE)) install.packages("remotes")
      remotes::install_github(github)
    } else if (!is.null(repos)) {
      install.packages(pkg, repos = repos)
    } else {
      install.packages(pkg)
    }
    ok <- requireNamespace(pkg, quietly = TRUE)
  }
  v <- if (ok) as.character(utils::packageVersion(pkg)) else ""
  message(sprintf("  [%-7s] %-15s %s", if (ok) "OK" else "MISSING", pkg, v))
  invisible(ok)
}
