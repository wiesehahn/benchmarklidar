# Acquire the sample point-cloud corpus in data/pointclouds/ from a
# network share. Run manually/occasionally — NOT part of _setup.R — since
# it needs access to the J: share specific to this machine/network (see
# README "known limitations"). Safe to re-run: skips files that already
# exist locally, and write_lax() below skips files that are already
# indexed.
#
# Source: J:/lidar/als/ni/2016/landesbefliegung — Lower Saxony's 2016
# statewide ALS campaign (~22,500 tiles total). Files here are much
# smaller than a typical forest-focused acquisition (100 tiles here total
# ~4.5GB, vs. ~13GB for the previous 33-tile Solling 2024 corpus), which
# lets the sample corpus include enough files to properly stress-test
# worker-queue scaling (see docs/worker-scaling-findings.md) while
# staying a manageable total size. A fixed random seed makes the sample
# reproducible across machines/re-runs — same 100 tiles every time.
library(fs)
library(lasR)

source_dir <- "J:/lidar/als/ni/2016/landesbefliegung"
sample_size <- 100

set.seed(42)
# glob (not type = "file") avoids a per-file stat call — this directory
# has ~22,500 entries, so type-filtering would be considerably slower.
all_files <- dir_ls(source_dir, glob = "*.laz")
sample_files <- sample(all_files, sample_size)

dest <- path("data/pointclouds", path_file(sample_files))
to_copy <- sample_files[!file_exists(dest)]
file_copy(to_copy, path("data/pointclouds", path_file(to_copy)))

# Unlike the old Solling corpus, this source directory has no .lax spatial
# index at all. Without one, lasR treats the collection as unindexed and
# auto-inserts its own write_lax() at the start of every pipeline — but
# that auto-inserted version runs on-the-fly and, per lasR's own docs,
# "cannot be run in parallel". That silently penalizes anything using
# lasR's internal concurrent_files() threading (benchmarks/parallel_strategies.R's
# lasr_internal) far more than the mirai/future.apply strategies (each
# worker only ever indexes its own single file), which is the likely
# explanation for lasr_internal flipping from fastest to slowest when the
# sample corpus switched to this unindexed source. Building the index
# once, in parallel, up front avoids paying that cost inside every
# benchmark run.
#
# overwrite = TRUE is required here even though these files have no .lax
# at all: write_lax()'s default (overwrite = FALSE, "skip if already
# indexed") appears to false-positive on this source's files — confirmed
# by testing, with overwrite = FALSE no .lax is written for any file here,
# with overwrite = TRUE it works as expected.
exec(write_lax(overwrite = TRUE), on = dest)
