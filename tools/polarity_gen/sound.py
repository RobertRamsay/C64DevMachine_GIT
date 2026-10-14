"""POLARITY music (MUSIC_MAKER) and sound effects (SFX_MAKER) metas.
The instrument set is the editor's stock one (taken from the GATE-GAME
template); the patterns, song and effects are new."""
import copy, json

KICK_BASS, BASS, SNARE_BASS, HAT, LEAD = 1, 0, 2, 3, 4

def empty_step():
    return {"empty": True, "cmd_val": 0.0, "instr_idx": -1.0, "note": "", "cmd": -1.0}

def step(note, instr):
    return {"empty": False, "cmd_val": 0.0, "instr_idx": float(instr), "note": note, "cmd": -1.0}

def pattern(name, notes):
    steps = [empty_step() for _ in range(32)]
    for pos, note, instr in notes:
        steps[pos] = step(note, instr)
    return {"pattern_len": 32.0, "steps": steps, "name": name}

def up(note, octs=1):
    return note[:2] + str(int(note[2]) + octs)

def bass(name, roots):
    notes = []
    for i, r in enumerate(roots):
        b = i * 8
        notes += [(b, r, KICK_BASS), (b + 2, r, BASS), (b + 3, "C-7", HAT),
                  (b + 4, up(r), SNARE_BASS), (b + 6, r, BASS), (b + 7, "C-7", HAT)]
    return pattern(name, notes)

def lead(name, seq):
    return pattern(name, [(p, n, LEAD) for p, n in seq])

PATTERNS = [
    pattern("REST", []),
    bass("BASS C-Am-F-G", ["C-3", "A-2", "F-2", "G-2"]),
    bass("BASS Am-F-C-G", ["A-2", "F-2", "C-3", "G-2"]),
    bass("BASS Am-F-G-G", ["A-2", "F-2", "G-2", "G-2"]),
    lead("TUNE A1", [(0, "E-5"), (2, "G-5"), (4, "C-6"), (6, "G-5"), (8, "A-5"), (10, "G-5"), (12, "E-5"), (14, "C-5"),
                     (16, "F-5"), (18, "A-5"), (20, "C-6"), (22, "A-5"), (24, "G-5"), (26, "F-5"), (28, "D-5"), (30, "B-4")]),
    lead("TUNE A2", [(0, "C-5"), (2, "E-5"), (4, "G-5"), (6, "C-6"), (8, "C-6"), (10, "B-5"), (12, "A-5"), (14, "E-5"),
                     (16, "F-5"), (20, "A-5"), (22, "G-5"), (24, "B-4"), (26, "D-5"), (28, "G-5"), (30, "F-5")]),
    lead("BRIDGE B1", [(0, "A-5"), (4, "C-6"), (6, "B-5"), (8, "A-5"), (12, "F-5"),
                       (16, "G-5"), (20, "E-5"), (22, "G-5"), (24, "D-6"), (28, "B-5")]),
    lead("BRIDGE B2", [(0, "C-6"), (2, "B-5"), (4, "A-5"), (6, "E-5"), (8, "F-5"), (10, "A-5"), (12, "C-6"), (14, "A-5"),
                       (16, "B-5"), (20, "D-6"), (24, "G-5"), (26, "F-5"), (28, "E-5"), (30, "D-5")]),
]

def row(v1, v2):
    return {"v1": float(v1), "v2": float(v2), "v3": 0.0, "dg": -1.0, "force_len": 32.0, "repeat_short": False}

SONGS = [{
    "loop_row": 0.0, "name": "POLARITY THEME", "loop": True,
    "order": [row(1, 4), row(1, 5), row(1, 4), row(1, 5), row(2, 6), row(3, 7), row(2, 6), row(3, 7)],
}]

SFX = [
    # name, text, note, attack, decay, sustain, release, priority
    ("COIN",    "$11,N+12,D2,N+19,D2,N+24,D4,---", "C-5", 0, 6, 0, 2, 2),
    ("USE",     "$41,D1,N+7,D2,---",               "C-5", 0, 3, 0, 1, 1),
    ("MAGIC",   "$21,D1,N+12,D1,N+7,D1,N+19,D2,---", "C-5", 0, 4, 2, 2, 1),
    ("SWAP",    "$11,D2,N+4,D2,N+7,D2,N+12,D2,N+16,D4,---", "C-5", 0, 6, 4, 3, 3),
    ("OUCH",    "$81,D2,$41,N-5,D3,N-10,D4,---",    "C-4", 0, 6, 2, 2, 3),
    ("PROMOTE", "$21,D4,N+4,D4,N+7,D4,N+12,D10,---", "C-5", 0, 6, 8, 3, 3),
    ("ERROR",   "$41,D6,N-1,D6,---",                "C-3", 0, 8, 6, 2, 2),
    ("SLEEP",   "$11,D8,N-3,D8,N-7,D12,---",        "C-4", 2, 8, 6, 6, 2),
]
SFX_ID = {s[0]: i for i, s in enumerate(SFX)}


def music_meta(gate_music_meta):
    m = copy.deepcopy(gate_music_meta)
    m["patterns"] = copy.deepcopy(PATTERNS)
    m["songs"] = copy.deepcopy(SONGS)
    m["play_speed"] = 5.0
    m["voice_mask"] = 3.0
    m["song_loop"] = True
    m["song_loop_row"] = 0.0
    for k in ("sel_song", "sel_order_row", "sel_voice", "sel_step", "bank_sel_pattern", "list_scroll", "sel_instr"):
        m[k] = 0.0
    m["song_order"] = []
    return m


def sfx_meta(gate_sfx_meta):
    m = copy.deepcopy(gate_sfx_meta)
    m["instruments"] = [{
        "release": float(r), "pulse_width": 2048.0, "sfx_note": note, "sfx_priority": float(pri),
        "name": name, "text": text, "attack": float(a), "decay": float(d), "sustain": float(s),
    } for name, text, note, a, d, s, r, pri in SFX]
    m["sel_instr"] = 0.0
    return m
