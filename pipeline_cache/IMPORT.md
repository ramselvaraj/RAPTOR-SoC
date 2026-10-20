# CPU source provenance

Imported without source changes from the user's `riscv` repository,
`pipeline_cache/`, commit `3f78153caccfe90f6c95933c5294f08c8002cbbe`.
The source tree was clean at import. The upstream repository has no separate
license grant. This is the user's own code, not third-party licensed IP.

Integration additions are kept in RAPTOR-specific modules where possible.
The standalone Makefile uses a RAPTOR-local, ignored build directory.
Subsequent changes add optional D-cache bypass/address routing without changing
the default standalone configuration. Simulation assertions are guarded with
`ifndef SYNTHESIS` for DC. See `docs/PHASE5_PROGRESS.md` for results.
