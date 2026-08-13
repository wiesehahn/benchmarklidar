
# get sample data and make valid
library(lasR)
exec(reader() +
       set_crs(25832) +
       delete_points(filter = "ReturnNumber < 1") +
       delete_points(filter = "NumberOfReturns < 1") +
       write_las("data/*.laz"),
     on = "L:/lidar/ALS/ni/stand_2022_0513/daten/lasfilez_594000_5843000_laz.laz")


lasfiles <- dir_ls("J:/lidar/als/ni/2024/solling", type = "file", regexp = "*.laz")
in_laz <- path("data/pointclouds/", path_file(lasfiles))
to_copy <- lasfiles[!file_exists(in_laz)]
file_copy(to_copy, path("data/pointclouds/", path_file(to_copy)))