

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

# classifiy ground and normalize intensities in lidR
library(lidR)
system.time({
  ans_lidr <- lasfile |> 
    readALS() |> classify_ground(csf()) |> 
    normalize_intensity() |> 
    writeLAS(lasR::templas())
})

# classifiy ground and normalize intensities in lasR
library(lasR)
call_normalize_intensity <- callback(normalize_intensity, expose = "i")
pipeline <- reader() + classify_with_csf() + call_normalize_intensity + write_las()

system.time({
  ans_lasr <- exec(pipeline, on = lasfile)
})