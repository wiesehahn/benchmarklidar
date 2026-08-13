# Compare lidR vs lasR for a ground-classify + custom intensity-normalize
# + write pipeline. Both run against the same single representative file.
source("_setup.R")

bench_file <- pick_representative_file(in_laz)
set_fixed_thread_baseline(cores = 4)

# function to normalize intensity
normalize_intensity <- function(data) {

  lower_pct = 0.01
  upper_pct = 0.99

  min_val <- 0
  max_val <- 2^16 - 1

  i <- data$Intensity

  # Compute percentiles
  lower <- quantile(i, probs = lower_pct, na.rm = TRUE)
  upper <- quantile(i, probs = upper_pct, na.rm = TRUE)

  # Scale intensities based on percentiles
  i <- (i - lower) / (upper - lower) * (max_val - min_val) + min_val

  # Clip values to min/max
  i[i < min_val] <- min_val
  i[i > max_val] <- max_val

  # Convert to integer
  data$Intensity <- as.integer(round(i))

  return(data)
}

# classify ground and normalize intensities in lidR
lidr_ground_intensity <- function() {
  library(lidR)
  bench_file |>
    readALS() |> classify_ground(csf()) |>
    normalize_intensity() |>
    writeLAS(lasR::templas())
}

# classify ground and normalize intensities in lasR
lasr_ground_intensity <- function() {
  call_normalize_intensity <- lasR::callback(normalize_intensity, expose = "i")
  pipeline <- lasR::reader() + lasR::classify_with_csf() + call_normalize_intensity + lasR::write_las()
  lasR::exec(pipeline, on = bench_file)
}

run_bench(
  "lidr-lasr_ground-intensity.RDS",
  lidR = lidr_ground_intensity,
  lasR = lasr_ground_intensity,
  fileinfo = get_fileinfo(bench_file)
)
