# Acquire the sample point-cloud corpus in data/pointclouds/ from network
# shares. Run manually/occasionally — NOT part of _setup.R — since it
# needs access to L:/J: shares specific to this machine/network (see
# README "known limitations"). Safe to re-run: both steps skip files that
# already exist locally.
library(fs)
library(lasR)

# One reference tile: fix CRS and drop invalid-return points before adding
# it to the sample corpus.
exec(reader() +
       set_crs(25832) +
       delete_points(filter = "ReturnNumber < 1") +
       delete_points(filter = "NumberOfReturns < 1") +
       write_las("data/pointclouds/*.laz"),
     on = "L:/lidar/ALS/ni/stand_2022_0513/daten/lasfilez_594000_5843000_laz.laz")

# Batch of real ALS tiles used as the main benchmark corpus.
lasfiles <- dir_ls("J:/lidar/als/ni/2024/solling", type = "file", regexp = "*.laz")
dest <- path("data/pointclouds", path_file(lasfiles))
to_copy <- lasfiles[!file_exists(dest)]
file_copy(to_copy, path("data/pointclouds", path_file(to_copy)))
