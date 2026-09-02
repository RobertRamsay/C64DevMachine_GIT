/// ====================================================================
/// VOI64 — SID FRAME EMITTER
///
/// Converts the parameter frames from scr_voi64_build_frames into the
/// exact bytes the C64 player writes to the SID, at compile time. The
/// 6502 side does no arithmetic at all: it copies eight bytes to eight
/// registers, waits a raster frame, and repeats. That is the whole
/// player, and it is the cross-development trick applied twice — first
/// to the letter-to-sound rules, now to the synthesis itself.
///
/// VOICE TOPOLOGY, AND ITS ONE HONEST COMPROMISE
/// A voice needs a PITCH and it needs FORMANTS, and the SID cannot give
/// you both on three voices without help. Hard sync is the help: an
/// oscillator with SYNC set restarts on its sync source's period, so it
/// rings at ITS OWN frequency while repeating at the SOURCE's. That is
/// formant synthesis in one bit.
///
/// The sync ring is fixed in silicon — V1 syncs to V3, V2 to V1, V3 to
/// V2 — so exactly one voice can be synced to a pitch source:
///
///     V3  glottal pitch. Triangle, sustain 0, so it is SILENT and
///         exists only as V1's sync source. Sync reads the oscillator,
///         not the envelope, so a muted voice still drives it.
///     V1  F1, pulse, SYNC set -> a properly pitched first formant.
///     V2  F2, pulse, free-running.
///
/// So F1 is pitched and F2 is a tone. F1 carries most of the energy, so
/// this buys most of the benefit; F2 sitting unpitched next to it is the
/// compromise, and it is the main reason the C64 will sound harder and
/// more metallic than the GML preview. F3 has no voice left and is
/// dropped for voiced frames.
///
/// Unvoiced frames have no pitch to preserve, so V3 is freed for the
/// noise waveform and carries the frication, which is where all the
/// energy of an S or an SH lives anyway.
///
/// FRAME FORMAT — 8 bytes, and byte 7 = $FF terminates
///     0,1  V1 frequency lo/hi   (F1)
///     2,3  V2 frequency lo/hi   (F2)
///     4,5  V3 frequency lo/hi   (pitch, or noise rate)
///     6    (a1 << 4) | a2       sustain nibbles, straight from the table
///     7    (a3 << 4) | flags    bit0 = voiced (sync V1, triangle V3)
///                               bit1 = V3 is noise
/// ====================================================================

/// @function scr_voi64_sid_timer_period(_pitch)
/// @desc CIA2 Timer A period for one glottal cycle, PAL. The timer counts
///       down to zero inclusive, so the divisor is period+1 and the value
///       written is one less than the cycle count.
function scr_voi64_sid_timer_period(_pitch) {
    var _hz = clamp(_pitch, 50, 400);
    return clamp(round(985248 / _hz) - 1, 1, 65535);
}

/// @function scr_voi64_sid_freq(_hz)
/// @desc Hz to a SID 16-bit frequency word, PAL.
///       Fout = Fn * clock / 16777216 with clock 985248, so
///       Fn = Hz * 17.0284. NTSC would be 16.4 — if NTSC output is ever
///       wanted this is the one constant that has to change, which is why
///       it is a named function rather than a sprinkled magic number.
function scr_voi64_sid_freq(_hz) {
    return clamp(round(_hz * 17.0284), 0, 65535);
}

/// @function scr_voi64_sid_frames(_phonemes, _pitch, _speed, _throat, _mouth)
/// @desc Build the byte stream the C64 player consumes.
/// @return {array} array of 8-element byte arrays, terminator NOT included
function scr_voi64_sid_frames(_phonemes, _pitch = 120, _speed = 128, _throat = 128, _mouth = 128) {
    var _frames = scr_voi64_build_frames(_phonemes, _speed);
    var _out    = [];
    if (array_length(_frames) == 0) {
        return _out;
    }

    var _throat_mul = 0.6 + (clamp(_throat, 0, 255) / 255) * 0.8;
    var _mouth_mul  = 0.6 + (clamp(_mouth,  0, 255) / 255) * 0.8;
    var _pitch_hz   = clamp(_pitch, 50, 400);
    var _pw3        = scr_voi64_sid_freq(_pitch_hz);

    // The builder works at 100Hz. The player's frame rate is the GLOTTAL
    // PITCH, because the envelope retrigger at the top of each frame is
    // what produces voicing — so pitch and the parameter clock have to be
    // the same clock. Resample by nearest source frame rather than
    // averaging: averaging rounds off the stop bursts, which are the
    // shortest and most important events in the stream.
    var _src_n = array_length(_frames);
    var _out_n = max(1, round(_src_n * _pitch_hz / 100));

    for (var _o = 0; _o < _out_n; _o++) {
        var _i = clamp(floor(_o * 100 / _pitch_hz), 0, _src_n - 1);
        var _p = _frames[_i];

        var _voiced = (_p.vcd > 3);
        var _noise  = (_p.nz  > 3);

        var _f1 = scr_voi64_sid_freq(clamp(_p.f1 * _throat_mul, 120, 1200));
        var _f2 = scr_voi64_sid_freq(clamp(_p.f2 * _mouth_mul,  400, 3400));

        // V3 is the pitch source when voiced, and the noise generator when
        // not. Noise rate sets the spectral centre of the hiss, so an S and
        // an F differ here by exactly this word.
        var _f3 = _pw3;
        if (!_voiced && _noise) {
            var _nf = _p.nf;
            if (_nf <= 0) { _nf = _p.f2; }
            _f3 = scr_voi64_sid_freq(clamp(_nf * _mouth_mul, 600, 8000) * 0.5);
        }

        var _a1 = clamp(round(_p.a1), 0, 15);
        var _a2 = clamp(round(_p.a2), 0, 15);
        var _a3 = clamp(round(_p.nz), 0, 15);   // V3 carries frication, not F3
        if (_voiced) {
            _a3 = 0;                            // silent pitch source
        }

        var _flags = 0;
        if (_voiced) { _flags = _flags | 0x01; }
        if (!_voiced && _noise) { _flags = _flags | 0x02; }

        array_push(_out, [
            _f1 & 0xFF, (_f1 >> 8) & 0xFF,
            _f2 & 0xFF, (_f2 >> 8) & 0xFF,
            _f3 & 0xFF, (_f3 >> 8) & 0xFF,
            ((_a1 & 0x0F) << 4) | (_a2 & 0x0F),
            ((_a3 & 0x0F) << 4) | (_flags & 0x0F)
        ]);
    }

    return _out;
}

/// @function scr_voi64_say_source_text(_node)
/// @desc Resolve a MACRO_VOI64_SAY node to the text it should speak,
///       whichever source mode it is in. Both sources are known at build
///       time, which is what lets the letters stay on the PC.
///       [4] src mode: 0 = inline, 1 = TEXT_DATA asset
///       [5] inline text   [6] asset name
function scr_voi64_say_source_text(_node) {
    var _i0 = _node.instructions[0];
    var _src = 0;
    if (array_length(_i0) > 4 && is_real(_i0[4])) { _src = real(_i0[4]); }

    if (_src == 0) {
        if (array_length(_i0) > 5) { return string(_i0[5]); }
        return "";
    }

    var _name = "";
    if (array_length(_i0) > 6) { _name = string(_i0[6]); }
    if (_name == "" || !instance_exists(obj_asset_manager)) { return ""; }

    for (var _ai = 0; _ai < ds_list_size(obj_asset_manager.asset_list); _ai++) {
        var _a = obj_asset_manager.asset_list[| _ai];
        if (_a.name != _name) { continue; }
        if (_a.type != "TEXT_DATA") { continue; }
        // meta.text is where a TEXT_DATA asset actually keeps its string —
        // it is what MACRO_PRINT and MACRO_SID_SOUND both read. The earlier
        // version guessed at a top-level .text and then at the raw buffer,
        // found neither, and handed back an empty string. An empty phrase
        // makes the SAY case emit nothing, which is why the node measured
        // 0 BYTES.
        if (variable_struct_exists(_a, "meta")) {
            if (variable_struct_exists(_a.meta, "text")) {
                return string(_a.meta.text);
            }
        }
        return "";
    }
    return "";
}

/// @function scr_voi64_say_phoneme_string(_node, _master)
/// @desc The phoneme string a SAY node will emit, resolving TEXT vs
///       PHONEME mode. Used by both the compiler and the node's own
///       preview button, so what you hear in the tool is what gets built.
///       [3] mode: 0 = TEXT (run letter-to-sound), 1 = PHONEME (verbatim)
function scr_voi64_say_phoneme_string(_node) {
    var _i0 = _node.instructions[0];
    var _mode = 0;
    if (array_length(_i0) > 3 && is_real(_i0[3])) { _mode = real(_i0[3]); }

    var _txt = scr_voi64_say_source_text(_node);
    if (_txt == "") { return ""; }
    if (_mode == 1) {
        return string_upper(_txt);
    }
    return scr_voi64_text_to_phonemes(_txt);
}

/// @function scr_voi64_find_master()
/// @desc The connected MACRO_VOI64_MASTER, or noone. SAY is meaningless
///       without one: the master owns the player routine and the default
///       voice, so a SAY with no master is a build error, not a warning.
function scr_voi64_find_master() {
    var _m = noone;
    with (obj_c64_node) {
        if (node_type == "MACRO_VOI64_MASTER" && is_connected) {
            _m = id;
            break;
        }
    }
    return _m;
}

/// @function scr_voi64_effective_voice(_node)
/// @desc Resolve a SAY node's voice: master defaults, with any per-say
///       override applied. A value of -1 in a SAY slot means inherit,
///       which is what the node draws as a dash.
/// @return {struct} { pitch, speed, throat, mouth }
function scr_voi64_effective_voice(_node) {
    var _v = { pitch: 120, speed: 128, throat: 128, mouth: 128 };

    var _m = scr_voi64_find_master();
    if (instance_exists(_m)) {
        var _mi = _m.instructions[0];
        if (array_length(_mi) > 1 && is_real(_mi[1])) { _v.pitch  = real(_mi[1]); }
        if (array_length(_mi) > 2 && is_real(_mi[2])) { _v.speed  = real(_mi[2]); }
        if (array_length(_mi) > 3 && is_real(_mi[3])) { _v.throat = real(_mi[3]); }
        if (array_length(_mi) > 4 && is_real(_mi[4])) { _v.mouth  = real(_mi[4]); }
    }

    if (_node.node_type == "MACRO_VOI64_SAY") {
        var _i0 = _node.instructions[0];
        // [7] pitch  [8] speed  [9] throat  [10] mouth, -1 = inherit
        if (array_length(_i0) >  7 && is_real(_i0[ 7]) && real(_i0[ 7]) >= 0) { _v.pitch  = real(_i0[ 7]); }
        if (array_length(_i0) >  8 && is_real(_i0[ 8]) && real(_i0[ 8]) >= 0) { _v.speed  = real(_i0[ 8]); }
        if (array_length(_i0) >  9 && is_real(_i0[ 9]) && real(_i0[ 9]) >= 0) { _v.throat = real(_i0[ 9]); }
        if (array_length(_i0) > 10 && is_real(_i0[10]) && real(_i0[10]) >= 0) { _v.mouth  = real(_i0[10]); }
    }

    return _v;
}
