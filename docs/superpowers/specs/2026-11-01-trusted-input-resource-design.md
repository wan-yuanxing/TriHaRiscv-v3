# Trusted-input resource reduction design

## Goal
Reduce the LUT and high-fanout carry cost of the minimum face-box board profile while preserving the B03 data movement, cache, ready/valid protocol, and all 79 model operations.

## Scope
Only the board configuration with `TRUSTED_MODEL=1` enables the reduction. The model and operator table are sealed by the board integration, so runtime input admission checks are redundant for this demonstration. Non-trusted configurations retain the existing checks.

## Architecture
`TRUSTED_MODEL` is propagated from the board top through the face system, compute system, NPU frame service/frame executor, layer executor, and model-input block. In trusted mode the model-input block:

- skips per-beat weight/quantizer/auxiliary admission comparisons;
- skips the 64-channel parameter-bound accumulation and `PARAM_BOUND` state;
- continues fetching all parameter, feature, and row data;
- continues key/cache state, row-window construction, gather, and all output handshakes;
- keeps transport, epoch, tag, response-status, address-range, and bank conflict checks.

The existing behavior is the default when `TRUSTED_MODEL=0`.

## Error handling
Transport errors, response mismatches, epoch cancellation, address alignment/range failures, and bank conflicts remain fatal in both modes. Only content-validation failures that cannot occur with the sealed model are removed from the trusted implementation.

## Verification
Run the existing B03 input/frame regression and face-system compile checks. Synthesize `triha_face_board` and compare LUT, FF, DRM, APM, distributed RAM, synthesis WNS, and fanout warnings against the 2-lane baseline. Do not claim routed timing unless a full route reaches zero unrouted nets and passes STA.
