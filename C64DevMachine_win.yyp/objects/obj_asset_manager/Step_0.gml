/// @desc obj_asset_manager Step
// Find the max whole-number scale that fits inside the current window size
// DEBUG — watch for unauthorised writes to the imported .txt
{
    var _watch_path = "C:\\Users\\me\\Downloads\\Mechs_Demo.txt";
    if (file_exists(_watch_path)) {
        var _new_md5 = md5_file(_watch_path);
        if (!variable_instance_exists(id, "_watch_md5")) {
            _watch_md5 = _new_md5;
            show_debug_message("WATCH: initial MD5 = " + _new_md5);
        } else if (_watch_md5 != _new_md5) {
            show_debug_message("!!! WATCH: FILE CHANGED");
            show_debug_message("    old MD5: " + _watch_md5);
            show_debug_message("    new MD5: " + _new_md5);
            _watch_md5 = _new_md5;
        }
    }
}

var _scale_x = window_get_width() div 480;
var _scale_y = window_get_height() div 300;

// Calculate what the base cap SHOULD be right now
var _new_base = max(1, min(_scale_x, _scale_y));


// Only update and snap the zoom if the window size ACTUALLY changed.
// This allows the user to still use their mouse wheel without it instantly resetting!
if (bmp_ui_zoom_cap_base != _new_base) {
    bmp_ui_zoom_cap_base = _new_base;
    bmp_ui_zoom_cap      = bmp_ui_zoom_cap_base; 
}

var _gui_w        = global.gui_w;
var _gui_h        = display_get_gui_height();
var _mx           = global.gui_mouse_x;
var _my           = global.gui_mouse_y;
var _panel_right  = _gui_w - 2;
var _panel_bottom = _gui_h - 100;
var _panel_w      = _panel_right - panel_x;
var _panel_h      = _panel_bottom - panel_y;

panel_w = 244;
panel_x = _gui_w - panel_w - 30;
panel_y = 410;
global.mouse_in_asset_panel = false;
global.mouse_in_asset_panel = point_in_rectangle(_mx, _my, panel_x, panel_y, panel_x + panel_w, panel_y + panel_h);

var _mouse_in_panel = global.mouse_in_asset_panel

// Viewer bounds — must match Draw GUI exactly.
// BITMAP_BUILDER runs a wider layout and starts further left.
var _vx1 = 288;
if (viewer_open && viewer_asset >= 0 && viewer_asset < ds_list_size(asset_list)) {
    var _vb_asset = ds_list_find_value(asset_list, viewer_asset);
    if (_vb_asset.type == "BITMAP_BUILDER") {
        _vx1 = 30;
    }
}
var _vy1 = 108;
var _vx2 = panel_x - 10;
if (viewer_open && viewer_asset >= 0 && viewer_asset < ds_list_size(asset_list)) {
    var _vb2_asset = ds_list_find_value(asset_list, viewer_asset);
    if (_vb2_asset.type == "BITMAP_BUILDER") {
        _vx2 = panel_x + 20;
    }
}
var _vy2 = 972;
var _mouse_in_viewer = viewer_open && point_in_rectangle(_mx, _my, _vx1, _vy1, _vx2, _vy2);

// -------------------------------------------------------
// WINDOW FOCUS — reload changed asset files + text editor pickup
// -------------------------------------------------------
var _focused = window_has_focus();

// Check for Spred64 save every frame (md5 polling — not focus dependent)

if (spr_edit_path != "" &&
    spr_edit_md5   != "" &&
    spr_edit_asset >= 0  &&
    spr_edit_asset < ds_list_size(asset_list)) {
    if (file_exists(spr_edit_path)) {
        var _current_md5 = md5_file(spr_edit_path);
        if (_current_md5 != spr_edit_md5) {
            var _sa = ds_list_find_value(asset_list, spr_edit_asset);
            scr_asset_spr_import_spred64_text(_sa, spr_edit_path);
            // Force surface rebuild
            if (variable_struct_exists(_sa.meta, "preview_surf") &&
                surface_exists(_sa.meta.preview_surf)) {
                surface_free(_sa.meta.preview_surf);
                _sa.meta.preview_surf = -1;
            }
            scr_asset_spr_cache_sprites(_sa, true);
            // Update md5 so next save triggers again
            spr_edit_md5 = md5_file(spr_edit_path);
            reload_notify_names = [];
            array_push(reload_notify_names, _sa.name + " (SPRED64 EDIT)");
            reload_notify_timer = 180;
            // Keep spr_edit_path active — watch for further saves
        }
    }
}

if (_focused && !_last_focus) {
    reload_notify_names = [];

    // Pick up text edited externally in notepad
    if (text_edit_path != "" &&
        text_edit_asset >= 0 &&
        text_edit_asset < ds_list_size(asset_list)) {
		if (file_exists(text_edit_path)) {
            var _ta   = ds_list_find_value(asset_list, text_edit_asset);
var _tbuf = buffer_load(text_edit_path);
                if (buffer_exists(_tbuf)) {
                    var _tstr = "";
                    var _bsz = buffer_get_size(_tbuf);
                    // Detect UTF-16 LE BOM (FF FE)
                    if (_bsz >= 2 &&
                        buffer_peek(_tbuf, 0, buffer_u8) == 0xFF &&
                        buffer_peek(_tbuf, 1, buffer_u8) == 0xFE) {
                        // Read UTF-16 LE: skip BOM, read every other byte (lo byte of each u16)
                        for (var _bi = 2; _bi < _bsz - 1; _bi += 2) {
                            var _lo = buffer_peek(_tbuf, _bi, buffer_u8);
                            if (_lo == 0) break;
                            _tstr += chr(_lo);
                        }
                    } else {
                        buffer_seek(_tbuf, buffer_seek_start, 0);
                        _tstr = buffer_read(_tbuf, buffer_text);
                    }
                    buffer_delete(_tbuf);
                if (!variable_struct_exists(_ta, "meta")) _ta.meta = {};
				if (_ta.type == "BYTE_DATA") {
                    _ta.meta.byte_string = _tstr;
                    scr_asset_byte_data_flush(_ta);
                    array_push(reload_notify_names, _ta.name + " (BYTE EDIT)");
                } else if (_ta.type == "CHAR_SET") {
                    // Convert Hex Text back to Buffer
                    var _clean = string_replace_all(_tstr, "$", "");
                    _clean = string_replace_all(_clean, ",", " ");
                    _clean = string_replace_all(_clean, "\r", " ");
                    _clean = string_replace_all(_clean, "\n", " ");
                    
                    var _vals = string_split_ext(_clean, [" ", "  "], true);
                    var _count = array_length(_vals);
                    
                    buffer_delete(_ta.buffer);
                    _ta.buffer = buffer_create(_count, buffer_fixed, 1);
                    for (var _vi = 0; _vi < _count; _vi++) {
                        buffer_write(_ta.buffer, buffer_u8, hex_to_decimal(_vals[_vi]));
                    }
                    _ta.meta.char_count = floor(_count / 8);
                    _ta.meta.total_size = _count;
                    scr_asset_chr_build_preview(_ta);
                    array_push(reload_notify_names, _ta.name + " (TILE EDIT)");
                } else {
                    _ta.meta.text = _tstr;
                    scr_asset_text_flush(_ta);
                    array_push(reload_notify_names, _ta.name + " (TEXT EDIT)");
                }
                reload_notify_timer = 180;
                global.addresses_dirty = true;
            }
        }
        text_edit_path  = "";
        text_edit_asset = -1;
    }

    // Standard file-change detection for all assets
    for (var _ri = 0; _ri < ds_list_size(asset_list); _ri++) {
        var _ra = ds_list_find_value(asset_list, _ri);
if (_ra.file == "") continue;
        var _watch_file = (variable_struct_exists(_ra.meta, "source_file") && _ra.meta.source_file != "")
                        ? _ra.meta.source_file : _ra.file;
        if (!file_exists(_watch_file)) continue;
        var _mtime = md5_file(_watch_file);
        if (!variable_struct_exists(_ra.meta, "_mtime")) {
            _ra.meta._mtime = _mtime; // initialise to current — no spurious reload on first focus
        }
if (_ra.meta._mtime != _mtime) {
            _ra.meta._mtime = _mtime;
            array_push(reload_notify_names, _ra.name);
            reload_notify_timer = 180;
            show_debug_message("RELOAD SWITCH: " + _ra.name + " type=" + _ra.type);
            var _src = (variable_struct_exists(_ra.meta, "source_file") && _ra.meta.source_file != "")
                     ? _ra.meta.source_file : _ra.file;
            if (_src != _ra.file && file_exists(_src)) file_copy(_src, _ra.file);

switch (_ra.type) {
                case "SPRITE_SET": break;
                case "BITMAP":     scr_asset_kla_reload(_ra);           break;
                case "SID_MUSIC":  scr_asset_sid_reload(_ra);           break;
                case "SFX_DATA":   scr_asset_sfx_reload(_ra);           break;
                case "CHAR_SET":   scr_asset_chr_reload(_ra);           break;
                case "MAP_DATA":   break; // never auto-reload — edits live in memory, flush on save
				case "META_TILESET":  break;
				case "META_MAP":      break;
                case "TEXT_DATA":  scr_asset_txt_import(_ra, _ra.file); break;
            }
        }
    }
}
_last_focus = _focused;
if (reload_notify_timer > 0) reload_notify_timer--;

// -------------------------------------------------------
// BYTE_DATA STRING EDITING INPUT
// -------------------------------------------------------
if (byte_data_editing) {
    global.is_any_text_active = true;
    if (keyboard_string != "") {
        byte_data_edit_string += keyboard_string;
        keyboard_string = "";
    }
    if (keyboard_check_pressed(vk_backspace) && string_length(byte_data_edit_string) > 0) {
        byte_data_edit_string = string_delete(byte_data_edit_string, string_length(byte_data_edit_string), 1);
        keyboard_string = "";
    }
    if (keyboard_check_pressed(vk_enter)) {
        if (byte_data_edit_idx >= 0 && byte_data_edit_idx < ds_list_size(asset_list)) {
            var _ba = ds_list_find_value(asset_list, byte_data_edit_idx);
            _ba.meta.byte_string = byte_data_edit_string;
            scr_asset_byte_data_flush(_ba);
            global.addresses_dirty = true;
        }
        byte_data_editing    = false;
        byte_data_edit_idx   = -1;
        byte_data_edit_string = "";
        global.is_any_text_active = false;
        keyboard_string = "";
    }
    if (keyboard_check_pressed(vk_escape)) {
        byte_data_editing    = false;
        byte_data_edit_idx   = -1;
        byte_data_edit_string = "";
        global.is_any_text_active = false;
        keyboard_string = "";
        keyboard_clear(vk_escape);
    }
    exit;
}


// -------------------------------------------------------
// ADDRESS EDITING INPUT
// -------------------------------------------------------
if (editing_address) {
	global.is_any_text_active = true;
    if (keyboard_string != "") {
        var _k = string_upper(keyboard_string);
        keyboard_string = "";
        for (var _ki = 1; _ki <= string_length(_k); _ki++) {
            var _ch = string_char_at(_k, _ki);
            if (((_ch >= "0" && _ch <= "9") || (_ch >= "A" && _ch <= "F")) &&
                string_length(editing_addr_string) < 4) {
                editing_addr_string += _ch;
            }
        }
    }
    if (keyboard_check_pressed(vk_backspace)) {
        if (string_length(editing_addr_string) > 0)
            editing_addr_string = string_delete(editing_addr_string,
                string_length(editing_addr_string), 1);
        keyboard_string = "";
    }
if (keyboard_check_pressed(vk_enter)) {
        if (editing_address_idx >= 0 && editing_address_idx < ds_list_size(asset_list)) {
            var _asset = ds_list_find_value(asset_list, editing_address_idx);
            if (string_length(editing_addr_string) > 0)
            {
                _asset.address = hex_to_decimal(editing_addr_string);

                // Re-sync any MACRO_CHR nodes linked to this charset so $D018
                // (and $D011/$D016) update immediately rather than waiting for
                // a node click or recompile.
                if (_asset.type == "CHAR_SET")
                {
                    var _changed_name = _asset.name;
                    with (obj_c64_node)
                    {
                        if (node_type == "MACRO_CHR")
                        {
                            if (array_length(instructions[0]) > 1)
                            {
                                if (string(instructions[0][1]) == _changed_name)
                                {
                                    scr_macro_chr_sync(id);
                                }
                            }
                        }
                    }
                }

                global.addresses_dirty  = true;
                global.memory_bar_dirty = true;
            }
        }
        editing_address           = false;
        editing_address_idx       = -1;
        editing_addr_string       = "";
        global.is_any_text_active = false;
        keyboard_string           = "";
    }
// FIX: escape now correctly clears address editing vars (was wrongly clearing editing_name vars)
    if (keyboard_check_pressed(vk_escape)) {
        editing_address           = false;
        editing_address_idx       = -1;
        editing_addr_string       = "";
        global.is_any_text_active = false;
        keyboard_string           = "";
        keyboard_clear(vk_escape);
    }

    // CLICK-AWAY: a left-click while editing commits the current value and
    // closes the editor. The hit-test rectangle for the active box is stored
    // each frame in the Draw GUI as editing_addr_box_x1/y1/x2/y2. If the click
    // lands outside that box (or the box coords are stale/unset), commit + close.
    if (mouse_check_button_pressed(mb_left)) {
        var _mx_ca = global.gui_mouse_x;
        var _my_ca = global.gui_mouse_y;
        var _in_box = false;
        if (variable_instance_exists(id, "editing_addr_box_x1")) {
            _in_box = point_in_rectangle(_mx_ca, _my_ca,
                editing_addr_box_x1, editing_addr_box_y1,
                editing_addr_box_x2, editing_addr_box_y2);
        }
        if (!_in_box) {
            if (editing_address_idx >= 0 && editing_address_idx < ds_list_size(asset_list)) {
                var _asset_ca = ds_list_find_value(asset_list, editing_address_idx);
                if (string_length(editing_addr_string) > 0) {
                    _asset_ca.address = hex_to_decimal(editing_addr_string);
                    if (_asset_ca.type == "CHAR_SET") {
                        var _changed_name_ca = _asset_ca.name;
                        with (obj_c64_node) {
                            if (node_type == "MACRO_CHR") {
                                if (array_length(instructions[0]) > 1) {
                                    if (string(instructions[0][1]) == _changed_name_ca) {
                                        scr_macro_chr_sync(id);
                                    }
                                }
                            }
                        }
                    }
                    global.addresses_dirty  = true;
                    global.memory_bar_dirty = true;
                }
            }
            editing_address           = false;
            editing_address_idx       = -1;
            editing_addr_string       = "";
            global.is_any_text_active = false;
            keyboard_string           = "";
        }
    }

    exit;
}

// -------------------------------------------------------
// MAP DIMENSION EDITING INPUT
// -------------------------------------------------------
if (editing_map_dim) {
    global.is_any_text_active = true;
    if (keyboard_string != "") {
        var _k = keyboard_string;
        keyboard_string = "";
        for (var _ki = 1; _ki <= string_length(_k); _ki++) {
            var _ch = string_char_at(_k, _ki);
            if (_ch >= "0" && _ch <= "9" && string_length(editing_map_string) < 4)
                editing_map_string += _ch;
        }
    }
    if (keyboard_check_pressed(vk_backspace)) {
        if (string_length(editing_map_string) > 0)
            editing_map_string = string_delete(editing_map_string, string_length(editing_map_string), 1);
        keyboard_string = "";
    }
    if (keyboard_check_pressed(vk_enter)) {
        if (editing_map_asset_idx >= 0 && editing_map_asset_idx < ds_list_size(asset_list) &&
            string_length(editing_map_string) > 0) {
			var _ma   = ds_list_find_value(asset_list, editing_map_asset_idx);
            var _m    = _ma.meta;

            // META_TILESET has its own metatile-aware reflow (per active map).
            if (_ma.type == "META_TILESET") {
                var _mts_val = real(editing_map_string);
                if (_m.active_map >= 0 && _m.active_map < array_length(_m.maps)) {
                    if (editing_map_field == "W") {
                        scr_mts_resize_map(_m, _m.active_map, _mts_val, _m.map_h[_m.active_map]);
                    } else {
                        scr_mts_resize_map(_m, _m.active_map, _m.map_w[_m.active_map], _mts_val);
                    }
                }
                editing_map_dim       = false;
                editing_map_field     = "";
                editing_map_string    = "";
                editing_map_asset_idx = -1;
                global.is_any_text_active = false;
                keyboard_string = "";
                exit;
            }

            // Backfill physical dims for assets that predate this feature
            if (!variable_struct_exists(_m, "grid_w")) _m.grid_w = _m.map_w;
            if (!variable_struct_exists(_m, "grid_h")) _m.grid_h = _m.map_h;
      
            var _raw_val    = real(editing_map_string);
            var _other_dim  = (editing_map_field == "W") ? _m.map_h : _m.map_w;
            var _max_cells  = 8000;
            var _max_this   = floor(_max_cells / max(1, _other_dim));
            var _min_this   = (editing_map_field == "W") ? 1 : 1;
            var _val        = clamp(_raw_val, _min_this, _max_this);
            if (_raw_val > _max_this) {
                show_debug_message("MAP DIM: clamped " + editing_map_field
                    + " from " + string(_raw_val)
                    + " to " + string(_val)
                    + " (total cells would exceed 8000)");
            }
            if (editing_map_field == "W" && (_val mod 2 != 0)) _val++;
            if (editing_map_field == "W") {
                // Grow physical grid if needed — new cols appended on right, left anchor preserved
                if (_val > _m.grid_w) {
                    var _new_gw  = _val;
                    var _new_sz  = _new_gw * _m.grid_h;
                    var _new_cg  = array_create(_new_sz, 0);
                    var _new_col = array_create(_new_sz, 1);
                    var _new_ov  = array_create(_new_sz, 0);
                    // Re-stride ALL THREE planes together. override_grid MUST be
                    // re-strided here too — if it isn't, flush rebuilds it with a
                    // flat copy at the new width and scrambles every per-cell HR/MC
                    // flag below row 0.
                    if (!variable_struct_exists(_m, "override_grid") ||
                        array_length(_m.override_grid) != _m.grid_w * _m.grid_h) {
                        _m.override_grid = array_create(_m.grid_w * _m.grid_h, 0);
                    }
                    for (var _r = 0; _r < _m.grid_h; _r++) {
                        for (var _c = 0; _c < _m.grid_w; _c++) {
                            _new_cg[_r * _new_gw + _c]  = _m.char_grid[_r * _m.grid_w + _c];
                            _new_col[_r * _new_gw + _c] = _m.colour_grid[_r * _m.grid_w + _c];
                            _new_ov[_r * _new_gw + _c]  = _m.override_grid[_r * _m.grid_w + _c];
                        }
                    }
                    _m.char_grid     = _new_cg;
                    _m.colour_grid   = _new_col;
                    _m.override_grid = _new_ov;
                    _m.grid_w        = _new_gw;
                }
                _m.map_w = min(_val, _m.grid_w);
            } else {
                // Grow physical grid if needed
                if (_val > _m.grid_h) {
                    var _new_gh  = _val;
                    var _new_sz  = _m.grid_w * _new_gh;
                    var _new_cg  = array_create(_new_sz, 0);
                    var _new_col = array_create(_new_sz, 1);
                    var _new_ov  = array_create(_new_sz, 0);
                    // Re-stride override_grid alongside char/colour. Width is
                    // unchanged here so this is a straight copy, but the plane must
                    // still be carried into the larger array or flush will rebuild
                    // it flat and lose the per-cell HR/MC flags.
                    if (!variable_struct_exists(_m, "override_grid") ||
                        array_length(_m.override_grid) != _m.grid_w * _m.grid_h) {
                        _m.override_grid = array_create(_m.grid_w * _m.grid_h, 0);
                    }
                    for (var _r = 0; _r < _m.grid_h; _r++) {
                        for (var _c = 0; _c < _m.grid_w; _c++) {
                            _new_cg[_r * _m.grid_w + _c]  = _m.char_grid[_r * _m.grid_w + _c];
                            _new_col[_r * _m.grid_w + _c] = _m.colour_grid[_r * _m.grid_w + _c];
                            _new_ov[_r * _m.grid_w + _c]  = _m.override_grid[_r * _m.grid_w + _c];
                        }
                    }
                    _m.char_grid     = _new_cg;
                    _m.colour_grid   = _new_col;
                    _m.override_grid = _new_ov;
                    _m.grid_h        = _new_gh;
                }
                _m.map_h = min(_val, _m.grid_h);
            }
            scr_asset_map_flush(_ma);
            // Re-sync any MACRO_MAP nodes referencing this asset
            with (obj_c64_node) {
                if (node_type == "MACRO_MAP" && string(instructions[0][1]) == _ma.name)
                    scr_macro_map_sync(id);
            }
        }
        editing_map_dim       = false;
        editing_map_field     = "";
        editing_map_string    = "";
        editing_map_asset_idx = -1;
        global.is_any_text_active = false;
        keyboard_string = "";
    }
    if (keyboard_check_pressed(vk_escape)) {
        editing_map_dim       = false;
        editing_map_field     = "";
        editing_map_string    = "";
        editing_map_asset_idx = -1;
        global.is_any_text_active = false;
        keyboard_string = "";
        keyboard_clear(vk_escape);
    }
    exit;
}

// -------------------------------------------------------
// NAME EDITING INPUT
// -------------------------------------------------------
if (editing_name) {
    global.is_any_text_active = true;
    obj_workspace_manager.is_entering_text = false;
    obj_workspace_manager.keyboard_string  = "";
    if (keyboard_string != "") {
        var _add = keyboard_string;
        if (string_length(editing_string) + string_length(_add) <= 15) {
            editing_string = string_insert(_add, editing_string, editing_cursor + 1);
            editing_cursor += string_length(_add);
        }
        keyboard_string = "";
    }
if (keyboard_check_pressed(vk_backspace)) {
        if (keyboard_check(vk_control)) {
            editing_string = "";
            editing_cursor = 0;
        } else if (editing_cursor > 0) {
            editing_string = string_delete(editing_string, editing_cursor, 1);
            editing_cursor--;
        }
        keyboard_string = "";
    }
    if (keyboard_check_pressed(vk_left))  editing_cursor = max(0, editing_cursor - 1);
    if (keyboard_check_pressed(vk_right)) editing_cursor = min(string_length(editing_string), editing_cursor + 1);

if (keyboard_check_pressed(vk_enter) || mouse_check_button_pressed(mb_left)) {
    keyboard_string = "";
    var _commit_idx    = editing_idx;
    var _commit_string = editing_string;
    editing_name   = false;
    editing_idx    = -1;
    editing_string = "";
    editing_cursor = 0;
    if (_commit_idx >= 0 && _commit_idx < ds_list_size(asset_list)) {
            var _asset    = ds_list_find_value(asset_list, _commit_idx);
            var _proposed = (_commit_string == "") ? _asset.type : _commit_string;
            var _duplicate = false;
for (var _di = 0; _di < ds_list_size(asset_list); _di++) {
                if (_di == _commit_idx) continue;
                var _other = ds_list_find_value(asset_list, _di);
                if (_other.name == _proposed) { _duplicate = true; break; }
            }
            if (_duplicate) {
                var _suffix = 2;
                while (_duplicate) {
                    _proposed  = _commit_string + "_" + string(_suffix);
                    _duplicate = false;
for (var _di = 0; _di < ds_list_size(asset_list); _di++) {
                        if (_di == _commit_idx) continue;
                        var _other = ds_list_find_value(asset_list, _di);
                        if (_other.name == _proposed) { _duplicate = true; break; }
                    }
                    _suffix++;
                }
            }
            if (_asset.type == "SPRITE_SET") {
                var _sprites_dir = working_directory + "temp/sprites";
                var _old_name    = _asset.name;
                for (var _si = 0; _si < 64; _si++) {
                    var _old_png = _sprites_dir + "/" + _old_name + "_" + string(_si) + ".png";
                    var _new_png = _sprites_dir + "/" + _proposed  + "_" + string(_si) + ".png";
                    if (file_exists(_old_png)) file_rename(_old_png, _new_png);
                }
            }
			var _old_name             = _asset.name;
			_asset.name               = _proposed;

            // Patch asset-meta cross-references when the renamed asset is
            // something other assets point to by name:
            //   CHAR_SET name      ← referenced by MAP_DATA.meta.chr_asset and META_TILESET.meta.chr_asset
            //   META_TILESET name  ← referenced by META_MAP.meta.tileset_name
            if (_asset.type == "CHAR_SET") {
                for (var _rmi = 0; _rmi < ds_list_size(asset_list); _rmi++) {
                    var _rma = ds_list_find_value(asset_list, _rmi);
                    if (_rma.type == "MAP_DATA" && variable_struct_exists(_rma.meta, "chr_asset")) {
                        if (_rma.meta.chr_asset == _old_name) {
                            _rma.meta.chr_asset = _proposed;
                        }
                    }
                    if (_rma.type == "META_TILESET" && variable_struct_exists(_rma.meta, "chr_asset")) {
                        if (_rma.meta.chr_asset == _old_name) {
                            _rma.meta.chr_asset = _proposed;
                        }
                    }
                }
            }
            if (_asset.type == "META_TILESET") {
                for (var _rmi = 0; _rmi < ds_list_size(asset_list); _rmi++) {
                    var _rma = ds_list_find_value(asset_list, _rmi);
                    if (_rma.type == "META_MAP" && variable_struct_exists(_rma.meta, "tileset_name")) {
                        if (_rma.meta.tileset_name == _old_name) {
                            _rma.meta.tileset_name = _proposed;
                        }
                    }
                }
            }
			
			// added 16APR
			// Rename the physical file on disk to match the new asset name
            if (_asset.file != "" && file_exists(_asset.file)) {
                var _dir = filename_dir(_asset.file);
                var _ext = filename_ext(_asset.file);
                var _new_file = _dir + "/" + _proposed + _ext;
                
                if (file_rename(_asset.file, _new_file)) {
                    _asset.file = _new_file; // Update internal path to the new file
                }
            }
			// end of added 16APR
			
            // Update all node references to the old asset name
			with (obj_c64_node) {
                switch (node_type) {
					case "MACRO_BMP":
                    case "MACRO_SPR":
                    case "MACRO_SID":
                    case "MACRO_SFX":
                    case "MACRO_MAP":
                    case "MACRO_CHR":
                    case "MACRO_SID_SONG":
                        if (array_length(instructions[0]) > 1 &&
                            string(instructions[0][1]) == _old_name)
                            instructions[0][1] = _proposed;
                        break;
                    case "MACRO_TEXT_SCROLL":
                        // slot 10 = text/scroller asset, slot 13 = charset asset
                        if (array_length(instructions[0]) > 10 &&
                            string(instructions[0][10]) == _old_name)
                            instructions[0][10] = _proposed;
                        if (array_length(instructions[0]) > 13 &&
                            string(instructions[0][13]) == _old_name)
                            instructions[0][13] = _proposed;
                        break;
                    case "MACRO_ANIM":
                        // slots 0-7 are at indices 2-9
                        for (var _rai = 2; _rai <= 9; _rai++) {
                            if (array_length(instructions[0]) > _rai &&
                                string(instructions[0][_rai]) == _old_name)
                                instructions[0][_rai] = _proposed;
                        }
                        break;
                    case "MACRO_LOADER":
                        // slot 1 = LOAD_ORG name, slot 2 = linked file/asset name
                        if (array_length(instructions[0]) > 1 &&
                            string(instructions[0][1]) == _old_name)
                            instructions[0][1] = _proposed;
                        if (array_length(instructions[0]) > 2 &&
                            string(instructions[0][2]) == _old_name)
                            instructions[0][2] = _proposed;
                        break;
                    case "NEW_STR":
                        // slot 4 = "uses linked asset" flag, slot 5 = linked TEXT_DATA name
                        if (array_length(instructions[0]) > 5 &&
                            is_real(instructions[0][4]) &&
                            real(instructions[0][4]) == 1 &&
                            string(instructions[0][5]) == _old_name)
                            instructions[0][5] = _proposed;
                        break;
                    case "MACRO_COLL_ADV":
                        // slot 4 = MAP_DATA / META_TILESET / META_MAP asset name
                        if (array_length(instructions[0]) > 4 &&
                            string(instructions[0][4]) == _old_name)
                            instructions[0][4] = _proposed;
                        break;
                    case "GET_VAR":
                        // slot 3 = BYTE_DATA asset name (asset src mode only)
                        if (array_length(instructions[0]) > 3 &&
                            string(instructions[0][3]) == _old_name)
                            instructions[0][3] = _proposed;
                        break;
                    case "MACRO_METAMAP":
                        // slot 1 = META_TILESET asset name
                        if (array_length(instructions[0]) > 1 &&
                            string(instructions[0][1]) == _old_name)
                            instructions[0][1] = _proposed;
                        break;
                    case "MACRO_SID_SOUND":
                        // slot 21 = NOTE list (TEXT_DATA), slot 25 = WAVE list (BYTE_DATA)
                        if (array_length(instructions[0]) > 21 &&
                            string(instructions[0][21]) == _old_name)
                            instructions[0][21] = _proposed;
                        if (array_length(instructions[0]) > 25 &&
                            string(instructions[0][25]) == _old_name)
                            instructions[0][25] = _proposed;
                        break;
                }
            }
			// Update any LOAD_ORG linked_assets that reference the old name.
            // Also refresh d64_filename when it still matches the auto-derived
            // form of the old name — that way defaults track the rename, but
            // user-customised disk filenames are preserved as-is.
            var _old_auto_d64 = string_upper(string_copy(_old_name, 1, 16));
            var _new_auto_d64 = string_upper(string_copy(_proposed, 1, 16));
            for (var _loi = 0; _loi < ds_list_size(asset_list); _loi++) {
                var _loa = ds_list_find_value(asset_list, _loi);
                if (_loa.type != "LOAD_ORG") continue;
                if (!variable_struct_exists(_loa, "linked_assets")) continue;
                for (var _loli = 0; _loli < array_length(_loa.linked_assets); _loli++) {
                    var _link_ref = _loa.linked_assets[_loli];
                    if (_link_ref.asset_name == _old_name) {
                        _link_ref.asset_name = _proposed;
                        if (variable_struct_exists(_link_ref, "d64_filename")
                        &&  _link_ref.d64_filename == _old_auto_d64) {
                            _link_ref.d64_filename = _new_auto_d64;
                        }
                    }
                }
            }
            // Mark caches dirty — memory bar, address resolution and autosave
            // all index by name, so a rename invalidates each.
            global.memory_bar_dirty   = true;
            global.addresses_dirty    = true;
            global.autosave_dirty     = true;
            keyboard_string           = "";
            global.is_any_text_active = false;
            editorClosed              = 1;
            alarm[0]                  = 5;
        }
    }
	
    if (keyboard_check_pressed(vk_escape)) {
        editing_name   = false;
        editing_idx    = -1;
        editing_string = "";
        editing_cursor = 0;
        keyboard_clear(vk_escape);
    }
    exit;
}

// -------------------------------------------------------
// SCROLL
// -------------------------------------------------------
if (_mouse_in_panel) {
    var _count       = ds_list_size(asset_list);
    var _content_h   = _count * item_h;
    var _visible_h   = _panel_bottom - 38 - (panel_y + 66);
    var _max_visible = floor(_visible_h / item_h) * item_h;
    panel_max_scroll = max(0, _content_h - _max_visible);
    if (mouse_wheel_up())   panel_scroll = max(0, panel_scroll - item_h);
    if (mouse_wheel_down()) panel_scroll = min(panel_max_scroll, panel_scroll + item_h);
    panel_scroll = clamp(panel_scroll, 0, panel_max_scroll);
}

// -------------------------------------------------------
// HOVER
// -------------------------------------------------------
hover_idx = -1;
hover_pos = -1;
if (_mouse_in_panel && _my >= panel_y + 66 && _my <= _panel_bottom - 38) {
    var _hov_sorted = scr_asset_sorted_indices();
    for (var _pos = 0; _pos < ds_list_size(asset_list); _pos++) {
        var _iy1 = panel_y + 66 + (_pos * item_h) - panel_scroll;
        var _iy2 = _iy1 + item_h;
        if (_iy2 < panel_y + 66 || _iy1 > _panel_bottom - 38) continue;
        if (point_in_rectangle(_mx, _my, panel_x, _iy1, panel_x + panel_w, _iy2)) {
            hover_idx = _hov_sorted[_pos];
            hover_pos = _pos;
            break;
        }
    }
}

// -------------------------------------------------------
// ADD DROPDOWN HOVER
// -------------------------------------------------------
add_dropdown_hover = -1;
if (add_dropdown_open) {
    for (var _i = 0; _i < array_length(asset_types); _i++) {
        var _dy1 = panel_y + 28 + (_i * 20);
        var _dy2 = _dy1 + 20;
        if (point_in_rectangle(_mx, _my, panel_x, _dy1, panel_x + panel_w, _dy2)) {
            add_dropdown_hover = _i;
            break;
        }
    }
}

// -------------------------------------------------------
// SID PICKER
// -------------------------------------------------------
if (sid_picker_open) {
    if (!instance_exists(sid_picker_node)) { sid_picker_open = false; }
    else {
        var _cam_x    = obj_workspace_manager.cam_x;
        var _cam_y    = obj_workspace_manager.cam_y;
        var _cam_zoom = obj_workspace_manager.cam_zoom;
        var _node     = sid_picker_node;
        var _px       = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
        var _py       = ((_node.y + 24)              - _cam_y) / _cam_zoom;
        var _pw       = 180;
        var _ih       = 20;
var _matches  = [];
        for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
            var _a = ds_list_find_value(asset_list, _i);
            if (_a.type == "SID_MUSIC") array_push(_matches, _a);
        }
        var _total_h = max(1, array_length(_matches)) * _ih + 4;
        sid_picker_hover = -1;
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy = _py + 2 + (_i * _ih);
            if (point_in_rectangle(_mx, _my, _px, _iy, _px + _pw, _iy + _ih)) {
                sid_picker_hover = _i; break;
            }
        }
        if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
            if (sid_picker_hover >= 0) {
                _node.instructions[0][1] = _matches[sid_picker_hover].name;
                _node.instructions[0][2] = 0;
            }
            sid_picker_open = false; sid_picker_node = noone; sid_picker_hover = -1;
            exit;
        }
        if (mouse_check_button_pressed(mb_right) ||
            (mouse_check_button_pressed(mb_left) &&
             !point_in_rectangle(_mx, _my, _px, _py, _px + _pw, _py + _total_h))) {
            sid_picker_open = false; sid_picker_node = noone; sid_picker_hover = -1;
        }
    }
    exit;
}

if (sfx_picker_open) {
    if (!instance_exists(sfx_picker_node)) {
        sfx_picker_open = false;
    } else {
        var _cam_x    = obj_workspace_manager.cam_x;
        var _cam_y    = obj_workspace_manager.cam_y;
        var _cam_zoom = obj_workspace_manager.cam_zoom;
        var _node     = sfx_picker_node;
        var _px       = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
        var _py       = ((_node.y + 24)              - _cam_y) / _cam_zoom;
        var _pw       = 220;
        var _ih       = 20;

        // Build match list
        var _match_labels  = []; // display strings
        var _match_values  = []; // what gets stored (asset name string OR instrument index integer)

        if (sfx_picker_field == "asset") {
            for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
                var _a = ds_list_find_value(asset_list, _i);
                if (_a.type == "SFX_DATA") {
                    var _sfx_n = variable_struct_exists(_a.meta, "instruments")
                        ? array_length(_a.meta.instruments) : 0;
                    array_push(_match_labels, _a.name
                        + "  (" + string(_sfx_n) + " instr)");
                    array_push(_match_values, _a.name); // store asset name
                }
            }
        } else {
            // instrument index picker — list from selected asset
            var _asset_name = string(_node.instructions[0][1]);
            for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
                var _a = ds_list_find_value(asset_list, _i);
                if (_a.type == "SFX_DATA" && _a.name == _asset_name &&
                    variable_struct_exists(_a.meta, "instruments")) {
                    var _instrs = _a.meta.instruments;
                    for (var _ii = 0; _ii < array_length(_instrs); _ii++) {
                        var _ins = _instrs[_ii];
                        // "N: NAME  AD=$xx SR=$xx"
                        array_push(_match_labels,
                            string(_ii) + ": " + _ins.name
                            + "  $" + string_upper(decimal_to_hex(_ins.ad))
                            + "/$"  + string_upper(decimal_to_hex(_ins.sr)));
                        array_push(_match_values, _ii); // store index
                    }
                    break;
                }
            }
        }

        var _total_h = max(1, array_length(_match_labels)) * _ih + 24;

        sfx_picker_hover = -1;
        for (var _i = 0; _i < array_length(_match_labels); _i++) {
            var _iy = _py + 20 + (_i * _ih);
            if (point_in_rectangle(_mx, _my, _px, _iy, _px + _pw, _iy + _ih)) {
                sfx_picker_hover = _i;
                break;
            }
        }

        if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
            if (sfx_picker_hover >= 0) {
                if (sfx_picker_field == "asset") {
                    _node.instructions[0][1] = _match_values[sfx_picker_hover]; // asset name
                    _node.instructions[0][2] = 0; // reset instrument index when asset changes
                } else {
                    _node.instructions[0][2] = _match_values[sfx_picker_hover]; // instrument index
                }
                global.addresses_dirty = true;
            }
            sfx_picker_open  = false;
            sfx_picker_node  = noone;
            sfx_picker_hover = -1;
            sfx_picker_field = "asset";
            exit;
        }

        if (mouse_check_button_pressed(mb_right) ||
            (mouse_check_button_pressed(mb_left) &&
             !point_in_rectangle(_mx, _my, _px, _py, _px + _pw, _py + _total_h))) {
            sfx_picker_open  = false;
            sfx_picker_node  = noone;
            sfx_picker_hover = -1;
            sfx_picker_field = "asset";
        }
    }
    exit;
}


// -------------------------------------------------------
// SPRITE PICKER
// -------------------------------------------------------
if (spr_picker_open) {
    if (!instance_exists(spr_picker_node)) { spr_picker_open = false; }
    else {
        var _cam_x    = obj_workspace_manager.cam_x;
        var _cam_y    = obj_workspace_manager.cam_y;
        var _cam_zoom = obj_workspace_manager.cam_zoom;
        var _node     = spr_picker_node;
        var _px       = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
        var _py       = ((_node.y + 24)              - _cam_y) / _cam_zoom;
        var _pw       = 180;
        var _ih       = 20;
        var _matches  = [];
        for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
            var _a = ds_list_find_value(asset_list, _i);
            if (_a.type == "SPRITE_SET") array_push(_matches, _a);
        }
        var _total_h = max(1, array_length(_matches)) * _ih + 4;
        spr_picker_hover = -1;
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy = _py + 2 + (_i * _ih);
            if (point_in_rectangle(_mx, _my, _px, _iy, _px + _pw, _iy + _ih)) {
                spr_picker_hover = _i; break;
            }
        }
        if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
            if (spr_picker_hover >= 0)
                _node.instructions[0][1] = _matches[spr_picker_hover].name;
            spr_picker_open = false; spr_picker_node = noone; spr_picker_hover = -1;
            exit;
        }
        if (mouse_check_button_pressed(mb_right) ||
            (mouse_check_button_pressed(mb_left) &&
             !point_in_rectangle(_mx, _my, _px, _py, _px + _pw, _py + _total_h))) {
            spr_picker_open = false; spr_picker_node = noone; spr_picker_hover = -1;
        }
    }
    exit;
}

// -------------------------------------------------------
// SURFACE REBUILD ON RESIZE
// -------------------------------------------------------
if (last_gui_w != _gui_w || last_gui_h != _gui_h) {
    last_gui_w = _gui_w;
    last_gui_h = _gui_h;
    for (var _ri = 0; _ri < ds_list_size(asset_list); _ri++) {
        var _ra = ds_list_find_value(asset_list, _ri);
        // Rebuild even if no file exists (handles "Made" assets in memory)
        if (_ra.type == "CHAR_SET") scr_asset_chr_build_preview(_ra);
        if (_ra.type == "BITMAP"   && _ra.file != "") scr_asset_kla_reload(_ra);
        if (_ra.type == "SPRITE_SET" && _ra.file != "" && 
            variable_struct_exists(_ra.meta, "used_count")) scr_asset_spr_cache_sprites(_ra);
    }
}

// -------------------------------------------------------
// CHARSET PICKER (node-linked)
// -------------------------------------------------------
if (chr_picker_open) {
    if (!instance_exists(chr_picker_node)) { chr_picker_open = false; }
    else {
        var _cam_x    = obj_workspace_manager.cam_x;
        var _cam_y    = obj_workspace_manager.cam_y;
        var _cam_zoom = obj_workspace_manager.cam_zoom;
        var _node     = chr_picker_node;
        var _px       = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
        var _py       = ((_node.y + 24)              - _cam_y) / _cam_zoom;
        var _pw       = 180;
        var _ih       = 20;
        var _matches  = [];
        for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
            var _a = ds_list_find_value(asset_list, _i);
            if (_a.type == "CHAR_SET") array_push(_matches, _a);
        }
        var _total_h = max(1, array_length(_matches)) * _ih + 4;
        chr_picker_hover = -1;
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy = _py + 2 + (_i * _ih);
            if (point_in_rectangle(_mx, _my, _px, _iy, _px + _pw, _iy + _ih)) {
                chr_picker_hover = _i; break;
            }
        }
if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
            if (chr_picker_hover >= 0) {
                if (_node.node_type == "MACRO_TEXT_SCROLL") {
                    // Safe-guard array size and write to slot 13
                    while (array_length(_node.instructions[0]) <= 13) array_push(_node.instructions[0], 0);
                    _node.instructions[0][13] = _matches[chr_picker_hover].name;
                    scr_c64_update_addresses(); // Force visual and address refresh
                } else {
                    _node.instructions[0][1] = _matches[chr_picker_hover].name;
                    scr_macro_chr_sync(_node);
                }
            }
            chr_picker_open = false; chr_picker_node = noone; chr_picker_hover = -1;
            exit;
        }
        if (mouse_check_button_pressed(mb_right) ||
            (mouse_check_button_pressed(mb_left) &&
             !point_in_rectangle(_mx, _my, _px, _py, _px + _pw, _py + _total_h))) {
            chr_picker_open = false; chr_picker_node = noone; chr_picker_hover = -1;
        }
    }
    exit;
}

// -------------------------------------------------------
// LOAD_ORG ASSET PICKER
// -------------------------------------------------------
// MACRO_LOADER — LOAD_ORG picker (pick which D64 the node references)
	if (loader_org_picker_open) {
		if (!instance_exists(loader_org_picker_node)) {
			loader_org_picker_open  = false;
			loader_org_picker_node  = noone;
			loader_org_picker_hover = -1;
		} else {
			// Build LOAD_ORG list
			var _lop_matches = [];
			for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
				var _a = ds_list_find_value(asset_list, _i);
				if (_a.type == "LOAD_ORG") array_push(_lop_matches, _a);
			}
			loader_org_picker_hover = -1;
			var _drop_x = loader_org_picker_node.x + 68;
			var _drop_y = loader_org_picker_node.y + 36;
			for (var _i = 0; _i < array_length(_lop_matches); _i++) {
				var _ry = _drop_y + (_i * 16);
				if (point_in_rectangle(mouse_x, mouse_y, _drop_x, _ry, _drop_x + 180, _ry + 16)) {
					loader_org_picker_hover = _i;
					break;
				}
			}
			if (mouse_check_button_pressed(mb_left)) {
				if (loader_org_picker_hover >= 0) {
					var _picked = _lop_matches[loader_org_picker_hover];
					while (array_length(loader_org_picker_node.instructions[0]) <= 3) {
						array_push(loader_org_picker_node.instructions[0], "");
					}
					// If LOAD_ORG changed, clear file selection
					if (string(loader_org_picker_node.instructions[0][1]) != _picked.name) {
						loader_org_picker_node.instructions[0][2] = "";
					}
					loader_org_picker_node.instructions[0][1] = _picked.name;
					scr_c64_update_addresses();
				}
				loader_org_picker_open  = false;
				loader_org_picker_node  = noone;
				loader_org_picker_hover = -1;
			}
			if (mouse_check_button_pressed(mb_right) || keyboard_check_pressed(vk_escape)) {
				loader_org_picker_open  = false;
				loader_org_picker_node  = noone;
				loader_org_picker_hover = -1;
			}
		}
	}

	// MACRO_LOADER — FILE picker (pick which linked asset inside the LOAD_ORG)
	if (loader_file_picker_open) {
		if (!instance_exists(loader_file_picker_node)) {
			loader_file_picker_open  = false;
			loader_file_picker_node  = noone;
			loader_file_picker_hover = -1;
		} else {
			var _lfp_org_name = (array_length(loader_file_picker_node.instructions[0]) > 1)
			                  ? string(loader_file_picker_node.instructions[0][1]) : "";
			var _lfp_matches = [];
			if (_lfp_org_name != "") {
				for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
					var _a = ds_list_find_value(asset_list, _i);
					if (_a.type == "LOAD_ORG" && _a.name == _lfp_org_name) {
						if (variable_struct_exists(_a, "linked_assets")) {
							var _lks = _a.linked_assets;
							for (var _lki = 0; _lki < array_length(_lks); _lki++) {
								array_push(_lfp_matches, _lks[_lki]);
							}
						}
						break;
					}
				}
			}
			loader_file_picker_hover = -1;
			var _drop_x = loader_file_picker_node.x + 68;
			var _drop_y = loader_file_picker_node.y + 48;
			for (var _i = 0; _i < array_length(_lfp_matches); _i++) {
				var _ry = _drop_y + (_i * 16);
				if (point_in_rectangle(mouse_x, mouse_y, _drop_x, _ry, _drop_x + 180, _ry + 16)) {
					loader_file_picker_hover = _i;
					break;
				}
			}
			if (mouse_check_button_pressed(mb_left)) {
				if (loader_file_picker_hover >= 0) {
					var _picked = _lfp_matches[loader_file_picker_hover];
					while (array_length(loader_file_picker_node.instructions[0]) <= 3) {
						array_push(loader_file_picker_node.instructions[0], "");
					}
					loader_file_picker_node.instructions[0][2] = _picked.asset_name;
					scr_c64_update_addresses();
				}
				loader_file_picker_open  = false;
				loader_file_picker_node  = noone;
				loader_file_picker_hover = -1;
			}
			if (mouse_check_button_pressed(mb_right) || keyboard_check_pressed(vk_escape)) {
				loader_file_picker_open  = false;
				loader_file_picker_node  = noone;
				loader_file_picker_hover = -1;
			}
		}
	}

	// LOAD_ORG ASSET PICKER
	
	if (load_org_picker_open) {
    var _lpw  = 220;
    var _lih  = 20;
    var _lpx  = _vx1 + 10;
    var _lpy  = _vy1 + 200;

    // Build list of all non-LOAD_ORG assets not already linked
    var _lo_matches = [];
    if (load_org_picker_asset >= 0 && load_org_picker_asset < ds_list_size(asset_list)) {
        var _lo_asset = ds_list_find_value(asset_list, load_org_picker_asset);
        var _lo_links = variable_struct_exists(_lo_asset, "linked_assets") ? _lo_asset.linked_assets : [];
        for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
            var _a = ds_list_find_value(asset_list, _i);
            if (_a.type == "LOAD_ORG") continue;
            // Check not already linked
            var _already = false;
            for (var _li = 0; _li < array_length(_lo_links); _li++) {
                if (_lo_links[_li].asset_name == _a.name) { _already = true; break; }
            }
            if (!_already) array_push(_lo_matches, _a);
        }
    }

    load_org_picker_hover = -1;
    for (var _i = 0; _i < array_length(_lo_matches); _i++) {
        var _iy = _lpy + 20 + (_i * _lih);
        if (point_in_rectangle(_mx, _my, _lpx, _iy, _lpx + _lpw, _iy + _lih)) {
            load_org_picker_hover = _i; break;
        }
    }

    if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
        if (load_org_picker_hover >= 0 &&
            load_org_picker_asset >= 0 &&
            load_org_picker_asset < ds_list_size(asset_list)) {
            var _lo_a    = ds_list_find_value(asset_list, load_org_picker_asset);
            var _picked  = _lo_matches[load_org_picker_hover];
            var _new_link = {
                asset_name   : _picked.name,
                d64_filename : string_upper(string_copy(_picked.name, 1, 16)),
                load_later   : false,
            };
            if (!variable_struct_exists(_lo_a, "linked_assets")) _lo_a.linked_assets = [];
            array_push(_lo_a.linked_assets, _new_link);
        }
        load_org_picker_open  = false;
        load_org_picker_asset = -1;
        load_org_picker_hover = -1;
        exit;
    }
    if (mouse_check_button_pressed(mb_right)) {
        load_org_picker_open  = false;
        load_org_picker_asset = -1;
        load_org_picker_hover = -1;
    }
    exit;
}

// -------------------------------------------------------
// META TILESET CHARSET PICKER
// -------------------------------------------------------
if (meta_ts_picker_open) {
    var _tspw  = 180;
    var _tsih  = 20;
    var _tspx  = _vx1 + 74;
    var _tspy  = meta_ts_btn_y + 14;
    var _ts_matches = [];
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _a = ds_list_find_value(asset_list, _i);
        if (_a.type == "CHAR_SET") array_push(_ts_matches, _a);
    }
    var _ts_total_h = max(1, array_length(_ts_matches)) * _tsih + 4;

    meta_ts_picker_hover = -1;
    for (var _i = 0; _i < array_length(_ts_matches); _i++) {
        var _iy = _tspy + 2 + (_i * _tsih);
        if (point_in_rectangle(_mx, _my, _tspx, _iy, _tspx + _tspw, _iy + _tsih)) {
            meta_ts_picker_hover = _i;
            break;
        }
    }

    if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
        if (meta_ts_picker_hover >= 0 &&
            viewer_asset >= 0 &&
            viewer_asset < ds_list_size(asset_list)) {
            var _ta = ds_list_find_value(asset_list, viewer_asset);
            if (_ta.type == "META_TILESET") {
                _ta.meta.chr_asset = _ts_matches[meta_ts_picker_hover].name;
            }
        }
        meta_ts_picker_open  = false;
        meta_ts_picker_hover = -1;
        exit;
    }

    if (mouse_check_button_pressed(mb_right) ||
        (mouse_check_button_pressed(mb_left) &&
         !point_in_rectangle(_mx, _my, _tspx, _tspy, _tspx + _tspw, _tspy + _ts_total_h))) {
        meta_ts_picker_open  = false;
        meta_ts_picker_hover = -1;
    }
    exit;
}


// -------------------------------------------------------
// MAP VIEWER CHARSET PICKER
// — runs every frame while open, updates hover, handles clicks
// -------------------------------------------------------
if (map_chr_picker_open) {
    var _mcpw       = 180;
    var _mcih       = 20;
    var _mcpx       = _vx1 + 274;
    var _mcpy       = map_chr_picker_draw_y;
    var _mc_matches = [];
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _a = ds_list_find_value(asset_list, _i);
        if (_a.type == "CHAR_SET") {
            array_push(_mc_matches, _a);
        }
    }

    map_chr_picker_hover = -1;
    for (var _i = 0; _i < array_length(_mc_matches); _i++) {
        var _iy = _mcpy + 2 + (_i * _mcih);
        if (point_in_rectangle(_mx, _my, _mcpx, _iy, _mcpx + _mcpw, _iy + _mcih)) {
            map_chr_picker_hover = _i;
            break;
        }
    }

    if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
        if (map_chr_picker_hover >= 0 &&
            map_chr_picker_asset >= 0 &&
            map_chr_picker_asset < ds_list_size(asset_list)) {
            var _ma = ds_list_find_value(asset_list, map_chr_picker_asset);
            if (variable_struct_exists(_ma, "meta")) {
                _ma.meta.chr_asset = _mc_matches[map_chr_picker_hover].name;
                if (!variable_struct_exists(_ma.meta, "fill_mode")) {
                    _ma.meta.fill_mode = false;
                }
            }
        }
        map_chr_picker_open  = false;
        map_chr_picker_asset = -1;
        map_chr_picker_hover = -1;
        keyboard_string      = "";
        exit;
    }

    if (mouse_check_button_pressed(mb_right)) {
        map_chr_picker_open  = false;
        map_chr_picker_asset = -1;
        map_chr_picker_hover = -1;
    }

    exit;
}

// -------------------------------------------------------
// MAP PICKER (node-linked)
// -------------------------------------------------------
if (map_picker_open) {
    if (!instance_exists(map_picker_node)) { map_picker_open = false; }
    else {
        var _cam_x    = obj_workspace_manager.cam_x;
        var _cam_y    = obj_workspace_manager.cam_y;
        var _cam_zoom = obj_workspace_manager.cam_zoom;
        var _node     = map_picker_node;
        var _px       = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
        var _py       = ((_node.y + 24)              - _cam_y) / _cam_zoom;
        var _pw       = 180;
        var _ih       = 20;
        var _matches  = [];
        for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
            var _a = ds_list_find_value(asset_list, _i);
            if (_a.type == "MAP_DATA") array_push(_matches, _a);
        }
        var _total_h = max(1, array_length(_matches)) * _ih + 4;
        map_picker_hover = -1;
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy = _py + 2 + (_i * _ih);
            if (point_in_rectangle(_mx, _my, _px, _iy, _px + _pw, _iy + _ih)) {
                map_picker_hover = _i; break;
            }
        }
        if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
            if (map_picker_hover >= 0) {
                _node.instructions[0][1] = _matches[map_picker_hover].name;
                scr_macro_map_sync(_node);
            }
            map_picker_open = false; map_picker_node = noone; map_picker_hover = -1;
            exit;
        }
        if (mouse_check_button_pressed(mb_right) ||
            (mouse_check_button_pressed(mb_left) &&
             !point_in_rectangle(_mx, _my, _px, _py, _px + _pw, _py + _total_h))) {
            map_picker_open = false; map_picker_node = noone; map_picker_hover = -1;
        }
    }
    exit;
}

// -------------------------------------------------------
// METAMAP PICKER (node-linked) — lists META_TILESET assets
// -------------------------------------------------------
if (metamap_picker_open) {
    if (!instance_exists(metamap_picker_node)) { metamap_picker_open = false; }
    else {
        var _cam_x    = obj_workspace_manager.cam_x;
        var _cam_y    = obj_workspace_manager.cam_y;
        var _cam_zoom = obj_workspace_manager.cam_zoom;
        var _node     = metamap_picker_node;
        var _px       = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
        var _py       = ((_node.y + 24)              - _cam_y) / _cam_zoom;
        var _pw       = 180;
        var _ih       = 20;
        var _matches  = [];
        for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
            var _a = ds_list_find_value(asset_list, _i);
            if (_a.type == "META_TILESET") array_push(_matches, _a);
        }
        var _total_h = max(1, array_length(_matches)) * _ih + 4;
        metamap_picker_hover = -1;
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy = _py + 2 + (_i * _ih);
            if (point_in_rectangle(_mx, _my, _px, _iy, _px + _pw, _iy + _ih)) {
                metamap_picker_hover = _i; break;
            }
        }
        if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
            if (metamap_picker_hover >= 0) {
                _node.instructions[0][1] = _matches[metamap_picker_hover].name;
                _node.instructions[0][2] = 0; // reset map index when tileset changes
                global.addresses_dirty = true;
            }
            metamap_picker_open = false; metamap_picker_node = noone; metamap_picker_hover = -1;
            exit;
        }
        if (mouse_check_button_pressed(mb_right) ||
            (mouse_check_button_pressed(mb_left) &&
             !point_in_rectangle(_mx, _my, _px, _py, _px + _pw, _py + _total_h))) {
            metamap_picker_open = false; metamap_picker_node = noone; metamap_picker_hover = -1;
        }
    }
    exit;
}

// -------------------------------------------------------
// BITMAP_BUILDER SRC/DST PICKER
// -------------------------------------------------------
// Lists every BITMAP asset. Commits into the open builder's meta.src_asset or
// meta.dst_asset, then forces a preview rebuild.
if (bbuild_picker_open) {
    var _bbp_w   = 180;
    var _bbp_ih  = 18;
    var _bbp_x   = bbuild_picker_x;
    var _bbp_y   = bbuild_picker_y;

    var _bbp_matches = [];
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _a = ds_list_find_value(asset_list, _i);
        if (_a.type == "BITMAP") array_push(_bbp_matches, _a);
    }
    var _bbp_total_h = max(1, array_length(_bbp_matches)) * _bbp_ih + 4;

    bbuild_picker_hover = -1;
    for (var _i = 0; _i < array_length(_bbp_matches); _i++) {
        var _iy = _bbp_y + 2 + (_i * _bbp_ih);
        if (point_in_rectangle(_mx, _my, _bbp_x, _iy, _bbp_x + _bbp_w, _iy + _bbp_ih)) {
            bbuild_picker_hover = _i;
            break;
        }
    }

    if (mouse_check_button_pressed(mb_left)) {
        if (bbuild_picker_hover >= 0 &&
            viewer_asset >= 0 &&
            viewer_asset < ds_list_size(asset_list)) {
            var _bba = ds_list_find_value(asset_list, viewer_asset);
            if (_bba.type == "BITMAP_BUILDER") {
                if (bbuild_picker_field == "SRC") {
                    _bba.meta.src_asset = _bbp_matches[bbuild_picker_hover].name;
                } else {
                    _bba.meta.dst_asset = _bbp_matches[bbuild_picker_hover].name;
                }
                _bba.meta.prev_dirty = true;
                _bba.meta.is_dirty   = true;
            }
        }
        bbuild_picker_open  = false;
        bbuild_picker_hover = -1;
        exit;
    }

    if (mouse_check_button_pressed(mb_right) || keyboard_check_pressed(vk_escape)) {
        bbuild_picker_open  = false;
        bbuild_picker_hover = -1;
        keyboard_clear(vk_escape);
    }
    exit;
}

// -------------------------------------------------------
// BITMAP PICKER
// -------------------------------------------------------
if (bmp_picker_open) {
    if (!instance_exists(bmp_picker_node)) { bmp_picker_open = false; }
    else {
        var _cam_x    = obj_workspace_manager.cam_x;
        var _cam_y    = obj_workspace_manager.cam_y;
        var _cam_zoom = obj_workspace_manager.cam_zoom;
        var _node     = bmp_picker_node;
        var _px       = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
        var _py       = ((_node.y + 24)              - _cam_y) / _cam_zoom;
        var _pw       = 180;
        var _ih       = 20;
        var _matches  = [];
        for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
            var _a = ds_list_find_value(asset_list, _i);
            if (_a.type == "BITMAP") array_push(_matches, _a);
        }
        var _total_h = max(1, array_length(_matches)) * _ih + 4;
        bmp_picker_hover = -1;
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy = _py + 2 + (_i * _ih);
            if (point_in_rectangle(_mx, _my, _px, _iy, _px + _pw, _iy + _ih)) {
                bmp_picker_hover = _i; break;
            }
        }
        if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
            if (bmp_picker_hover >= 0)
                _node.instructions[0][1] = _matches[bmp_picker_hover].name;
            bmp_picker_open = false; bmp_picker_node = noone; bmp_picker_hover = -1;
            exit;
        }
        if (mouse_check_button_pressed(mb_right) ||
            (mouse_check_button_pressed(mb_left) &&
             !point_in_rectangle(_mx, _my, _px, _py, _px + _pw, _py + _total_h))) {
            bmp_picker_open = false; bmp_picker_node = noone; bmp_picker_hover = -1;
        }
    }
    exit;
}

// -------------------------------------------------------
// LMB CLICKS
// -------------------------------------------------------
global.ui_click_block_timer = 0;
global.ui_click_consumed    = false;
if (mouse_check_button_pressed(mb_left) && !global.any_picker_open) {

// Close dropdown if clicking outside
    if (add_dropdown_open) {
        if (add_dropdown_hover >= 0) {
            var _type      = asset_types[add_dropdown_hover];
            // Default name is the type string, but BITMAP_BUILDER gets a short
            // stem — the generated BYTE_DATA table is named BBDSolid_<builder>,
            // and "BBDSolid_BITMAP_BUILDER" is unwieldy. "BBDSolid_BMPBDR" is
            // not. Still fully user-editable afterwards.
            var _base_name = _type;
            if (_type == "BITMAP_BUILDER") {
                _base_name = "BMPBDR";
            }
            if (_type == "MUSIC_MAKER") {
                _base_name = "MUSIC_";
            }
            var _proposed  = _base_name;
            var _suffix    = 2;
            var _dup       = true;
            while (_dup) {
                _dup = false;
                for (var _di = 0; _di < ds_list_size(asset_list); _di++) {
                    if (ds_list_find_value(asset_list, _di).name == _proposed) {
                        _proposed = _base_name + "_" + string(_suffix);
                        _suffix++;
                        _dup = true;
                        break;
                    }
                }
            }
			var _new_buffer = buffer_create(1, buffer_fixed, 1);
			var _new_meta = {};

			if (_type == "CHAR_SET") {
			    // Start with 4 rows of 16 tiles = 64 tiles (64 * 8 bytes = 512 bytes)
			    buffer_delete(_new_buffer);
			    _new_buffer = buffer_create(512, buffer_fixed, 1);
			    buffer_fill(_new_buffer, 0, buffer_u8, 0, 512);
			    _new_meta = {
			        format      : "binary",
			        char_count  : 64,
			        total_size  : 512,
			        preview_surf: -1,
			        mc_mode     : 0,
			        mc_fg       : 1,
			        mc_bg       : 0,
			        mc_col1     : 1,
			        mc_col2     : 2,
			        undo_stack  : [],
			        redo_stack  : []
			    };
			}

			if (_type == "BITMAP") {
			    // Editable KLA/bitmap paint asset. Seed the full editor meta here so
			    // the Draw-event paint routines never read an uninitialised field
			    // (undo_stack in particular is read by the F11 surface-restore block
			    // on the very first frame).
			    _new_meta = {
			        format        : "koala",
			        preview_surf  : -1,
			        pixel_backup  : -1,
			        pixels_dirty  : false,
			        bg_col        : 0,
			        bg_mask       : array_create(64000, 0),
			        clash_grid    : array_create(1000, false),
			        auto_clean    : true,
			        is_editing    : false,
			        needs_mask_init : false,
			        active_color  : 1,
			        active_tool   : "DRAW",
			        dither_mode   : "NONE",
			        dither_invert : false,
			        brush_size    : 0,
			        bmp_pan_x     : 0,
			        bmp_pan_y     : 0,
			        last_px       : undefined,
			        last_py       : undefined,
			        undo_stack    : [],
			        redo_stack    : [],
			        undo_pending  : false,
			        tone_sorted   : false
			    };
			}

			var _new_asset = {
			    type          : _type,
			    name          : _proposed,
			    file          : "",
			    address       : scr_asset_default_address(_type),
			    buffer        : _new_buffer,
			    meta          : _new_meta,
			    load_later    : false,
			    d64_filename  : (_type == "LOAD_ORG") ? string_upper(_proposed) : "",
			    linked_assets : (_type == "LOAD_ORG") ? [] : [],
			};
			if (_type == "SPRITE_SET") {
			    // Fresh sprite asset starts with a single blank sprite.
			    // 64 bytes = one C64 sprite block, zeroed. Arrays sized to 1;
			    // the "+" cell in the picker grows this up to 64.
			    if (buffer_exists(_new_asset.buffer)) buffer_delete(_new_asset.buffer);
			    _new_asset.buffer = buffer_create(64, buffer_fixed, 1);
			    buffer_fill(_new_asset.buffer, 0, buffer_u8, 0, 64);
			    _new_asset.meta = {
			        format      : "binary",
			        has_colour  : true,
			        bg_col      : 0,
			        mc1_col     : 1,
			        mc2_col     : 2,
			        sprite_mcs  : array_create(1, 0),
			        sprite_ucs  : array_create(1, 1),
			        spr_sprites : array_create(1, -1),
			        found_count : 1,
			        used_count  : 1,
			        total_size  : 64
			    };
			    scr_asset_spr_cache_sprites(_new_asset, true);

			    var _bmp_connected = false;
			    with (obj_c64_node) {
			        if (node_type == "MACRO_BMP" && is_connected) {
			            _bmp_connected = true;
			        }
			    }
			    if (_bmp_connected) {
			        _new_asset.address = 0x6800;
			    }
			}
			if (_type == "TEXT_DATA") {
                _new_asset.meta.text              = "HELLO WORLD ";
				_new_asset.meta.inline_edit_open      = false;
				_new_asset.meta.inline_edit_text      = _new_asset.meta.text;
				_new_asset.meta.inline_edit_cursor    = 0;
				_new_asset.meta.inline_edit_scroll_y  = 0;
				_new_asset.meta.inline_edit_sel_start = -1;
				_new_asset.meta.inline_edit_sel_end   = -1;
				_new_asset.meta.inline_edit_blink     = 0;
				_new_asset.meta.inline_edit_key_timer = 0;
                scr_asset_text_flush(_new_asset);
            }
           if (_type == "BYTE_DATA") {
                _new_asset.meta.byte_string           = "$00, $01, $02";
				_new_asset.meta.inline_edit_open      = false;
				_new_asset.meta.inline_edit_text      = _new_asset.meta.byte_string;
				_new_asset.meta.inline_edit_cursor    = 0;
				_new_asset.meta.inline_edit_scroll_y  = 0;
				_new_asset.meta.inline_edit_sel_start = -1;
				_new_asset.meta.inline_edit_sel_end   = -1;
				_new_asset.meta.inline_edit_blink     = 0;
				_new_asset.meta.inline_edit_key_timer = 0;
				_new_asset.meta.is_save_file           = false;
				_new_asset.meta.save_file_size          = 256;
                scr_asset_byte_data_flush(_new_asset);
            }
        if (_type == "MAP_DATA") {
            _new_asset.meta = {
                map_w             : 40,
                map_h             : 25,
                grid_w            : 40,
                grid_h            : 25,
                char_grid         : array_create(40 * 25, 0),
                colour_grid       : array_create(40 * 25, 1),
                override_grid     : array_create(40 * 25, 0),
                chr_asset         : "",
                scroll_x          : 0,
                scroll_y          : 0,
                zoom              : 2,
                active_char       : 0,
                active_colour     : 1,
                tool              : "CHAR",
                char_strip_offset : 0,
                preview_surf      : -1,
                mc_mode           : 2,
                paint_mc          : 0,
                map_mc_bg         : -1,
                map_mc_col1       : -1,
                map_mc_col2       : -1,
                stamp_data        : [],
                stamp_active      : false,
                sel_grid          : array_create(40 * 25, 0),
                map_undo_stack    : [],
                map_redo_stack    : []
            };
        }
        if (_type == "META_TILESET") {
            scr_asset_meta_tileset_create(_new_asset);
        }
        if (_type == "BITMAP_BUILDER") {
            // Authoring asset — no C64 payload of its own.
            if (buffer_exists(_new_asset.buffer)) buffer_delete(_new_asset.buffer);
            _new_asset.buffer = buffer_create(1, buffer_fixed, 1);
            scr_bitmap_builder_create(_new_asset);
        }
        if (_type == "MUSIC_MAKER") {
            // Authoring asset — no C64 payload of its own, same family as
            // BITMAP_BUILDER. GENERATE emits the real BYTE_DATA/TEXT_DATA
            // assets (instruments + per-voice patterns) that SEQ VOICE nodes
            // consume.
            if (buffer_exists(_new_asset.buffer)) buffer_delete(_new_asset.buffer);
            _new_asset.buffer = buffer_create(1, buffer_fixed, 1);
            scr_sound_editor_create(_new_asset);
        }
        if (_type == "META_MAP") {
            scr_asset_meta_map_create(_new_asset);
        }
        if (_type == "VECTOR_BITMAP") {
            // No buffer — the picture is a replayable command list, not pixels.
            // commands[] is an ordered array of primitive structs (see compile case).
            // Coords are hi-res pixel space (x 0-319, y 0-199) regardless of mode;
            // the C64 plot routine folds x for MC. SETCOL values are MC source
            // selectors 0-3 (00 bg / 01 scr-hi / 10 scr-lo / 11 col-RAM).
            if (buffer_exists(_new_asset.buffer)) buffer_delete(_new_asset.buffer);
            _new_asset.buffer = -1; // no binary payload; bytes emitted by MACRO_VECTOR_BMP via org
            _new_asset.meta = {
                mode          : 1,        // 0 = HR, 1 = MC (default MC)
                bg            : 0,        // selector 0 → $D021 background colour
                col1          : 1,        // selector 1 → screen-RAM upper nibble (white)
                col2          : 2,        // selector 2 → screen-RAM lower nibble (red)
                col3          : 3,        // selector 3 → colour RAM (cyan)
                fill_stack    : 0xC000,   // flood-fill RAM stack base on C64
                stream_addr   : 0xC800,   // where the command byte-stream lands in the PRG (safe RAM)
                commands      : [],       // ordered primitive structs (PAGE 0's list — mirror of pages[0].commands)
                // ── MULTI-PAGE ── pages[] is the source of truth. Page 0's
                // commands/bg/col1/col2/col3 are ALSO kept in the top-level
                // fields above for backward-compat with single-page code paths.
                // The editor edits pages[active_page]; on switch it syncs the
                // active page's fields up to top-level. See scr_vbmp_page_*.
                pages         : [ { commands: [], bg: 0, col1: 1, col2: 2, col3: 3 } ],
                active_page   : 0,        // which page the inline editor is editing
                // editor preview state (built lazily by the editor, never serialised as pixels)
                preview_surf  : -1,
                active_col    : 1,        // current selector for new ops
                active_pat    : 0,        // current dither pattern index
                tool          : "LINE",   // editor active tool
                draw_x1       : -1,
                draw_y1       : -1,
                zoom          : 2,
                vbmp_undo_stack : [],
                vbmp_redo_stack : [],
                // KLA-compat fields so the shared scr_asset_bmp_draw_* routines
                // run against this asset without crashing. Editor-only, not serialised.
                bg_mask       : array_create(64000, 0),
                dither_mode   : "NONE",
                dither_invert : false,
                brush_size    : 0
            };
        }
			ds_list_add(asset_list, _new_asset);
            global.undo_dirty = true;
            with (obj_workspace_manager) { alarm[3] = 6; }
        }
        add_dropdown_open = false;
        exit;
    }

    // ADD ASSET button
    if (point_in_rectangle(_mx, _my, panel_x + 4, panel_y + 4, panel_x + panel_w - 4, panel_y + 26)) {
        add_dropdown_open = !add_dropdown_open;
        exit;
    }

    // -------------------------------------------------------
    // VIEWER BUTTONS
    // -------------------------------------------------------
    if (viewer_open && viewer_asset >= 0 && viewer_asset < ds_list_size(asset_list)) {
        var _asset = ds_list_find_value(asset_list, viewer_asset);

        // Close button
        if (point_in_rectangle(_mx, _my, _vx2 - 80, _vy1 + 4, _vx2 - 4, _vy1 + 24)) {
            if (spred64_v2.active) scr_spred64_v2_close(true);
			scr_asset_inline_editor_close_all()
            viewer_open              = false;
            viewer_asset             = -1;
            spred64_open             = false;
            spr_edit_path            = "";
            spr_edit_md5             = "";
            editorClosed             = 1;
            alarm[0]                 = 65;
            global.was_editor_open   = true;
            alarm[2]                 = 60;
            exit;
        }

// CHARSET viewer interactions
if (_asset.type == "CHAR_SET") {
    // ---- TILE SELECT from preview grid ----
    // Use coordinates stored by Draw GUI this frame.
    // Three interaction modes:
    //   1. Plain click on a tile = make it the edit target, clear selection.
    //   2. Ctrl+click = toggle individual tile in/out of multi-selection.
    //   3. Ctrl+drag = paint tiles into the multi-selection as the mouse
    //      passes over them. The drag tracks `chr_drag_last_idx` so each
    //      tile is only toggled once per stroke (no flicker on re-entry).
    var _chr_ecm_now    = variable_struct_exists(_asset.meta, "mc_mode") && (_asset.meta.mc_mode == 2);
    var _chr_real_rows  = ceil(_asset.meta.char_count / 16);
    var _chr_ecm_rows   = min(_chr_real_rows, 4); // ECM hard cap: 4 rows = 64 chars
    var _chr_grid_rows  = _chr_ecm_now ? (_chr_ecm_rows * 4) : _chr_real_rows;
    if (chr_grid_cell_px > 0 &&
        point_in_rectangle(_mx, _my, chr_grid_draw_x, chr_grid_draw_y,
                           chr_grid_draw_x + 16 * chr_grid_cell_px,
                           chr_grid_draw_y + _chr_grid_rows * chr_grid_cell_px)) {
        var _tx = floor((_mx - chr_grid_draw_x) / chr_grid_cell_px);
        var _ty = floor((_my - chr_grid_draw_y) / chr_grid_cell_px);
        var _hover_idx = -1;
        if (_tx >= 0 && _tx < 16 && _ty >= 0) {
            // ECM: band = which real-row-block was clicked; real char comes
            // from the row WITHIN that band (capped to the 64-char window),
            // not from the flat index.
            var _real_row  = _chr_ecm_now ? (_ty mod _chr_ecm_rows) : _ty;
            _hover_idx = (_tx + (_real_row * 16));
        }

        // --- Initial press ---
        if (mouse_check_button_pressed(mb_left) && _hover_idx >= 0 && _hover_idx < _asset.meta.char_count) {
            // Only treat as Ctrl+click select if Ctrl is held WITHOUT any of the
            // copy/paste/deselect shortcut keys also down. Otherwise Ctrl+V will
            // both paste AND toggle the hovered tile into the selection.
            var _ctrl_alone = scr_ctrl_held()
                            && !keyboard_check(ord("C"))
                            && !keyboard_check(ord("V"))
                            && !keyboard_check(ord("X"))
                            && !keyboard_check(ord("Z"))
                            && !keyboard_check(ord("Y"))
                            && !keyboard_check(ord("D"))
                            && !keyboard_check(ord("A"));
            if (_ctrl_alone) {
                // Ctrl+click — toggle this tile, start drag-paint stroke
                var _ms_found = -1;
                for (var _msi = 0; _msi < array_length(chr_multi_select); _msi++) {
                    if (chr_multi_select[_msi] == _hover_idx) {
                        _ms_found = _msi;
                        break;
                    }
                }
                if (_ms_found >= 0) {
                    array_delete(chr_multi_select, _ms_found, 1);
                    chr_drag_mode = "remove";
                } else {
                    array_push(chr_multi_select, _hover_idx);
                    chr_drag_mode = "add";
                }
                chr_paste_anchor   = _hover_idx;
                chr_drag_active    = true;
                chr_drag_last_idx  = _hover_idx;
            } else {
                // Plain click — change edit target, clear selection, set anchor
                chr_edit_idx       = _hover_idx;
                chr_multi_select   = [];
                chr_paste_anchor   = _hover_idx;
                chr_drag_active    = false;
                chr_drag_last_idx  = -1;
            }
        }

        }
    // Drag continuation and end-of-stroke are handled in the frame-level
    // CHAR_SET handler near the top of Step — they need to run every frame,
    // not just on mouse press, so the held-button motion can paint tiles.

    // ---- ADD TILE button ----
    var _atbx1 = _vx1 + 120;
    var _atbx2 = _atbx1 + 100;
    var _atby1 = _vy1 + 38;
    var _atby2 = _vy1 + 58;
    if (mouse_check_button_pressed(mb_left) &&
        point_in_rectangle(_mx, _my, _atbx1, _atby1, _atbx2, _atby2)) {
        if (_asset.meta.char_count >= 256) {
            exit;
        }
        var _old_sz = buffer_get_size(_asset.buffer);
        var _new_sz = _old_sz + 128; // 16 tiles * 8 bytes
        var _temp_buf = buffer_create(_new_sz, buffer_fixed, 1);
        buffer_copy(_asset.buffer, 0, _old_sz, _temp_buf, 0);
        buffer_fill(_temp_buf, _old_sz, buffer_u8, 0, 128);
        buffer_delete(_asset.buffer);
        _asset.buffer = _temp_buf;
        _asset.meta.char_count = min(_asset.meta.char_count + 16, 256);
        _asset.meta.total_size = _asset.meta.char_count * 8;
        scr_asset_chr_build_preview(_asset);
        with (obj_c64_node) {
            if ((node_type == "MACRO_MAP" || node_type == "MACRO_CHR") &&
                instructions[0][1] == _asset.name) {
                if (node_type == "MACRO_CHR") scr_macro_chr_sync(id);
            }
        }
        global.undo_dirty = true;
        exit;
    }

}

// BITMAP_BUILDER — all viewer interaction lives in scr_bitmap_builder_editor
// (Draw GUI). Swallow the click here so it can't fall through to the generic
// IMPORT / ADDRESS handlers below, which would try to import a file into an
// asset that has no file.
if (_asset.type == "BITMAP_BUILDER") {
    exit;
}

// SOUND_EDITOR — same reasoning: all interaction lives in
// scr_sound_editor_editor (Draw GUI). No file, nothing to import.
if (_asset.type == "MUSIC_MAKER") {
    exit;
}

if (_asset.type == "META_TILESET") {
            var _tscpx1 = _vx1 + 74;
            var _tscpx2 = _tscpx1 + 130;
            var _tscpy1 = meta_ts_btn_y;
            var _tscpy2 = _tscpy1 + 14;
            if (point_in_rectangle(_mx, _my, _tscpx1, _tscpy1, _tscpx2, _tscpy2)) {
                meta_ts_picker_open  = true;
                meta_ts_picker_hover = -1;
                exit;
            }
            exit;
        }

// CHARSET PICKER + UNDOCK TILE EDITOR buttons (MAP_DATA viewer only)

        if (_asset.type == "MAP_DATA" &&
            variable_struct_exists(_asset, "meta") &&
            variable_struct_exists(_asset.meta, "char_grid")) {
            var _cpbx1 = _vx1 + 268;
            var _cpbx2 = _cpbx1 + 140;
            var _cpby1 = map_chr_btn_y;
            var _cpby2 = _cpby1 + 14;
			show_debug_message("btn y=" + string(_cpby1) + " my=" + string(_my));
            if (point_in_rectangle(_mx, _my, _cpbx1, _cpby1, _cpbx2, _cpby2)) {
                map_chr_picker_open   = true;
                map_chr_picker_asset  = viewer_asset;
                map_chr_picker_draw_y = _cpby2 + 2;
                exit;
            }
        }
        // EDIT SPRITES button (SPRITE_SET only) — opens the V2 built-in editor.
        if (_asset.type == "SPRITE_SET") {
            var _v2bx1 = _vx1 + 10;
            var _v2bx2 = _v2bx1 + 150;
            var _v2by1 = spred64_v2_btn_y;
            var _v2by2 = _v2by1 + 22;
            if (point_in_rectangle(_mx, _my, _v2bx1, _v2by1, _v2bx2, _v2by2)) {
                if (spred64_v2.active && spred64_v2.asset_index == viewer_asset) {
                    // Close — commit working state back to asset
                    scr_spred64_v2_close(true);
                } else {
                    // Open V2 on the current SPRITE_SET asset
                    scr_spred64_v2_open(viewer_asset);
                }
                exit;
            }
        }



        // LOAD_ORG viewer clicks
        if (_asset.type == "LOAD_ORG") {
            var _links = variable_struct_exists(_asset, "linked_assets") ? _asset.linked_assets : [];
            var _lo_cy = _vy1 + 38 + 20 + 18 + 14 + 14;
            _lo_cy += 20;
            _lo_cy += 18;
            for (var _li = 0; _li < array_length(_links); _li++) {
                var _link = _links[_li];
                if (point_in_rectangle(_mx, _my, _vx2 - 26, _lo_cy + 2, _vx2 - 8, _lo_cy + 18)) {
                    array_delete(_links, _li, 1);
                    exit;
                }
                _lo_cy += 22;
            }
            if (point_in_rectangle(_mx, _my, _vx1 + 10, _lo_cy, _vx1 + 80, _lo_cy + 40)) {
                load_org_picker_open  = true;
                load_org_picker_asset = viewer_asset;
                load_org_picker_hover = -1;
                exit;
            }
            exit;
        }

        // LOAD FILE / IMPORT button — suppressed for SPRITE_SET while V2 is
        // active on this asset. Importing through V2 overwrites the asset's
        // meta (compositor, anim, palette) while V2 holds stale working
        // clones, leading to data loss on the user's next action. The user
        // must close V2 first if they want to re-import.
        var _lbx1 = _vx1 + 10;
        var _lbx2 = _vx1 + 110;
        var _lby1 = _vy1 + 38;
        var _lby2 = _vy1 + 58;
        var _v2_blocking_import = (_asset.type == "SPRITE_SET"
                                && spred64_v2.active
                                && spred64_v2.asset_index == viewer_asset);
        if (!_v2_blocking_import
        &&  point_in_rectangle(_mx, _my, _lbx1, _lby1, _lbx2, _lby2)) {
            switch (_asset.type) {
                case "SPRITE_SET":
                    scr_asset_spr_import(_asset);
                    scr_asset_spr_cache_sprites(_asset);
                    break;
                case "BITMAP":     scr_asset_kla_import(_asset); break;
                case "SID_MUSIC":  scr_asset_sid_import(_asset); break;
                case "SFX_DATA":   scr_asset_sfx_data_import(_asset); break;
                case "CHAR_SET":   scr_asset_chr_import(_asset); break;
                case "MAP_DATA":      scr_asset_map_import(_asset);           break;
				case "META_TILESET":  scr_asset_meta_tileset_create(_asset);  break;
				case "META_MAP":      scr_asset_meta_map_create(_asset);      break;
                case "TEXT_DATA":  scr_asset_txt_import(_asset); break;
                case "BYTE_DATA":  scr_asset_byte_import_as_text(_asset); break;
            }
            exit;
        }

        // ADDRESS click in viewer — LOAD_ORG is a manifest, BITMAP_BUILDER is an
        // internal authoring asset. Neither has an editable load address.
        if (_asset.type != "LOAD_ORG" && _asset.type != "BITMAP_BUILDER" && _asset.type != "MUSIC_MAKER" && 
            point_in_rectangle(_mx, _my, _vx1 + 74, _vy1 + 65, _vx1 + 162, _vy1 + 79)) {
            editing_address     = true;
            editing_address_idx = viewer_asset;
            editing_addr_string = string_upper(decimal_to_hex(_asset.address));
            while (string_length(editing_addr_string) < 4)
                editing_addr_string = "0" + editing_addr_string;
            exit;
        }


        exit; // swallow all other viewer clicks
    }

    // -------------------------------------------------------
    // ASSET LIST CLICKS
    // -------------------------------------------------------
    if (_mouse_in_panel && hover_idx >= 0) {
        var _asset  = ds_list_find_value(asset_list, hover_idx);
        var _list_y = panel_y + 66;
        var _iy     = _list_y + (hover_pos * item_h) - panel_scroll;
        var _addr_x = _panel_right - 58;
        var _edit_x = _addr_x - 30;

        if (_asset.type == "SPRITE_SET" && _asset.file != "")
            scr_asset_spr_cache_sprites(_asset);

        if (_asset.type != "LOAD_ORG" && _asset.type != "BITMAP_BUILDER" && _asset.type != "MUSIC_MAKER" && 
            point_in_rectangle(_mx, _my, _addr_x, _iy, _panel_right, _iy + item_h)) {
            editing_address     = true;
            editing_address_idx = hover_idx;
            editing_addr_string = string_upper(decimal_to_hex(_asset.address));
            while (string_length(editing_addr_string) < 4)
                editing_addr_string = "0" + editing_addr_string;
            exit;
        }

        if (point_in_rectangle(_mx, _my, panel_x, _iy, _edit_x, _iy + item_h)) {
            editing_name   = true;
            editing_idx    = hover_idx;
            editing_string = _asset.name;
            editing_cursor = string_length(editing_string);
            keyboard_string = "";
            exit;
        }

        if (point_in_rectangle(_mx, _my, _edit_x, _iy, _addr_x, _iy + item_h)) {
            viewer_open  = true;keyboard_string = "";
            viewer_asset = hover_idx;
            // Opening any asset straight from the list means we did NOT arrive
            // via a builder's EDIT button, so drop any stale return breadcrumb.
            bb_return_asset = -1;
            var _opened = ds_list_find_value(asset_list, hover_idx);
            // META_TILESET: default-select first stamp if one exists and nothing is selected
            if (_opened.type == "META_TILESET" &&
                variable_struct_exists(_opened.meta, "stamp_count") &&
                _opened.meta.stamp_count > 0 &&
                (!variable_struct_exists(_opened.meta, "edit_stamp") || _opened.meta.edit_stamp < 0)) {
                var _om = _opened.meta;
                _om.edit_stamp = 0;
                var _def_cells = _om.stamp_w * _om.stamp_h;
                _om.active_stamp_grid_char = array_create(_def_cells, 0);
                _om.active_stamp_grid_col  = array_create(_def_cells, 1);
                _om.active_stamp_grid_ov   = array_create(_def_cells, 0);
                for (var _dci = 0; _dci < _def_cells; _dci++) {
                    var _ddidx = _dci * 3;
                    if (_ddidx + 2 < array_length(_om.stamp_data)) {
                        _om.active_stamp_grid_char[_dci] = _om.stamp_data[_ddidx];
                        _om.active_stamp_grid_col[_dci]  = _om.stamp_data[_ddidx + 1];
                        _om.active_stamp_grid_ov[_dci]   = _om.stamp_data[_ddidx + 2];
                    }
                }
            }
            if (_opened.type == "MAP_DATA" &&
                variable_struct_exists(_opened, "meta") &&
                variable_struct_exists(_opened.meta, "char_grid")) {
                var _chr_name = variable_struct_exists(_opened.meta, "chr_asset") ? _opened.meta.chr_asset : "";
                if (_chr_name == "" && ds_list_size(asset_list) == 1) {
	                for (var _ci = 0; _ci < ds_list_size(asset_list); _ci++) {
	                    var _ca = ds_list_find_value(asset_list, _ci);
	                    if (_ca.type == "CHAR_SET") { _opened.meta.chr_asset = _ca.name; break; }
	                }
	            }
            }
            // SPRITE_SET viewer-open: ensure thumbnails are built from the
            // buffer even if no source file is present on disk. Standard
            // scr_asset_spr_cache_sprites bails when file == "" — but the
            // buffer itself is the source of truth, so rebuild from there
            // if any thumbnails are missing.
            if (_opened.type == "SPRITE_SET"
            && buffer_exists(_opened.buffer)
            && variable_struct_exists(_opened.meta, "spr_sprites")) {
                var _needs_rebuild = false;
                var _used = variable_struct_exists(_opened.meta, "used_count")
                    ? _opened.meta.used_count : 1;
                for (var _ti = 0; _ti < _used; _ti++) {
                    if (_opened.meta.spr_sprites[_ti] == -1
                    || !sprite_exists(_opened.meta.spr_sprites[_ti])) {
                        _needs_rebuild = true;
                        break;
                    }
                }
                if (_needs_rebuild) {
                    scr_spred64_v2_rebuild_thumbs_from_buffer(_opened);
                }
            }
            exit;
        }
    }

    // Close viewer if clicking outside
    if (viewer_open && !_mouse_in_viewer) {
        if (spred64_v2.active) scr_spred64_v2_close(true);
		scr_asset_inline_editor_close_all()
        viewer_open            = false;
        viewer_asset           = -1;
        global.was_editor_open = true;
        alarm[2]               = 60;
    }
}

// -------------------------------------------------------
// CHAR_SET MULTI COPY/PASTE + CTRL+DRAG-PAINT CONTINUATION
// Runs every frame so held-button motion can paint into the
// multi-selection — press-arm in the viewer-buttons block only
// fires once per click, so continuation must live here.
// -------------------------------------------------------
if (viewer_open && viewer_asset >= 0 && viewer_asset < ds_list_size(asset_list)) {
    var _chr_view_asset = ds_list_find_value(asset_list, viewer_asset);
    if (_chr_view_asset.type == "CHAR_SET") {

        // Ctrl+C / Ctrl+V / Backspace / Delete — multi-tile clipboard
        scr_chr_multi_copy_paste(_chr_view_asset);

        // Ctrl+drag continuation — paint tiles into / out of selection
        if (chr_grid_cell_px > 0 && chr_drag_active && mouse_check_button(mb_left) && scr_ctrl_held()) {
            var _tx_d = floor((_mx - chr_grid_draw_x) / chr_grid_cell_px);
            var _ty_d = floor((_my - chr_grid_draw_y) / chr_grid_cell_px);
            var _drag_ecm_now   = variable_struct_exists(_chr_view_asset.meta, "mc_mode") && (_chr_view_asset.meta.mc_mode == 2);
            var _drag_real_rows = ceil(_chr_view_asset.meta.char_count / 16);
            var _drag_ecm_rows  = min(_drag_real_rows, 4);
            var _hover_idx_d = -1;
            if (_tx_d >= 0 && _tx_d < 16 && _ty_d >= 0) {
                var _real_row_d = _drag_ecm_now ? (_ty_d mod _drag_ecm_rows) : _ty_d;
                _hover_idx_d = (_tx_d + (_real_row_d * 16));
            }
            if (_hover_idx_d >= 0
            &&  _hover_idx_d < _chr_view_asset.meta.char_count
            &&  _hover_idx_d != chr_drag_last_idx) {
                var _ms_found_d = -1;
                for (var _msi_d = 0; _msi_d < array_length(chr_multi_select); _msi_d++) {
                    if (chr_multi_select[_msi_d] == _hover_idx_d) {
                        _ms_found_d = _msi_d;
                        break;
                    }
                }
                if (chr_drag_mode == "add") {
                    if (_ms_found_d < 0) array_push(chr_multi_select, _hover_idx_d);
                } else {
                    if (_ms_found_d >= 0) array_delete(chr_multi_select, _ms_found_d, 1);
                }
                chr_drag_last_idx = _hover_idx_d;
            }
        }

        // End-of-stroke — clear drag when LMB or Ctrl released
        if (chr_drag_active && (!mouse_check_button(mb_left) || !scr_ctrl_held())) {
            chr_drag_active   = false;
            chr_drag_last_idx = -1;
        }
    }
}

// -------------------------------------------------------
// RMB - DELETE ASSET
// -------------------------------------------------------
if (mouse_check_button_pressed(mb_right) && _mouse_in_panel && hover_idx >= 0) {
    var _asset = ds_list_find_value(asset_list, hover_idx);
    // BYTE_DATA and TEXT_DATA aren't node-referenced — they're compiled
    // straight into the build at their address. Deletion can quietly remove
    // data that other code depends on, so confirm before proceeding.
    if (_asset.type == "BYTE_DATA" || _asset.type == "TEXT_DATA") {
        var _confirm_msg = "Delete " + _asset.type + " asset \"" + _asset.name + "\"?\n\n"
                         + "This data is injected directly into the build at $"
                         + string_upper(decimal_to_hex(_asset.address))
                         + " and may be read by your code at runtime.";
        if (!show_question(_confirm_msg)) {
            exit;
        }
		
    }

    // Check if referenced by any node
    var _is_referenced = false;
    _delete_check_name = _asset.name;
    with (obj_c64_node) {
        var _ref_name = "";
        switch (node_type) {
            case "MACRO_BMP": case "MACRO_SPR": case "MACRO_SID": case "MACRO_SFX": case "MACRO_MAP": case "MACRO_CHR": case "MACRO_SID_SONG":
                if (array_length(instructions[0]) > 1)
                    _ref_name = string(instructions[0][1]);
                break;
            case "MACRO_LOADER":
                // slot 1 = LOAD_ORG name, slot 2 = linked file name
                if (array_length(instructions[0]) > 1 &&
                    string(instructions[0][1]) == other._delete_check_name) {
                    _ref_name = string(instructions[0][1]);
                } else if (array_length(instructions[0]) > 2 &&
                           string(instructions[0][2]) == other._delete_check_name) {
                    _ref_name = string(instructions[0][2]);
                }
                break;
            case "MACRO_TEXT_SCROLL":
                // slot 10 = text/scroll asset, slot 13 = charset asset
                if (array_length(instructions[0]) > 10 &&
                    string(instructions[0][10]) == other._delete_check_name) {
                    _ref_name = string(instructions[0][10]);
                } else if (array_length(instructions[0]) > 13 &&
                           string(instructions[0][13]) == other._delete_check_name) {
                    _ref_name = string(instructions[0][13]);
                }
                break;
            case "NEW_STR":
                if ((array_length(instructions[0]) > 4 && is_real(instructions[0][4]) && real(instructions[0][4]) == 1) &&
                    array_length(instructions[0]) > 5)
                    _ref_name = string(instructions[0][5]);
                break;
            case "MACRO_MOVE_BMP_BLOCK":
                // slot 17 = SRC BYTE_DATA asset, slot 20 = BBT collision BYTE_DATA asset
                if (array_length(instructions[0]) > 17 &&
                    string(instructions[0][17]) == other._delete_check_name) {
                    _ref_name = string(instructions[0][17]);
                } else if (array_length(instructions[0]) > 20 &&
                           string(instructions[0][20]) == other._delete_check_name) {
                    _ref_name = string(instructions[0][20]);
                }
                break;
        }
        if (_ref_name == other._delete_check_name) _is_referenced = true;
    }

    // Also block deletion if the asset lives inside any LOAD_ORG's manifest.
    if (!_is_referenced) {
        for (var _dlci = 0; _dlci < ds_list_size(asset_list); _dlci++) {
            var _dlca = ds_list_find_value(asset_list, _dlci);
            if (_dlca.type != "LOAD_ORG") continue;
            if (_dlca == _asset) continue;
            if (!variable_struct_exists(_dlca, "linked_assets")) continue;
            for (var _dllki = 0; _dllki < array_length(_dlca.linked_assets); _dllki++) {
                if (_dlca.linked_assets[_dllki].asset_name == _asset.name) {
                    _is_referenced = true;
                    break;
                }
            }
            if (_is_referenced) break;
        }
    }

    // Also block deletion if the asset lives inside any LOAD_ORG's manifest.
    // (Cosmetic delete cleanup further down also wipes these refs, but we
    //  want the user to consciously remove from the LOAD_ORG first.)
    if (!_is_referenced) {
        for (var _dlci = 0; _dlci < ds_list_size(asset_list); _dlci++) {
            var _dlca = ds_list_find_value(asset_list, _dlci);
            if (_dlca.type != "LOAD_ORG") continue;
            if (_dlca == _asset) continue;
            if (!variable_struct_exists(_dlca, "linked_assets")) continue;
            for (var _dllki = 0; _dllki < array_length(_dlca.linked_assets); _dllki++) {
                if (_dlca.linked_assets[_dllki].asset_name == _asset.name) {
                    _is_referenced = true;
                    break;
                }
            }
            if (_is_referenced) break;
        }
    }

    if (_is_referenced) {
        delete_warn_timer  = 180;
        delete_warn_name   = _asset.name;
    } else {
        if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);

       if (_asset.type == "SPRITE_SET") {
            var _sprites_dir = working_directory + "temp/sprites";
            for (var _si = 0; _si < 64; _si++) {
                var _png = _sprites_dir + "/" + _asset.name + "_" + string(_si) + ".png";
                if (file_exists(_png)) file_delete(_png);
            }
            if (variable_struct_exists(_asset.meta, "spr_sprites")) {
                var _del_len = array_length(_asset.meta.spr_sprites);
                for (var _si = 0; _si < _del_len; _si++) {
                    if (_asset.meta.spr_sprites[_si] != -1 &&
                        sprite_exists(_asset.meta.spr_sprites[_si]))
                        sprite_delete(_asset.meta.spr_sprites[_si]);
                }
            }
            if (variable_struct_exists(_asset.meta, "preview_surf") &&
                surface_exists(_asset.meta.preview_surf))
                surface_free(_asset.meta.preview_surf);
        }

        if (_asset.type == "BITMAP") {
            if (variable_struct_exists(_asset.meta, "preview_surf") &&
                surface_exists(_asset.meta.preview_surf))
                surface_free(_asset.meta.preview_surf);
        }
            
        if (_asset.type == "CHAR_SET") {
            if (variable_struct_exists(_asset.meta, "preview_surf") &&
                surface_exists(_asset.meta.preview_surf))
                surface_free(_asset.meta.preview_surf);
            if (variable_struct_exists(_asset.meta, "preview_surf_mc") &&
                surface_exists(_asset.meta.preview_surf_mc))
                surface_free(_asset.meta.preview_surf_mc);
        }

        if (_asset.type == "MUSIC_MAKER") {
            // Rendered auditions are keyed on instrument bytecode, so a deleted
            // asset's entries can never be looked up again — they would just sit
            // allocated for the rest of the session. Flushing the whole cache is
            // heavy-handed (other assets' entries rebuild on next use) but it is
            // the only teardown path, and deletion is rare.
            scr_sound_preview_cache_clear();
        }

        // Remove stale LOAD_ORG linked_asset references to this asset
        for (var _loi = 0; _loi < ds_list_size(asset_list); _loi++) {
            var _loa = ds_list_find_value(asset_list, _loi);
            if (_loa.type != "LOAD_ORG") continue;
            if (!variable_struct_exists(_loa, "linked_assets")) continue;
            for (var _loli = array_length(_loa.linked_assets) - 1; _loli >= 0; _loli--) {
                if (_loa.linked_assets[_loli].asset_name == _asset.name)
                    array_delete(_loa.linked_assets, _loli, 1);
            }
        }
        ds_list_delete(asset_list, hover_idx);

        if (viewer_asset == hover_idx || viewer_asset >= ds_list_size(asset_list)) {
            if (spred64_v2.active) scr_spred64_v2_close(false);
			scr_asset_inline_editor_close_all()
            viewer_open  = false;
            viewer_asset = -1;
        }
    }
}

// -------------------------------------------------------
// BITMAP_BUILDER UNDO / REDO (Ctrl+Z / Ctrl+Y)
// The editor pushes a snapshot before every mutation (stamp, [X], CLEAR,
// + ADD, group delete, UP/DOWN). Restoring swaps the whole records[] array —
// the group model, the filtered view and the emitted table are all derived
// from it, so nothing else needs unwinding. The BBD table regenerates on the
// next draw via the prev_dirty -> scr_bitmap_builder_generate path.
// -------------------------------------------------------
if (viewer_open && viewer_asset >= 0 && viewer_asset < ds_list_size(asset_list)) {
    var _bb_asset = ds_list_find_value(asset_list, viewer_asset);
    if (_bb_asset.type == "BITMAP_BUILDER") {
        var _bbm = _bb_asset.meta;

        // Records are structs, so a shallow copy would alias them and a later
        // edit could reach back into a stack entry. Deep-copy on both push and
        // restore.
        var _bb_deep = function(_src_arr) {
            var _out = [];
            for (var _di = 0; _di < array_length(_src_arr); _di++) {
                var _r = _src_arr[_di];
                if (_r.kind == "END") {
                    array_push(_out, { kind : "END" });
                } else {
                    array_push(_out, {
                        kind : "REC",
                        sx   : _r.sx,
                        sy   : _r.sy,
                        dx   : _r.dx,
                        dy   : _r.dy,
                        w    : _r.w,
                        h    : _r.h
                    });
                }
            }
            return _out;
        };

        if (keyboard_check(vk_control) && keyboard_check_pressed(ord("Z"))) {
            if (array_length(_bbm.undo_stack) > 0) {
                // Current state -> redo, then pop undo.
                array_push(_bbm.redo_stack, {
                    records    : _bb_deep(_bbm.records),
                    prev_entry : _bbm.prev_entry,
                    sel_rec    : _bbm.sel_rec
                });
                if (array_length(_bbm.redo_stack) > 50) {
                    array_delete(_bbm.redo_stack, 0, 1);
                }
                var _u_top  = array_length(_bbm.undo_stack) - 1;
                var _u_snap = _bbm.undo_stack[_u_top];
                array_delete(_bbm.undo_stack, _u_top, 1);

                _bbm.records     = _bb_deep(_u_snap.records);
                _bbm.prev_entry  = clamp(_u_snap.prev_entry, 0, max(0, array_length(_bbm.records) - 1));
                _bbm.sel_rec     = min(_u_snap.sel_rec, array_length(_bbm.records) - 1);
                _bbm.list_scroll = 0;
                // A grab in flight refers to a source rect, not a record, so it
                // survives — but the phase is dropped so an undo can't be
                // followed by a place that lands in a list that just changed.
                _bbm.phase       = 0;
                _bbm.anchor_c    = -1;
                _bbm.anchor_r    = -1;
                _bbm.prev_dirty  = true;
                _bbm.is_dirty    = true;
            }
            keyboard_clear(ord("Z"));
            exit;
        }

        if (keyboard_check(vk_control) && keyboard_check_pressed(ord("Y"))) {
            if (array_length(_bbm.redo_stack) > 0) {
                array_push(_bbm.undo_stack, {
                    records    : _bb_deep(_bbm.records),
                    prev_entry : _bbm.prev_entry,
                    sel_rec    : _bbm.sel_rec
                });
                if (array_length(_bbm.undo_stack) > 50) {
                    array_delete(_bbm.undo_stack, 0, 1);
                }
                var _r_top  = array_length(_bbm.redo_stack) - 1;
                var _r_snap = _bbm.redo_stack[_r_top];
                array_delete(_bbm.redo_stack, _r_top, 1);

                _bbm.records     = _bb_deep(_r_snap.records);
                _bbm.prev_entry  = clamp(_r_snap.prev_entry, 0, max(0, array_length(_bbm.records) - 1));
                _bbm.sel_rec     = min(_r_snap.sel_rec, array_length(_bbm.records) - 1);
                _bbm.list_scroll = 0;
                _bbm.phase       = 0;
                _bbm.anchor_c    = -1;
                _bbm.anchor_r    = -1;
                _bbm.prev_dirty  = true;
                _bbm.is_dirty    = true;
            }
            keyboard_clear(ord("Y"));
            exit;
        }
    }
}

// -------------------------------------------------------
// MAP UNDO / REDO (Ctrl+Z / Ctrl+Y)
// -------------------------------------------------------
if (viewer_open && viewer_asset >= 0 && viewer_asset < ds_list_size(asset_list)) {
    var _undo_asset = ds_list_find_value(asset_list, viewer_asset);
    if (_undo_asset.type == "MAP_DATA" && variable_struct_exists(_undo_asset.meta, "char_grid")) {
        var _um = _undo_asset.meta;
        if (!variable_struct_exists(_um, "map_undo_stack")) _um.map_undo_stack = [];
        if (!variable_struct_exists(_um, "map_redo_stack")) _um.map_redo_stack = [];

        // Ctrl+Z — undo (skip if mouse is over the inline chr editor)
        var _chr_ed_x = _vx2 - 220;
        var _chr_ed_y = _vy1 + 38;
        var _mouse_on_chr_editor = point_in_rectangle(_mx, _my, _chr_ed_x, _chr_ed_y, _chr_ed_x + 128, _chr_ed_y + 128);
        if (keyboard_check(vk_control) && keyboard_check_pressed(ord("Z"))) {
            if (_mouse_on_chr_editor) {
                // Route to chr editor undo — handled in Draw GUI, just clear to prevent double-fire
                // Do NOT exit so Draw GUI still receives the keypress this frame
            } else {
                if (array_length(_um.map_undo_stack) > 0) {
                    array_push(_um.map_redo_stack, {
                        char_grid:     array_copy_shallow(_um.char_grid),
                        colour_grid:   array_copy_shallow(_um.colour_grid),
                        override_grid: array_copy_shallow(_um.override_grid)
                    });
                    var _snap = _um.map_undo_stack[array_length(_um.map_undo_stack) - 1];
                    array_delete(_um.map_undo_stack, array_length(_um.map_undo_stack) - 1, 1);
                    _um.char_grid     = _snap.char_grid;
                    _um.colour_grid   = _snap.colour_grid;
                    _um.override_grid = _snap.override_grid;
                    scr_asset_map_flush(_undo_asset);
                }
                keyboard_clear(ord("Z"));
                exit;
            }
        }

        if (keyboard_check(vk_control) && keyboard_check_pressed(ord("Y"))) {
            if (_mouse_on_chr_editor) {
                // Route to chr editor redo — handled in Draw GUI
            } else {
                if (array_length(_um.map_redo_stack) > 0) {
                    array_push(_um.map_undo_stack, {
                        char_grid:     array_copy_shallow(_um.char_grid),
                        colour_grid:   array_copy_shallow(_um.colour_grid),
                        override_grid: array_copy_shallow(_um.override_grid)
                    });
                    var _snap = _um.map_redo_stack[array_length(_um.map_redo_stack) - 1];
                    array_delete(_um.map_redo_stack, array_length(_um.map_redo_stack) - 1, 1);
                    _um.char_grid     = _snap.char_grid;
                    _um.colour_grid   = _snap.colour_grid;
                    _um.override_grid = _snap.override_grid;
                    scr_asset_map_flush(_undo_asset);
                }
                keyboard_clear(ord("Y"));
                exit;
            }
        }
    }
} 

// -------------------------------------------------------
// META_TILESET MAP UNDO / REDO (Ctrl+Z / Ctrl+Y) — panel + active_map sensitive
// -------------------------------------------------------
if (viewer_open && viewer_asset >= 0 && viewer_asset < ds_list_size(asset_list)) {
    var _mt_asset = ds_list_find_value(asset_list, viewer_asset);
    if (_mt_asset.type == "META_TILESET") {
        var _mm = _mt_asset.meta;
        if (!variable_struct_exists(_mm, "mt_undo_stack")) _mm.mt_undo_stack = [];
        if (!variable_struct_exists(_mm, "mt_redo_stack")) _mm.mt_redo_stack = [];

        

        if (keyboard_check(vk_control) && keyboard_check_pressed(ord("Z"))) {
            if (array_length(_mm.mt_undo_stack) > 0) {
                var _peek = _mm.mt_undo_stack[array_length(_mm.mt_undo_stack) - 1];
                // Stage 1: next undo belongs to a different map — switch view only,
                // leave the entry on the stack. The following Ctrl+Z restores it.
                if (_mm.active_map != _peek.map_idx) {
                    _mm.active_map = _peek.map_idx;
                } else {
                    // Stage 2: we're on the right map — perform the restore
                    var _snap = _mm.mt_undo_stack[array_length(_mm.mt_undo_stack) - 1];
                    array_delete(_mm.mt_undo_stack, array_length(_mm.mt_undo_stack) - 1, 1);
                    var _z_target = (_snap.map_idx >= 0 && _snap.map_idx < _mm.map_count)
                                  ? _mm.maps[_snap.map_idx]
                                  : _mm.test_grid;
                    array_push(_mm.mt_redo_stack, {
                        map_idx: _snap.map_idx,
                        grid:    array_copy_shallow(_z_target)
                    });
                    if (_snap.map_idx < 0) {
                        _mm.test_grid = _snap.grid;
                    } else {
                        _mm.maps[_snap.map_idx] = _snap.grid;
                    }
                    _mm.is_dirty = true;
                }
            }
            keyboard_clear(ord("Z"));
            exit;
        }

        if (keyboard_check(vk_control) && keyboard_check_pressed(ord("Y"))) {
            if (array_length(_mm.mt_redo_stack) > 0) {
                var _snap = _mm.mt_redo_stack[array_length(_mm.mt_redo_stack) - 1];
                array_delete(_mm.mt_redo_stack, array_length(_mm.mt_redo_stack) - 1, 1);
                // Switch to the map this edit belongs to before restoring
                if (_mm.active_map != _snap.map_idx) {
                    _mm.active_map = _snap.map_idx;
                }
                var _y_target = (_snap.map_idx >= 0 && _snap.map_idx < _mm.map_count)
                              ? _mm.maps[_snap.map_idx]
                              : _mm.test_grid;
                array_push(_mm.mt_undo_stack, {
                    map_idx: _snap.map_idx,
                    grid:    array_copy_shallow(_y_target)
                });
                if (_snap.map_idx < 0) {
                    _mm.test_grid = _snap.grid;
                } else {
                    _mm.maps[_snap.map_idx] = _snap.grid;
                }
                _mm.is_dirty = true;
            }
            keyboard_clear(ord("Y"));
            exit;
        }

        // ---- SLICE modal result consumer ----
        // obj_integer_box publishes { w, h, action, cancelled } into
        // global.integer_result. Drain it here so the modal stays decoupled.
        if (is_struct(global.integer_result))
        {
            var _ir = global.integer_result;
            global.integer_result = "";   // consume immediately (single-shot)

            if (!_ir.cancelled && _ir.action == "SLICE")
            {
                var _room_w = _ir.w;
                var _room_h = _ir.h;
                if (_room_w >= 1 && _room_h >= 1)
                {
                    scr_mts_slice_active_map(_mm, _room_w, _room_h);
                    _mm.is_dirty = true;
                }
            }
        }
    }
}

// -------------------------------------------------------
// ESCAPE - close viewer
// -------------------------------------------------------

if (keyboard_check_pressed(vk_escape) && !global.integer_box_open) {
    if (viewer_open) {
        // If stamp mode active, cancel it first rather than closing viewer
        if (viewer_asset >= 0 && viewer_asset < ds_list_size(asset_list)) {
            var _esc_asset = ds_list_find_value(asset_list, viewer_asset);
            if (_esc_asset.type == "MAP_DATA" &&
                variable_struct_exists(_esc_asset.meta, "stamp_active") &&
                _esc_asset.meta.stamp_active) {
                _esc_asset.meta.stamp_active = false;
                _esc_asset.meta.stamp_data   = [];
                _esc_asset.meta.sel_grid     = array_create(
                    _esc_asset.meta.grid_w * _esc_asset.meta.grid_h, 0);
                keyboard_clear(vk_escape);
                exit;
            }
        }
		if (spred64_v2.active) scr_spred64_v2_close(true);
		scr_asset_inline_editor_close_all()
        viewer_open     = false;
        viewer_asset    = -1;
        bb_return_asset = -1;   // leaving the viewer entirely — drop the breadcrumb
        editorClosed = 1;
        alarm[0]     = 65;
        keyboard_clear(vk_escape);
        exit;
    }
}

if editorClosed==1 gpu_set_tex_filter(true);