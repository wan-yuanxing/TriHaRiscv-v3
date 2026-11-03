"""Prove identity-only physical Gray buffers from a native routed netlist.

The PDS route may use a CLM feed-through counted as a logic level in STA.
Accept only a traced V_BUF chain between the exact registered bit endpoints.
All delay, setup and clock-spread checks still apply to the entire path.
"""
import hashlib
from pathlib import Path
import re


# Reviewed PDS 2022.2-SP6.4 primitive: combinational `assign Z = I`.
V_BUF_MODEL_SHA256 = '774fb1a08820223eef6c66217e510d3a5eb328edebffb488a25467fe3e623836'


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def ports(body):
    pairs = re.findall(r'\.(\w+)\s*\(([^()]*)\)', body)
    if len({name for name, _ in pairs}) != len(pairs):
        raise ValueError('Duplicate netlist port')
    return {name: re.sub(r'\s+', ' ', net).strip() for name, net in pairs}


class GrayNetlist:
    def __init__(self, text):
        self.registers = {}
        pattern = (r'\bV_FFASYN\s*/\*\s*([^\r\n]*?)/FF\d+/FF\s*\*/\s*#\((.*?)\)'
                   r'\s*(\\\S+)\s*\((.*?)\);')
        for match in re.finditer(pattern, text, re.S):
            cell, _, physical, body = match.groups()
            # Packed non-Gray logic may contain several FFs under one mapped
            # cell. Such a cell cannot serve as a unique Gray endpoint.
            self.registers[cell] = (None if cell in self.registers else
                                    dict(physical=physical, ports=ports(body)))
        self.buffers = {}
        for match in re.finditer(r'\bV_BUF\s+(\\\S+)\s*\((.*?)\);', text, re.S):
            physical, body = match.groups()
            pins = ports(body)
            if set(pins) != {'I', 'Z'} or pins['Z'] in self.buffers:
                raise ValueError('Ambiguous buffer ports or driver')
            self.buffers[pins['Z']] = dict(physical=physical, input=pins['I'])

    def prove(self, block, start, end, levels):
        if not self.registers.get(start) or not self.registers.get(end):
            raise ValueError('Buffered Gray endpoint is not a unique native register')
        source = self.registers[start]['ports'].get('Q')
        target = self.registers[end]['ports'].get('D')
        if source is None or target is None:
            raise ValueError('Missing Gray register Q/D port')
        chain, seen = [], set()
        while target != source:
            if target in seen or target not in self.buffers or len(chain) >= 16:
                raise ValueError('Gray path contains unproven logic or wrong-bit connectivity')
            seen.add(target)
            buffer = self.buffers[target]
            chain.append(buffer['physical'].lstrip('\\').split('/')[0])
            target = buffer['input']
        chain.reverse()
        # Tie the functional chain to the physical feed-throughs in this STA path.
        arcs = re.findall(r'^\s*(\S+)/\S+\s+td\s+[\d.]+\s+[\d.]+\s+[rf]\s+(\S+)\s*$', block, re.M)
        if (len(chain) != levels or [site for site, _ in arcs] != chain
                or any(not re.fullmatch(r'CLKROUTE_\d+/CR', name) for _, name in arcs)):
            raise ValueError('Gray buffer netlist and STA physical chain differ')
        return dict(identity_buffers=levels, sites=chain)


def load_evidence(record, routed_db_sha256):
    if record['routed_db_sha256'] != routed_db_sha256:
        raise ValueError('Gray netlist belongs to a different route')
    for key in ('netlist', 'model'):
        path = Path(record[key]['path'])
        if sha(path) != record[key]['sha256']:
            raise ValueError('Gray identity evidence changed: '+key)
    if record['model']['sha256'] != V_BUF_MODEL_SHA256:
        raise ValueError('Unreviewed V_BUF primitive implementation')
    return GrayNetlist(Path(record['netlist']['path']).read_text(encoding='utf-8'))
