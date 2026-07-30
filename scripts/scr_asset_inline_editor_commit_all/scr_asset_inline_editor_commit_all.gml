/// @function scr_asset_inline_editor_commit_all()
/// @desc Forces every open inline asset editor to flush its pending edit
///       buffer WITHOUT closing it. Called immediately before a build.
///
/// Editors hold uncommitted text: BYTE_DATA and TEXT_DATA keep an
/// inline_edit_text buffer that only reaches the asset on save, and a
/// SOUND_EDITOR instrument's source only reaches instr.compiled on click-away
/// or Ctrl+Enter. A build fired with the caret still in a text box therefore
/// compiles the PREVIOUS content — the edit looks ignored, and the next build
/// (after any click elsewhere) silently picks it up, which reads as a
/// intermittent compiler bug rather than a stale buffer.
///
/// Mirrors scr_asset_inline_editor_close_all's walk, but leaves every editor
/// open and does not touch preview audio — the user is mid-edit and expects to
/// carry on after the build.
function scr_asset_inline_editor_commit_all() {
    with (obj_asset_manager) {
        var _count = ds_list_size(asset_list);
        for (var _i = 0; _i < _count; _i++) {
            var _a = asset_list[| _i];
            if (!is_struct(_a)) {
                continue;
            }
            if (!variable_struct_exists(_a, "meta")) {
                continue;
            }

            if (_a.type == "BYTE_DATA") {
                if (variable_struct_exists(_a.meta, "inline_edit_open") && _a.meta.inline_edit_open) {
                    scr_asset_byte_data_save(_a);
                }
            } else if (_a.type == "TEXT_DATA") {
                if (variable_struct_exists(_a.meta, "inline_edit_open") && _a.meta.inline_edit_open) {
                    scr_asset_text_data_save(_a);
                }
            } else if (_a.type == "MUSIC_MAKER") {
                // The sound editor has no inline_edit_open flag — it tracks
                // three independent text states of its own. Only the
                // instrument source affects what gets emitted; the song and
                // instrument NAME boxes are cosmetic, so they are deliberately
                // left mid-edit rather than force-committed.
                var _mm = _a.meta;
                if (variable_struct_exists(_mm, "instr_edit_active") && _mm.instr_edit_active) {
                    var _si = variable_struct_exists(_mm, "sel_instr") ? _mm.sel_instr : -1;
                    if (_si >= 0 && _si < array_length(_mm.instruments)) {
                        scr_sound_editor_commit_instrument(_mm, _mm.instruments[_si]);
                    }
                }
            }
        }
    }
}