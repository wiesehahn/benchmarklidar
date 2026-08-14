- run the full benchmark suite on PC026 — it's the production Threadripper
  target and so far only has drive-I/O results; PC069 now has fresh
  results (incl. a full workers_raw-to-processed.R sweep) against the
  100-tile landesbefliegung 2016 corpus
- confirm whether PC026's worker-scaling sweet spot also sits above
  "half of cores" as it did on PC069 (~1.5x logical cores was fastest
  there) — see docs/worker-scaling-findings.md
- follow-up session: extend benchmark *content* on top of the new
  structure (out of scope for this restructuring pass)
