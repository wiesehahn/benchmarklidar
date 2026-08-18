# Copy sample point-cloud files (and their .lax sidecars) from the repo's
# data/pointclouds/ corpus into a local directory (tempdir() by default)
# so benchmarks measure processing time, not network-share read latency,
# unless a script is explicitly testing I/O itself (see
# benchmarks/drives_local-vs-network.R).
stage_sample_data <- function(source_dir = "data/pointclouds", dest_dir = tempdir()) {
  stage <- function(regexp) {
    src <- fs::dir_ls(source_dir, type = "file", regexp = regexp)
    dest <- fs::path(dest_dir, fs::path_file(src))
    to_copy <- src[!fs::file_exists(dest)]
    if (length(to_copy) > 0) {
      gb <- round(sum(fs::file_size(to_copy)) / 1024^3, 2)
      message(sprintf("Staging sample data: copying %d file(s) (%s GB) to %s ...",
                       length(to_copy), gb, dest_dir))
      fs::file_copy(to_copy, fs::path(dest_dir, fs::path_file(to_copy)))
      message(sprintf("Staging sample data: corpus now has %d file(s) staged at %s", length(src), dest_dir))
    }
    fs::path(dest_dir, fs::path_file(src))
  }

  stage("*.lax")
  stage("*.laz")
}
