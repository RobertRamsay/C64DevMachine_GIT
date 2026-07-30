function scr_macro_spr_sync(_node_id) {
    if (!instance_exists(_node_id)) exit;
    if (!_node_id.is_expanded) exit;

    var _frame      = real(_node_id.instructions[0][5]);  // MOVED UP
    var _slot       = clamp(real(_node_id.instructions[0][2]), 0, 7);
    var _sx         = real(_node_id.instructions[0][3]);
    var _sy         = real(_node_id.instructions[0][4]);

    var _bank_addr  = 0x7000;
    var _mc_flag    = 0;
    var _asset_name = string(_node_id.instructions[0][1]);
    if (instance_exists(obj_asset_manager) && _asset_name != "") {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "SPRITE_SET" && _a.name == _asset_name) {
                _bank_addr = _a.address;
                if (variable_struct_exists(_a.meta, "sprite_mcs") &&
                    _frame < array_length(_a.meta.sprite_mcs)) {
                    _mc_flag = _a.meta.sprite_mcs[_frame];
                }
                break;
            }
        }
    }
    // OLD spr_link BLOCK REMOVED

    var _spr_ptr    = (_bank_addr / 64) + _frame;
	var _vic_bank   = _bank_addr & 0xC000;
    var _screen_ram = _vic_bank + 0x2000;
    var _ptr_reg    = _screen_ram + 0x03F8 + _slot;
    var _x_reg      = 0xD000 + (_slot * 2);
    var _y_reg      = 0xD001 + (_slot * 2);
    var _en_bit     = (1 << _slot);

    var _expected = [
        _spr_ptr, _ptr_reg,
        _sx,      _x_reg,
        _sy,      _y_reg,
        _en_bit,  0xD015,
        _mc_flag, 0xD01C
    ];

    var _children = [];
    with (obj_c64_node) {
        if (variable_instance_exists(id, "macro_owner") && macro_owner == _node_id) {
            array_push(_children, id);
        }
    }
    array_sort(_children, function(_a, _b) { return _a.y - _b.y; });
    for (var _i = 0; _i < min(array_length(_children), array_length(_expected)); _i++) {
        _children[_i].instructions[0][1] = _expected[_i];
    }
    scr_c64_update_addresses();
}