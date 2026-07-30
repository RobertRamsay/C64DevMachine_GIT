/// scr_sfx_data_find_asset(_name)
/// Returns the SFX_DATA asset struct with that name, or noone.
function scr_sfx_data_find_asset(_name) {
    if (!instance_exists(obj_asset_manager)) return noone;
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.type == "SFX_DATA" && _a.name == _name) return _a;
    }
    return noone;
}
