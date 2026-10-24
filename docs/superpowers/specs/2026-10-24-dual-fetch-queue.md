# Dual fetch queue closure experiment

Continue the authorized six-stage dual CPU >4/MHz and actual100MHz target in
the existing isolated Windows worktree. Production RTL and integration remain
unchanged; all candidates are reconstructed patches under build/cpu.

The actual SRAM1253888cycle interval has361315 response-backpressure cycles,
303185 with concurrent dequeue. Queue occupancy0..4 is61662/187899/643012/
314383/46932. Frontend stalls split61662empty and20554PC mismatch. These are
opportunity counts, not saved cycles. Removing WAW checks cannot help this run:
the measured WAW-only opportunities are zero.

Three options were considered: pop-dependent combinational accept, deeper
storage, or fixed-entry compaction. Pop-dependent accept adds a reverse path
from late issue through fetch control, conflicting with current timing work.
Use fixed-entry compaction first with identical capacity and behavior, then
independently measure six-word storage with conservative registered-count
accept. No additional main pipeline stage or bypass/issue rule changes.

For each fixed destination, surviving payload comes only from itself, the
next word, or two words ahead. B-only removal keeps head0 and shifts entries
after1. Appends compare the remaining count to each fixed destination; no
dynamic destination array write is needed. PC/data/info/CSR history move
together. Flush only clears count, reset clears stored payload; inactive
entries retain their previous content exactly as the existing compact FIFO.
The existing two-output interface and cross-packet contiguous-PC rule stay.

The existing original upstream FIFO is the reference for bounded count,
push/pop handshakes and separate validity/data. Cross-packet compaction is
the local adaptation; do not claim this whole algorithm is copied upstream.
Source provenance and licenses stay intact. An independent word-stream
oracle covers order, sidebands, B-only, one/two-word push, full/flush and
random simultaneous operations. Unknown pop/pred inputs require explicit
comparison with the existing procedural semantics, not an assumed two-state
rewrite. No uninitialized payload may create a request.

Same-capacity candidate must reproduce complete SRAM and Cache-on measured
streams and cycles. The deeper candidate must preserve the program/images,
CRC and normalized architectural data/store streams; timestamps may change
only at the validated cycle reads and matching started storage. Both need
fresh original10ns/IO/hold/multicorner postroute checks before admission.
