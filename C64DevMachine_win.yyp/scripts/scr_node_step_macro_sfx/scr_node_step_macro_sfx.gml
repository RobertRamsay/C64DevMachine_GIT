/// scr_node_step_macro_sfx(_draw_x)
/// Click handler for MACRO_SFX.

function scr_node_step_macro_sfx(_draw_x) {
    while (array_length(instructions[0]) < 4) array_push(instructions[0], "");
    if (!is_real(instructions[0][2]) || instructions[0][2] == "") instructions[0][2] = 0;
    if (!is_real(instructions[0][3]) || instructions[0][3] == "") instructions[0][3] = 3;

    var _native_sfx=scr_sfx_data_find_asset(string(instructions[0][1]));
    if (is_struct(_native_sfx) && _native_sfx.type=="SFX_MAKER") {
        // Compact rows (scr_sfx_maker_node_draw): ASSET y+28, EFFECT y+42,
        // VOICE y+56, ACTION y+70, each 14px tall.
        var _nx1 = _draw_x + 68;
        var _nx2 = _draw_x + width - 8;
        if (point_in_rectangle(mouse_x, mouse_y, _nx1, y + 27, _nx2, y + 41)) {
            if (instance_exists(obj_asset_manager)) {
                obj_asset_manager.sfx_picker_open  = true;
                obj_asset_manager.sfx_picker_node  = id;
                obj_asset_manager.sfx_picker_hover = -1;
                obj_asset_manager.sfx_picker_field = "asset";
            }
            exit;
        }
        if (point_in_rectangle(mouse_x, mouse_y, _nx1, y + 41, _nx2, y + 55)) {
            if (instance_exists(obj_asset_manager)) {
                obj_asset_manager.sfx_picker_open  = true;
                obj_asset_manager.sfx_picker_node  = id;
                obj_asset_manager.sfx_picker_hover = -1;
                obj_asset_manager.sfx_picker_field = "instrument";
            }
            exit;
        }
        if (point_in_rectangle(mouse_x, mouse_y, _nx1, y + 55, _nx2, y + 69)) {
            var _nv = real(instructions[0][3]);
            if (_nv >= 3) {
                instructions[0][3] = 1;
            } else {
                instructions[0][3] = _nv + 1;
            }
            global.addresses_dirty = true;
            exit;
        }
        if (point_in_rectangle(mouse_x, mouse_y, _nx1, y + 69, _nx2, y + 83)) {
            while(array_length(instructions[0])<5) array_push(instructions[0],0);
            instructions[0][4]=(real(instructions[0][4])+1) mod 4;
            global.addresses_dirty=true;global.undo_dirty=true;exit;
        }
        exit;   // the native layout has no other click areas
    }
    var _val_x1 = _draw_x + 72;
    var _val_x2 = _draw_x + width - 8;
    var _fld_h  = 16;

    // ── Asset field — open SFX_DATA picker ───────────────────────────────
    var _ay = y + 30;
    if (point_in_rectangle(mouse_x, mouse_y, _val_x1, _ay, _val_x2, _ay + _fld_h)) {
        if (instance_exists(obj_asset_manager)) {
            obj_asset_manager.sfx_picker_open  = true;
            obj_asset_manager.sfx_picker_node  = id;
            obj_asset_manager.sfx_picker_hover = -1;
            obj_asset_manager.sfx_picker_field = "asset";
        }
        exit;
    }

    // ── Instrument field — open instrument index picker ───────────────────
    var _iy = y + 52;
    if (point_in_rectangle(mouse_x, mouse_y, _val_x1, _iy, _val_x2, _iy + _fld_h)) {
        var _asset_name = string(instructions[0][1]);
        if (_asset_name == "" || _asset_name == "0") exit;
        if (instance_exists(obj_asset_manager)) {
            obj_asset_manager.sfx_picker_open  = true;
            obj_asset_manager.sfx_picker_node  = id;
            obj_asset_manager.sfx_picker_hover = -1;
            obj_asset_manager.sfx_picker_field = "instrument";
        }
        exit;
    }

    // ── Voice field — left click cycles 1→2→3→1 ──────────────────────────
    var _vbx1 = _draw_x + 50;
    var _vbx2 = _draw_x + width - 8;
    var _vy2_ = y + 74;
    if (point_in_rectangle(mouse_x, mouse_y, _vbx1, _vy2_, _vbx2, _vy2_ + _fld_h)) {
        var _v = real(instructions[0][3]);
        instructions[0][3] = (_v >= 3) ? 1 : _v + 1;
        global.addresses_dirty = true;
        exit;
    }
}
