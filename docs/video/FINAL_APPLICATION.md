# TriHa face application

For the board-accepted RAW, BOX and photo AVATAR modes, use the [2026-11-04 photo release and seven-segment loading instructions](../../releases/face-photo-20261104/README.md). The rest of this page describes the 2026-11-03 BOX-only milestone.

For a clean checkout, use the versioned [2026-11-03 release](../../releases/face-box-20261103/README.md).
It includes the accepted bitstream/mask, model, firmware, simulation fixtures,
physical databases and evidence. Run `python scripts/video/restore_face_release.py --install`
before the commands below. Native database replay and a complete rebuild recipe
are documented there; the original build records remain unchanged.

2026-11-03 priority: complete real face detection, simulation, routed timing
and a reproducible bitstream before connecting hardware. Frame rate is measured
but is not a release threshold. Use the explicit `--face-profile box` build
below. Avatar/landmarks do not block this milestone.

Offline acceptance completed on 2026-11-03. The current BOX package is
`build/video/releases/triha_face_board_3939c52f4d94`; keep its `.sbit` and `.smsk`
together. Its manifest binds the 50/125/40 MHz profile, real positive/negative
system simulations, the frozen routed database, all five timing categories at
both corners, 23 Gray groups / 116 bits / 928 clock observations, 140 actual
ports, and the two DDR gate sites. Worst setup is +0.183 ns and worst hold is
+0.108 ns. The package bytes and hashes were checked against the qualified
build. Subsequent board Program/Verify and model loading passed. The user
confirmed a correct face box, updated boxes after changing face position,
cleared boxes without a face, and continuing frame updates. The first-priority
functional milestone is accepted; external HDMI I/O AC is not formally signed
off and FPS has not been measured. The linked hardware evidence and verbatim
manual observations are in `build/video/face_box_board_acceptance_20261103.json`.

Bitstream SHA256:
`3939c52f4d94cd50476905a206f50ae82347f864604f4b8bb8c98a6fefd51e65`.
Verification mask SHA256:
`d3ca5bbce1a9e90e4ee1ca568df24fd1d10d78505e96ecaff1da8bad5a8997fd`.

The production application entry is `triha_face_board_top`. The default board
configuration is the CPU+B03 application with the timing-bounded CPU control
profile (`DEMO_BOX_ONLY=0`, `MINIMAL_CONTROL_CPU=1`): it connects
the existing HDMI input/output pins and DDR3 IP to `triha_face_system`:

```text
HDMI RX -> capture/preprocess -> three-slot frame pool -> CPU frame ABI
        -> B03 graph/heads -> CPU decode + NMS -> CPU BOX record -> HDMI scanout
```

The full path keeps CPU frame allocation, completion publication, display
record submission and slot retirement. The FPGA runs the graph and writes the
real cls/obj/bbox heads. The CPU reads those heads, applies the 0.6 score
threshold, decodes the B03 lookup table, performs a small IoU-0.3 NMS, clips
the restored 800x600 boxes, and submits the existing display record. This
removes the FPGA decoder, sorter, ROI and result-record writer from the board
configuration while preserving the real inference result path.

The current B03 model is bbox-only and has no valid landmark branch, so all
point fields and the landmark-valid flag remain zero. The default full-board
configuration disables hardware post-processing with
`ENABLE_HARDWARE_POST=0`; `DEMO_BOX_ONLY=1` remains an explicit TX-only
bring-up override. Setting `MINIMAL_CONTROL_CPU=0` restores the full CPU
control profile when the board timing budget permits it. The board resource
profile compares only the CPU-selected primary box in the pixel overlay; RAW
pixels, box coordinates and NPU/CPU inference work are unchanged.

The board uses a separate PLL for CPU/NPU at 50 MHz, the DDR user clock for
video at 125 MHz, and a 40 MHz pixel clock. The simulation uses the same clock
periods. Keep the existing 0.2 ns uncertainty and bounded CDC constraints.
The functional profile follows completed 100 MHz and 80 MHz routes that failed
setup. The PLL itself runs at 50 MHz (125 MHz input, I=5/M=16/F=2/O=16,
800 MHz VCO); its STA ratio is 2/5. The timing check does not accept a faster
circuit by merely relaxing its constraint. The compact video MMIO endpoint
also registers each accepted read address before decoding it. One request can
wait for the record-copy RAM; response backpressure and reset preserve AXI
ordering. This removes the upstream address bus from same-cycle ready/response
control without changing the software ABI.

The Verilog default retains the full avatar application. The build profile
`box` explicitly sets `ENABLE_AVATAR=0`, `ENABLE_MINIMAL_BOX=1`, and
`DEMO_BOX_ONLY=0`. This uses real inference and displays the primary face
rectangle. The CPU still decodes/NMSes the complete candidate set in pages;
only the pixel renderer is limited to the primary box. With no mode key,
firmware selects BOX before capture. The `avatar` profile retains the cache,
KEY1 mode control and seven-segment boot. Its three additional timing commands
are in `triha_face_avatar.fdc`; all shared timing commands remain unchanged.

Native environment used for the current recovery:

```powershell
$env:TRIHA_RISCV_GCC='D:/xpack-riscv-gcc/xpack-riscv-none-elf-gcc-15.2.0-1/bin/riscv-none-elf-gcc.exe'
$env:TRIHA_VSIM='D:/modeltech64_10.5/win64/vsim.exe'
python -m pip install --target build/python-deps --only-binary=:all: -r config/face_python_requirements.txt
$env:PYTHONPATH="$PWD/build/python-deps"
python scripts/video/doctor.py
python scripts/video/prepare_reference.py --reference hdmi
python scripts/video/prepare_reference.py --reference ddr
python scripts/video/prepare_reference.py --reference key
```

Dependencies stay in ignored `build/`; no global Python environment is replaced.
The upstream checkout must be at `558280b30219acdcf9f962acd6e907e0f680ab52`.
On a fresh workspace, restore the generated model inputs as follows (outputs
must be new directories):

```powershell
python scripts/npu/recover_format1_assets.py --npu-root build/sources/npu_zgtc --output build/npu/recovered_format1
python scripts/npu/prepare_b03_assets.py --output build/npu/b03_assets_20261030 --npu-root build/sources/npu_zgtc --search-root build/npu/recovered_format1 --python D:/anaconda3/python.exe
python scripts/npu/prepare_natural_face.py --image build/npu/lena.jpg --output build/npu/face_fixture_20261103
```

Use OpenCV 4.10.0 `samples/data/lena.jpg`; the fixture generator enforces its
SHA256. The recovery audit can return `PARTIAL` because historical scene/log
artifacts are unavailable. Inspect `recovery_report.json`: require
`core_ready=true`, the zero/full255/pattern runtime cases ready, and the admitted
hashes to match. This does not restore or claim the missing historical scenes.

Use the digital final-application regression while the board target is being
closed:

```powershell
python scripts/soc/run_face_system.py --board-profile --boot-load --fixture build/npu/face_fixture_20261103
```

The regression exercises real CPU firmware, capture/preprocess, the B03 graph,
the shared DDR proxy, CPU result reads, same-frame BOX pixels, three-slot
holding, retirement and reuse. Its result is not a board or timing claim.

The fixture directory contains the independently prepared natural-face image
and reference HEAD data. The board-profile boot regression also sends all six
model segments through the actual loader before admitting the CPU. Without
these options, the runner's preloaded/default configuration is a separate test.

The BOX test now requires BOX selection before the first capture and verifies
the visible two-pixel rectangle on each complete 800x600 output frame. A run
that stays in RAW cannot pass. The one-face fixture is a functional reference,
not a detection-accuracy benchmark.

Build using the exact `firmware.elf` from the passing full-system run:

```powershell
python scripts/video/build_pds.py --target triha_face_board --face-profile box --stage route --seed-start 4 --seed-count 1 --pnr-mode normal --plc-decongestion 3 --firmware-elf build/soc/face_system-POSITIVE_RUN/firmware.elf
```

Replace `face_system-POSITIVE_RUN` with that run's actual directory. The ELF includes
test-layout constants, but executes the production application. Keep the
bitstream, firmware and simulation bound to the same source snapshot.
Also run the six-segment regression without `--fixture` for the negative scene.
After the physical build and both simulations finish, use their exact output
directories (each review/output directory below must be new):

```powershell
$build='build/video/pds/BUILD_RUN'
python scripts/video/review_face_route.py --base $build --route $build --output build/video/face_review_RUN
python scripts/video/check_face_gray_clocks.py --review build/video/face_review_RUN/result.json --output build/video/face_clocks_RUN
python scripts/video/test_face_route_audit.py --base $build --review build/video/face_review_RUN --clock-review build/video/face_clocks_RUN --output build/video/face_audit_controls_RUN.json
python scripts/video/qualify_face_bitstream.py --base $build --placement $build --route $build --review build/video/face_review_RUN --clock-review build/video/face_clocks_RUN --positive build/soc/face_system-POSITIVE_RUN --negative build/soc/face_system-NEGATIVE_RUN --output build/video/face_qualified_RUN --generate
python scripts/video/package_board.py --target triha_face_board
```

The qualification step rejects any failing setup/hold/recovery/removal/pulse
table, incomplete Gray-bit coverage, source or firmware mismatch, unexpected
critical warning, or changed physical pin/site. It preserves earlier failed
build records and generates the `.sbit`/`.smsk` only after internal acceptance.
The Gray audit bounds every bit's delay together with early/late launch and
capture clock spread; a PDS `All Constraints Met` line alone is insufficient
because this installed version can omit its max-skew assertions from that line.
If PDS inserts a physical feed-through on a Gray bit, the review exports a
functional netlist from that same routed database. Only an identity `V_BUF`
chain connecting the exact source Q to destination D may pass; its physical
sites and level count must match STA, and the reviewed primitive, netlist and
database hashes are bound together. The complete buffered delay remains in
the original bound. `python scripts/video/test_face_gray_netlist.py` covers
inversion, wrong-bit wiring, extra logic, loops and changed evidence.

If the mapped design is valid but its physical implementation misses timing,
`reroute_face.py` can run a new placement and route from the frozen database:

```powershell
$route='build/video/pds/face_reroute_RUN'
python scripts/video/reroute_face.py --base $build --output $route --seed 5 --mode performance --decongestion 3
```

Then pass `$route` as `--route` to the review, and as both `--placement` and
`--route` to qualification. Keep `--base $build` unchanged. Use fresh review,
clock-review and qualification directories for every routed database. A failed
route or a passing audit-control test never authorizes bitstream generation.

For a small measured routing miss, keep the existing placement with
`--placement $build --priority-constraints path/to/critical_nets.rcf --mode normal`.
The optional RCF accepts only unique `def_route -prior_net {exact mapped net}`
commands; it cannot relax timing constraints. Bind those names to the failed
route report. In this case qualification still uses `--placement $build`,
and `--route` points to the new routing output. All final timing and Gray-clock
checks must be repeated on the new database.

PDS supports only one RCF per project. The runner combines the original two
DDR clock routing priorities and any application priorities into one generated
`routing.rcf`. It stops immediately if PDS replaces or rejects a routing
constraint. Run `python scripts/video/test_face_reroute_constraints.py` to
check this admission behavior. Earlier failed multi-RCF trials are historical
evidence and are not qualified implementations.

If hold violations remain, `--hold-iterations 30 --hold-margin-ps 100` asks PDS
to repair them toward 100 ps positive slack, with up to 30 iterations. These
are physical optimization controls, not relaxed STA constraints. The margin
option also sets the documented clock-tree hold-repair threshold and explicitly
enables repair during routing; all original clock uncertainties remain intact.

The current board profile keeps `MINIMAL_CONTROL_CPU=1` and `CACHE_ENABLE=0`,
retaining the existing instruction functionality. It disables the board's cache
path, branch prediction and selected bypasses; it must not be described as the
full CPU performance configuration. These are existing board defaults, not new
reductions introduced by the vector/control timing changes. NPU defaults are
`M_LANES=2`, `QUANTIZER_LANES=1` and `TRUSTED_MODEL=1`.
The timing work adds the existing extra decode pipeline stage. Its performance
evidence is the application regression, not a general CPU benchmark.

The user connected the board after offline acceptance on 2026-11-03. The
qualified image passed volatile JTAG Program/Verify on PG2L100H / 00602899;
see `build/video/board_program/20261103T112808_536586Z`. The user installed the
missing CP210x driver, and the board UART is COM12. The six model segments
(1,770,496 bytes / 6,916 packets) were acknowledged with zero retries and a
final seal acknowledgement; see `build/soc/model_upload-20261103T113330_193913Z`.
Visible HDMI/inference acceptance subsequently passed by the user's positive,
changed-position and no-face observations. The board remains running. After
power loss, repeat volatile JTAG configuration and the six-segment model load.
For any deployment, require
a source-bound build with the application ELF, completed routing, and passing
setup, hold, recovery, removal and pulse-width checks at both corners. Placement
estimates and global routing with zero remaining nets are intermediate results.
The current run and pending work are recorded in `docs/video/STATUS.md`.
Also review numeric Gray-pointer max-skew results and the DDR PHY gate sites.
The historical avatar route timeout is not a BOX implementation result.

For the later board session, use the matching `.sbit` and `.smsk` for volatile
JTAG Program/Verify, reset the board, wait for DDR calibration, and then upload
the model through the explicitly selected USB serial port:

Connect an HDMI source configured for **800x600 at nominal 60 Hz**, plus an
HDMI display and USB serial. The configured raster uses a 40 MHz pixel clock,
1056 horizontal clocks and 628 lines, with positive HS/VS. The fixed HDMI
video mode is independent of inference throughput; relaxing the inference FPS
target does not enable arbitrary HDMI input resolutions. Use a visible face
and then a scene without a face for the first hardware checks.

```powershell
# This command audits local assets without opening a serial port.
python scripts/soc/upload_face_model.py --model-only
# Replace COMx with the connected board's actual serial port when ready.
python scripts/soc/upload_face_model.py --model-only --port COMx
```

For the BOX bitstream, `--model-only` is required (the uploader's default is
seven segments for the avatar profile). The uploader defaults to 115200 baud and records the exact six segment hashes,
packet count and acknowledged cursor. A final loader acknowledgement permits
capture/inference/display admission; it alone does not prove face detection or
HDMI output. The current display shows the CPU-selected primary face box.
External HDMI I/O AC timing and actual DDR/HDMI operation remain board acceptance
items separate from internal STA.
