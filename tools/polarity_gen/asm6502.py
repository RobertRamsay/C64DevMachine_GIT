"""Tiny two-pass 6502 assembler for the subset of syntax the POLARITY code
blocks use (same as the Dev Machine CODE BLOCK syntax). Used to check
sizes / branch ranges and to build a stand-alone test PRG."""
import re

OPS = {
 'ADC': {'imm':0x69,'zp':0x65,'zpx':0x75,'abs':0x6D,'abx':0x7D,'aby':0x79,'izx':0x61,'izy':0x71},
 'AND': {'imm':0x29,'zp':0x25,'zpx':0x35,'abs':0x2D,'abx':0x3D,'aby':0x39,'izx':0x21,'izy':0x31},
 'ASL': {'acc':0x0A,'zp':0x06,'zpx':0x16,'abs':0x0E,'abx':0x1E},
 'BIT': {'zp':0x24,'abs':0x2C},
 'BPL': {'rel':0x10},'BMI': {'rel':0x30},'BVC': {'rel':0x50},'BVS': {'rel':0x70},
 'BCC': {'rel':0x90},'BCS': {'rel':0xB0},'BNE': {'rel':0xD0},'BEQ': {'rel':0xF0},
 'BRK': {'imp':0x00},
 'CMP': {'imm':0xC9,'zp':0xC5,'zpx':0xD5,'abs':0xCD,'abx':0xDD,'aby':0xD9,'izx':0xC1,'izy':0xD1},
 'CPX': {'imm':0xE0,'zp':0xE4,'abs':0xEC},
 'CPY': {'imm':0xC0,'zp':0xC4,'abs':0xCC},
 'DEC': {'zp':0xC6,'zpx':0xD6,'abs':0xCE,'abx':0xDE},
 'EOR': {'imm':0x49,'zp':0x45,'zpx':0x55,'abs':0x4D,'abx':0x5D,'aby':0x59,'izx':0x41,'izy':0x51},
 'CLC': {'imp':0x18},'SEC': {'imp':0x38},'CLI': {'imp':0x58},'SEI': {'imp':0x78},
 'CLV': {'imp':0xB8},'CLD': {'imp':0xD8},'SED': {'imp':0xF8},
 'INC': {'zp':0xE6,'zpx':0xF6,'abs':0xEE,'abx':0xFE},
 'JMP': {'abs':0x4C,'ind':0x6C},
 'JSR': {'abs':0x20},
 'LDA': {'imm':0xA9,'zp':0xA5,'zpx':0xB5,'abs':0xAD,'abx':0xBD,'aby':0xB9,'izx':0xA1,'izy':0xB1},
 'LDX': {'imm':0xA2,'zp':0xA6,'zpy':0xB6,'abs':0xAE,'aby':0xBE},
 'LDY': {'imm':0xA0,'zp':0xA4,'zpx':0xB4,'abs':0xAC,'abx':0xBC},
 'LSR': {'acc':0x4A,'zp':0x46,'zpx':0x56,'abs':0x4E,'abx':0x5E},
 'NOP': {'imp':0xEA},
 'ORA': {'imm':0x09,'zp':0x05,'zpx':0x15,'abs':0x0D,'abx':0x1D,'aby':0x19,'izx':0x01,'izy':0x11},
 'TAX': {'imp':0xAA},'TXA': {'imp':0x8A},'DEX': {'imp':0xCA},'INX': {'imp':0xE8},
 'TAY': {'imp':0xA8},'TYA': {'imp':0x98},'DEY': {'imp':0x88},'INY': {'imp':0xC8},
 'ROL': {'acc':0x2A,'zp':0x26,'zpx':0x36,'abs':0x2E,'abx':0x3E},
 'ROR': {'acc':0x6A,'zp':0x66,'zpx':0x76,'abs':0x6E,'abx':0x7E},
 'RTI': {'imp':0x40},'RTS': {'imp':0x60},
 'SBC': {'imm':0xE9,'zp':0xE5,'zpx':0xF5,'abs':0xED,'abx':0xFD,'aby':0xF9,'izx':0xE1,'izy':0xF1},
 'STA': {'zp':0x85,'zpx':0x95,'abs':0x8D,'abx':0x9D,'aby':0x99,'izx':0x81,'izy':0x91},
 'TXS': {'imp':0x9A},'TSX': {'imp':0xBA},'PHA': {'imp':0x48},'PLA': {'imp':0x68},
 'PHP': {'imp':0x08},'PLP': {'imp':0x28},
 'STX': {'zp':0x86,'zpy':0x96,'abs':0x8E},
 'STY': {'zp':0x84,'zpx':0x94,'abs':0x8C},
}
SIZE = {'imp':1,'acc':1,'imm':2,'zp':2,'zpx':2,'zpy':2,'izx':2,'izy':2,'rel':2,'abs':3,'abx':3,'aby':3,'ind':3}


class AsmError(Exception):
    pass


def num(s):
    s = s.strip()
    if s.startswith('$'): return int(s[1:], 16)
    if s.startswith('%'): return int(s[1:], 2)
    if s.isdigit(): return int(s)
    return None


def strip_comment(line):
    in_str = False
    for i, ch in enumerate(line):
        if ch == '"': in_str = not in_str
        if not in_str and (ch == ';' or line[i:i+2] == '//'):
            return line[:i]
    return line


class Assembler:
    def __init__(self):
        self.labels = {}
        self.items = []          # (addr, kind, data)
        self.pc = None

    def parse(self, text, where=""):
        """Returns list of (label|None, mnemonic|None, operand|None, directive)."""
        out = []
        for ln, raw in enumerate(text.splitlines()):
            line = strip_comment(raw).strip()
            if not line:
                continue
            m = re.match(r'^\.?([A-Za-z_][A-Za-z0-9_]*):\s*(.*)$', line)
            if m:
                out.append(('label', m.group(1), where, ln))
                line = m.group(2).strip()
                if not line:
                    continue
            if line.lower().startswith('.byte'):
                vals = [v.strip() for v in line[5:].split(',') if v.strip()]
                out.append(('byte', vals, where, ln))
                continue
            parts = line.split(None, 1)
            mn = parts[0].upper()
            op = parts[1].replace(' ', '') if len(parts) > 1 else ''
            if mn not in OPS:
                raise AsmError("%s:%d unknown mnemonic %r" % (where, ln + 1, raw))
            out.append(('ins', mn, op, where, ln))
        return out

    def mode(self, mn, op):
        modes = OPS[mn]
        if op == '' or op.upper() == 'A':
            return ('acc' if 'acc' in modes else 'imp'), None
        if 'rel' in modes:
            return 'rel', op
        if op.startswith('#'):
            return 'imm', op[1:]
        if op.startswith('(') and op.upper().endswith('),Y'):
            return 'izy', op[1:-3]
        if op.startswith('(') and op.upper().endswith(',X)'):
            return 'izx', op[1:-3]
        if op.startswith('(') and op.endswith(')'):
            return 'ind', op[1:-1]
        idx = None
        if op.upper().endswith(',X'): idx, op = 'x', op[:-2]
        elif op.upper().endswith(',Y'): idx, op = 'y', op[:-2]
        v = num(op)
        zp = v is not None and v <= 255 and len(op.lstrip('$')) <= 2 and op.startswith('$')
        if idx is None:
            m = 'zp' if zp and 'zp' in modes else 'abs'
        elif idx == 'x':
            m = 'zpx' if zp and 'zpx' in modes else 'abx'
        else:
            m = 'zpy' if zp and 'zpy' in modes else 'aby'
        return m, op

    def add_block(self, text, org=None, where=""):
        if org is not None:
            self.pc = org
        for it in self.parse(text, where):
            if it[0] == 'label':
                name = it[1]
                if name in self.labels and self.labels[name] != self.pc:
                    raise AsmError("duplicate label %s (%s)" % (name, where))
                self.labels[name] = self.pc
            elif it[0] == 'byte':
                self.items.append((self.pc, 'byte', it[1], it[2], it[3]))
                self.pc += len(it[1])
            else:
                _, mn, op, w, ln = it
                m, arg = self.mode(mn, op)
                if m not in OPS[mn]:
                    raise AsmError("%s:%d bad mode %s %s" % (w, ln + 1, mn, op))
                self.items.append((self.pc, 'ins', (mn, m, arg), w, ln))
                self.pc += SIZE[m]

    def value(self, expr, w, ln):
        expr = expr.strip()
        lohi = None
        if expr[:1] in '<>':
            lohi, expr = expr[0], expr[1:]
        total, sign = 0, 1
        for tok in re.findall(r'[+-]|[^+-]+', expr):
            if tok == '+': sign = 1; continue
            if tok == '-': sign = -1; continue
            v = num(tok)
            if v is None:
                if tok not in self.labels:
                    raise AsmError("%s:%d unresolved label %s" % (w, ln + 1, tok))
                v = self.labels[tok]
            total += sign * v
        if lohi == '<': return total & 255
        if lohi == '>': return (total >> 8) & 255
        return total

    def link(self):
        mem = {}
        for addr, kind, data, w, ln in self.items:
            if kind == 'byte':
                for i, v in enumerate(data):
                    mem[addr + i] = self.value(v, w, ln) & 255
                continue
            mn, m, arg = data
            mem[addr] = OPS[mn][m]
            if SIZE[m] == 1:
                continue
            v = self.value(arg, w, ln)
            if m == 'rel':
                d = v - (addr + 2)
                if not -128 <= d <= 127:
                    raise AsmError("%s:%d branch out of range (%d) to %s" % (w, ln + 1, d, arg))
                mem[addr + 1] = d & 255
            elif SIZE[m] == 2:
                if m != 'imm' and v > 255:
                    raise AsmError("%s:%d zp operand > 255" % (w, ln + 1))
                mem[addr + 1] = v & 255
            else:
                mem[addr + 1] = v & 255
                mem[addr + 2] = (v >> 8) & 255
        return mem
