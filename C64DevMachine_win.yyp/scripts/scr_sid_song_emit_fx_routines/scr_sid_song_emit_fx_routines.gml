/// @function scr_sid_song_emit_fx_routines(_list, _id, _key, _chip, _c0)
/// @desc Emits MACRO_SID_SONG's two shared effect routines (phase 1 of the
///       GoatTracker-style features). Both take X = voice (0-2) and work on
///       the per-voice RAM tables declared in the song's data block.
///
///   <key>cmdr — applies the row's command (<key>rcmd / <key>rval, $FF = none).
///     Effects 1-4 last for their own row only: a row without one (or with any
///     other command) stops the effect; the pitch stays where it got to.
///     0XX  no effect
///     1XX  portamento up    (XX added to the pitch every frame of the row)
///     2XX  portamento down
///     3XX  slide to note    (the row trigger stored the target)
///     4XY  vibrato, X = frames per half-cycle, Y = depth (Y*4 per frame); 400 = off
///     5XX / 6XX / 7XX  set AD / SR / waveform — one-shot, applied by fxr once
///                      any hard restart has finished so the note's own values
///                      don't overwrite it
///     DXX  write $D418 directly (volume, filter mode)
///     FXX  tempo in frames per row (00 ignored)
///
///   <key>fxr — per-frame, Y = voice * 7 as well: pending one-shot, portamento,
///     vibrato (the 4XY command's, else the instrument's after its delay), then
///     writes base pitch + vibrato offset to the voice's frequency registers.
///     <key>hrw != 0 means a hard restart is still counting down.
///
/// _c0 is the zero-page address of voice 0's control-register shadow; the three
/// shadows are consecutive, so voice X's is _c0 + X.
///
/// _use_fx false (no command column anywhere, no instrument vibrato): cmdr is a
/// bare RTS and fxr only writes the pitch, so a song that uses none of this
/// pays ~20 bytes here instead of ~550.
function scr_sid_song_emit_fx_routines(_list, _id, _key, _chip, _c0, _use_fx) {
    var _k = _key;

    if (!_use_fx) {
        array_push(_list, ["label",   _k + "cmdr"]);
        array_push(_list, ["rts",     0, _id]);
        array_push(_list, ["label",   _k + "fxr"]);
        array_push(_list, ["lda_abx", _k + "fql", _id]);
        array_push(_list, ["sta_aby", _chip + 0, _id]);
        array_push(_list, ["lda_abx", _k + "fqh", _id]);
        array_push(_list, ["sta_aby", _chip + 1, _id]);
        array_push(_list, ["rts",     0, _id]);
        return;
    }

    // ═════════════════════════ cmdr ═════════════════════════
    array_push(_list, ["label",   _k + "cmdr"]);
    array_push(_list, ["lda_abs", _k + "rcmd", _id]);
    array_push(_list, ["cmp_imm", 0xFF, _id]);
    array_push(_list, ["bne",     _k + "c_has", _id]);
    // No command on this row: the effect ends here.
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["sta_abx", _k + "fx", _id]);
    array_push(_list, ["rts",     0, _id]);
    array_push(_list, ["label",   _k + "c_has"]);
    // 000 — stop the continuous effect (A = 0 here).
    array_push(_list, ["cmp_imm", 0x00, _id]);
    array_push(_list, ["bne",     _k + "c_n0", _id]);
    array_push(_list, ["sta_abx", _k + "fx", _id]);
    array_push(_list, ["rts",     0, _id]);
    array_push(_list, ["label",   _k + "c_n0"]);
    array_push(_list, ["cmp_imm", 0x05, _id]);
    array_push(_list, ["bcs",     _k + "c_ge5", _id]);
    // 1-4: continuous. Y keeps the command.
    array_push(_list, ["tay",     0, _id]);
    array_push(_list, ["cmp_imm", 0x04, _id]);
    array_push(_list, ["bne",     _k + "c_st", _id]);
    // Starting vibrato (not already running) restarts its cycle centred.
    array_push(_list, ["cmp_abx", _k + "fx", _id]);
    array_push(_list, ["beq",     _k + "c_st", _id]);
    array_push(_list, ["lda_imm", 0xFF, _id]);
    array_push(_list, ["sta_abx", _k + "vbc", _id]);
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["sta_abx", _k + "vol", _id]);
    array_push(_list, ["sta_abx", _k + "voh", _id]);
    array_push(_list, ["sta_abx", _k + "vdir", _id]);
    array_push(_list, ["label",   _k + "c_st"]);
    array_push(_list, ["tya",     0, _id]);
    array_push(_list, ["sta_abx", _k + "fx", _id]);
    array_push(_list, ["lda_abs", _k + "rval", _id]);
    array_push(_list, ["sta_abx", _k + "fxv", _id]);
    array_push(_list, ["cpy_imm", 0x04, _id]);
    array_push(_list, ["bne",     _k + "c_ret", _id]);
    array_push(_list, ["and_imm", 0x0F, _id]);          // depth = Y * 4
    array_push(_list, ["asl_a",   0, _id]);
    array_push(_list, ["asl_a",   0, _id]);
    array_push(_list, ["sta_abx", _k + "cvd", _id]);
    array_push(_list, ["lda_abs", _k + "rval", _id]);   // speed = X
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["sta_abx", _k + "cvs", _id]);
    array_push(_list, ["label",   _k + "c_ret"]);
    array_push(_list, ["rts",     0, _id]);
    // 5-F: not an effect, so any running effect ends on this row too.
    array_push(_list, ["label",   _k + "c_ge5"]);
    array_push(_list, ["tay",     0, _id]);
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["sta_abx", _k + "fx", _id]);
    array_push(_list, ["tya",     0, _id]);
    // 5-7: one-shot, applied by fxr.
    array_push(_list, ["cmp_imm", 0x08, _id]);
    array_push(_list, ["bcs",     _k + "c_ge8", _id]);
    array_push(_list, ["sta_abx", _k + "pcmd", _id]);
    array_push(_list, ["lda_abs", _k + "rval", _id]);
    array_push(_list, ["sta_abx", _k + "pval", _id]);
    array_push(_list, ["rts",     0, _id]);
    array_push(_list, ["label",   _k + "c_ge8"]);
    // D: $D418.
    array_push(_list, ["cmp_imm", 0x0D, _id]);
    array_push(_list, ["bne",     _k + "c_nd", _id]);
    array_push(_list, ["lda_abs", _k + "rval", _id]);
    array_push(_list, ["sta_abs", _chip + 0x18, _id]);
    array_push(_list, ["rts",     0, _id]);
    array_push(_list, ["label",   _k + "c_nd"]);
    // F: tempo.
    array_push(_list, ["cmp_imm", 0x0F, _id]);
    array_push(_list, ["bne",     _k + "c_end", _id]);
    array_push(_list, ["lda_abs", _k + "rval", _id]);
    array_push(_list, ["beq",     _k + "c_end", _id]);
    array_push(_list, ["sta_abs", _k + "spd", _id]);
    array_push(_list, ["label",   _k + "c_end"]);
    array_push(_list, ["rts",     0, _id]);

    // ═════════════════════════ fxr ═════════════════════════
    array_push(_list, ["label",   _k + "fxr"]);
    // ── pending one-shot (5/6/7) ──
    array_push(_list, ["lda_abx", _k + "pcmd", _id]);
    array_push(_list, ["beq",     _k + "f_porta", _id]);
    array_push(_list, ["lda_abs", _k + "hrw", _id]);
    array_push(_list, ["bne",     _k + "f_porta", _id]);
    array_push(_list, ["lda_abx", _k + "pcmd", _id]);
    array_push(_list, ["cmp_imm", 0x05, _id]);
    array_push(_list, ["bne",     _k + "f_o6", _id]);
    array_push(_list, ["lda_abx", _k + "pval", _id]);
    array_push(_list, ["sta_aby", _chip + 5, _id]);
    array_push(_list, ["jmp_abs", _k + "f_oclr", _id]);
    array_push(_list, ["label",   _k + "f_o6"]);
    array_push(_list, ["cmp_imm", 0x06, _id]);
    array_push(_list, ["bne",     _k + "f_o7", _id]);
    array_push(_list, ["lda_abx", _k + "pval", _id]);
    array_push(_list, ["sta_aby", _chip + 6, _id]);
    array_push(_list, ["jmp_abs", _k + "f_oclr", _id]);
    array_push(_list, ["label",   _k + "f_o7"]);
    array_push(_list, ["lda_abx", _k + "pval", _id]);
    array_push(_list, ["sta_zpx", _c0, _id]);           // keep the ctrl shadow in step
    array_push(_list, ["sta_aby", _chip + 4, _id]);
    array_push(_list, ["label",   _k + "f_oclr"]);
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["sta_abx", _k + "pcmd", _id]);

    // ── portamento ──
    array_push(_list, ["label",   _k + "f_porta"]);
    array_push(_list, ["lda_abx", _k + "fx", _id]);
    array_push(_list, ["cmp_imm", 0x01, _id]);
    array_push(_list, ["bne",     _k + "f_p2", _id]);
    array_push(_list, ["clc",     0, _id]);
    array_push(_list, ["lda_abx", _k + "fql", _id]);
    array_push(_list, ["adc_abx", _k + "fxv", _id]);
    array_push(_list, ["sta_abx", _k + "fql", _id]);
    array_push(_list, ["lda_abx", _k + "fqh", _id]);
    array_push(_list, ["adc_imm", 0x00, _id]);
    array_push(_list, ["sta_abx", _k + "fqh", _id]);
    array_push(_list, ["bcc",     _k + "f_pj", _id]);
    array_push(_list, ["lda_imm", 0xFF, _id]);          // clamp at the top
    array_push(_list, ["sta_abx", _k + "fql", _id]);
    array_push(_list, ["sta_abx", _k + "fqh", _id]);
    array_push(_list, ["label",   _k + "f_pj"]);
    array_push(_list, ["jmp_abs", _k + "f_vib", _id]);
    array_push(_list, ["label",   _k + "f_p2"]);
    array_push(_list, ["cmp_imm", 0x02, _id]);
    array_push(_list, ["bne",     _k + "f_p3", _id]);
    array_push(_list, ["sec",     0, _id]);
    array_push(_list, ["lda_abx", _k + "fql", _id]);
    array_push(_list, ["sbc_abx", _k + "fxv", _id]);
    array_push(_list, ["sta_abx", _k + "fql", _id]);
    array_push(_list, ["lda_abx", _k + "fqh", _id]);
    array_push(_list, ["sbc_imm", 0x00, _id]);
    array_push(_list, ["sta_abx", _k + "fqh", _id]);
    array_push(_list, ["bcs",     _k + "f_pj2", _id]);
    array_push(_list, ["lda_imm", 0x00, _id]);          // clamp at the bottom
    array_push(_list, ["sta_abx", _k + "fql", _id]);
    array_push(_list, ["sta_abx", _k + "fqh", _id]);
    array_push(_list, ["label",   _k + "f_pj2"]);
    array_push(_list, ["jmp_abs", _k + "f_vib", _id]);
    array_push(_list, ["label",   _k + "f_p3"]);
    array_push(_list, ["cmp_imm", 0x03, _id]);
    array_push(_list, ["beq",     _k + "f_tp", _id]);
    array_push(_list, ["jmp_abs", _k + "f_vib", _id]);
    // Slide to the target, snapping onto it rather than overshooting.
    array_push(_list, ["label",   _k + "f_tp"]);
    array_push(_list, ["lda_abx", _k + "fqh", _id]);
    array_push(_list, ["cmp_abx", _k + "tgh", _id]);
    array_push(_list, ["bcc",     _k + "f_up", _id]);
    array_push(_list, ["bne",     _k + "f_down", _id]);
    array_push(_list, ["lda_abx", _k + "fql", _id]);
    array_push(_list, ["cmp_abx", _k + "tgl", _id]);
    array_push(_list, ["bcc",     _k + "f_up", _id]);
    array_push(_list, ["bne",     _k + "f_down", _id]);
    array_push(_list, ["jmp_abs", _k + "f_vib", _id]);  // already there
    array_push(_list, ["label",   _k + "f_up"]);
    array_push(_list, ["clc",     0, _id]);
    array_push(_list, ["lda_abx", _k + "fql", _id]);
    array_push(_list, ["adc_abx", _k + "fxv", _id]);
    array_push(_list, ["sta_abx", _k + "fql", _id]);
    array_push(_list, ["lda_abx", _k + "fqh", _id]);
    array_push(_list, ["adc_imm", 0x00, _id]);
    array_push(_list, ["sta_abx", _k + "fqh", _id]);
    array_push(_list, ["bcs",     _k + "f_snap", _id]);
    array_push(_list, ["lda_abx", _k + "fqh", _id]);
    array_push(_list, ["cmp_abx", _k + "tgh", _id]);
    array_push(_list, ["bcc",     _k + "f_tpd", _id]);
    array_push(_list, ["bne",     _k + "f_snap", _id]);
    array_push(_list, ["lda_abx", _k + "fql", _id]);
    array_push(_list, ["cmp_abx", _k + "tgl", _id]);
    array_push(_list, ["bcc",     _k + "f_tpd", _id]);
    array_push(_list, ["jmp_abs", _k + "f_snap", _id]);
    array_push(_list, ["label",   _k + "f_down"]);
    array_push(_list, ["sec",     0, _id]);
    array_push(_list, ["lda_abx", _k + "fql", _id]);
    array_push(_list, ["sbc_abx", _k + "fxv", _id]);
    array_push(_list, ["sta_abx", _k + "fql", _id]);
    array_push(_list, ["lda_abx", _k + "fqh", _id]);
    array_push(_list, ["sbc_imm", 0x00, _id]);
    array_push(_list, ["sta_abx", _k + "fqh", _id]);
    array_push(_list, ["bcc",     _k + "f_snap", _id]);
    array_push(_list, ["lda_abx", _k + "fqh", _id]);
    array_push(_list, ["cmp_abx", _k + "tgh", _id]);
    array_push(_list, ["bcc",     _k + "f_snap", _id]);
    array_push(_list, ["bne",     _k + "f_tpd", _id]);
    array_push(_list, ["lda_abx", _k + "fql", _id]);
    array_push(_list, ["cmp_abx", _k + "tgl", _id]);
    array_push(_list, ["bcc",     _k + "f_snap", _id]);
    array_push(_list, ["label",   _k + "f_tpd"]);
    array_push(_list, ["jmp_abs", _k + "f_vib", _id]);
    array_push(_list, ["label",   _k + "f_snap"]);
    array_push(_list, ["lda_abx", _k + "tgl", _id]);
    array_push(_list, ["sta_abx", _k + "fql", _id]);
    array_push(_list, ["lda_abx", _k + "tgh", _id]);
    array_push(_list, ["sta_abx", _k + "fqh", _id]);

    // ── vibrato ──
    array_push(_list, ["label",   _k + "f_vib"]);
    array_push(_list, ["lda_abx", _k + "fx", _id]);
    array_push(_list, ["cmp_imm", 0x04, _id]);
    array_push(_list, ["bne",     _k + "f_ivib", _id]);
    array_push(_list, ["lda_abx", _k + "cvs", _id]);
    array_push(_list, ["sta_abs", _k + "vts", _id]);
    array_push(_list, ["lda_abx", _k + "cvd", _id]);
    array_push(_list, ["sta_abs", _k + "vtd", _id]);
    array_push(_list, ["jmp_abs", _k + "f_vrun", _id]);
    array_push(_list, ["label",   _k + "f_ivib"]);
    array_push(_list, ["lda_abx", _k + "ivdl", _id]);   // instrument vibrato delay
    array_push(_list, ["beq",     _k + "f_ivgo", _id]);
    array_push(_list, ["sec",     0, _id]);
    array_push(_list, ["sbc_imm", 0x01, _id]);
    array_push(_list, ["sta_abx", _k + "ivdl", _id]);
    array_push(_list, ["jmp_abs", _k + "f_vzero", _id]);
    array_push(_list, ["label",   _k + "f_ivgo"]);
    array_push(_list, ["lda_abx", _k + "ivs", _id]);
    array_push(_list, ["sta_abs", _k + "vts", _id]);
    array_push(_list, ["lda_abx", _k + "ivp", _id]);
    array_push(_list, ["sta_abs", _k + "vtd", _id]);
    array_push(_list, ["label",   _k + "f_vrun"]);
    array_push(_list, ["lda_abs", _k + "vts", _id]);
    array_push(_list, ["beq",     _k + "f_vzero", _id]);
    array_push(_list, ["lda_abs", _k + "vtd", _id]);
    array_push(_list, ["beq",     _k + "f_vzero", _id]);
    // $FF = fresh cycle: start half-way so the pitch swings either side of the note.
    array_push(_list, ["lda_abx", _k + "vbc", _id]);
    array_push(_list, ["cmp_imm", 0xFF, _id]);
    array_push(_list, ["bne",     _k + "f_vcnt", _id]);
    array_push(_list, ["lda_abs", _k + "vts", _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["sta_abx", _k + "vbc", _id]);
    array_push(_list, ["label",   _k + "f_vcnt"]);
    array_push(_list, ["lda_abx", _k + "vdir", _id]);
    array_push(_list, ["bne",     _k + "f_vdn", _id]);
    array_push(_list, ["clc",     0, _id]);
    array_push(_list, ["lda_abx", _k + "vol", _id]);
    array_push(_list, ["adc_abs", _k + "vtd", _id]);
    array_push(_list, ["sta_abx", _k + "vol", _id]);
    array_push(_list, ["lda_abx", _k + "voh", _id]);
    array_push(_list, ["adc_imm", 0x00, _id]);
    array_push(_list, ["sta_abx", _k + "voh", _id]);
    array_push(_list, ["jmp_abs", _k + "f_vstep", _id]);
    array_push(_list, ["label",   _k + "f_vdn"]);
    array_push(_list, ["sec",     0, _id]);
    array_push(_list, ["lda_abx", _k + "vol", _id]);
    array_push(_list, ["sbc_abs", _k + "vtd", _id]);
    array_push(_list, ["sta_abx", _k + "vol", _id]);
    array_push(_list, ["lda_abx", _k + "voh", _id]);
    array_push(_list, ["sbc_imm", 0x00, _id]);
    array_push(_list, ["sta_abx", _k + "voh", _id]);
    array_push(_list, ["label",   _k + "f_vstep"]);
    array_push(_list, ["lda_abx", _k + "vbc", _id]);
    array_push(_list, ["clc",     0, _id]);
    array_push(_list, ["adc_imm", 0x01, _id]);
    array_push(_list, ["sta_abx", _k + "vbc", _id]);
    array_push(_list, ["cmp_abs", _k + "vts", _id]);
    array_push(_list, ["bcc",     _k + "f_out", _id]);
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["sta_abx", _k + "vbc", _id]);
    array_push(_list, ["lda_abx", _k + "vdir", _id]);
    array_push(_list, ["eor_imm", 0x01, _id]);
    array_push(_list, ["sta_abx", _k + "vdir", _id]);
    array_push(_list, ["jmp_abs", _k + "f_out", _id]);
    array_push(_list, ["label",   _k + "f_vzero"]);
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["sta_abx", _k + "vol", _id]);
    array_push(_list, ["sta_abx", _k + "voh", _id]);
    array_push(_list, ["sta_abx", _k + "vdir", _id]);
    array_push(_list, ["lda_imm", 0xFF, _id]);
    array_push(_list, ["sta_abx", _k + "vbc", _id]);

    // ── output: base pitch + vibrato offset ──
    array_push(_list, ["label",   _k + "f_out"]);
    array_push(_list, ["clc",     0, _id]);
    array_push(_list, ["lda_abx", _k + "fql", _id]);
    array_push(_list, ["adc_abx", _k + "vol", _id]);
    array_push(_list, ["sta_aby", _chip + 0, _id]);
    array_push(_list, ["lda_abx", _k + "fqh", _id]);
    array_push(_list, ["adc_abx", _k + "voh", _id]);
    array_push(_list, ["sta_aby", _chip + 1, _id]);
    array_push(_list, ["rts",     0, _id]);
}
