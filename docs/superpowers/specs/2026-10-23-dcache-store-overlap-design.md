# D Cache store response overlap

The user approved the next optimization on 2026-10-23: first measure the
prepared load-overlap image on hardware, then overlap safe store completions.
Parent commit `febadb3`; preserve tag `cpu-before-store-overlap-20261023`.
Reuse the existing CPU worktree and Windows tools. Six-stage single-issue,
GCC15.2 `-O2`/no-LTO, cache sizes/policy and all 100MHz constraints stay fixed.

## Bounded design

During successful private cached STORE_UPDATE, accept an ordinary next load
or store only when its set differs from the completing store's set. The
synchronous read port samples the new address while the write port updates
the old bytes and dirty tag. The old response tag remains visible until the
edge, then normal request capture selects LOOKUP. Same-set requests wait for
the normal IDLE acceptance edge, even when their word or tag differs. This
conservative rule avoids all read-first tag/data collisions without forwarding.

Maintain the prior successful cached-load response overlap. Uncached/error
responses and maintenance remain serialized; do not introduce acceptance of
FENCE.I flush/line clean/invalidate on a store-update edge. No posted external
write, dirty data forwarding, RAM-to-CPU load bypass or extra load stage is
introduced. Store ACK and dirty updates still occur on the same original edge.
Old data/address/tag/way must not be replaced before that edge.

## Alternatives and selection

- Different-set store overlap is selected as the smallest next increment.
- Same-set overlap with data/tag forwarding is deferred: a wider collision and
  dirty-bit forwarding network adds correctness and physical cost.
- Removing the load register is excluded by the accepted physical boundary.

## Validation and gates

First capture actual 5000-iteration parent-image CoreMark and preserve raw UART,
Program/Verify and complete immutable package bindings. Never claim a model
score is a board measurement. No long KEY0 hold or Flash operation is required.
If board access is unavailable, record the condition and continue independent
RTL tests without inventing a board result.

A public-interface self-check must fail on `febadb3` for missing different-set
store overlap before RTL changes. Cover load/store successors, both ways,
byte writes, same set with same/different words/tags, dirty victim failure and
retry, shared/explicit uncached successors, maintenance and ordered responses.
Use the existing RAM model's synchronous read-first behavior, not an ideal RAM.
Retain all prior load-overlap and FENCE.I tests and corruption rejection.

Run real CPU/cache/SoC/native DDR and digital two-boot/fault tests, followed by
same-payload five-iteration CoreMark and complete normalized WB/store comparison.
Profile store-edge and load-edge acceptance separately. Memory event counts
must match; cycle reductions must come from real accepted transactions.

Only pursue full implementation if the benefit is measurable. Check native
CPU-only and cache/transport resource overhead separately, then admit a new
image only after unchanged-constraint Slow/Fast final setup/hold/MPW and all
CDC checks pass. Preserve the physically admitted parent on failure or no gain.
Any deployment of the new store-overlap candidate follows its completed gates.

## Outcome

Completed 2026-10-23. Parent board capture passes at249.743516780CoreMark.
Store candidate functionality and same-payload comparison pass, but modeled
throughput+0.73387994% costs+64CPU/+9cacheLUT, reducing CPU-LUT efficiency
0.24724444%. No candidate PNR or deployment. Production restored to `febadb3`;
validated replay patch and evidence are in `docs/verification/cpu/` and build.
