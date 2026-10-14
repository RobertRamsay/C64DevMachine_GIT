"""POLARITY music (MUSIC_MAKER) and sound effects (SFX_MAKER) metas.

An original tune, arranged the way classic late-80s C64 game music is built
(style notes from a register-level study of a few HVSC classics; no melodies
were taken from them):
  - 6 frames per row, 16 rows per bar, 2-bar patterns
  - voice 1: click bass (pulse with a 1-frame noise click) through a low-pass
    filter, kick and snare folded into the bass notes, hats between
  - voice 2: vibrato lead with a slow pulse sweep, or fast chord arpeggios
  - voice 3 stays free for the game's sound effects
Structure: staged intro (bass + arps), Sunny's theme (C major), Hex's theme
(A minor, flat-two chord for a witchy colour), arp breakdown, bridge, repeat.
"""
import copy

NOTES = ["C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-"]

def transpose(note, semis):
    i = NOTES.index(note[:2]) + int(note[2]) * 12 + semis
    return NOTES[i % 12] + str(i // 12)


# ------------------------------------------------------------------ instruments
def ins(name, main, loop_to=None, pulse=None, a=0, d=9, s=8, r=4, pw=2048, filt=0, end=False):
    """main: program tokens. loop_to: token index the program loops back to
    (holds the note). pulse: (speed, frames) sweep up/down, keeps running."""
    toks = list(main)
    if end:
        toks.append("---")
    elif loop_to is not None:
        toks.append("L%d" % loop_to)
    if pulse:
        q, dd = pulse
        start = len(toks) + 1
        toks += ["~PULSE+", "Q+%d" % q, "D%d" % dd, "Q-%d" % q, "D%d" % dd, "L%d" % start]
    return {"name": name, "text": "\n".join(toks), "attack": float(a), "decay": float(d),
            "sustain": float(s), "release": float(r), "pulse_width": float(pw), "filt": float(filt),
            "vib_delay": 0.0, "vib_speed": 0.0, "vib_depth": 0.0, "dirty": True}

INSTRUMENTS = [
    ins("CLICK BASS", ["$41", "D1", "$81", "N=96", "D1", "$41", "N", "D1"], 7, (96, 24), a=0, d=8, s=8, r=9, pw=1280, filt=1),
    ins("KICK BASS", ["$11", "N=60", "D1", "N=44", "D1", "N=36", "D1", "$41", "N", "D1"], 9, (96, 24), a=0, d=9, s=8, r=9, pw=1280, filt=1),
    ins("SNARE BASS", ["$81", "N=72", "D1", "$41", "N=48", "D1", "$81", "N=70", "D1", "$41", "N", "D1"], 11, (96, 24), a=0, d=9, s=8, r=9, pw=1280, filt=1),
    ins("HAT", ["$81", "N=96", "D1", "$80"], end=True, a=0, d=2, s=0, r=0),
    ins("LEAD", ["$21", "D1", "$41", "D14", "V$24", "D1"], 5, (16, 48), a=0, d=0, s=11, r=8, pw=1600),
    ins("ARP MAJOR", ["$41", "N", "D1", "N+4", "D1", "N+7", "D1", "N+12", "D1"], 1, (32, 32), a=0, d=9, s=6, r=4, pw=1024),
    ins("ARP MINOR", ["$41", "N", "D1", "N+3", "D1", "N+7", "D1", "N+12", "D1"], 1, (32, 32), a=0, d=9, s=6, r=4, pw=1024),
    ins("ECHO LEAD", ["$21", "D1", "$41", "D14", "V$24", "D1"], 5, (16, 48), a=0, d=0, s=6, r=6, pw=1600),
    ins("PAD", ["$41", "D60", "V$23", "D1"], 3, (120, 28), a=10, d=10, s=12, r=8),
    ins("SNARE LEAD", ["$81", "N=72", "D1", "$41", "N=50", "D1", "$80", "D3"], end=True, a=0, d=8, s=0, r=4),
]
I = {n["name"]: i for i, n in enumerate(INSTRUMENTS)}


# ------------------------------------------------------------------ patterns
def empty_step():
    return {"empty": True, "cmd_val": 0.0, "instr_idx": -1.0, "note": "", "cmd": -1.0}

def step(note, instr):
    return {"empty": False, "cmd_val": 0.0, "instr_idx": float(instr), "note": note, "cmd": -1.0}

def pattern(name, notes):
    steps = [empty_step() for _ in range(32)]
    for pos, note, instr in notes:
        assert 0 <= pos < 32 and steps[pos]["empty"], (name, pos)
        steps[pos] = step(note, instr)
    return {"pattern_len": 32.0, "steps": steps, "name": name}

def groove(name, roots, drums=True):
    """Bass + drums in one voice. roots: 2 per pattern (bar chords) or 4 (half-bar)."""
    span = 32 // len(roots)
    notes = []
    for i, r in enumerate(roots):
        b = i * span
        hi = transpose(r, 12)
        if not drums:
            for k in range(0, span, 2):
                notes.append((b + k, hi if (k // 2) % 2 else r, I["CLICK BASS"]))
            continue
        cell = [(0, r, "KICK BASS"), (2, r, "CLICK BASS"), (3, "C-7", "HAT"),
                (4, r, "SNARE BASS"), (6, hi, "CLICK BASS"), (7, "C-7", "HAT")]
        for off in range(0, span, 8):
            notes += [(b + off + o, n, I[k]) for o, n, k in cell]
    return pattern(name, notes)

def arps(name, chords):
    """Chord stabs in a 3-3-2 rhythm. chords: (root, 'MAJOR'/'MINOR') per bar."""
    notes = []
    for i, (root, q) in enumerate(chords):
        b = i * 16
        for o in (0, 3, 6, 8, 11, 14):
            notes.append((b + o, root, I["ARP " + q]))
    return pattern(name, notes)

def lead(name, seq, instr="LEAD"):
    out = []
    for tok in seq.split():
        pos, note = tok.split(":")
        out.append((int(pos), note, I[instr]))
    return pattern(name, out)

PATTERNS = [
    pattern("REST", []),                                                         # 0
    groove("BASS INTRO C-G", ["C-3", "G-2"], drums=False),                       # 1
    groove("BASS INTRO Am-F", ["A-2", "F-2"], drums=False),                      # 2
    groove("GROOVE C-G", ["C-3", "G-2"]),                                        # 3
    groove("GROOVE Am-F", ["A-2", "F-2"]),                                       # 4
    groove("GROOVE F G-C", ["F-2", "G-2", "C-3", "C-3"]),                        # 5
    groove("GROOVE Am-Am", ["A-2", "A-2"]),                                      # 6
    groove("GROOVE Bb-Am", ["A#2", "A-2"]),                                      # 7
    groove("GROOVE Dm-E", ["D-3", "E-2"]),                                       # 8
    groove("GROOVE Am-E", ["A-2", "E-2"]),                                       # 9
    groove("GROOVE F G-Em Am", ["F-2", "G-2", "E-2", "A-2"]),                    # 10
    groove("GROOVE F G-C", ["F-2", "G-2", "C-3", "C-3"]),                        # 11
    arps("ARPS C-G", [("C-4", "MAJOR"), ("G-3", "MAJOR")]),                      # 12
    arps("ARPS Am-F", [("A-3", "MINOR"), ("F-3", "MAJOR")]),                     # 13
    arps("ARPS Am-Am", [("A-3", "MINOR"), ("A-3", "MINOR")]),                    # 14
    arps("ARPS Bb-Am", [("A#3", "MAJOR"), ("A-3", "MINOR")]),                    # 15
    # Sunny's theme (C major)
    lead("SUNNY 1", "0:E-5 2:G-5 4:C-6 6:B-5 8:C-6 10:G-5 12:E-5 14:G-5 16:D-5 18:G-5 20:B-5 24:A-5 28:G-5"),   # 16
    lead("SUNNY 2", "0:A-5 4:C-6 6:B-5 8:A-5 12:E-5 16:F-5 18:A-5 20:C-6 22:D-6 24:C-6 28:A-5"),                # 17
    lead("SUNNY 3", "0:G-5 2:E-5 4:G-5 6:C-6 8:E-6 12:D-6 14:C-6 16:B-5 18:C-6 20:D-6 24:G-5 28:B-5"),          # 18
    lead("SUNNY 4", "0:A-5 2:C-6 4:A-5 6:F-5 8:G-5 10:B-5 12:D-6 14:B-5 16:C-6 20:E-5 24:C-5"),                 # 19
    # Hex's theme (A minor, witchy)
    lead("HEX 1", "0:A-4 6:C-5 8:E-5 12:D#5 14:E-5 16:A-5 20:G-5 22:F-5 24:E-5 28:C-5"),                        # 20
    lead("HEX 2", "0:D-5 4:F-5 6:A#5 8:A-5 12:F-5 16:E-5 20:C-5 24:B-4 28:A-4"),                                # 21
    lead("HEX 3", "0:D-5 2:F-5 4:A-5 8:D-6 12:C-6 16:B-5 18:G#5 20:E-5 24:G#5 28:B-5"),                         # 22
    lead("HEX 4", "0:A-5 4:E-5 6:A-5 8:C-6 12:B-5 16:G#5 20:B-5 24:E-6"),                                       # 23
    # bridge back to the light
    lead("BRIDGE 1", "0:C-6 4:D-6 8:B-5 12:C-6 16:A-5 20:B-5 24:C-6 28:E-6"),                                   # 24
    lead("BRIDGE 2", "0:F-6 2:E-6 4:D-6 6:C-6 8:D-6 12:B-5 16:C-6 24:G-5", "ECHO LEAD"),                         # 25
]

def row(v1, v2):
    return {"v1": float(v1), "v2": float(v2), "v3": 0.0, "dg": -1.0, "force_len": 32.0, "repeat_short": False}

ORDER = [
    row(1, 12), row(2, 13),                                   # intro: bass + arps
    row(3, 16), row(4, 17), row(3, 18), row(5, 19),           # Sunny's theme
    row(3, 16), row(4, 17), row(3, 18), row(5, 19),
    row(6, 20), row(7, 21), row(8, 22), row(9, 23),           # Hex's theme
    row(6, 14), row(7, 15),                                   # arp breakdown
    row(10, 24), row(11, 25),                                 # bridge
    row(3, 18), row(5, 19),                                   # home again
]
SONGS = [{"loop_row": 2.0, "name": "POLARITY THEME", "loop": True, "order": ORDER}]

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
    m["instruments"] = copy.deepcopy(INSTRUMENTS)
    m["patterns"] = copy.deepcopy(PATTERNS)
    m["songs"] = copy.deepcopy(SONGS)
    m["play_speed"] = 6.0
    m["voice_mask"] = 3.0
    m["song_loop"] = True
    m["song_loop_row"] = 2.0
    m["filt_mode"] = 1.0          # low-pass, for the bass voice
    m["filt_res"] = 10.0
    m["filt_cut"] = 1152.0
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
