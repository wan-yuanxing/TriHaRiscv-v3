# Single-bit one-hot selection diagnostic

**Goal:** Remove re-decoding of the already known one-hot forwarding selector
on the actual fetch-index -> forwarding -> branch path, without new latency.
**Architecture:** Keep exact procedural hit and priority qualification. Replace
full-vector case matching with a reverse-case on individual known select bits;
retain explicit default RF and final x0 override, including selected X/Z data.
**Tech stack:** Existing native Windows Verilog/ModelSim/PDS/GCC15.2-O2 only.

The current function already produces one-hot selects. The old exact six-bit
case may infer another decode/priority layer. A bitwise masked OR mux is common
but turns selected Z into X in RTL; reject that shortcut. Reverse-case uses
unchanged known one-hot bits and copies payload without changing X/Z data.
A parallel_case attribute is valid because procedural hit initialization and
priority resolution guarantee zero or one known bit for any index/tag X/Z.
No full_case attribute is used: default RF is explicit.

A pinned mature Verilog reverse-case/parallel_case reference and original
license/header are read under ignored build/cpu/reference-onehot. Record
revision/source hash independently; do not change names or production RTL.

- [x] Run existing24448-check parallel-read oracle in both modes on parent;
      confirm a deliberate output-corruption negative fails.
- [x] Build-only v15 from v14b changes only forwarding case representation.
- [x] Run both-mode oracle (all64 six-source match masks for31indices, unknown
      tags/index, X/Z data, RF reset/priority), plus zero-pair and ordered/IRQ.
- [x] Preserve full-base patch/22source manifest; reconstruct; fresh actual
      SRAM/Cache-on CoreMark and full images/WB/store/profile comparisons.
- [x] Independent source and original10ns/no-region physical binding review.
- [ ] Actual PDS synthesis must accept intended parallel selection; final
      six STA checks and same-candidate >4/MHz remain mandatory.
