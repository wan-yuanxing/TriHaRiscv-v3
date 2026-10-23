# D Cache response/request overlap

The user approved optimizing cache-hit throughput after the write-back
checkpoint `43e0428`. Reuse the existing isolated CPU worktree and preserve
backup `cpu-before-dcache-overlap-20261022`. Do not modify the main worktree,
the deployed board image, compiler/predictor, six-stage single-issue CPU,
cache geometry, write-back policy, or 100MHz timing constraints.

## Bounded design

Allow a new request to be accepted during a successful cached-load RESPONSE
cycle. The old response data, error and tag remain registered and visible
until the acceptance edge. At that edge, synchronous tag/data read ports
sample the incoming address and the request payload replaces the completed
one; the next cycle performs its normal lookup. No load-data register is
removed, and no RAM-to-CPU bypass is introduced.

STORE_UPDATE remains a separate completion cycle without new acceptance.
This avoids read-first data collisions and stale dirty-bit observations on
same-set store/read or store/miss combinations. Error responses, uncached
responses and maintenance responses remain conservative. A refill or dirty
writeback never overlaps a second outstanding lower transaction.

The existing FIFO depth and response-owner interfaces remain unchanged.
FENCE.I may consume the newly available slot to inject its existing internal
flush, but the previous CPU response must still be delivered once, with its
original tag. Its internal flush acknowledgement remains hidden from CPU.

## Alternatives considered

1. Successful load response overlap: smallest behavioral change, preserves
   register boundaries and provides a directly measurable benefit.
2. Also accept during STORE_UPDATE: could remove more bubbles but requires
   same-set hazards or forwarding; defer until the first change is measured.
3. Remove the load return register: previously failed actual 100MHz timing;
   excluded from this task.

## Acceptance

First reproduce a missing-overlap failure on the parent using an independent
memory oracle. Require old data/tag stability during overlap, a correct
next-address lookup, hit/miss and error transitions, byte-store ordering,
private/shared attributes, and maintenance/FENCE.I ownership. The same O2
CoreMark payload must have matching CRC and normalized WB/store traces with
lower cycles. CPU-only and cache resources are separate. Admit a release only
after unchanged-constraint actual post-route timing passes in both corners.
If the candidate has no useful measured benefit or fails its physical gate,
preserve the accepted write-back release and record the actual result.
