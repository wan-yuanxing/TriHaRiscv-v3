# Video capture MMIO endpoint

Baseline: `f3c456f`. User authorized continuing CPU/Video integration. This batch
adds the Video-owned AXI4-Lite capture endpoint and generated RTL/C ABI. The CPU
worktree currently exports its native request/tag bus but has no formal SoC
fabric. No CPU migration, branch switch, Flash, push or merge is included.

## Scope and choice

Implement the capture endpoint first, instead of importing an unfinished CPU SoC
or combining capture, display, allocation and shared arbitration in one change.
Reuse `video_three_branch_capture` unchanged. One accepted request per coordinated
port reset remains explicit. Software owns slot allocation; this endpoint only
locks the supplied slot and frame/version identity. It cannot prove the slot is
FREE or grant CPU/NPU visibility across a fabric that is not yet integrated.

The endpoint runs in the same core clock domain as capture. AXI4-Lite CDC belongs
at the later SoC boundary. Reset must be coordinated with capture, ingress and
all outstanding DMA; the ABI provides no local reset or rearm command.

## AXI4-Lite transport

32-bit little-endian address/data, four byte strobes, one write and one read
outstanding. Independently buffer AW and W in either order. Issue exactly one B
after executing a paired write; hold B/R payloads under backpressure. Capture
read data at the AR handshake, without read side effects. Concurrent read and
register write observes the pre-write state. Reset starts with all VALID low.

Decode the complete address in `0x20010000..0x2001ffff`; require word alignment.
Outside, reserved and unimplemented display/counter offsets return DECERR=3.
Writes to RO registers and invalid values/commands return SLVERR=2 without state
changes. Zero WSTRB is a no-op on implemented writable registers. Shadow words,
CONTROL and IRQ_MASK merge enabled bytes before validating reserved bits. W1C
applies only enabled bytes; reserved set bits reject the entire write. The
CAPTURE_REQUEST command requires full WSTRB and value1 (zero/full is a no-op).
Unknown accepted address/data/strobes fail closed in simulation. No AXI timeout
withdraws a published VALID. AWPROT/ARPROT are accepted but do not authorize any
extra access; address filtering and privilege enforcement remain SoC duties.

## ABI v1.0

`config/video_regs.json` is authoritative for base, version, offsets, access,
bitfields and capabilities. `scripts/video/gen_regs.py` validates it and produces
`rtl/video/include/video_regs.vh` and `sw/include/video_regs.h`; drift/malformed
configuration checks must fail. Reserved offsets are not generated as supported
features. Fixed geometry/address values remain from `video_cfg.json`.

| Offset | Name | Access / meaning |
|---|---|---|
| 000 | VERSION | RO 00010000 |
| 004 | CAPABILITIES | RO bits0 capture,1 held events,2 IRQ; value7 |
| 008 | CONTROL | RW bit0 enable new capture commands; reset0 |
| 00c | STATUS | RO bits0 enabled,1 shot_used,2 request_pending,3 dispatched,4 accepted_pending,5 completion_pending,6 sticky_fault,7 capture_port_drained |
| 010 | IRQ_MASK | RW bits0 accepted,1 completion,2 fault; reset0 |
| 014 | IRQ_PENDING | RW1C same bits; ACK also consumes the associated mailbox valid, retaining record contents |
| 018 | ERROR_CODE | RO first nonzero capture/live/protocol fault, reset0 |
| 01c | reserved | DECERR |
| 020 | CAPTURE_REQUEST | WO full-word value1 submits shadow; value0 no-op |
| 024 | CAPTURE_STATUS | RO alias of STATUS |
| 028 | ACCEPTED_FRAME_ID | RO accepted record frame_id, reset0 |
| 02c | COMPLETED_FRAME_ID | RO completion record frame_id, reset0 |
| 100 | REQUEST_SLOT | RW bits1:0, slot0..2 required at command |
| 104 | REQUEST_FRAME_ID | RW all32 bits; zero/wrap allowed, allocator owns ordering |
| 108 | REQUEST_VERSION | RW all32 bits; must match VIDEO_INPUT_PREPROCESS_VERSION at command |
| 10c/110/114 | REQUEST_RAW/PREVIEW/INPUT_BASE | RO computed from shadow slot; slot3 reads0 |
| 118/11c/120 | RAW/PREVIEW/INPUT_STRIDE | RO fixed configured strides |
| 124/128 | FRAME_WIDTH/HEIGHT | RO configured geometry |
| 12c/130 | INPUT_WIDTH/HEIGHT | RO configured storage dimensions |
| 140/144/148 | ACCEPTED_SLOT / ACCEPTED_FRAME_ID_RECORD / ACCEPTED_VERSION | RO held accepted identity; frame alias at028 |
| 14c/150/154 | ACCEPTED_RAW/PREVIEW/INPUT_BASE | RO held addresses |
| 180/184/188 | COMPLETED_SLOT / COMPLETED_FRAME_ID_RECORD / COMPLETED_VERSION | RO held completion identity; frame alias at02c |
| 18c | COMPLETED_RESULT | RO bit0 success; bits15:8 error_code |
| 190/194/198 | COMPLETED_RAW/PREVIEW/INPUT_BASE | RO held addresses |
| 19c/1a0/1a4 | COMPLETED_RAW/PREVIEW/INPUT_PIXELS | RO held counts |
| 1a8/1ac/1b0 | COMPLETED_RAW/PREVIEW/INPUT_BYTES | RO held successful-B byte counts |
| 1b4/1b8/1bc | COMPLETED_RAW/PREVIEW_CRC, FIFO_PEAK | RO held diagnostic values |

All undocumented bits read0. REQUEST_SLOT reserved bits reject writes; slot3
can be staged but cannot submit. Commands require enable, no prior shot, no
live/sticky fault and legal version/slot. Staging/CONTROL writes while a shot is
queued or active reject; after completion the shadow remains locked until reset
as shot_used remains1. IRQ_MASK and W1C stay writable. CONTROL disable may be
accepted only before a shot; it never retracts a published request.

## Capture handshake and immutable events

Queue one immutable request on a successful command write; shot_used is set
immediately. `capture_req_valid_o` and slot/frame/version hold until core ready.
Set dispatched only on that handshake. Do not gate VALID with live faults.

Accept the capture core's held accepted/completion ports into separate one-entry
mailboxes. READY depends only on the corresponding mailbox being empty; a full
mailbox backpressures its producer. New events win over same-edge W1C. Accepted
record is published at the existing first-core-PIX event, not a newly claimed
physical SOF timestamp. Completion always requires matching locked request
identity, success/code consistency and known payload. Successful completion also
requires accepted identity (including a valid accepted event on the same edge).
A legitimate failed completion may precede the first accepted PIX and retains
its known nonzero producer code. Success is the producer's three-branch/good-EOF/all-B result, not an
independent numerical or shared-master visibility proof.

Validate slot/frame/version and computed bases against the locked request.
Unknown, unsolicited, duplicate or mismatched handshakes set sticky protocol
fault E1, do not overwrite a valid historical record and request capture abort.
A malformed event is drained when READY permits, never silently treated as
success. Known legitimate failed completion is retained with its code. Incoming
live_fault/code sets the first sticky error (unknown/zero fault code maps to E1).
If multiple new causes coincide, protocol fault precedes failed completion,
then live fault. Sticky fault asserts abort_o and IRQ fault once; W1C only clears
the interrupt pending bit, never the error/abort or shot_used.

Historical completion data is immutable after capture, even under late fault.
STATUS.sticky_fault revokes live health. CPU must inspect this status and the
result, and later honor the formal fabric visibility/ownership protocol before
publishing INPUT_READY. IRQ is level `|(IRQ_PENDING & IRQ_MASK)`; mask does not
discard events. Mask and ACK writes never reset capture or drop DMA ownership.

## Implementation boundaries and verification

Module `video_capture_mmio` uses clk_i/rst_ni and *_i/*_o names; its explicit
capture ports mirror request, accepted/completion metadata and count outputs.
Geometry parameters allow small tests; production defaults800x600, padding40/40.
The synthesizable component target has no board pins or bitstream. The existing
three-board recovery target and source hashes remain unchanged.

Tests cover AW/W order and skew, B/R stalls, all byte masks, reserved/unmapped/
unaligned/RO accesses, request immutability, every legal slot, unknown inputs,
mailbox backpressure/ACK races, failure and late fault, duplicate/stale events,
first-error priority, coordinated reset and frame-id wrap. A real capture-core
integration bench proves that MMIO completion is absent until good EOF and all
three successful B responses; failed DMA drains before failure completion.
Verify generated C with installed RV32/ILP32 GCC. Run component suites, the full
Video regression, synthesis and independent spec/quality reviews. Record these
as component/digital evidence, without new physical board or CPU/fabric claims.
