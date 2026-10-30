"""Run the standalone synchronous NPU AXI128 DMA protocol regression."""
from datetime import datetime, timezone
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts/video"))
from common import input_hashes, run_logged, sha256, tool, write_json
from frozen_inputs import FrozenInputs


def main():
    build = ROOT / "build/npu"
    stamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S_%fZ")
    work = build / "dma" / stamp
    work.mkdir(parents=True, exist_ok=False)
    latest = build / "latest_dma.json"
    sources = [ROOT / "rtl/npu/npu_axi128_single.v",
               ROOT / "tb/npu/tb_npu_axi128_single.sv"]
    result = {"status": "running", "directory": str(work.relative_to(ROOT)),
              "physical_ddr": False, "cdc_verified": False}
    write_json(latest, result)
    try:
        names = ['rtl/npu/npu_axi128_single.v', 'tb/npu/tb_npu_axi128_single.sv',
                 'scripts/npu/test_dma_runner.py', 'scripts/npu/frozen_inputs.py', 'scripts/video/common.py']
        guard = FrozenInputs(ROOT, work / 'inputs', names)
        result['inputs'] = guard.inputs
        sources = [work / 'inputs' / p.relative_to(ROOT) for p in sources]
        def checked(command, log):
            guard.verify()
            try:
                return run_logged(command, log)
            finally:
                guard.verify()
        result["tools"] = {}
        for name in ("iverilog", "vvp"):
            executable = tool(name)
            result["tools"][name] = {"path": str(executable), "sha256": sha256(executable)}
            guard.track(executable)
            checked([executable, "-V"], work / f"{name}_version.log")
        binary = work / "dma.vvp"
        checked([tool("iverilog"), "-g2012", "-Wall", "-s", "tb_npu_axi128_single",
                    "-o", binary, *sources], work / "compile.log")
        guard.track(binary)
        output = checked([tool("vvp"), binary], work / "simulation.log")
        if output.count("NPU_AXI128_SINGLE_PASS") != 1:
            raise RuntimeError("Missing unique DMA regression success marker")
        guard.verify()
        result["source_unchanged"] = True
        result["status"] = "pass"
        result["summary"] = output.strip()
        result["artifacts"] = input_hashes(sorted(work.glob("*.log")))
        write_json(work / "result.json", result)
        write_json(latest, result)
        print(output.strip())
        print(work)
        return 0
    except Exception as error:
        result["status"] = "fail"
        result["error"] = str(error)
        write_json(work / "result.json", result)
        write_json(latest, result)
        print(str(error), file=sys.stderr)
        print(work, file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
