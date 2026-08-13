- run the full benchmark suite on PC026 — it's the production Threadripper
  target and so far only has drive-I/O results (PC069 now has fresh
  tools_comparison/lasr_stages/parallel_strategies/drives_local-vs-network
  results as of this restructuring)
- re-run the suite on PC069 against the new landesbefliegung 2016 sample
  corpus — existing PC069 results were run against the old Solling 2024
  files, which are no longer part of the sample data (still valid
  historical records, just not reflecting the current default corpus)
- run benchmarks/workers_raw-to-processed.R for real (only smoke-tested so
  far) — now has a 100-file sample corpus to stress-test the worker queue
  at high worker counts, per docs/worker-scaling-findings.md
- follow-up session: extend benchmark *content* on top of the new
  structure (out of scope for this restructuring pass)
