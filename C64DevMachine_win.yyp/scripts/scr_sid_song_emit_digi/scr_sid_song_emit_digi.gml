/// MACRO_SID_SONG DIGI TRACK — $D418 sample playback driven by a CIA2 timer NMI.
///
/// The IRQ side (the song's <key>_play) reads two digi bytes per row:
///   byte 0  $FF nothing (a playing sample carries on), $FE OFF (cut),
///           else a VARIANT index: one sample at one note
///   byte 1  volume 0-3 (0 = 1/4 ... 3 = full)
///
/// NOTES: the NMI always runs at the tune's digi rate. A note other than C-4
/// is a separate copy of the sample, resampled at build time so it plays at
/// that pitch at the fixed rate (the editor preview speeds the sound up or
/// down instead — the same result). An earlier version changed the timer rate
/// per note, but the handler (~120 cycles with the KERNAL's NMI entry) can't
/// keep up above ~7 kHz, so high notes came out flat on a real C64. Each
/// distinct sample+note used costs its own bytes (the DIGI byte count shows it).
/// and starts or stops the NMI player. The NMI runs once per sample at the
/// tune's digi rate (CIA2 timer A, continuous) and writes
///     volume_table[level] | (music's $D418 filter-mode bits)
/// to $D418, so the music's filter settings survive under the digi.
///
/// Packing (per SAMPLE asset, see scr_sample_encode_at):
///   4-bit  two samples per byte, first in the low nibble
///   2-bit  delta, four per byte from bit 0 up, level += -3/-1/+1/+3 from 8
///
/// The NMI vector is set at $0318 (KERNAL in) AND $FFFA (KERNAL out — a write
/// there lands in the RAM under the ROM), so it works in either banking. While
/// no sample is playing the handler ignores NMIs, so RESTORE does nothing.
///
/// Only the shared row clock is supported; with TIMING: PER VOICE the digi
/// track is left out of the build (a debug message says so).

/// Average NMI cost in cycles, for the CPU estimate in the editor: the handler
/// (98 / 128 on alternate samples) plus the 6502's interrupt entry and the
/// KERNAL's NMI stub.
#macro DIGI_NMI_CYCLES 127
/// Digi step speed command (step.spd): 0 none, 1-31 frames a digi row from
/// this row on, DIGI_SPD_SONG (F00) back to the song's rows.
#macro DIGI_SPD_MAX 31
#macro DIGI_SPD_SONG 32
/// Most sample+note variants one tune can use (byte 0 values $FE/$FF are taken).
#macro DIGI_MAX_VARIANTS 200

/// Collects everything the digi track needs. Returns { used, ... }; used is
/// false when the song has no digi steps (or can't have them), and then nothing
/// at all is emitted.
function scr_sid_song_digi_plan(_sm, _song_order, _n_ord, _free, _asset_name) {
    var _plan = { used: false, ord: [], pats: [], slots: [], rate: 8000, latch: 0, boost: 0, speed: 0 };
    var _dpats = _sm[$ "digi_patterns"];
    var _dslots = _sm[$ "digi_samples"];
    if (!is_array(_dpats) || !is_array(_dslots) || array_length(_dpats) == 0) {
        return _plan;
    }
    // VOICES row SMP OFF: leave the digi track out, like a voice switched off.
    var _don = _sm[$ "digi_on"];
    if (!is_undefined(_don) && real(_don) == 0) {
        return _plan;
    }
    var _rate = _sm[$ "digi_rate"];
    if (is_undefined(_rate)) {
        _rate = 8000;
    }
    _plan.rate  = clamp(real(_rate), 1000, 16000);
    var _boost = _sm[$ "digi_boost"];
    if (!is_undefined(_boost)) {
        _plan.boost = clamp(real(_boost), 0, 3);
    }
    _plan.latch = scr_sample_cia_latch(_plan.rate);
    // DIGI SPEED: 0 = rows go with the song's rows, 1-31 = own frames a row.
    var _dspd = _sm[$ "digi_speed"];
    if (!is_undefined(_dspd)) {
        _plan.speed = clamp(round(real(_dspd)), 0, 31);
    }

    // Which digi patterns the order rows use, renumbered densely.
    var _remap = array_create(array_length(_dpats), -1);
    var _ord = [];
    var _any_row = false;
    for (var _oi = 0; _oi < _n_ord; _oi++) {
        var _dg = _song_order[_oi][$ "dg"];
        if (is_undefined(_dg)) {
            _dg = -1;
        }
        _dg = real(_dg);
        if (_dg >= 0 && _dg < array_length(_dpats)) {
            if (_remap[_dg] < 0) {
                _remap[_dg] = array_length(_plan.pats);
                array_push(_plan.pats, _dpats[_dg]);
            }
            array_push(_ord, _remap[_dg]);
            _any_row = true;
        } else {
            array_push(_ord, 0xFF);
        }
    }
    if (!_any_row) {
        return _plan;
    }
    if (_free) {
        show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' has a digi track but uses TIMING: PER VOICE;"
            + " the digi track needs the shared row clock and is left out of this build.");
        return _plan;
    }

    // Sample+note variants the used patterns trigger, each encoded so it
    // plays at its note's pitch at the tune's fixed rate.
    var _var_map = {};            // "slot:note" -> variant index (-1 = no audio)
    var _pat_bytes = [];
    var _any_step = false;
    for (var _pi = 0; _pi < array_length(_plan.pats); _pi++) {
        var _pat = _plan.pats[_pi];
        var _len = clamp(real(_pat.pattern_len), 1, 255);
        var _bytes = [];
        for (var _si = 0; _si < _len; _si++) {
            var _b = 0xFF;
            var _vol = 3;
            if (_si < array_length(_pat.steps)) {
                var _st = _pat.steps[_si];
                var _smp = real(_st.smp);
                if (_smp == DIGI_SMP_OFF) {
                    _b = 0xFE;
                    _any_step = true;
                } else if (_smp >= 0 && _smp < DIGI_SLOTS) {
                    var _nt = DIGI_NOTE_BASE;
                    if (!is_undefined(_st[$ "note"])) {
                        _nt = clamp(round(real(_st.note)), 0, 95);
                    }
                    var _vkey = string(_smp) + ":" + string(_nt);
                    var _vi = _var_map[$ _vkey];
                    if (is_undefined(_vi)) {
                        _vi = -1;
                        var _name = "";
                        if (_smp < array_length(_dslots)) {
                            _name = _dslots[_smp];
                        }
                        var _a = scr_digi_find_sample(_name);
                        if (is_undefined(_a)) {
                            show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' digi slot " + string(_smp)
                                + " has no sample ('" + _name + "'); its steps are skipped.");
                        } else if (array_length(_plan.slots) >= DIGI_MAX_VARIANTS) {
                            show_debug_message("MACRO_SID_SONG: '" + _asset_name + "' uses more than "
                                + string(DIGI_MAX_VARIANTS) + " sample+note combinations; the rest are skipped.");
                        } else {
                            // Encoding at rate / ratio and playing at rate shifts the
                            // pitch by ratio: up an octave = half the samples.
                            var _ratio = power(2, (_nt - DIGI_NOTE_BASE) / 12);
                            var _enc = scr_sample_encode_at(_a, _plan.rate / _ratio, _a.meta.pack);
                            if (array_length(_enc.packed) > 0) {
                                _vi = array_length(_plan.slots);
                                array_push(_plan.slots, { name: _name + " " + scr_digi_note_name(_nt),
                                                          packed: _enc.packed, pack: _a.meta.pack });
                            }
                        }
                        _var_map[$ _vkey] = _vi;
                    }
                    if (_vi >= 0) {
                        _b = _vi;
                        _vol = clamp(real(_st.vol), 0, 3);
                        _any_step = true;
                    }
                }
            }
            // Byte 1: volume in bits 0-1, speed command in bits 2-7.
            var _code = 0;
            if (_si < array_length(_pat.steps)) {
                var _sp_v = _pat.steps[_si][$ "spd"];
                if (!is_undefined(_sp_v)) {
                    _code = clamp(round(real(_sp_v)), 0, DIGI_SPD_SONG);
                }
            }
            if (_code > 0) {
                _any_step = true;
            }
            array_push(_bytes, _b);
            array_push(_bytes, _vol | (_code << 2));
        }
        array_push(_pat_bytes, _bytes);
    }
    if (!_any_step) {
        return _plan;
    }
    _plan.ord = _ord;
    _plan.pat_bytes = _pat_bytes;
    _plan.used = true;
    return _plan;
}

/// Data: per-order-row digi pattern, digi patterns, sample slot tables, the
/// samples themselves, volume tables and the NMI's variables. Goes in the
/// song's (jumped-over) data block.
function scr_sid_song_digi_emit_data(_list, _id, _key, _plan) {
    var _k = _key;
    array_push(_list, ["label", _k + "dgord"]);
    for (var _oi = 0; _oi < array_length(_plan.ord); _oi++) {
        array_push(_list, ["byte", _plan.ord[_oi] & 0xFF, _id]);
    }
    var _np = array_length(_plan.pat_bytes);
    for (var _pi = 0; _pi < _np; _pi++) {
        array_push(_list, ["label", _k + "dgpat" + string(_pi)]);
        var _pb = _plan.pat_bytes[_pi];
        for (var _bi = 0; _bi < array_length(_pb); _bi++) {
            array_push(_list, ["byte", _pb[_bi], _id]);
        }
    }
    array_push(_list, ["label", _k + "dgppl"]);
    for (var _pi = 0; _pi < _np; _pi++) {
        array_push(_list, ["byte_lab_lo", _k + "dgpat" + string(_pi), _id]);
    }
    array_push(_list, ["label", _k + "dgpph"]);
    for (var _pi = 0; _pi < _np; _pi++) {
        array_push(_list, ["byte_lab_hi", _k + "dgpat" + string(_pi), _id]);
    }
    array_push(_list, ["label", _k + "dglen"]);
    for (var _pi = 0; _pi < _np; _pi++) {
        array_push(_list, ["byte", (array_length(_plan.pat_bytes[_pi]) div 2) & 0xFF, _id]);   // rows
    }

    // Sample slots: start, byte count, decoder.
    var _ns = array_length(_plan.slots);
    for (var _si = 0; _si < _ns; _si++) {
        array_push(_list, ["label", _k + "dgsmp" + string(_si)]);
        var _pk = _plan.slots[_si].packed;
        for (var _bi = 0; _bi < array_length(_pk); _bi++) {
            array_push(_list, ["byte", _pk[_bi] & 0xFF, _id]);
        }
    }
    array_push(_list, ["label", _k + "dgsl"]);
    for (var _si = 0; _si < _ns; _si++) {
        array_push(_list, ["byte_lab_lo", _k + "dgsmp" + string(_si), _id]);
    }
    array_push(_list, ["label", _k + "dgsh"]);
    for (var _si = 0; _si < _ns; _si++) {
        array_push(_list, ["byte_lab_hi", _k + "dgsmp" + string(_si), _id]);
    }
    array_push(_list, ["label", _k + "dgcl"]);
    for (var _si = 0; _si < _ns; _si++) {
        array_push(_list, ["byte", array_length(_plan.slots[_si].packed) & 0xFF, _id]);
    }
    array_push(_list, ["label", _k + "dgch"]);
    for (var _si = 0; _si < _ns; _si++) {
        array_push(_list, ["byte", (array_length(_plan.slots[_si].packed) >> 8) & 0xFF, _id]);
    }
    array_push(_list, ["label", _k + "dgml"]);
    for (var _si = 0; _si < _ns; _si++) {
        var _h = _k + "dgn4";
        if (_plan.slots[_si].pack == 1) {
            _h = _k + "dgd2";
        }
        array_push(_list, ["byte_lab_lo", _h, _id]);
    }
    array_push(_list, ["label", _k + "dgmh"]);
    for (var _si = 0; _si < _ns; _si++) {
        var _h2 = _k + "dgn4";
        if (_plan.slots[_si].pack == 1) {
            _h2 = _k + "dgd2";
        }
        array_push(_list, ["byte_lab_hi", _h2, _id]);
    }

    // Volume tables: 4 x 16, level scaled about the 7.5 centre.
    var _scale = [0.25, 0.5, 0.75, 1.0];
    for (var _v = 0; _v < 4; _v++) {
        array_push(_list, ["label", _k + "dgvt" + string(_v)]);
        for (var _l = 0; _l < 16; _l++) {
            var _out = clamp(round((_l - 7.5) * _scale[_v] + 7.5), 0, 15);
            array_push(_list, ["byte", _out, _id]);
        }
    }
    array_push(_list, ["label", _k + "dgvtl"]);
    for (var _v = 0; _v < 4; _v++) {
        array_push(_list, ["byte_lab_lo", _k + "dgvt" + string(_v), _id]);
    }
    array_push(_list, ["label", _k + "dgvth"]);
    for (var _v = 0; _v < 4; _v++) {
        array_push(_list, ["byte_lab_hi", _k + "dgvt" + string(_v), _id]);
    }
    // 2-bit delta steps: -3, -1, +1, +3.
    array_push(_list, ["label", _k + "dgdt"]);
    array_push(_list, ["byte", 0xFD, _id]);
    array_push(_list, ["byte", 0xFF, _id]);
    array_push(_list, ["byte", 0x01, _id]);
    array_push(_list, ["byte", 0x03, _id]);

    // NMI state.
    var _vars = ["dgact", "dgph", "dgby", "dglv", "dghi", "dgcnl", "dgcnh", "dgvol", "dgpi", "dgrc", "dgcn", "dgsp"];
    for (var _vi = 0; _vi < array_length(_vars); _vi++) {
        array_push(_list, ["label", _k + _vars[_vi]]);
        array_push(_list, ["byte", 0, _id]);
    }
}

/// Runtime: <key>dgnmi (the NMI handler), <key>dgsync / <key>dgtick / <key>dgplay
/// (the digi lane's rows, called by the IRQ player), <key>dgstart, <key>dgstop
/// and <key>dginit.
/// Self-modified operands are written as raw bytes with a label on each
/// operand byte, because the assembler can't take label+offset operands.
function scr_sid_song_digi_emit_runtime(_list, _id, _key, _plan, _chip_base, _S_ORD, _S_ROW, _S_PTR) {
    var _k = _key;
    var _D418 = _chip_base + 0x18;

    // ── NMI ──
    array_push(_list, ["label",   _k + "dgnmi"]);
    array_push(_list, ["pha",     0, _id]);
    array_push(_list, ["txa",     0, _id]);
    array_push(_list, ["pha",     0, _id]);
    array_push(_list, ["lda_abs", _k + "dgact", _id]);
    array_push(_list, ["bne",     _k + "dgon", _id]);
    array_push(_list, ["jmp_abs", _k + "dgquit", _id]);     // idle: RESTORE etc.
    array_push(_list, ["label",   _k + "dgon"]);
    array_push(_list, ["cmp_imm", 0x02, _id]);             // 2 = last sample went out
    array_push(_list, ["bne",     _k + "dgplay", _id]);
    array_push(_list, ["jmp_abs", _k + "dgend", _id]);
    array_push(_list, ["label",   _k + "dgplay"]);
    // Fetch a new byte when the decoder starts one.
    array_push(_list, ["lda_abs", _k + "dgph", _id]);
    array_push(_list, ["bne",     _k + "dgnof", _id]);
    array_push(_list, ["byte",    0xAD, _id]);              // LDA abs (self-modified)
    array_push(_list, ["label",   _k + "dgfl"]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["label",   _k + "dgfh"]);
    array_push(_list, ["byte",    0x00, _id]);
    array_push(_list, ["sta_abs", _k + "dgby", _id]);
    array_push(_list, ["label",   _k + "dgnof"]);
    array_push(_list, ["byte",    0x4C, _id]);              // JMP abs (self-modified): decoder
    array_push(_list, ["label",   _k + "dgjl"]);
    array_push(_list, ["byte_lab_lo", _k + "dgn4", _id]);
    array_push(_list, ["label",   _k + "dgjh"]);
    array_push(_list, ["byte_lab_hi", _k + "dgn4", _id]);

    // 4-bit: low nibble, then high nibble and next byte.
    array_push(_list, ["label",   _k + "dgn4"]);
    array_push(_list, ["lda_abs", _k + "dgph", _id]);
    array_push(_list, ["bne",     _k + "dgn4h", _id]);
    array_push(_list, ["inc_abs", _k + "dgph", _id]);
    array_push(_list, ["lda_abs", _k + "dgby", _id]);
    array_push(_list, ["and_imm", 0x0F, _id]);
    array_push(_list, ["sta_abs", _k + "dglv", _id]);
    array_push(_list, ["jmp_abs", _k + "dgout", _id]);
    array_push(_list, ["label",   _k + "dgn4h"]);
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["sta_abs", _k + "dgph", _id]);
    array_push(_list, ["lda_abs", _k + "dgby", _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["sta_abs", _k + "dglv", _id]);
    array_push(_list, ["jmp_abs", _k + "dgadv", _id]);

    // 2-bit delta: four codes per byte.
    array_push(_list, ["label",   _k + "dgd2"]);
    array_push(_list, ["lda_abs", _k + "dgby", _id]);
    array_push(_list, ["and_imm", 0x03, _id]);
    array_push(_list, ["tax",     0, _id]);
    array_push(_list, ["lda_abs", _k + "dglv", _id]);
    array_push(_list, ["clc",     0, _id]);
    array_push(_list, ["adc_abx", _k + "dgdt", _id]);
    array_push(_list, ["and_imm", 0x0F, _id]);
    array_push(_list, ["sta_abs", _k + "dglv", _id]);
    array_push(_list, ["lda_abs", _k + "dgby", _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["sta_abs", _k + "dgby", _id]);
    array_push(_list, ["inc_abs", _k + "dgph", _id]);
    array_push(_list, ["lda_abs", _k + "dgph", _id]);
    array_push(_list, ["cmp_imm", 0x04, _id]);
    array_push(_list, ["bne",     _k + "dgout", _id]);
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["sta_abs", _k + "dgph", _id]);
    // falls into dgadv

    // Next byte; stop at the end.
    array_push(_list, ["label",   _k + "dgadv"]);
    array_push(_list, ["inc_abs", _k + "dgfl", _id]);
    array_push(_list, ["bne",     _k + "dgadv1", _id]);
    array_push(_list, ["inc_abs", _k + "dgfh", _id]);
    array_push(_list, ["label",   _k + "dgadv1"]);
    array_push(_list, ["lda_abs", _k + "dgcnl", _id]);
    array_push(_list, ["bne",     _k + "dgadv2", _id]);
    array_push(_list, ["dec_abs", _k + "dgcnh", _id]);
    array_push(_list, ["label",   _k + "dgadv2"]);
    array_push(_list, ["dec_abs", _k + "dgcnl", _id]);
    array_push(_list, ["lda_abs", _k + "dgcnl", _id]);
    array_push(_list, ["ora_abs", _k + "dgcnh", _id]);
    array_push(_list, ["bne",     _k + "dgout", _id]);
    // Last byte: output this sample, end on the next NMI.
    array_push(_list, ["lda_imm", 0x02, _id]);
    array_push(_list, ["sta_abs", _k + "dgact", _id]);
    array_push(_list, ["jmp_abs", _k + "dgout", _id]);
    // End of sample (one NMI after the last one): timer off, music volume back.
    array_push(_list, ["label",   _k + "dgend"]);
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["sta_abs", _k + "dgact", _id]);
    array_push(_list, ["lda_imm", 0x01, _id]);
    array_push(_list, ["sta_abs", 0xDD0D, _id]);
    array_push(_list, ["lda_abs", 0xDD0E, _id]);
    array_push(_list, ["and_imm", 0xFE, _id]);
    array_push(_list, ["sta_abs", 0xDD0E, _id]);
    array_push(_list, ["lda_abs", _k + "f18", _id]);
    array_push(_list, ["sta_abs", _D418, _id]);
    array_push(_list, ["jmp_abs", _k + "dgquit", _id]);

    // Output: volume table (self-modified base) | music filter-mode bits.
    array_push(_list, ["label",   _k + "dgout"]);
    array_push(_list, ["ldx_abs", _k + "dglv", _id]);
    array_push(_list, ["byte",    0xBD, _id]);              // LDA abs,X (self-modified)
    array_push(_list, ["label",   _k + "dgvl"]);
    array_push(_list, ["byte_lab_lo", _k + "dgvt3", _id]);
    array_push(_list, ["label",   _k + "dgvh"]);
    array_push(_list, ["byte_lab_hi", _k + "dgvt3", _id]);
    array_push(_list, ["ora_abs", _k + "dghi", _id]);
    array_push(_list, ["sta_abs", _D418, _id]);
    array_push(_list, ["label",   _k + "dgquit"]);
    // Acknowledge CIA2 LAST: the NMI line stays low until now, so a timer
    // underflow during the handler can't start a second NMI inside this one
    // (it is dropped instead, which just costs one sample on a busy frame).
    array_push(_list, ["lda_abs", 0xDD0D, _id]);
    array_push(_list, ["pla",     0, _id]);
    array_push(_list, ["tax",     0, _id]);
    array_push(_list, ["pla",     0, _id]);
    array_push(_list, ["rti",     0, _id]);

    // ── STOP ── safe to call any time.
    array_push(_list, ["label",   _k + "dgstop"]);
    array_push(_list, ["lda_imm", 0x01, _id]);
    array_push(_list, ["sta_abs", 0xDD0D, _id]);            // timer A interrupt off
    array_push(_list, ["lda_abs", 0xDD0E, _id]);
    array_push(_list, ["and_imm", 0xFE, _id]);              // timer A stopped (TOD bit kept)
    array_push(_list, ["sta_abs", 0xDD0E, _id]);
    array_push(_list, ["lda_abs", 0xDD0D, _id]);            // clear anything pending
    array_push(_list, ["lda_abs", _k + "dgact", _id]);
    array_push(_list, ["beq",     _k + "dgst1", _id]);
    array_push(_list, ["lda_abs", _k + "f18", _id]);        // music volume back
    array_push(_list, ["sta_abs", _D418, _id]);
    array_push(_list, ["label",   _k + "dgst1"]);
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["sta_abs", _k + "dgact", _id]);
    array_push(_list, ["rts",     0, _id]);

    // ── START ── A = digi step byte (slot | volume << 4).
    array_push(_list, ["label",   _k + "dgstart"]);
    array_push(_list, ["pha",     0, _id]);
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["sta_abs", _k + "dgact", _id]);      // NMI stands down while we rewire it
    array_push(_list, ["lda_imm", 0x01, _id]);
    array_push(_list, ["sta_abs", 0xDD0D, _id]);
    array_push(_list, ["pla",     0, _id]);
    array_push(_list, ["tax",     0, _id]);                 // X = variant
    array_push(_list, ["lda_abx", _k + "dgsl", _id]);
    array_push(_list, ["sta_abs", _k + "dgfl", _id]);
    array_push(_list, ["lda_abx", _k + "dgsh", _id]);
    array_push(_list, ["sta_abs", _k + "dgfh", _id]);
    array_push(_list, ["lda_abx", _k + "dgcl", _id]);
    array_push(_list, ["sta_abs", _k + "dgcnl", _id]);
    array_push(_list, ["lda_abx", _k + "dgch", _id]);
    array_push(_list, ["sta_abs", _k + "dgcnh", _id]);
    array_push(_list, ["lda_abx", _k + "dgml", _id]);
    array_push(_list, ["sta_abs", _k + "dgjl", _id]);
    array_push(_list, ["lda_abx", _k + "dgmh", _id]);
    array_push(_list, ["sta_abs", _k + "dgjh", _id]);
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["sta_abs", _k + "dgph", _id]);
    array_push(_list, ["lda_imm", 0x08, _id]);
    array_push(_list, ["sta_abs", _k + "dglv", _id]);        // delta start level
    array_push(_list, ["lda_abs", _k + "dgvol", _id]);
    array_push(_list, ["and_imm", 0x03, _id]);
    array_push(_list, ["tax",     0, _id]);
    array_push(_list, ["lda_abx", _k + "dgvtl", _id]);
    array_push(_list, ["sta_abs", _k + "dgvl", _id]);
    array_push(_list, ["lda_abx", _k + "dgvth", _id]);
    array_push(_list, ["sta_abs", _k + "dgvh", _id]);
    array_push(_list, ["lda_imm", 0x01, _id]);
    array_push(_list, ["sta_abs", _k + "dgact", _id]);
    array_push(_list, ["lda_abs", 0xDD0D, _id]);            // drop a stale flag
    array_push(_list, ["lda_imm", 0x81, _id]);
    array_push(_list, ["sta_abs", 0xDD0D, _id]);            // timer A interrupt on
    array_push(_list, ["lda_abs", 0xDD0E, _id]);
    array_push(_list, ["and_imm", 0x80, _id]);              // keep TOD 50/60 Hz bit
    array_push(_list, ["ora_imm", 0x11, _id]);              // start, continuous, force load
    array_push(_list, ["sta_abs", 0xDD0E, _id]);
    array_push(_list, ["rts",     0, _id]);

    // ── ROW TRIGGER ── called by the shared row clock before it advances.
    // Uses the song's _S_PTR as scratch, like the voices before it.
    // ── DIGI ROWS ──
    // The digi lane has its own row (dgrc) in its own pattern (dgpi). Speed
    // dgsp: 0 = follow the song's rows, 1-31 = own clock, frames a row. It
    // starts at DIGI SPEED and an Fxx step changes it. Every order row's
    // first row restarts the lane at row 0.
    //   <key>dgsync  every song row (from the row clock)
    //   <key>dgtick  every frame, after the song's rows
    //   <key>dgplay  plays row dgrc: volume, speed command, sample
    array_push(_list, ["label",   _k + "dgsync"]);
    array_push(_list, ["lda_zp",  _S_ROW, _id]);
    array_push(_list, ["bne",     _k + "dgsn", _id]);
    array_push(_list, ["ldx_zp",  _S_ORD, _id]);
    array_push(_list, ["lda_abx", _k + "dgord", _id]);
    array_push(_list, ["sta_abs", _k + "dgpi", _id]);
    array_push(_list, ["lda_imm", 0xFF, _id]);
    array_push(_list, ["sta_abs", _k + "dgrc", _id]);
    array_push(_list, ["lda_abs", _k + "dgsp", _id]);
    array_push(_list, ["beq",     _k + "dgsf", _id]);
    array_push(_list, ["lda_imm", 0x01, _id]);
    array_push(_list, ["sta_abs", _k + "dgcn", _id]);       // own clock: row 0 this frame
    array_push(_list, ["rts",     0, _id]);
    array_push(_list, ["label",   _k + "dgsn"]);
    array_push(_list, ["lda_abs", _k + "dgsp", _id]);
    array_push(_list, ["bne",     _k + "dgsx", _id]);       // own clock: song rows don't step it
    array_push(_list, ["ldx_zp",  _S_ORD, _id]);
    array_push(_list, ["lda_abx", _k + "dgord", _id]);
    array_push(_list, ["sta_abs", _k + "dgpi", _id]);
    array_push(_list, ["label",   _k + "dgsf"]);
    array_push(_list, ["lda_zp",  _S_ROW, _id]);
    array_push(_list, ["sta_abs", _k + "dgrc", _id]);
    array_push(_list, ["jsr",     _k + "dgplay", _id]);
    // An Fxx here just started the own clock; dgtick also runs this frame,
    // so one extra count keeps the row xx frames long.
    array_push(_list, ["lda_abs", _k + "dgsp", _id]);
    array_push(_list, ["beq",     _k + "dgsx", _id]);
    array_push(_list, ["inc_abs", _k + "dgcn", _id]);
    array_push(_list, ["label",   _k + "dgsx"]);
    array_push(_list, ["rts",     0, _id]);

    array_push(_list, ["label",   _k + "dgtick"]);
    array_push(_list, ["lda_abs", _k + "dgsp", _id]);
    array_push(_list, ["beq",     _k + "dgrx", _id]);
    array_push(_list, ["dec_abs", _k + "dgcn", _id]);
    array_push(_list, ["bne",     _k + "dgrx", _id]);
    array_push(_list, ["lda_abs", _k + "dgsp", _id]);
    array_push(_list, ["sta_abs", _k + "dgcn", _id]);
    array_push(_list, ["inc_abs", _k + "dgrc", _id]);

    array_push(_list, ["label",   _k + "dgplay"]);
    array_push(_list, ["lda_abs", _k + "dgpi", _id]);
    array_push(_list, ["cmp_imm", 0xFF, _id]);
    array_push(_list, ["beq",     _k + "dgrx", _id]);
    array_push(_list, ["tax",     0, _id]);
    array_push(_list, ["lda_abs", _k + "dgrc", _id]);
    array_push(_list, ["cmp_abx", _k + "dglen", _id]);
    array_push(_list, ["bcs",     _k + "dgrx", _id]);      // past this digi pattern's end
    array_push(_list, ["lda_abx", _k + "dgppl", _id]);
    array_push(_list, ["sta_zp",  _S_PTR, _id]);
    array_push(_list, ["lda_abx", _k + "dgpph", _id]);
    array_push(_list, ["sta_zp",  _S_PTR + 1, _id]);
    array_push(_list, ["lda_abs", _k + "dgrc", _id]);
    array_push(_list, ["asl_a",   0, _id]);                 // 2 bytes a row (rows <= 128)
    array_push(_list, ["tay",     0, _id]);
    array_push(_list, ["iny",     0, _id]);
    array_push(_list, ["lda_izy", _S_PTR, _id]);
    array_push(_list, ["sta_abs", _k + "dgvol", _id]);      // volume (dgstart masks bits 0-1)
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["beq",     _k + "dgnc", _id]);       // no speed command
    array_push(_list, ["cmp_imm", DIGI_SPD_SONG, _id]);
    array_push(_list, ["bne",     _k + "dgss", _id]);
    array_push(_list, ["lda_imm", 0x00, _id]);              // F00: follow the song's rows
    array_push(_list, ["label",   _k + "dgss"]);
    array_push(_list, ["sta_abs", _k + "dgsp", _id]);
    array_push(_list, ["sta_abs", _k + "dgcn", _id]);
    array_push(_list, ["label",   _k + "dgnc"]);
    array_push(_list, ["dey",     0, _id]);
    array_push(_list, ["lda_izy", _S_PTR, _id]);
    array_push(_list, ["cmp_imm", 0xFF, _id]);
    array_push(_list, ["beq",     _k + "dgrx", _id]);
    array_push(_list, ["cmp_imm", 0xFE, _id]);
    array_push(_list, ["bne",     _k + "dgrt", _id]);
    array_push(_list, ["jmp_abs", _k + "dgstop", _id]);
    array_push(_list, ["label",   _k + "dgrt"]);
    array_push(_list, ["jmp_abs", _k + "dgstart", _id]);
    array_push(_list, ["label",   _k + "dgrx"]);
    array_push(_list, ["rts",     0, _id]);

    // ── INIT ── vectors (and the boost voice). Called from <key>_init.
    array_push(_list, ["label",   _k + "dginit"]);
    if (_plan.boost > 0) {
        // BOOST: the voice's pulse output is forced high by the TEST bit and
        // the envelope sits at sustain 15, so the voice puts a constant full
        // DC level into the mixer. $D418's volume nibble scales the whole
        // mix, so the digi now has a big DC level to modulate — the 8580's own
        // offset is too small to hear. The music doesn't drive this voice.
        var _bv = _chip_base + (_plan.boost - 1) * 7;
        array_push(_list, ["lda_imm", 0x00, _id]);
        array_push(_list, ["sta_abs", _bv + 0, _id]);       // frequency 0
        array_push(_list, ["sta_abs", _bv + 1, _id]);
        array_push(_list, ["sta_abs", _bv + 2, _id]);       // pulse width 0
        array_push(_list, ["sta_abs", _bv + 3, _id]);
        array_push(_list, ["sta_abs", _bv + 5, _id]);       // attack 0, decay 0
        array_push(_list, ["lda_imm", 0xF0, _id]);
        array_push(_list, ["sta_abs", _bv + 6, _id]);       // sustain 15, release 0
        array_push(_list, ["lda_imm", 0x49, _id]);
        array_push(_list, ["sta_abs", _bv + 4, _id]);       // pulse + TEST + gate
    }
    array_push(_list, ["lda_imm", 0xFF, _id]);
    array_push(_list, ["sta_abs", _k + "dgpi", _id]);       // no digi pattern until a sync
    array_push(_list, ["lda_imm", _plan.speed, _id]);
    array_push(_list, ["sta_abs", _k + "dgsp", _id]);       // DIGI SPEED (0 = song rows)
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["sta_abs", _k + "dgact", _id]);
    array_push(_list, ["lda_lab_lo", _k + "dgnmi", _id]);
    array_push(_list, ["sta_abs", 0x0318, _id]);
    array_push(_list, ["sta_abs", 0xFFFA, _id]);
    array_push(_list, ["lda_lab_hi", _k + "dgnmi", _id]);
    array_push(_list, ["sta_abs", 0x0319, _id]);
    array_push(_list, ["sta_abs", 0xFFFB, _id]);
    array_push(_list, ["lda_imm", _plan.latch & 0xFF, _id]);   // the tune's one digi rate
    array_push(_list, ["sta_abs", 0xDD04, _id]);
    array_push(_list, ["lda_imm", (_plan.latch >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_abs", 0xDD05, _id]);
    array_push(_list, ["jmp_abs", _k + "dgstop", _id]);
}
