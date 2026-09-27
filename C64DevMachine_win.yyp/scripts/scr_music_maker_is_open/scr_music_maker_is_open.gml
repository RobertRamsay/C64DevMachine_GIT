/// @function scr_music_maker_is_open()
/// @desc True while the Music Maker editor is the open asset viewer. Its
///       transport owns F1-F4 (GoatTracker layout), so the workspace's own
///       F1 (welcome screen) and F4 (export) stand down while it is open.
function scr_music_maker_is_open() {
    if (!instance_exists(obj_asset_manager)) {
        return false;
    }
    var _am = obj_asset_manager;
    if (!_am.viewer_open) {
        return false;
    }
    if (_am.viewer_asset < 0 || _am.viewer_asset >= ds_list_size(_am.asset_list)) {
        return false;
    }
    return (ds_list_find_value(_am.asset_list, _am.viewer_asset).type == "MUSIC_MAKER");
}
