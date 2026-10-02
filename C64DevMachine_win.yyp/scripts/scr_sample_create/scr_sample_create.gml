/// SAMPLE asset — a digitised sound for $D418 playback (the "4th voice" trick).
///
/// The asset's BUFFER holds the SOURCE: 8-bit unsigned mono PCM (128 = centre),
/// peak-normalised on import, at src_rate (never above SAMPLE_SRC_MAX_RATE).
/// The workspace saver blobs it out like any other asset buffer.
///
/// The C64 data is DERIVED from the source by scr_sample_encode every time a
/// setting changes: trim -> resample to `rate` -> gain -> (dither) -> 4-bit,
/// then packed. Keeping the source means a later consumer (the Music Maker
/// digi track) can re-encode at its own playback rate with no quality loss.
///
/// The asset owns no C64 address: whatever plays it emits the packed bytes.

#macro SAMPLE_SRC_MAX_RATE 22050
#macro SAMPLE_MAX_SECONDS  10
#macro SAMPLE_PAL_CLOCK    985248
#macro SAMPLE_PV_RATE      22050

/// Playback-rate presets offered by the editor (Hz).
function scr_sample_rate_presets() {
    static _rates = [4000, 5000, 6000, 7000, 8000, 10000, 11025];
    return _rates;
}

/// Fields written to / read from the workspace file.
function scr_sample_saved_keys() {
    static _keys = ["src_rate", "src_len", "src_name", "rate", "gain", "dither",
                    "pack", "sid_model", "trim_start", "trim_end", "normalise", "compress"];
    return _keys;
}

/// @function scr_sample_create(_asset)
/// @desc Seeds every meta field the editor, encoder and savers touch.
function scr_sample_create(_asset) {
    _asset.meta = {
        // ── SOURCE ── describes the PCM in asset.buffer
        src_rate   : 0,        // Hz; 0 = nothing imported yet
        src_len    : 0,        // samples in the buffer that are real audio
        src_name   : "",       // WAV file name, display only

        // ── ENCODE SETTINGS ──
        rate       : 8000,     // C64 playback rate, Hz
        gain       : 100,      // percent, applied after normalise / compress
        normalise  : 1,        // 1 = the trimmed region's peak becomes full scale
        compress   : 0,        // 0-100 %: lifts quiet passages towards the loud ones
        dither     : 0,        // 1 = TPDF dither before the 4-bit quantise
        pack       : 0,        // 0 = 4-bit nibbles (2/byte), 1 = 2-bit delta (4/byte)
        sid_model  : 0,        // 0 = 6581, 1 = 8580 (the player adds the 8580 DC boost)
        trim_start : 0,        // source samples, inclusive
        trim_end   : 0,        // source samples, exclusive

        // ── DERIVED (never saved) ── rebuilt by scr_sample_encode
        enc        : [],       // decoded 4-bit levels exactly as the C64 will play them
        packed     : [],       // bytes the player reads
        out_count  : 0,
        out_bytes  : 0,
        clip_count : 0,
        enc_dirty  : true,
        enc_ver    : 0,
        data_ver   : 0,

        // ── EDITOR (never saved) ──
        wf_src     : [],
        wf_src_key : "",
        wf_enc     : [],
        wf_enc_key : "",
        drag       : -1,       // -1 none, 0 dragging trim start, 1 trim end
        warn_msg   : "",
        warn_timer : 0,

        // ── MUSIC MAKER DIGI PREVIEW (never saved) ── see scr_digi_sample_sound
        pv_dg_snd  : -1,
        pv_dg_buf  : -1,
        pv_dg_key  : ""
    };
}

/// @function scr_sample_restore(_asset, _saved)
/// @desc Loader path: seed defaults, lay the saved fields over them, then make
///       the numbers agree with the buffer the blob actually decoded to.
function scr_sample_restore(_asset, _saved) {
    scr_sample_create(_asset);
    var _m = _asset.meta;
    var _keys = scr_sample_saved_keys();
    for (var _i = 0; _i < array_length(_keys); _i++) {
        var _k = _keys[_i];
        var _v = _saved[$ _k];
        if (!is_undefined(_v)) {
            _m[$ _k] = _v;
        }
    }
    _m.src_rate   = real(_m.src_rate);
    _m.src_len    = real(_m.src_len);
    _m.rate       = real(_m.rate);
    _m.gain       = real(_m.gain);
    _m.normalise  = real(_m.normalise);
    _m.compress   = real(_m.compress);
    _m.dither     = real(_m.dither);
    _m.pack       = real(_m.pack);
    _m.sid_model  = real(_m.sid_model);
    _m.trim_start = real(_m.trim_start);
    _m.trim_end   = real(_m.trim_end);

    var _have = 0;
    if (buffer_exists(_asset.buffer)) {
        _have = buffer_get_size(_asset.buffer);
    }
    if (_m.src_rate <= 0) {
        _m.src_len = 0;
    }
    _m.src_len    = clamp(_m.src_len, 0, _have);
    _m.trim_start = clamp(_m.trim_start, 0, _m.src_len);
    _m.trim_end   = clamp(_m.trim_end, _m.trim_start, _m.src_len);
    _m.enc_dirty  = true;
}

/// @function scr_sample_save_meta(_asset)
/// @desc The saved field set — shared by save, save-as and autosave.
function scr_sample_save_meta(_asset) {
    var _out  = {};
    var _keys = scr_sample_saved_keys();
    for (var _i = 0; _i < array_length(_keys); _i++) {
        var _k = _keys[_i];
        _out[$ _k] = _asset.meta[$ _k];
    }
    return _out;
}
