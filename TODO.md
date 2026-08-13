- run the full benchmark suite on PC026 — it's the production Threadripper
  target and so far only has drive-I/O results (PC069 now has fresh
  tools_comparison/lasr_stages/parallel_strategies/drives_local-vs-network
  results as of this restructuring)
- run benchmarks/workers_raw-to-processed.R for real (only smoke-tested so
  far) — needs a larger file set than the 33-tile sample corpus to properly
  stress-test the worker queue at high worker counts (100+ files per
  docs/worker-scaling-findings.md)
- follow-up session: extend benchmark *content* on top of the new
  structure (out of scope for this restructuring pass)
- managelidar cleanup: remove dev/benchmark_workers.R and
  dev/BENCHMARK_HANDOFF.md there after confirming this migration —
  separate repo, needs explicit go-ahead
