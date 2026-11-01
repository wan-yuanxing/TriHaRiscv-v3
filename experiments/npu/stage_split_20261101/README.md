# Pending stage-split timing candidate

This directory preserves the two exact RTL overrides used by the ongoing
`build/video/pds/stage_split_route_20261101` run. They are **not** in the production
filelists. Production remains the admitted `control_decode` implementation.
No routed timing closure, deployable bitstream or board acceptance is claimed.

The graph override stores the final product in its existing accumulator before
checking overflow and tensor sizes. The input override precomputes the burst-end
cursor and continuation flag in PLAN. CPU configuration, model arithmetic,
125 MHz clock and the additional 0.2 ns setup margin are unchanged.

Measured evidence before routing:

| Check | Result |
| --- | --- |
| Full model boot, real CPU/NPU, two frames and pixel display | PASS; 51,716,858 cycles, same as baseline; zero simulator errors/warnings |
| Synthesis | 43,503 LUT; 45,555 FF; 77.5 DRM; 59 APM; no latches |
| Single seed 4 placement, slow core setup | WNS -0.440 ns; TNS -8.557 ns; 89 failing endpoints |
| Previous production placement | WNS -0.603 ns; TNS -12.379 ns; 69 failing endpoints |
| Placement worst hold across all clock pairs | Slow -0.226 ns; fast -0.270 ns |

These are placement estimates, not routed signoff. See
[`docs/verification/npu/2026-11-01-face-timing-progress.json`](../../../docs/verification/npu/2026-11-01-face-timing-progress.json)
for the evidence locations and current production/candidate distinction.
`snapshot.json` records source hashes and the snapshot status; live build outputs
remain in ignored `build/` directories.

The component runners accept these overrides explicitly, for example:

```powershell
python scripts/npu/run_b03_timing_metadata.py --multiply --source experiments/npu/stage_split_20261101/b03_graph_engine_cap.v --output build/npu/multiply_snapshot_check
python scripts/npu/run_b03_timing_metadata.py --input-plan --source experiments/npu/stage_split_20261101/b03_model_input_payload.v --output build/npu/input_snapshot_check
```

Both test output directories must be new. The graph multiplication boundary test
targets this candidate; running it against the current production graph is the
intentional negative control. Adopting either source requires updating the B03
provenance manifest/admission hash and rechecking the relevant evidence.
