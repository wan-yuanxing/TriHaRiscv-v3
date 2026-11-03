"""Reimplement a frozen BOX mapped database without changing logical inputs."""
import argparse
import json
from pathlib import Path
import re
import subprocess
import time

from build_pds import tcl_path, verify_build_inputs
from common import sha256
from face_route_evidence import placement_record
from face_profiles import require_profile


def merge_route_constraints(paths, output):
    """PDS accepts one RCF only: later add_constraint calls replace earlier RCFs."""
    commands = []
    for path in paths:
        for line in path.read_text(encoding='utf-8').splitlines():
            line = line.strip()
            if line and not line.startswith('#') and line not in commands:
                commands.append(line)
    output.write_text('# Combined routing constraints; preserve vendor clock routes.\n'
                      +'\n'.join(commands)+'\n', encoding='utf-8')
    return commands


def route_constraint_error(text):
    return next((line for line in text.splitlines()
                 if re.match(r'^[WCE]: RouteConstraintEditor-', line)), None)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', type=Path, required=True)
    parser.add_argument('--output', type=Path, required=True)
    parser.add_argument('--seed', type=int, default=5)
    parser.add_argument('--mode', choices=('normal', 'performance'), default='performance')
    parser.add_argument('--decongestion', type=int, choices=range(10), default=3)
    parser.add_argument('--placement', type=Path, help='Reuse this reviewed placement instead of placing again')
    parser.add_argument('--priority-constraints', type=Path, help='Routing-order-only RCF for measured critical nets')
    parser.add_argument('--fixed-route-constraints', type=Path, help='Observed hold-safe branch RCF with a matching .json evidence record')
    parser.add_argument('--hold-iterations', type=int, help='Explicit PDS hold-repair iteration limit, 1..100')
    parser.add_argument('--hold-margin-ps', type=int, help='Nonnegative hold-repair target, 0..200 ps; STA constraints remain unchanged')
    parser.add_argument('--pds', type=Path, default=Path('D:/pango/PDS_2022.2-SP6.4/bin/pds_shell.exe'))
    args = parser.parse_args()
    if args.hold_iterations is not None and not 1 <= args.hold_iterations <= 100:
        parser.error('--hold-iterations must be between 1 and 100')
    if args.hold_margin_ps is not None and not 0 <= args.hold_margin_ps <= 200:
        parser.error('--hold-margin-ps must be between 0 and 200')
    base = args.base.resolve()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    result = dict(status='RUNNING', stage='route', started=time.time(),
                  scope='New physical implementation of unchanged BOX mapped design; full STA required',
                  base=str(base), seed=args.seed, mode=args.mode, decongestion=args.decongestion)
    result['hold_repair'] = dict(iterations=args.hold_iterations, margin_ps=args.hold_margin_ps,
                               timing_constraints_unchanged=True)

    def save():
        (out/'receipt.json').write_text(json.dumps(result, indent=2)+'\n', encoding='utf-8')

    try:
        build = json.loads((base/'result.json').read_text(encoding='utf-8'))
        require_profile(build)
        if build.get('status') == 'running':
            raise ValueError('Expected completed frozen face synthesis')
        verify_build_inputs(base, build)
        mapped = base/'device_map/triha_face_board_top_map.adf'
        constraints = [base/'physical.pcf', base/'src/fpga/pg2l100h/constraints/triha_face_phy.rcf']
        placement_inputs = []
        fixed_route_inputs = []
        fixed_sites = []
        placed = None
        if args.placement:
            placement = args.placement.resolve()
            evidence = placement_record(placement)
            for name, digest in evidence['inputs'].items():
                if sha256(Path(name)) != digest:
                    raise ValueError('Placement input changed: '+name)
            if evidence['inputs'].get(str(mapped)) != sha256(mapped):
                raise ValueError('Placement belongs to another mapped design')
            placed = placement/'place_route/triha_face_board_top_plc.adf'
            placement_inputs = [placed, Path(evidence['record_path'])]
            result['placement'] = str(placement)
        if args.priority_constraints:
            if not placed:
                raise ValueError('Critical-net priorities require a frozen placement')
            priority = args.priority_constraints.resolve()
            commands = [line.strip() for line in priority.read_text(encoding='utf-8').splitlines()
                        if line.strip() and not line.lstrip().startswith('#')]
            if not commands or len(set(commands)) != len(commands) or any(
                    not re.fullmatch(r'def_route -prior_net \{[^{}\r\n]+\}', line) for line in commands):
                raise ValueError('Priority RCF must contain only unique def_route -prior_net commands')
            constraints.append(priority)
            result['priority_nets'] = len(commands)
        if args.fixed_route_constraints:
            if not placed:
                raise ValueError('A fixed route requires its original frozen placement')
            fixed = args.fixed_route_constraints.resolve()
            proof_path = fixed.with_suffix('.json')
            proof = json.loads(proof_path.read_text(encoding='utf-8'))
            if proof['rcf_sha256'] != sha256(fixed) or proof['source_placement_sha256'] != sha256(placed):
                raise ValueError('Fixed-route evidence does not match the RCF and placement')
            commands = [line.strip() for line in fixed.read_text(encoding='utf-8').splitlines()
                        if line.strip() and not line.lstrip().startswith('#')]
            pins = proof['branch_pins']
            if (len(pins) < 2 or any(not re.fullmatch(r'[A-Za-z0-9_\[\]]+:[A-Za-z0-9_]+', pin) for pin in pins)
                    or not re.fullmatch(r'[^{}\r\n]+', proof['route_net'])
                    or commands != ['def_route {'+proof['route_net']+'} {'+';'.join(pins)+';}']):
                raise ValueError('Fixed route is not the exact observed physical branch')
            for key in ('source_database', 'source_review', 'observation'):
                path = Path(proof[key]).resolve()
                if sha256(path) != proof[key+'_sha256']:
                    raise ValueError('Fixed-route source changed: '+key)
                fixed_route_inputs.append(path)
            source_review = json.loads(Path(proof['source_review']).read_text(encoding='utf-8'))
            if source_review['route_evidence']['routed_db_sha256'] != proof['source_database_sha256']:
                raise ValueError('Fixed-route observation and timing review use different databases')
            if any(row['failing_endpoints'] for rows in source_review['timing']['summaries']['hold'].values() for row in rows):
                raise ValueError('Fixed-route source did not pass both hold corners')
            sites_path = Path(source_review['sites']['path'])
            if sha256(sites_path) != source_review['sites']['sha256']:
                raise ValueError('Fixed-route physical site evidence changed')
            site_text = sites_path.read_text(encoding='utf-8')
            if len(proof['endpoints']) != 2:
                raise ValueError('Fixed route requires two explicit physical endpoints')
            for endpoint, pin in zip(proof['endpoints'], (pins[0], pins[-1])):
                line = 'def_inst_site {'+endpoint['cell']+'} '+endpoint['site']+' '+endpoint['resource']
                if (endpoint['site'] != pin.split(':')[1]
                        or len(re.findall('^'+re.escape(line)+r'(?: -no_check)?\s*$', site_text, re.M)) != 1):
                    raise ValueError('Fixed-route endpoint differs from observed placement')
                fixed_sites.append(line)
            fixed_route_inputs.append(sites_path)
            constraints.append(fixed)
            fixed_route_inputs.append(proof_path)
            result['fixed_route'] = dict(net=proof['route_net'], pins=len(pins), proof=str(proof_path))
        constraint_sources = list(constraints)
        physical = constraints[0]
        if fixed_sites:
            text = physical.read_text(encoding='utf-8')
            for line in fixed_sites:
                cell = re.search(r'\{([^}]+)\}', line)[1]
                existing = re.findall(r'^def_inst_site \{'+re.escape(cell)+r'\}[^\n]*', text, re.M)
                if existing and existing != [line]:
                    raise ValueError('Conflicting fixed-route endpoint constraint: '+cell)
                if not existing:
                    text += '\n'+line+'\n'
            physical = out/'physical.pcf'
            physical.write_text(text, encoding='utf-8')
        combined = out/'routing.rcf'
        commands = merge_route_constraints(constraint_sources[1:], combined)
        constraints = [physical, combined]
        result['routing_constraints'] = dict(files=1, commands=len(commands),
                                             explicit_endpoint_sites=fixed_sites)
        script = out/'route.tcl'
        lines = ['set_arch -family Logos2 -device PG2L100H -speedgrade -6 -package FBG676']
        lines += ['add_constraint '+tcl_path(path) for path in constraints]
        lines += ['pnr -force_to_run -optimize_multi_corner_timing -fix_hold_violation'
                  ' -slack_prior_in_global_router TRUE -dump_router_congestion_plot TRUE'
                  f' -mode {args.mode}'
                  + (f' -fix_hold_violation_iterations {args.hold_iterations}'
                     if args.hold_iterations is not None else '')
                  + (f' -fix_hold_violation_threshold {args.hold_margin_ps}'
                     ' -fix_hold_violation_in_route TRUE'
                     f' -fix_hold_violation_threshold_for_clk_tree {args.hold_margin_ps}'
                     if args.hold_margin_ps is not None else '')
                  + (f' -plc_decongestion {args.decongestion}'
                     f' -gplace_seed {args.seed} -gplace_times 1 -saved_outcome 1 -parallel 1'
                     if placed is None else '')
                  + ' -input_db_file '+tcl_path(mapped)
                  + (' -input_place_db_file '+tcl_path(placed) if placed else '')]
        script.write_text('\n'.join(lines)+'\n', encoding='utf-8')
        inputs = [mapped, *constraint_sources, *constraints, *placement_inputs, *fixed_route_inputs,
                  base/'result.json', script, Path(__file__), Path(__file__).with_name('face_profiles.py'), args.pds.resolve()]
        result['inputs'] = {str(path): sha256(path) for path in inputs}
        save()
        with (out/'route.log').open('wb') as log:
            proc = subprocess.Popen([str(args.pds), '-file', str(script), '-work_dir', str(out),
                                     '-project_name', 'face_reroute'], cwd=out, stdout=log,
                                    stderr=subprocess.STDOUT, creationflags=subprocess.CREATE_NO_WINDOW)
            result['pid'] = proc.pid
            save()
            try:
                deadline = time.monotonic()+5400
                while proc.poll() is None:
                    time.sleep(2)
                    error = route_constraint_error((out/'route.log').read_text(encoding='utf-8', errors='replace'))
                    if error:
                        raise RuntimeError('PDS rejected routing constraints: '+error)
                    if time.monotonic() >= deadline:
                        raise RuntimeError('Physical implementation timed out')
                result['exit_code'] = proc.returncode
            except Exception:
                subprocess.run(['taskkill', '/PID', str(proc.pid), '/T', '/F'], capture_output=True, timeout=30)
                proc.wait(timeout=30)
                raise
        for path, digest in result['inputs'].items():
            if sha256(Path(path)) != digest:
                raise ValueError('Physical input changed: '+path)
        verify_build_inputs(base, build)
        text = (out/'route.log').read_text(encoding='utf-8', errors='replace')
        if route_constraint_error(text):
            raise RuntimeError('PDS rejected routing constraints: '+route_constraint_error(text))
        if result['exit_code'] or any(line.startswith('E:') for line in text.splitlines()):
            raise RuntimeError('Physical implementation failed; inspect route.log')
        if not re.search(r"Design 'triha_face_board_top' has been (?:placed and )?routed successfully\.", text):
            raise RuntimeError('Missing successful route completion')
        remaining = re.findall(r'Unrouted nets (\d+) at the end of iteration (\d+)\.', text)
        if not remaining or remaining[-1][0] != '0':
            raise RuntimeError('Route is incomplete')
        routed = out/'place_route/triha_face_board_top_pnr.adf'
        if placed is None:
            placed = out/'place_route/triha_face_board_top_plc.adf'
            # A new combined PNR also supplies its own placement evidence.
            (out/'place.log').write_bytes((out/'route.log').read_bytes())
        result['inputs'][str(placed)] = sha256(placed)
        result['inputs'][str(out/'route.log')] = sha256(out/'route.log')
        result.update(status='ROUTE_REVIEW_READY', routed_db=str(routed),
                      routed_db_sha256=sha256(routed), inputs_unchanged=True)
    except Exception as error:
        result.update(status='FAIL', error=str(error))
    finally:
        result['elapsed'] = time.time()-result['started']
        save()
    print(result['status'], result.get('error', ''), out, flush=True)
    return 0 if result['status'] == 'ROUTE_REVIEW_READY' else 1


if __name__ == '__main__':
    raise SystemExit(main())
