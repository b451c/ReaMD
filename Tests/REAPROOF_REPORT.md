# ReaProof U7 authoring report — ReaMD (interactive mode, 2026-07-16)

Protocol: ReaProof `docs/AGENT_TEST_AUTHORING.md`. User checkpoint decisions:
priorities = pure logic + REAPER E2E + AI Parse; permanent D26 seam allowed;
tests live in this repo. Manifest: `../reaproof_features.json` (validated by
`reaproof features-report`, anti-fabrication checks on).

## Landed
- `Tests/test_parser_gaps.lua` — 5 tests: TABLE nodes (incl. escaped-pipe
  v1.1.0 fix) + STRIKETHROUGH, both previously untested. 5/5.
- `Tests/test_sidecar_config.lua` — 8 tests: .reamd sidecar v3 round-trip,
  v2->v3 GUID migration, corrupt-file refusal, legacy marker strip, Config
  type-validation/persistence/recents-MRU. 8/8.
- `Tests/test_e2e_reaproof.py` — 2 REAPER E2E via the new permanent seam:
  open-file (state model + window) and time:// link (edit-cursor effect, with
  a second-timestamp mutation) + seam-inert-without-flag negative control.
  2/2, run twice.
- **Permanent D26 seam** in `Main/ReaMD.lua` (ExtState-gated, inert in
  production) exposing state + 7 file-local entry points.

## REAL BUG found and fixed
`ScenarioEngine.strip_reamd_marker` built its gsub pattern from marker strings
containing unescaped `-` (Lua-pattern quantifier) — it NEVER matched a real
marker, so legacy embedded blocks were silently left in opened files. Fixed
with proper pattern escaping (`Libs/scenario_engine.lua`), guarded by
`test_sidecar_config.lua`.

## Honest tail
- Pre-existing red (not introduced here): `Tests/test_scenario.lua:201`
  "link_fragment updates existing fragment" fails on current master.
- spec-needed (7): v3 item linking, playback highlight, auto-link-by-item,
  export-to-regions, AI-parse polling (+ plaintext-API-key finding), search,
  save flow — all mapped with oracles in the manifest.
- untestable-this-round (4): the ImGui visual layer, deprioritized at the
  user checkpoint.

Re-run: `cd Tests && lua test_parser_gaps.lua && lua test_sidecar_config.lua`
and `PYTHONPATH=$REAPROOF/src pytest Tests/test_e2e_reaproof.py -q`.
