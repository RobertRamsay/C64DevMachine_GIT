function scr_asset_inline_editor_close_all() {
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
            if (!variable_struct_exists(_a.meta, "inline_edit_open")) {
                continue;
            }
            if (!_a.meta.inline_edit_open) {
                continue;
            }
            if (_a.type == "BYTE_DATA") {
                scr_asset_byte_data_save(_a);
            } else if (_a.type == "LINE_COLL") {
                scr_line_coll_save(_a);
            } else if (_a.type == "TEXT_DATA") {
                scr_asset_text_data_save(_a);
            }
            _a.meta.inline_edit_open = false;
        }
    }
    // Release preview audio. The sound editor allocates a buffer sound per
    // channel on every audition and keeps the last one alive until something
    // replaces it — closing the editor is where that final one is reclaimed.
    // Channels are global rather than per-asset, so this runs unconditionally:
    // the loop above only handles BYTE_DATA/TEXT_DATA and never sees a
    // SOUND_EDITOR asset at all.
    for (var _fci = 0; _fci < 3; _fci++) {
        scr_sound_preview_free_channel(_fci);
    }

    // Drain any pending characters so they don't leak to other systems
    keyboard_string = "";

    // Every inline editor is now closed, so no inline text field can still be
    // taking input — release the global text-entry lock.
    //
    // The three EDIT buttons (BYTE_DATA / TEXT_DATA / LINE_COLL) raise this
    // flag once when they open and lower it once on their own CLOSE button.
    // Every OTHER way out of the viewer — ESC, the viewer's [X], clicking
    // outside it, deleting the asset — routed through here, which closed the
    // editor but left the flag raised. It gates every single-key shortcut in
    // obj_workspace_manager (node spawning, F1, F, B, the quick menus, camera
    // pan), so one ESC out of a text editor disabled L, A, J and the rest for
    // the remainder of the session.
    //
    // Clearing it here cannot steal the flag from a still-active text box:
    // the name / address / map-dimension / byte-string editors all re-assert
    // it at the top of their own block in obj_asset_manager's Step and then
    // exit, so Step never reaches any of this function's call sites while one
    // of them has focus.
    global.is_any_text_active = false;
}