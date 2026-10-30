#!/usr/bin/env python3
"""Render selected ModelSim VCD signals as publication-ready digital waveforms."""
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Dict, List, Tuple

import matplotlib.pyplot as plt
from matplotlib import font_manager
from matplotlib.ticker import FuncFormatter


def parse_vcd(path: Path):
    ids: Dict[str, str] = {}
    widths: Dict[str, int] = {}
    values: Dict[str, str] = {}
    traces: Dict[str, List[Tuple[int, str]]] = {}
    time = 0
    for raw in path.read_text(errors="replace").splitlines():
        line = raw.strip()
        if line.startswith("$var"):
            p = line.split()
            ident, width = p[3], int(p[2])
            name = " ".join(p[4:-1])
            ids[name] = ident
            widths[ident] = width
            values[ident] = "x"
            traces[name] = []
        elif line.startswith("#"):
            time = int(line[1:])
        elif line and line[0] in "01xz":
            ident = line[1:].strip()
            if ident in values:
                values[ident] = line[0]
                for name, code in ids.items():
                    if code == ident:
                        traces[name].append((time, values[ident]))
                        break
        elif line.startswith("b"):
            parts = line.split()
            if len(parts) == 2 and parts[1] in values:
                ident = parts[1]
                values[ident] = parts[0][1:]
                for name, code in ids.items():
                    if code == parts[1]:
                        traces[name].append((time, values[ident]))
                        break
    return traces


def trim(traces, names, start=None, end=None):
    points = [t for n in names for t, _ in traces.get(n, [])]
    if not points:
        raise ValueError("no selected signals in VCD")
    lo = min(points) if start is None else start
    hi = max(points) if end is None else end
    out = {}
    for name in names:
        seq = [(t, v) for t, v in traces.get(name, []) if lo <= t <= hi]
        if seq and seq[0][0] > lo:
            before = [(t, v) for t, v in traces.get(name, []) if t < lo]
            seq.insert(0, (lo, before[-1][1] if before else "0"))
        out[name] = seq
    return lo, hi, out


def render(path, out, title, names, labels, start=None, end=None):
    traces = parse_vcd(path)
    lo, hi, data = trim(traces, names, start, end)
    fig, axes = plt.subplots(len(names), 1, sharex=True, figsize=(15, 0.46 * len(names) + 1.45),
                             gridspec_kw={"hspace": 0.06})
    if len(names) == 1:
        axes = [axes]
    for ax, name in zip(axes, names):
        seq = data[name]
        if not seq:
            ax.text(0.5, 0.5, "signal absent", ha="center", va="center")
            continue
        numeric = []
        for t, v in seq:
            try:
                numeric.append(int(v, 2) if len(v) > 1 else int(v))
            except ValueError:
                numeric.append(float("nan"))
        is_scalar = all(v in (0, 1) for v in numeric if v == v)
        if is_scalar:
            ax.step([t for t, _ in seq], numeric, where="post", color="#174a7e", linewidth=1.35)
            ax.set_ylim(-0.2, 1.2)
            ax.set_yticks([0, 1])
            ax.set_yticklabels(["0", "1"], fontsize=7)
        else:
            ax.step([t for t, _ in seq], numeric, where="post", color="#174a7e", linewidth=1.0)
            ax.yaxis.set_major_locator(plt.MaxNLocator(3))
            ax.tick_params(axis="y", labelsize=7)
        ax.set_ylabel(labels.get(name, name), rotation=0, ha="right", va="center", fontsize=8)
        ax.grid(axis="x", color="#d9e2ec", linewidth=0.6)
        ax.spines[["top", "right", "left"]].set_visible(False)
        ax.tick_params(axis="y", length=0)
    axes[-1].set_xlim(lo, hi)
    axes[-1].xaxis.set_major_formatter(FuncFormatter(lambda x, _: f"{x/1000:.1f}"))
    zh = font_manager.FontProperties(fname=r"C:\Windows\Fonts\simhei.ttf")
    axes[-1].set_xlabel("仿真时间 / ns", fontsize=9, fontproperties=zh)
    fig.suptitle(title, fontproperties=zh, fontsize=12, fontweight="bold", y=0.995)
    fig.text(0.995, 0.005, f"源文件：{path.name}（ModelSim WLF 导出 VCD）", ha="right", va="bottom", fontsize=7, color="#555555", fontproperties=zh)
    fig.subplots_adjust(left=0.18, right=0.985, top=0.96, bottom=0.08)
    out.parent.mkdir(parents=True, exist_ok=True)
    fig.savefig(out, dpi=220, facecolor="white")
    plt.close(fig)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--video-vcd", type=Path, required=True)
    ap.add_argument("--npu-vcd", type=Path, required=True)
    ap.add_argument("--out-dir", type=Path, required=True)
    args = ap.parse_args()
    video = ["capture_req_valid_o", "capture_req_ready_i", "awvalid", "awready", "wvalid", "wready", "bvalid", "bready", "capture_port_drained_i", "completion_valid_i", "completion_success_i", "irq_o", "cycles", "checked_bytes"]
    vlabels = {"capture_req_valid_o":"capture req valid", "capture_req_ready_i":"capture req ready", "awvalid":"AW valid", "awready":"AW ready", "wvalid":"W valid", "wready":"W ready", "bvalid":"B valid", "bready":"B ready", "capture_port_drained_i":"port drained", "completion_valid_i":"completion valid", "completion_success_i":"completion success", "irq_o":"IRQ", "cycles":"cycles", "checked_bytes":"checked bytes"}
    npu_control = ["s_axi_awvalid_i", "s_axi_awready_o", "s_axi_wvalid_i", "s_axi_wready_o", "s_axi_bvalid_o", "s_axi_bready_i", "m_axi_arvalid_o", "m_axi_arready_i", "m_axi_rvalid_i", "m_axi_rready_o", "m_axi_awvalid_o", "m_axi_awready_i", "m_axi_wvalid_o", "m_axi_wready_i"]
    npu_complete = ["m_axi_arvalid_o", "m_axi_arready_i", "m_axi_rvalid_i", "m_axi_rready_o", "m_axi_awvalid_o", "m_axi_awready_i", "m_axi_wvalid_o", "m_axi_wready_i", "m_axi_bvalid_i", "m_axi_bready_o", "cycles", "read_transactions", "write_transactions"]
    nlabels = {n:n.replace("_", " ") for n in set(npu_control + npu_complete)}
    render(args.video_vcd, args.out_dir / "system-interconnect-cpu-video-modelsim.png", "CPU→Video 控制请求、AXI 写入与完成中断", video, vlabels, 0, 28520000)
    render(args.npu_vcd, args.out_dir / "system-interconnect-cpu-npu-control-modelsim.png", "CPU→NPU 配置与 AXI128 初始传输", npu_control, nlabels, 0, 50000000)
    render(args.npu_vcd, args.out_dir / "system-interconnect-cpu-npu-complete-modelsim.png", "CPU→NPU 尾部写响应与计数器收敛", npu_complete, nlabels, 860000000, 880000000)


if __name__ == "__main__":
    main()
