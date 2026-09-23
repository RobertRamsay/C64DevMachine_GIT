/// Does the project differ from what was last saved / loaded?
///
/// global.manual_saved goes false on any mouse release that set undo_dirty /
/// addresses_dirty - including clicks that change nothing - so on its own it
/// asks "unsaved changes?" after a save when there are none. This confirms
/// against the md5 of the project JSON a save would write now vs the one
/// written / loaded last (global.saved_hash). No baseline yet = assume changed.
function scr_workspace_has_changes() {
    if (global.manual_saved) { return false; }
    if (global.saved_hash == "") { return true; }
    var _now = scr_save_workspace_as_path("", true);
    if (_now == global.saved_hash) {
        global.manual_saved = true;
        return false;
    }
    return true;
}
