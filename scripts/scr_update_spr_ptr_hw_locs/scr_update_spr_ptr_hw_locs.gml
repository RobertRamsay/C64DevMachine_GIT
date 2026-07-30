/// @desc scr_update_spr_ptr_hw_locs()
/// Recomputes HW_SPR_PTR0-7 addresses based on the active VIC configuration.
/// Priority: MACRO_BMP > MACRO_VIC > sprite asset bank > $0400 absolute fallback.
/// Call from scr_c64_do_update_addresses() each frame.
function scr_update_spr_ptr_hw_locs() {

    // ---- Step 1: Determine screen RAM from connected nodes ----
    var _screen_ram = -1;

    // MACRO_BMP takes highest priority
    var _bmp_found = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_BMP" && is_connected) {
            var _bmp_addr = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0x4000;
            var _bmp_bank = floor(_bmp_addr / 0x4000);
            var _bmp_base = _bmp_bank * 0x4000;
            var _bmp_scr  = _bmp_addr + 0x2000;
            if (_bmp_bank == 2) _bmp_scr = _bmp_base + 0x3C00;
            if (_bmp_bank == 3) _bmp_scr = _bmp_base + 0x0400;
            _screen_ram = _bmp_scr;
            _bmp_found  = true;
            break;
        }
    }

// MACRO_VIC next
    if (!_bmp_found) {
        with (obj_c64_node) {
            if (node_type == "MACRO_VIC" && is_connected) {
                _screen_ram = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0x0400;
                break;
            }
        }
    }

    // MACRO_MAP implies bank 0, screen at $0400 -> pointers at $07F8
    if (_screen_ram == -1) {
        with (obj_c64_node) {
            if (node_type == "MACRO_MAP" && is_connected) {
                _screen_ram = 0x0400;
                break;
            }
        }
    }

    // Sprite asset bank fallback — pull asset name out of with() first
    // to avoid GML scoping issues with inner variable writes
    if (_screen_ram == -1) {
        var _spr_asset_name = "";
        with (obj_c64_node) {
            if (node_type == "MACRO_SPR" && is_connected) {
                _spr_asset_name = string(instructions[0][1]);
                break;
            }
        }
        if (_spr_asset_name != "" && instance_exists(obj_asset_manager)) {
            var _am = obj_asset_manager;
            for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                var _a = ds_list_find_value(_am.asset_list, _ai);
                if (_a.type == "SPRITE_SET" && _a.name == _spr_asset_name) {
                    var _spr_bank_base = (_a.address >> 14) * 0x4000;
                    _screen_ram = _spr_bank_base + 0x0400;
                    break;
                }
            }
        }
    }

    // Absolute last resort
    if (_screen_ram == -1) {
        _screen_ram = 0x0400;
    }

    // ---- Step 2: Compute the pointer base ----
    var _ptr_base = _screen_ram + 0x03F8;

    // ---- Step 3: Patch named_loc_map ----
    for (var _slot = 0; _slot < 8; _slot++) {
        var _name = "HW_SPR_PTR" + string(_slot);
        var _addr = _ptr_base + _slot;
        if (ds_map_exists(global.named_loc_map, _name)) {
            ds_map_replace(global.named_loc_map, _name, _addr);
        }
    }

    // ---- Step 4: Patch named_loc_meta ----
    for (var _mi = 0; _mi < array_length(global.named_loc_meta); _mi++) {
        var _m = global.named_loc_meta[_mi];
        if (string_pos("HW_SPR_PTR", _m.name) == 1) {
            var _slot = real(string_copy(_m.name, 11, string_length(_m.name) - 10));
            _m.addr = _ptr_base + _slot;
        }
    }
}