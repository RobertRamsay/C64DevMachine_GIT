/// @function scr_sound_editor_commit_instrument(_m, _instr)
/// @desc Writes the in-progress text buffer back to the instrument and
///       recompiles it via scr_instrument_parse. Called on blur (click away)
///       or Ctrl+Enter — never on every keystroke — so a mid-edit typo never
///       corrupts instr.compiled.
function scr_sound_editor_commit_instrument(_m, _instr) {
    if (!_m.instr_edit_active) {
        return;
    }
    _instr.text     = _m.instr_edit_buf;
    _instr.compiled = scr_instrument_parse(_instr.text);
    _instr.dirty    = true;
    _m.instr_edit_active = false;
    global.undo_dirty     = true;
    // The compiled stream length varies with the source text, so a text edit
    // changes how many bytes MACRO_SID_SONG emits. Without this the node keeps
    // its old size and every node downstream sits at the wrong address.
    global.addresses_dirty = true;
}