"""Guard the physical face-board clock contract.

The DDR user interface and video fabric are 125 MHz.  The CPU/B03 compute
fabric is a separate 50 MHz domain; the reusable SoC already contains CDC
bridges for that boundary.  This test keeps the board wrapper and metadata
from silently collapsing the two domains back onto one clock.
"""
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def test_face_board_declares_split_clock_contract():
    manifest = json.loads(
        (ROOT / "fpga/pg2l100h/project/triha_face_board.json").read_text(
            encoding="utf-8"
        )
    )
    contract = manifest["clock_contract"]
    assert contract["core_hz"] == 125_000_000
    assert contract["compute_hz"] == 50_000_000
    assert contract["pixel_hz"] == 40_000_000


def test_face_board_wires_compute_and_video_to_distinct_domains():
    top = (ROOT / "fpga/pg2l100h/rtl/triha_face_board_top.sv").read_text(
        encoding="utf-8"
    )
    assert "triha_compute_pll" in top
    assert ".core_clk(ddr_clk)" in top
    assert ".compute_clk_i(compute_clk)" in top
    assert ".video_clk_i(ddr_clk)" in top
    assert ".compute_clk_i(core_clk)" not in top
    assert ".video_clk_i(core_clk)" not in top


def test_video_side_ports_stay_in_ddr_domain():
    top = (ROOT / "fpga/pg2l100h/rtl/triha_face_board_top.sv").read_text()
    for instance, clock_port in [("ingress", "core_clk"), ("capture_register", "clk"),
                                 ("boot_uart_rx", "clk_i"), ("boot_uart_tx", "clk_i")]:
        ports = re.search(r"\b" + instance + r"\s*\((.*?)\);", top, re.S)[1]
        assert f".{clock_port}(ddr_clk)" in ports, instance + " crosses directly into video"
    assert "BOOT_UART_DIVISOR=(125_000_000+UART_BAUD/2)/UART_BAUD" in top


def test_clock_separation_does_not_hide_all_cross_domain_paths():
    fdc = (ROOT / "fpga/pg2l100h/constraints/triha_face_board.fdc").read_text()
    for line in fdc.splitlines():
        assert not ("set_clock_groups" in line and "compute_clk" in line)
    assert "set_clock_uncertainty 0.2 -from [get_clocks {compute_clk}]" in fdc


def test_board_profile_simulates_the_actual_compute_frequency():
    bench = (ROOT / "tb/soc/tb_face_system.sv").read_text()
    assert "always #10 compute_clk_i=~compute_clk_i;" in bench


def test_pll_recipe_and_sta_describe_the_same_physical_50_mhz():
    recipe = json.loads((ROOT/'fpga/pg2l100h/ip/triha_compute_pll.json').read_text(encoding='utf-8'))
    actual = recipe['reference_hz'] * recipe['feedback_multiplier'] * recipe['feedback_divider']
    actual /= recipe['input_divider'] * recipe['output_divider']
    assert actual == recipe['compute_hz'] == 50_000_000
    fdc = (ROOT/'fpga/pg2l100h/constraints/triha_face_board.fdc').read_text(encoding='utf-8')
    command = next(line for line in fdc.splitlines() if line.startswith('create_generated_clock -name {compute_clk}'))
    assert '-multiply_by {2} -divide_by {5}' in command

