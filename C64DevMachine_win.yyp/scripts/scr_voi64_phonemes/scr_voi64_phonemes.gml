/// ====================================================================
/// VOI64 — PHONEME MODEL
///
/// An original formant model, written from published acoustic phonetics.
/// Nothing here derives from SAM or any disassembly of it: the vowel
/// targets are the Peterson & Barney (1952) adult-male formant means,
/// the consonant figures are standard textbook values, and the synthesis
/// model is a three-resonator PARALLEL bank.
///
/// Parallel, not cascade, on purpose. Three resonators summed is exactly
/// what three SID voices summed will be, so the GML preview in
/// scr_voi64_render and the eventual 6502 player describe the same
/// machine. Tune the numbers here, hear them on the PC, and the SID
/// player inherits the tuning rather than needing its own.
///
/// PHONEME RECORD
///   nm    name, ARPABET-style
///   kind  "VOW" vowel   "DIP" diphthong  "NAS" nasal   "LIQ" liquid/glide
///         "STP" stop    "FRI" fricative  "AFF" affricate "SIL" silence
///   f1..3 formant centres, Hz
///   b1..3 formant bandwidths, Hz — wider = duller, narrower = more nasal
///   a1..3 formant amplitudes 0-15. Chosen 0-15 so each drops straight
///         into a SID sustain nibble with no rescaling on the C64 side.
///   dur   nominal length in 100Hz frames (the player's frame rate)
///   vcd   glottal excitation 0-15  (voicing)
///   nz    noise excitation 0-15    (frication / aspiration / burst)
///   nf    noise centre, Hz. 0 means "use f2".
///   gl    glide target phoneme for diphthongs, "" otherwise
///   sil   leading silence in frames — stops need a closure before the burst
///
/// AMPLITUDE CONVENTION
/// a1 dominates for vowels and a3 is always the quietest; that falling
/// tilt is what makes a formant stack read as a voice rather than as a
/// chord. Resist the urge to level them.
/// ====================================================================

/// @function scr_voi64_ph(_nm, _kind, _f1, _f2, _f3, _a1, _a2, _a3, _dur, _vcd, _nz, _nf, _gl, _sil)
/// @desc One phoneme record. Bandwidths are derived rather than passed —
///       F1 sits narrow, F2 and F3 progressively wider, which is the usual
///       shape and one less column to hand-maintain across 45 entries.
function scr_voi64_ph(_nm, _kind, _f1, _f2, _f3, _a1, _a2, _a3, _dur, _vcd, _nz, _nf, _gl, _sil) {
    return {
        nm:   _nm,
        kind: _kind,
        f1:   _f1,  f2: _f2,  f3: _f3,
        b1:   90,   b2: 110,  b3: 170,
        a1:   _a1,  a2: _a2,  a3: _a3,
        dur:  _dur,
        vcd:  _vcd,
        nz:   _nz,
        nf:   _nf,
        gl:   _gl,
        sil:  _sil
    };
}

/// @function scr_voi64_phoneme_table()
/// @desc The whole set, built once and cached on a global. Returns a struct
///       keyed by phoneme name so lookup is a hash rather than a scan —
///       scr_voi64_render asks for one per frame and a sentence is hundreds
///       of frames.
function scr_voi64_phoneme_table() {
    if (variable_global_exists("voi64_ph_table")) {
        return global.voi64_ph_table;
    }

    var _t = {};

    // ── VOWELS ────────────────────────────────────────────────────────
    // Peterson & Barney adult-male means. These are the load-bearing
    // numbers: if the voice is unintelligible, it is almost always F2 on
    // the front vowels, not the consonants.
    //                       nm     kind   f1    f2    f3   a1 a2 a3  dur vcd nz  nf  gl  sil
    _t[$ "IY"] = scr_voi64_ph("IY", "VOW",  270, 2290, 3010, 15, 11,  7, 12, 15,  0,  0, "", 0);
    _t[$ "IH"] = scr_voi64_ph("IH", "VOW",  390, 1990, 2550, 15, 11,  7,  9, 15,  0,  0, "", 0);
    _t[$ "EH"] = scr_voi64_ph("EH", "VOW",  530, 1840, 2480, 15, 12,  7,  9, 15,  0,  0, "", 0);
    _t[$ "AE"] = scr_voi64_ph("AE", "VOW",  660, 1720, 2410, 15, 12,  6, 12, 15,  0,  0, "", 0);
    _t[$ "AA"] = scr_voi64_ph("AA", "VOW",  730, 1090, 2440, 15, 10,  5, 13, 15,  0,  0, "", 0);
    _t[$ "AO"] = scr_voi64_ph("AO", "VOW",  570,  840, 2410, 15,  9,  5, 12, 15,  0,  0, "", 0);
    _t[$ "UH"] = scr_voi64_ph("UH", "VOW",  440, 1020, 2240, 15,  9,  5,  8, 15,  0,  0, "", 0);
    _t[$ "UW"] = scr_voi64_ph("UW", "VOW",  300,  870, 2240, 15,  8,  4, 12, 15,  0,  0, "", 0);
    _t[$ "AH"] = scr_voi64_ph("AH", "VOW",  640, 1190, 2390, 15, 10,  5,  9, 15,  0,  0, "", 0);
    _t[$ "ER"] = scr_voi64_ph("ER", "VOW",  490, 1350, 1690, 15, 12,  9, 11, 15,  0,  0, "", 0);
    // Schwa. Short, weak, and everywhere — every unstressed vowel in
    // English collapses to this, which is most of why reduced speech
    // sounds natural and fully-articulated speech sounds like a robot.
    _t[$ "AX"] = scr_voi64_ph("AX", "VOW",  500, 1500, 2500, 12,  9,  5,  6, 15,  0,  0, "", 0);

    // ── DIPHTHONGS ────────────────────────────────────────────────────
    // Held at the first target, then glided to gl over the back half.
    // scr_voi64_render owns the glide; these only name the destination.
    _t[$ "EY"] = scr_voi64_ph("EY", "DIP",  530, 1840, 2480, 15, 12,  7, 16, 15,  0,  0, "IY", 0);
    _t[$ "AY"] = scr_voi64_ph("AY", "DIP",  730, 1090, 2440, 15, 10,  5, 17, 15,  0,  0, "IY", 0);
    _t[$ "OY"] = scr_voi64_ph("OY", "DIP",  570,  840, 2410, 15,  9,  5, 18, 15,  0,  0, "IY", 0);
    _t[$ "AW"] = scr_voi64_ph("AW", "DIP",  730, 1090, 2440, 15, 10,  5, 17, 15,  0,  0, "UH", 0);
    _t[$ "OW"] = scr_voi64_ph("OW", "DIP",  570,  840, 2410, 15,  9,  5, 16, 15,  0,  0, "UW", 0);

    // ── NASALS ────────────────────────────────────────────────────────
    // Low F1 and a weak upper stack: the mouth is shut, so the energy is
    // all in the nasal cavity. The place of articulation lives in F2.
    _t[$ "M" ] = scr_voi64_ph("M",  "NAS",  250, 1100, 2300, 12,  5,  3,  8, 14,  0,  0, "", 0);
    _t[$ "N" ] = scr_voi64_ph("N",  "NAS",  250, 1700, 2600, 12,  6,  3,  8, 14,  0,  0, "", 0);
    _t[$ "NG"] = scr_voi64_ph("NG", "NAS",  250, 2300, 2750, 12,  6,  3,  9, 14,  0,  0, "", 0);

    // ── LIQUIDS AND GLIDES ────────────────────────────────────────────
    // R is the one that matters: F3 dropping to ~1400 and nearly touching
    // F2 is the whole cue. Get F3 wrong and it turns into a W.
    _t[$ "L" ] = scr_voi64_ph("L",  "LIQ",  360, 1300, 2700, 14,  8,  5,  8, 15,  0,  0, "", 0);
    _t[$ "R" ] = scr_voi64_ph("R",  "LIQ",  310, 1060, 1380, 14, 10,  8,  9, 15,  0,  0, "", 0);
    _t[$ "W" ] = scr_voi64_ph("W",  "LIQ",  300,  610, 2200, 14,  8,  4,  7, 15,  0,  0, "", 0);
    _t[$ "Y" ] = scr_voi64_ph("Y",  "LIQ",  280, 2200, 3000, 14, 10,  6,  6, 15,  0,  0, "", 0);

    // ── UNVOICED FRICATIVES ───────────────────────────────────────────
    // Pure noise, no glottal source. S is the loudest and highest thing
    // in English speech — if S is quiet the whole voice sounds muffled.
    _t[$ "F" ] = scr_voi64_ph("F",  "FRI", 1000, 1500, 2500,  3,  5,  5, 11,  0,  7, 1500, "", 0);
    _t[$ "TH"] = scr_voi64_ph("TH", "FRI", 1000, 1800, 2600,  3,  5,  5, 11,  0,  6, 1800, "", 0);
    _t[$ "S" ] = scr_voi64_ph("S",  "FRI",  900, 5500, 6500,  2,  9, 11, 12,  0, 14, 5500, "", 0);
    _t[$ "SH"] = scr_voi64_ph("SH", "FRI",  900, 2800, 4200,  2, 11,  8, 12,  0, 13, 2800, "", 0);
    // Aspiration. Ideally H borrows the formants of whatever follows it;
    // this holds a neutral shape instead, which is the usual simplification
    // and costs surprisingly little intelligibility.
    _t[$ "HH"] = scr_voi64_ph("HH", "FRI",  500, 1500, 2500,  4,  5,  4,  7,  0,  6,    0, "", 0);

    // ── VOICED FRICATIVES ─────────────────────────────────────────────
    // Same noise shape as the unvoiced pair, plus a glottal source. The
    // voicing is the ONLY difference between S/Z and F/V.
    _t[$ "V" ] = scr_voi64_ph("V",  "FRI",  400, 1500, 2500,  8,  4,  4, 10, 10,  5, 1500, "", 0);
    _t[$ "DH"] = scr_voi64_ph("DH", "FRI",  400, 1800, 2600,  8,  4,  4, 10, 10,  4, 1800, "", 0);
    _t[$ "Z" ] = scr_voi64_ph("Z",  "FRI",  400, 5500, 6500,  8,  7,  8, 11, 10, 11, 5500, "", 0);
    _t[$ "ZH"] = scr_voi64_ph("ZH", "FRI",  400, 2800, 4200,  8,  9,  6, 11, 10, 10, 2800, "", 0);

    // ── UNVOICED STOPS ────────────────────────────────────────────────
    // A stop is a silence followed by a burst. The sil column is the
    // closure — drop it and the consonant vanishes, because the ear reads
    // the gap, not the click.
    _t[$ "P" ] = scr_voi64_ph("P",  "STP",  400, 1100, 2200,  3,  5,  4,  3,  0, 10, 1200, "", 5);
    _t[$ "T" ] = scr_voi64_ph("T",  "STP",  400, 1800, 2600,  3,  6,  7,  3,  0, 12, 4000, "", 5);
    _t[$ "K" ] = scr_voi64_ph("K",  "STP",  400, 1900, 2500,  3,  8,  6,  4,  0, 12, 2200, "", 5);

    // ── VOICED STOPS ──────────────────────────────────────────────────
    // Quieter burst, shorter closure, and a voice bar running through it.
    _t[$ "B" ] = scr_voi64_ph("B",  "STP",  300, 1100, 2200,  7,  4,  3,  3,  9,  5, 1200, "", 3);
    _t[$ "D" ] = scr_voi64_ph("D",  "STP",  300, 1800, 2600,  7,  5,  5,  3,  9,  6, 4000, "", 3);
    _t[$ "G" ] = scr_voi64_ph("G",  "STP",  300, 1900, 2500,  7,  6,  4,  4,  9,  6, 2200, "", 3);

    // ── AFFRICATES ────────────────────────────────────────────────────
    // A stop burst running straight into a fricative. Modelled as one unit
    // with a long noisy tail rather than as two phonemes, so the timing
    // cannot drift apart.
    _t[$ "CH"] = scr_voi64_ph("CH", "AFF",  900, 2800, 4200,  2, 11,  8, 12,  0, 13, 2800, "", 5);
    _t[$ "JH"] = scr_voi64_ph("JH", "AFF",  400, 2800, 4200,  7,  9,  6, 11,  9, 10, 2800, "", 3);

    // ── SILENCE ───────────────────────────────────────────────────────
    // SIL is an inter-word gap; PA is a longer sentence-level pause.
    _t[$ "SIL"] = scr_voi64_ph("SIL", "SIL", 500, 1500, 2500, 0, 0, 0,  6, 0, 0, 0, "", 0);
    _t[$ "PA" ] = scr_voi64_ph("PA",  "SIL", 500, 1500, 2500, 0, 0, 0, 20, 0, 0, 0, "", 0);

    global.voi64_ph_table = _t;
    return _t;
}

/// @function scr_voi64_phoneme(_nm)
/// @desc Look one up. Unknown names return the schwa rather than undefined —
///       a rule table with a typo in it should mumble, not crash a build.
function scr_voi64_phoneme(_nm) {
    var _t  = scr_voi64_phoneme_table();
    var _up = string_upper(string(_nm));
    if (variable_struct_exists(_t, _up)) {
        return _t[$ _up];
    }
    return _t[$ "AX"];
}

/// @function scr_voi64_phoneme_names()
/// @desc Every phoneme name, for the picker on MACRO_VOI64_SAY's phoneme
///       mode and for validating a hand-typed phoneme string.
function scr_voi64_phoneme_names() {
    return variable_struct_get_names(scr_voi64_phoneme_table());
}

/// @function scr_voi64_phoneme_valid(_nm)
/// @desc Does this name exist? Used by the SAY node to flag a typo in a
///       phoneme string instead of silently substituting schwa.
function scr_voi64_phoneme_valid(_nm) {
    var _t = scr_voi64_phoneme_table();
    return variable_struct_exists(_t, string_upper(string(_nm)));
}
