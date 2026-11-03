"""Read frozen route evidence from either the main build or a reused placement."""
import json
import re
from pathlib import Path
from common import sha256


def route_record(directory):
    directory=Path(directory).resolve()
    receipt=directory/'receipt.json'
    if receipt.exists():
        result=json.loads(receipt.read_text(encoding='utf-8'))
        result['record_path']=str(receipt)
        result['log_path']=str(directory/'route.log')
        return result
    receipt=directory/'result.json'
    build=json.loads(receipt.read_text(encoding='utf-8'))
    if build['target']!='triha_face_board' or build['stage'] not in ('route','bitstream') or build['status']=='running':
        raise ValueError('Main physical build has not finished')
    log=directory/'physical.log'
    text=log.read_text(encoding='utf-8',errors='replace')
    if not re.search(r"Design 'triha_face_board_top' has been (?:placed and )?routed successfully\.",text):
        raise ValueError('Main build has no successful completed route')
    db=directory/'place_route/triha_face_board_top_pnr.adf'
    inputs=[receipt,log,directory/'physical.tcl',directory/'physical.pcf',
            directory/'device_map/triha_face_board_top_map.adf',
            directory/'place_route/triha_face_board_top_plc.adf',Path(__file__)]
    return dict(status='ROUTE_REVIEW_READY',source_build_status=build['status'],
                scope='Completed route milestone only; preserve original build/timing status',
                record_path=str(receipt),log_path=str(log),routed_db=str(db),
                routed_db_sha256=sha256(db),inputs={str(p):sha256(p) for p in inputs})


def placement_record(directory):
    directory=Path(directory).resolve()
    receipt=directory/'receipt.json'
    if receipt.exists():
        result=json.loads(receipt.read_text(encoding='utf-8'))
        result['record_path']=str(receipt);result['log_path']=str(directory/'place.log')
        return result
    result=route_record(directory)
    result['status']='PLACEMENT_COMPLETED_IN_MAIN_BUILD'
    return result
