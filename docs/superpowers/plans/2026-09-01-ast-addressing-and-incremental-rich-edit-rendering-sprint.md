# AST addressing and incremental rich-edit rendering — delivery plan

## Reconciliation at 2026-09-01

The current implementation has a sound full-render correctness path and a few
important precursors: linear parser range stamping, source-unchanged parser
reuse, cursor-boundary skipping, in-place rope edits, and an image adornment
pool. It does not retain a structural snapshot, assign addresses or lineages,
record per-block render ownership, or patch isolated rendered ranges. Therefore
an edit still parses and styles the complete document, while an image pool is
rotated on every source change because its key includes an absolute position.

This sprint delivers the phase-one seam without claiming partial rendering:

1. `McMarkdownDocumentSnapshot` wraps a completed parser without mutating it,
   creates canonical `/document/...` block addresses, source-based deterministic
   syntax/subtree fingerprints, and address/AST/interval indexes.
2. `McMarkdownPath` validates and prints the canonical absolute-location
   subset; `McMarkdownPathResolver` resolves generated paths. The API boundary
   deliberately permits replacing the subset resolver with the GT XPath adapter
   after its precise protocol is spiked.
3. `McRichEdit>>attachToEditor:` removes test-only instance-variable wiring.
   Styling suspension is a nesting counter, and source mutations capture a
   one-shot, size-stamped edit descriptor for the later reconciler.

## Critical gap closure sequence

| Order | Slice | Exit criterion |
| --- | --- | --- |
| 0 | GT/Bloc API probes | Establish attribute shifting, owner-scoped removal, global `styleText` clearing, dynamic adornment reattachment, XPath adapter protocol, and text-modification event payloads in attached-editor tests. |
| 1 | Snapshot completion | Add block-relative inline-map ownership and a stable byte digest if profiling needs compaction; retain exact source/equality collision confirmation. |
| 2a | Render ownership | Create `McRichEditProjectionState` and `McRichEditRenderPatch`; visit an enclosing block range, record non-overlapping write footprints, and verify each patch against the full-render oracle. Eliminate the code fence's cross-owner newline write first. |
| 2b | Cursor routing | Attribute probe boundaries to block lineages, union owner records, and patch only departed/entered block owners. Any untrusted record forces full style. |
| 3 | Reconciliation | Full parse + fresh snapshot after edits; monotonic sibling diff on kind/subtree fingerprint, source-overlap handling for modified blocks, lineages, conservative ambiguity fallback, and lineage-keyed bounded widget cache. |
| 4 | Adaptive policy | Instrument parse/projection/reconcile/attribute/layout work. Calibrate weight, dirty fraction, and damping from repeatable GT benchmarks; put deterministic counters in CI. |
| 5 | Incremental parsing | Safe parser checkpoints, reparse window expansion/convergence, persistent range/address index updates, then an independent parsing policy. |

## Mandatory safety gates

- No partial patch may enter through `editor styleText` until the Bloc global
  styler-clearing behavior is proven compatible; it needs its own transaction.
- No owners may overlap. Tables own their subordinate cell ropes wholesale;
  code-fence newline hiding must be redesigned or assigned unambiguously.
- Reconciliation uncertainty, untrusted cursor records, stale descriptors, and
  async dependency changes always select the existing full renderer.
- Image/database/link/palette/file-watch dependencies need named generations;
  syntax fingerprints never carry those mutable states.

## Verification

The current focused checks pass: `McMarkdownSnapshotTest` (5) and
`McRichEditPerfTest` (32 before the two newly added seam checks). The complete
suite should remain the merge gate once concurrent GT invocations have drained.
