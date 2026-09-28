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
///     8XX  set pulse width to XX * 16 ($000-$FF0) — one-shot, like 5-7
///     9XX  pulse sweep for the row: 01-7F adds XX per frame, 80-FF subtracts
///          (256 - XX); clamped to $000-$FFF
///     AXX  filter cutoff = XX * 8 (the top 8 of its 11 bits)
///     BX0  filter resonance X (voice routing is untouched)
///     CXX  cutoff sweep for the row: 01-7F up XX per frame, 80-FF down
///          (256 - XX); clamped to 0-2047
///     DXX  write $D418 directly (volume, filter mode)
///     EXX  filter mode, keeping the volume: 1 low-pass, 2 band-pass,
///          4 high-pass, 8 voice 3 off — add them to combine
///     FXX  tempo in frames per row (00 ignored)
///     (A/B/C/E only exist when the song uses the filter, _use_filter.)
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
function scr_sid_song_emit_fx_routines(_list, _id, _key, _chip, _c0, _use_fx, _use_filter) {
    var _k = _key;

    if (_use_filter) {
        // <key>fcut — writes the 11-bit cutoff (fch:fcl) to $D415/$D416.
        // $D415 = bits 0-2, $D416 = bits 3-10. A and ftmp only; X/Y kept.
        array_push(_list, ["label",   _k + "fcut"]);
        array_push(_list, ["lda_abs", _k + "fcl", _id]);
        array_push(_list, ["and_imm", 0x07, _id]);
        array_push(_list, ["sta_abs", _chip + 0x15, _id]);
        array_push(_list, ["lda_abs", _k + "fch", _id]);
        array_push(_list, ["asl_a",   0, _id]);
        array_push(_list, ["asl_a",   0, _id]);
        array_push(_list, ["asl_a",   0, _id]);
        array_push(_list, ["asl_a",   0, _id]);
        array_push(_list, ["asl_a",   0, _id]);
        array_push(_list, ["sta_abs", _k + "ftmp", _id]);
        array_push(_list, ["lda_abs", _k + "fcl", _id]);
        array_push(_list, ["lsr_a",   0, _id]);
        array_push(_list, ["lsr_a",   0, _id]);
        array_push(_list, ["lsr_a",   0, _id]);
        array_push(_list, ["ora_abs", _k + "ftmp", _id]);
        array_push(_list, ["sta_abs", _chip + 0x16, _id]);
        array_push(_list, ["rts",     0, _id]);
    }

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
    // 9: pulse sweep, an effect like 1-4.
    array_push(_list, ["cmp_imm", 0x09, _id]);
    array_push(_list, ["bne",     _k + "c_n9", _id]);
    array_push(_list, ["sta_abx", _k + "fx", _id]);
    array_push(_list, ["lda_abs", _k + "rval", _id]);
    array_push(_list, ["sta_abx", _k + "fxv", _id]);
    array_push(_list, ["rts",     0, _id]);
    array_push(_list, ["label",   _k + "c_n9"]);
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
    // 5-8: one-shot, applied by fxr.
    array_push(_list, ["cmp_imm", 0x09, _id]);
    array_push(_list, ["bcs",     _k + "c_ge8", _id]);
    array_push(_list, ["sta_abx", _k + "pcmd", _id]);
    array_push(_list, ["lda_abs", _k + "rval", _id]);
    array_push(_list, ["sta_abx", _k + "pval", _id]);
    array_push(_list, ["rts",     0, _id]);
    array_push(_list, ["label",   _k + "c_ge8"]);
    if (_use_filter) {
        // A: cutoff = XX * 8.
        array_push(_list, ["cmp_imm", 0x0A, _id]);
        array_push(_list, ["bne",     _k + "c_na", _id]);
        array_push(_list, ["lda_abs", _k + "rval", _id]);
        array_push(_list, ["asl_a",   0, _id]);
        array_push(_list, ["asl_a",   0, _id]);
        array_push(_list, ["asl_a",   0, _id]);
        array_push(_list, ["sta_abs", _k + "fcl", _id]);
        array_push(_list, ["lda_abs", _k + "rval", _id]);
        array_push(_list, ["lsr_a",   0, _id]);
        array_push(_list, ["lsr_a",   0, _id]);
        array_push(_list, ["lsr_a",   0, _id]);
        array_push(_list, ["lsr_a",   0, _id]);
        array_push(_list, ["lsr_a",   0, _id]);
        array_push(_list, ["sta_abs", _k + "fch", _id]);
        array_push(_list, ["jmp_abs", _k + "fcut", _id]);   // its rts returns
        array_push(_list, ["label",   _k + "c_na"]);
        // B: resonance = high nibble of XX, routing bits kept.
        array_push(_list, ["cmp_imm", 0x0B, _id]);
        array_push(_list, ["bne",     _k + "c_nb", _id]);
        array_push(_list, ["lda_abs", _k + "f17", _id]);
        array_push(_list, ["and_imm", 0x0F, _id]);
        array_push(_list, ["sta_abs", _k + "ftmp", _id]);
        array_push(_list, ["lda_abs", _k + "rval", _id]);
        array_push(_list, ["and_imm", 0xF0, _id]);
        array_push(_list, ["ora_abs", _k + "ftmp", _id]);
        array_push(_list, ["sta_abs", _k + "f17", _id]);
        array_push(_list, ["sta_abs", _chip + 0x17, _id]);
        array_push(_list, ["rts",     0, _id]);
        array_push(_list, ["label",   _k + "c_nb"]);
        // C: cutoff sweep — an effect for this row, run by fxr.
        array_push(_list, ["cmp_imm", 0x0C, _id]);
        array_push(_list, ["bne",     _k + "c_nc", _id]);
        array_push(_list, ["sta_abx", _k + "fx", _id]);
        array_push(_list, ["lda_abs", _k + "rval", _id]);
        array_push(_list, ["sta_abx", _k + "fxv", _id]);
        array_push(_list, ["rts",     0, _id]);
        array_push(_list, ["label",   _k + "c_nc"]);
        // E: mode (high nibble of $D418), volume kept.
        array_push(_list, ["cmp_imm", 0x0E, _id]);
        array_push(_list, ["bne",     _k + "c_ne", _id]);
        array_push(_list, ["lda_abs", _k + "f18", _id]);
        array_push(_list, ["and_imm", 0x0F, _id]);
        array_push(_list, ["sta_abs", _k + "ftmp", _id]);
        array_push(_list, ["lda_abs", _k + "rval", _id]);
        array_push(_list, ["asl_a",   0, _id]);
        array_push(_list, ["asl_a",   0, _id]);
        array_push(_list, ["asl_a",   0, _id]);
        array_push(_list, ["asl_a",   0, _id]);
        array_push(_list, ["ora_abs", _k + "ftmp", _id]);
        array_push(_list, ["sta_abs", _k + "f18", _id]);
        array_push(_list, ["sta_abs", _chip + 0x18, _id]);
        array_push(_list, ["rts",     0, _id]);
        array_push(_list, ["label",   _k + "c_ne"]);
    }
    // D: $D418 (and its copy, so a later EXX keeps this volume).
    array_push(_list, ["cmp_imm", 0x0D, _id]);
    array_push(_list, ["bne",     _k + "c_nd", _id]);
    array_push(_list, ["lda_abs", _k + "rval", _id]);
    array_push(_list, ["sta_abs", _chip + 0x18, _id]);
    array_push(_list, ["sta_abs", _k + "f18", _id]);
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
    array_push(_list, ["cmp_imm", 0x07, _id]);
    array_push(_list, ["bne",     _k + "f_o8", _id]);
    array_push(_list, ["lda_abx", _k + "pval", _id]);
    array_push(_list, ["sta_zpx", _c0, _id]);           // keep the ctrl shadow in step
    array_push(_list, ["sta_aby", _chip + 4, _id]);
    array_push(_list, ["jmp_abs", _k + "f_oclr", _id]);
    // 8XX: pulse width = XX * 16.
    array_push(_list, ["label",   _k + "f_o8"]);
    array_push(_list, ["lda_abx", _k + "pval", _id]);
    array_push(_list, ["asl_a",   0, _id]);
    array_push(_list, ["asl_a",   0, _id]);
    array_push(_list, ["asl_a",   0, _id]);
    array_push(_list, ["asl_a",   0, _id]);
    array_push(_list, ["sta_abx", _k + "pwl", _id]);
    array_push(_list, ["sta_aby", _chip + 2, _id]);
    array_push(_list, ["lda_abx", _k + "pval", _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["lsr_a",   0, _id]);
    array_push(_list, ["sta_abx", _k + "pwh", _id]);
    array_push(_list, ["sta_aby", _chip + 3, _id]);
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
    array_push(_list, ["bne",     _k + "f_n3", _id]);
    array_push(_list, ["jmp_abs", _k + "f_tp", _id]);   // too far for a branch
    array_push(_list, ["label",   _k + "f_n3"]);
    array_push(_list, ["cmp_imm", 0x09, _id]);
    array_push(_list, ["beq",     _k + "f_pw", _id]);
    if (_use_filter) {
        array_push(_list, ["cmp_imm", 0x0C, _id]);
        array_push(_list, ["bne",     _k + "f_ncs", _id]);
        array_push(_list, ["jmp_abs", _k + "f_cs", _id]);
        array_push(_list, ["label",   _k + "f_ncs"]);
    }
    array_push(_list, ["jmp_abs", _k + "f_vib", _id]);
    // 9XX pulse sweep: add XX sign-extended, clamp to $000-$FFF, write.
    array_push(_list, ["label",   _k + "f_pw"]);
    array_push(_list, ["lda_abx", _k + "fxv", _id]);
    array_push(_list, ["bmi",     _k + "f_pwdn", _id]);
    array_push(_list, ["clc",     0, _id]);
    array_push(_list, ["adc_abx", _k + "pwl", _id]);
    array_push(_list, ["sta_abx", _k + "pwl", _id]);
    array_push(_list, ["lda_abx", _k + "pwh", _id]);
    array_push(_list, ["adc_imm", 0x00, _id]);
    array_push(_list, ["sta_abx", _k + "pwh", _id]);
    array_push(_list, ["cmp_imm", 0x10, _id]);
    array_push(_list, ["bcc",     _k + "f_pwout", _id]);
    array_push(_list, ["lda_imm", 0xFF, _id]);          // past the top: $FFF
    array_push(_list, ["sta_abx", _k + "pwl", _id]);
    array_push(_list, ["lda_imm", 0x0F, _id]);
    array_push(_list, ["sta_abx", _k + "pwh", _id]);
    array_push(_list, ["jmp_abs", _k + "f_pwout", _id]);
    array_push(_list, ["label",   _k + "f_pwdn"]);
    array_push(_list, ["clc",     0, _id]);
    array_push(_list, ["adc_abx", _k + "pwl", _id]);
    array_push(_list, ["sta_abx", _k + "pwl", _id]);
    array_push(_list, ["lda_abx", _k + "pwh", _id]);
    array_push(_list, ["adc_imm", 0xFF, _id]);
    array_push(_list, ["sta_abx", _k + "pwh", _id]);
    array_push(_list, ["cmp_imm", 0x10, _id]);
    array_push(_list, ["bcc",     _k + "f_pwout", _id]);
    array_push(_list, ["lda_imm", 0x00, _id]);          // below zero: $000
    array_push(_list, ["sta_abx", _k + "pwl", _id]);
    array_push(_list, ["sta_abx", _k + "pwh", _id]);
    array_push(_list, ["label",   _k + "f_pwout"]);
    array_push(_list, ["lda_abx", _k + "pwl", _id]);
    array_push(_list, ["sta_aby", _chip + 2, _id]);
    array_push(_list, ["lda_abx", _k + "pwh", _id]);
    array_push(_list, ["sta_aby", _chip + 3, _id]);
    array_push(_list, ["jmp_abs", _k + "f_vib", _id]);
    if (_use_filter) {
        // CXX cutoff sweep: XX sign-extended onto the 11-bit cutoff, clamped.
        array_push(_list, ["label",   _k + "f_cs"]);
        array_push(_list, ["lda_abx", _k + "fxv", _id]);
        array_push(_list, ["bmi",     _k + "f_csdn", _id]);
        array_push(_list, ["clc",     0, _id]);
        array_push(_list, ["adc_abs", _k + "fcl", _id]);
        array_push(_list, ["sta_abs", _k + "fcl", _id]);
        array_push(_list, ["lda_abs", _k + "fch", _id]);
        array_push(_list, ["adc_imm", 0x00, _id]);
        array_push(_list, ["sta_abs", _k + "fch", _id]);
        array_push(_list, ["cmp_imm", 0x08, _id]);
        array_push(_list, ["bcc",     _k + "f_csw", _id]);
        array_push(_list, ["lda_imm", 0xFF, _id]);          // past the top: 2047
        array_push(_list, ["sta_abs", _k + "fcl", _id]);
        array_push(_list, ["lda_imm", 0x07, _id]);
        array_push(_list, ["sta_abs", _k + "fch", _id]);
        array_push(_list, ["jmp_abs", _k + "f_csw", _id]);
        array_push(_list, ["label",   _k + "f_csdn"]);
        array_push(_list, ["clc",     0, _id]);
        array_push(_list, ["adc_abs", _k + "fcl", _id]);
        array_push(_list, ["sta_abs", _k + "fcl", _id]);
        array_push(_list, ["lda_abs", _k + "fch", _id]);
        array_push(_list, ["adc_imm", 0xFF, _id]);
        array_push(_list, ["sta_abs", _k + "fch", _id]);
        array_push(_list, ["cmp_imm", 0x08, _id]);
        array_push(_list, ["bcc",     _k + "f_csw", _id]);
        array_push(_list, ["lda_imm", 0x00, _id]);          // below zero: 0
        array_push(_list, ["sta_abs", _k + "fcl", _id]);
        array_push(_list, ["sta_abs", _k + "fch", _id]);
        array_push(_list, ["label",   _k + "f_csw"]);
        array_push(_list, ["jsr",     _k + "fcut", _id]);
        array_push(_list, ["jmp_abs", _k + "f_vib", _id]);
    }
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

/// @function scr_sid_song_emit_sfx(_list, _id, _key, _chip, _ptr)
/// @desc GoatTracker-compatible sound effects for an exported SID (EXPORT SID
///       with SFX support). Same calling convention and data format as a
///       GoatTracker player packed with sound support, so the existing SFX
///       macro (which calls load address + 6) and GoatTracker .snd / .ins
///       effects work unchanged.
///
///   <key>sfxt  trigger: A = effect data lo, Y = hi, X = channel offset
///              (0 = voice 1, 7 = voice 2, 14 = voice 3). An effect at a lower
///              address than the one already playing on that voice is ignored
///              (GoatTracker's priority rule).
///   <key>sfxx  per frame, X = channel offset; called at the end of PLAY for
///              each voice. While an effect runs, the music skips that voice.
///
///   Effect data: AD, SR, pulse (one byte, written to both $D402/$D403), then
///   per frame a note ($82-$DF, $80 + note number) optionally followed by a
///   waveform byte (< $82); $00 ends the effect. Frame 1 hard-restarts the
///   voice, frame 2 loads ADSR/pulse with the test bit, notes start at frame 3.
///   _ptr = a zero-page pointer pair that is free once the music has run.
function scr_sid_song_emit_sfx(_list, _id, _key, _chip, _ptr) {
    var _k = _key;

    // ── trigger ──
    array_push(_list, ["label",   _k + "sfxt"]);
    array_push(_list, ["pha",     0, _id]);
    array_push(_list, ["lda_abx", _k + "sfxc", _id]);
    array_push(_list, ["beq",     _k + "sfxt_ok", _id]);
    array_push(_list, ["tya",     0, _id]);
    array_push(_list, ["cmp_abx", _k + "sfxh", _id]);
    array_push(_list, ["bcc",     _k + "sfxt_no", _id]);   // lower priority: skip
    array_push(_list, ["bne",     _k + "sfxt_ok", _id]);
    array_push(_list, ["pla",     0, _id]);
    array_push(_list, ["pha",     0, _id]);
    array_push(_list, ["cmp_abx", _k + "sfxl", _id]);
    array_push(_list, ["bcc",     _k + "sfxt_no", _id]);
    array_push(_list, ["label",   _k + "sfxt_ok"]);
    array_push(_list, ["pla",     0, _id]);
    array_push(_list, ["sta_abx", _k + "sfxl", _id]);
    array_push(_list, ["tya",     0, _id]);
    array_push(_list, ["sta_abx", _k + "sfxh", _id]);
    array_push(_list, ["lda_imm", 0x01, _id]);
    array_push(_list, ["sta_abx", _k + "sfxc", _id]);
    array_push(_list, ["rts",     0, _id]);
    array_push(_list, ["label",   _k + "sfxt_no"]);
    array_push(_list, ["pla",     0, _id]);
    array_push(_list, ["rts",     0, _id]);

    // ── per frame ──
    array_push(_list, ["label",   _k + "sfxx"]);
    array_push(_list, ["ldy_abx", _k + "sfxc", _id]);
    array_push(_list, ["bne",     _k + "sfxx_on", _id]);
    array_push(_list, ["rts",     0, _id]);
    array_push(_list, ["label",   _k + "sfxx_on"]);
    array_push(_list, ["lda_abx", _k + "sfxl", _id]);
    array_push(_list, ["sta_zp",  _ptr, _id]);
    array_push(_list, ["lda_abx", _k + "sfxh", _id]);
    array_push(_list, ["sta_zp",  _ptr + 1, _id]);
    array_push(_list, ["lda_abx", _k + "sfxc", _id]);   // counter + 1 (Y keeps the old value)
    array_push(_list, ["clc",     0, _id]);
    array_push(_list, ["adc_imm", 0x01, _id]);
    array_push(_list, ["sta_abx", _k + "sfxc", _id]);
    array_push(_list, ["cpy_imm", 0x02, _id]);
    array_push(_list, ["beq",     _k + "sfxx_f0", _id]);
    array_push(_list, ["bcs",     _k + "sfxx_fn", _id]);
    // frame 1: hard restart — zero ADSR, gate off
    array_push(_list, ["lda_imm", 0x00, _id]);
    array_push(_list, ["sta_abx", _chip + 6, _id]);
    array_push(_list, ["sta_abx", _chip + 5, _id]);
    array_push(_list, ["sta_abx", _chip + 4, _id]);
    array_push(_list, ["rts",     0, _id]);
    // frame 2: ADSR, pulse, test bit
    array_push(_list, ["label",   _k + "sfxx_f0"]);
    array_push(_list, ["ldy_imm", 0x00, _id]);
    array_push(_list, ["lda_izy", _ptr, _id]);
    array_push(_list, ["sta_abx", _chip + 5, _id]);
    array_push(_list, ["iny",     0, _id]);
    array_push(_list, ["lda_izy", _ptr, _id]);
    array_push(_list, ["sta_abx", _chip + 6, _id]);
    array_push(_list, ["iny",     0, _id]);
    array_push(_list, ["lda_izy", _ptr, _id]);
    array_push(_list, ["sta_abx", _chip + 2, _id]);
    array_push(_list, ["sta_abx", _chip + 3, _id]);
    array_push(_list, ["lda_imm", 0x09, _id]);
    array_push(_list, ["sta_abx", _chip + 4, _id]);
    array_push(_list, ["rts",     0, _id]);
    // frame 3+: note (+ optional waveform), or $00 = end
    array_push(_list, ["label",   _k + "sfxx_fn"]);
    array_push(_list, ["lda_izy", _ptr, _id]);
    array_push(_list, ["bne",     _k + "sfxx_nt", _id]);
    array_push(_list, ["sta_abx", _k + "sfxc", _id]);     // end: effect off,
    array_push(_list, ["sta_abx", _chip + 4, _id]);       // gate off
    array_push(_list, ["rts",     0, _id]);
    array_push(_list, ["label",   _k + "sfxx_nt"]);
    array_push(_list, ["sec",     0, _id]);
    array_push(_list, ["sbc_imm", 0x80, _id]);
    array_push(_list, ["tay",     0, _id]);
    array_push(_list, ["lda_aby", "SIDSONG_NOTELO", _id]);
    array_push(_list, ["sta_abx", _chip + 0, _id]);
    array_push(_list, ["lda_aby", "SIDSONG_NOTEHI", _id]);
    array_push(_list, ["sta_abx", _chip + 1, _id]);
    array_push(_list, ["ldy_abx", _k + "sfxc", _id]);     // peek the next byte
    array_push(_list, ["lda_izy", _ptr, _id]);
    array_push(_list, ["beq",     _k + "sfxx_dn", _id]);
    array_push(_list, ["cmp_imm", 0x82, _id]);
    array_push(_list, ["bcs",     _k + "sfxx_dn", _id]);  // a note: next frame's
    array_push(_list, ["pha",     0, _id]);               // a waveform: take it now
    array_push(_list, ["lda_abx", _k + "sfxc", _id]);
    array_push(_list, ["clc",     0, _id]);
    array_push(_list, ["adc_imm", 0x01, _id]);
    array_push(_list, ["sta_abx", _k + "sfxc", _id]);
    array_push(_list, ["pla",     0, _id]);
    array_push(_list, ["sta_abx", _chip + 4, _id]);
    array_push(_list, ["label",   _k + "sfxx_dn"]);
    array_push(_list, ["rts",     0, _id]);
}
