"""Validate testbench-only, exact-window DDR CoreMark observations."""
import re


ISSUE = 'issue cancel lsu pipe div csr frontend unit dependency other wb stores'.split()
DC = 'reads writes read_hits read_misses uncached_reads store_hits store_misses uncached_writes refills lower_writes'.split()
DC_STATES = 'idle lookup refill_req refill relookup response write_req write_wait store_update uncached_req uncached_wait reset invalidate flush'.split()
DC_STATES_WB = 'reset idle lookup refill_req refill relookup response store_update uncached_req uncached_wait invalidate maint_check maint_adv wb_read wb_req wb_wait maint_read clean'.split()
BRIDGE_STATES = 'idle collect wpre waddr wdata vpre vaddr vdata raddr rdata rpre rresp bresp quarantine'.split()
NATIVE = 'native_aw native_ar native_wbeats native_rbeats'.split()


def parse_profile(text, measured_cycles):
    def fields(label, expected):
        lines = re.findall(r'(?m)^(?:# )?CPU_DDR_PROFILE_' + label + r' (.+)\r?$', text)
        if len(lines) != 1:
            raise ValueError('missing or duplicate profile section: ' + label)
        pairs = re.findall(r'(\w+)=(\d+)', lines[0])
        if len(pairs) != len(expected) or set(k for k, _ in pairs) != set(expected):
            raise ValueError('missing, duplicate or unknown profile field: ' + label)
        if ' '.join(k+'='+v for k, v in pairs) != lines[0].strip():
            raise ValueError('invalid profile field text: ' + label)
        return {k: int(v) for k, v in pairs}

    write_back = 'CPU_DDR_PROFILE_POLICY' in text
    if write_back and fields('POLICY', ['write_back']) != {'write_back': 1}:
        raise ValueError('unsupported write policy')
    window = fields('WINDOW', ['cycles', 'start', 'stop', 'reads'])
    issue = fields('ISSUE', ISSUE)
    dc = fields('DC', DC + (['writeback_words', 'uncached_lower_writes'] if write_back else []))
    states = fields('DC_STATES', DC_STATES_WB if write_back else DC_STATES)
    bridge = fields('BRIDGE', BRIDGE_STATES + NATIVE)
    cycles = window['cycles']
    if (cycles <= 0 or cycles != measured_cycles or window['reads'] != 2 or
            (window['stop']-window['start']) % (1 << 32) != cycles):
        raise ValueError('profile window differs from actual software cycle measurement')
    if sum(issue[k] for k in ISSUE[:-2]) != cycles or sum(states.values()) != cycles:
        raise ValueError('profile cycle categories do not partition the window')
    if sum(bridge[k] for k in BRIDGE_STATES) != cycles:
        raise ValueError('bridge CPU-edge samples do not partition the window')
    if (dc['reads'] != dc['read_hits'] + dc['read_misses'] + dc['uncached_reads'] or
            dc['writes'] != dc['store_hits'] + dc['store_misses'] + dc['uncached_writes']):
        raise ValueError('D-cache request classification/transport count mismatch')
    if write_back:
        if (dc['lower_writes'] != dc['writeback_words'] + dc['uncached_lower_writes'] or
                dc['uncached_lower_writes'] != dc['uncached_writes'] or
                dc['refills'] != dc['read_misses'] + dc['store_misses']):
            raise ValueError('D-cache writeback/allocate transport count mismatch')
    elif dc['lower_writes'] != dc['writes'] or dc['refills'] != dc['read_misses']:
        raise ValueError('D-cache write-through transport count mismatch')
    cached_reads = dc['read_hits'] + dc['read_misses']
    dc['read_hit_rate'] = dc['read_hits']/cached_reads if cached_reads else None
    result = dict(cycles=cycles, window=window, issue=issue, dcache=dc,
        write_policy='write_back' if write_back else 'write_through',
        dcache_states=states, bridge_states={k: bridge[k] for k in BRIDGE_STATES},
        native_events={k: bridge[k] for k in NATIVE}, physical_board_profile=False,
        scope='Digital native-DDR model; issue buckets partition CPU cycles. Cache and bridge occupancy overlap issue buckets. Native events sampled at DDR clock with the CPU window gate.')
    if 'CPU_DDR_PROFILE_OVERLAP' in text:
        overlap = fields('OVERLAP', ['accepted'])
        if overlap['accepted'] > dc['reads'] + dc['writes'] or overlap['accepted'] > cycles:
            raise ValueError('overlap observation exceeds accepted requests or window')
        result['dcache_overlap'] = overlap
    return result
