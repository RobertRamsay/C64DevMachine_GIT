/// @desc obj_asset_manager Draw GUI



if obj_workspace_manager.code_editor_open or obj_workspace_manager.hideui exit;


// Invalidate dither cache when mode/invert changes
var _am = (viewer_open && viewer_asset >= 0) ? ds_list_find_value(asset_list, viewer_asset) : noone;
var _cur_mode = (_am != noone && _am.type == "BITMAP" && variable_struct_exists(_am.meta, "dither_mode")) ? _am.meta.dither_mode : "NONE";
var _cur_inv  = (_am != noone && _am.type == "BITMAP" && variable_struct_exists(_am.meta, "dither_invert")) ? _am.meta.dither_invert : false;
var _cur_hires = (_am != noone && _am.type == "BITMAP") ? scr_asset_bmp_is_hires(_am) : false;
if (!variable_struct_exists(id, "_dither_cache_hires")) _dither_cache_hires = false;
if (_cur_mode != _dither_cache_mode || _cur_inv != _dither_cache_inv || _cur_hires != _dither_cache_hires) {
    _dither_cache_mode  = _cur_mode;
    _dither_cache_inv   = _cur_inv;
    _dither_cache_hires = _cur_hires;
    _dither_cache      = array_create(320 * 200, true);
    for (var _dy = 0; _dy < 200; _dy++) {
        for (var _dx = 0; _dx < 320; _dx++) {
            _dither_cache[_dy * 320 + _dx] = scr_check_dither_mask(_cur_mode, _dx, _dy, _cur_hires);
        }
    }
}

var _gui_w        = global.gui_w;
var _gui_h        = display_get_gui_height();
var _mx           = global.gui_mouse_x;
var _my           = global.gui_mouse_y;
var _panel_right  = _gui_w - 2;
var _panel_bottom = _gui_h - 100;
var _panel_w      = _panel_right - panel_x;
var _panel_h      = _panel_bottom - panel_y;

// Seed pixel_backup for every BITMAP asset that has a valid surface but no backup yet
// This ensures F11 surface loss can always restore, even if the viewer has never been opened
var _bmp_seed_count = ds_list_size(asset_list);
for (var _bsi = 0; _bsi < _bmp_seed_count; _bsi++) {
    var _bsa = ds_list_find_value(asset_list, _bsi);
    if (_bsa.type != "BITMAP") continue;
    if (!variable_struct_exists(_bsa.meta, "preview_surf")) continue;
    if (!surface_exists(_bsa.meta.preview_surf)) continue;
    if (!variable_struct_exists(_bsa.meta, "pixel_backup")) _bsa.meta.pixel_backup = -1;
    if (buffer_exists(_bsa.meta.pixel_backup)) continue;
    _bsa.meta.pixel_backup = buffer_create(320 * 200 * 4, buffer_fixed, 1);
    buffer_get_surface(_bsa.meta.pixel_backup, _bsa.meta.preview_surf, 0);
}

panel_w  = 244;
panel_x  = _gui_w - panel_w - 30;
panel_y = 410;

if (variable_instance_exists(id, "map_chr_picker_open") && map_chr_picker_open) {
    draw_set_color(c_red);
    draw_text(400, 400, "PICKER OPEN");
}

// -------------------------------------------------------
// PANEL BACKGROUND
// -------------------------------------------------------
draw_set_color(make_color_rgb(18, 18, 28));
draw_rectangle(panel_x, panel_y, _panel_right, _panel_bottom, false);
draw_set_color(make_color_rgb(50, 50, 70));
draw_rectangle(panel_x, panel_y, _panel_right, _panel_bottom, true);

// -------------------------------------------------------
// ADD ASSET BUTTON
// -------------------------------------------------------
if (!viewer_open || viewer_asset < 0 || viewer_asset >= ds_list_size(asset_list)) {
var _btn_hover = point_in_rectangle(_mx, _my, panel_x + 4, panel_y + 4, _panel_right - 4, panel_y + 26);
draw_set_color(_btn_hover ? make_color_rgb(60, 190, 90) : make_color_rgb(30, 80, 40));
draw_rectangle(panel_x + 4, panel_y + 4, _panel_right - 4, panel_y + 26, false);
draw_set_font(fnt_c64_code);
draw_set_color(c_white);
draw_set_halign(fa_center);
draw_text(panel_x + (_panel_w * 0.5), panel_y + 6, "[ADD ASSET +]");
draw_set_halign(fa_left);

// -------------------------------------------------------
// SORT BY control
// -------------------------------------------------------
var _sort_row_y = panel_y + 30;
var _sort_opts  = ["NAME", "TYPE", "ADDR"];
draw_set_font(fnt_c64_tiny);
draw_set_color(make_color_rgb(140, 140, 140));
draw_text(panel_x + 6, _sort_row_y + 4, "SORT BY:");
var _sort_btn_x = panel_x + 62;
for (var _soi = 0; _soi < array_length(_sort_opts); _soi++) {
    var _so_w    = 46;
    var _so_x1   = _sort_btn_x + (_soi * (_so_w + 4));
    var _so_x2   = _so_x1 + _so_w;
    var _so_hov  = point_in_rectangle(_mx, _my, _so_x1, _sort_row_y, _so_x2, _sort_row_y + 16);
    var _so_on   = (asset_sort_mode == _sort_opts[_soi]);
    draw_set_color(_so_on ? make_color_rgb(200, 160, 40) : (_so_hov ? make_color_rgb(70, 70, 90) : make_color_rgb(40, 40, 55)));
    draw_rectangle(_so_x1, _sort_row_y, _so_x2, _sort_row_y + 16, false);
    draw_set_color(_so_on ? c_black : c_white);
    draw_set_halign(fa_center);
    draw_text((_so_x1 + _so_x2) / 2, _sort_row_y + 2, _sort_opts[_soi]);
    draw_set_halign(fa_left);
    if (_so_hov && mouse_check_button_pressed(mb_left)) {
        asset_sort_mode = _sort_opts[_soi];
    }
}

// -------------------------------------------------------
// ASSET LIST
// -------------------------------------------------------
var _count  = ds_list_size(asset_list);
var _list_y = panel_y + 66;

// Sort a display-order index array rather than asset_list itself, so the
// underlying list's real insertion order (relied
// on everywhere else that indexes asset_list directly) never changes.
// Shared with Step_0's hit-testing via scr_asset_sorted_indices() so the
// two can never disagree about display order.
var _sorted_indices = scr_asset_sorted_indices();

for (var _pos = 0; _pos < _count; _pos++) {
    var _i     = _sorted_indices[_pos];
    var _asset = ds_list_find_value(asset_list, _i);
    var _iy    = _list_y + (_pos * item_h) - panel_scroll;

	if (_iy + item_h <= panel_y + 66 || _iy >= _panel_bottom - 38) continue;

   // Row background
        var _is_load_org = false;
    var _is_load_reu = false;

    if (variable_struct_exists(_asset, "type")) {
        _is_load_org = (_asset.type == "LOAD_ORG");
        _is_load_reu = (_asset.type == "LOAD_REU");
    }
    
    var _row_col;
    if (_is_load_org) {
        if (_i == hover_idx) {
            _row_col = make_color_rgb(130, 100, 50);
        }
        else {
            _row_col = make_color_rgb(100, 70, 30);
        }
    }
        else if (_is_load_reu) {
        if (_i == hover_idx) {
            _row_col = make_color_rgb(45, 105, 120);
        } else {
            _row_col = make_color_rgb(25, 65, 80);
        }
    }
    else {
        if (_i == hover_idx) {
            _row_col = make_color_rgb(45, 45, 65);
        }
        else {
            if (_i mod 2 == 0) {
                _row_col = make_color_rgb(22, 22, 35);
            }
            else {
                _row_col = make_color_rgb(18, 18, 28);
            }
        }
    }
    
    // Conflict Flashing
    var _has_conflict = false;
    var _my_size = buffer_exists(_asset.buffer) ? buffer_get_size(_asset.buffer) : 0;
    var _my_end = _asset.address + _my_size;

// Check against nodes — only flag if the node physically overlaps
    with (obj_c64_node) {
        if (!is_connected) continue;
        if (node_type == "MACRO_CODE") continue;
        if (total_node_size == 0) continue;
        if (pc_address == 0) continue;
        if (pc_address < _my_end && (pc_address + total_node_size) > _asset.address) {
            _has_conflict = true;
        }
    }

// Also check global conflict ranges
    if (!_has_conflict && _my_size > 0) {
        var _my_end2 = _asset.address + _my_size;
        var _cr_len = array_length(global.conflict_ranges);
        for (var _cri = 0; _cri < _cr_len; _cri++) {
            var _cr = global.conflict_ranges[_cri];
            if (_asset.address < _cr.addr_end && _my_end2 > _cr.addr_start) {
                _has_conflict = true;
                break;
            }
        }
    }
// Direct check: does any conflicted node overlap this asset?
    if (!_has_conflict && _my_size > 0) {
        var _my_end2 = _asset.address + _my_size;
        with (obj_c64_node) {
            if (!is_conflicted) continue;
            // Check node body range
            if (pc_address < _my_end2 && (pc_address + total_node_size) > _asset.address) {
                _has_conflict = true;
                break;
            }
            // Check MACRO_CODE proxy segments
            if (node_type == "MACRO_CODE" && variable_instance_exists(id, "code_seg_cache")) {
                var _seg_len = array_length(code_seg_cache);
                            for (var _sci = 0; _sci < _seg_len; _sci++) {
                    var _cs = code_seg_cache[_sci];
                    if (_cs.addr < _my_end2 && (_cs.addr + _cs.size) > _asset.address) {
                        _has_conflict = true;
                        break;
                    }
                }
            }
            if (_has_conflict) break;
        }
    }

    if (_has_conflict && _my_size > 0) {
        var _p = abs(sin(current_time * 0.01));
        _row_col = merge_color(_row_col, make_color_rgb(150, 0, 0), 0.4 * _p);
    }
	
    draw_set_color(_row_col);
    draw_rectangle(panel_x, _iy, _panel_right, _iy + item_h, false);

    // Type colour tag (left edge)
    var _tcol = variable_struct_exists(type_colours, _asset.type)
              ? variable_struct_get(type_colours, _asset.type)
              : c_gray;
    draw_set_color(_tcol);
    draw_rectangle(panel_x, _iy, panel_x + 4, _iy + item_h, false);

    // Type label
    draw_set_font(fnt_c64_tiny);
    draw_set_color(_tcol);
    draw_text(panel_x + 8, _iy + 2, _asset.type);

    // Zone boundaries
    var _addr_x = _panel_right - 58;
    var _edit_x = _addr_x - 30;

    // Name - editing or display
    draw_set_font(fnt_c64_code);
    if (editing_name && editing_idx == _i) {
        draw_set_color(make_color_rgb(30, 50, 40));
        draw_rectangle(panel_x + 8, _iy + 16, _edit_x - 2, _iy + item_h - 2, false);
        draw_set_color(c_lime);
        draw_text(panel_x + 10, _iy + 17, editing_string);
        if ((current_time mod 600) < 300) {
            var _cw = string_width(string_copy(editing_string, 1, editing_cursor));
            draw_set_color(c_white);
            draw_line(panel_x + 10 + _cw, _iy + 17, panel_x + 10 + _cw, _iy + item_h - 4);
        }
    } else {
        draw_set_color(c_white);
        draw_text(panel_x + 8, _iy + 16, _asset.name);
    }

    // Divider before EDIT zone
    draw_set_color(make_color_rgb(50, 50, 70));
    draw_line(_edit_x, _iy + 2, _edit_x, _iy + item_h - 2);

    // EDIT zone
    var _edit_hover = point_in_rectangle(_mx-3, _my, _edit_x, _iy, _addr_x, _iy + item_h);
    draw_set_color(_edit_hover ? make_color_rgb(50, 80, 60) : make_color_rgb(28, 28, 40));
    draw_rectangle(_edit_x + 1, _iy + 1, _addr_x - 1, _iy + item_h - 1, false);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(_edit_hover ? c_white : make_color_rgb(70, 70, 90));
    draw_set_halign(fa_center);
    draw_text(_edit_x + 15, _iy + 13, "EDIT");
    draw_set_halign(fa_left);

    // Divider before address zone
    draw_set_color(make_color_rgb(50, 50, 70));
    draw_line(_addr_x, _iy + 2, _addr_x, _iy + item_h - 2);

    // Address
    draw_set_font(fnt_c64_code);
    draw_set_halign(fa_right);
    if (editing_address && editing_address_idx == _i) {
        draw_set_color(make_color_rgb(20, 50, 30));
        draw_rectangle(_addr_x + 2, _iy + 4, _panel_right - 4, _iy + item_h - 4, false);
        draw_set_color(c_lime);
        var _blink = ((current_time mod 600) < 300) ? "_" : " ";
        draw_text(_panel_right - 6, _iy + 12, editing_addr_string + _blink);
    } else if (_asset.type == "LOAD_ORG" || _asset.type == "LOAD_REU" || _asset.type == "BITMAP_BUILDER" || _asset.type == "MUSIC_MAKER") {
        // LOAD_ORG is a manifest, not physical data — it has no meaningful
        // load address (each linked asset carries its own). BITMAP_BUILDER is
        // an internal editor asset: it emits a derived BYTE_DATA table which
        // carries the real address, so the builder itself has none. Show a dash.
        draw_set_color(make_color_rgb(90, 90, 110));
        draw_text(_panel_right - 6, _iy + 12, "--");
    } else {
        var _ah = string_upper(decimal_to_hex(_asset.address));
        while (string_length(_ah) < 4) _ah = "0" + _ah;
        var _addr_hover = point_in_rectangle(_mx, _my, _addr_x, _iy, _panel_right, _iy + item_h);
        draw_set_color(_addr_hover ? c_white : c_aqua);
        draw_text(_panel_right - 6, _iy + 12, "$" + _ah);
    }
    draw_set_halign(fa_left);

	// LOAD_ORG membership tag
	    if (instance_exists(obj_asset_manager)) {
	        var _tag_x = _edit_x - 4;
	        for (var _tai = 0; _tai < ds_list_size(asset_list); _tai++) {
	            var _ta = ds_list_find_value(asset_list, _tai);
	            if (_ta.type != "LOAD_ORG" && _ta.type != "LOAD_REU") continue;
	            if (!variable_struct_exists(_ta, "linked_assets")) continue;
	            for (var _tli = 0; _tli < array_length(_ta.linked_assets); _tli++) {
	                if (_ta.linked_assets[_tli].asset_name == _asset.name) {
	                    var _tag_col = (_ta.type == "LOAD_REU")
			             ? make_color_rgb(45, 105, 120)
			             : make_color_rgb(200, 160, 40);
	                    draw_set_color(_tag_col);
	                    draw_rectangle(_tag_x - 80, _iy + 4, _tag_x - 2, _iy + item_h - 4, false);
	                    draw_set_font(fnt_c64_pico);
	                    draw_set_color(c_white);
	                    draw_set_halign(fa_center);
						var _tag_sprite = (_ta.type == "LOAD_REU") ? spr_chipRam : spr_disk;

							draw_sprite_ext(
							    _tag_sprite,
							    0,
							    _tag_x - 64,
							    _iy + 19,
							    .2,
							    .2,
							    0,
							    c_white,
							    1.0
							);
	                    var _short = string_copy(_ta.name, 1, 12);
					
	                    draw_text(_tag_x - 40, _iy + 13, _short);
						draw_set_halign(fa_left);
	                   
	                    break;
	                }
	            }
	        }
	    }

	    // Row divider
	    draw_set_color(make_color_rgb(35, 35, 50));
	    draw_line(panel_x, _iy + item_h, _panel_right, _iy + item_h);
	}
// Empty state
if (_count == 0) {
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(60, 60, 80));
    draw_set_halign(fa_center);
    draw_text(panel_x + (_panel_w * 0.5), _list_y + 20, "NO ASSETS");
    draw_text(panel_x + (_panel_w * 0.5), _list_y + 34, "CLICK [ADD ASSET +]");
    draw_set_halign(fa_left);
}
} // end hide panel when viewer open

// -------------------------------------------------------
// ADD DROPDOWN (drawn over list)
// -------------------------------------------------------
gpu_set_scissor(0, 0, window_get_width(), window_get_height());

if (add_dropdown_open) {
    for (var _i = 0; _i < array_length(asset_types); _i++) {
        var _dy  = panel_y + 28 + (_i * 20);
        var _hov = (add_dropdown_hover == _i);
        draw_set_color(_hov ? make_color_rgb(50, 80, 60) : make_color_rgb(25, 35, 30));
        draw_rectangle(panel_x, _dy, _panel_right, _dy + 20, false);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(_hov ? c_white : c_ltgray);
        draw_text(panel_x + 10, _dy + 4, asset_types[_i]);
    }
    draw_set_color(make_color_rgb(50, 50, 70));
    draw_rectangle(panel_x, panel_y + 28, _panel_right,
                   panel_y + 28 + (array_length(asset_types) * 20), true);
}

// -------------------------------------------------------
// BMP PICKER DROPDOWN
// -------------------------------------------------------
if (bmp_picker_open && instance_exists(bmp_picker_node)) {
    var _cam_x    = obj_workspace_manager.cam_x;
    var _cam_y    = obj_workspace_manager.cam_y;
    var _cam_zoom = obj_workspace_manager.cam_zoom;
    var _node     = bmp_picker_node;
    var _pdx      = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
    var _pdy      = ((_node.y + 24)              - _cam_y) / _cam_zoom;
    var _pw       = 180;
    var _ih       = 20;

    var _matches = [];
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _a = ds_list_find_value(asset_list, _i);
        if (_a.type == "BITMAP") array_push(_matches, _a);
    }

    var _total_h = max(1, array_length(_matches)) * _ih + 4;
    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, false);
    draw_set_color(make_color_rgb(80, 80, 120));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, true);

    if (array_length(_matches) == 0) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_text(_pdx + 8, _pdy + 6, "NO BITMAP ASSETS");
    } else {
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy  = _pdy + 2 + (_i * _ih);
            var _hov = (bmp_picker_hover == _i);
            draw_set_color(_hov ? make_color_rgb(60, 60, 100) : make_color_rgb(25, 25, 40));
            draw_rectangle(_pdx + 2, _iy, _pdx + _pw - 2, _iy + _ih - 1, false);
            draw_set_font(fnt_c64_code);
            draw_set_color(_hov ? c_white : c_ltgray);
            draw_text(_pdx + 8, _iy + 3, _matches[_i].name);
        }
    }
}

// -------------------------------------------------------
// VECTOR BITMAP PICKER DROPDOWN
// -------------------------------------------------------
if (vbmp_picker_open && instance_exists(vbmp_picker_node)) {
    var _cam_x    = obj_workspace_manager.cam_x;
    var _cam_y    = obj_workspace_manager.cam_y;
    var _cam_zoom = obj_workspace_manager.cam_zoom;
    var _node     = vbmp_picker_node;
    var _pdx      = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
    var _pdy      = ((_node.y + 24)              - _cam_y) / _cam_zoom;
    var _pw       = 180;
    var _ih       = 20;

    var _matches = [];
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _a = ds_list_find_value(asset_list, _i);
        if (_a.type == "VECTOR_BITMAP") array_push(_matches, _a);
    }

    var _total_h = max(1, array_length(_matches)) * _ih + 4;
    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, false);
    draw_set_color(make_color_rgb(120, 200, 220));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, true);

    if (array_length(_matches) == 0) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_text(_pdx + 8, _pdy + 6, "NO VECTOR BITMAP ASSETS");
    } else {
        var _vbmp_mouse_i = -1;
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy  = _pdy + 2 + (_i * _ih);
            var _hov = point_in_rectangle(device_mouse_x_to_gui(0), device_mouse_y_to_gui(0), _pdx + 2, _iy, _pdx + _pw - 2, _iy + _ih - 1);
            draw_set_color(_hov ? make_color_rgb(40, 90, 100) : make_color_rgb(25, 25, 40));
            draw_rectangle(_pdx + 2, _iy, _pdx + _pw - 2, _iy + _ih - 1, false);
            draw_set_font(fnt_c64_code);
            draw_set_color(_hov ? c_white : c_ltgray);
            draw_text(_pdx + 8, _iy + 3, _matches[_i].name);
        }
    }
}

// -------------------------------------------------------
// SID PICKER DROPDOWN
// -------------------------------------------------------
if (sid_picker_open && instance_exists(sid_picker_node)) {
    var _cam_x    = obj_workspace_manager.cam_x;
    var _cam_y    = obj_workspace_manager.cam_y;
    var _cam_zoom = obj_workspace_manager.cam_zoom;
    var _node     = sid_picker_node;
    var _pdx      = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
    var _pdy      = ((_node.y + 24)              - _cam_y) / _cam_zoom;
    var _pw       = 180;
    var _ih       = 20;

    var _matches = [];
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _a = ds_list_find_value(asset_list, _i);
       if (_a.type == "SID_MUSIC") array_push(_matches, _a);
    }

    var _total_h = max(1, array_length(_matches)) * _ih + 4;
    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, false);
    draw_set_color(make_color_rgb(180, 60, 180));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, true);

    if (array_length(_matches) == 0) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_text(_pdx + 8, _pdy + 6, "NO SID ASSETS");
    } else {
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy  = _pdy + 2 + (_i * _ih);
            var _hov = (sid_picker_hover == _i);
            draw_set_color(_hov ? make_color_rgb(80, 30, 80) : make_color_rgb(25, 25, 40));
            draw_rectangle(_pdx + 2, _iy, _pdx + _pw - 2, _iy + _ih - 1, false);
            draw_set_font(fnt_c64_code);
            draw_set_color(_hov ? c_white : c_ltgray);
            draw_text(_pdx + 8, _iy + 3, _matches[_i].name);
        }
    }
}

if (sfx_picker_open && instance_exists(sfx_picker_node)) {
    var _cam_x    = obj_workspace_manager.cam_x;
    var _cam_y    = obj_workspace_manager.cam_y;
    var _cam_zoom = obj_workspace_manager.cam_zoom;
    var _node     = sfx_picker_node;
    var _pdx      = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
    var _pdy      = ((_node.y + 24)              - _cam_y) / _cam_zoom;
    var _pw       = 220;
    var _ih       = 20;

    var _match_labels = [];
    var _header       = "";

    if (sfx_picker_field == "asset") {
        _header = "SFX DATA ASSETS";
        for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
            var _a = ds_list_find_value(asset_list, _i);
            if (_a.type == "SFX_DATA") {
                var _sfx_n = variable_struct_exists(_a.meta, "instruments")
                    ? array_length(_a.meta.instruments) : 0;
                array_push(_match_labels, _a.name
                    + "  (" + string(_sfx_n) + " instr)");
            }
        }
    } else {
        _header = "SELECT INSTRUMENT";
        var _asset_name = string(_node.instructions[0][1]);
        for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
            var _a = ds_list_find_value(asset_list, _i);
            if (_a.type == "SFX_DATA" && _a.name == _asset_name &&
                variable_struct_exists(_a.meta, "instruments")) {
                var _instrs = _a.meta.instruments;
                for (var _ii = 0; _ii < array_length(_instrs); _ii++) {
                    var _ins = _instrs[_ii];
                    array_push(_match_labels,
                        string(_ii) + ": " + _ins.name
                        + "  $" + string_upper(decimal_to_hex(_ins.ad))
                        + "/$"  + string_upper(decimal_to_hex(_ins.sr)));
                }
                break;
            }
        }
    }

    var _total_h = max(1, array_length(_match_labels)) * _ih + 24;

    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, false);
    draw_set_color(make_color_rgb(120, 60, 200));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, true);

    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(180, 120, 255));
    draw_text(_pdx + 6, _pdy + 4, _header);

    if (array_length(_match_labels) == 0) {
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_text(_pdx + 8, _pdy + 24,
            sfx_picker_field == "asset" ? "NO SFX_DATA ASSETS" : "NO INSTRUMENTS");
    } else {
        for (var _i = 0; _i < array_length(_match_labels); _i++) {
            var _iy  = _pdy + 20 + (_i * _ih);
            var _hov = (sfx_picker_hover == _i);
            draw_set_color(_hov ? make_color_rgb(70, 40, 140) : make_color_rgb(25, 25, 40));
            draw_rectangle(_pdx + 2, _iy, _pdx + _pw - 2, _iy + _ih - 1, false);
            draw_set_font(fnt_c64_code);
            draw_set_color(_hov ? c_white : make_color_rgb(200, 160, 255));
            draw_text(_pdx + 8, _iy + 3, _match_labels[_i]);
        }
    }
}




// -------------------------------------------------------
// SPR PICKER DROPDOWN
// -------------------------------------------------------
if (spr_picker_open && instance_exists(spr_picker_node)) {
    var _cam_x    = obj_workspace_manager.cam_x;
    var _cam_y    = obj_workspace_manager.cam_y;
    var _cam_zoom = obj_workspace_manager.cam_zoom;
    var _node     = spr_picker_node;
    var _pdx      = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
    var _pdy      = ((_node.y + 24)              - _cam_y) / _cam_zoom;
    var _pw       = 180;
    var _ih       = 20;

    var _matches = [];
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _a = ds_list_find_value(asset_list, _i);
        if (_a.type == "SPRITE_SET") array_push(_matches, _a);
    }

    var _total_h = max(1, array_length(_matches)) * _ih + 4;
    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, false);
    draw_set_color(make_color_rgb(200, 120, 40));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, true);

    if (array_length(_matches) == 0) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_text(_pdx + 8, _pdy + 6, "NO SPRITE ASSETS");
    } else {
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy  = _pdy + 2 + (_i * _ih);
            var _hov = (spr_picker_hover == _i);
            draw_set_color(_hov ? make_color_rgb(80, 50, 20) : make_color_rgb(25, 25, 40));
            draw_rectangle(_pdx + 2, _iy, _pdx + _pw - 2, _iy + _ih - 1, false);
            draw_set_font(fnt_c64_code);
            draw_set_color(_hov ? c_white : c_ltgray);
            draw_text(_pdx + 8, _iy + 3, _matches[_i].name);
        }
    }
}



// -------------------------------------------------------
// MAP PICKER DROPDOWN
// -------------------------------------------------------
if (map_picker_open && instance_exists(map_picker_node)) {
    var _cam_x    = obj_workspace_manager.cam_x;
    var _cam_y    = obj_workspace_manager.cam_y;
    var _cam_zoom = obj_workspace_manager.cam_zoom;
    var _node     = map_picker_node;
    var _pdx      = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
    var _pdy      = ((_node.y + 24)              - _cam_y) / _cam_zoom;
    var _pw       = 180;
    var _ih       = 20;

    var _matches = [];
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _a = ds_list_find_value(asset_list, _i);
        if (_a.type == "MAP_DATA") array_push(_matches, _a);
    }

    var _total_h = max(1, array_length(_matches)) * _ih + 4;
    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, false);
    draw_set_color(make_color_rgb(80, 200, 120));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, true);

    if (array_length(_matches) == 0) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_text(_pdx + 8, _pdy + 6, "NO MAP ASSETS");
    } else {
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy  = _pdy + 2 + (_i * _ih);
            var _hov = (map_picker_hover == _i);
            draw_set_color(_hov ? make_color_rgb(40, 90, 55) : make_color_rgb(25, 25, 40));
            draw_rectangle(_pdx + 2, _iy, _pdx + _pw - 2, _iy + _ih - 1, false);
            draw_set_font(fnt_c64_code);
            draw_set_color(_hov ? c_white : c_ltgray);
            draw_text(_pdx + 8, _iy + 3, _matches[_i].name);
        }
    }
}

// -------------------------------------------------------
// METAMAP PICKER DROPDOWN — lists META_TILESET assets
// -------------------------------------------------------
if (metamap_picker_open && instance_exists(metamap_picker_node)) {
    var _cam_x    = obj_workspace_manager.cam_x;
    var _cam_y    = obj_workspace_manager.cam_y;
    var _cam_zoom = obj_workspace_manager.cam_zoom;
    var _node     = metamap_picker_node;
    var _pdx      = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
    var _pdy      = ((_node.y + 24)              - _cam_y) / _cam_zoom;
    var _pw       = 180;
    var _ih       = 20;

    var _matches = [];
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _a = ds_list_find_value(asset_list, _i);
        if (_a.type == "META_TILESET") array_push(_matches, _a);
    }

    var _total_h = max(1, array_length(_matches)) * _ih + 4;
    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, false);
    draw_set_color(make_color_rgb(80, 200, 120));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, true);

    if (array_length(_matches) == 0) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_text(_pdx + 8, _pdy + 6, "NO META_TILESET ASSETS");
    } else {
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy  = _pdy + 2 + (_i * _ih);
            var _hov = (metamap_picker_hover == _i);
            draw_set_color(_hov ? make_color_rgb(40, 90, 55) : make_color_rgb(25, 25, 40));
            draw_rectangle(_pdx + 2, _iy, _pdx + _pw - 2, _iy + _ih - 1, false);
            draw_set_font(fnt_c64_code);
            draw_set_color(_hov ? c_white : c_ltgray);
            draw_text(_pdx + 8, _iy + 3, _matches[_i].name);
        }
    }
}


// -------------------------------------------------------
// ASSET VIEWER
// -------------------------------------------------------

if (viewer_open && viewer_asset >= 0 && viewer_asset < ds_list_size(asset_list)) {
    var _asset = ds_list_find_value(asset_list, viewer_asset);

	var _wide_editor = (_asset.type == "BITMAP_BUILDER" || _asset.type == "MUSIC_MAKER");
	var _vx1 = _wide_editor ? 30 : 288;
	var _vy1 = 108;
	var _vx2 = _wide_editor ? (panel_x + 20) : (panel_x - 10);
	var _vy2 = 972;
	
    var _vw    = _vx2 - _vx1;
    var _vh    = _vy2 - _vy1;

     //Backdrop
    draw_set_color(make_color_rgb(0, 0, 0));
    draw_set_alpha(0.6);
    draw_rectangle(0, 0, _gui_w, _gui_h, false);
    draw_set_alpha(1.0);

    // Panel
    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(_vx1, _vy1, _vx2, _vy2, false);
    draw_set_color(make_color_rgb(50, 50, 70));
    draw_rectangle(_vx1, _vy1, _vx2, _vy2, true);

    // Header bar
    var _tcol = variable_struct_exists(type_colours, _asset.type)
              ? variable_struct_get(type_colours, _asset.type)
              : c_gray;
    draw_set_color(_tcol);
    draw_rectangle(_vx1, _vy1, _vx2, _vy1 + 28, false);
    draw_set_font(fnt_c64_code);
    draw_set_color(c_white);
    draw_text(_vx1 + 10, _vy1 + 6, _asset.type + " : " + _asset.name);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(40, 30, 0));
    draw_set_halign(fa_right);
    draw_text(_vx2 - 8, _vy1 + 8, "ESC TO CLOSE");
    draw_set_halign(fa_left);

    var _cy = _vy1 + 38;

    // LOAD FILE BUTTON
    // For SPRITE_SET assets, the IMPORT button is hidden while V2 is open
    // on this asset. Importing mid-edit would overwrite the asset's meta
    // (compositor, anim, palette) while V2 holds stale working clones —
    // user must close V2 first to re-import cleanly.
    var _hide_import = (_asset.type == "SPRITE_SET"
                     && spred64_v2.active
                     && spred64_v2.asset_index == viewer_asset);
    var _lbx1     = _vx1 + 10;
    var _lbx2     = _vx1 + 110;
    var _lby1     = _cy;
    var _lby2     = _cy + 20;
    if (!_hide_import && _asset.type != "LOAD_ORG" && _asset.type != "LOAD_REU"
	&& _asset.type != "META_TILESET" && _asset.type != "BITMAP_BUILDER" 
	&& _asset.type != "MUSIC_MAKER"
	&& !(_asset.type == "BYTE_DATA" && variable_struct_exists(_asset.meta, "is_save_file") && _asset.meta.is_save_file)) {
        var _lb_hover = point_in_rectangle(_mx, _my, _lbx1, _lby1, _lbx2, _lby2);
        draw_set_color(_lb_hover ? make_color_rgb(80, 200, 80) : make_color_rgb(30, 90, 40));
        draw_rectangle(_lbx1, _lby1, _lbx2, _lby2, false);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_lbx1 + 50, _lby1 + 5, "IMPORT");
        draw_set_halign(fa_left);
        draw_set_color(_asset.file != "" ? c_lime : make_color_rgb(100, 200, 120));
        draw_set_font(fnt_c64_tiny);
        draw_text(_lbx2 + 580, _lby1 + 5,
                  _asset.file != "" ? filename_name(_asset.file) : "CUSTOM: " + _asset.name);
        if (_asset.type == "SPRITE_SET" &&
            variable_struct_exists(_asset.meta, "has_colour") &&
            !_asset.meta.has_colour) {
            draw_set_color(c_orange);
            draw_text(_lbx2 + 10, _lby1 + 16, "! BINARY: NO COLOUR DATA");
        }
    }
    _cy += 28;

    // META INFO ROW (address editable). BITMAP_BUILDER is an internal authoring
    // asset with no C64 payload — suppress the label entirely rather than
    // showing an empty field.
    draw_set_font(fnt_c64_tiny);
    if (_asset.type != "BITMAP_BUILDER" && _asset.type != "MUSIC_MAKER") {
        draw_set_color(c_ltgray); draw_text(_vx1 + 10, _cy, "ADDRESS:");
    }

    if (editing_address && editing_address_idx == viewer_asset) {
        draw_set_color(make_color_rgb(20, 50, 30));
        draw_rectangle(_vx1 + 74, _cy - 1, _vx1 + 162, _cy + 13, false);
        draw_set_color(c_lime);
        var _blink = ((current_time mod 600) < 300) ? "_" : " ";
        draw_text(_vx1 + 78, _cy, editing_addr_string + _blink);
        draw_set_color(c_gray);
        draw_text(_vx1 + 170, _cy, "ENTER TO CONFIRM");
    } else if (_asset.type == "LOAD_ORG" || _asset.type == "LOAD_REU" || _asset.type == "BITMAP_BUILDER" || _asset.type == "MUSIC_MAKER") {
        // LOAD_ORG is a manifest — no meaningful load address. BITMAP_BUILDER
        // and SOUND_EDITOR are internal-only; their emitted BYTE_DATA/TEXT_DATA
        // assets hold the real addresses. Show a dash, no hover/edit affordance.
        draw_set_color(make_color_rgb(90, 90, 110));
        draw_text(_vx1 + 80, _cy, "--");
    } else {
        var _ah = string_upper(decimal_to_hex(_asset.address));
        while (string_length(_ah) < 4) _ah = "0" + _ah;
        var _addr_v_hover = point_in_rectangle(_mx, _my, _vx1 + 74, _cy - 1, _vx1 + 162, _cy + 13);
        draw_set_color(_addr_v_hover ? c_white : c_aqua);
        draw_text(_vx1 + 80, _cy, "$" + _ah);
        if (_addr_v_hover) {
            draw_set_color(make_color_rgb(60, 60, 80));
            draw_rectangle(_vx1 + 74, _cy - 1, _vx1 + 131, _cy + 15, true);
            draw_set_color(c_gray);
            draw_text(_vx1 + 132, _cy-1, "< EDIT");
        }
    }
if (variable_struct_exists(_asset.meta, "source_file") && _asset.meta.source_file != "" && _asset.type != "BITMAP") {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 230, 100));
        draw_text(_vx1 + 240, _vy1 + 44, "SOURCE:");
        draw_set_color(make_color_rgb(140, 140, 240));
        draw_text(_vx1 + 300, _vy1 + 44, _asset.meta.source_file);
    }
	
    if (_asset.type == "SPRITE_SET" && variable_struct_exists(_asset.meta, "format")) {
        draw_set_color(c_ltgray); draw_text(_vx1 + 150, _cy, "FORMAT:");
        draw_set_color(c_yellow); draw_text(_vx1 + 220, _cy, string_upper(_asset.meta.format));
        if (variable_struct_exists(_asset.meta, "used_count")) {
            draw_set_color(c_ltgray); draw_text(_vx1 + 320, _cy, "SPRITES:");
			
			var _end_loc = _asset.address + (_asset.meta.used_count * 64) - 1;
			var _end_hex = string_upper(decimal_to_hex(_end_loc));
			while (string_length(_end_hex) < 4) _end_hex = "0" + _end_hex;

			draw_set_color(c_white);
			draw_text(_vx1 + 390, _cy, string(_asset.meta.used_count) + "   END LOCATION (To): spr  $" + _end_hex);
           // draw_set_color(c_white);  draw_text(_vx1 + 390, _cy, string(_asset.meta.used_count) + " End Loc: ");
        }
    }
    _cy += 20;

// TYPE-SPECIFIC CONTENT
var _chr_surf_key = "";
switch (_asset.type) {

case "VECTOR_BITMAP": {
    scr_vbmp_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my);
} break;

case "BITMAP_BUILDER": {
    // _vx1 is already 30 for this type (set in the viewer block above), so the
    // editor's internals travel with the panel — no extra offset here.
    scr_bitmap_builder_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my);
} break;

case "MUSIC_MAKER": {
    // Same wide-panel treatment as BITMAP_BUILDER — _vx1 is already 30 here.
    scr_sound_editor_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my);
} break;
		
case "CHAR_SET": {
    // Rebuild all three charset surfaces if any are lost (F11 / surface loss)
    var _chr_needs_rebuild = false;
    if (variable_struct_exists(_asset.meta, "preview_surf") && !surface_exists(_asset.meta.preview_surf)) _chr_needs_rebuild = true;
    if (variable_struct_exists(_asset.meta, "preview_surf_clean") && !surface_exists(_asset.meta.preview_surf_clean)) _chr_needs_rebuild = true;
    if (variable_struct_exists(_asset.meta, "preview_surf_mc") && !surface_exists(_asset.meta.preview_surf_mc)) _chr_needs_rebuild = true;
    if (_chr_needs_rebuild && buffer_exists(_asset.buffer)) {
        scr_asset_chr_build_preview(_asset);
		
    } else if (_chr_needs_rebuild && _asset.file != "") {
        scr_asset_chr_reload(_asset);
    }

    if (!variable_struct_exists(_asset.meta, "rows")) {
        _asset.meta.rows = buffer_exists(_asset.buffer) ? (buffer_get_size(_asset.buffer) div 128) : 1;
        if (_asset.meta.rows < 1) { _asset.meta.rows = 1; }
    }
    if (!variable_struct_exists(_asset.meta, "char_count")) {
        _asset.meta.char_count = _asset.meta.rows * 16;
    }

    var _chr_mc = _asset.meta.mc_mode;
    if (_chr_mc == 2 && chr_edit_idx >= 64) {
        chr_edit_idx = chr_edit_idx mod 64;
    }

    // ---- BUTTONS ROW (_vy1+38 already set as _lby1 for LOAD FILE) ----
    // [+] ADD TILE
    var _atbx1 = _vx1 + 120;
    var _atbx2 = _atbx1 + 100;
    var _atby1 = _vy1 + 38;
    var _atby2 = _atby1 + 20;
    var _athov = point_in_rectangle(_mx, _my, _atbx1, _atby1, _atbx2, _atby2);
    draw_set_color(_athov ? make_color_rgb(100, 100, 255) : make_color_rgb(40, 40, 120));
    draw_rectangle(_atbx1, _atby1, _atbx2, _atby2, false);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_atbx1 + 50, _atby1 + 5, "[+] ADD ROW");
    draw_set_halign(fa_left);

    if (_athov && mouse_check_button_pressed(mb_left) && _asset.meta.rows < 16) {
        scr_chr_undo_push_full(_asset);
        _asset.meta.rows      += 1;
        _asset.meta.char_count = _asset.meta.rows * 16;
        var _new_size          = _asset.meta.char_count * 8;
        var _expanded          = buffer_create(_new_size, buffer_fixed, 1);
        var _old_size          = buffer_get_size(_asset.buffer);
        buffer_copy(_asset.buffer, 0, _old_size, _expanded, 0);
        // Zero-fill the new row bytes
        for (var _bi = _old_size; _bi < _new_size; _bi++) {
            buffer_poke(_expanded, _bi, buffer_u8, 0);
        }
        buffer_delete(_asset.buffer);
        _asset.buffer          = _expanded;
        _asset.meta.is_dirty   = true;
        scr_asset_chr_build_preview(_asset);
    }
	
// [-] REMOVE ROW — row below [+] ADD ROW
    var _rtbx1 = _atbx1;
    var _rtbx2 = _atbx2;
    var _rtby1 = _atby1 + 26;
    var _rtby2 = _atby2 + 26;
    var _rthov = point_in_rectangle(_mx, _my, _rtbx1, _rtby1, _rtbx2, _rtby2);

    draw_set_color(_rthov ? make_color_rgb(200, 60, 60) : make_color_rgb(100, 30, 30));
    draw_rectangle(_rtbx1, _rtby1, _rtbx2, _rtby2, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_rtbx1 + 50, _rtby1 + 5, "[-] REM ROW");
    draw_set_halign(fa_left);

    if (_rthov && mouse_check_button_pressed(mb_left)) {
        if (_asset.meta.rows > 1) {
            scr_chr_undo_push_full(_asset);
            _asset.meta.rows       -= 1;
            _asset.meta.char_count  = _asset.meta.rows * 16;
            var _new_size           = _asset.meta.char_count * 8;
            var _trimmed            = buffer_create(_new_size, buffer_fixed, 1);
            buffer_copy(_asset.buffer, 0, _new_size, _trimmed, 0);
            buffer_delete(_asset.buffer);
            _asset.buffer           = _trimmed;
            _asset.meta.is_dirty    = true;
            scr_asset_chr_build_preview(_asset);
        }
    }

    // [!] COPY CHAR ROM — to the right of [+] ADD ROW
    var _crbx1 = _atbx2 + 10;
    var _crbx2 = _crbx1 + 100;
    var _crby1 = _atby1;
    var _crby2 = _atby2;
    var _crhov = point_in_rectangle(_mx, _my, _crbx1, _crby1, _crbx2, _crby2);

    draw_set_color(_crhov ? make_color_rgb(200, 80, 80) : make_color_rgb(120, 40, 40));
    draw_rectangle(_crbx1, _crby1, _crbx2, _crby2, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_crbx1 + 50, _crby1 + 5, "COPY ROM");
    draw_set_halign(fa_left);

    if (_crhov && mouse_check_button_pressed(mb_left)) {
        scr_chr_undo_push_full(_asset);
        var _rom = scr_get_c64_char_rom();
        var _len = array_length(_rom);
        if (buffer_exists(_asset.buffer)) {
            if (buffer_get_size(_asset.buffer) < _len) {
                buffer_resize(_asset.buffer, _len);
            }
            buffer_seek(_asset.buffer, buffer_seek_start, 0);
            for (var _i = 0; _i < _len; _i++) {
                buffer_write(_asset.buffer, buffer_u8, _rom[_i]);
            }
            _asset.meta.rows       = 16;
            _asset.meta.char_count = 256;
            _asset.meta.is_dirty   = true;
            scr_asset_chr_build_preview(_asset);
        }
    }
	

    // ---- MODE TOGGLE (HR -> MC -> ECM -> HR) ----
    var _mcbx1  = _vx1 + 10;
    var _mcbx2  = _mcbx1 + 120;
    var _mcby1  = _cy;
    var _mcby2  = _cy + 18;
    var _mcbhov = point_in_rectangle(_mx, _my, _mcbx1, _mcby1, _mcbx2, _mcby2);
    var _mode_bg_cols  = [make_color_rgb(30, 30, 45), make_color_rgb(160, 80, 20), make_color_rgb(20, 80, 90)];
    var _mode_txt_cols = [make_color_rgb(80, 80, 100), make_color_rgb(255, 160, 60), make_color_rgb(80, 220, 240)];
    var _mode_labels   = ["HR MODE", "MC MODE", "ECM MODE"];
    draw_set_color(_mode_bg_cols[_chr_mc]);
    draw_rectangle(_mcbx1, _mcby1, _mcbx2, _mcby2, false);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(_mode_txt_cols[_chr_mc]);
    draw_set_halign(fa_center);
    draw_text(_mcbx1 + 60, _mcby1 + 4, _mode_labels[_chr_mc]);
    draw_set_halign(fa_left);
    if (_mcbhov && mouse_check_button_pressed(mb_left)) {
        _asset.meta.mc_mode = (_chr_mc + 1) mod 3;
        scr_asset_chr_build_preview(_asset);
		_asset.meta.is_dirty = true;
    }
    _cy += 24;

// ---- COLOUR PICKERS ----
	var _mc_fg_v   = _asset.meta.mc_fg;
    var _mc_bg_v   = _asset.meta.mc_bg;
    var _mc_col1_v = _asset.meta.mc_col1;
    var _mc_col2_v = _asset.meta.mc_col2;
    if (!variable_struct_exists(_asset.meta, "ecm_bg1")) _asset.meta.ecm_bg1 = 6;
    if (!variable_struct_exists(_asset.meta, "ecm_bg2")) _asset.meta.ecm_bg2 = 14;
    if (!variable_struct_exists(_asset.meta, "ecm_bg3")) _asset.meta.ecm_bg3 = 3;
    var _cp_sw     = 24;
    var _cp_gap    = 2;
    var _cp_labels, _cp_vals, _cp_fields;
    if (_chr_mc == 1) {
        _cp_labels = ["BG", "C1", "C2", "FG"];
        _cp_vals   = [_mc_bg_v, _mc_col1_v, _mc_col2_v, _mc_fg_v];
        _cp_fields = ["mc_bg", "mc_col1", "mc_col2", "mc_fg"];
    } else if (_chr_mc == 2) {
        _cp_labels = ["BG0", "BG1", "BG2", "BG3", "FG"];
        _cp_vals   = [_mc_bg_v, _asset.meta.ecm_bg1, _asset.meta.ecm_bg2, _asset.meta.ecm_bg3, _mc_fg_v];
        _cp_fields = ["mc_bg", "ecm_bg1", "ecm_bg2", "ecm_bg3", "mc_fg"];
    } else {
        _cp_labels = ["BG", "FG"];
        _cp_vals   = [_mc_bg_v, _mc_fg_v];
        _cp_fields = ["mc_bg", "mc_fg"];
    }
    var _cp_row_h  = _cp_sw + 6;
    draw_set_font(fnt_c64_tiny);
	
	// draw some instructions to the right:
	var _ins_x = _vx1 + 550;
	var _ins_y = _cy ;
	draw_set_color(c_ltgrey);
	draw_text(_ins_x,_ins_y,
	"INSTRUCTIONS:\n"+
	"\n"+
	"CTRL + Click / Drag to multi select\n"+
	"Delete or Backspace to clear selected\n"+
	"CTRL + C to COPY and CTRL + V to PASTE");
	// end instructions. Modfy for mac os
	
	
	
    var _cp_row_count = array_length(_cp_labels);
    var _cp_fg_row     = _cp_row_count - 1;
    for (var _cpi = 0; _cpi < _cp_row_count; _cpi++) {
        var _cp_row_y = _cy + _cpi * _cp_row_h;
        draw_set_color(make_color_rgb(120, 120, 160));
        draw_text(_vx1 + 10, _cp_row_y + 6, _cp_labels[_cpi] + ":");
        for (var _si = 0; _si < 16; _si++) {
            var _sx1  = _vx1 + 44 + _si * (_cp_sw + _cp_gap);
            var _shov = point_in_rectangle(_mx, _my, _sx1, _cp_row_y, _sx1 + _cp_sw, _cp_row_y + _cp_sw);
            
            draw_set_color(scr_c64_pepto_colour(_si));
            
            // Dim colours 8-15 for the FG row in MC mode (C64 hardware limitation)
            if (_chr_mc == 1 && _cpi == _cp_fg_row && _si >= 8) draw_set_alpha(0.3);
            else draw_set_alpha(1.0);
            
            draw_rectangle(_sx1, _cp_row_y, _sx1 + _cp_sw, _cp_row_y + _cp_sw, false);
            draw_set_alpha(1.0); // Reset alpha

            if (_cp_vals[_cpi] == _si) {
                draw_set_color(c_white);
                draw_rectangle(_sx1, _cp_row_y, _sx1 + _cp_sw, _cp_row_y + _cp_sw, true);
            }
            if (_shov && mouse_check_button_pressed(mb_left)) {
                var _val = _si;
                
                // Wrap FG colour to 0-7 if in MC mode
                if (_chr_mc == 1 && _cpi == _cp_fg_row && _val >= 8) {
                    _val -= 8;
                }
                
                variable_struct_set(_asset.meta, _cp_fields[_cpi], _val);
                // Picking a colour for this row also selects it as the active
                // paint swatch (MC: bit-pair index; ECM: BG slot/FG target).
                if (_chr_mc == 1) {
                    chr_active_mc_colour = _cpi;
                } else if (_chr_mc == 2) {
                    if (_cpi < 4) {
                        chr_active_ecm_bg     = _cpi;
                        chr_active_ecm_target = "BG";
                    } else {
                        chr_active_ecm_target = "FG";
                    }
                }
                scr_asset_chr_build_preview(_asset);
                with (obj_c64_node) {
                    if (node_type == "MACRO_CHR" &&
                        array_length(instructions[0]) > 1 &&
                        string(instructions[0][1]) == _asset.name)
                        scr_macro_chr_sync(id);
                }
            }
        }
    }
    _cy += _cp_row_count * _cp_row_h + 8;

    // Surface key for grid drawn after REFERENCED BY
    var _use_mc_surf  = (_chr_mc == 1) &&
                        variable_struct_exists(_asset.meta, "preview_surf_mc") &&
                        surface_exists(_asset.meta.preview_surf_mc);
    var _chr_surf_key = _use_mc_surf ? "preview_surf_mc" : "preview_surf";



// ---- INLINE PIXEL EDITOR (top-right) ----
    // MC/HR toggle for the tile editor
var _ted_x1  = _vx2 - 220;
    var _ted_x2  = _ted_x1 + 80;
      var _ted_y1  = _vy1 + 206;
    var _ted_y2  = _vy1 + 220;
    var _tedhov  = point_in_rectangle(_mx, _my, _ted_x1, _ted_y1, _ted_x2, _ted_y2);
    var _ted_bg_cols  = [make_color_rgb(30, 30, 45), make_color_rgb(160, 80, 20), make_color_rgb(20, 80, 90)];
    var _ted_txt_cols = [make_color_rgb(80, 80, 100), make_color_rgb(255, 160, 60), make_color_rgb(80, 220, 240)];
    var _ted_labels   = ["HR MODE", "MC MODE", "ECM MODE"];
    draw_set_color(_ted_bg_cols[_chr_mc]);
    draw_rectangle(_ted_x1, _ted_y1, _ted_x2, _ted_y2, false);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(_ted_txt_cols[_chr_mc]);
    draw_set_halign(fa_center);
    draw_text(_ted_x1 + 40, _ted_y1 -1, _ted_labels[_chr_mc]);
    draw_set_halign(fa_left);
    if (_tedhov && mouse_check_button_pressed(mb_left)) {
        _asset.meta.mc_mode = (_chr_mc + 1) mod 3;
        scr_asset_chr_build_preview(_asset);
		_asset.meta.is_dirty = true;
    }
    scr_chr_editor_draw(_asset, _vx2 - 220, _vy1 + 38, _chr_mc);
} break;	

	
case "MAP_DATA": {
    var _m = _asset.meta;

    // Init global tile store bank
    if (!variable_global_exists("map_tile_bank")) {
        global.map_tile_bank     = [];
        global.map_tile_bank_sel = -1;
    }

    // CREATE button
    var _crbx1  = _vx1 + 120;
    var _crbx2  = _crbx1 + 80;
    var _crby1  = _vy1 + 38;
    var _crby2  = _crby1 + 20;
    var _crbhov = point_in_rectangle(_mx, _my, _crbx1, _crby1, _crbx2, _crby2);
    draw_set_color(_crbhov ? make_color_rgb(60, 180, 200) : make_color_rgb(20, 70, 90));
    draw_rectangle(_crbx1, _crby1, _crbx2, _crby2, false);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_crbx1 + 40, _crby1 + 5, "CREATE");
    draw_set_halign(fa_left);

    if (_crbhov && mouse_check_button_pressed(mb_left)) {
        var _input_cr = get_string("New map dimensions (e.g. 40,25 or 40x25):", "40,25");
        if (_input_cr == "") { /* cancelled */ } else {
        var _gw = 40;
        var _gh = 25;
        var _sep_cr = ",";
        if (string_count("x", string_lower(_input_cr)) > 0 && string_count(",", _input_cr) == 0) {
            if (string_count("X", _input_cr) > 0) {
                _sep_cr = "X";
            } else {
                _sep_cr = "x";
            }
        }
        var _parts_cr = string_split(_input_cr, _sep_cr);
        if (array_length(_parts_cr) >= 2) {
            _gw = clamp(real(string_digits(_parts_cr[0])), 1, 160);
            _gh = clamp(real(string_digits(_parts_cr[1])), 1, 160);
        }
        _asset.meta.map_w          = _gw;
        _asset.meta.map_h          = _gh;
        _asset.meta.grid_w         = _gw;
        _asset.meta.grid_h         = _gh;
        _asset.meta.char_grid      = array_create(_gw * _gh, 0);
        _asset.meta.colour_grid    = array_create(_gw * _gh, 1);
        _asset.meta.override_grid  = array_create(_gw * _gh, 0);
        _asset.meta.sel_grid       = array_create(_gw * _gh, 0);
        _asset.meta.stamp_data     = [];
        _asset.meta.stamp_active   = false;
        _asset.meta.active_char    = 0;
        _asset.meta.active_colour  = 1;
        _asset.meta.zoom           = 2;
        _asset.meta.scroll_x       = 0;
        _asset.meta.scroll_y       = 0;
        _asset.meta.show_grid      = true;
        _asset.meta.paint_mc       = 0;
        _asset.meta.map_mc_bg      = -1;
        _asset.meta.map_mc_col1    = -1;
        _asset.meta.map_mc_col2    = -1;
        _asset.meta.char_strip_offset = 0;
        _asset.meta.chr_asset      = "";

        scr_asset_map_flush(_asset);
        global.undo_dirty = true;
        } // end else (input not cancelled)
    }
		    if (!variable_struct_exists(_m, "char_grid")) {
		        draw_set_color(make_color_rgb(40, 40, 60));
		        draw_rectangle(_vx1 + 10, _cy, _vx2 - 10, _cy + 60, false);
		        draw_set_font(fnt_c64_tiny);
		        draw_set_color(make_color_rgb(80, 80, 80));
		        draw_set_halign(fa_center);
		        draw_text(_vx1 + _vw * 0.5, _cy + 22, "NO MAP  —  CLICK LOAD FILE OR CREATE");
		        draw_set_halign(fa_left);
		        _cy += 70;
		        break;
		    }
			


		    var _mw = max(_m.map_w, 40); // lower bound kept (viewport-width floor); the old
		                                 // 216 upper clamp is gone — MACRO_SCROLL now auto-
		                                 // switches to 16-bit column indexing above 255 wide.
		    var _mh = _m.map_h;

		    // ---- INFO ROW ----
		    draw_set_font(fnt_c64_tiny);
var _gw = variable_struct_exists(_m, "grid_w") ? _m.grid_w : _mw;
var _gh = variable_struct_exists(_m, "grid_h") ? _m.grid_h : _mh;


		// Retrofit selection grid for existing maps
		    if (!variable_struct_exists(_m, "sel_grid") || array_length(_m.sel_grid) != _gw * _gh) {
		        _m.sel_grid = array_create(_gw * _gh, 0);
		        _m.stamp_data = [];
		        _m.stamp_active = false;
		    }
//show_debug_message("MAP DEBUG: map_w=" + string(_mw) + " map_h=" + string(_mh) + " grid_w=" + string(_gw) + " grid_h=" + string(_gh) + " char_grid_len=" + string(array_length(_m.char_grid)));
		    draw_set_font(fnt_c64_tiny);
		    draw_set_color(c_ltgray);
		    draw_text(_vx1 + 240, _vy1 + 40, "MAP SIZE:");

		    // Editable W
		    var _wbx1 = _vx1 + 238;
		    var _wbx2 = _wbx1 + 26;
			
var _map_row_y = _vy1 + 58;
    var _whov = point_in_rectangle(_mx, _my, _wbx1, _map_row_y - 1, _wbx2, _map_row_y + 13);
    draw_set_color(_whov ? make_color_rgb(40, 80, 60) : make_color_rgb(20, 35, 25));
    draw_rectangle(_wbx1, _map_row_y - 1, _wbx2, _map_row_y + 13, false);
    if (editing_map_dim && editing_map_field == "W" && editing_map_asset_idx == viewer_asset) {
        draw_set_color(c_lime);
        draw_text(_wbx1 + 2, _map_row_y, editing_map_string + ((current_time mod 600 < 300) ? "_" : ""));
    } else {
        draw_set_color(_whov ? c_white : c_aqua);
        draw_text(_wbx1 + 2, _map_row_y, string(_mw));
    }

    draw_set_color(c_ltgray);
    draw_text(_wbx2 + 2, _map_row_y, "x");

    // Editable H
    var _hbx1 = _wbx2 + 12;
    var _hbx2 = _hbx1 + 36;
    var _hhov = point_in_rectangle(_mx, _my, _hbx1, _map_row_y - 1, _hbx2, _map_row_y + 13);
    draw_set_color(_hhov ? make_color_rgb(40, 80, 60) : make_color_rgb(20, 35, 25));
    draw_rectangle(_hbx1, _map_row_y - 1, _hbx2, _map_row_y + 13, false);
    if (editing_map_dim && editing_map_field == "H" && editing_map_asset_idx == viewer_asset) {
        draw_set_color(c_lime);
        draw_text(_hbx1 + 2, _map_row_y, editing_map_string + ((current_time mod 600 < 300) ? "_" : ""));
    } else {
        draw_set_color(_hhov ? c_white : c_aqua);
        draw_text(_hbx1 + 2, _map_row_y, string(_mh));
    }

    draw_set_color(c_ltgray);
    draw_text(_hbx2 + 6, _map_row_y, "(" + string(_mw * _mh) + " CELLS)");
    if (_gw != _mw || _gh != _mh) {
        draw_set_color(make_color_rgb(100, 100, 60));
        draw_text(_hbx2 + 100, _map_row_y, "PHYS: " + string(_gw) + "x" + string(_gh));
    }
    // Click detection for W and H fields
    if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
        if (_whov) {
            editing_map_dim       = true;
            editing_map_field     = "W";
            editing_map_string    = string(_mw);
            editing_map_asset_idx = viewer_asset;
            keyboard_string = "";
        } else if (_hhov) {
            editing_map_dim       = true;
            editing_map_field     = "H";
            editing_map_string    = string(_mh);
            editing_map_asset_idx = viewer_asset;
            keyboard_string = "";
        }
    }

draw_set_color(c_ltgray);
    draw_text(_vx1 + 200, _cy, "   CHARSET:");
    var _chr_name = variable_struct_exists(_m, "chr_asset") ? _m.chr_asset : "";
    var _cpbx1  = _vx1 + 274;
    var _cpbx2  = _cpbx1 + 130;
    var _cpby1  = _cy - 1;
    var _cpby2  = _cy + 13;
    // Store exact Y for Step click detection
    map_chr_btn_y         = _cpby1;
    map_chr_picker_draw_y = _cpby1 + 16;


		    var _cpbhov = point_in_rectangle(_mx, _my, _cpbx1, _cpby1, _cpbx2, _cpby2);
		    draw_set_color(_cpbhov ? make_color_rgb(40, 80, 60) : make_color_rgb(20, 35, 25));
		    draw_rectangle(_cpbx1, _cpby1, _cpbx2, _cpby2, false);
		    draw_set_color(_chr_name != "" ? c_lime : make_color_rgb(150, 150, 150));
		    draw_text(_cpbx1 + 10, _cy-2, _chr_name != "" ? _chr_name : "-- PICK --");

		    // ---- TILE STORE BANK ----
		    var _bank_max   = 128;
		    var _bank_sh    = 14;
		    var _bank_ox    = _cpbx2 + 10;
		    var _bank_oy    = _cpby1;
		    var _bank_count = array_length(global.map_tile_bank);

		    // STORE button
		    var _has_stamp  = variable_struct_exists(_m, "stamp_data") && array_length(_m.stamp_data) > 0;
		    var _stbx1      = _bank_ox;
		    var _stbx2      = _stbx1 + 38;
		    var _stbhov     = point_in_rectangle(_mx, _my, _stbx1, _bank_oy, _stbx2, _bank_oy + _bank_sh);
		    draw_set_color(_has_stamp ? (_stbhov ? make_color_rgb(220, 180, 30) : make_color_rgb(120, 90, 10)) : make_color_rgb(35, 35, 35));
		    draw_rectangle(_stbx1, _bank_oy, _stbx2, _bank_oy + _bank_sh, false);
		    draw_set_font(fnt_c64_tiny);
		    draw_set_color(_has_stamp ? c_white : make_color_rgb(70, 70, 70));
		    draw_set_halign(fa_center);
		    draw_text(_stbx1 + 19, _bank_oy , "STORE");
			draw_text(_stbx1 + 16, _bank_oy + 20, "MAX:6x6");
			draw_text(_stbx1 + 6, _bank_oy + 38, "TILES EACH");
		    draw_set_halign(fa_left);
		    if (_has_stamp && _stbhov && mouse_check_button_pressed(mb_left)) {
		        var _bnd_w = 0, _bnd_h = 0;
		        for (var _si = 0; _si < array_length(_m.stamp_data); _si++) {
		            _bnd_w = max(_bnd_w, _m.stamp_data[_si].dx + 1);
		            _bnd_h = max(_bnd_h, _m.stamp_data[_si].dy + 1);
		        }
		        var _new_slot = { stamp_data: [], bnd_w: _bnd_w, bnd_h: _bnd_h };
		        for (var _si = 0; _si < array_length(_m.stamp_data); _si++) {
		            var _sd = _m.stamp_data[_si];
		            array_push(_new_slot.stamp_data, { dx: _sd.dx, dy: _sd.dy, char: _sd.char, col: _sd.col, ov: _sd.ov });
		        }
		 
		        if (_bank_count >= _bank_max) array_delete(global.map_tile_bank, 0, 1);
		        array_push(global.map_tile_bank, _new_slot);
		        global.map_tile_bank_sel = array_length(global.map_tile_bank) - 1;
		        _bank_count = array_length(global.map_tile_bank);

		        // Auto-scroll to the row containing the new slot only if it's out of view
		        var _scan_strip_x1 = _stbx2 + 4;
		        var _scan_strip_x2 = _vx2 - 230;
		        var _scan_x   = _scan_strip_x1;
		        var _scan_row = 0;
		        for (var _scan_i = 0; _scan_i < _bank_count; _scan_i++) {
		            var _scan_slot = global.map_tile_bank[_scan_i];
		            var _scan_tpx  = max(2, min(floor(min(128 / max(1, _scan_slot.bnd_w), 128 / max(1, _scan_slot.bnd_h))), 16));
		            var _scan_sw   = min(_scan_slot.bnd_w, 6) * _scan_tpx;
		            if (_scan_x + _scan_sw > _scan_strip_x2 - 22 && _scan_x > _scan_strip_x1) {
		                _scan_row++;
		                _scan_x = _scan_strip_x1;
		            }
		            if (_scan_i == global.map_tile_bank_sel) {

		                if (_scan_row >= global.map_tile_bank_scroll + 3) {
		                    global.map_tile_bank_scroll = _scan_row - 3 + 1;
		                }
		                break;
		            }
		            _scan_x += _scan_sw + 4;
		        }
		    }

		   

		    // Init bank scroll offset
		    if (!variable_global_exists("map_tile_bank_scroll")) global.map_tile_bank_scroll = 0;

		    // Resolve chr ref once for all slots
		    var _bchr = noone;
		    if (_chr_name != "") {
		        for (var _cai = 0; _cai < ds_list_size(asset_list); _cai++) {
		            var _ca3 = ds_list_find_value(asset_list, _cai);
		            if (_ca3.type == "CHAR_SET" && _ca3.name == _chr_name) { _bchr = _ca3; break; }
		        }
		    }
		    var _bbg = (variable_struct_exists(_m, "map_mc_bg") && _m.map_mc_bg >= 0) ? _m.map_mc_bg
		             : ((_bchr != noone && variable_struct_exists(_bchr.meta, "mc_bg")) ? _bchr.meta.mc_bg : 0);

		
		    // Bank strip layout
		    var _bank_strip_x1 = _stbx2 + 4;
		    var _bank_strip_x2 = _vx2 - 230;
		    var _bank_strip_w  = _bank_strip_x2 - _bank_strip_x1;
		    var _bank_row_h    = 100; // max slot height + gap
		    var _bank_vis_rows = 3;   // how many rows visible at once
		    var _bank_area_h   = _bank_vis_rows * _bank_row_h;

		    // Scissor the entire bank area
		    var _ssx = window_get_width()  / _gui_w;
		    var _ssy = window_get_height() / display_get_gui_height();
		    gpu_set_scissor(
		        floor((_bank_strip_x1 - 1) * _ssx),
		        floor((_bank_oy - 1) * _ssy),
		        ceil((_bank_strip_w + 1) * _ssx),
		        ceil((_bank_area_h + 1) * _ssy)
		    );

		    // Handle wheel scroll — scrolls by row
		    var _mouse_on_bank = point_in_rectangle(_mx, _my, _bank_strip_x1, _bank_oy, _bank_strip_x2, _bank_oy + _bank_area_h);
		    if (_mouse_on_bank) {
		        if (mouse_wheel_up())   global.map_tile_bank_scroll = max(0, global.map_tile_bank_scroll - 1);
		        if (mouse_wheel_down()) global.map_tile_bank_scroll += 1;
		    }


		    // First pass — compute row heights
		    var _row_heights = array_create(128, 0);
		    var _pass_x    = _bank_strip_x1;
		    var _pass_row  = 0;
		    for (var _pi = 0; _pi < _bank_count; _pi++) {
		        var _ps     = global.map_tile_bank[_pi];
		        var _ptpx   = max(2, min(floor(min(128 / max(1, _ps.bnd_w), 128 / max(1, _ps.bnd_h))), 16));
		        var _psw    = min(_ps.bnd_w, 6) * _ptpx;
		        var _psh    = min(_ps.bnd_h, 6) * _ptpx;
		        if (_pass_x + _psw > _bank_strip_x2 - 22 && _pass_x > _bank_strip_x1) {
		            _pass_row++;
		            _pass_x = _bank_strip_x1;
		        }
		        _row_heights[_pass_row] = max(_row_heights[_pass_row], _psh);
		        _pass_x += _psw + 4;
		    }

		    // Build cumulative row Y offsets from actual heights
		    var _row_y_offsets = array_create(128, 0);
		    var _accum_y = 0;
		    for (var _ri = 0; _ri < 128; _ri++) {
		        _row_y_offsets[_ri] = _accum_y;
		        if (_row_heights[_ri] > 0) _accum_y += _row_heights[_ri] + 4;
		    }

		    // Second pass — layout and draw
		    var _cur_x    = _bank_strip_x1;
		    var _cur_row  = 0;

		    for (var _bi = 0; _bi < _bank_count; _bi++) {
		        var _bslot  = global.map_tile_bank[_bi];
		        var _tpx    = max(2, min(floor(min(128 / max(1, _bslot.bnd_w), 128 / max(1, _bslot.bnd_h))), 16));
		        var _sw     = min(_bslot.bnd_w, 6) * _tpx;
		        var _sh     = min(_bslot.bnd_h, 6) * _tpx;

		        // Wrap to next row if slot doesn't fit within the viewable strip width
		        if (_cur_x + _sw > _bank_strip_x2 - 22 && _cur_x > _bank_strip_x1) {
		            _cur_row++;
		            _cur_x  = _bank_strip_x1;
		        }

		        var _scroll_offset_y = _row_y_offsets[global.map_tile_bank_scroll];
		        var _bx1  = _cur_x;
		        var _bx2  = _bx1 + _sw;
		        var _by1  = _bank_oy + _row_y_offsets[_cur_row] - _scroll_offset_y;
		        var _by2  = _by1 + _sh;

		        _cur_x   += _sw + 4;

		        // Skip rows above scroll
		        if (_cur_row < global.map_tile_bank_scroll) continue;
		        // Stop rows below visible area
		        if (_by1 >= _bank_oy + _bank_area_h) break;

		        var _bsel = (global.map_tile_bank_sel == _bi);
		        var _bhov = point_in_rectangle(_mx, _my, _bx1, _by1, _bx2, _by2);

		        draw_set_color(make_color_rgb(10, 10, 20));
		        draw_rectangle(_bx1, _by1, _bx2, _by2, false);
		        draw_set_color(_bsel ? make_color_rgb(80, 200, 80) : (_bhov ? c_white : make_color_rgb(60, 60, 80)));
		        draw_rectangle(_bx1, _by1, _bx2, _by2, true);
		        if (_bsel) {
		            // Extra 1px border for selected
		            draw_rectangle(_bx1 - 1, _by1 - 1, _bx2 + 1, _by2 + 1, true);
		        }

		        for (var _si = 0; _si < array_length(_bslot.stamp_data); _si++) {
		            var _sd  = _bslot.stamp_data[_si];
		            if (_sd.dx >= 6 || _sd.dy >= 6) continue;
		            var _tx  = _bx1 + _sd.dx * _tpx;
		            var _ty  = _by1 + _sd.dy * _tpx;

		            if (_bchr != noone && buffer_exists(_bchr.buffer)) {
		                var _ppw     = max(1, _tpx / 8);
		                var _pph     = max(1, _tpx / 8);
		                var _b_ov    = variable_struct_exists(_sd, "ov") ? _sd.ov : 0;
		                var _b_is_mc = (obj_workspace_manager.map_global_mixed == 1) && (_b_ov == 1);
		                draw_set_color(scr_c64_pepto_colour(_bbg));
		                draw_rectangle(_tx, _ty, _tx + _tpx, _ty + _tpx, false);
		                if (_b_is_mc) {
		                    var _b_col1 = (variable_struct_exists(_m, "map_mc_col1") && _m.map_mc_col1 >= 0) ? _m.map_mc_col1 : (variable_struct_exists(_bchr.meta, "mc_col1") ? _bchr.meta.mc_col1 : 1);
		                    var _b_col2 = (variable_struct_exists(_m, "map_mc_col2") && _m.map_mc_col2 >= 0) ? _m.map_mc_col2 : (variable_struct_exists(_bchr.meta, "mc_col2") ? _bchr.meta.mc_col2 : 2);
		                    var _b_pal  = [scr_c64_pepto_colour(_bbg), scr_c64_pepto_colour(_b_col1), scr_c64_pepto_colour(_b_col2), scr_c64_pepto_colour(_sd.col & 0x07)];
		                    var _b_pxw  = max(1, _tpx / 4);
		                    var _b_pxh  = max(1, _tpx / 8);
		                    for (var _sr = 0; _sr < 8; _sr++) {
		                        var _sboff = (_sd.char * 8) + _sr;
		                        if (_sboff >= buffer_get_size(_bchr.buffer)) break;
		                        var _sbyte = buffer_peek(_bchr.buffer, _sboff, buffer_u8);
		                        for (var _sp = 0; _sp < 4; _sp++) {
		                            var _sbits = (_sbyte >> (6 - _sp * 2)) & 0x03;
		                            if (_sbits == 0) continue;
		                            draw_set_color(_b_pal[_sbits]);
		                            draw_rectangle(_tx + _sp*_b_pxw, _ty + _sr*_b_pxh, _tx + _sp*_b_pxw + _b_pxw, _ty + _sr*_b_pxh + _b_pxh, false);
		                        }
		                    }
		                } else {
		                    draw_set_color(scr_c64_pepto_colour(_sd.col & 0x0F));
		                    for (var _sr = 0; _sr < 8; _sr++) {
		                        var _sboff = (_sd.char * 8) + _sr;
		                        if (_sboff >= buffer_get_size(_bchr.buffer)) break;
		                        var _sbyte = buffer_peek(_bchr.buffer, _sboff, buffer_u8);
		                        for (var _sb = 0; _sb < 8; _sb++) {
		                            if (_sbyte & (0x80 >> _sb))
		                                draw_rectangle(_tx+_sb*_ppw, _ty+_sr*_pph, _tx+_sb*_ppw+_ppw, _ty+_sr*_pph+_pph, false);
		                        }
		                    }
		                }
		            } else {
		                draw_set_color(scr_c64_pepto_colour(_sd.col));
		                draw_rectangle(_tx, _ty, _tx + _tpx, _ty + _tpx, false);
		            }
		        }

		        if (_bhov && mouse_check_button_pressed(mb_left)) {
		            global.map_tile_bank_sel = _bi;
		            _m.stamp_data = [];
		            for (var _si = 0; _si < array_length(_bslot.stamp_data); _si++) {
		                var _sd = _bslot.stamp_data[_si];
		                array_push(_m.stamp_data, { dx: _sd.dx, dy: _sd.dy, char: _sd.char, col: _sd.col, ov: _sd.ov });
		            }
		            _m.stamp_active = true;
		            var _sgw = variable_struct_exists(_m, "grid_w") ? _m.grid_w : _m.map_w;
		            var _sgh = variable_struct_exists(_m, "grid_h") ? _m.grid_h : _m.map_h;
		            _m.sel_grid = array_create(_sgw * _sgh, 0);
		        }

		        if (_bhov && mouse_check_button_pressed(mb_right)) {
					 array_delete(global.map_tile_bank, _bi, 1);
		            if (global.map_tile_bank_sel >= array_length(global.map_tile_bank))
		                global.map_tile_bank_sel = array_length(global.map_tile_bank) - 1;
		            break;
		        }
		    }

		  
		    gpu_set_scissor(0, 0, window_get_width(), window_get_height());

		    // Scroll indicator arrows
		    if (_bank_count > 0) {
		        var _arr_x = _bank_strip_x2 -20;
		        var _arr_y = _bank_oy;
		        draw_set_font(fnt_c64_tiny);
		        var _up_hov = point_in_rectangle(_mx, _my, _arr_x, _arr_y, _arr_x + 18, _arr_y + 14);
		        draw_set_color(_up_hov ? c_white : (global.map_tile_bank_scroll > 0 ? make_color_rgb(160, 160, 200) : make_color_rgb(50, 50, 70)));
		        draw_rectangle(_arr_x, _arr_y, _arr_x + 18, _arr_y + 14, false);
		        draw_set_color(c_black);
		        draw_set_halign(fa_center);
		        draw_text(_arr_x + 9, _arr_y + 2, "^");
		        var _dn_hov = point_in_rectangle(_mx, _my, _arr_x, _arr_y + 16, _arr_x + 18, _arr_y + 30);
		        draw_set_color(_dn_hov ? c_white : make_color_rgb(160, 160, 200));
		        draw_rectangle(_arr_x, _arr_y + 16, _arr_x + 18, _arr_y + 30, false);
		        draw_set_color(c_black);
		        draw_text(_arr_x + 9, _arr_y + 18, "v");
		        draw_set_halign(fa_left);
		        if (_up_hov && mouse_check_button_pressed(mb_left))
		            global.map_tile_bank_scroll = max(0, global.map_tile_bank_scroll - 1);
		        if (_dn_hov && mouse_check_button_pressed(mb_left))
		            global.map_tile_bank_scroll += 1;
		    }

// ---- MC MODE TOGGLE (hidden when linked CHAR_SET is ECM) ----
	    // Early ECM check — _chr_asset_ref itself isn't resolved until further
	    // down, but this toggle draws first, so resolve just the mode bit here.
	    var _early_chr_ecm = false;
	    if (_chr_name != "") {
	        for (var _ecmi = 0; _ecmi < ds_list_size(asset_list); _ecmi++) {
	            var _ecma = ds_list_find_value(asset_list, _ecmi);
	            if (_ecma.type == "CHAR_SET" && _ecma.name == _chr_name) {
	                _early_chr_ecm = variable_struct_exists(_ecma.meta, "mc_mode") && (_ecma.meta.mc_mode == 2);
	                break;
	            }
	        }
	    }

	    // Per-asset mode: each MAP_DATA remembers its own HR-ONLY / MIXED state.
	    // Sync the global flag to THIS asset's stored mode while its viewer is open
	    // so the rest of the editor (which reads the global) matches what's saved.
	    if (!variable_struct_exists(_m, "map_mixed")) {
	        _m.map_mixed = obj_workspace_manager.map_global_mixed;
	    }
	    if (_early_chr_ecm) {
	        // ECM and MC are hardware-exclusive on the VIC-II — force HR-ONLY
	        // and skip the toggle entirely so the editor can't drift out of
	        // sync with what the compile chain actually emits.
	        _m.map_mixed = 0;
	    }
	    obj_workspace_manager.map_global_mixed = _m.map_mixed;
	    var _global_mixed = _m.map_mixed;
	    var _paint_mc = _m.paint_mc;

	    var _map_mc_raw = 0; // legacy unused
	    var _eff_mc     = _paint_mc; // swatch follows paint mode

	    if (_early_chr_ecm) {
	        draw_set_font(fnt_c64_tiny);
	        draw_set_color(make_color_rgb(80, 220, 240));
	        draw_text(_vx1 + 10, _cy + 3, "MODE: ECM");
	    } else {
	        var _gb_labels = ["HR ONLY", "MIXED"];
	        var _gb_cols   = [make_color_rgb(30,30,45), make_color_rgb(20,60,80)];
	        var _gb_tcols  = [make_color_rgb(80,80,100), make_color_rgb(80,200,255)];
	        var _gbx1  = _vx1 + 10;
	        var _gbx2  = _gbx1 + 90;
	        var _gby1  = _cy;
	        var _gby2  = _cy + 16;
	        var _gbhov = point_in_rectangle(_mx, _my, _gbx1, _gby1, _gbx2, _gby2);
	        draw_set_color(_gb_cols[_global_mixed]);
	        draw_rectangle(_gbx1, _gby1, _gbx2, _gby2, false);
	        draw_set_font(fnt_c64_tiny);
	        draw_set_color(_gb_tcols[_global_mixed]);
	        draw_text(_gbx1 + 45, _gby1 + 3, _gb_labels[_global_mixed]);
	        draw_set_halign(fa_left);
		if (_gbhov && mouse_check_button_pressed(mb_left)) {
	        _m.map_mixed = (_global_mixed == 0) ? 1 : 0;
	        obj_workspace_manager.map_global_mixed = _m.map_mixed;
	        _m.is_dirty = true;
	    }

	    // PAINT MODE button: only shown in MIXED mode
	    if (_global_mixed == 1) {
	        var _pb_labels = ["PAINT HR", "PAINT MC"];
	        var _pb_cols   = [make_color_rgb(30,30,45), make_color_rgb(160,80,20)];
	        var _pb_tcols  = [make_color_rgb(80,80,100), make_color_rgb(255,160,60)];
	        var _pbx1  = _gbx2 + 8;
	        var _pbx2  = _pbx1 + 90;
	        var _pby1  = _cy;
	        var _pby2  = _cy + 16;
	        var _pbhov = point_in_rectangle(_mx, _my, _pbx1, _pby1, _pbx2, _pby2);
	        draw_set_color(_pb_cols[_paint_mc]);
	        draw_rectangle(_pbx1, _pby1, _pbx2, _pby2, false);
	        draw_set_font(fnt_c64_tiny);
	        draw_set_color(_pb_tcols[_paint_mc]);
	        draw_set_halign(fa_center);
	        draw_text(_pbx1 + 45, _pby1 + 3, _pb_labels[_paint_mc]);
	        draw_set_halign(fa_left);
	        if (_pbhov && mouse_check_button_pressed(mb_left)) {
	            _m.paint_mc = (_paint_mc == 0) ? 1 : 0;
	        }
	    }
	 }
_cy += 22;

// Resolve charset ref early — needed for colour pickers and canvas
    var _chr_asset_ref = noone;
    if (_chr_name != "") {
        for (var _ci2 = 0; _ci2 < ds_list_size(asset_list); _ci2++) {
            var _ca2 = ds_list_find_value(asset_list, _ci2);
            if (_ca2.type == "CHAR_SET" && _ca2.name == _chr_name) {
                _chr_asset_ref = _ca2; break;
            }
        }
    }
    // Rebuild charset surfaces if lost (F11 / surface loss)
    if (_chr_asset_ref != noone && buffer_exists(_chr_asset_ref.buffer)) {
        if (!variable_struct_exists(_chr_asset_ref.meta, "rows")) {
            _chr_asset_ref.meta.rows = buffer_get_size(_chr_asset_ref.buffer) div 128;
            if (_chr_asset_ref.meta.rows < 1) _chr_asset_ref.meta.rows = 1;
        }
        if (!variable_struct_exists(_chr_asset_ref.meta, "char_count")) {
            _chr_asset_ref.meta.char_count = _chr_asset_ref.meta.rows * 16;
        }
        var _map_chr_needs_rebuild = false;
        if (variable_struct_exists(_chr_asset_ref.meta, "preview_surf") && !surface_exists(_chr_asset_ref.meta.preview_surf)) _map_chr_needs_rebuild = true;
        if (variable_struct_exists(_chr_asset_ref.meta, "preview_surf_clean") && !surface_exists(_chr_asset_ref.meta.preview_surf_clean)) _map_chr_needs_rebuild = true;
        if (variable_struct_exists(_chr_asset_ref.meta, "preview_surf_mc") && !surface_exists(_chr_asset_ref.meta.preview_surf_mc)) _map_chr_needs_rebuild = true;
        if (_map_chr_needs_rebuild) scr_asset_chr_build_preview(_chr_asset_ref);
    }

	    // ---- BG COLOUR PICKERS (ECM 4-way, or MC 3-way inherit-capable) ----
	    var _map_ecm_here = (_chr_asset_ref != noone) && variable_struct_exists(_chr_asset_ref.meta, "mc_mode") && (_chr_asset_ref.meta.mc_mode == 2);

	    // Declared here (not inside either branch) — the INLINE TILE EDITOR
	    // section further down reads these unconditionally to temporarily swap
	    // colours into the linked charset before calling scr_chr_editor_draw.
	    // For ECM these values are harmless placeholders: scr_chr_editor_draw's
	    // 1-bit pixel format never actually uses palette slots 1/2 (C1/C2).
	    var _disp_bg_v   = (_chr_asset_ref != noone) ? _chr_asset_ref.meta.mc_bg   : 0;
	    var _disp_col1_v = (_chr_asset_ref != noone) ? _chr_asset_ref.meta.mc_col1 : 1;
	    var _disp_col2_v = (_chr_asset_ref != noone) ? _chr_asset_ref.meta.mc_col2 : 2;

	    if (_map_ecm_here) {
	        // ECM: single set of 4 background registers, lives on the linked
	        // CHAR_SET (mc_bg/ecm_bg1-3) — no per-map override slot, since only
	        // one charset can be linked and ECM/MC are hardware-exclusive.
	        // Full 16-colour picker per BG row — same layout/style as the
	        // CHAR_SET ECM editor's BG0-3 swatch grid, click to set directly
	        // rather than cycling +1/-1.
	        var _ecm_labels_md = ["BG0", "BG1", "BG2", "BG3"];
	        var _ecm_fields_md = ["mc_bg", "ecm_bg1", "ecm_bg2", "ecm_bg3"];
	        var _ecm_sw_md     = 20;
	        var _ecm_gap_md    = 1;
	        var _ecm_cy_start  = _cy;
	        draw_set_font(fnt_c64_tiny);
	        for (var _ebi_md = 0; _ebi_md < 4; _ebi_md++) {
	            var _eby_md = _cy + _ebi_md * (_ecm_sw_md + 4);
	            draw_set_color(make_color_rgb(80, 80, 100));
	            draw_text(_vx1 + 10, _eby_md + 4, _ecm_labels_md[_ebi_md] + ":");
	            var _ebval_md = variable_struct_get(_chr_asset_ref.meta, _ecm_fields_md[_ebi_md]);
	            for (var _ebsi_md = 0; _ebsi_md < 16; _ebsi_md++) {
	                var _ebx1_md  = _vx1 + 44 + _ebsi_md * (_ecm_sw_md + _ecm_gap_md);
	                var _ebx2_md  = _ebx1_md + _ecm_sw_md;
	                var _ebhov_md = point_in_rectangle(_mx, _my, _ebx1_md, _eby_md, _ebx2_md, _eby_md + _ecm_sw_md);
	                draw_set_color(scr_c64_pepto_colour(_ebsi_md));
	                draw_rectangle(_ebx1_md, _eby_md, _ebx2_md, _eby_md + _ecm_sw_md, false);
	                if (_ebval_md == _ebsi_md) {
	                    draw_set_color(c_white);
	                    draw_rectangle(_ebx1_md, _eby_md, _ebx2_md, _eby_md + _ecm_sw_md, true);
	                }
	                if (_ebhov_md && mouse_check_button_pressed(mb_left)) {
	                    variable_struct_set(_chr_asset_ref.meta, _ecm_fields_md[_ebi_md], _ebsi_md);
	                    _chr_asset_ref.meta.is_dirty = true;
	                }
	            }
	        }

	        _cy += 4 * (_ecm_sw_md + 4) + 6;
	    } else {
	        var _ov_bg_v   = _m.map_mc_bg;
	        var _ov_col1_v = _m.map_mc_col1;
	        var _ov_col2_v = _m.map_mc_col2;
	        var _inh_bg   = (_chr_asset_ref != noone) ? _chr_asset_ref.meta.mc_bg   : 0;
	        var _inh_col1 = (_chr_asset_ref != noone) ? _chr_asset_ref.meta.mc_col1 : 1;
	        var _inh_col2 = (_chr_asset_ref != noone) ? _chr_asset_ref.meta.mc_col2 : 2;
	        _disp_bg_v   = (_ov_bg_v   >= 0) ? _ov_bg_v   : _inh_bg;
	        _disp_col1_v = (_ov_col1_v >= 0) ? _ov_col1_v : _inh_col1;
	        _disp_col2_v = (_ov_col2_v >= 0) ? _ov_col2_v : _inh_col2;
	        var _mc_pal_labels = ["BG", "C1", "C2"];
	        var _mc_pal_disp   = [_disp_bg_v, _disp_col1_v, _disp_col2_v];
	        var _mc_pal_fields = ["map_mc_bg", "map_mc_col1", "map_mc_col2"];
	        var _mc_sw  = 16;
	        var _mc_gap = 1;
	        draw_set_font(fnt_c64_tiny);
	        for (var _mpi = 0; _mpi < 3; _mpi++) {
	            var _mpy = _cy + _mpi * (_mc_sw + 4);
	            draw_set_color(make_color_rgb(80, 80, 100));
	            draw_text(_vx1 + 10, _mpy + 3, _mc_pal_labels[_mpi] + ":");
	            for (var _msi = 0; _msi < 16; _msi++) {
	                var _msx = _vx1 + 36 + _msi * (_mc_sw + _mc_gap);
	                var _mshov = point_in_rectangle(_mx, _my, _msx, _mpy, _msx + _mc_sw, _mpy + _mc_sw);
	                draw_set_color(scr_c64_pepto_colour(_msi));
	                draw_rectangle(_msx, _mpy, _msx + _mc_sw, _mpy + _mc_sw, false);
	                if (_mc_pal_disp[_mpi] == _msi) {
	                    draw_set_color(c_white);
	                    draw_rectangle(_msx, _mpy, _msx + _mc_sw, _mpy + _mc_sw, true);
	                }
	                if (_mshov && mouse_check_button_pressed(mb_left))
	                    variable_struct_set(_m, _mc_pal_fields[_mpi], _msi);
	                if (_mshov && mouse_check_button_pressed(mb_right))
	                    variable_struct_set(_m, _mc_pal_fields[_mpi], -1); // clear to inherit
	            }
	            // Show inherit indicator
	            if (variable_struct_get(_m, _mc_pal_fields[_mpi]) < 0) {
	                draw_set_color(make_color_rgb(60, 60, 80));
	                draw_text(_vx1 + 36 + 16 * (_mc_sw + _mc_gap) + 4, _mpy + 3, "CHR");
	            }
	        }
	        _cy += 3 * (_mc_sw + 4) + 6;
	    }

	    // resolve _chr_asset_ref early for colour pickers above
	    // (already resolved below too, safe to do here first)

// ---- ACTIVE SWATCH BAR ----
	    draw_set_font(fnt_c64_tiny);
	    draw_set_color(c_ltgray);
	    draw_text(_vx1 + 10, _cy + 3, "PAINT:");

		// Colour swatch
		    draw_set_color(scr_c64_pepto_colour(_m.active_colour));
		    draw_rectangle(_vx1 + 54, _cy + 2, _vx1 + 70, _cy + 14, false);
		    draw_set_color(c_white);
		    draw_rectangle(_vx1 + 54, _cy + 2, _vx1 + 70, _cy + 14, true);
		    draw_text(_vx1 + 74, _cy + 3, "COL " + string(_m.active_colour));

// Paint mode follows global — no secondary toggle needed
			
				

// Char swatch — _chr_asset_ref already resolved above
		    // Universal BG — resolved once, used by canvas, swatch and tile strip
		    var _global_bg = (_m.map_mc_bg >= 0) ? _m.map_mc_bg
	                   : ((_chr_asset_ref != noone) ? _chr_asset_ref.meta.mc_bg : 0);

		    // ---- ECM: 256 virtual slots (64 real chars x 4 BG bands) ----
		    // A virtual char index >= 64 is the same glyph as (index mod 64),
		    // rendered against a different VIC background register.
		    // char_grid / active_char keep storing the full 0-255 virtual index;
		    // only pixel lookups (mod 64) and background colour (div 64) differ.
		    var _map_ecm_mode    = (_chr_asset_ref != noone) && variable_struct_exists(_chr_asset_ref.meta, "mc_mode") && (_chr_asset_ref.meta.mc_mode == 2);
		    var _map_ecm_bg_cols = [
		        _global_bg,
		        (_chr_asset_ref != noone && variable_struct_exists(_chr_asset_ref.meta, "ecm_bg1")) ? _chr_asset_ref.meta.ecm_bg1 : 6,
		        (_chr_asset_ref != noone && variable_struct_exists(_chr_asset_ref.meta, "ecm_bg2")) ? _chr_asset_ref.meta.ecm_bg2 : 14,
		        (_chr_asset_ref != noone && variable_struct_exists(_chr_asset_ref.meta, "ecm_bg3")) ? _chr_asset_ref.meta.ecm_bg3 : 3
		    ];
			
			var _sw_x  = _vx1 + 210;
		    var _sw_sz = 42; // 3x bigger (was 14)
		    draw_set_color(scr_c64_pepto_colour(_global_bg));
		    draw_rectangle(_sw_x, _cy, _sw_x + _sw_sz, _cy + _sw_sz, false);
			var _pmc_sw = (_global_mixed == 1) ? _paint_mc : 0;
		    if (_chr_asset_ref != noone && buffer_exists(_chr_asset_ref.buffer) && _pmc_sw == 1) {
		        // MC direct render for swatch
				var _sw_res_bg   = _global_bg;
				var _sw_res_col1 = (_m.map_mc_col1 >= 0) ? _m.map_mc_col1 : _chr_asset_ref.meta.mc_col1;
		        var _sw_res_col2 = (_m.map_mc_col2 >= 0) ? _m.map_mc_col2 : _chr_asset_ref.meta.mc_col2;
		        var _sw_palette  = [
		            scr_c64_pepto_colour(_global_bg),
		            scr_c64_pepto_colour(_sw_res_col1),
		            scr_c64_pepto_colour(_sw_res_col2),
		            scr_c64_pepto_colour(_m.active_colour & 0x07)
		        ];
		        var _swpxw = max(1, _sw_sz / 4);
		        var _swpxh = max(1, _sw_sz / 8);
		        draw_set_color(_sw_palette[0]);
		        draw_rectangle(_sw_x, _cy, _sw_x + _sw_sz - 1, _cy + _sw_sz - 1, false);
		        for (var _swr = 0; _swr < 8; _swr++) {
		            var _swboff = (_m.active_char * 8) + _swr;
		            if (_swboff >= buffer_get_size(_chr_asset_ref.buffer)) break;
		            var _swbyte = buffer_peek(_chr_asset_ref.buffer, _swboff, buffer_u8);
		            for (var _swp = 0; _swp < 4; _swp++) {
		                var _swbits = (_swbyte >> (6 - _swp * 2)) & 0x03;
		                if (_swbits == 0) continue;
		                draw_set_color(_sw_palette[_swbits]);
		                draw_rectangle(_sw_x + _swp * _swpxw, _cy + _swr * _swpxh,
		                               _sw_x + _swp * _swpxw + _swpxw, _cy + _swr * _swpxh + _swpxh, false);
		            }
		        }
			} else if (_chr_asset_ref != noone &&
		        variable_struct_exists(_chr_asset_ref.meta, "preview_surf_clean") &&
		        surface_exists(_chr_asset_ref.meta.preview_surf_clean)) {
		        var _sw_real_char = _map_ecm_mode ? (_m.active_char mod 64) : _m.active_char;
		        var _sw_bg_col    = _map_ecm_mode ? scr_c64_pepto_colour(_map_ecm_bg_cols[_m.active_char div 64]) : scr_c64_pepto_colour(_global_bg);
		        // Fill BG first so surface tint blends correctly
				var _sw_hr_pxw = max(1, _sw_sz / 8);
		        var _sw_hr_pxh = max(1, _sw_sz / 8);
		        draw_set_color(_sw_bg_col);
		        draw_rectangle(_sw_x, _cy, _sw_x + _sw_sz - 1, _cy + _sw_sz - 1, false);
		        draw_set_color(scr_c64_pepto_colour(_m.active_colour));
		        for (var _swr2 = 0; _swr2 < 8; _swr2++) {
		            var _swboff2 = (_sw_real_char * 8) + _swr2;
		            if (_swboff2 >= buffer_get_size(_chr_asset_ref.buffer)) break;
		            var _swbyte2 = buffer_peek(_chr_asset_ref.buffer, _swboff2, buffer_u8);
		            for (var _swbit = 0; _swbit < 8; _swbit++) {
		                if (_swbyte2 & (0x80 >> _swbit)) {
		                    draw_rectangle(
		                        _sw_x + _swbit * _sw_hr_pxw, _cy + _swr2 * _sw_hr_pxh,
		                        _sw_x + _swbit * _sw_hr_pxw + _sw_hr_pxw - 1, _cy + _swr2 * _sw_hr_pxh + _sw_hr_pxh - 1,
		                        false);
		                }
		            }
		        }
		    } else {
		        draw_set_color(make_color_rgb(40, 40, 60));
		        draw_rectangle(_sw_x, _cy, _sw_x + _sw_sz, _cy + _sw_sz, false);
		    }
		    draw_set_color(c_white);
		    draw_rectangle(_sw_x, _cy, _sw_x + _sw_sz, _cy + _sw_sz, true);
		    draw_set_font(fnt_c64_tiny);
		    draw_set_color(c_white);
		    draw_text(_sw_x + _sw_sz + 4, _cy + 3, "CHR " + string(_m.active_char));
		    _cy += _sw_sz + 4;

// ---- INLINE TILE EDITOR (top-right, uses linked charset) ----
        if (_chr_asset_ref != noone) {
            // Sync tile editor to the active char being painted
            chr_edit_idx = _m.active_char;
            // Use paint_mc as the editor mode so it matches what's being painted
            var _map_ed_mc = (_global_mixed == 1) ? _paint_mc : 0;

            // Resolve map colour overrides — these are what the user sees on canvas
            // so the tile editor swatches must match them

            var _eff_bg   = _global_bg;
            var _eff_col1 = _disp_col1_v;
            var _eff_col2 = _disp_col2_v;

// Temporarily push resolved colours into charset meta so editor reads them
            var _save_bg   = _chr_asset_ref.meta.mc_bg;
            var _save_col1 = _chr_asset_ref.meta.mc_col1;
            var _save_col2 = _chr_asset_ref.meta.mc_col2;
            var _save_fg   = _chr_asset_ref.meta.mc_fg;
            _chr_asset_ref.meta.mc_bg   = _eff_bg;
            _chr_asset_ref.meta.mc_col1 = _eff_col1;
            _chr_asset_ref.meta.mc_col2 = _eff_col2;
            _chr_asset_ref.meta.mc_fg   = _m.active_colour;

            scr_chr_editor_draw(_chr_asset_ref, _vx2 - 220, _vy1 + 38, _map_ed_mc, false);

            // Restore original charset colours
            _chr_asset_ref.meta.mc_bg   = _save_bg;
            _chr_asset_ref.meta.mc_col1 = _save_col1;
            _chr_asset_ref.meta.mc_col2 = _save_col2;
            _chr_asset_ref.meta.mc_fg   = _save_fg;
        }

	    // ---- ZOOM BUTTONS ----
	    var _zoom   = _m.zoom;
		    var _btn_y  = _cy;
		    var _btn_bw = 28;
		    var _btn_bh = 18;

var _zmx1  = _vx2 - _btn_bw * 2 - 6;
	    var _zmhov = point_in_rectangle(_mx, _my, _zmx1, _btn_y, _zmx1 + _btn_bw, _btn_y + _btn_bh);
	    draw_set_color(_zmhov ? c_white : c_gray);
	    draw_rectangle(_zmx1, _btn_y, _zmx1 + _btn_bw, _btn_y + _btn_bh, true);
	    draw_set_halign(fa_center);
	    draw_text(_zmx1 + _btn_bw * 0.5, _btn_y + 3, "Z-");
	    if (_zmhov && mouse_check_button_pressed(mb_left)) _m.zoom = max(1, _zoom - 1);

	    var _zpx1  = _vx2 - _btn_bw - 2;
	    var _zphov = point_in_rectangle(_mx, _my, _zpx1, _btn_y, _zpx1 + _btn_bw, _btn_y + _btn_bh);
	    draw_set_color(_zphov ? c_white : c_gray);
	    draw_rectangle(_zpx1, _btn_y, _zpx1 + _btn_bw, _btn_y + _btn_bh, true);
	    draw_text(_zpx1 + _btn_bw * 0.5, _btn_y + 3, "Z+");
	    draw_set_halign(fa_left);
	    if (_zphov && mouse_check_button_pressed(mb_left)) _m.zoom = min(6, _zoom + 1);

	    // GRID toggle button
	    if (!variable_struct_exists(_m, "show_grid")) _m.show_grid = true;
	    var _show_grid = _m.show_grid;
	    var _gbtn_x1  = _vx2 - _btn_bw * 4 - 12;
	    var _gbtn_x2  = _gbtn_x1 + _btn_bw + 10;
	    var _gbtn_hov = point_in_rectangle(_mx, _my, _gbtn_x1, _btn_y, _gbtn_x2, _btn_y + _btn_bh);
	    draw_set_color(_show_grid ? make_color_rgb(60, 160, 60) : make_color_rgb(60, 60, 60));
	    draw_rectangle(_gbtn_x1, _btn_y, _gbtn_x2, _btn_y + _btn_bh, false);
	    draw_set_color(_gbtn_hov ? c_white : (_show_grid ? c_lime : c_gray));
	    draw_rectangle(_gbtn_x1, _btn_y, _gbtn_x2, _btn_y + _btn_bh, true);
	    draw_set_halign(fa_center);
	    draw_text(_gbtn_x1 + (_btn_bw + 10) * 0.5, _btn_y + 3, "GRID");
	    draw_set_halign(fa_left);
	    if (_gbtn_hov && mouse_check_button_pressed(mb_left))
        _m.show_grid = !_show_grid;

    // FILL MODE toggle button
    if (!variable_struct_exists(_m, "fill_mode")) _m.fill_mode = false;
    var _fill_mode = _m.fill_mode;
    var _fbtn_x1   = _gbtn_x1 - _btn_bw - 14;
    var _fbtn_x2   = _fbtn_x1 + _btn_bw + 4;
    var _fbtn_hov  = point_in_rectangle(_mx, _my, _fbtn_x1, _btn_y, _fbtn_x2, _btn_y + _btn_bh);
    draw_set_color(_fill_mode ? make_color_rgb(160, 60, 160) : make_color_rgb(60, 60, 60));
    draw_rectangle(_fbtn_x1, _btn_y, _fbtn_x2, _btn_y + _btn_bh, false);
    draw_set_color(_fbtn_hov ? c_white : (_fill_mode ? make_color_rgb(255, 120, 255) : c_gray));
    draw_rectangle(_fbtn_x1, _btn_y, _fbtn_x2, _btn_y + _btn_bh, true);
    draw_set_halign(fa_center);
    draw_text(_fbtn_x1 + (_btn_bw + 4) * 0.5, _btn_y + 3, "FILL");
    draw_set_halign(fa_left);
    if (_fbtn_hov && mouse_check_button_pressed(mb_left))
        _m.fill_mode = !_fill_mode;

    _cy += _btn_bh + 4;

		    // ---- CANVAS ----
		    // Reserve bottom 80px for colour strip (20) + char strip (30+margins) below canvas.
		    // ECM reserves extra rows: the char strip becomes a 4-row grid (one row
		    // per BG0-3 band) instead of a single scrolling row.
		    var _cv_x1 = _vx1 + 10;
		    var _cv_y1 = _cy;
		    var _cv_x2 = _vx2 - 10;
		    var _cv_y2 = _vy2 - (_map_ecm_mode ? 195 : 80);
		    var _cv_w  = _cv_x2 - _cv_x1;
		    var _cv_h  = _cv_y2 - _cv_y1;

		    var _cs = 8 * _zoom;

		    draw_set_color(c_black);
		    draw_rectangle(_cv_x1, _cv_y1, _cv_x2, _cv_y2, false);
		    draw_set_color(make_color_rgb(40, 40, 60));
		    draw_rectangle(_cv_x1, _cv_y1, _cv_x2, _cv_y2, true);

		    var _scx = _m.scroll_x;
			var _scy = _m.scroll_y;

		    var _vis_cols  = ceil(_cv_w / _cs) + 1;
		    var _vis_rows  = ceil(_cv_h / _cs) + 1;
		    var _start_col = _scx;
		    var _start_row = _scy;
			var _end_col   = min(_start_col + _vis_cols, _gw);
	        var _end_row   = min(_start_row + _vis_rows, _gh);
	        var _ov_grid     = variable_struct_exists(_m, "override_grid") ? _m.override_grid : noone;
	        var _ov_grid_len = (_ov_grid != noone) ? array_length(_ov_grid) : 0;

var _chr_cols = 16;
		    if (_chr_asset_ref != noone && variable_struct_exists(_chr_asset_ref.meta, "char_count"))
		        _chr_cols = min(16, _chr_asset_ref.meta.char_count);
		    // _global_bg already resolved above after _chr_asset_ref lookup

		    var _sx_scale = window_get_width()  / _gui_w;
		    var _sy_scale = window_get_height() / display_get_gui_height();
		    gpu_set_scissor(
		        floor(_cv_x1 * _sx_scale),
		        floor(_cv_y1 * _sy_scale),
		        ceil((_cv_x2 - _cv_x1) * _sx_scale),
		        ceil((_cv_y2 - _cv_y1) * _sy_scale)
		    );

			for (var _row = _start_row; _row < _end_row; _row++) {
		        for (var _col = _start_col; _col < _end_col; _col++) {
		            var _idx   = _row * _gw + _col;
		            var _char  = _m.char_grid[_idx];
		            var _col_v = _m.colour_grid[_idx];
		            var _cx    = _cv_x1 + (_col - _start_col) * _cs;
		            var _cy2   = _cv_y1 + (_row - _start_row) * _cs;
		            var _cell_real_char = _map_ecm_mode ? (_char mod 64) : _char;
		            var _cell_bg_col    = _map_ecm_mode ? scr_c64_pepto_colour(_map_ecm_bg_cols[_char div 64]) : scr_c64_pepto_colour(_global_bg);

		            var _td = _show_grid ? 1 : 0;
		            if (_chr_asset_ref != noone &&
		                variable_struct_exists(_chr_asset_ref.meta, "preview_surf_clean") &&
		                surface_exists(_chr_asset_ref.meta.preview_surf_clean)) {
		                var _src_scale = 8;
		                var _src_cell  = 8 * _src_scale;
		                var _src_col   = _char mod _chr_cols;
		                var _src_row2  = _char div _chr_cols;
		                draw_set_color(_cell_bg_col);
						draw_rectangle(_cx, _cy2, _cx + _cs - _td, _cy2 + _cs - _td, false);
						
// Resolve per-cell MC: check override_grid first, fall back to global
var _ov_val = (_ov_grid_len > _idx) ? _ov_grid[_idx] : 0;
// In HR16 mode all cells are HR regardless of override

				var _cell_is_mc = (_global_mixed == 1) && (_ov_val == 1);
				// Resolve render colour based on global mode
				// In MIXED mode bit3 of colour RAM is stolen by C64 as MC flag, so only 3 bits available
				// In HR16 mode full 4-bit colour nibble is available
				var _render_col = 0;
				if (_global_mixed == 0) {
				    // HR16 mode — full nibble
				    _render_col = _col_v & 0x0F;
				} else {
				    // MIXED mode — only lower 3 bits usable regardless of HR or MC cell
				    _render_col = _col_v & 0x07;
				}
	                if (_cell_is_mc &&
	                    _chr_asset_ref != noone &&
	                    buffer_exists(_chr_asset_ref.buffer)) {
	                    // Resolve MC shared colours (map override or inherit from charset)
						var _res_bg   = _global_bg; // universal BG
	                    var _res_col1 = (variable_struct_exists(_m, "map_mc_col1") && _m.map_mc_col1 >= 0) ? _m.map_mc_col1 : (variable_struct_exists(_chr_asset_ref.meta, "mc_col1") ? _chr_asset_ref.meta.mc_col1 : 1);
	                    var _res_col2 = (variable_struct_exists(_m, "map_mc_col2") && _m.map_mc_col2 >= 0) ? _m.map_mc_col2 : (variable_struct_exists(_chr_asset_ref.meta, "mc_col2") ? _chr_asset_ref.meta.mc_col2 : 2);
	                    var _res_col3 = _col_v & 0x07; // colour RAM = bits 0-2
	                    var _mc_palette = [
	                        scr_c64_pepto_colour(_res_bg),
	                        scr_c64_pepto_colour(_res_col1),
	                        scr_c64_pepto_colour(_res_col2),
	                        scr_c64_pepto_colour(_res_col3)
	                    ];
	                 
					// MC: 4 bit-pairs per row, each pair = cs/4 wide, cs/8 tall
	                    var _pxw = max(1, _cs / 4); // width of one bit-pair (2 MC pixels wide)
	                    var _pxh = max(1, _cs / 8); // height of one pixel row
	                    // Fill BG first
	                    draw_set_color(_mc_palette[0]);
	                    draw_rectangle(_cx, _cy2, _cx + _cs - _td, _cy2 + _cs - _td, false);
	                    // Draw each row from charset buffer
	                    for (var _brow = 0; _brow < 8; _brow++) {
	                        var _boff = (_char * 8) + _brow;
	                        if (_boff >= buffer_get_size(_chr_asset_ref.buffer)) break;
	                        var _byte = buffer_peek(_chr_asset_ref.buffer, _boff, buffer_u8);
	                        for (var _pair = 0; _pair < 4; _pair++) {
	                            var _bits = (_byte >> (6 - _pair * 2)) & 0x03;
	                            if (_bits == 0) continue; // BG already filled
	                            draw_set_color(_mc_palette[_bits]);
	                            var _px = _cx + _pair * _pxw;
	                            var _py = _cy2 + _brow * _pxh;
	                            draw_rectangle(_px, _py, _px + _pxw, _py + _pxh, false);
	                        }
	                    }
} else {
	                    // Hires cell — direct buffer render, 1 bit per pixel
	                    var _hr_pxw = max(1, _cs / 8);
	                    var _hr_pxh = max(1, _cs / 8);
draw_set_color(_cell_bg_col);
	                    draw_rectangle(_cx, _cy2, _cx + _cs - _td, _cy2 + _cs - _td, false);
	                    draw_set_color(scr_c64_pepto_colour(_render_col));
	                    for (var _brow = 0; _brow < 8; _brow++) {
	                        var _boff = (_cell_real_char * 8) + _brow;
	                        if (_boff >= buffer_get_size(_chr_asset_ref.buffer)) break;
	                        var _byte = buffer_peek(_chr_asset_ref.buffer, _boff, buffer_u8);
	                        for (var _bit = 0; _bit < 8; _bit++) {
	                            if (_byte & (0x80 >> _bit)) {
	                                var _px = _cx + _bit * _hr_pxw;
	                                var _py = _cy2 + _brow * _hr_pxh;
	                                draw_rectangle(_px, _py, _px + _hr_pxw, _py + _hr_pxh, false);
	                            }
	                        }
	                    }
	                }
					
					
			} else {
		                draw_set_color(make_color_rgb(20, 20, 35));
		                draw_rectangle(_cx, _cy2, _cx + _cs - _td, _cy2 + _cs - _td, false);
		                if (_char > 0 && _cs >= 14) {
		                    draw_set_color(scr_c64_pepto_colour(clamp(_col_v, 0, 15)));
		                    draw_set_font(fnt_c64_tiny);
		                    draw_set_halign(fa_center);
		                    draw_text(_cx + _cs * 0.5, _cy2 + _cs * 0.5 - 4, string(_char));
		                    draw_set_halign(fa_left);
		                }
		            }
		
					// Highlight selected tiles
					if (_m.sel_grid[_idx]) {
						draw_set_color(c_white);
						draw_set_alpha(0.3 + 0.1 * sin(current_time / 150)); // Pulsing effect
						draw_rectangle(_cx, _cy2, _cx + _cs, _cy2 + _cs, false);
						draw_set_alpha(1.0);
					}
		        }
		    }

// Grid lines
	    if (_show_grid) {
	        draw_set_color(make_color_rgb(30, 50, 80));
	        draw_set_alpha(0.5);
	        for (var _gc = 0; _gc <= (_end_col - _start_col); _gc++)
	            draw_line(_cv_x1 + _gc * _cs, _cv_y1, _cv_x1 + _gc * _cs, _cv_y2);
	        for (var _gr = 0; _gr <= (_end_row - _start_row); _gr++)
	            draw_line(_cv_x1, _cv_y1 + _gr * _cs, _cv_x2, _cv_y1 + _gr * _cs);
	        draw_set_alpha(1.0);

	    }
	
    gpu_set_scissor(0, 0, window_get_width(), window_get_height());


	// ==========================================
    // STAMP, SELECTION & PAINTING INTERACTION
    // ==========================================

    // --- MAP UNDO INIT ---
    if (!variable_struct_exists(_m, "map_undo_stack")) _m.map_undo_stack = [];
    if (!variable_struct_exists(_m, "map_redo_stack")) _m.map_redo_stack = [];

    var _mouse_in_canvas = point_in_rectangle(_mx, _my, _cv_x1, _cv_y1, _cv_x2, _cv_y2);

    if (_mouse_in_canvas) {
        var _mcol = _m.scroll_x + floor((_mx - _cv_x1) / _cs);
        var _mrow = _m.scroll_y + floor((_my - _cv_y1) / _cs);
        var _midx = _mrow * _gw + _mcol;

        if (_mcol >= 0 && _mcol < _gw && _mrow >= 0 && _mrow < _gh) {
            
            // --- 1. SELECTION (Control + Left Click/Drag) ---
            if (scr_ctrl_held()) {
                if (mouse_check_button(mb_left)) {
                    _m.sel_grid[_midx] = 1; // Mark as selected
                }
            }
            // --- 2. STAMPING (Left Click with stamp data) ---
            else if (_m.stamp_active && mouse_check_button_pressed(mb_left) && !scr_ctrl_held()) {
                // Push undo snapshot
                array_push(_m.map_undo_stack, {
                    char_grid:     array_copy_shallow(_m.char_grid),
                    colour_grid:   array_copy_shallow(_m.colour_grid),
                    override_grid: array_copy_shallow(_m.override_grid)
                });
                if (array_length(_m.map_undo_stack) > 50) array_delete(_m.map_undo_stack, 0, 1);
                _m.map_redo_stack = [];
                for (var _i = 0; _i < array_length(_m.stamp_data); _i++) {
                    var _stamp = _m.stamp_data[_i];
                    var _dest_col = _mcol + _stamp.dx;
                    var _dest_row = _mrow + _stamp.dy;
                    var _dest_idx = _dest_row * _gw + _dest_col;
                    if (_dest_col >= 0 && _dest_col < _gw && _dest_row >= 0 && _dest_row < _gh) {
                        _m.char_grid[_dest_idx]     = _stamp.char;
                        _m.colour_grid[_dest_idx]   = _stamp.col;
                        _m.override_grid[_dest_idx] = _stamp.ov;
                        scr_asset_map_flush_cell(_asset, _dest_row, _dest_col);
                    }
                }
            }
            // --- 3. FLOOD FILL (Left Click in fill mode) ---
            else if (_m.fill_mode && mouse_check_button_pressed(mb_left) && !scr_ctrl_held()) {
                // Push undo snapshot before fill
                array_push(_m.map_undo_stack, {
                    char_grid:     array_copy_shallow(_m.char_grid),
                    colour_grid:   array_copy_shallow(_m.colour_grid),
                    override_grid: array_copy_shallow(_m.override_grid)
                });
                if (array_length(_m.map_undo_stack) > 50) array_delete(_m.map_undo_stack, 0, 1);
                _m.map_redo_stack = [];

                // Read target char at click position
                var _fill_target_char   = _m.char_grid[_midx];
                var _fill_target_colour = _m.colour_grid[_midx];
                var _fill_new_char      = _m.active_char;
                var _fill_new_colour    = (_global_mixed == 1) ? (_m.active_colour & 0x07) : (_m.active_colour & 0x0F);
                var _fill_new_ov        = (_global_mixed == 1 && _m.paint_mc == 1) ? 1 : 0;

                // Only fill if target differs from what we are painting
                if (_fill_target_char != _fill_new_char || _fill_target_colour != _fill_new_colour) {
                    // Iterative flood fill using a stack array
                    var _fill_stack = [_midx];
                    var _fill_visited = array_create(_gw * _gh, false);
                    _fill_visited[_midx] = true;

                    while (array_length(_fill_stack) > 0) {
                        var _fi      = _fill_stack[array_length(_fill_stack) - 1];
                        array_delete(_fill_stack, array_length(_fill_stack) - 1, 1);

                        var _fc = _fi mod _gw;
                        var _fr = _fi div _gw;

                        // Only fill cells that match the original char and colour
                        if (_m.char_grid[_fi] != _fill_target_char) continue;
                        if (_m.colour_grid[_fi] != _fill_target_colour) continue;

                        _m.char_grid[_fi]     = _fill_new_char;
                        _m.colour_grid[_fi]   = _fill_new_colour;
                        _m.override_grid[_fi] = _fill_new_ov;

                        // Push 4-connected neighbours
                        var _fill_neighbours = [
                            (_fr - 1) * _gw + _fc,
                            (_fr + 1) * _gw + _fc,
                            _fr * _gw + (_fc - 1),
                            _fr * _gw + (_fc + 1)
                        ];
                        for (var _fn = 0; _fn < 4; _fn++) {
                            var _nidx = _fill_neighbours[_fn];
                            var _nc   = _nidx mod _gw;
                            var _nr   = _nidx div _gw;
                            if (_nc >= 0 && _nc < _gw && _nr >= 0 && _nr < _gh && !_fill_visited[_nidx]) {
                                _fill_visited[_nidx] = true;
                                array_push(_fill_stack, _nidx);
                            }
                        }
                    }
                    scr_asset_map_flush(_asset);
                }
            }

            // --- 4. NORMAL PAINTING (Left/Right Click without control or stamp) ---
            else if (mouse_check_button_pressed(mb_left) && !scr_ctrl_held() && !keyboard_check(vk_shift)) {
                array_push(_m.map_undo_stack, {
                    char_grid:     array_copy_shallow(_m.char_grid),
                    colour_grid:   array_copy_shallow(_m.colour_grid),
                    override_grid: array_copy_shallow(_m.override_grid)
                });
                if (array_length(_m.map_undo_stack) > 50) array_delete(_m.map_undo_stack, 0, 1);
                _m.map_redo_stack = [];
                _m.char_grid[_midx]   = _m.active_char;
                _m.colour_grid[_midx] = _m.active_colour;
                scr_asset_map_flush_cell(_asset, _mrow, _mcol);
            }
        }
    }

    // --- 4. COPY COMMAND (Ctrl + C) ---
    if (scr_ctrl_held() && keyboard_check_pressed(ord("C"))) {
        _m.stamp_data = [];
        var _min_c = _gw, _min_r = _gh;
        for (var _r = 0; _r < _gh; _r++) {
            for (var _c = 0; _c < _gw; _c++) {
                if (_m.sel_grid[_r * _gw + _c]) {
                    _min_c = min(_min_c, _c);
                    _min_r = min(_min_r, _r);
                }
            }
        }
        if (_min_c < _gw && _min_r < _gh) {
            for (var _r = 0; _r < _gh; _r++) {
                for (var _c = 0; _c < _gw; _c++) {
                    var _idx = _r * _gw + _c;
                    if (_m.sel_grid[_idx]) {
                        array_push(_m.stamp_data, {
                            dx:   _c - _min_c,
                            dy:   _r - _min_r,
                            char: _m.char_grid[_idx],
                            col:  _m.colour_grid[_idx],
                            ov:   _m.override_grid[_idx]
                        });
                    }
                }
            }
            _m.stamp_active = true;
            _m.sel_grid = array_create(_gw * _gh, 0);
            show_debug_message("COPY: stamp_data count=" + string(array_length(_m.stamp_data)));
        }
    }

    // --- 5. DESELECT / CANCEL STAMP (Ctrl + D) ---
    if (scr_ctrl_held() && keyboard_check_pressed(ord("D"))) {
        _m.sel_grid     = array_create(_gw * _gh, 0);
        _m.stamp_data   = [];
        _m.stamp_active = false;
    }

    // ==========================================
    // FLOATING STAMP PREVIEW (Visuals)
    // ==========================================
    gpu_set_scissor(0, 0, window_get_width(), window_get_height());

// Blok1
    if (_m.stamp_active) {
        var _scx2 = _m.scroll_x;
		
        var _scy2 = _m.scroll_y;
        var _mcol = _scx2 + floor((_mx - _cv_x1) / _cs);
        var _mrow = _scy2 + floor((_my - _cv_y1) / _cs);

        draw_set_color(c_black);
        draw_set_alpha(0.15);
        draw_rectangle(_cv_x1, _cv_y1, _cv_x2, _cv_y2, false);
        draw_set_alpha(1.0);

        for (var _i = 0; _i < array_length(_m.stamp_data); _i++) {
            var _stamp  = _m.stamp_data[_i];
            var _px_col = _mcol + _stamp.dx;
            var _px_row = _mrow + _stamp.dy;
            var _px_x   = _cv_x1 + (_px_col - _scx2) * _cs;
            var _px_y   = _cv_y1 + (_px_row - _scy2) * _cs;

            if (_px_x >= _cv_x1 && _px_x < _cv_x2 && _px_y >= _cv_y1 && _px_y < _cv_y2) {
                var _s_ov  = variable_struct_exists(_stamp, "ov") ? _stamp.ov : 0;
                var _s_mc  = (_global_mixed == 1) && (_s_ov == 1);
                var _s_col = (_global_mixed == 0) ? (_stamp.col & 0x0F) : (_stamp.col & 0x07);
                if (_chr_asset_ref != noone && buffer_exists(_chr_asset_ref.buffer)) {
                    if (_s_mc) {
                        var _s_bg   = _global_bg;
                        var _s_col1 = (variable_struct_exists(_m, "map_mc_col1") && _m.map_mc_col1 >= 0) ? _m.map_mc_col1 : _chr_asset_ref.meta.mc_col1;
                        var _s_col2 = (variable_struct_exists(_m, "map_mc_col2") && _m.map_mc_col2 >= 0) ? _m.map_mc_col2 : _chr_asset_ref.meta.mc_col2;
                        var _s_pal  = [scr_c64_pepto_colour(_s_bg), scr_c64_pepto_colour(_s_col1), scr_c64_pepto_colour(_s_col2), scr_c64_pepto_colour(_stamp.col & 0x07)];
                        var _s_pxw  = max(1, _cs / 4);
                        var _s_pxh  = max(1, _cs / 8);
                        draw_set_color(_s_pal[0]);
                        draw_rectangle(_px_x, _px_y, _px_x + _cs, _px_y + _cs, false);
                        for (var _sr = 0; _sr < 8; _sr++) {
                            var _sboff = (_stamp.char * 8) + _sr;
                            if (_sboff >= buffer_get_size(_chr_asset_ref.buffer)) break;
                            var _sbyte = buffer_peek(_chr_asset_ref.buffer, _sboff, buffer_u8);
                            for (var _sp = 0; _sp < 4; _sp++) {
                                var _sbits = (_sbyte >> (6 - _sp * 2)) & 0x03;
                                if (_sbits == 0) continue;
                                draw_set_color(_s_pal[_sbits]);
                                draw_rectangle(_px_x + _sp * _s_pxw, _px_y + _sr * _s_pxh, _px_x + _sp * _s_pxw + _s_pxw, _px_y + _sr * _s_pxh + _s_pxh, false);
                            }
                        }
                    } else {
                        var _s_pxw2 = max(1, _cs / 8);
                        var _s_pxh2 = max(1, _cs / 8);
                        draw_set_color(scr_c64_pepto_colour(_global_bg));
                        draw_rectangle(_px_x, _px_y, _px_x + _cs, _px_y + _cs, false);
                        draw_set_color(scr_c64_pepto_colour(_s_col));
                        for (var _sr = 0; _sr < 8; _sr++) {
                            var _sboff = (_stamp.char * 8) + _sr;
                            if (_sboff >= buffer_get_size(_chr_asset_ref.buffer)) break;
                            var _sbyte = buffer_peek(_chr_asset_ref.buffer, _sboff, buffer_u8);
                            for (var _sb = 0; _sb < 8; _sb++) {
                                if (_sbyte & (0x80 >> _sb)) {
                                    draw_rectangle(_px_x + _sb * _s_pxw2, _px_y + _sr * _s_pxh2, _px_x + _sb * _s_pxw2 + _s_pxw2, _px_y + _sr * _s_pxh2 + _s_pxh2, false);
                                }
                            }
                        }
                    }
                } else {
                    // No charset loaded — fallback to colour block
                    draw_set_color(scr_c64_pepto_colour(_stamp.col));
                    draw_rectangle(_px_x, _px_y, _px_x + _cs, _px_y + _cs, false);
                }
                // Stamp outline
                draw_set_color(c_white);
                draw_set_alpha(0.4);
                draw_rectangle(_px_x, _px_y, _px_x + _cs, _px_y + _cs, true);
                draw_set_alpha(1.0);
            }
        }
    }

    // Grey out inactive region (beyond map_w x map_h)
    if (_gw > _mw || _gh > _mh) {
        var _active_x2 = _cv_x1 + (_mw - _scx) * _cs;
        var _active_y2 = _cv_y1 + (_mh - _scy) * _cs;
        draw_set_color(make_color_rgb(0, 0, 0));
        draw_set_alpha(0.5);
        if (_active_x2 < _cv_x2)
            draw_rectangle(_active_x2, _cv_y1, _cv_x2, _cv_y2, false);
        if (_active_y2 < _cv_y2)
            draw_rectangle(_cv_x1, _active_y2, _active_x2, _cv_y2, false);
        draw_set_alpha(1.0);
    }
			
	

// ---- HOVER + UNIFIED PAINT ----
    if (mouse_check_button_released(mb_left)) {
        map_paint_last_col = -999999;
        map_paint_last_row = -999999;
    }
    if (point_in_rectangle(_mx, _my, _cv_x1, _cv_y1, _cv_x2, _cv_y2)) {
        var _hcol = _start_col + (_mx - _cv_x1) div _cs;
        var _hrow = _start_row + (_my - _cv_y1) div _cs;
        
        if (_hcol >= 0 && _hcol < _mw && _hrow >= 0 && _hrow < _mh) {
            var _hx = _cv_x1 + (_hcol - _start_col) * _cs;
            var _hy = _cv_y1 + (_hrow - _start_row) * _cs;
            
            draw_set_color(c_white);
            draw_set_alpha(0.3);
            draw_rectangle(_hx, _hy, _hx + _cs, _hy + _cs, false);
            draw_set_alpha(1.0);
            draw_rectangle(_hx, _hy, _hx + _cs, _hy + _cs, true);
            draw_set_font(fnt_c64_tiny);
            draw_set_color(c_ltgray);

            var _pidx = _hrow * _gw + _hcol;

           // A held — force HR on hovered cell (MIXED mode only)
            if (keyboard_check(ord("A")) && _global_mixed == 1) {
                if (array_length(_m.override_grid) != _gw * _gh) {
                    _m.override_grid = array_create(_gw * _gh, 0);
                }
                if (_m.override_grid[_pidx] != 0) {
                    _m.override_grid[_pidx] = 0;
                    scr_asset_map_flush_cell(_asset, _hrow, _hcol);
                }
            }
					
            
            // S held — force MC on hovered cell (MIXED mode only)
            if (keyboard_check(ord("S")) && _global_mixed == 1) {
                if (!variable_struct_exists(_m, "override_grid") || array_length(_m.override_grid) != _gw * _gh)
                    _m.override_grid = array_create(_gw * _gh, 0);
                if (_m.override_grid[_pidx] != 1) {
                    _m.override_grid[_pidx] = 1;
                    scr_asset_map_flush_cell(_asset, _hrow, _hcol);
                }
            }
			
			if (keyboard_check_pressed(ord("X")) && _global_mixed == 1 && !_m.stamp_active) {
                if (!variable_struct_exists(_m, "override_grid") || array_length(_m.override_grid) != _gw * _gh)
                    _m.override_grid = array_create(_gw * _gh, 0);
                _m.override_grid[_pidx] = (_m.override_grid[_pidx] == 1) ? 0 : 1;
                scr_asset_map_flush_cell(_asset, _hrow, _hcol);
            }
            if (keyboard_check_pressed(ord("X")) && _m.stamp_active) {
                var _max_dx = 0;
                for (var _fi = 0; _fi < array_length(_m.stamp_data); _fi++)
                    _max_dx = max(_max_dx, _m.stamp_data[_fi].dx);
                for (var _fi = 0; _fi < array_length(_m.stamp_data); _fi++)
                    _m.stamp_data[_fi].dx = _max_dx - _m.stamp_data[_fi].dx;
            }
            if (keyboard_check_pressed(ord("Y")) && _m.stamp_active) {
                var _max_dy = 0;
                for (var _fi = 0; _fi < array_length(_m.stamp_data); _fi++)
                    _max_dy = max(_max_dy, _m.stamp_data[_fi].dy);
                for (var _fi = 0; _fi < array_length(_m.stamp_data); _fi++)
                    _m.stamp_data[_fi].dy = _max_dy - _m.stamp_data[_fi].dy;
            }
			

            // --- 1. SELECTION (Control + Left Click/Drag) ---
            if (keyboard_check(vk_control)) {
                if (mouse_check_button(mb_left)) {
                    _m.sel_grid[_pidx] = 1; // Mark as selected
                }
            }
            // --- 2. STAMPING (Left Click with stamp data) ---
            else if (_m.stamp_active && mouse_check_button_pressed(mb_left) && !keyboard_check(vk_control)) {
                for (var _i = 0; _i < array_length(_m.stamp_data); _i++) {
                    var _stamp = _m.stamp_data[_i];
                    var _dest_col = _hcol + _stamp.dx;
                    var _dest_row = _hrow + _stamp.dy;
                    var _dest_idx = _dest_row * _gw + _dest_col;

                    if (_dest_col >= 0 && _dest_col < _gw && _dest_row >= 0 && _dest_row < _gh) {
                        _m.char_grid[_dest_idx]   = _stamp.char;
                        _m.colour_grid[_dest_idx] = _stamp.col;
                        if (variable_struct_exists(_stamp, "ov")) {
                            _m.override_grid[_dest_idx] = _stamp.ov; 
                        }
                        scr_asset_map_flush_cell(_asset, _dest_row, _dest_col);
                    }
                }
            }
            // --- 3. NORMAL PAINTING (Left/Right Click without control or stamp) ---
            else {
                // Left click — paint CHAR and COLOUR, interpolated across any
                // gap since the last painted cell (fast drags otherwise skip
                // cells the paint loop never got a chance to poll at).
                if (mouse_check_button(mb_left) && !_m.stamp_active) {
                    var _pmc = variable_struct_exists(_m, "paint_mc") ? _m.paint_mc : 0;
                    var _raw_col = (_global_mixed == 1) ? (_m.active_colour & 0x07) : (_m.active_colour & 0x0F);

                    if (!variable_struct_exists(_m, "override_grid") || array_length(_m.override_grid) != _gw * _gh)
                        _m.override_grid = array_create(_gw * _gh, 0);

                    var _shift_paint = keyboard_check(vk_shift);

                    if (map_paint_last_col == -999999 || map_paint_last_row == -999999) {
                        map_paint_last_col = _hcol;
                        map_paint_last_row = _hrow;
                    }

                    // Bresenham walk from the last painted cell to the current one.
                    var _lx0 = map_paint_last_col, _ly0 = map_paint_last_row;
                    var _lx1 = _hcol,              _ly1 = _hrow;
                    var _ldx = abs(_lx1 - _lx0), _lsx = (_lx0 < _lx1) ? 1 : -1;
                    var _ldy = -abs(_ly1 - _ly0), _lsy = (_ly0 < _ly1) ? 1 : -1;
                    var _lerr = _ldx + _ldy;
                    var _lcx = _lx0, _lcy = _ly0;
                    var _lguard = 0; // safety cap — a stroke never needs more steps than map cells
                    var _lguard_max = _gw + _gh + 4;
                    while (true) {
                        if (_lcx >= 0 && _lcx < _mw && _lcy >= 0 && _lcy < _mh) {
                            var _lidx = _lcy * _gw + _lcx;
                            if (_shift_paint) {
                                _m.colour_grid[_lidx] = _raw_col;
                            } else {
                                _m.char_grid[_lidx]     = _m.active_char;
                                _m.colour_grid[_lidx]   = _raw_col;
                                _m.override_grid[_lidx] = (_global_mixed == 1 && _pmc == 1) ? 1 : 0;
                            }
                            scr_asset_map_flush_cell(_asset, _lcy, _lcx);
                        }
                        if (_lcx == _lx1 && _lcy == _ly1) break;
                        _lguard++;
                        if (_lguard > _lguard_max) break; // defensive — should never trigger
                        var _le2 = 2 * _lerr;
                        if (_le2 >= _ldy) { _lerr += _ldy; _lcx += _lsx; }
                        if (_le2 <= _ldx) { _lerr += _ldx; _lcy += _lsy; }
                    }

                    map_paint_last_col = _hcol;
                    map_paint_last_row = _hrow;
                }
                
                // Right click — erase all non-zero chars covered by stamp footprint
                if (mouse_check_button(mb_right)) {
                    if (_m.stamp_active && array_length(_m.stamp_data) > 0) {
                        for (var _er = 0; _er < array_length(_m.stamp_data); _er++) {
                            var _estamp   = _m.stamp_data[_er];
                            var _edest_col = _hcol + _estamp.dx;
                            var _edest_row = _hrow + _estamp.dy;
                            if (_edest_col >= 0 && _edest_col < _gw && _edest_row >= 0 && _edest_row < _gh) {
                                var _edest_idx = _edest_row * _gw + _edest_col;
                                if (_m.char_grid[_edest_idx] != 0) {
                                    _m.char_grid[_edest_idx] = 0;
                                }
                                scr_asset_map_flush_cell(_asset, _edest_row, _edest_col);
                            }
                        }
                    } else {
                        _m.char_grid[_pidx] = 0;
                        scr_asset_map_flush_cell(_asset, _hrow, _hcol);
                    }
                }
            }
        }

    
    

		        if (keyboard_check_pressed(ord("P")) && _global_mixed == 1) _m.paint_mc = (_paint_mc == 0) ? 1 : 0;
			    if (keyboard_check_pressed(vk_right)) _m.scroll_x = min(_mw - 1, _m.scroll_x + 1);
		        if (keyboard_check_pressed(vk_left))  _m.scroll_x = max(0, _m.scroll_x - 1);
		        if (keyboard_check_pressed(vk_down))  _m.scroll_y = min(_mh - 1, _m.scroll_y + 1);
		        if (keyboard_check_pressed(vk_up))    _m.scroll_y = max(0, _m.scroll_y - 1);
				if (keyboard_check_pressed(ord("M")) && !_early_chr_ecm) {
				    _m.map_mixed = (_global_mixed == 0) ? 1 : 0;
				    obj_workspace_manager.map_global_mixed = _m.map_mixed;
				    _m.is_dirty = true;
				}

		        if (mouse_wheel_up())   _m.zoom = min(6, _zoom + 1);
		        if (mouse_wheel_down()) _m.zoom = max(1, _zoom - 1);

				if (mouse_check_button_pressed(mb_middle) || keyboard_check_pressed(vk_alt) || keyboard_check_pressed(vk_space) ) {
		            _m.pan_active   = true;
		            _m.pan_start_mx = _mx;
		            _m.pan_start_my = _my;
		            _m.pan_start_sx = _m.scroll_x;
		            _m.pan_start_sy = _m.scroll_y;
		        }
		       if (mouse_check_button_released(mb_middle) || keyboard_check_released(vk_alt) || keyboard_check_released(vk_space) || !window_has_focus()) {
		            _m.pan_active = false;
		            keyboard_clear(vk_alt);
		        }
				if (variable_struct_exists(_m, "pan_active") && _m.pan_active && window_has_focus()) {
		            var _dx = (_m.pan_start_mx - _mx) div _cs;
		            var _dy = (_m.pan_start_my - _my) div _cs;
		            _m.scroll_x = clamp(_m.pan_start_sx + _dx, 0, _gw - 1);
		            _m.scroll_y = clamp(_m.pan_start_sy + _dy, 0, _gh - 1);
		        }
		       

	    }




    // ==========================================
    // FLOATING STAMP PREVIEW (Visuals)
    // ==========================================
// blok2
    if (_m.stamp_active) {
        var _scx3 = _m.scroll_x;
        var _scy3 = _m.scroll_y;
        var _pcol = _scx3 + floor((_mx - _cv_x1) / _cs);
        var _prow = _scy3 + floor((_my - _cv_y1) / _cs);

        draw_set_color(c_black);
        draw_set_alpha(0.15);
        draw_rectangle(_cv_x1, _cv_y1, _cv_x2, _cv_y2, false);
        draw_set_alpha(1.0);

        for (var _i = 0; _i < array_length(_m.stamp_data); _i++) {
            var _stamp  = _m.stamp_data[_i];
            var _px_col = _pcol + _stamp.dx;
            var _px_row = _prow + _stamp.dy;
            var _px_x   = _cv_x1 + (_px_col - _scx3) * _cs;
            var _px_y   = _cv_y1 + (_px_row - _scy3) * _cs;
     
            if (_px_x >= _cv_x1 && _px_x < _cv_x2 && _px_y >= _cv_y1 && _px_y < _cv_y2) {
                var _s_ov  = variable_struct_exists(_stamp, "ov") ? _stamp.ov : 0;
                var _s_mc  = (_global_mixed == 1) && (_s_ov == 1);
                var _s_col = (_global_mixed == 0) ? (_stamp.col & 0x0F) : (_stamp.col & 0x07);
                if (_chr_asset_ref != noone && buffer_exists(_chr_asset_ref.buffer)) {
                    if (_s_mc) {
                        var _s_bg   = _global_bg;
                        var _s_col1 = (variable_struct_exists(_m, "map_mc_col1") && _m.map_mc_col1 >= 0) ? _m.map_mc_col1 : _chr_asset_ref.meta.mc_col1;
                        var _s_col2 = (variable_struct_exists(_m, "map_mc_col2") && _m.map_mc_col2 >= 0) ? _m.map_mc_col2 : _chr_asset_ref.meta.mc_col2;
                        var _s_pal  = [scr_c64_pepto_colour(_s_bg), scr_c64_pepto_colour(_s_col1), scr_c64_pepto_colour(_s_col2), scr_c64_pepto_colour(_stamp.col & 0x07)];
                        var _s_pxw  = max(1, _cs / 4);
                        var _s_pxh  = max(1, _cs / 8);
                        draw_set_color(_s_pal[0]);
                        draw_rectangle(_px_x, _px_y, _px_x + _cs, _px_y + _cs, false);
                        for (var _sr = 0; _sr < 8; _sr++) {
                            var _sboff = (_stamp.char * 8) + _sr;
                            if (_sboff >= buffer_get_size(_chr_asset_ref.buffer)) break;
                            var _sbyte = buffer_peek(_chr_asset_ref.buffer, _sboff, buffer_u8);
                            for (var _sp = 0; _sp < 4; _sp++) {
                                var _sbits = (_sbyte >> (6 - _sp * 2)) & 0x03;
                                if (_sbits == 0) continue;
                                draw_set_color(_s_pal[_sbits]);
                                draw_rectangle(_px_x + _sp * _s_pxw, _px_y + _sr * _s_pxh, _px_x + _sp * _s_pxw + _s_pxw, _px_y + _sr * _s_pxh + _s_pxh, false);
                            }
                        }
                    } else {
                        var _s_pxw2 = max(1, _cs / 8);
                        var _s_pxh2 = max(1, _cs / 8);
                        draw_set_color(scr_c64_pepto_colour(_global_bg));
                        draw_rectangle(_px_x, _px_y, _px_x + _cs, _px_y + _cs, false);
                        draw_set_color(scr_c64_pepto_colour(_s_col));
                        for (var _sr = 0; _sr < 8; _sr++) {
                            var _sboff = (_stamp.char * 8) + _sr;
                            if (_sboff >= buffer_get_size(_chr_asset_ref.buffer)) break;
                            var _sbyte = buffer_peek(_chr_asset_ref.buffer, _sboff, buffer_u8);
                            for (var _sb = 0; _sb < 8; _sb++) {
                                if (_sbyte & (0x80 >> _sb)) {
                                    draw_rectangle(_px_x + _sb * _s_pxw2, _px_y + _sr * _s_pxh2, _px_x + _sb * _s_pxw2 + _s_pxw2, _px_y + _sr * _s_pxh2 + _s_pxh2, false);
                                }
                            }
                        }
                    }
                } else {
                    // No charset loaded — fallback to colour block
                    draw_set_color(scr_c64_pepto_colour(_stamp.col));
                    draw_rectangle(_px_x, _px_y, _px_x + _cs, _px_y + _cs, false);
                }
                // Stamp outline
                draw_set_color(c_white);
                draw_set_alpha(0.4);
                draw_rectangle(_px_x, _px_y, _px_x + _cs, _px_y + _cs, true);
                draw_set_alpha(1.0);
            }
        }
    }

// ---- COLOUR PALETTE STRIP (always visible) ----
	    var _pal_y = _cv_y2 + 6;
	    var _sw    = 22;
	    var _sh    = 16;
	    draw_set_font(fnt_c64_tiny);
	    draw_set_color(make_color_rgb(200, 255, 255));
	    draw_text(_cv_x1, _pal_y, "COLOUR");
	    draw_text(_cv_x1 + 460, _pal_y - 6,
		"[ CTRL = SELECT ] [ SHIFT = COLOUR ONLY ] [ SPACEBAR = PAN ] [M = TOGGLE MC/HR MODEs ]  [ALT + LMB/RMB = TILE TYPES ]\n"+
		
		"[HOLD A = MAKE HR ] [HOLD S = MAKE MC ]  [ P = PAINT MODEs ] [X/Y = FLIP STAMP ORDER]");

var _pal_count = (_global_mixed == 1) ? 8 : 16;
    var _pal_sw    = (_global_mixed == 1) ? _sw : _sw;
    var _pal_sh    = _sh;
    for (var _pi = 0; _pi < _pal_count; _pi++) {
	        var _px1  = _cv_x1 + _pi * (_pal_sw + 2) + 60;
	        var _phov = point_in_rectangle(_mx, _my, _px1, _pal_y, _px1 + _pal_sw, _pal_y + _pal_sh);
	        draw_set_color(scr_c64_pepto_colour(_pi));
	        draw_rectangle(_px1, _pal_y, _px1 + _pal_sw, _pal_y + _pal_sh, false);
	        if (_m.active_colour == _pi) {
	            draw_set_color(c_white);
	            draw_rectangle(_px1, _pal_y, _px1 + _pal_sw, _pal_y + _pal_sh, true);
	        }
	        if (_phov && mouse_check_button_pressed(mb_left))
	            _m.active_colour = _pi;
	    }

// ---- CHAR STRIP (always visible) ----
		    var _cp_y     = _pal_y + _sh + 18;
		    var _cp_sz    = 28;

		    if (_map_ecm_mode) {
		        // ---- ECM: fixed 4-row grid — one row per BG0-3 band, same real
		        // chars across every row, so all 4 "parallel copies" of a glyph
		        // are visible together instead of scrolling through 256 slots.
		        var _cp_real_total = (_chr_asset_ref != noone) ? _chr_asset_ref.meta.char_count : 64;
		        var _cp_cnt         = floor((_cv_x2 - _cv_x1) / (_cp_sz + 2)) - 2;
		        var _cp_start       = _m.char_strip_offset;
		        var _cp_row_h       = _cp_sz + 6;
		        var _cp_band_labels = ["BG0", "BG1", "BG2", "BG3"];

		        draw_set_color(make_color_rgb(200, 255, 255));
		        draw_text(_cv_x1, _cp_y, "TILE (ECM BANDS)");

		        for (var _bnd = 0; _bnd < 4; _bnd++) {
		            var _row_y = _cp_y + 16 + _bnd * _cp_row_h;
		            draw_set_font(fnt_c64_tiny);
		            draw_set_color(make_color_rgb(160, 160, 200));
		            draw_text(_cv_x1, _row_y + 8, _cp_band_labels[_bnd]);

		            for (var _pi = 0; _pi < _cp_cnt; _pi++) {
		                var _real_ci = _cp_start + _pi;
		                if (_real_ci >= _cp_real_total) break;
		                var _virt_ci = (_bnd * 64) + _real_ci;
		                var _px1  = _cv_x1 + 45 + _pi * (_cp_sz + 2);
		                var _phov = point_in_rectangle(_mx, _my, _px1, _row_y, _px1 + _cp_sz, _row_y + _cp_sz);
		                var _sel  = (_m.active_char == _virt_ci);
		                var _band_bg = scr_c64_pepto_colour(_map_ecm_bg_cols[_bnd]);

		                draw_set_color(_sel ? make_color_rgb(60, 120, 80) : _band_bg);
		                draw_rectangle(_px1, _row_y, _px1 + _cp_sz, _row_y + _cp_sz, false);

		                if (_chr_asset_ref != noone && buffer_exists(_chr_asset_ref.buffer)) {
		                    var _st_pxw = max(1, (_cp_sz - 4) / 8);
		                    var _st_pxh = max(1, (_cp_sz - 4) / 8);
		                    draw_set_color(_band_bg);
		                    draw_rectangle(_px1 + 2, _row_y + 2, _px1 + _cp_sz - 2, _row_y + _cp_sz - 2, false);
		                    draw_set_color(scr_c64_pepto_colour(_m.active_colour & 0x0F));
		                    for (var _str = 0; _str < 8; _str++) {
		                        var _stboff = (_real_ci * 8) + _str;
		                        if (_stboff >= buffer_get_size(_chr_asset_ref.buffer)) break;
		                        var _stbyte = buffer_peek(_chr_asset_ref.buffer, _stboff, buffer_u8);
		                        for (var _stbit = 0; _stbit < 8; _stbit++) {
		                            if (_stbyte & (0x80 >> _stbit)) {
		                                draw_rectangle(
		                                    _px1 + 2 + _stbit * _st_pxw, _row_y + 2 + _str * _st_pxh,
		                                    _px1 + 2 + _stbit * _st_pxw + _st_pxw, _row_y + 2 + _str * _st_pxh + _st_pxh,
		                                    false);
		                            }
		                        }
		                    }
		                } else {
		                    draw_set_font(fnt_c64_tiny);
		                    draw_set_color(c_gray);
		                    draw_set_halign(fa_center);
		                    draw_text(_px1 + _cp_sz * 0.5, _row_y + 6, string(_real_ci));
		                    draw_set_halign(fa_left);
		                }

		                if (_sel) {
		                    draw_set_color(c_white);
		                    draw_rectangle(_px1 - 2, _row_y - 2, _px1 + _cp_sz + 2, _row_y + _cp_sz + 2, true);
		                    draw_rectangle(_px1, _row_y, _px1 + _cp_sz, _row_y + _cp_sz, true);
		                }
		                if (_phov && mouse_check_button_pressed(mb_left)) {
		                    _m.active_char = _virt_ci;
		                }
		            }
		        }

		        // Horizontal scroll (real chars only — bands are stacked rows, not scroll targets)
		        var _ecm_strip_bottom = _cp_y + 16 + 4 * _cp_row_h;
		        if (point_in_rectangle(_mx, _my, _cv_x1, _cp_y, _cv_x2, _ecm_strip_bottom)) {
		            var _max_offset = max(0, _cp_real_total - _cp_cnt);
		            if (mouse_wheel_up())   _m.char_strip_offset = max(0, _m.char_strip_offset - 1);
		            if (mouse_wheel_down()) _m.char_strip_offset = min(_max_offset, _m.char_strip_offset + 1);
		            if (mouse_check_button_pressed(mb_middle) or keyboard_check_pressed(vk_space)) {
		                _m.strip_drag_active = true;
		                _m.strip_drag_start_mx = _mx;
		                _m.strip_drag_start_offset = _m.char_strip_offset;
		            }
		        }
		        if (variable_struct_exists(_m, "strip_drag_active") && _m.strip_drag_active) {
		            var _max_offset = max(0, _cp_real_total - _cp_cnt);
		            var _drag_delta = (_m.strip_drag_start_mx - _mx) div (_cp_sz + 2);
		            _m.char_strip_offset = clamp(_m.strip_drag_start_offset + _drag_delta, 0, _max_offset);
		            if (mouse_check_button_released(mb_middle) or keyboard_check_released(vk_space)) _m.strip_drag_active = false;
		        }
		    } else {
			var _cp_cnt   = floor((_cv_x2 - _cv_x1) / (_cp_sz + 2)) - 2;
			var _cp_total = (_chr_asset_ref != noone) ? _chr_asset_ref.meta.char_count : 256;
			var _cp_start = _m.char_strip_offset;

		    draw_set_color(make_color_rgb(200, 255, 255));
		    draw_text(_cv_x1, _cp_y , "TILE");
			
for (var _pi = 0; _pi < _cp_cnt; _pi++) {
			    var _ci = _cp_start + _pi;
			    if (_ci >= _cp_total) break;
		        var _px1  = _cv_x1 + 45 + _pi * (_cp_sz + 2);
		        var _phov = point_in_rectangle(_mx, _my, _px1, _cp_y, _px1 + _cp_sz, _cp_y + _cp_sz);
		        var _sel  = (_m.active_char == _ci);

		        draw_set_color(_sel ? make_color_rgb(60, 120, 80) : scr_c64_pepto_colour(_global_bg));
		        draw_rectangle(_px1, _cp_y, _px1 + _cp_sz, _cp_y + _cp_sz, false);


				if (_chr_asset_ref != noone &&
	            buffer_exists(_chr_asset_ref.buffer) &&
	            _global_mixed == 1 && _paint_mc == 1) {
	            // MC strip render — direct buffer, same as canvas
	            var _strip_res_bg   = _global_bg;
				var _strip_res_col1 = (_m.map_mc_col1 >= 0) ? _m.map_mc_col1 : _chr_asset_ref.meta.mc_col1;
	            var _strip_res_col2 = (_m.map_mc_col2 >= 0) ? _m.map_mc_col2 : _chr_asset_ref.meta.mc_col2;
	            var _strip_col3     = _m.active_colour & 0x07;
	            var _strip_palette  = [
	                scr_c64_pepto_colour(_global_bg),
	                scr_c64_pepto_colour(_strip_res_col1),
	                scr_c64_pepto_colour(_strip_res_col2),
	                scr_c64_pepto_colour(_strip_col3)
	            ];
	            var _spxw = max(1, (_cp_sz - 4) / 4);
	            var _spxh = max(1, (_cp_sz - 4) / 8);
	            draw_set_color(_strip_palette[0]);
	            draw_rectangle(_px1 + 2, _cp_y + 2, _px1 + _cp_sz - 2, _cp_y + _cp_sz - 2, false);
	            for (var _sr = 0; _sr < 8; _sr++) {
	                var _sboff = (_ci * 8) + _sr;
	                if (_sboff >= buffer_get_size(_chr_asset_ref.buffer)) break;
	                var _sbyte = buffer_peek(_chr_asset_ref.buffer, _sboff, buffer_u8);
	                for (var _sp = 0; _sp < 4; _sp++) {
	                    var _sbits = (_sbyte >> (6 - _sp * 2)) & 0x03;
	                    if (_sbits == 0) continue;
	                    draw_set_color(_strip_palette[_sbits]);
	                    var _spx = _px1 + 2 + _sp * _spxw;
	                    var _spy = _cp_y + 2 + _sr * _spxh;
	                    draw_rectangle(_spx, _spy, _spx + _spxw, _spy + _spxh, false);
	                }
	            }
	        } else if (_chr_asset_ref != noone &&
	            variable_struct_exists(_chr_asset_ref.meta, "preview_surf_clean") &&
	            surface_exists(_chr_asset_ref.meta.preview_surf_clean)) {
	            var _st_pxw = max(1, (_cp_sz - 4) / 8);
		    var _st_pxh = max(1, (_cp_sz - 4) / 8);
		var _strip_hr_col = 0;
		    if (_global_mixed == 0) {
		        _strip_hr_col = _m.active_colour & 0x0F;
		    } else {
		        _strip_hr_col = _m.active_colour & 0x07;
		    }
		    draw_set_color(scr_c64_pepto_colour(_global_bg));
		    draw_rectangle(_px1 + 2, _cp_y + 2, _px1 + _cp_sz - 2, _cp_y + _cp_sz - 2, false);
		    draw_set_color(scr_c64_pepto_colour(_strip_hr_col));
		    for (var _str = 0; _str < 8; _str++) {
		        var _stboff = (_ci * 8) + _str;
		        if (_stboff >= buffer_get_size(_chr_asset_ref.buffer)) break;
		        var _stbyte = buffer_peek(_chr_asset_ref.buffer, _stboff, buffer_u8);
		        for (var _stbit = 0; _stbit < 8; _stbit++) {
		            if (_stbyte & (0x80 >> _stbit)) {
		                draw_rectangle(
		                    _px1 + 2 + _stbit * _st_pxw, _cp_y + 2 + _str * _st_pxh,
		                    _px1 + 2 + _stbit * _st_pxw + _st_pxw, _cp_y + 2 + _str * _st_pxh + _st_pxh,
		                    false);
		            }
		        }
		    }
	        } else {
	            draw_set_font(fnt_c64_tiny);
	            draw_set_color(c_gray);
	            draw_set_halign(fa_center);
	            draw_text(_px1 + _cp_sz * 0.5, _cp_y + 6, string(_ci));
	            draw_set_halign(fa_left);
	        }

		        if (_sel) {
		            draw_set_color(c_white);
		            draw_rectangle(_px1 - 2, _cp_y - 2, _px1 + _cp_sz + 2, _cp_y + _cp_sz + 2, true);
		            draw_rectangle(_px1 - 1, _cp_y - 1, _px1 + _cp_sz + 1, _cp_y + _cp_sz + 1, true);
		            draw_rectangle(_px1, _cp_y, _px1 + _cp_sz, _cp_y + _cp_sz, true);
		        }
		       if (_phov && mouse_check_button_pressed(mb_left)) {
            _m.active_char = _ci;
        }
    }
	
    // Char strip scroll (wheel over strip area)
			if (point_in_rectangle(_mx, _my, _cv_x1, _cp_y - 4, _cv_x2, _cp_y + _cp_sz + 4)) {
			        var _max_offset = max(0, _cp_total - _cp_cnt);
			        if (mouse_wheel_up())   _m.char_strip_offset = max(0, _m.char_strip_offset - 1);
			        if (mouse_wheel_down()) _m.char_strip_offset = min(_max_offset, _m.char_strip_offset + 1);
			        // Middle mouse drag to scroll strip
			        if (mouse_check_button_pressed(mb_middle) or keyboard_check_pressed(vk_space)) {
			            _m.strip_drag_active = true;
			            _m.strip_drag_start_mx = _mx;
			            _m.strip_drag_start_offset = _m.char_strip_offset;
			        }
			    }
			    // Strip drag continues even if mouse leaves strip area
			    if (variable_struct_exists(_m, "strip_drag_active") && _m.strip_drag_active) {
			        var _max_offset = max(0, _cp_total - _cp_cnt);
			        var _drag_delta = (_m.strip_drag_start_mx - _mx) div (_cp_sz + 2);
			        _m.char_strip_offset = clamp(_m.strip_drag_start_offset + _drag_delta, 0, _max_offset);
		        if (mouse_check_button_released(mb_middle) or keyboard_check_released(vk_space)) _m.strip_drag_active = false;
		    
				}
			}
		} break;  // end MAP_DATA

case "SFX_DATA": {
    var _instrs   = variable_struct_exists(_asset.meta, "instruments")
                  ? _asset.meta.instruments : [];
    var _icount   = array_length(_instrs);
    var _sng_name = variable_struct_exists(_asset.meta, "song_name")
                  ? _asset.meta.song_name : "";

    draw_set_font(fnt_c64_tiny);

    // Song name
    if (_sng_name != "") {
        draw_set_color(make_color_rgb(120, 80, 200));
        draw_text(_vx1 + 10, _cy, "SONG:");
        draw_set_color(c_white);
        draw_text(_vx1 + 52, _cy, _sng_name);
        _cy += 16;
    }

    // Instrument count
    draw_set_color(make_color_rgb(120, 80, 200));
    draw_text(_vx1 + 10, _cy, "INSTRUMENTS:");
    draw_set_color(c_white);
    draw_text(_vx1 + 106, _cy, string(_icount));
    _cy += 24;

    if (_icount == 0) {
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_text(_vx1 + 10, _cy, "NO INSTRUMENTS  —  CLICK LOAD FILE TO IMPORT .SNG");
        _cy += 16;
        break;
    }

    // ── Instrument summary table ──────────────────────────────────────────
    var _cx_idx  = _vx1 + 10;
    var _cx_name = _vx1 + 38;
    var _cx_ad   = _vx1 + 160;
    var _cx_sr   = _vx1 + 210;
    var _cx_wpos = _vx1 + 260;
    var _cx_rows = _vx1 + 310;

    draw_set_color(make_color_rgb(130, 120, 90));
    draw_text(_cx_idx,  _cy, "#");
    draw_text(_cx_name, _cy, "NAME");
    draw_text(_cx_ad,   _cy, "AD");
    draw_text(_cx_sr,   _cy, "SR");
    draw_text(_cx_wpos, _cy, "WPOS");
    draw_text(_cx_rows, _cy, "ROWS");
    _cy += 18;

    draw_set_color(make_color_rgb(40, 40, 60));
    draw_line(_vx1 + 8, _cy, _vx2 - 8, _cy);
    _cy += 6;

    for (var _ii = 0; _ii < _icount; _ii++) {
        var _ins     = _instrs[_ii];
        var _row_col = (_ii mod 2 == 0)
                     ? make_color_rgb(22, 22, 35)
                     : make_color_rgb(18, 18, 28);
        draw_set_color(_row_col);
        draw_rectangle(_vx1 + 8, _cy, _vx2 - 8, _cy + 18, false);

        draw_set_font(fnt_c64_code);
        draw_set_color(make_color_rgb(100, 80, 160));
        draw_text(_cx_idx,  _cy + 2, string(_ii));
        draw_set_color(make_color_rgb(210, 170, 255));
        draw_text(_cx_name, _cy + 2, _ins.name);
        draw_set_color(c_aqua);
        draw_text(_cx_ad,   _cy + 2, "$" + string_upper(decimal_to_hex(_ins.ad)));
        draw_text(_cx_sr,   _cy + 2, "$" + string_upper(decimal_to_hex(_ins.sr)));
        draw_text(_cx_wpos, _cy + 2, "$" + string_upper(decimal_to_hex(_ins.wave_pos)));
        var _nr = array_length(_ins.wavetable_rows);
        draw_set_color(_nr > 0 ? c_lime : make_color_rgb(80, 80, 80));
        draw_text(_cx_rows, _cy + 2, string(_nr));
        _cy += 18;
    }
    _cy += 16;

    // ── Wavetable column view ─────────────────────────────────────────────
    if (!variable_struct_exists(_asset.meta, "wavetable") ||
        _asset.meta.wavetable == noone) break;

    var _wt  = _asset.meta.wavetable;
    var _wtn = array_length(_wt.left);

    // Column layout constants
    var _col_w      = 120; // px per instrument column
    var _row_h      = 20;
    var _hdr_h      = 28;
    var _vis_cols = max(1, min(floor((_vx2 - _vx1 - 20) / _col_w), _icount));

    // Scroll state — stored on meta so it persists while viewer is open
    if (!variable_struct_exists(_asset.meta, "sfx_col_offset"))
        _asset.meta.sfx_col_offset = 0;
    if (!variable_struct_exists(_asset.meta, "sfx_row_offset"))
        _asset.meta.sfx_row_offset = 0;

    // Arrow key column scroll (only when viewer mouse is hovering)
    if (point_in_rectangle(_mx, _my, _vx1, _cy, _vx2, _vy2)) {
        if (keyboard_check_pressed(vk_left))
            _asset.meta.sfx_col_offset = max(0, _asset.meta.sfx_col_offset - 1);
        if (keyboard_check_pressed(vk_right))
            _asset.meta.sfx_col_offset = min(_icount - _vis_cols, _asset.meta.sfx_col_offset + 1);

        // Find max rows across visible instruments for scroll clamping
        var _max_rows = 0;
        for (var _ci = 0; _ci < _icount; _ci++)
            _max_rows = max(_max_rows, array_length(_instrs[_ci].wavetable_rows));
        var _vis_rows   = floor((_vy2 - _cy - _hdr_h - 20) / _row_h);
        var _max_scroll = max(0, _max_rows - _vis_rows);
        if (mouse_wheel_up())   _asset.meta.sfx_row_offset = max(0, _asset.meta.sfx_row_offset - 1);
        if (mouse_wheel_down()) _asset.meta.sfx_row_offset = min(_max_scroll, _asset.meta.sfx_row_offset + 1);
    }

    var _col_offset = _asset.meta.sfx_col_offset;
    var _row_offset = _asset.meta.sfx_row_offset;

    // Section label + arrow hints
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(130, 120, 90));
    draw_text(_vx1 + 10, _cy, "WAVETABLE  (" + string(_wtn) + " rows)");
    if (_icount > _vis_cols) {
        draw_set_color(_col_offset > 0
            ? make_color_rgb(200, 160, 255) : make_color_rgb(50, 50, 70));
        draw_text(_vx1 + 10, _cy + 12, "< LEFT");
        draw_set_color(_col_offset < _icount - _vis_cols
            ? make_color_rgb(200, 160, 255) : make_color_rgb(50, 50, 70));
        draw_text(_vx1 + 56, _cy + 12, "RIGHT >");
    }
    _cy += (_icount > _vis_cols) ? 28 : 16;

    // Column colours — one per instrument
    var _owner_cols = [
        make_color_rgb(160, 100, 255),
        make_color_rgb(255, 190,  60),
        make_color_rgb( 60, 210, 160),
        make_color_rgb(255,  80, 130),
        make_color_rgb( 80, 170, 255),
        make_color_rgb(255, 140,  60),
    ];

    // Column headers
    for (var _ci = 0; _ci < _vis_cols; _ci++) {
        var _ii  = _ci + _col_offset;
        if (_ii >= _icount) break;
        var _cx2 = _vx1 + 10 + _ci * _col_w;
        var _hcol = _owner_cols[_ii mod array_length(_owner_cols)];

        draw_set_color(make_color_rgb(25, 20, 35));
        draw_rectangle(_cx2, _cy, _cx2 + _col_w - 4, _cy + _hdr_h - 2, false);
        draw_set_color(_hcol);
        draw_rectangle(_cx2, _cy, _cx2 + _col_w - 4, _cy + 3, false); // colour bar top
        draw_set_font(fnt_c64_code);
        draw_text(_cx2 + 4, _cy + 6, string(_ii) + ": " + _instrs[_ii].name);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(100, 100, 120));
       // var _nr2 = array_length(_instrs[_ii].wavetable_rows);
       // draw_text(_cx2 + 4, _cy + 18, string(_nr2) + " rows");
    }
    _cy += _hdr_h;

    // Divider
    draw_set_color(make_color_rgb(50, 50, 70));
    draw_line(_vx1 + 8, _cy, _vx2 - 8, _cy);
    _cy += 4;

    // Rows
    var _ref_reserve = 60; // space for REFERENCED BY block below wavetable
    var _vis_rows = floor((_vy2 - _cy - _ref_reserve) / _row_h);
    // Find max rows across all instruments to know how many rows to render
    var _max_rows = 0;
    for (var _ci = 0; _ci < _icount; _ci++)
        _max_rows = max(_max_rows, array_length(_instrs[_ci].wavetable_rows));

    for (var _ri = 0; _ri < _vis_rows; _ri++) {
        var _ridx = _ri + _row_offset;
        if (_ridx >= _max_rows) break;

        var _ry = _cy + _ri * _row_h;

        // Row stripe
        draw_set_color((_ri mod 2 == 0)
            ? make_color_rgb(18, 18, 28) : make_color_rgb(22, 22, 35));
        draw_rectangle(_vx1 + 8, _ry, _vx2 - 8, _ry + _row_h - 1, false);

        // Row index (shared, leftmost)
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(55, 55, 75));
        var _ri_hex = string_upper(decimal_to_hex(_ridx + 1));
        if (string_length(_ri_hex) < 2) _ri_hex = "0" + _ri_hex;
        draw_text(_vx1 + 10, _ry + 1, _ri_hex + ":");

        // Each instrument column
        for (var _ci = 0; _ci < _vis_cols; _ci++) {
            var _ii  = _ci + _col_offset;
            if (_ii >= _icount) break;
            var _cx2  = _vx1 + 28 + _ci * _col_w;
            var _hcol = _owner_cols[_ii mod array_length(_owner_cols)];
            var _rows = _instrs[_ii].wavetable_rows;

            if (_ridx < array_length(_rows)) {
                var _wrow = _rows[_ridx];
                var _L    = _wt.left[_wrow.row - 1];
                var _R    = _wt.right[_wrow.row - 1];
                draw_set_font(fnt_c64_code);
                draw_set_color(_hcol);
                draw_text(_cx2, _ry + 1,
                    string_upper(decimal_to_hex(_L)) + " "
                    + string_upper(decimal_to_hex(_R)));
            } else {
                // This instrument has no row here — dash
                draw_set_font(fnt_c64_tiny);
                draw_set_color(make_color_rgb(35, 35, 50));
                draw_text(_cx2 + 14, _ry + 2, "--");
            }
        }
    }

    // Scroll indicator
    if (_max_rows > _vis_rows) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 80, 100));
        draw_text(_vx1 + 10, _cy + _vis_rows * _row_h + 2,
            "... " + string(_max_rows - _vis_rows - _row_offset) + " more rows  (SCROLL)");
    }
} break;

case "SPRITE_SET": {
        // EDIT SPRITES button — opens the V2 built-in sprite editor.
        var _v2bx1 = _vx1 + 10;
        var _v2bx2 = _v2bx1 + 150;
        var _v2by1 = _cy;
        var _v2by2 = _cy + 22;
        spred64_v2_btn_y = _v2by1; // store for Step click detection
        var _v2_open = (spred64_v2.active && spred64_v2.asset_index == viewer_asset);
        var _v2_hov  = point_in_rectangle(_mx, _my, _v2bx1, _v2by1, _v2bx2, _v2by2);
        draw_set_color(_v2_open
            ? make_color_rgb(180, 80, 40)
            : (_v2_hov ? make_color_rgb(255, 180, 60) : make_color_rgb(120, 60, 20)));
        draw_rectangle(_v2bx1, _v2by1, _v2bx2, _v2by2, false);
        draw_set_color(make_color_rgb(255, 220, 120));
        draw_rectangle(_v2bx1, _v2by1, _v2bx2, _v2by2, true);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(_v2_hov ? c_black : c_white);
        draw_set_halign(fa_center);
        if (_v2_open) {
            draw_text(_v2bx1 + 72, _v2by1 + 2, "CLOSE (COMMIT EDITS)");
        } else {
            draw_text(_v2bx1 + 72, _v2by1 + 2, "EDIT SPRITES");
        }
        draw_set_halign(fa_left);

        // ── EXPORT SPRED64 — right of the EDIT SPRITES button ─────────────────
        var _esx1 = _v2bx2 + 8;
        var _esx2 = _esx1 + 150;
        var _es_hov = point_in_rectangle(_mx, _my, _esx1, _v2by1, _esx2, _v2by2);
        draw_set_color(_es_hov ? make_color_rgb(40, 140, 80) : make_color_rgb(20, 80, 40));
        draw_rectangle(_esx1, _v2by1, _esx2, _v2by2, false);
        draw_set_color(_es_hov ? c_white : c_ltgray);
        draw_rectangle(_esx1, _v2by1, _esx2, _v2by2, true);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(_es_hov ? c_white : c_ltgray);
        draw_set_halign(fa_center);
        draw_text(_esx1 + 75, _v2by1 + 2, "EXPORT SPRED64");
        draw_set_halign(fa_left);

        if (_es_hov && mouse_check_button_pressed(mb_left)
        && !global.ui_click_consumed && !global.any_picker_open) {
            var _spr_base = _asset.name;
            var _spr_path = get_save_filename("Spred64 Text (*.txt)|*.txt", _spr_base + ".txt");
            if (_spr_path != "") {
                scr_asset_spr_export_spred64(_asset, _spr_path);
            }
            global.ui_click_consumed = true;
        }
        // ── END EXPORT SPRED64 ────────────────────────────────────────────────

        _cy += 30;

        // If V2 is active on this asset, hand off the entire viewer area to it
        // and skip the rest of the existing SPRITE_SET render.
        if (_v2_open) {
            scr_spred64_v2_draw(_asset, _vx1, _cy, _vx2, _vy2, _mx, _my);
            break;
        }

        if (!variable_struct_exists(_asset.meta, "spr_sprites")) break;

        if (variable_struct_exists(_asset.meta, "bg_col")) {
            draw_set_font(fnt_c64_tiny);
            draw_set_color(c_ltgray); draw_text(_vx1 + 10, _cy, "BG:");
            draw_set_color(scr_c64_pepto_colour(_asset.meta.bg_col));
            draw_rectangle(_vx1 + 36, _cy, _vx1 + 52, _cy + 12, false);
            draw_set_color(c_white);
            draw_text(_vx1 + 56, _cy, string(_asset.meta.bg_col));
            draw_set_color(c_ltgray); draw_text(_vx1 + 90, _cy, "MC1:");
            draw_set_color(scr_c64_pepto_colour(_asset.meta.mc1_col));
            draw_rectangle(_vx1 + 120, _cy, _vx1 + 136, _cy + 12, false);
            draw_set_color(c_white);
            draw_text(_vx1 + 140, _cy, string(_asset.meta.mc1_col));
            draw_set_color(c_ltgray); draw_text(_vx1 + 174, _cy, "MC2:");
            draw_set_color(scr_c64_pepto_colour(_asset.meta.mc2_col));
            draw_rectangle(_vx1 + 204, _cy, _vx1 + 220, _cy + 12, false);
            draw_set_color(c_white);
            draw_text(_vx1 + 224, _cy, string(_asset.meta.mc2_col));
            if (!variable_struct_exists(_asset.meta, "has_colour") || !_asset.meta.has_colour) {
                draw_set_color(c_orange);
                draw_text(_vx1 + 270, _cy, "(DEFAULTS - BINARY HAS NO COLOUR)");
            }
        }
        _cy += 20;

        draw_set_font(fnt_c64_code);
        draw_set_color(make_color_rgb(60,60,80));
        draw_line(_vx1 + 10, _cy, _vx1 + 290, _cy);
        _cy += 16;
        draw_set_color(c_ltgray);
        draw_text(_vx1 + 10, _cy, "REFERENCED BY:");
        _cy += 18;
        var _ref_count = 0;
        with (obj_c64_node) {
            var _ref_name = "";
switch (node_type) {
            case "MACRO_BMP": case "MACRO_SPR": case "MACRO_SID": case "MACRO_SFX": case "MACRO_MAP": case "MACRO_CHR": case "MACRO_LOADER": case "MACRO_SID_SONG":
                if (array_length(instructions[0]) > 1)
                    _ref_name = string(instructions[0][1]);
                break;
			case "MACRO_TEXT_SCROLL":
                if (array_length(instructions[0]) > 10)
                    _ref_name = string(instructions[0][10]);
                break;
            case "NEW_STR":
                if ((array_length(instructions[0]) > 4 && is_real(instructions[0][4]) && real(instructions[0][4]) == 1) &&
                    array_length(instructions[0]) > 5)
                    _ref_name = string(instructions[0][5]);
                break;
        }
            if (_ref_name == _asset.name) {
                draw_set_font(fnt_c64_tiny);
                draw_set_color(c_yellow);
                draw_text(_vx1 + 20, _cy, node_title + " @ $" + string_upper(decimal_to_hex(pc_address)));
                _cy += 16;
                _ref_count++;
            }
        }
        if (_ref_count == 0) {
            draw_set_font(fnt_c64_tiny);
            draw_set_color(make_color_rgb(80,80,80));
            draw_text(_vx1 + 20, _cy, "NONE - ASSET NOT IN USE");
            _cy += 16;
        }
        _cy -= 20;

        var _hover_si = -1;
        var _cell_w       = 24 * 3 + 4;
        var _cell_h       = 21 * 3 + 4;
        var _cols         = 8;
        // Show only the sprites this asset actually uses, plus one trailing
        // "+" cell to append a blank sprite (up to the 64-slot cap).
        var _used         = clamp(_asset.meta.used_count, 1, 64);
        var _add_slot     = (_used < 64) ? _used : -1; // -1 = bank full, no + cell
        var _grid_total_w = _cols * _cell_w;
        var _grid_x       = _vx1 + (_vw * 0.5) - (_grid_total_w * 0.5);
        var _grid_y       = _cy;

        // Hover over a real sprite cell
        for (var _si = 0; _si < _used; _si++) {
            var _sx = _grid_x + (_si mod _cols) * _cell_w;
            var _sy = _grid_y + (_si div _cols) * _cell_h;
            if (point_in_rectangle(_mx, _my, _sx, _sy, _sx + _cell_w - 2, _sy + _cell_h - 2)) {
                _hover_si = _si;
                break;
            }
        }

        // Hover over the + add cell
        var _add_hover = false;
        if (_add_slot >= 0) {
            var _asx = _grid_x + (_add_slot mod _cols) * _cell_w;
            var _asy = _grid_y + (_add_slot div _cols) * _cell_h;
            _add_hover = point_in_rectangle(_mx, _my, _asx, _asy,
                _asx + _cell_w - 2, _asy + _cell_h - 2);
        }

        // Click a picker thumbnail = open V2 already focused on that slot.
        // V2 isn't active yet (we're in the closed-viewer branch), so it's
        // safe to set its selected_slot before opening. The open call seeds
        // selected_slot = 0 by default, so we override it right after.
        if (_hover_si >= 0 && mouse_check_button_pressed(mb_left)
        && !global.ui_click_consumed && !global.any_picker_open) {
            scr_spred64_v2_open(viewer_asset);
            spred64_v2.selected_slot = _hover_si;
            // Force edit-surface rebuild so the new slot's bits render immediately
            if (surface_exists(spred64_v2.edit_surface)) {
                surface_free(spred64_v2.edit_surface);
            }
            spred64_v2.edit_surface = -1;
            // Cooldown — suppresses canvas paint for a few frames so the
            // opening click doesn't bleed through to a held-button paint.
            // Also consume the click for any other same-frame handlers.
            spred64_v2.paint_cooldown = 5;
            global.ui_click_consumed = true;
        }

        // + add cell click — append a blank sprite straight to the asset.
        if (_add_slot >= 0 && _add_hover && mouse_check_button_pressed(mb_left)
        && !global.ui_click_consumed && !global.any_picker_open) {
            scr_asset_spr_add_blank_slot(_asset);
            global.ui_click_consumed = true;
        }

        // Crisp pixels for sprite thumbnails — no bilinear blur on 1.5x scale.
        gpu_set_tex_filter(false);
        for (var _si = 0; _si < _used; _si++) {
            var _sx = _grid_x + (_si mod _cols) * _cell_w;
            var _sy = _grid_y + (_si div _cols) * _cell_h;
            // Cell background = the C64 BG colour (so sprite transparency
            // composites correctly). Hover state is shown via the border
            // only, not by tinting the BG, so the colour stays accurate.
            var _cell_bg_idx = variable_struct_exists(_asset.meta, "bg_col") ? _asset.meta.bg_col : 0;
            draw_set_color(scr_c64_pepto_colour(_cell_bg_idx));
            draw_rectangle(_sx, _sy, _sx + _cell_w - 2, _sy + _cell_h - 2, false);
            if (_asset.meta.spr_sprites[_si] != -1 && sprite_exists(_asset.meta.spr_sprites[_si])) {
                // Cached sprite is 48x42; at 1.5x scale it lands at 72x63
                // matching the cell. (Cell is 24*3 + 4 chrome.)
                draw_sprite_ext(_asset.meta.spr_sprites[_si], 0, _sx, _sy, 1.5, 1.5, 0, c_white, 1);
            }
            // No else — unused slots keep the C64 BG fill we painted above,
            // matching how the V2 picker shows empty slots and how a real
            // sprite bank looks when slots are blank.
            
            if (_si == _hover_si) {
                draw_set_color(c_white);
                draw_rectangle(_sx, _sy, _sx + _cell_w - 2, _sy + _cell_h - 2, true);
            } else {
                draw_set_color(make_color_rgb(40,40,60));
                draw_rectangle(_sx, _sy, _sx + _cell_w - 2, _sy + _cell_h - 2, true);
            }
            draw_set_font(fnt_c64_tiny);
            draw_set_color(make_color_rgb(160,160,80));
            draw_text(_sx + 2, _sy + _cell_h - 20, string(_si));
        }

        // ----- "+" ADD-SLOT CELL -----
        if (_add_slot >= 0) {
            var _asx = _grid_x + (_add_slot mod _cols) * _cell_w;
            var _asy = _grid_y + (_add_slot div _cols) * _cell_h;
            draw_set_color(_add_hover
                ? make_color_rgb(40, 90, 50)
                : make_color_rgb(24, 40, 28));
            draw_rectangle(_asx, _asy, _asx + _cell_w - 2, _asy + _cell_h - 2, false);
            draw_set_color(_add_hover
                ? make_color_rgb(120, 255, 120)
                : make_color_rgb(80, 160, 90));
            draw_rectangle(_asx, _asy, _asx + _cell_w - 2, _asy + _cell_h - 2, true);
            draw_set_font(fnt_c64_code);
            draw_set_color(_add_hover ? c_white : make_color_rgb(120, 200, 130));
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            draw_text(_asx + (_cell_w - 2) * 0.5, _asy + (_cell_h - 2) * 0.5, "+");
            draw_set_halign(fa_left);
            draw_set_valign(fa_top);
        }

        // Row count includes the + cell so the info line clears the grid.
        var _grid_cells = _used + ((_add_slot >= 0) ? 1 : 0);
        var _rows   = ceil(_grid_cells / _cols);
        var _info_y = _grid_y + (_rows * _cell_h) + 8;

        if (_hover_si >= 0) {
            var _hmc = _asset.meta.sprite_mcs[_hover_si];
            var _huc = _asset.meta.sprite_ucs[_hover_si];
            draw_set_font(fnt_c64_tiny);
            draw_set_color(c_ltgray);  draw_text(_vx1 + 10,  _info_y, "SPRITE:");
            draw_set_color(c_white);   draw_text(_vx1 + 68,  _info_y, string(_hover_si));
            draw_set_color(c_ltgray);  draw_text(_vx1 + 100, _info_y, "MODE:");
            draw_set_color(_hmc ? make_color_rgb(200,120,40) : c_aqua);
            draw_text(_vx1 + 144, _info_y, _hmc ? "MULTICOLOUR" : "HIRES");
            draw_set_color(c_ltgray);  draw_text(_vx1 + 240, _info_y, "UC:");
            draw_set_color(scr_c64_pepto_colour(_huc));
            draw_rectangle(_vx1 + 266, _info_y, _vx1 + 280, _info_y + 10, false);
            draw_set_color(c_white);   draw_text(_vx1 + 284, _info_y, string(_huc));
        } else {
            draw_set_font(fnt_c64_tiny);
            draw_set_color(make_color_rgb(60,60,80));
            draw_text(_vx1 + 10, _info_y, "HOVER A SPRITE FOR INFO");
        }
        _cy = _info_y + 20;
    } break;

case "BITMAP": {
	        // Recalculate UI zoom cap to match display scale — keeps pixels consistent size
	        var _scale_f_cap = display_get_height() / window_get_height();
	        bmp_ui_zoom_cap = floor(bmp_ui_zoom_cap_base * _scale_f_cap * 1000) / 1000;
	        bmp_ui_zoom_cap = max(1.0, bmp_ui_zoom_cap);
	            
	        var _bmp_prev_filter = gpu_get_texfilter();
	        gpu_set_texfilter(true);
	        var _png_import_active_top = variable_struct_exists(_asset.meta, "png_import_mode") && _asset.meta.png_import_mode;
	        if (!_png_import_active_top &&
	            variable_struct_exists(_asset.meta, "preview_surf") &&
	            _asset.meta.preview_surf != -1 &&
	            !surface_exists(_asset.meta.preview_surf) &&
	            _asset.file != "") {
	            scr_asset_kla_reload(_asset);
                
	            // CRITICAL FIX: If the external reload script built a 160x200 surface, 
	            // we must stretch it to 320x200 so our editor tools, mask, and saving math align perfectly.
	            if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
	                if (surface_get_width(_asset.meta.preview_surf) != 320) {
	                    var _new_surf = surface_create(320, 200);
	                    surface_set_target(_new_surf);
	                    draw_surface_stretched(_asset.meta.preview_surf, 0, 0, 320, 200);
	                    surface_reset_target();
	                    surface_free(_asset.meta.preview_surf);
	                    _asset.meta.preview_surf = _new_surf;
	                }
	            }
	        }
			
			
			
			// UNDO/REDO STACK GUARDS — must exist before the surface-restore block above
			// reads undo_stack (F11/surface loss can trigger that read on the first frame).
		        if (!variable_struct_exists(_asset.meta, "undo_stack")) _asset.meta.undo_stack = [];
		        if (!variable_struct_exists(_asset.meta, "redo_stack")) _asset.meta.redo_stack = [];
		        if (!variable_struct_exists(_asset.meta, "undo_pending")) _asset.meta.undo_pending = false;

			// PIXEL BACKUP — keep a buffer mirror of the surface so F11/surface loss can restore
		        if (!variable_struct_exists(_asset.meta, "pixel_backup")) _asset.meta.pixel_backup = -1;
		        if (!variable_struct_exists(_asset.meta, "pixels_dirty")) _asset.meta.pixels_dirty = false;

		        // Seed backup immediately if surface is valid but backup does not yet exist
		        // This covers the case where a file is loaded and viewed without entering the editor
		        if (variable_struct_exists(_asset.meta, "preview_surf") &&
	            _asset.meta.preview_surf != -1 &&
	            surface_exists(_asset.meta.preview_surf) &&
	            !buffer_exists(_asset.meta.pixel_backup)) {
		            _asset.meta.pixel_backup = buffer_create(320 * 200 * 4, buffer_fixed, 1);
		            buffer_get_surface(_asset.meta.pixel_backup, _asset.meta.preview_surf, 0);
		        }
            
if (!variable_struct_exists(_asset.meta, "dirty_timer")) _asset.meta.dirty_timer = -1;
	        if (_asset.meta.pixels_dirty) {
	            _asset.meta.dirty_timer = 15;
	            _asset.meta.pixels_dirty = false;
	            // Snapshot pixels immediately so F11 surface loss can restore the latest strokes
	            if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
	                if (!buffer_exists(_asset.meta.pixel_backup)) {
	                    _asset.meta.pixel_backup = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                }
	                buffer_get_surface(_asset.meta.pixel_backup, _asset.meta.preview_surf, 0);
	            }
	        }
	        if (_asset.meta.dirty_timer > 0) {
	            // Only tick down the auto-save timer if hands are off the controls
	            if (!mouse_check_button(mb_any) && !keyboard_check(vk_anykey)) {
	                _asset.meta.dirty_timer--;
	            } else {
	                // Reset the timer while actively drawing/typing so it waits 1 full second AFTER releasing
	                _asset.meta.dirty_timer = 12;
	            }
                
	            if (_asset.meta.dirty_timer == 0) {
	                // Only auto-save (and thus auto-clean) if the toggle is ON
	                if (_asset.meta.auto_clean && variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf) && buffer_exists(_asset.meta.pixel_backup)) {
					
	                    if (!buffer_exists(_asset.meta.pixel_backup)) {
	                        _asset.meta.pixel_backup = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                    }
	                    buffer_get_surface(_asset.meta.pixel_backup, _asset.meta.preview_surf, 0);
	                    scr_asset_kla_save(_asset);
	                    _asset.meta.bmp_unsaved = false;
	                }
	            }
	        }
            
	        // SURFACE RESTORE from backup buffer (catches F11 and any other surface loss)
	        // Skipped entirely while a PNG import is in progress: the PNG pipeline
	        // manages preview_surf itself (frees the old one, builds a fresh one
	        // from the new source), so an invalid preview_surf mid-import is
	        // EXPECTED, not surface loss. Without this guard, this block's
	        // fallback ("no backup -> reload from _asset.file") reloads the
	        // PREVIOUS committed KLA right on top of the import you just started.
	        var _png_import_active = variable_struct_exists(_asset.meta, "png_import_mode") && _asset.meta.png_import_mode;
	        if (!_png_import_active && variable_struct_exists(_asset.meta, "preview_surf") && !surface_exists(_asset.meta.preview_surf)) {
	            if (variable_struct_exists(_asset.meta, "pixel_backup") && buffer_exists(_asset.meta.pixel_backup)) {
           _asset.meta.preview_surf = surface_create(320, 200);
            // Prefer the top of the undo stack — it's always newer than pixel_backup.
            // Handle both new struct format and legacy raw buffers.
            var _undo_top = array_length(_asset.meta.undo_stack) - 1;
            var _restored_from_undo = false;
            if (_undo_top >= 0) {
                var _top_entry = _asset.meta.undo_stack[_undo_top];
                if (is_struct(_top_entry) && buffer_exists(_top_entry.buf)) {
                    buffer_set_surface(_top_entry.buf, _asset.meta.preview_surf, 0);
                    buffer_copy(_top_entry.buf, 0, 320 * 200 * 4, _asset.meta.pixel_backup, 0);
                    _restored_from_undo = true;
                } else if (buffer_exists(_top_entry)) {
                    buffer_set_surface(_top_entry, _asset.meta.preview_surf, 0);
                    buffer_copy(_top_entry, 0, 320 * 200 * 4, _asset.meta.pixel_backup, 0);
                    _restored_from_undo = true;
                }
            }
            if (!_restored_from_undo) {
                buffer_set_surface(_asset.meta.pixel_backup, _asset.meta.preview_surf, 0);
            }
        } else if (_asset.file != "") {
	                scr_asset_kla_reload(_asset);
	            }
	        }
			// COORDINATE DRIFT PROTECTION
	        // If the surface is valid but 160px wide, our 320px brush math will be offset by 2x.
	        if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
	            if (surface_get_width(_asset.meta.preview_surf) == 160) {
	                var _upscale = surface_create(320, 200);
	                surface_set_target(_upscale);
	                gpu_set_texfilter(false);
	                draw_surface_stretched(_asset.meta.preview_surf, 0, 0, 320, 200);
	                surface_reset_target();
	                surface_free(_asset.meta.preview_surf);
	                _asset.meta.preview_surf = _upscale;
	            }
	        }
			
			if (!variable_struct_exists(_asset.meta, "auto_clean")) _asset.meta.auto_clean = true;
	        if (!variable_struct_exists(_asset.meta, "bmp_zoom")) _asset.meta.bmp_zoom = bmp_ui_zoom_cap;
	        if (!variable_struct_exists(_asset.meta, "auto_clean")) _asset.meta.auto_clean = true;
	        if (!variable_struct_exists(_asset.meta, "clash_grid")) _asset.meta.clash_grid = array_create(1000, false);
            
	        // Mask tracking: 0 = Background (Absorbs changes), 1 = Explicitly Drawn (Protected)
	        if (!variable_struct_exists(_asset.meta, "bg_mask")) {
	            _asset.meta.bg_mask = array_create(64000, 0); 
	            // Only scan for pre-existing pixels if a file is actually loaded
	            _asset.meta.needs_mask_init = (_asset.file != ""); 
	        }
	        // HiRes cell-colour model: hr_role_mask[pixel] = which of the cell's 2
	        // colours this pixel uses (0 = bg-role, 1 = fg-role). hr_cell_fg_col /
	        // hr_cell_bg_col[cell] = the actual colour currently assigned to that
	        // role for that cell. Painting with LMB sets role=1 + updates the
	        // cell's fg colour; RMB sets role=0 + updates the cell's bg colour —
	        // either way the WHOLE cell's matching-role pixels repaint, matching
	        // real hardware (a cell only ever has 2 colours, shared cell-wide).
	        // Untouched cells default to role=0 everywhere + bg colour 0 (black).
	        if (!variable_struct_exists(_asset.meta, "hr_role_mask"))  _asset.meta.hr_role_mask  = array_create(64000, 0);
	        if (!variable_struct_exists(_asset.meta, "hr_cell_fg_col")) _asset.meta.hr_cell_fg_col = array_create(1000, 0);
	        if (!variable_struct_exists(_asset.meta, "hr_cell_bg_col")) _asset.meta.hr_cell_bg_col = array_create(1000, 0);
			// Stroke tracking for continuous fast drawing
	        if (!variable_struct_exists(_asset.meta, "last_px")) _asset.meta.last_px = undefined;
	        if (!variable_struct_exists(_asset.meta, "last_py")) _asset.meta.last_py = undefined;
	        if (!variable_struct_exists(_asset.meta, "bmp_pan_x")) _asset.meta.bmp_pan_x = 0;
	        if (!variable_struct_exists(_asset.meta, "bmp_pan_y")) _asset.meta.bmp_pan_y = 0;
	        if (!variable_struct_exists(_asset.meta, "undo_stack")) _asset.meta.undo_stack = [];
	        if (!variable_struct_exists(_asset.meta, "redo_stack")) _asset.meta.redo_stack = [];
	        if (!variable_struct_exists(_asset.meta, "undo_pending")) _asset.meta.undo_pending = false; 
            
			// SAFETY GATE: Ensure critical meta variables exist before local assignment
	        if (!variable_struct_exists(_asset.meta, "is_editing")) _asset.meta.is_editing = false;
	        if (!variable_struct_exists(_asset.meta, "auto_clean")) _asset.meta.auto_clean = true;
	        if (!variable_struct_exists(_asset.meta, "bmp_zoom"))   _asset.meta.bmp_zoom = bmp_ui_zoom_cap;
	        if (!variable_struct_exists(_asset.meta, "bmp_mode"))   _asset.meta.bmp_mode = "MC"; // "MC" or "HIRES" — defaults to Multicolour

	        var _is_ed = _asset.meta.is_editing;
	        var _has_canvas = variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf);
	        var _bmp_is_hires = scr_asset_bmp_is_hires(_asset);
	        var _bmp_step     = _bmp_is_hires ? 1 : 2; // world-px per addressable unit: 1 for HiRes, 2 for MC pairs
	        // _prev_input_blocked calculated after scale vars are set below
            
	        // TOP BUTTONS (Aligned with LOAD FILE)
	        // ── RETURN TO BITMAP BUILDER ──────────────────────────────────────
	        // Only shown when we arrived here via a builder's EDIT SRC/DST button
	        // (bb_return_asset holds that builder's index). Clicking it commits
	        // the current bitmap edit exactly like the EDIT toggle's exit path —
	        // save, drop edit mode, refresh node thumbnails — then repoints the
	        // viewer back at the builder and clears the breadcrumb.
	        if (variable_instance_exists(id, "bb_return_asset")
	        &&  bb_return_asset >= 0
	        &&  bb_return_asset < ds_list_size(asset_list)) {
	            // Dropped into the empty band below the toolbar row, sitting above
	            // the canvas. _vy1+80 clears the +38 button row; the x holds its
	            // old column so it stays under the toolbar buttons it belongs to.
	            var _rtb_x1  = _vx1 + 560;
	            var _rtb_x2  = _rtb_x1 + 220;
	            var _rtb_y1  = _vy1 + 80;
	            var _rtb_y2  = _rtb_y1 + 22;
	            var _rtb_hov = point_in_rectangle(_mx, _my, _rtb_x1, _rtb_y1, _rtb_x2, _rtb_y2);
	            draw_set_color(_rtb_hov ? make_color_rgb(180, 120, 255) : make_color_rgb(90, 50, 140));
	            draw_rectangle(_rtb_x1, _rtb_y1, _rtb_x2, _rtb_y2, false);
	            draw_set_color(_rtb_hov ? c_white : make_color_rgb(200, 160, 255));
	            draw_rectangle(_rtb_x1, _rtb_y1, _rtb_x2, _rtb_y2, true);
	            draw_set_font(fnt_c64_tiny);
	            draw_set_color(c_white);
	            draw_set_halign(fa_center);
	            draw_text((_rtb_x1 + _rtb_x2) * 0.5, _rtb_y1 + 5, "< RETURN TO BITMAP BUILDER");
	            draw_set_halign(fa_left);
	            if (_rtb_hov && mouse_check_button_pressed(mb_left)) {
	                // Commit the edit — same sequence as the EDIT button's exit path.
	                if (_asset.meta.is_editing) {
	                    gpu_set_texfilter(true);
	                    scr_asset_kla_save(_asset);
	                    _asset.meta.bmp_unsaved = false;
	                    _asset.meta.has_data    = true;
	                    _asset.meta.is_editing  = false;
	                    _asset.meta.last_px     = undefined;
	                    _asset.meta.last_py     = undefined;
	                    // Kill node thumbnail caches so the freshly edited pixels
	                    // show on any MACRO_BMP referencing this asset.
	                    with (all) {
	                        if (variable_instance_exists(id, "instructions")) {
	                            if (is_array(instructions) && array_length(instructions) > 0
	                            &&  string(instructions[0][1]) == _asset.name) {
	                                if (variable_instance_exists(id, "kla_filename")) {
	                                    kla_filename = filename_name(_asset.file);
	                                }
	                                if (variable_instance_exists(id, "preview_surf")) {
	                                    if (surface_exists(preview_surf)) surface_free(preview_surf);
	                                    preview_surf = -1;
	                                }
	                            }
	                        }
	                    }
	                    global.undo_dirty = true;
	                }
	                // Jump back to the builder and clear the breadcrumb. The builder's
	                // own prev_dirty path rebuilds its scratch preview next frame, so
	                // any edits to the source/dest bitmap show immediately.
	                viewer_asset    = bb_return_asset;
	                bb_return_asset = -1;
	                keyboard_string = "";
	                exit;
	            }
	        }

	        // REFERENCED BY — inline in header row
	        draw_set_font(fnt_c64_tiny);
	        draw_set_color(c_ltgray);
	        draw_text(_vx1 + 900, _vy1 + 43, "USED BY:");
	            
	        // PNG mode flag — needed early to gate several UI sections
	        var _png_mode = variable_struct_exists(_asset.meta, "png_import_mode") && _asset.meta.png_import_mode;
	        if (!variable_struct_exists(_asset.meta, "png_pending_bg")) _asset.meta.png_pending_bg = 0;
	            
	        // SOURCE FILE PATH ROW — shown below main buttons
	        var _src_path = variable_struct_exists(_asset.meta, "source_file") ? _asset.meta.source_file : _asset.file;
	        var _is_working_copy = (string_pos("_imported_", _asset.file) > 0);
	        // Truncate path from left if too long
	        var _path_label = (_is_working_copy ? "SRC: " : "FILE: ") + _src_path;
	        var _max_path_w = 840;
	        while (string_width(_path_label) > _max_path_w && string_length(_path_label) > 10) {
	            _path_label = "..." + string_copy(_path_label, 20, string_length(_path_label) - 19);
	        }
	        draw_set_color(_is_working_copy ? make_color_rgb(60, 120, 60) : make_color_rgb(60, 60, 80));
	        draw_set_color(_is_working_copy ? make_color_rgb(80, 160, 80) : make_color_rgb(100, 100, 120));
	        draw_text(_vx1 + 180, _vy1 + 106, _path_label);
	            
	        // RELOAD SOURCE button
	        if (_is_working_copy && !_png_mode && string_lower(filename_ext(_src_path)) != ".png") {
	            var _rsx1 = _vx1 + 870;
	            var _rsx2 = _rsx1 + 114;
	            var _rs_hov = point_in_rectangle(_mx, _my, _rsx1, _vy1 + 80, _rsx2, _vy1 + 97);
	            draw_set_color(_rs_hov ? make_color_rgb(180, 120, 40) : make_color_rgb(100, 70, 20));
	            draw_rectangle(_rsx1, _vy1 + 80, _rsx2, _vy1 + 97, false);
	            draw_set_color(_rs_hov ? c_yellow : c_ltgray);
	            draw_rectangle(_rsx1, _vy1 + 80, _rsx2, _vy1 + 97, true);
	            draw_set_color(_rs_hov ? c_yellow : c_white);
	            draw_text(_rsx1 + 4, _vy1 + 80, "RELOAD SOURCE");
	            if (_rs_hov && mouse_check_button_pressed(mb_left)) {
	                // Reload the working copy from the original source
	                   
	                file_copy(_src_path, _asset.file);
	                if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);
	                _asset.buffer = buffer_load(_asset.file);
	                if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
	                    surface_free(_asset.meta.preview_surf);
	                    _asset.meta.preview_surf = -1;
	                }
	                if (buffer_exists(_asset.meta.pixel_backup)) {
	                    buffer_delete(_asset.meta.pixel_backup);
	                    _asset.meta.pixel_backup = -1;
	                }
	                // Free any old struct-format undo entries cleanly before wiping
	                for (var _ui = 0; _ui < array_length(_asset.meta.undo_stack); _ui++) {
	                    var _ue = _asset.meta.undo_stack[_ui];
	                    if (is_struct(_ue) && buffer_exists(_ue.buf)) buffer_delete(_ue.buf);
	                    else if (buffer_exists(_ue)) buffer_delete(_ue);
	                }
	                for (var _ri = 0; _ri < array_length(_asset.meta.redo_stack); _ri++) {
	                    var _re = _asset.meta.redo_stack[_ri];
	                    if (is_struct(_re) && buffer_exists(_re.buf)) buffer_delete(_re.buf);
	                    else if (buffer_exists(_re)) buffer_delete(_re);
	                }
	                _asset.meta.undo_stack = [];
	                _asset.meta.redo_stack = [];
	                scr_asset_bmp_build_preview(_asset);
	            _asset.meta.bmp_unsaved = false;
	            }
	        }
	            
	        // ── EXPORT BUTTONS ────────────────────────────────────────────────────
	        if (_has_canvas && !_png_mode) {
	            var _ex_x1 = _vx1 + 992;  // right of RELOAD SOURCE (_vx1+870 + 114 + 8)
	            var _ex_x2 = _ex_x1 + 114;
	            var _ex_y  = _vy1 + 80;   // same row as RELOAD SOURCE
	                
	            // EXPORT PNG
	            var _epng_hov = point_in_rectangle(_mx, _my, _ex_x1, _ex_y, _ex_x2, _ex_y + 17);
	            draw_set_color(_epng_hov ? make_color_rgb(40, 120, 180) : make_color_rgb(20, 70, 110));
	            draw_rectangle(_ex_x1, _ex_y, _ex_x2, _ex_y + 17, false);
	            draw_set_color(_epng_hov ? c_white : c_ltgray);
	            draw_rectangle(_ex_x1, _ex_y, _ex_x2, _ex_y + 17, true);
	            draw_set_color(_epng_hov ? c_white : c_ltgray);
	            draw_text(_ex_x1 + 4, _ex_y , "EXPORT PNG");
	            if (_epng_hov && mouse_check_button_pressed(mb_left)) {
	                var _png_base = filename_name(_asset.file);
	                var _png_ext  = filename_ext(_png_base);
	                _png_base = string_copy(_png_base, 1, string_length(_png_base) - string_length(_png_ext));
	                var _png_path = get_save_filename("PNG Image (*.png)|*.png", _png_base + ".png");
	                if (_png_path != "" && variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
	                    surface_save(_asset.meta.preview_surf, _png_path);
	                }
	            }
	                
	            // EXPORT KLA — right of EXPORT PNG
	            var _ex_x3  = _ex_x2 + 8;
	            var _ex_x4  = _ex_x3 + 114;
	            var _ekla_hov = point_in_rectangle(_mx, _my, _ex_x3, _ex_y, _ex_x4, _ex_y + 17);
	            draw_set_color(_ekla_hov ? make_color_rgb(40, 140, 80) : make_color_rgb(20, 80, 40));
	            draw_rectangle(_ex_x3, _ex_y, _ex_x4, _ex_y + 17, false);
	            draw_set_color(_ekla_hov ? c_white : c_ltgray);
	            draw_rectangle(_ex_x3, _ex_y, _ex_x4, _ex_y + 17, true);
	            draw_set_color(_ekla_hov ? c_white : c_ltgray);
	            draw_text(_ex_x3 + 4, _ex_y , "EXPORT KLA");
	            if (_ekla_hov && mouse_check_button_pressed(mb_left)) {
	                var _kla_path = get_save_filename("Koala Painter (*.kla)|*.kla", filename_name(_asset.file));
	                if (_kla_path != "") {
	                    scr_asset_kla_save(_asset);
	                    file_copy(_asset.file, _kla_path);
	                }
	            }
	        }
	        // ── END EXPORT BUTTONS ────────────────────────────────────────────────
				
	        var _ref_inline_x = _vx1 + 750;
	        var _ref_found = false;
			bmp_ref_asset_name = _asset.name;
	        bmp_ref_vy1        = _vy1;
	        bmp_ref_found      = false;
	        bmp_ref_x          = _vx1 + 1000;
	        with (obj_c64_node) {
	            var _rn = "";
	            if (node_type == "MACRO_BMP" && array_length(instructions[0]) > 1)
	                _rn = string(instructions[0][1]);
	            if (_rn == other.bmp_ref_asset_name) {
	                other.bmp_ref_found = true;
	                draw_set_color(c_yellow);
	                draw_text(other.bmp_ref_x, other.bmp_ref_vy1 + 43, node_title + " $" + string_upper(decimal_to_hex(pc_address)));
	                other.bmp_ref_x += string_width(node_title + " $" + string_upper(decimal_to_hex(pc_address))) + 12;
	            }
	        }
			/*
	        if (!bmp_ref_found) {
	            draw_set_color(make_color_rgb(60, 60, 80));
	            draw_text(_vx1 + 780, _vy1 + 43, "NONE");
	        }
            */
			
	        // ── DRAGGABLE 320×200 PREVIEW WINDOW ──────────────────────────────────
	        if (!variable_struct_exists(_asset.meta, "prev_win_x"))      _asset.meta.prev_win_x      = 114;
	        if (!variable_struct_exists(_asset.meta, "prev_win_y"))      _asset.meta.prev_win_y      = 660;
	        if (!variable_struct_exists(_asset.meta, "prev_win_drag"))   _asset.meta.prev_win_drag   = false;
	        if (!variable_struct_exists(_asset.meta, "prev_win_drag_ox"))_asset.meta.prev_win_drag_ox = 0;
	        if (!variable_struct_exists(_asset.meta, "prev_win_drag_oy"))_asset.meta.prev_win_drag_oy = 0;
	        if (!variable_struct_exists(_asset.meta, "prev_win_visible"))_asset.meta.prev_win_visible = true;

	        //var _scale_f = display_get_height() / window_get_height();
	        //var _draw_w  = 320 * _scale_f;
	        //var _draw_h  = 200 * _scale_f;
	        //var _hdr_h   = 18 * _scale_f;
				
			var _scale_f = display_get_height() / window_get_height();
	        var _draw_w  = floor(320 * _scale_f);
	        var _draw_h  = floor(200 * _scale_f);
	        var _hdr_h   = floor(18 * _scale_f);
				
				
	        var _pw_x    = _asset.meta.prev_win_x;
	        var _pw_y    = _asset.meta.prev_win_y;
	        var _pw_w    = _draw_w;
	        var _pw_h    = _draw_h;
	        var _mx      = device_mouse_x_to_gui(0);
	        var _my      = device_mouse_y_to_gui(0);
	        var _gui_w   = display_get_gui_width();
	        var _gui_h   = display_get_gui_height();

	        // Input block now that scale vars exist
	        var _prev_input_blocked = _asset.meta.prev_win_drag ||
	            (_asset.meta.prev_win_visible && _has_canvas &&
	                point_in_rectangle(_mx, _my,
	                    _asset.meta.prev_win_x, _asset.meta.prev_win_y,
	                    _asset.meta.prev_win_x + _draw_w,
	                    _asset.meta.prev_win_y + _hdr_h + _draw_h));

	        if (!_prev_input_blocked) {
	            if (!_is_ed && mouse_wheel_up() && _has_canvas) {
	                _asset.meta.is_editing = true;
	                _is_ed = true;
	            }
	        }

	        // Toggle button — PREVIEW (aligned with source path row)
	        var _tog_x = _vx1 + 1240;
	        var _tog_y = _vy1 + 40;
	        var _tog_w = 70;
	        var _tog_h = 22;
	        var _tog_hover = point_in_rectangle(_mx, _my, _tog_x, _tog_y, _tog_x + _tog_w, _tog_y + _tog_h);
	        draw_set_font(fnt_c64_tiny);
	        draw_set_color(_asset.meta.prev_win_visible ? make_color_rgb(40,40,80) : make_color_rgb(25,25,40));
	        draw_rectangle(_tog_x, _tog_y, _tog_x + _tog_w, _tog_y + _tog_h, false);
	        draw_set_color(_tog_hover ? c_yellow : make_color_rgb(80,80,140));
	        draw_rectangle(_tog_x, _tog_y, _tog_x + _tog_w, _tog_y + _tog_h, true);
	        draw_set_color(_tog_hover ? c_yellow : (_asset.meta.prev_win_visible ? c_white : c_gray));
	        draw_text(_tog_x + 6, _tog_y + 2, "PREVIEW");
	        if (_tog_hover && mouse_check_button_pressed(mb_left))
	            _asset.meta.prev_win_visible = !_asset.meta.prev_win_visible;
            
// ── PREVIEW WINDOW: input blocking (update the existing var, don't redeclare) ──
	        var _prev_win_rect_hover = false;
	        if (_asset.meta.prev_win_visible && _has_canvas) {
	            _prev_win_rect_hover = point_in_rectangle(_mx, _my,
	                _pw_x, _pw_y, _pw_x + _pw_w, _pw_y + _hdr_h + _pw_h);
	        }
	        _prev_input_blocked = (_prev_win_rect_hover || _asset.meta.prev_win_drag);

	        // ── PREVIEW WINDOW: drag logic ──
	        if (_asset.meta.prev_win_visible && _has_canvas) {
	            var _in_hdr = point_in_rectangle(_mx, _my, _pw_x, _pw_y, _pw_x + _pw_w, _pw_y + _hdr_h);
	                
	            if (_in_hdr && mouse_check_button_pressed(mb_left)) {
	                _asset.meta.prev_win_drag    = true;
	                _asset.meta.prev_win_drag_ox = _pw_x - _mx;
	                _asset.meta.prev_win_drag_oy = _pw_y - _my;
	            }
	                
	            if (_asset.meta.prev_win_drag) {
	                if (mouse_check_button(mb_left)) {
	                    _asset.meta.prev_win_x = clamp(_mx + _asset.meta.prev_win_drag_ox, 0, _gui_w - _pw_w);
	                    _asset.meta.prev_win_y = clamp(_my + _asset.meta.prev_win_drag_oy, 0, _gui_h - (_pw_h + _hdr_h));
	                    _pw_x = _asset.meta.prev_win_x;
	                    _pw_y = _asset.meta.prev_win_y;
	                } else {
	                    _asset.meta.prev_win_drag = false;
	                }
	            }
	        }
	        // ── END PREVIEW WINDOW (draw deferred to end of case) ─────────────────


	        var _btn_y = _vy1 + 38; 
	        var _ebx1 = _vx1 + 120;
	        var _ebx2 = _ebx1 + 80;
	        var _eb_hov = point_in_rectangle(_mx, _my, _ebx1, _btn_y, _ebx2, _btn_y + 20);
	        draw_set_color(_eb_hov ? make_color_rgb(60, 180, 200) : (_is_ed ? make_color_rgb(20, 70, 90) : make_color_rgb(20, 70, 90)));
	        draw_rectangle(_ebx1, _btn_y, _ebx2, _btn_y + 20, false);
	        draw_set_font(fnt_c64_tiny);
	        draw_set_color(c_white);
	        draw_set_halign(fa_center);
	        var _btn_label = _has_canvas ? "EDIT" : "CREATE";
	        draw_text(_ebx1 + 40, _btn_y + 5, _btn_label);
            
if (_eb_hov && mouse_check_button_pressed(mb_left)) {
	            _asset.meta.is_editing = !_is_ed;
                
	            // Reset stroke tracking to prevent jump-lines when toggling edit mode
	            _asset.meta.last_px = undefined;
	            _asset.meta.last_py = undefined;

	            // EXITING EDITOR: Commit changes and broadcast to workspace
	            if (!_asset.meta.is_editing) {
	                gpu_set_texfilter(true);
	                scr_asset_kla_save(_asset);
	                // See RESAVE's comment — HiRes encode always forces every cell to
	                // exactly 2 colours, so the saved file can differ from an
	                // un-cleaned-up on-screen canvas. Rebuild from the just-saved
	                // bytes so what you see next time you open the editor matches
	                // what's actually on disk, without needing a forced reload.
	                scr_asset_bmp_build_preview(_asset);
	                if (!buffer_exists(_asset.meta.pixel_backup)) {
	                    _asset.meta.pixel_backup = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                }
	                buffer_get_surface(_asset.meta.pixel_backup, _asset.meta.preview_surf, 0);
	                _asset.meta.bmp_unsaved = false;
                    
	                // Force meta flag so nodes know data physically exists
	                _asset.meta.has_data = true;
                    
	                with (all) {
	                    if (variable_instance_exists(id, "instructions")) {
	                        if (is_array(instructions) && array_length(instructions) > 0 && string(instructions[0][1]) == _asset.name) {
	                            // Sync filename display
	                            if (variable_instance_exists(id, "kla_filename")) kla_filename = filename_name(_asset.file);
                                
	                            // Kill thumbnail cache to force redraw of new pixels
	                            if (variable_instance_exists(id, "preview_surf")) {
	                                if (surface_exists(preview_surf)) surface_free(preview_surf);
	                                preview_surf = -1;
	                            }
	                        }
	                    }
	                }
	                global.undo_dirty = true;
	            }

// ENTERING EDITOR: Initialize canvas and paths
            if (_asset.meta.is_editing) {
                
                // Ensure surface exists before we try to snapshot it
                if (!variable_struct_exists(_asset.meta, "preview_surf") || !surface_exists(_asset.meta.preview_surf)) {
                    _asset.meta.preview_surf = surface_create(320, 200);
                    surface_set_target(_asset.meta.preview_surf);
                    draw_clear(scr_c64_pepto_colour(0));
                    surface_reset_target();
                    
                    if (!variable_struct_exists(_asset.meta, "bg_col")) _asset.meta.bg_col = 0;
                    
                    // Path Assignment for brand new assets only
                    if (_asset.file == "" || _asset.file == undefined) {
                        var _save_dir = working_directory + "bitmaps";
                        if (!directory_exists(_save_dir)) directory_create(_save_dir);
                        _asset.file = _save_dir + "/" + _asset.name + ".kla";
                    }
                    
                    _asset.meta.needs_mask_init = false;
                    _asset.meta.bmp_pan_x = 0;
                    _asset.meta.bmp_pan_y = 0;
                } else if (variable_struct_exists(_asset.meta, "needs_mask_init") && _asset.meta.needs_mask_init) {
                    scr_asset_kla_process_surface(_asset, false, -1);
                }
                
                // Push initial snapshot so first Ctrl+Z has something to revert to.
                // Snapshot pixels + bg_mask + bg_col in the new struct format so undo
                // fully restores state. Also seed pixel_backup so F11 surface loss
                // can restore even untouched bitmaps.
                if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
                    var _init_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
                    buffer_get_surface(_init_buf, _asset.meta.preview_surf, 0);
                    var _init_mask = array_create(64000, 0);
                    if (variable_struct_exists(_asset.meta, "bg_mask")) {
                        array_copy(_init_mask, 0, _asset.meta.bg_mask, 0, 64000);
                    }
                    var _init_bg = variable_struct_exists(_asset.meta, "bg_col") ? _asset.meta.bg_col : 0;
                    var _init_entry = { buf: _init_buf, mask: _init_mask, bg_col: _init_bg };
                    array_push(_asset.meta.undo_stack, _init_entry);
                    
                    if (!buffer_exists(_asset.meta.pixel_backup)) {
                        _asset.meta.pixel_backup = buffer_create(320 * 200 * 4, buffer_fixed, 1);
                    }
                    buffer_get_surface(_asset.meta.pixel_backup, _asset.meta.preview_surf, 0);
                    
                    if (array_length(_asset.meta.undo_stack) > 25) {
                        var _idrop0 = _asset.meta.undo_stack[0];
                        if (is_struct(_idrop0) && buffer_exists(_idrop0.buf)) {
                            buffer_delete(_idrop0.buf);
                        } else if (buffer_exists(_idrop0)) {
                            buffer_delete(_idrop0);
                        }
                        array_delete(_asset.meta.undo_stack, 0, 1);
                    }
                    _asset.meta.redo_stack = [];
                }
            }
        }
                        
            
			// RESAVE & CLEANUP BUTTONS
	        if (_is_ed) {
	            var _rbx1 = _ebx2 + 10;
	            var _rbx2 = _rbx1 + 80;
	            var _rb_hov = point_in_rectangle(_mx, _my, _rbx1, _btn_y, _rbx2, _btn_y + 20);
	            var _rb_unsaved = variable_struct_exists(_asset.meta, "bmp_unsaved") && _asset.meta.bmp_unsaved;
	            // Lighten the button if hovered OR if it needs a save (unsaved)
	            var _rb_col = make_color_rgb(140, 40, 30); // Base Dark Red
	            if (_rb_unsaved) _rb_col = make_color_rgb(220, 120, 40); // Unsaved "Warning" Orange
	            if (_rb_hov)     _rb_col = make_color_rgb(200, 80, 60); // Hover Light Red

	            draw_set_color(_rb_col);
	            draw_rectangle(_rbx1, _btn_y, _rbx2, _btn_y + 20, false);
	            draw_set_color(c_white);
	            draw_text(_rbx1 + 40, _btn_y + 5, "RESAVE");
	            if (_rb_hov && mouse_check_button_released(mb_left)) {
	                scr_asset_kla_save(_asset);
	                // HiRes encode always forces every cell to exactly 2 colours — that's
	                // the whole point, a HiRes file physically can't hold more. If the
	                // on-screen canvas hadn't already been cleaned up (AUTO off, or no
	                // cleanup pass run yet), the FILE ends up correctly quantised while
	                // the CANVAS still shows the old, un-quantised pixels — a silent
	                // mismatch that only surfaced before via a forced reload (alt-tab /
	                // surface loss). Rebuilding here closes that gap immediately.
	                scr_asset_bmp_build_preview(_asset);
	                if (!buffer_exists(_asset.meta.pixel_backup)) {
	                    _asset.meta.pixel_backup = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                }
	                buffer_get_surface(_asset.meta.pixel_backup, _asset.meta.preview_surf, 0);
	                _asset.meta.bmp_unsaved = false;
	            }
				
				

	            var _clrx1 = _rbx2 + 10;
	            var _clrx2 = _clrx1 + 60;
	            var _clr_hov = point_in_rectangle(_mx, _my, _clrx1, _btn_y, _clrx2, _btn_y + 20);
	            draw_set_color(_clr_hov ? make_color_rgb(255, 60, 60) : make_color_rgb(140, 20, 20));
	            draw_rectangle(_clrx1, _btn_y, _clrx2, _btn_y + 20, false);
	            draw_set_color(c_white);
	            draw_text(_clrx1 + 30, _btn_y + 5, "CLEAR");
	            if (_clr_hov && mouse_check_button_pressed(mb_left)) {
	                // Push pre-CLEAR snapshot so this destructive op is undoable.
	                if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
	                    var _clr_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                    buffer_get_surface(_clr_buf, _asset.meta.preview_surf, 0);
	                    var _clr_mask = array_create(64000, 0);
	                    array_copy(_clr_mask, 0, _asset.meta.bg_mask, 0, 64000);
	                    var _clr_entry = { buf: _clr_buf, mask: _clr_mask, bg_col: _asset.meta.bg_col };
	                    array_push(_asset.meta.undo_stack, _clr_entry);
	                    if (array_length(_asset.meta.undo_stack) > 25) {
	                        var _cdrop0 = _asset.meta.undo_stack[0];
	                        if (is_struct(_cdrop0) && buffer_exists(_cdrop0.buf)) {
	                            buffer_delete(_cdrop0.buf);
	                        } else if (buffer_exists(_cdrop0)) {
	                            buffer_delete(_cdrop0);
	                        }
	                        array_delete(_asset.meta.undo_stack, 0, 1);
	                    }
	                    _asset.meta.redo_stack = [];
	                }
	                surface_set_target(_asset.meta.preview_surf);
	                // HiRes has no editable background — CLEAR always resets to a
	                // fixed black canvas, fully unprotected, same as a brand new asset.
	                draw_clear(scr_c64_pepto_colour(_bmp_is_hires ? 0 : _asset.meta.bg_col));
	                surface_reset_target();
	                _asset.meta.bg_mask = array_create(64000, 0);
	                _asset.meta.clash_grid = array_create(1000, false);
	                if (_bmp_is_hires) {
	                    // CRITICAL: the pixel buffer and bg_mask reset above are NOT
	                    // the full source of truth in HiRes — hr_cell_fg_col/
	                    // hr_cell_bg_col are what actually gets painted back onto a
	                    // cell the next time any stroke touches it. Without also
	                    // zeroing these here, a cell's OLD colours (e.g. from a PNG
	                    // import before CLEAR) sit around invisibly and reappear
	                    // as soon as you draw in that cell again — the "residual
	                    // data" symptom.
	                    _asset.meta.hr_role_mask   = array_create(64000, 0);
	                    _asset.meta.hr_cell_fg_col = array_create(1000, 0);
	                    _asset.meta.hr_cell_bg_col = array_create(1000, 0);
	                }
	                _asset.meta.pixels_dirty = true;
	                _asset.meta.bmp_unsaved = true;
	            }

	            var _clx1 = _clrx2 + 10;
	            var _clx2 = _clx1 + 90;
	            var _cl_hov = point_in_rectangle(_mx, _my, _clx1, _btn_y, _clx2, _btn_y + 20);
	            var _has_clashes = false;
	            for (var _cci = 0; _cci < 1000; _cci++) {
	                if (_asset.meta.clash_grid[_cci]) { _has_clashes = true; break; }
	            }
	            var _cl_flash = _has_clashes && ((current_time mod 600) < 300);
	            draw_set_color(_cl_hov ? make_color_rgb(200, 150, 60) : (_cl_flash ? make_color_rgb(220, 60, 40) : make_color_rgb(140, 100, 30)));
	            draw_rectangle(_clx1, _btn_y, _clx2, _btn_y + 20, false);
	            draw_set_color(c_white);
	            draw_text(_clx1 + 45, _btn_y + 5, "CLEANUP");
                
				// Trigger Cleanup Logic
	            if ((_cl_hov && mouse_check_button_pressed(mb_left)) || keyboard_check_pressed(vk_backspace)) {
	                scr_asset_kla_process_surface(_asset, true, -1); 
	            }
				// AUTO-CLEAN TOGGLE
	            var _acx1 = _clx2 + 10;
	            var _acx2 = _acx1 + 90;
	            var _ac_hov = point_in_rectangle(_mx, _my, _acx1, _btn_y, _acx2, _btn_y + 20);
	            var _ac_on = _asset.meta.auto_clean;
                
	            draw_set_color(_ac_hov ? make_color_rgb(100, 200, 100) : (_ac_on ? make_color_rgb(40, 100, 40) : make_color_rgb(60, 60, 60)));
	            draw_rectangle(_acx1, _btn_y, _acx2, _btn_y + 20, false);
	            draw_set_color(c_white);
	            draw_text(_acx1 + 45, _btn_y + 5, "AUTO:" + (_ac_on ? "ON" : "OFF"));
                
	            if (_ac_hov && mouse_check_button_pressed(mb_left)) {
	                _asset.meta.auto_clean = !_asset.meta.auto_clean;
	            }

				// MC / HIRES MODE TOGGLE
	            var _mmx1 = _acx2 + 10;
	            var _mmx2 = _mmx1 + 90;
	            var _mm_hov = point_in_rectangle(_mx, _my, _mmx1, _btn_y, _mmx2, _btn_y + 20);
	            var _mm_hires = scr_asset_bmp_is_hires(_asset);
                
	            draw_set_color(_mm_hov ? make_color_rgb(200, 140, 60) : (_mm_hires ? make_color_rgb(120, 70, 20) : make_color_rgb(30, 60, 90)));
	            draw_rectangle(_mmx1, _btn_y, _mmx2, _btn_y + 20, false);
	            draw_set_color(c_white);
	            draw_text(_mmx1 + 38, _btn_y + 5, _mm_hires ? "HIRES" : "MC MODE");
                
	            if (_mm_hov && mouse_check_button_pressed(mb_left)) {
	                if (_png_mode) {
	                    // Import/conversion mode: nothing is committed yet (no saved
	                    // file, no undo history to protect), so the confirm dialog and
	                    // snapshot machinery below don't apply — just flip the mode and
	                    // force the shader to reconvert immediately, rather than
	                    // waiting for the user to nudge a slider to see the effect.
	                    _asset.meta.bmp_mode = _mm_hires ? "MC" : "HIRES";
	                    if (_asset.meta.bmp_mode == "HIRES") {
	                        _asset.meta.secondary_color = _asset.meta.bg_col;
	                    }
	                    _asset.meta.png_conv_dirty = true;
	                } else if (scr_show_question_bool("Okay to convert?\nUndo available")) {
	                    // Switching modes changes what a "valid cell" means (4 colours
	                    // vs 2), so the existing pixels are almost certainly invalid
	                    // under the new mode's rule. Snapshot the OLD mode + pixels for
	                    // undo, then flip the mode and immediately re-quantise via the
	                    // same pass CLEANUP/RESAVE already use, so the canvas is never
	                    // left claiming a mode it doesn't actually conform to.
	                    if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
	                        var _mode_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                        buffer_get_surface(_mode_buf, _asset.meta.preview_surf, 0);
	                        var _mode_mask = array_create(64000, 0);
	                        array_copy(_mode_mask, 0, _asset.meta.bg_mask, 0, 64000);
	                        var _mode_entry = { buf: _mode_buf, mask: _mode_mask, bg_col: _asset.meta.bg_col, bmp_mode: _asset.meta.bmp_mode };
	                        array_push(_asset.meta.undo_stack, _mode_entry);
	                        if (array_length(_asset.meta.undo_stack) > 25) {
	                            var _modedrop0 = _asset.meta.undo_stack[0];
	                            if (is_struct(_modedrop0) && buffer_exists(_modedrop0.buf)) {
	                                buffer_delete(_modedrop0.buf);
	                            } else if (buffer_exists(_modedrop0)) {
	                                buffer_delete(_modedrop0);
	                            }
	                            array_delete(_asset.meta.undo_stack, 0, 1);
	                        }
	                        _asset.meta.redo_stack = [];
	                    }
	                    _asset.meta.bmp_mode = _mm_hires ? "MC" : "HIRES";
	                    if (_asset.meta.bmp_mode == "HIRES") {
	                        _asset.meta.secondary_color = _asset.meta.bg_col;
	                    }
	                    scr_asset_kla_process_surface(_asset, true, -1);
	                    // Immediately encode + write to disk, then rebuild the preview
	                    // surface straight from those freshly-saved bytes. This is the
	                    // only way to GUARANTEE the canvas visually matches the new
	                    // format's real constraints (MC pixel-pairing, HiRes 2-colour
	                    // cells) right away — process_surface alone only fixes colour
	                    // budget, it doesn't force MC's 2-wide pixel pairing, so without
	                    // this the canvas could keep showing single-pixel-resolution
	                    // artifacts until something else (e.g. a surface-loss reload)
	                    // forced a rebuild from disk.
	                    scr_asset_kla_save(_asset);
	                    scr_asset_bmp_build_preview(_asset);
	                    if (!buffer_exists(_asset.meta.pixel_backup)) {
	                        _asset.meta.pixel_backup = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                    }
	                    buffer_get_surface(_asset.meta.pixel_backup, _asset.meta.preview_surf, 0);
	                    _asset.meta.bmp_unsaved       = false;
	                    _asset.meta.needs_clash_check = false;
	                }
	            }
            
	        }
	        draw_set_halign(fa_left);

	        // DYNAMIC INTEGER SIZING — Fits window, but strictly locks to 1x, 2x, or 3x
	        var _avail_h = (_vy2 - 40) - _cy;
            
	        // Find the max whole-number scale that fits the PANEL, not the window.
	        // _thumb dims already bake in _scale_f_cap, so divide panel space by it here.
	        var _panel_avail_w = _vw - 180; // reserve room for left + right toolbars
	        var _fit_by_w = floor(_panel_avail_w / (320 * _scale_f_cap));
	        var _fit_by_h = floor(_avail_h      / (200 * _scale_f_cap));
            
	        // Pick the smaller scale so it doesn't clip, cap at 3x, minimum 1x
	        var _frame_z = clamp(min(_fit_by_w, _fit_by_h), 1, 3);
            
	        // Multiply by the GUI scale correction factor to prevent sub-pixel lapsing
	        var _thumb_w = floor(320 * _frame_z * _scale_f_cap); 
	        var _thumb_h = floor(200 * _frame_z * _scale_f_cap);
	        var _thumb_x = _vx1 + (_vw * 0.5) - (_thumb_w * 0.5);
	        var _thumb_y = _cy + (_avail_h * 0.5) - (_thumb_h * 0.5);
	        _thumb_y = max(_thumb_y, _cy + 10);
            

	        // Allow PNG conversion mode to enter even without an existing surface
	        if (_png_mode || (variable_struct_exists(_asset.meta, "preview_surf") &&
	            surface_exists(_asset.meta.preview_surf))) {
                
	            // Draw Canvas (Crisp Pixels / No Interpolation)
	            var _prev_filter = gpu_get_texfilter();
	            gpu_set_texfilter(false);
	            // SNAPPING to whole pixels prevents the 1px drift/black border
var _sx = floor(_thumb_x);
var _sy = floor(_thumb_y);
var _sw = floor(_thumb_w);
var _sh = floor(_thumb_h);

gpu_set_texfilter(false); // CRITICAL for C64 pixel accuracy
var _pan_x   = _asset.meta.bmp_pan_x;
var _pan_y   = _asset.meta.bmp_pan_y;
var _px_zoom = _asset.meta.bmp_zoom / bmp_ui_zoom_cap;

// Scissor to canvas bounds so nothing bleeds outside
var _sx_scale2 = window_get_width()  / _gui_w;
var _sy_scale2 = window_get_height() / display_get_gui_height();
gpu_set_scissor(
	floor(_sx * _sx_scale2),
	floor(_sy * _sy_scale2),
	ceil(_sw * _sx_scale2),
	ceil(_sh * _sy_scale2)
);

var _has_surf = variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf);
if (_asset.meta.bmp_zoom <= bmp_ui_zoom_cap) {
	if (_has_surf) draw_surface_stretched(_asset.meta.preview_surf, _sx, _sy, _sw, _sh);
} else {
	var _src_w = max(1, 320 / _px_zoom);
	var _src_h = max(1, 200 / _px_zoom);
	var _src_x = clamp(_pan_x, 0, 320 - _src_w);
	var _src_y = clamp(_pan_y, 0, 200 - _src_h);
	if (_has_surf)
	draw_surface_part_ext(_asset.meta.preview_surf,
	    _src_x, _src_y, _src_w, _src_h,
	    _sx, _sy,
	    _sw / _src_w, _sh / _src_h,
	    c_white, 1);
}
gpu_set_scissor(0, 0, window_get_width(), window_get_height());
gpu_set_texfilter(_prev_filter);

draw_set_color(make_color_rgb(80,80,80));
draw_rectangle(_sx, _sy, _sx + _sw, _sy + _sh, true);

// ── LIVE CURSOR COORDS ────────────────────────────────────────────────
// Computed here (outside the _is_ed gate) so the readout bar below the
// canvas can show them whether or not the editor is armed. The editor's
// own _raw_px/_raw_py are recalculated inside its block as before — these
// are a mirror parked on meta purely for the readout.
if (!variable_struct_exists(_asset.meta, "hud_px")) _asset.meta.hud_px = -1;
if (!variable_struct_exists(_asset.meta, "hud_py")) _asset.meta.hud_py = -1;
if (point_in_rectangle(_mx, _my, _sx, _sy, _sx + _sw, _sy + _sh)) {
    if (_asset.meta.bmp_zoom <= bmp_ui_zoom_cap) {
        _asset.meta.hud_px = clamp(floor(((_mx - _sx) / _sw) * 320), 0, 319);
        _asset.meta.hud_py = clamp(floor(((_my - _sy) / _sh) * 200), 0, 199);
    } else {
        var _hud_z  = _asset.meta.bmp_zoom / bmp_ui_zoom_cap;
        var _hud_sw = max(1, 320 / _hud_z);
        var _hud_sh = max(1, 200 / _hud_z);
        var _hud_sx = clamp(_asset.meta.bmp_pan_x, 0, 320 - _hud_sw);
        var _hud_sy = clamp(_asset.meta.bmp_pan_y, 0, 200 - _hud_sh);
        _asset.meta.hud_px = clamp(floor(_hud_sx + ((_mx - _sx) / _sw) * _hud_sw), 0, 319);
        _asset.meta.hud_py = clamp(floor(_hud_sy + ((_my - _sy) / _sh) * _hud_sh), 0, 199);
    }
} else {
    _asset.meta.hud_px = -1;
    _asset.meta.hud_py = -1;
}

// 8x8 grid overlay when pixel-zoomed to 100%+
if (_asset.meta.bmp_zoom > bmp_ui_zoom_cap) {
	var _pxz_g   = _asset.meta.bmp_zoom / bmp_ui_zoom_cap;
	var _src_w_g = max(1, 320 / _pxz_g);
	var _src_h_g = max(1, 200 / _pxz_g);
	var _src_x_g = clamp(_asset.meta.bmp_pan_x, 0, 320 - _src_w_g);
	var _src_y_g = clamp(_asset.meta.bmp_pan_y, 0, 200 - _src_h_g);
	// pixels per screen pixel
	var _pps_x = _sw / _src_w_g;
	var _pps_y = _sh / _src_h_g;
	// only draw grid if each surface pixel is at least 4 screen pixels wide
	if (_pps_x >= 4) {
	    var _sx_sc3 = window_get_width()  / _gui_w;
	    var _sy_sc3 = window_get_height() / display_get_gui_height();
	    gpu_set_scissor(
	        floor(_sx * _sx_sc3), floor(_sy * _sy_sc3),
	        ceil(_sw * _sx_sc3),  ceil(_sh * _sy_sc3)
	    );
	    
	    // Calculate transition (t) from 0.0 at min zoom (4) to 1.0 at full zoom
	    var _max_pps = 32; // Adjust this to match your absolute maximum _pps_x
	    var _zoom_t = clamp((_pps_x - 4) / max(1, _max_pps - 4), 0, 1);
	    
	    var _col_start = make_color_rgb(40, 40, 60);
	    var _col_end   = make_color_rgb(140, 140, 170); // Lighter target color
	    
	    draw_set_color(merge_color(_col_start, _col_end, _zoom_t));
	    draw_set_alpha(lerp(0.15, 1.0, _zoom_t)); // Fade smoothly from faint to solid
	    
	    // vertical lines every 8 surface pixels
	    var _first_gx = floor(_src_x_g / 8) * 8;
	    for (var _gx = _first_gx; _gx <= _src_x_g + _src_w_g; _gx += 8) {
	        var _screen_gx = _sx + (_gx - _src_x_g) * _pps_x;
	        draw_line(_screen_gx, _sy, _screen_gx, _sy + _sh);
	    }
	    // horizontal lines every 8 surface pixels
	    var _first_gy = floor(_src_y_g / 8) * 8;
	    for (var _gy = _first_gy; _gy <= _src_y_g + _src_h_g; _gy += 8) {
	        var _screen_gy = _sy + (_gy - _src_y_g) * _pps_y;
	        draw_line(_sx, _screen_gy, _sx + _sw, _screen_gy);
	    }
	    draw_set_alpha(1.0);
	    gpu_set_scissor(0, 0, window_get_width(), window_get_height());
	}
}

// SCROLLBARS (only shown when pixel-zoomed in)
if (_asset.meta.bmp_zoom > bmp_ui_zoom_cap) {
	var _pxz     = _asset.meta.bmp_zoom / bmp_ui_zoom_cap;
	var _src_w2  = max(1, 320 / _pxz);
	var _src_h2  = max(1, 200 / _pxz);
	var _sb_th   = 10; // scrollbar thickness
    
			if (!variable_struct_exists(_asset.meta, "hbar_dragging")) _asset.meta.hbar_dragging = false;
	        if (!variable_struct_exists(_asset.meta, "vbar_dragging")) _asset.meta.vbar_dragging = false;
	        if (!variable_struct_exists(_asset.meta, "hbar_drag_ox"))  _asset.meta.hbar_drag_ox  = 0;
	        if (!variable_struct_exists(_asset.meta, "vbar_drag_oy"))  _asset.meta.vbar_drag_oy  = 0;

	        // Horizontal scrollbar
	        var _hbar_x  = _sx;
	        var _hbar_y  = _sy + _sh + 2;
	        var _hbar_w  = _sw;
	        draw_set_color(make_color_rgb(30, 30, 45));
	        draw_rectangle(_hbar_x, _hbar_y, _hbar_x + _hbar_w, _hbar_y + _sb_th, false);
	        var _hthumb_w = max(20, floor((_src_w2 / 320) * _hbar_w));
	        var _hthumb_x = _hbar_x + floor((_pan_x / max(1, 320 - _src_w2)) * (_hbar_w - _hthumb_w));
	        var _hthumb_hov = point_in_rectangle(_mx, _my, _hthumb_x, _hbar_y, _hthumb_x + _hthumb_w, _hbar_y + _sb_th);
	        draw_set_color(_asset.meta.hbar_dragging ? c_white : (_hthumb_hov ? make_color_rgb(110, 110, 160) : make_color_rgb(80, 80, 120)));
	        draw_rectangle(_hthumb_x, _hbar_y, _hthumb_x + _hthumb_w, _hbar_y + _sb_th, false);

	        if (_hthumb_hov && mouse_check_button_pressed(mb_left)) {
	            _asset.meta.hbar_dragging = true;
	            _asset.meta.hbar_drag_ox  = _mx - _hthumb_x;
	        }
	        if (_asset.meta.hbar_dragging) {
	            if (mouse_check_button(mb_left)) {
	                var _new_hthumb_x = clamp(_mx - _asset.meta.hbar_drag_ox, _hbar_x, _hbar_x + _hbar_w - _hthumb_w);
	                var _htrack_range = max(1, _hbar_w - _hthumb_w);
	                _asset.meta.bmp_pan_x = clamp(((_new_hthumb_x - _hbar_x) / _htrack_range) * (320 - _src_w2), 0, 320 - _src_w2);
	            } else {
	                _asset.meta.hbar_dragging = false;
	            }
	        }
    
	        // Vertical scrollbar
	        var _vbar_x  = _sx + _sw + 2;
	        var _vbar_y  = _sy;
	        var _vbar_h  = _sh;
	        draw_set_color(make_color_rgb(30, 30, 45));
	        draw_rectangle(_vbar_x, _vbar_y, _vbar_x + _sb_th, _vbar_y + _vbar_h, false);
	        var _vthumb_h = max(20, floor((_src_h2 / 200) * _vbar_h));
	        var _vthumb_y = _vbar_y + floor((_pan_y / max(1, 200 - _src_h2)) * (_vbar_h - _vthumb_h));
	        var _vthumb_hov = point_in_rectangle(_mx, _my, _vbar_x, _vthumb_y, _vbar_x + _sb_th, _vthumb_y + _vthumb_h);
	        draw_set_color(_asset.meta.vbar_dragging ? c_white : (_vthumb_hov ? make_color_rgb(110, 110, 160) : make_color_rgb(80, 80, 120)));
	        draw_rectangle(_vbar_x, _vthumb_y, _vbar_x + _sb_th, _vthumb_y + _vthumb_h, false);

	        if (_vthumb_hov && mouse_check_button_pressed(mb_left)) {
	            _asset.meta.vbar_dragging = true;
	            _asset.meta.vbar_drag_oy  = _my - _vthumb_y;
	        }
	        if (_asset.meta.vbar_dragging) {
	            if (mouse_check_button(mb_left)) {
	                var _new_vthumb_y = clamp(_my - _asset.meta.vbar_drag_oy, _vbar_y, _vbar_y + _vbar_h - _vthumb_h);
	                var _vtrack_range = max(1, _vbar_h - _vthumb_h);
	                _asset.meta.bmp_pan_y = clamp(((_new_vthumb_y - _vbar_y) / _vtrack_range) * (200 - _src_h2), 0, 200 - _src_h2);
	            } else {
	                _asset.meta.vbar_dragging = false;
	            }
	        }
			
	// Zoom level indicator
	draw_set_font(fnt_c64_tiny);
	draw_set_color(make_color_rgb(100, 100, 140));
	var _zoom_hud_y = min(_hbar_y + _sb_th + 50, _gui_h - 14);
	draw_text(_sx + 80, _zoom_hud_y, "ZOOM: " + string(floor(_pxz * 100)) + "%  [SCROLL=ZOOM]  [MMB/SPACEBAR=PAN]  [G=GRAB]  [D=DRAW]  [R=REPLACE]  [X=FLIP X]  [Y=FLIP Y]  [ [ / ] =BRUSH SIZE] [ALT+LCLICK=PICK] [CTRL=TINT STAMP]");
}
                
// EDITOR TOOLS & PALETTE OVERLAYS
            if (_is_ed && !_prev_input_blocked) {
                
            // ══ PNG CONVERSION MODE ══════════════════════════════════════════
            if (!variable_struct_exists(_asset.meta, "bg_col"))    _asset.meta.bg_col    = 0;
            if (!variable_struct_exists(_asset.meta, "bmp_zoom"))  _asset.meta.bmp_zoom  = bmp_ui_zoom_cap;
            if (!variable_struct_exists(_asset.meta, "bmp_pan_x")) _asset.meta.bmp_pan_x = 0;
            if (!variable_struct_exists(_asset.meta, "bmp_pan_y")) _asset.meta.bmp_pan_y = 0;
            if (variable_struct_exists(_asset.meta, "png_import_mode") && _asset.meta.png_import_mode) {
                    
                if (!variable_struct_exists(_asset.meta, "png_off_x"))    _asset.meta.png_off_x    = 0;
	                if (!variable_struct_exists(_asset.meta, "png_off_y"))    _asset.meta.png_off_y    = 0;
	                if (!variable_struct_exists(_asset.meta, "png_fine_x"))   _asset.meta.png_fine_x   = 0.0;
	                if (!variable_struct_exists(_asset.meta, "png_fine_y"))   _asset.meta.png_fine_y   = 0.0;
	                // Init source surface from PNG once
	                if (!surface_exists(_asset.meta.png_source_surf)) {
                    var _spr = sprite_add(_asset.meta.png_import_path, 1, false, false, 0, 0);
                    if (_spr != -1) {
                        var _sw2 = sprite_get_width(_spr);
                        var _sh2 = sprite_get_height(_spr);
                        // Draw to native-size surface first to get off the atlas cleanly
                        var _raw_surf = surface_create(_sw2, _sh2);
                        surface_set_target(_raw_surf);
                        gpu_set_texfilter(false);
                        draw_clear(c_black);
                        draw_sprite(_spr, 0, 0, 0);
                        surface_reset_target();
                        sprite_delete(_spr);
                        // Keep raw surf at native resolution — scale/offset applied at shader draw time
	                        _asset.meta.png_source_surf = _raw_surf;
	                        _asset.meta.png_src_w = _sw2;
	                        _asset.meta.png_src_h = _sh2;
	                        _asset.meta.png_conv_dirty = true;
                    }
                }
                
                // FAST PATH — 320x200 PNG: skip conversion, import directly as sprite blit
                if (variable_struct_exists(_asset.meta, "png_src_w") && _asset.meta.png_src_w == 320
                &&  variable_struct_exists(_asset.meta, "png_src_h") && _asset.meta.png_src_h == 200
                &&  surface_exists(_asset.meta.png_source_surf)) {
                    if (!variable_struct_exists(_asset.meta, "preview_surf") || !surface_exists(_asset.meta.preview_surf)) {
                        _asset.meta.preview_surf = surface_create(320, 200);
                    }
                    surface_set_target(_asset.meta.preview_surf);
                    gpu_set_texfilter(false);
                    gpu_set_blendmode_ext(bm_one, bm_zero);
                    draw_clear(c_black);
                    draw_surface(_asset.meta.png_source_surf, 0, 0);
                    gpu_set_blendmode(bm_normal);
                    surface_reset_target();
                    // Snap off-palette (e.g. Aseprite) RGB to exact Pepto + enforce MC pairs.
                    // The fast path skips the quantisation shader, so heal manually here.
                    scr_asset_kla_heal_palette(_asset);
                    if (surface_exists(_asset.meta.png_source_surf)) surface_free(_asset.meta.png_source_surf);
                    _asset.meta.png_source_surf  = -1;
                    _asset.meta.png_import_mode  = false;
                    _asset.meta.png_conv_dirty   = false;
                    _asset.meta.pixels_dirty     = true;
                    _asset.meta.bmp_unsaved      = true;
                    // Run one clash cleanup pass with a fresh mask, same as the CONFIRM path
                    _asset.meta.bg_mask          = array_create(64000, 0);
                    _asset.meta.clash_grid       = array_create(1000, false);
                    _asset.meta.needs_mask_init  = true;
                    scr_asset_kla_process_surface(_asset, true, -1);
                    _asset.meta.is_editing       = true;
                }
                
                // Set default scale now that png_src_w is guaranteed to exist
	                if (!variable_struct_exists(_asset.meta, "png_scale")) {
					    var _fit_w = variable_struct_exists(_asset.meta, "png_src_w") ? _asset.meta.png_src_w : 320;
					    var _fit_h = variable_struct_exists(_asset.meta, "png_src_h") ? _asset.meta.png_src_h : 200;
					    var _scale_by_w = 320 / _fit_w;
					    var _scale_by_h = 200 / _fit_h;
					    _asset.meta.png_scale = min(_scale_by_w, _scale_by_h);
					}
	                    
	                // Controls layout — anchored BELOW the canvas rather than
	                // above it, so the sliders and CONFIRM/CANCEL don't sit
	                // under the top toolbar row. Top-to-bottom: canvas ->
	                // SCALE/OFFSET/FINE row (_cy2-30) -> HUE/SAT/etc row (_cy2)
	                // -> CONFIRM/CANCEL (_cy2+30, defined further below).
                var _cx2  = _sx;
                var _cy2  = _sy + _sh + 100;
                var _slw  = 160; // slider width
                var _lmb  = mouse_check_button(mb_left);
                var _lmb_released = mouse_check_button(mb_left);
                    
                // Sliders — drag updates the value live but conversion only fires on release
                if (!variable_struct_exists(_asset.meta, "png_dither_amount")) _asset.meta.png_dither_amount = 0.1;
          
                var _new_hue = scr_draw_slider(_mx, _my, _cx2,        _cy2 + 20, _slw, "HUE",        _asset.meta.png_hue,           -1.0, 1.0,  _lmb, _asset, "HUE", 0.0);
                var _new_sat = scr_draw_slider(_mx, _my, _cx2 + 190,  _cy2 + 20, _slw, "SAT",        _asset.meta.png_saturation,     0.0,  2.0,  _lmb, _asset, "SAT", 1.0);
                var _new_con = scr_draw_slider(_mx, _my, _cx2 + 380,  _cy2 + 20, _slw, "CONTRAST",   _asset.meta.png_contrast,       0.0,  2.0,  _lmb, _asset, "CONTRAST", 1.0);
                var _new_bri = scr_draw_slider(_mx, _my, _cx2 + 570,  _cy2 + 20, _slw, "BRIGHTNESS", _asset.meta.png_brightness,    -1.0,  1.0,  _lmb, _asset, "BRIGHTNESS", 0.0);         
                var _new_dit = scr_draw_slider(_mx, _my, _cx2 + 760,  _cy2 + 20, _slw, "DITHER AMT", _asset.meta.png_dither_amount,  0.0,  0.5,  _lmb, _asset, "DITHER_AMT", 0.1);
                // Reset button for colour row
                var _rst_c_x = _cx2 + 760 + _slw + 8;
                var _rst_c_y = _cy2 + 20;
                var _rst_c_hov = point_in_rectangle(_mx, _my, _rst_c_x, _rst_c_y, _rst_c_x + 50, _rst_c_y + 16);
                draw_set_color(_rst_c_hov ? make_color_rgb(180, 80, 80) : make_color_rgb(80, 40, 40));
                draw_rectangle(_rst_c_x, _rst_c_y, _rst_c_x + 50, _rst_c_y + 16, false);
                draw_set_color(c_white);
                draw_rectangle(_rst_c_x, _rst_c_y, _rst_c_x + 50, _rst_c_y + 16, true);
                draw_text(_rst_c_x + 4, _rst_c_y + 2, "RESET");
                    
                if (_rst_c_hov && mouse_check_button_pressed(mb_left)) {
                    _asset.meta.png_hue = 0.0; _new_hue = 0.0;
                    _asset.meta.png_saturation = 1.0; _new_sat = 1.0;
                    _asset.meta.png_contrast = 1.0; _new_con = 1.0;
                    _asset.meta.png_brightness = 0.0; _new_bri = 0.0;
                    _asset.meta.png_dither_amount = 0.1; _new_dit = 0.1;
                    _asset.meta.png_conv_dirty = true;
                }
                    
                var _fit_scale_default = 320 / (variable_struct_exists(_asset.meta, "png_src_w") ? _asset.meta.png_src_w : 320);
                var _new_scl = scr_draw_slider(_mx, _my, _cx2,        _cy2 - 10, _slw, "SCALE",      _asset.meta.png_scale,          0.01,  2.0,  _lmb, _asset, "SCALE", _fit_scale_default);
                var _new_ofx = scr_draw_slider(_mx, _my, _cx2 + 190,  _cy2 - 10, _slw, "OFFSET X",   _asset.meta.png_off_x,         -160, 160,   _lmb, _asset, "OFFSET_X", 0);
                var _new_ofy = scr_draw_slider(_mx, _my, _cx2 + 380,  _cy2 - 10, _slw, "OFFSET Y",   _asset.meta.png_off_y,         -100, 100,   _lmb, _asset, "OFFSET_Y", 0);
                var _new_fnx = scr_draw_slider(_mx, _my, _cx2 + 570,  _cy2 - 10, _slw, "FINE X",     _asset.meta.png_fine_x,        -1.0, 1.0,   _lmb, _asset, "FINE_X", 0.0);
                var _new_fny = scr_draw_slider(_mx, _my, _cx2 + 760,  _cy2 - 10, _slw, "FINE Y",     _asset.meta.png_fine_y,        -1.0, 1.0,   _lmb, _asset, "FINE_Y", 0.0);
                // Reset button for sizing row
                var _rst_s_x = _cx2 + 760 + _slw + 8;
                var _rst_s_y = _cy2 - 10;
                var _rst_s_hov = point_in_rectangle(_mx, _my, _rst_s_x, _rst_s_y, _rst_s_x + 50, _rst_s_y + 16);
                draw_set_color(_rst_s_hov ? make_color_rgb(180, 80, 80) : make_color_rgb(80, 40, 40));
                draw_rectangle(_rst_s_x, _rst_s_y, _rst_s_x + 50, _rst_s_y + 16, false);
                draw_set_color(c_white);
                draw_rectangle(_rst_s_x, _rst_s_y, _rst_s_x + 50, _rst_s_y + 16, true);
                draw_text(_rst_s_x + 4, _rst_s_y + 2, "RESET");
                if (_rst_s_hov && mouse_check_button_pressed(mb_left)) {
	                    var _fit_w2 = variable_struct_exists(_asset.meta, "png_src_w") ? _asset.meta.png_src_w : 320;
	                    _asset.meta.png_scale = 320 / _fit_w2; _new_scl = _asset.meta.png_scale;
                    _asset.meta.png_off_x = 0; _new_ofx = 0;
                    _asset.meta.png_off_y = 0; _new_ofy = 0;
                    _asset.meta.png_fine_x = 0.0; _new_fnx = 0.0;
                    _asset.meta.png_fine_y = 0.0; _new_fny = 0.0;
                    _asset.meta.png_conv_dirty = true;
                }
                    
                    
                // Always store latest dragged values so label shows live position
                _asset.meta.png_hue            = _new_hue;
                _asset.meta.png_saturation     = _new_sat;
                _asset.meta.png_contrast       = _new_con;
                _asset.meta.png_brightness     = _new_bri;
                _asset.meta.png_dither_amount  = _new_dit;
                if (_new_scl != _asset.meta.png_scale ||
                    floor(_new_ofx) != _asset.meta.png_off_x ||
                    floor(_new_ofy) != _asset.meta.png_off_y ||
                    round(_new_fnx * 20) / 20 != _asset.meta.png_fine_x ||
                    round(_new_fny * 20) / 20 != _asset.meta.png_fine_y) {
                    _asset.meta.png_conv_dirty = true;
                }
                _asset.meta.png_scale   = _new_scl;
                _asset.meta.png_off_x   = floor(_new_ofx);
                _asset.meta.png_off_y   = floor(_new_ofy);
                _asset.meta.png_fine_x  = round(_new_fnx * 20) / 20;
                _asset.meta.png_fine_y  = round(_new_fny * 20) / 20;
                // Only trigger expensive conversion when mouse is released
                if (_lmb_released) {
                    _asset.meta.png_conv_dirty = true;
                }
                    
                    
                // Dither buttons
                var _dithers_png = ["NONE", "CHECKER", "INTERLACE", "BAYER"];
                var _dbx = _vx1 +70;
                var _dby = _vy1 + 200;
                draw_set_font(fnt_c64_tiny);
                draw_set_color(c_ltgray);
                draw_text(_dbx, _dby-30 , "DITHER:");
                for (var _di = 0; _di < array_length(_dithers_png); _di++) {
                    var _dn   = _dithers_png[_di];
                    var _dact = (_asset.meta.png_dither == _dn);
                    var _dhov = point_in_rectangle(_mx, _my, _dbx, _dby, _dbx + 70, _dby + 14);
                    draw_set_color(_dhov ? make_color_rgb(80,80,110) : (_dact ? make_color_rgb(40,60,100) : make_color_rgb(30,30,50)));
                    draw_rectangle(_dbx, _dby, _dbx + 70, _dby + 14, false);
                    draw_set_color(_dact ? c_yellow : (_dhov ? c_white : c_ltgray));
                    draw_rectangle(_dbx, _dby, _dbx + 70, _dby + 14, true);
                    draw_set_color(_dact ? c_yellow : c_white);
                    draw_text(_dbx + 2, _dby-1, _dn);
                    if (_dhov && mouse_check_button_pressed(mb_left)) {
                        _asset.meta.png_dither = _dn;
                        _asset.meta.png_conv_dirty = true;
                    }
                    _dby += 30;
                }
                    
                // CONFIRM / CANCEL buttons — sit ABOVE both slider rows, in the
                // gap right below the canvas.
                var _cfx = _cx2 + 800;
                var _cfy = _cy2 - 60;
                var _cf_hov = point_in_rectangle(_mx, _my, _cfx, _cfy, _cfx + 150, _cfy + 18);
                draw_set_color(_cf_hov ? make_color_rgb(40,160,80) : make_color_rgb(20,90,40));
                draw_rectangle(_cfx, _cfy, _cfx + 150, _cfy + 18, false);
                draw_set_color(_cf_hov ? c_white : c_ltgray);
                draw_rectangle(_cfx, _cfy, _cfx + 150, _cfy + 18, true);
                draw_set_color(c_white);
                draw_text(_cfx + 6, _cfy + 3, "CONFIRM IMPORT");
                    
                var _cnx = _cfx + 158;
                var _cn_hov = point_in_rectangle(_mx, _my, _cnx, _cfy, _cnx + 60, _cfy + 18);
                draw_set_color(_cn_hov ? make_color_rgb(160,40,40) : make_color_rgb(90,20,20));
                draw_rectangle(_cnx, _cfy, _cnx + 60, _cfy + 18, false);
                draw_set_color(_cn_hov ? c_white : c_ltgray);
                draw_rectangle(_cnx, _cfy, _cnx + 60, _cfy + 18, true);
                draw_set_color(c_white);
                draw_text(_cnx + 6, _cfy + 3, "CANCEL");
                    
            
                
                // CANCEL
                if (_cn_hov && mouse_check_button_pressed(mb_left)) {
			    if (surface_exists(_asset.meta.png_source_surf)) {
			        surface_free(_asset.meta.png_source_surf);
			    }
			    _asset.meta.png_source_surf  = -1;
			    _asset.meta.png_import_mode  = false;
			    _asset.meta.png_conv_dirty   = false;
			    _asset.meta.is_editing       = false;
			    // Clear the preview surface so the editor doesn't show the half-converted result
			    if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
			        surface_free(_asset.meta.preview_surf);
			        _asset.meta.preview_surf = -1;
			    }
			}
                    
                // Live conversion — rebuild preview_surf when dirty
                if (_asset.meta.png_conv_dirty && surface_exists(_asset.meta.png_source_surf)) {
                    _asset.meta.png_conv_dirty = false;
                        
                    // Create/reset preview surface
                    if (!variable_struct_exists(_asset.meta, "preview_surf") || !surface_exists(_asset.meta.preview_surf)) {
                        _asset.meta.preview_surf = surface_create(320, 200);
                    }
                        
                    // Setup the 1D palette array for the Shader Uniform
                    var _pal_array = array_create(48, 0);
                    for (var _pi = 0; _pi < 16; _pi++) {
                        var _pc = scr_c64_pepto_colour(_pi);
                        _pal_array[_pi*3]     = color_get_red(_pc)   / 255;
                        _pal_array[_pi*3 + 1] = color_get_green(_pc) / 255;
                        _pal_array[_pi*3 + 2] = color_get_blue(_pc)  / 255;
                    }

                    var _d_mode = 0;
                    if (_asset.meta.png_dither == "CHECKER") _d_mode = 1;
                    else if (_asset.meta.png_dither == "INTERLACE") _d_mode = 2;
                    else if (_asset.meta.png_dither == "BAYER") _d_mode = 3;
                        
                    // Stage 1 — scale/offset raw source into clean 320x200 intermediate (no shader)
var _intermed = surface_create(320, 200);
surface_set_target(_intermed);
gpu_set_texfilter(false);
gpu_set_blendmode_ext(bm_one, bm_zero);
draw_clear_alpha(c_black, 1);
var _sc     = _asset.meta.png_scale;
var _dx     = _asset.meta.png_off_x + _asset.meta.png_fine_x;
var _dy     = _asset.meta.png_off_y + _asset.meta.png_fine_y;
var _src_w3 = variable_struct_exists(_asset.meta, "png_src_w") ? _asset.meta.png_src_w : 320;
var _src_h3 = variable_struct_exists(_asset.meta, "png_src_h") ? _asset.meta.png_src_h : 200;
var _dw     = _src_w3 * _sc;
var _dh     = _src_h3 * _sc;
var _cx3    = (320 - _dw) * 0.5 + _dx;
var _cy3    = (200 - _dh) * 0.5 + _dy;
// Floor position to whole pixels — fractional placement causes 1px row/col bleed
var _cx3i   = floor(_cx3);
var _cy3i   = floor(_cy3);
var _dw3i   = floor(_dw);
var _dh3i   = floor(_dh);
draw_surface_stretched(_asset.meta.png_source_surf, _cx3i, _cy3i, _dw3i, _dh3i);
gpu_set_blendmode(bm_normal);
surface_reset_target();

	                    // Stage 2 — run palette quantisation shader on the full 320x200 intermediate
	                    surface_set_target(_asset.meta.preview_surf);
	                    gpu_set_texfilter(false);
	                    shader_set(shd_png_import);
	                    shader_set_uniform_f(shader_get_uniform(shd_png_import, "u_hue"), _asset.meta.png_hue);
	                    shader_set_uniform_f(shader_get_uniform(shd_png_import, "u_sat"), _asset.meta.png_saturation);
	                    shader_set_uniform_f(shader_get_uniform(shd_png_import, "u_con"), _asset.meta.png_contrast);
	                    shader_set_uniform_f(shader_get_uniform(shd_png_import, "u_bri"), _asset.meta.png_brightness);
	                    shader_set_uniform_f(shader_get_uniform(shd_png_import, "u_dither_amount"), _asset.meta.png_dither_amount);
	                    shader_set_uniform_i(shader_get_uniform(shd_png_import, "u_dither_mode"), _d_mode);
	                    shader_set_uniform_i(shader_get_uniform(shd_png_import, "u_is_hires"), _bmp_is_hires ? 1 : 0);
	                    shader_set_uniform_f_array(shader_get_uniform(shd_png_import, "u_palette"), _pal_array);
	                    draw_clear(c_black);
	                    draw_surface(_intermed, 0, 0);
	                    shader_reset();
	                    surface_reset_target();
	                    surface_free(_intermed);
                }
	                    
	                // CONFIRM — bake and run cleanup pass
	                if (_cf_hov && mouse_check_button_pressed(mb_left)) {
    // Commit the pending bg colour as the real one now
    _asset.meta.bg_col = _asset.meta.png_pending_bg;
    // Run full KLA clash cleanup with fresh mask
    _asset.meta.bg_mask    = array_create(64000, 0);
    _asset.meta.clash_grid = array_create(1000, false);
    _asset.meta.needs_mask_init = true;
    scr_asset_kla_process_surface(_asset, true, -1);
	                    // Assign file path via normal working copy pipeline
	                    var _bmp_dir2 = filename_dir(_asset.meta.png_import_path);
	                    if (!directory_exists(_bmp_dir2)) directory_create(_bmp_dir2);
	                    var _png_base2 = filename_name(_asset.meta.png_import_path);
	                    var _png_ext2  = filename_ext(_png_base2);
	                    _png_base2 = string_copy(_png_base2, 1, string_length(_png_base2) - string_length(_png_ext2));
	                    if (_asset.file == "" || _asset.file == undefined)
	                        _asset.file = _bmp_dir2 + "/" + _png_base2 + "_imported_.kla";
	                    _asset.meta.source_file    = _asset.meta.png_import_path;
	                    _asset.meta.png_import_mode = false;
						_asset.meta.pixels_dirty    = true;
						_asset.meta.bmp_unsaved     = true;
						_asset.meta.needs_mask_init = true;
						scr_asset_kla_save(_asset);
	                    // Clean up temp surface
	                    if (surface_exists(_asset.meta.png_source_surf)) surface_free(_asset.meta.png_source_surf);
	                    _asset.meta.png_source_surf = -1;
	                }
	                    
	                // Skip rest of editor tools while in conversion mode
	                goto_end_editor = true;
	            } // end png_import_mode
	            var goto_end_editor = variable_struct_exists(_asset.meta, "png_import_mode") && _asset.meta.png_import_mode;
	            if (!goto_end_editor) {
	                
	                var _is_left = mouse_check_button(mb_left);
	                var _is_right = mouse_check_button(mb_right);
	                var _in_bounds = point_in_rectangle(_mx, _my, _sx, _sy, _sx + _sw, _sy + _sh);

	                // Ensure new tool variables exist
	                if (!variable_struct_exists(_asset.meta, "active_tool")) _asset.meta.active_tool = "DRAW";
	                if (!variable_struct_exists(_asset.meta, "dither_mode")) _asset.meta.dither_mode = "NONE";
	                if (!variable_struct_exists(_asset.meta, "dither_invert")) _asset.meta.dither_invert = false;
	                if (!variable_struct_exists(_asset.meta, "replace_mode")) _asset.meta.replace_mode = false;
	                if (!variable_struct_exists(_asset.meta, "replace_col_detect")) _asset.meta.replace_col_detect = 0;
	                if (!variable_struct_exists(_asset.meta, "replace_col_target")) _asset.meta.replace_col_target = 1;
	                if (!variable_struct_exists(_asset.meta, "secondary_color")) {
	                    // Default secondary to the asset's current background colour, so
	                    // an untouched HiRes cell's "second colour" starts out matching
	                    // what the canvas already looks like, rather than always index 0.
	                    _asset.meta.secondary_color = variable_struct_exists(_asset.meta, "bg_col") ? _asset.meta.bg_col : 0;
	                }
	                if (!variable_struct_exists(_asset.meta, "fill_toggle")) _asset.meta.fill_toggle = false;
					if (!variable_struct_exists(_asset.meta, "line_x1")) _asset.meta.line_x1 = -1;
	                if (!variable_struct_exists(_asset.meta, "shift_last_px")) _asset.meta.shift_last_px = -1;
	                if (!variable_struct_exists(_asset.meta, "shift_last_py")) _asset.meta.shift_last_py = -1;
	                if (!variable_struct_exists(_asset.meta, "line_y1")) _asset.meta.line_y1 = -1;
	                if (!variable_struct_exists(_asset.meta, "line_btn")) _asset.meta.line_btn = mb_left;
	                if (!variable_struct_exists(_asset.meta, "shape_x1")) _asset.meta.shape_x1 = -1;
	                if (!variable_struct_exists(_asset.meta, "shape_y1")) _asset.meta.shape_y1 = -1;
	                if (!variable_struct_exists(_asset.meta, "shape_drawing")) _asset.meta.shape_drawing = false;
	                if (!variable_struct_exists(_asset.meta, "shape_btn")) _asset.meta.shape_btn = mb_left;
	                if (!variable_struct_exists(_asset.meta, "gradient_x1")) _asset.meta.gradient_x1 = -1;
	                if (!variable_struct_exists(_asset.meta, "gradient_y1")) _asset.meta.gradient_y1 = -1;
	                if (!variable_struct_exists(_asset.meta, "gradient_drawing")) _asset.meta.gradient_drawing = false;
	                if (!variable_struct_exists(_asset.meta, "gradient_btn")) _asset.meta.gradient_btn = mb_left;
	                if (!variable_struct_exists(_asset.meta, "gradient_custom_active")) _asset.meta.gradient_custom_active = false;
	                if (!variable_struct_exists(_asset.meta, "gradient_custom_cols")) {
	                    _asset.meta.gradient_custom_cols = array_create(12, _asset.meta.active_color);
	                }
	                if (!variable_struct_exists(_asset.meta, "preview_overlay")) _asset.meta.preview_overlay = -1;
	                if (!variable_struct_exists(_asset.meta, "overlay_dirty")) _asset.meta.overlay_dirty = false;
                    
	                // Grab Brush States
	                if (!variable_struct_exists(_asset.meta, "grab_surf")) _asset.meta.grab_surf = -1;
	                if (!variable_struct_exists(_asset.meta, "grab_mask")) _asset.meta.grab_mask = [];
	                if (!variable_struct_exists(_asset.meta, "grab_w")) _asset.meta.grab_w = 0;
	                if (!variable_struct_exists(_asset.meta, "grab_h")) _asset.meta.grab_h = 0;
	                if (!variable_struct_exists(_asset.meta, "is_grabbing")) _asset.meta.is_grabbing = false;
	                if (!variable_struct_exists(_asset.meta, "grab_flip_x")) _asset.meta.grab_flip_x = false;
	                if (!variable_struct_exists(_asset.meta, "grab_x1")) _asset.meta.grab_x1 = 0;
	                if (!variable_struct_exists(_asset.meta, "grab_y1")) _asset.meta.grab_y1 = 0;
	                if (!variable_struct_exists(_asset.meta, "brush_surf")) _asset.meta.brush_surf = -1;
	                if (!variable_struct_exists(_asset.meta, "brush_size")) _asset.meta.brush_size = 0; // 0 = single MC pixel
	                if (!variable_struct_exists(_asset.meta, "grab_off_x1")) _asset.meta.grab_off_x1 = 0;
	                if (!variable_struct_exists(_asset.meta, "grab_off_y1")) _asset.meta.grab_off_y1 = 0;
	                if (!variable_struct_exists(_asset.meta, "grab_off_x2")) _asset.meta.grab_off_x2 = 0;
	                if (!variable_struct_exists(_asset.meta, "grab_off_y2")) _asset.meta.grab_off_y2 = 0;

	                // 1. Calculate Raw Canvas Coordinates
	                var _z = _asset.meta.bmp_zoom;
	                var _raw_px = 0, _raw_py = 0;
	                var _src_x2 = 0, _src_y2 = 0, _src_w2 = 320, _src_h2 = 200;

	                if (_z <= bmp_ui_zoom_cap) {
	                    // Use lerp or explicit casting to ensure precise floating point math before flooring
					_raw_px = clamp(floor(((_mx - _sx) / _sw) * 320), 0, 319);
	                _raw_py = clamp(floor(((_my - _sy) / _sh) * 200), 0, 199);
	                } else {
	                    var _px_zoom2 = _z / bmp_ui_zoom_cap;
	                    _src_w2 = max(1, 320 / _px_zoom2);
	                    _src_h2 = max(1, 200 / _px_zoom2);
	                    _src_x2 = clamp(_asset.meta.bmp_pan_x, 0, 320 - _src_w2);
	                    _src_y2 = clamp(_asset.meta.bmp_pan_y, 0, 200 - _src_h2);
	                    _raw_px = clamp(floor(_src_x2 + ((_mx - _sx) / _sw) * _src_w2), 0, 319);
	                    _raw_py = clamp(floor(_src_y2 + ((_my - _sy) / _sh) * _src_h2), 0, 199);
	                }

	                // ── AUTO-SCROLL WHEN DRAGGING A SHAPE OUTSIDE THE CANVAS ──────────
	                // Photoshop-style edge autopan: distance from canvas edge drives
	                // scroll speed, capped at 8 canvas px/frame. Only relevant when zoomed
	                // in, since bmp_pan_x/y have no effect at the fit-to-window scale.
	                var _shape_dragging_now = (_asset.meta.active_tool == "LINE" && _asset.meta.line_x1 >= 0)
	                    || ((_asset.meta.active_tool == "RECT" || _asset.meta.active_tool == "CIRCLE") && _asset.meta.shape_drawing);
	                if (_shape_dragging_now && _z > bmp_ui_zoom_cap) {
	                    var _as_max_speed = 8;
	                    var _as_edge_dist = 40; // screen px over which speed ramps from 0 to max
	                    var _as_dx = 0, _as_dy = 0;
	                    if (_mx < _sx)             _as_dx = -min(_as_max_speed, ceil(((_sx - _mx) / _as_edge_dist) * _as_max_speed));
	                    else if (_mx > _sx + _sw)  _as_dx =  min(_as_max_speed, ceil(((_mx - (_sx + _sw)) / _as_edge_dist) * _as_max_speed));
	                    if (_my < _sy)             _as_dy = -min(_as_max_speed, ceil(((_sy - _my) / _as_edge_dist) * _as_max_speed));
	                    else if (_my > _sy + _sh)  _as_dy =  min(_as_max_speed, ceil(((_my - (_sy + _sh)) / _as_edge_dist) * _as_max_speed));
	                    if (_as_dx != 0 || _as_dy != 0) {
	                        var _as_px_zoom = _z / bmp_ui_zoom_cap;
	                        var _as_src_w   = max(1, 320 / _as_px_zoom);
	                        var _as_src_h   = max(1, 200 / _as_px_zoom);
	                        _asset.meta.bmp_pan_x = clamp(_asset.meta.bmp_pan_x + _as_dx, 0, 320 - _as_src_w);
	                        _asset.meta.bmp_pan_y = clamp(_asset.meta.bmp_pan_y + _as_dy, 0, 200 - _as_src_h);
	                    }
	                }

// --- HOTKEYS ---
	                // Undo: Ctrl+Z
	                if (keyboard_check_pressed(ord("Z")) && keyboard_check(vk_control)) {
	                    if (array_length(_asset.meta.undo_stack) > 0) {
	                        // Snapshot CURRENT pixels + mask + bg_col into redo
	                        var _redo_buf  = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                        buffer_get_surface(_redo_buf, _asset.meta.preview_surf, 0);
	                        var _redo_mask = array_create(64000, 0);
	                        array_copy(_redo_mask, 0, _asset.meta.bg_mask, 0, 64000);
	                        var _redo_entry = { buf: _redo_buf, mask: _redo_mask, bg_col: _asset.meta.bg_col, bmp_mode: _asset.meta.bmp_mode };
	                        array_push(_asset.meta.redo_stack, _redo_entry);
	                        if (array_length(_asset.meta.redo_stack) > 25) {
	                            var _rdrop0 = _asset.meta.redo_stack[0];
	                            if (is_struct(_rdrop0) && buffer_exists(_rdrop0.buf)) {
	                                buffer_delete(_rdrop0.buf);
	                            } else if (buffer_exists(_rdrop0)) {
	                                buffer_delete(_rdrop0);
	                            }
	                            array_delete(_asset.meta.redo_stack, 0, 1);
	                        }
	                        // Pop undo entry
	                        var _last   = array_length(_asset.meta.undo_stack) - 1;
	                        var _uentry = _asset.meta.undo_stack[_last];
	                        array_delete(_asset.meta.undo_stack, _last, 1);
	                        if (is_struct(_uentry)) {
	                            // New-format entry: restore pixels, mask, and bg_col
	                            buffer_set_surface(_uentry.buf, _asset.meta.preview_surf, 0);
	                            buffer_copy(_uentry.buf, 0, 320 * 200 * 4, _asset.meta.pixel_backup, 0);
	                            buffer_delete(_uentry.buf);
	                            array_copy(_asset.meta.bg_mask, 0, _uentry.mask, 0, 64000);
	                            if (variable_struct_exists(_uentry, "bg_col")) {
	                                _asset.meta.bg_col = _uentry.bg_col;
	                            }
	                            if (variable_struct_exists(_uentry, "bmp_mode")) {
	                                _asset.meta.bmp_mode = _uentry.bmp_mode;
	                            }
	                        } else {
	                            // Legacy raw-buffer entry — pixels only, leave mask/bg_col alone
	                            buffer_set_surface(_uentry, _asset.meta.preview_surf, 0);
	                            buffer_copy(_uentry, 0, 320 * 200 * 4, _asset.meta.pixel_backup, 0);
	                            buffer_delete(_uentry);
	                        }
	                        _asset.meta.bmp_unsaved = true;
	                    }
	                }
	                // Redo: Ctrl+Y
	                if (keyboard_check_pressed(ord("Y")) && keyboard_check(vk_control)) {
	                    if (array_length(_asset.meta.redo_stack) > 0) {
	                        // Snapshot CURRENT pixels + mask + bg_col into undo
	                        var _undo_buf2  = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                        buffer_get_surface(_undo_buf2, _asset.meta.preview_surf, 0);
	                        var _undo_mask2 = array_create(64000, 0);
	                        array_copy(_undo_mask2, 0, _asset.meta.bg_mask, 0, 64000);
	                        var _undo_entry2 = { buf: _undo_buf2, mask: _undo_mask2, bg_col: _asset.meta.bg_col, bmp_mode: _asset.meta.bmp_mode };
	                        array_push(_asset.meta.undo_stack, _undo_entry2);
	                        // Pop redo entry
	                        var _last_r = array_length(_asset.meta.redo_stack) - 1;
	                        var _rentry = _asset.meta.redo_stack[_last_r];
	                        array_delete(_asset.meta.redo_stack, _last_r, 1);
	                        if (is_struct(_rentry)) {
	                            buffer_set_surface(_rentry.buf, _asset.meta.preview_surf, 0);
	                            buffer_copy(_rentry.buf, 0, 320 * 200 * 4, _asset.meta.pixel_backup, 0);
	                            buffer_delete(_rentry.buf);
	                            array_copy(_asset.meta.bg_mask, 0, _rentry.mask, 0, 64000);
	                            if (variable_struct_exists(_rentry, "bg_col")) {
	                                _asset.meta.bg_col = _rentry.bg_col;
	                            }
	                            if (variable_struct_exists(_rentry, "bmp_mode")) {
	                                _asset.meta.bmp_mode = _rentry.bmp_mode;
	                            }
	                        } else {
	                            buffer_set_surface(_rentry, _asset.meta.preview_surf, 0);
	                            buffer_copy(_rentry, 0, 320 * 200 * 4, _asset.meta.pixel_backup, 0);
	                            buffer_delete(_rentry);
	                        }
	                        _asset.meta.bmp_unsaved = true;
	                    }
	                }

	                if (keyboard_check_pressed(ord("G"))) {
	                    if (surface_exists(_asset.meta.grab_surf)) { surface_free(_asset.meta.grab_surf); _asset.meta.grab_surf = -1; }
	                    _asset.meta.active_tool = "GRAB";
	                }
	                if (keyboard_check_pressed(ord("D"))) {
	                    if (surface_exists(_asset.meta.grab_surf)) { surface_free(_asset.meta.grab_surf); _asset.meta.grab_surf = -1; }
	                    _asset.meta.active_tool = "DRAW";
	                }
	                if (keyboard_check_pressed(ord("R"))) _asset.meta.replace_mode = !_asset.meta.replace_mode;
	                if (!variable_struct_exists(_asset.meta, "brush_size")) _asset.meta.brush_size = 2;
	                if (keyboard_check_pressed(219)) _asset.meta.brush_size = max(0, _asset.meta.brush_size - 1);
	                if (keyboard_check_pressed(221)) _asset.meta.brush_size = min(16, _asset.meta.brush_size + 1);

	                var _press_flip_x = keyboard_check_pressed(ord("X"));
	                var _press_flip_y = keyboard_check_pressed(ord("Y")) && !keyboard_check(vk_control);
                    
	                if (_press_flip_x || _press_flip_y) {
	                    if (surface_exists(_asset.meta.grab_surf)) {
	                        // Flip the grab brush
	                        var _tw = _asset.meta.grab_w;
	                        var _th = _asset.meta.grab_h;
	                        var _tsurf = surface_create(_tw, _th);
	                        surface_set_target(_tsurf);
  
	                        draw_clear_alpha(c_black, 0); // clear before flip draw
	                        var _p_fil = gpu_get_texfilter(); gpu_set_texfilter(false);
	                        gpu_set_blendmode_ext(bm_one, bm_zero); // clean 1:1 copy — no alpha accumulation
                            
	                        if (_press_flip_x) {
	                            draw_surface_ext(_asset.meta.grab_surf, _tw, 0, -1, 1, 0, c_white, 1);
	                        } else {
	                            draw_surface_ext(_asset.meta.grab_surf, 0, _th, 1, -1, 0, c_white, 1);
	                        }
                            
	                        gpu_set_blendmode(bm_normal);
	                        gpu_set_texfilter(_p_fil);
	                        surface_reset_target();
	                        surface_copy(_asset.meta.grab_surf, 0, 0, _tsurf);
	                        surface_free(_tsurf);
                            
	                        // Flip the mask array inside the brush
	                        var _old_m = array_create(_tw * _th);
	                        array_copy(_old_m, 0, _asset.meta.grab_mask, 0, _tw * _th);
	                        for(var _gy = 0; _gy < _th; _gy++) {
	                            for(var _gx = 0; _gx < _tw; _gx++) {
	                                if (_press_flip_x) _asset.meta.grab_mask[_gy * _tw + _gx] = _old_m[_gy * _tw + (_tw - 1 - _gx)];
	                                else               _asset.meta.grab_mask[_gy * _tw + _gx] = _old_m[(_th - 1 - _gy) * _tw + _gx];
	                            }
	                        }
	                        // Track X-flip parity so the anchor can compensate for the half-MC-pair
	                        // shift the mirror introduces (flipped stamps need 1 C64px further left).
	                        if (!variable_struct_exists(_asset.meta, "grab_flip_x")) _asset.meta.grab_flip_x = false;
	                        if (_press_flip_x) _asset.meta.grab_flip_x = !_asset.meta.grab_flip_x;
	                        // Invalidate cached preview anchor so the stamp preview re-evaluates this frame
	                        // (otherwise the mirrored pixels keep drawing at the pre-flip position until a surface rebuild)
	                        _asset.meta._ov_last_mx = -1;
	                        _asset.meta._ov_last_my = -1;
	                    } else {
	                        // Flip entire canvas
	                        scr_asset_bmp_flip(_asset, _press_flip_x, _press_flip_y);
	                    }
	                }



	                // --- TOOL EXECUTION LOGIC ---
	                if (_in_bounds) {
	                    if (_asset.meta.active_tool == "GRAB") {
	                        // Marquee Drag Logic
							if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
	                            _asset.meta.is_grabbing = true;
	                            _asset.meta.grab_x1 = _raw_px;
	                            _asset.meta.grab_y1 = _raw_py;
	                        }
                            
	                        if (_asset.meta.is_grabbing && mouse_check_button_released(mb_left)) {
	                            _asset.meta.is_grabbing = false;
                                
	                            var _gx1 = floor(min(_asset.meta.grab_x1, _raw_px));
								var _gy1 = floor(min(_asset.meta.grab_y1, _raw_py))-1;
								var _gx2 = floor(max(_asset.meta.grab_x1, _raw_px));
								var _gy2 = floor(max(_asset.meta.grab_y1, _raw_py));
                                
								if (_bmp_is_hires) {
								    // HiRes: every pixel is independently addressable, no pair snapping.
								    _asset.meta.grab_w = (_gx2 - _gx1) + 1;
								    _asset.meta.grab_h = (_gy2 - _gy1) + 1;
								} else {
								    _gx1 = ((_gx1 div 2) * 2) - 1;  // Snap left to even MC boundary, -2 to include 1 extra MC pair on left       // Snap left to even MC boundary
	                            _gx2 = (_gx2 div 2) * 2;        // Snap right to MC pair start (even)

	                            _asset.meta.grab_w = (_gx2 - _gx1) + 2; // +2 includes full right MC pair, always even
	                            _asset.meta.grab_h = (_gy2 - _gy1) + 1;
								}

                                
	                            // DEBUG: store capture coords for display
	                            _asset.meta.dbg_gx1 = _gx1;
	                            _asset.meta.dbg_gy1 = _gy1;
	                            _asset.meta.dbg_gx2 = _gx2;
	                            _asset.meta.dbg_gy2 = _gy2;
	                            _asset.meta.dbg_raw_x1 = _asset.meta.grab_x1;
	                            _asset.meta.dbg_raw_y1 = _asset.meta.grab_y1;
	                            _asset.meta.dbg_raw_x2 = _raw_px;
	                            _asset.meta.dbg_raw_y2 = _raw_py;

if (_asset.meta.grab_w > 0 && _asset.meta.grab_h > 0) {
	                                if (surface_exists(_asset.meta.grab_surf)) surface_free(_asset.meta.grab_surf);
	                                _asset.meta.grab_surf = surface_create(_asset.meta.grab_w, _asset.meta.grab_h);
                                    
	                                // Anchor is top-left — offset applied at draw time
	                                if (_bmp_is_hires) {
	                                    // HiRes: simple centre pivot, no MC-pair boundary snapping.
	                                    _asset.meta.grab_cx = _asset.meta.grab_w div 2;
	                                    _asset.meta.grab_cy = _asset.meta.grab_h div 2;
	                                } else {
	                                // Centre pivot on MC-snapped width, then floor to even MC boundary
	                                var _half_w = (_asset.meta.grab_w div 2) - 1;
	                                _asset.meta.grab_cx = (_half_w mod 2 == 0) ? _half_w : _half_w - 1;
	                                _asset.meta.grab_cy = (_asset.meta.grab_h div 2) - 1;
	                                }

	                                _asset.meta.grab_mask = array_create(_asset.meta.grab_w * _asset.meta.grab_h, 0);
                                    
	                                // Extract pixels safely to build a transparent stamp
									if (!variable_struct_exists(_asset.meta, "preview_surf") || !surface_exists(_asset.meta.preview_surf)) {
										_asset.meta.is_grabbing = false;
										return; 
									}

									var _buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
									buffer_get_surface(_buf, _asset.meta.preview_surf, 0);
	                                var _bg_c = scr_c64_pepto_colour(_asset.meta.bg_col);
	                                var _b_r = color_get_red(_bg_c), _b_g = color_get_green(_bg_c), _b_b = color_get_blue(_bg_c);
									
									if (!surface_exists(_asset.meta.grab_surf)) {
										_asset.meta.grab_surf = surface_create(_asset.meta.grab_w, _asset.meta.grab_h);
									}

	                                surface_set_target(_asset.meta.grab_surf);
	                                draw_clear_alpha(c_black, 0); // Start completely transparent
                                    
									for (var _yy = 0; _yy < _asset.meta.grab_h; _yy++) {
	                                    for (var _xx = 0; _xx < _asset.meta.grab_w; _xx++) {
	                                        var _gx = _gx1 + _xx;
	                                        var _gy = _gy1 + _yy;
	                                        if (_gx < 0 || _gx >= 320 || _gy < 0 || _gy >= 200) continue;
	                                        var _mx_idx = _gy * 320 + _gx;
                                            
	                                        var _idx = _mx_idx * 4;
	                                        var _r = buffer_peek(_buf, _idx, buffer_u8);
	                                        var _g = buffer_peek(_buf, _idx + 1, buffer_u8);
	                                        var _b = buffer_peek(_buf, _idx + 2, buffer_u8);
                                            
	                                        // Transparency test: black (palette index 0) is treated as
	                                        // transparent for HiRes capture — same idea as MC's bg-colour
	                                        // exclusion, but hardcoded rather than tied to a per-asset
	                                        // bg_col (HiRes has no such concept). Placing a stamp can still
	                                        // clash against the destination cell's existing pair — that's
	                                        // expected and resolves the same way any other paint does.
	                                        var _hr_include = _bmp_is_hires && (_r != 0 || _g != 0 || _b != 0);
	                                        var _mc_include = !_bmp_is_hires && (_r != _b_r || _g != _b_g || _b != _b_b);
	                                        if (_hr_include || _mc_include) {
	                                            draw_set_color(make_color_rgb(_r, _g, _b));
	                                            draw_point(_xx, _yy);
	                                            if (_mx_idx < 64000) {
	                                                _asset.meta.grab_mask[_yy * _asset.meta.grab_w + _xx] = _asset.meta.bg_mask[_mx_idx];
	                                            }
	                                        }
	                                    }
	                                }
	                                surface_reset_target();
	                                buffer_delete(_buf);
                                    
	                                // Fresh capture is unflipped — clear X-flip parity
	                                _asset.meta.grab_flip_x = false;
	                                // Turn them into a stamp brush immediately
	                                _asset.meta.active_tool = "DRAW";
	                            }
	                        }
                            
	} else if ((_is_left || _is_right) && _asset.meta.active_tool == "DRAW" && !keyboard_check(vk_alt)) {
                            
	                        // Shift-click: draw a line from last confirmed plot to here using current brush
                if (mouse_check_button_pressed(mb_left) && keyboard_check(vk_shift)) {
                    if (_asset.meta.shift_last_px >= 0) {
                        var _shift_col  = _asset.meta.active_color;
                        var _shift_mask = 1;
                        // Push pre-shift-line snapshot in new struct format
                        if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
                            var _shift_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
                            buffer_get_surface(_shift_buf, _asset.meta.preview_surf, 0);
                            var _shift_mask_snap = array_create(64000, 0);
                            array_copy(_shift_mask_snap, 0, _asset.meta.bg_mask, 0, 64000);
                            var _shift_entry = { buf: _shift_buf, mask: _shift_mask_snap, bg_col: _asset.meta.bg_col };
                            array_push(_asset.meta.undo_stack, _shift_entry);
                            if (array_length(_asset.meta.undo_stack) > 25) {
                                var _sdrop0 = _asset.meta.undo_stack[0];
                                if (is_struct(_sdrop0) && buffer_exists(_sdrop0.buf)) {
                                    buffer_delete(_sdrop0.buf);
                                } else if (buffer_exists(_sdrop0)) {
                                    buffer_delete(_sdrop0);
                                }
                                array_delete(_asset.meta.undo_stack, 0, 1);
                            }
                            _asset.meta.redo_stack = [];
                        }
                        scr_asset_bmp_draw_line(_asset,
                            _asset.meta.shift_last_px, _asset.meta.shift_last_py,
                            _raw_px, _raw_py,
                            _shift_col, _shift_mask,
                            undefined, true);
                        _asset.meta.pixels_dirty    = true;
                        _asset.meta.bmp_unsaved     = true;
                        _asset.meta.needs_clash_check = true;
                    }
                    _asset.meta.shift_last_px = _raw_px;
                    _asset.meta.shift_last_py = _raw_py;
                } else if (_asset.meta.last_px == undefined) {
                    if (!keyboard_check(vk_shift)) {
                        _asset.meta.last_px = _raw_px;
                        _asset.meta.last_py = _raw_py;
                    }
                    _asset.meta.shift_last_px = _raw_px;
                    _asset.meta.shift_last_py = _raw_py;
                    // Push pre-stroke snapshot once per mouse-down so every stroke is undoable.
                    // Snapshot pixels + mask + bg_col so undo fully restores state.
                    if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
                        var _stroke_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
                        buffer_get_surface(_stroke_buf, _asset.meta.preview_surf, 0);
                        var _stroke_mask = array_create(64000, 0);
                        array_copy(_stroke_mask, 0, _asset.meta.bg_mask, 0, 64000);
                        var _stroke_entry = {
                            buf:    _stroke_buf,
                            mask:   _stroke_mask,
                            bg_col: _asset.meta.bg_col
                        };
                        array_push(_asset.meta.undo_stack, _stroke_entry);
                        if (array_length(_asset.meta.undo_stack) > 25) {
                            var _drop0 = _asset.meta.undo_stack[0];
                            if (is_struct(_drop0) && buffer_exists(_drop0.buf)) {
                                buffer_delete(_drop0.buf);
                            } else if (buffer_exists(_drop0)) {
                                buffer_delete(_drop0);
                            }
                            array_delete(_asset.meta.undo_stack, 0, 1);
                        }
                        _asset.meta.redo_stack = [];
                    }
                }
                            
	                       if (is_undefined(_asset.meta.last_px)) _asset.meta.last_px = _raw_px;
                        if (is_undefined(_asset.meta.last_py)) _asset.meta.last_py = _raw_py;
                        var _dist  = max(1, point_distance(_asset.meta.last_px, _asset.meta.last_py, _raw_px, _raw_py));
	                        var _steps = ceil(_dist);
	                        var _paint_col = _is_left ? _asset.meta.active_color : _asset.meta.bg_col;
	                        var _mask_val  = _is_left ? 1 : 0;
	                        var _color     = scr_c64_pepto_colour(_paint_col);
	                        var _det_color = scr_c64_pepto_colour(_asset.meta.replace_col_detect);
	                        var _det_r = color_get_red(_det_color);
	                        var _det_g = color_get_green(_det_color);
	                        var _det_b = color_get_blue(_det_color);
	                        var _det_key = (_det_r << 16) | (_det_g << 8) | _det_b;
                            
                            
	                        surface_set_target(_asset.meta.preview_surf);
							
	                        _prev_filter = gpu_get_texfilter();
	                        gpu_set_texfilter(false);
                            
// USING GRAB BRUSH
	                        if (surface_exists(_asset.meta.grab_surf)) {
	                            var _sdmode = _asset.meta.dither_mode;
	                            var _sdinv  = _asset.meta.dither_invert;
	                            var _using_dither = (_sdmode != "NONE");
                                
	                            // Read stamp pixels into buffer once for per-pixel dither writes.
	                            // HiRes also needs per-pixel colour lookups for role tracking even
	                            // when not dithering, so it always builds this buffer too.
	                            var _stamp_buf = -1;
	                            if (_using_dither || _bmp_is_hires) {
	                                _stamp_buf = buffer_create(_asset.meta.grab_w * _asset.meta.grab_h * 4, buffer_fixed, 1);
	                                buffer_get_surface(_stamp_buf, _asset.meta.grab_surf, 0);
	                            }
                                
	                            // HiRes: one fg/bg pair for the whole stamp (see
	                            // scr_asset_bmp_hr_get_stamp_pair), and a per-canvas-cell
	                            // "touched" flag so every cell the stamp crosses gets
	                            // GPU-repainted exactly once after the full drag is placed,
	                            // not once per pixel.
	                            var _hr_pair = { fg: 1, bg: 0 };
	                            var _hr_touched = -1;
	                            if (_bmp_is_hires) {
	                                _hr_pair = scr_asset_bmp_hr_get_stamp_pair(_asset);
	                                _hr_touched = array_create(1000, false);
	                            }
                                
	                            for (var _i = 0; _i <= _steps; _i++) {
	                                var _px = floor(lerp(_asset.meta.last_px, _raw_px, _i / _steps));
	                                var _py = floor(lerp(_asset.meta.last_py, _raw_py, _i / _steps));
	                                _px = (_px div _bmp_step) * _bmp_step; // do not touch offsets the grabbed brush
                                    
	                                // Mirror half-pair compensation only applies to MC's 2-wide pairing;
	                                // HiRes pixels are independently addressable, so no bias is needed.
	                                var _flip_bias = (!_bmp_is_hires && _asset.meta.grab_flip_x) ? -1 : 0;
	                                var _draw_x = _px - _asset.meta.grab_cx - _bmp_step + _flip_bias;
	                                _draw_x = ((_draw_x div _bmp_step) * _bmp_step) - _flip_bias;
	                                var _draw_y = _py - _asset.meta.grab_cy;
                                    
	                               if (!_using_dither) {
	                                    // No dither — draw whole stamp surface as before
	                                    var _use_fog = false;
	                                    var _fog_col = c_white;
	                                    if (_is_right && !_bmp_is_hires) { _use_fog = true; _fog_col = scr_c64_pepto_colour(_asset.meta.bg_col); }
	                                    else if (keyboard_check(vk_control)) { _use_fog = true; _fog_col = scr_c64_pepto_colour(_asset.meta.active_color); }
	                                    if (_use_fog) gpu_set_fog(true, _fog_col, 0, 0);
	                                    draw_surface(_asset.meta.grab_surf, _draw_x, _draw_y);
	                                    if (_use_fog) gpu_set_fog(false, c_white, 0, 0);
	                                    for (var _gy = 0; _gy < _asset.meta.grab_h; _gy++) {
	                                        for (var _gx = 0; _gx < _asset.meta.grab_w; _gx++) {
	                                            var _tx = _draw_x + _gx;
	                                            var _ty = _draw_y + _gy;
	                                            var _sidx0 = (_gy * _asset.meta.grab_w + _gx) * 4;
	                                            // HiRes gates on the stamp's actual OPACITY (every non-black
	                                            // captured pixel, per the capture-time transparency fix) —
	                                            // NOT grab_mask, which is a leftover protection bit that
	                                            // left the fill's role bookkeeping stale (fill blitted
	                                            // correctly, then the whole-cell repaint below read the
	                                            // stale role and overwrote it with the wrong pair colour —
	                                            // that was the white-box bug). MC keeps grab_mask gating.
	                                            var _place_here = _bmp_is_hires
	                                                ? (buffer_peek(_stamp_buf, _sidx0 + 3, buffer_u8) != 0)
	                                                : (_asset.meta.grab_mask[_gy * _asset.meta.grab_w + _gx] > 0);
	                                            if (_place_here) {
	                                                if (_ty >= 0 && _ty < 200 && _tx >= 0 && _tx < 320) {
	                                                    _asset.meta.bg_mask[_ty * 320 + _tx] = _mask_val;
	                                                    if (_bmp_is_hires) {
	                                                        // Classify this stamp pixel against the stamp's
	                                                        // derived pair (nearest of fg/bg) and mark its
	                                                        // cell for a post-drag repaint.
	                                                        var _sr0 = buffer_peek(_stamp_buf, _sidx0,     buffer_u8);
	                                                        var _sg0 = buffer_peek(_stamp_buf, _sidx0 + 1, buffer_u8);
	                                                        var _sb0 = buffer_peek(_stamp_buf, _sidx0 + 2, buffer_u8);
	                                                        var _fg_c0 = scr_c64_pepto_colour(_hr_pair.fg);
	                                                        var _bg_c0 = scr_c64_pepto_colour(_hr_pair.bg);
	                                                        var _dist_fg0 = abs(_sr0 - color_get_red(_fg_c0)) + abs(_sg0 - color_get_green(_fg_c0)) + abs(_sb0 - color_get_blue(_fg_c0));
	                                                        var _dist_bg0 = abs(_sr0 - color_get_red(_bg_c0)) + abs(_sg0 - color_get_green(_bg_c0)) + abs(_sb0 - color_get_blue(_bg_c0));
	                                                        var _use_fg0 = (_dist_fg0 <= _dist_bg0);
	                                                        var _hrc0 = (floor(_ty / 8) * 40) + floor(_tx / 8);
	                                                        _asset.meta.hr_role_mask[_ty * 320 + _tx] = _use_fg0 ? 1 : 0;
	                                                        _hr_touched[_hrc0] = true;
	                                                    }
	                                                }
	                                            }
	                                        }
	                                    }
	                                    if (_bmp_is_hires) {
	                                        for (var _hci0 = 0; _hci0 < 1000; _hci0++) {
	                                            if (_hr_touched[_hci0]) {
	                                                _asset.meta.hr_cell_fg_col[_hci0] = _hr_pair.fg;
	                                                _asset.meta.hr_cell_bg_col[_hci0] = _hr_pair.bg;
	                                            }
	                                        }
	                                    }
	                                } else {
	                                    // Dither — write pixels individually (MC pairs, or single HiRes pixels)
	                                    var _paint_col_stamp = _is_right ? _asset.meta.bg_col : _asset.meta.active_color;
	                                    var _dith_max_x = _bmp_is_hires ? 319 : 318;
	                                    var _dith_step  = _bmp_is_hires ? 1 : 2;
	                                    for (var _gy = 0; _gy < _asset.meta.grab_h; _gy++) {
	                                        for (var _gx = 0; _gx < _asset.meta.grab_w; _gx += _dith_step) {
	                                            var _tx = _draw_x + _gx;
	                                            var _ty = _draw_y + _gy;;
	                                            if (_tx < 0 || _tx > _dith_max_x || _ty < 0 || _ty >= 200) continue;
                                                
												
												var _dok = ((_tx >= 0 && _tx < 320 && _ty >= 0 && _ty < 200) && array_length(_dither_cache) > 1)
	                                                        ? _dither_cache[_ty * 320 + _tx]
	                                                        : scr_check_dither_mask(_sdmode, _tx, _ty, _bmp_is_hires);
	                                            if (!_dok) continue;
												
												
	                                            // Read stamp colour
	                                            var _sidx = (_gy * _asset.meta.grab_w + _gx) * 4;
	                                            var _sa   = buffer_peek(_stamp_buf, _sidx + 3, buffer_u8);
	                                            if (_sa == 0) continue; // transparent pixel — skip
	                                            var _sr = buffer_peek(_stamp_buf, _sidx,     buffer_u8);
	                                            var _sg = buffer_peek(_stamp_buf, _sidx + 1, buffer_u8);
	                                            var _sb = buffer_peek(_stamp_buf, _sidx + 2, buffer_u8);
	                                            // Override for right-click erase, CTRL tint, or ALT solid
	                                            if (_is_right && !_bmp_is_hires) {
	                                                var _ec = scr_c64_pepto_colour(_asset.meta.bg_col);
	                                                _sr = color_get_red(_ec); _sg = color_get_green(_ec); _sb = color_get_blue(_ec);
	                                            } else if (keyboard_check(vk_control)) {
	                                                // Tint: force active colour but keep stamp shape (same as non-dither ctrl behaviour)
	                                                var _tc = scr_c64_pepto_colour(_asset.meta.active_color);
	                                                _sr = color_get_red(_tc); _sg = color_get_green(_tc); _sb = color_get_blue(_tc);
	                                            } else if (keyboard_check(vk_alt)) {
	                                                var _ac = scr_c64_pepto_colour(_asset.meta.active_color);
	                                                _sr = color_get_red(_ac); _sg = color_get_green(_ac); _sb = color_get_blue(_ac);
	                                            }
                                                
	                                            if (_bmp_is_hires) {
	                                                var _fg_c1 = scr_c64_pepto_colour(_hr_pair.fg);
	                                                var _bg_c1 = scr_c64_pepto_colour(_hr_pair.bg);
	                                                var _dist_fg1 = abs(_sr - color_get_red(_fg_c1)) + abs(_sg - color_get_green(_fg_c1)) + abs(_sb - color_get_blue(_fg_c1));
	                                                var _dist_bg1 = abs(_sr - color_get_red(_bg_c1)) + abs(_sg - color_get_green(_bg_c1)) + abs(_sb - color_get_blue(_bg_c1));
	                                                var _use_fg1 = (_dist_fg1 <= _dist_bg1);
	                                                draw_set_color(_use_fg1 ? _fg_c1 : _bg_c1);
	                                                draw_rectangle(_tx, _ty, _tx + 1, _ty + 1, false);
	                                                _asset.meta.bg_mask[_ty * 320 + _tx] = _mask_val;
	                                                var _hrc1 = (floor(_ty / 8) * 40) + floor(_tx / 8);
	                                                _asset.meta.hr_role_mask[_ty * 320 + _tx] = _use_fg1 ? 1 : 0;
	                                                _hr_touched[_hrc1] = true;
	                                            } else {
	                                            // Write MC pair directly to surface buffer
	                                            var _off1 = (_ty * 320 + _tx) * 4;
	                                            var _off2 = (_ty * 320 + _tx + 1) * 4;
	                                            // We are already inside surface_set_target(preview_surf)
	                                            draw_set_color(make_color_rgb(_sr, _sg, _sb));
	                                            draw_point(_tx + 1, _ty + 1);
	                                            draw_point(_tx + 2, _ty + 1);
	                                            _asset.meta.bg_mask[(_ty + 1) * 320 + _tx + 1] = _mask_val;
	                                            _asset.meta.bg_mask[(_ty + 1) * 320 + _tx + 2] = _mask_val;
	                                            }
	                                        }
	                                    }
	                                    if (_bmp_is_hires) {
	                                        for (var _hci1 = 0; _hci1 < 1000; _hci1++) {
	                                            if (_hr_touched[_hci1]) {
	                                                _asset.meta.hr_cell_fg_col[_hci1] = _hr_pair.fg;
	                                                _asset.meta.hr_cell_bg_col[_hci1] = _hr_pair.bg;
	                                            }
	                                        }
	                                    }
	                                }
	                            }
                                
	                            // Repaint every cell the stamp touched, once, from the just-updated
	                            // role model. GPU-only (draw_rectangle), since preview_surf is the
	                            // active render target right now — same reasoning as freehand DRAW.
	                            if (_bmp_is_hires) {
	                                for (var _hci2 = 0; _hci2 < 1000; _hci2++) {
	                                    if (_hr_touched[_hci2]) {
	                                        scr_asset_bmp_hr_repaint_cell_gpu(_asset, _hci2);
	                                    }
	                                }
	                            }
                                
	                            if (buffer_exists(_stamp_buf)) buffer_delete(_stamp_buf);
                                
	                        // USING STANDARD BRUSH
	                        } else {
	                        var _bsz = _asset.meta.brush_size;
	                        var _brad2 = max(0, _bsz);
	                        // Primary (LMB) vs Secondary (RMB) paint colour/protection.
	                        // HiRes RMB paints a protected secondary colour; MC RMB still
	                        // erases to background (unprotected), same as before.
	                        var _std_paint_col, _std_mask_val;
	                        if (_is_left) {
	                            _std_paint_col = _asset.meta.active_color;
	                            _std_mask_val  = 1;
	                        } else if (_bmp_is_hires) {
	                            _std_paint_col = _asset.meta.secondary_color;
	                            _std_mask_val  = 1;
	                        } else {
	                            _std_paint_col = _asset.meta.bg_col;
	                            _std_mask_val  = 0;
	                        }
	                        var _std_color = scr_c64_pepto_colour(_std_paint_col);
	                            // Each brush is built from 2x1 MC pixel blocks
	                            // size 0 = 1 block (2x1), size N = circle of radius N in MC pixels
	                            var _brad = max(0, _bsz);
	                            var _bsurf_w = (_brad == 0) ? 2 : ((_brad * 2 + 1) * 2); // always even
	                            var _bsurf_h = (_brad == 0) ? 1 : (_brad * 2 + 1);
	                            if (!variable_struct_exists(_asset.meta, "brush_surf") || !surface_exists(_asset.meta.brush_surf) ||
	                                surface_get_width(_asset.meta.brush_surf) != _bsurf_w || surface_get_height(_asset.meta.brush_surf) != _bsurf_h) {
	                                if (surface_exists(_asset.meta.brush_surf)) surface_free(_asset.meta.brush_surf);
	                                _asset.meta.brush_surf = surface_create(_bsurf_w, _bsurf_h);
	                                surface_set_target(_asset.meta.brush_surf);
	                                draw_clear_alpha(c_black, 0);
	                                draw_set_color(c_white);
	                                if (_brad == 0) {
	                                    draw_rectangle(0, 0, 1, 0, false); // single 2x1 block
	                                } else {
	                                    // Draw filled circle using 2x1 MC pixel blocks
	                                    var _bcx = _brad;
	                                    var _bcy = _brad;
	                                    for (var _by = 0; _by <= _brad * 2; _by++) {
	                                        for (var _bx = 0; _bx <= _brad * 2; _bx++) {
	                                            var _dx = (_bx - _brad) / (_brad * 1.0);
	                                            var _dy = (_by - _brad) / (_brad * 0.5);
	                                            if (_dx * _dx + _dy * _dy <= 1.0) {
	                                                var _even_bx = (_bx div 1) * 2; // MC pair
	                                                draw_rectangle(_even_bx, _by, _even_bx + 1, _by, false);
	                                            }
	                                        }
	                                    }
	                                }
	                                surface_reset_target();
	                            }
	                            gpu_set_blendmode_ext(bm_one, bm_zero);
	                            var _max_bx = _bmp_is_hires ? 319 : 318;
	                            for (var _i = 0; _i <= _steps; _i++) {
	                                var _px = floor(lerp(_asset.meta.last_px, _raw_px, _i / _steps));
	                                var _py = floor(lerp(_asset.meta.last_py, _raw_py, _i / _steps));
	                                var _read_buf = -1;
	                                if (_asset.meta.replace_mode && _brad2 > 0) {
	                                    _read_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                                    buffer_get_surface(_read_buf, _asset.meta.preview_surf, 0);
	                                }
	                                if (_px >= 0 && _px <= 319 && _py >= 0 && _py < 200) {
	                                    _px = (_px div _bmp_step) * _bmp_step;
	                                    var _draw_allowed = true;
	                                    if (_asset.meta.replace_mode && _brad2 == 0) {
	                                        // Single pixel — check anchor colour
	                                        var _cur_c = surface_getpixel(_asset.meta.preview_surf, _px, _py);
	                                        if (_cur_c != _det_color) _draw_allowed = false;
	                                    }
						
	                    if (_asset.meta.dither_mode != "NONE" && _brad2 == 0) {
	                        var _dmask = ((_px >= 0 && _px < 320 && _py >= 0 && _py < 200) && array_length(_dither_cache) > 1)
	                                    ? _dither_cache[_py * 320 + _px]
	                                    : scr_check_dither_mask(_asset.meta.dither_mode, _px, _py, _bmp_is_hires);
	                        if (_asset.meta.dither_invert) _dmask = !_dmask;
	                        _draw_allowed = _dmask;
	                    }
	                    if (_draw_allowed) {
	                        var _final_c = _asset.meta.replace_mode ? scr_c64_pepto_colour(_asset.meta.replace_col_target) : _std_color;
	                        draw_set_color(_final_c);							
							
							
	                        if (_brad2 == 0) {
                                            if (_px >= 0 && _px <= _max_bx && _py >= 0 && _py < 200) {
                                                if (_bmp_is_hires) {
                                                    _asset.meta.bg_mask[_py * 320 + _px] = _std_mask_val;
                                                    var _hrcd = (floor(_py / 8) * 40) + floor(_px / 8);
                                                    _asset.meta.hr_role_mask[_py * 320 + _px] = _is_left ? 1 : 0;
                                                    if (_is_left) { _asset.meta.hr_cell_fg_col[_hrcd] = _std_paint_col; }
                                                    else          { _asset.meta.hr_cell_bg_col[_hrcd] = _std_paint_col; }
                                                    // GPU-only repaint of the WHOLE touched cell — never a buffer
                                                    // round-trip here, since preview_surf is the active render
                                                    // target right now (buffer_get_surface on it mid-render is
                                                    // unreliable and previously wiped the canvas to black).
                                                    scr_asset_bmp_hr_repaint_cell_gpu(_asset, _hrcd);
                                                } else {
                                                    draw_rectangle(_px, _py, _px + 2, _py + 1, false);
                                                    _asset.meta.bg_mask[_py * 320 + _px]     = _std_mask_val;
                                                    _asset.meta.bg_mask[_py * 320 + _px + 1] = _std_mask_val;
                                                }
                                            }
	                        } else {
		
								
	                            for (var _bmy = -_brad2; _bmy <= _brad2; _bmy++) {
	                                for (var _bmx = -_brad2; _bmx <= _brad2; _bmx++) {
	                                    // MC brush pixels are 2 world-px wide (2:1 aspect), so the X
	                                    // term is doubled to correct for it; HiRes pixels are square.
	                                    var _dx2 = _bmp_is_hires ? (_bmx / _brad2) : ((_bmx * 2) / _brad2);
	                                    var _dy2 = _bmy / _brad2;
	                                    if (_dx2 * _dx2 + _dy2 * _dy2 > 1.0) continue;
	                                    var _bmtx = (_px + _bmx * _bmp_step);
	                                    _bmtx = (_bmtx div _bmp_step) * _bmp_step;
	                                    var _bmty = _py + _bmy;
	                                    if (_bmtx >= 0 && _bmtx <= _max_bx && _bmty >= 0 && _bmty < 200) {
	                                        // Per-pixel dither check at world position
	                                        var _bdok = true;
	                                        if (_asset.meta.dither_mode != "NONE") {
                                            _bdok = ((_bmtx >= 0 && _bmtx < 320 && _bmty >= 0 && _bmty < 200) && array_length(_dither_cache) > 1)
                                                    ? _dither_cache[_bmty * 320 + _bmtx]
                                                    : scr_check_dither_mask(_asset.meta.dither_mode, _bmtx, _bmty, _bmp_is_hires);
                                            if (_asset.meta.dither_invert) _bdok = !_bdok;
                                        }
	                                        if (_bdok) {
	                                            // Replace mode — check each pixel's actual colour before overwriting
	                                            var _do_paint = true;
	                                            if (_asset.meta.replace_mode) {
	                                                var _buf_off = (_bmty * 320 + _bmtx) * 4;
	                                                var _br = buffer_peek(_read_buf, _buf_off,     buffer_u8);
	                                                var _bg2 = buffer_peek(_read_buf, _buf_off + 1, buffer_u8);
	                                                var _bb = buffer_peek(_read_buf, _buf_off + 2, buffer_u8);
	                                                var _bkey = (_br << 16) | (_bg2 << 8) | _bb;

	                                                _do_paint = (_bkey == _det_key);
	                                            }
	                                            if (_do_paint) {
	                                                if (_bmp_is_hires) {
	                                                    _asset.meta.bg_mask[_bmty * 320 + _bmtx] = _std_mask_val;
	                                                    var _hrce = (floor(_bmty / 8) * 40) + floor(_bmtx / 8);
	                                                    _asset.meta.hr_role_mask[_bmty * 320 + _bmtx] = _is_left ? 1 : 0;
	                                                    if (_is_left) { _asset.meta.hr_cell_fg_col[_hrce] = _std_paint_col; }
	                                                    else          { _asset.meta.hr_cell_bg_col[_hrce] = _std_paint_col; }
	                                                    scr_asset_bmp_hr_repaint_cell_gpu(_asset, _hrce);
	                                                } else {
	                                                    draw_rectangle(_bmtx, _bmty, _bmtx + 2, _bmty + 1, false);
	                                                    _asset.meta.bg_mask[_bmty * 320 + _bmtx]     = _std_mask_val;
	                                                    _asset.meta.bg_mask[_bmty * 320 + _bmtx + 1] = _std_mask_val;
	                                                }
	                                            }
	                                        }
	                                    }
	                                }
	                            }
	                        }
	                    }
					} // end _draw_allowed
	                                } // end if _px in bounds
	                                if (buffer_exists(_read_buf)) buffer_delete(_read_buf);
	                            } // end steps loop
	                        gpu_set_blendmode(bm_normal);
	                        gpu_set_texfilter(_prev_filter);
	                        surface_reset_target();
	                        _asset.meta.last_px = _raw_px;
	                        _asset.meta.last_py = _raw_py;
	                        _asset.meta.needs_clash_check = true;
	                        _asset.meta.pixels_dirty = true;
							_asset.meta.bmp_unsaved = true;

} else if (_asset.meta.active_tool == "LINE") {
                            
	                        // Press sets anchor and records which button
	                        if (mouse_check_button_pressed(mb_left) || mouse_check_button_pressed(mb_right)) {
	                            _asset.meta.line_x1    = (_raw_px div _bmp_step) * _bmp_step;
	                            _asset.meta.line_y1    = _raw_py;
	                            _asset.meta.line_btn   = mouse_check_button_pressed(mb_left) ? mb_left : mb_right;
	                            // Push pre-line snapshot in new struct format
	                            if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
	                                var _line_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                                buffer_get_surface(_line_buf, _asset.meta.preview_surf, 0);
	                                var _line_mask_snap = array_create(64000, 0);
	                                array_copy(_line_mask_snap, 0, _asset.meta.bg_mask, 0, 64000);
	                                var _line_entry = { buf: _line_buf, mask: _line_mask_snap, bg_col: _asset.meta.bg_col };
	                                array_push(_asset.meta.undo_stack, _line_entry);
	                                if (array_length(_asset.meta.undo_stack) > 25) {
	                                    var _ldrop0 = _asset.meta.undo_stack[0];
	                                    if (is_struct(_ldrop0) && buffer_exists(_ldrop0.buf)) {
	                                        buffer_delete(_ldrop0.buf);
	                                    } else if (buffer_exists(_ldrop0)) {
	                                        buffer_delete(_ldrop0);
	                                    }
	                                    array_delete(_asset.meta.undo_stack, 0, 1);
	                                }
	                                _asset.meta.redo_stack = [];
	                            }
	                        }
                            
	                        } else if (_asset.meta.active_tool == "RECT" || _asset.meta.active_tool == "CIRCLE") {
                            
	                        if (mouse_check_button_pressed(mb_left) || mouse_check_button_pressed(mb_right)) {
	                            _asset.meta.shape_x1      = (_raw_px div _bmp_step) * _bmp_step;
	                            _asset.meta.shape_y1      = _raw_py;
	                            _asset.meta.shape_drawing = true;
	                            _asset.meta.shape_btn     = mouse_check_button_pressed(mb_left) ? mb_left : mb_right;
	                            // Push pre-shape snapshot in new struct format
	                            if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
	                                var _shape_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                                buffer_get_surface(_shape_buf, _asset.meta.preview_surf, 0);
	                                var _shape_mask_snap = array_create(64000, 0);
	                                array_copy(_shape_mask_snap, 0, _asset.meta.bg_mask, 0, 64000);
	                                var _shape_entry = { buf: _shape_buf, mask: _shape_mask_snap, bg_col: _asset.meta.bg_col };
	                                array_push(_asset.meta.undo_stack, _shape_entry);
	                                if (array_length(_asset.meta.undo_stack) > 25) {
	                                    var _shdrop0 = _asset.meta.undo_stack[0];
	                                    if (is_struct(_shdrop0) && buffer_exists(_shdrop0.buf)) {
	                                        buffer_delete(_shdrop0.buf);
	                                    } else if (buffer_exists(_shdrop0)) {
	                                        buffer_delete(_shdrop0);
	                                    }
	                                    array_delete(_asset.meta.undo_stack, 0, 1);
	                                }
	                                _asset.meta.redo_stack = [];
	                            }
	                        }
                            
	                        } else if ((mouse_check_button_pressed(mb_left) || mouse_check_button_pressed(mb_right)) && _asset.meta.active_tool == "FILL") {
	                        // Push pre-fill snapshot in new struct format
	                        if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
	                            var _fill_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                            buffer_get_surface(_fill_buf, _asset.meta.preview_surf, 0);
	                            var _fill_mask_snap = array_create(64000, 0);
	                            array_copy(_fill_mask_snap, 0, _asset.meta.bg_mask, 0, 64000);
	                            var _fill_entry = { buf: _fill_buf, mask: _fill_mask_snap, bg_col: _asset.meta.bg_col };
	                            array_push(_asset.meta.undo_stack, _fill_entry);
	                            if (array_length(_asset.meta.undo_stack) > 25) {
	                                var _fdrop0 = _asset.meta.undo_stack[0];
	                                if (is_struct(_fdrop0) && buffer_exists(_fdrop0.buf)) {
	                                    buffer_delete(_fdrop0.buf);
	                                } else if (buffer_exists(_fdrop0)) {
	                                    buffer_delete(_fdrop0);
	                                }
	                                array_delete(_asset.meta.undo_stack, 0, 1);
	                            }
	                            _asset.meta.redo_stack = [];
	                        }
	                        var _fill_erase = mouse_check_button_pressed(mb_right);
	                        var _fill_col, _fill_mask;
	                        if (!_fill_erase) {
	                            _fill_col  = _asset.meta.active_color;
	                            _fill_mask = 1;
	                        } else if (_bmp_is_hires) {
	                            // HiRes RMB fill: paints the protected secondary colour, not an erase.
	                            _fill_col  = _asset.meta.secondary_color;
	                            _fill_mask = 1;
	                        } else {
	                            _fill_col  = _asset.meta.bg_col;
	                            _fill_mask = 0;
	                        }
	                        var _fill_px    = (_raw_px div _bmp_step) * _bmp_step;
	                        scr_asset_bmp_flood_fill(_asset, _fill_px, _raw_py, _fill_col, _fill_mask, !_fill_erase);
	                        _asset.meta.needs_clash_check = true;
							_asset.meta.pixels_dirty = true;
							_asset.meta.bmp_unsaved = true;
	                    } else if ((mouse_check_button_pressed(mb_left) || mouse_check_button_pressed(mb_right)) && _asset.meta.active_tool == "GRADIENT") {
	                        // Press sets the flood seed AND the gradient line's first point.
	                        // Either button starts the drag — direction is always col1->col2.
	                        _asset.meta.gradient_x1      = (_raw_px div _bmp_step) * _bmp_step;
	                        _asset.meta.gradient_y1      = _raw_py;
	                        _asset.meta.gradient_drawing = true;
	                        _asset.meta.gradient_btn     = mouse_check_button_pressed(mb_left) ? mb_left : mb_right;
	                        // Push pre-gradient snapshot in new struct format
	                        if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
	                            var _grad_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                            buffer_get_surface(_grad_buf, _asset.meta.preview_surf, 0);
	                            var _grad_mask_snap = array_create(64000, 0);
	                            array_copy(_grad_mask_snap, 0, _asset.meta.bg_mask, 0, 64000);
	                            var _grad_entry = { buf: _grad_buf, mask: _grad_mask_snap, bg_col: _asset.meta.bg_col };
	                            array_push(_asset.meta.undo_stack, _grad_entry);
	                            if (array_length(_asset.meta.undo_stack) > 25) {
	                                var _gdrop0 = _asset.meta.undo_stack[0];
	                                if (is_struct(_gdrop0) && buffer_exists(_gdrop0.buf)) {
	                                    buffer_delete(_gdrop0.buf);
	                                } else if (buffer_exists(_gdrop0)) {
	                                    buffer_delete(_gdrop0);
	                                }
	                                array_delete(_asset.meta.undo_stack, 0, 1);
	                            }
	                            _asset.meta.redo_stack = [];
	                        }
	                    }
	                }

	                // ── GRADIENT RELEASE (fires even if the cursor has left the canvas) ──
	                // Flood-fills the region matching the seed pixel's colour, then paints
	                // each pixel col1/col2 by an 8x8 Bayer threshold against how far that
	                // pixel projects onto the drawn line — a directional dithered gradient,
	                // same approach as the Amiga Dev Machine bitmap editor's GRADIENT tool.
	                if (_asset.meta.active_tool == "GRADIENT"
	                &&  _asset.meta.gradient_drawing
	                &&  (mouse_check_button_released(mb_left) || mouse_check_button_released(mb_right))) {
	                    // Fixed direction: always col1 (seed end) -> col2 (drag end),
	                    // regardless of which button was used to drag. CUSTOM
	                    // overrides both with the 12-slot stop run when active.
	                    var _grad_col_a = _asset.meta.active_color;    // col1
	                    var _grad_col_b = _asset.meta.secondary_color; // col2
	                    var _grad_stops = _asset.meta.gradient_custom_active ? _asset.meta.gradient_custom_cols : undefined;
	                    var _grad_x2 = (_raw_px div _bmp_step) * _bmp_step;
	                    var _grad_y2 = _raw_py;
	                    scr_asset_bmp_gradient_fill(_asset, _asset.meta.gradient_x1, _asset.meta.gradient_y1, _grad_x2, _grad_y2, _grad_col_a, _grad_col_b, _grad_stops);
	                    _asset.meta.gradient_drawing = false;
	                    _asset.meta.gradient_x1      = -1;
	                    _asset.meta.needs_clash_check = true;
	                    _asset.meta.pixels_dirty = true;
	                    _asset.meta.bmp_unsaved = true;
	                    if (surface_exists(_asset.meta.preview_overlay)) { surface_free(_asset.meta.preview_overlay); _asset.meta.preview_overlay = -1; }
	                }

	                // ── SHAPE RELEASE (fires even if the cursor has left the canvas) ──
	                // _raw_px/_raw_py stay clamped to 0..319 / 0..199 regardless of where
	                // the mouse actually is, so releasing outside the bitmap still commits
	                // the shape using the clamped edge coordinate.
	                if (_asset.meta.active_tool == "LINE"
	                &&  _asset.meta.line_x1 >= 0
	                &&  (mouse_check_button_released(mb_left) || mouse_check_button_released(mb_right))) {
	                    var _paint_col, _mask_val;
	                    if (_asset.meta.line_btn == mb_left) {
	                        _paint_col = _asset.meta.active_color;
	                        _mask_val  = 1;
	                    } else if (_bmp_is_hires) {
	                        _paint_col = _asset.meta.secondary_color;
	                        _mask_val  = 1;
	                    } else {
	                        _paint_col = _asset.meta.bg_col;
	                        _mask_val  = 0;
	                    }
	                    var _lx1 = _asset.meta.line_x1, _ly1 = _asset.meta.line_y1;
	                    var _lx2 = (_raw_px div _bmp_step) * _bmp_step, _ly2 = _raw_py;
	                    scr_asset_bmp_draw_line(_asset, _lx1, _ly1, _lx2, _ly2, _paint_col, _mask_val, undefined, (_asset.meta.line_btn == mb_left));
	                    _asset.meta.line_x1 = -1;
	                    _asset.meta.needs_clash_check = true;
	                    _asset.meta.pixels_dirty = true;
	                    _asset.meta.bmp_unsaved = true;
	                    if (surface_exists(_asset.meta.preview_overlay)) { surface_free(_asset.meta.preview_overlay); _asset.meta.preview_overlay = -1; }
	                }

	                if ((_asset.meta.active_tool == "RECT" || _asset.meta.active_tool == "CIRCLE")
	                &&  _asset.meta.shape_drawing
	                &&  (mouse_check_button_released(mb_left) || mouse_check_button_released(mb_right))) {
	                    var _paint_col, _mask_val;
	                    if (_asset.meta.shape_btn == mb_left) {
	                        _paint_col = _asset.meta.active_color;
	                        _mask_val  = 1;
	                    } else if (_bmp_is_hires) {
	                        _paint_col = _asset.meta.secondary_color;
	                        _mask_val  = 1;
	                    } else {
	                        _paint_col = _asset.meta.bg_col;
	                        _mask_val  = 0;
	                    }
	                    var _rx1 = min(_asset.meta.shape_x1, (_raw_px div _bmp_step) * _bmp_step);
	                    var _ry1 = min(_asset.meta.shape_y1, _raw_py);
	                    var _rx2 = max(_asset.meta.shape_x1, (_raw_px div _bmp_step) * _bmp_step);
	                    var _ry2 = max(_asset.meta.shape_y1, _raw_py);
	                    _rx1 = (_rx1 div _bmp_step) * _bmp_step;
	                    _rx2 = (_rx2 div _bmp_step) * _bmp_step;
	                    if (_asset.meta.active_tool == "RECT")
	                        scr_asset_bmp_draw_rect(_asset, _rx1, _ry1, _rx2, _ry2, _paint_col, _mask_val, _asset.meta.fill_toggle, undefined, (_asset.meta.shape_btn == mb_left));
	                    else
	                        scr_asset_bmp_draw_ellipse(_asset, _rx1, _ry1, _rx2, _ry2, _paint_col, _mask_val, _asset.meta.fill_toggle, undefined, (_asset.meta.shape_btn == mb_left));
	                    _asset.meta.shape_drawing = false;
	                    _asset.meta.needs_clash_check = true;
	                    _asset.meta.pixels_dirty = true;
	                    _asset.meta.bmp_unsaved = true;
	                    if (surface_exists(_asset.meta.preview_overlay)) { surface_free(_asset.meta.preview_overlay); _asset.meta.preview_overlay = -1; }
	                }

                    
	                if (!_is_left && !_is_right) {
	                    _asset.meta.last_px = undefined;
	                    _asset.meta.last_py = undefined;
	                }

	                // --- DRAWING THE UI OVERLAYS ---
// PIXEL-ACCURATE OVERLAY PREVIEW for LINE / RECT / CIRCLE
	                // Rebuild the overlay surface each frame during drag
	                var _need_overlay = false;
	                if (_asset.meta.active_tool == "LINE" && _asset.meta.line_x1 >= 0) _need_overlay = true;
	                if ((_asset.meta.active_tool == "RECT" || _asset.meta.active_tool == "CIRCLE") && _asset.meta.shape_drawing) _need_overlay = true;
	                if (_asset.meta.active_tool == "GRADIENT" && _asset.meta.gradient_drawing) _need_overlay = true;
                    
	                if (_need_overlay) {
	                    // Rebuild overlay surface at canvas resolution (320x200)
	                    if (!surface_exists(_asset.meta.preview_overlay)) {
	                        _asset.meta.preview_overlay = surface_create(320, 200);
	                        _asset.meta.overlay_dirty = true; // force first draw
	                    }
	                    // Only redraw overlay when mouse moves (saves ~0.3ms/frame during static drag)
	                    var _omx = variable_struct_exists(_asset.meta, "_ov_last_mx") ? _asset.meta._ov_last_mx : -1;
	                    var _omy = variable_struct_exists(_asset.meta, "_ov_last_my") ? _asset.meta._ov_last_my : -1;
	                    var _overlay_needs_redraw = (_omx != _raw_px || _omy != _raw_py);
	                    _asset.meta._ov_last_mx = _raw_px;
	                    _asset.meta._ov_last_my = _raw_py;
	                    if (!_overlay_needs_redraw) {
	                        // just blit the cached overlay — skip the expensive rebuild below
	                        // (jump to the draw section — GML has no continue for if-blocks so we use a flag)
	                    }
	                    if (_overlay_needs_redraw) {
	                    surface_set_target(_asset.meta.preview_overlay);
	                    draw_clear_alpha(c_black, 0); // fully transparent
	                    gpu_set_texfilter(false);
                        
	                    var _ov_active_btn = (_asset.meta.active_tool == "LINE") ? _asset.meta.line_btn : _asset.meta.shape_btn;
	                    var _prev_col;
	                    if (_ov_active_btn == mb_left) {
	                        _prev_col = _asset.meta.active_color;
	                    } else if (_bmp_is_hires) {
	                        _prev_col = _asset.meta.secondary_color;
	                    } else {
	                        _prev_col = _asset.meta.bg_col;
	                    }
	                    var _ov_col   = scr_c64_pepto_colour(_prev_col);
	                    var _ov_r = color_get_red(_ov_col);
	                    var _ov_g = color_get_green(_ov_col);
	                    var _ov_b = color_get_blue(_ov_col);
                        
// Cache dither state once for all overlay pixel writes
	                    var _ov_dmode = _asset.meta.dither_mode;
	                    var _ov_dinv  = _asset.meta.dither_invert;
                        
	                    if (_asset.meta.active_tool == "LINE" && _asset.meta.line_x1 >= 0) {
                        var _ov_max_x = _bmp_is_hires ? 319 : 318;
                        var _lx1o = _asset.meta.line_x1, _ly1o = _asset.meta.line_y1;
                        var _lx2o = (_raw_px div _bmp_step) * _bmp_step, _ly2o = _raw_py;
                        var _dx_mc = abs((_lx2o div _bmp_step) - (_lx1o div _bmp_step));
                        var _dy_o  = abs(_ly2o - _ly1o);
                        var _sx_o  = (_lx1o < _lx2o) ? _bmp_step : -_bmp_step;
                        var _sy_o  = (_ly1o < _ly2o) ? 1 : -1;
                        var _err_o = _dx_mc - _dy_o;
                        var _cx_o  = (_lx1o div _bmp_step) * _bmp_step;
                        var _cy_o  = _ly1o;
                        var _ex_o  = (_lx2o div _bmp_step) * _bmp_step;
                        var _ov_brad = _asset.meta.brush_size;
                        for (var _ls = 0; _ls < 640; _ls++) {
                            if (_ov_brad == 0) {
                                // Single pixel (HiRes) or MC pixel pair — thin line
                                if (_cx_o >= 0 && _cx_o <= _ov_max_x && _cy_o >= 0 && _cy_o < 200) {
                                    var _ov_px = _cx_o; var _ov_py = _cy_o;
                                    var _ov_ok = (_ov_dmode == "NONE") ? true : (((_ov_px >= 0 && _ov_px < 320 && _ov_py >= 0 && _ov_py < 200) && array_length(_dither_cache) > 1) ? _dither_cache[_ov_py * 320 + _ov_px] : scr_check_dither_mask(_ov_dmode, _ov_px, _ov_py, _bmp_is_hires));
                                    if (_ov_ok) {
                                        draw_set_color(make_color_rgb(_ov_r, _ov_g, _ov_b));
                                        if (_bmp_is_hires) {
                                            draw_rectangle(_cx_o, _cy_o, _cx_o + 1, _cy_o + 1, false);
                                        } else {
                                            draw_rectangle(_cx_o, _cy_o, _cx_o + 2, _cy_o + 1, false);
                                        }
                                    }
                                }
                            } else {
                                // Brush-thickness preview — same circle stamp scr_asset_bmp_draw_line
                                // uses at commit time, so what you see while dragging is what lands.
                                for (var _bmy_o = -_ov_brad; _bmy_o <= _ov_brad; _bmy_o++) {
                                    for (var _bmx_o = -_ov_brad; _bmx_o <= _ov_brad; _bmx_o++) {
                                        var _ndx_o = _bmp_is_hires ? (_bmx_o / _ov_brad) : ((_bmx_o * 2) / _ov_brad);
                                        var _ndy_o = _bmy_o / _ov_brad;
                                        if (_ndx_o * _ndx_o + _ndy_o * _ndy_o > 1.0) continue;
                                        var _tx_o = ((_cx_o + _bmx_o * _bmp_step) div _bmp_step) * _bmp_step;
                                        var _ty_o = _cy_o + _bmy_o;
                                        if (_tx_o < 0 || _tx_o > _ov_max_x || _ty_o < 0 || _ty_o >= 200) continue;
                                        var _ov_ok = (_ov_dmode == "NONE") ? true : (((_tx_o >= 0 && _tx_o < 320 && _ty_o >= 0 && _ty_o < 200) && array_length(_dither_cache) > 1) ? _dither_cache[_ty_o * 320 + _tx_o] : scr_check_dither_mask(_ov_dmode, _tx_o, _ty_o, _bmp_is_hires));
                                        if (_ov_ok) {
                                            draw_set_color(make_color_rgb(_ov_r, _ov_g, _ov_b));
                                            if (_bmp_is_hires) {
                                                draw_rectangle(_tx_o, _ty_o, _tx_o + 1, _ty_o + 1, false);
                                            } else {
                                                draw_rectangle(_tx_o, _ty_o, _tx_o + 2, _ty_o + 1, false);
                                            }
                                        }
                                    }
                                }
                            }
                            if (_cx_o == _ex_o && _cy_o == _ly2o) break;
                            var _e2_o = 2 * _err_o;
							
                            if (_e2_o > -_dy_o) { _err_o -= _dy_o; _cx_o += _sx_o; }
                            if (_e2_o <  _dx_mc) { _err_o += _dx_mc; _cy_o += _sy_o; }
                        }
                    }
                        
	                    if ((_asset.meta.active_tool == "RECT" || _asset.meta.active_tool == "CIRCLE") && _asset.meta.shape_drawing) {
	                        var _ov_max_x = _bmp_is_hires ? 319 : 318;
	                        var _rx1o = min(_asset.meta.shape_x1, (_raw_px div _bmp_step) * _bmp_step);
	                        var _ry1o = min(_asset.meta.shape_y1, _raw_py);
	                        var _rx2o = max(_asset.meta.shape_x1, (_raw_px div _bmp_step) * _bmp_step);
	                        var _ry2o = max(_asset.meta.shape_y1, _raw_py);
	                        _rx1o = (_rx1o div _bmp_step) * _bmp_step;
	                        _rx2o = (_rx2o div _bmp_step) * _bmp_step;
	                        draw_set_color(make_color_rgb(_ov_r, _ov_g, _ov_b));
	                        if (_asset.meta.active_tool == "RECT") {
	                            for (var _ry_o = _ry1o; _ry_o <= _ry2o; _ry_o++) {
	                                for (var _rx_o = _rx1o; _rx_o <= _rx2o; _rx_o += _bmp_step) {
	                                    var _on_edge = _bmp_is_hires
	                                        ? (_rx_o == _rx1o || _rx_o == _rx2o || _ry_o == _ry1o || _ry_o == _ry2o)
	                                        : (_rx_o == _rx1o || _rx_o >= _rx2o - 1 || _ry_o == _ry1o || _ry_o == _ry2o);
	                                    if (_asset.meta.fill_toggle || _on_edge) {
	                                        if (_rx_o >= 0 && _rx_o <= _ov_max_x && _ry_o >= 0 && _ry_o < 200) {
	                                            var _ov_px = _rx_o; var _ov_py = _ry_o;
	                                            var _ov_ok = (_ov_dmode == "NONE") ? true : (((_ov_px >= 0 && _ov_px < 320 && _ov_py >= 0 && _ov_py < 200) && array_length(_dither_cache) > 1) ? _dither_cache[_ov_py * 320 + _ov_px] : scr_check_dither_mask(_ov_dmode, _ov_px, _ov_py, _bmp_is_hires));
	                                            if (_ov_ok) {
	                                                if (_bmp_is_hires) {
	                                                    draw_rectangle(_rx_o, _ry_o, _rx_o + 1, _ry_o + 1, false);
	                                                } else {
	                                                    draw_rectangle(_rx_o, _ry_o, _rx_o + 2, _ry_o + 1, false);
	                                                }
	                                            }
	                                        }
	                                    }
	                                }
	                            }
	                        } else {
	                            // Ellipse — midpoint, in MC or HiRes units per _bmp_step
	                            var _ecx_o = (_rx1o + _rx2o) / 2;
	                            var _ecy_o = (_ry1o + _ry2o) / 2;
	                            var _erx_o = _bmp_is_hires ? max(1, (_rx2o - _rx1o) / 2) : max(1, (_rx2o - _rx1o) / 4);
	                            var _ery_o = max(1, (_ry2o - _ry1o) / 2);
	                            if (_asset.meta.fill_toggle) {
	                                for (var _efy = -_ery_o; _efy <= _ery_o; _efy++) {
	                                    var _row_rx_o = floor(sqrt(max(0, 1 - (_efy * _efy) / (_ery_o * _ery_o))) * _erx_o);
	                                    for (var _efx = -_row_rx_o; _efx <= _row_rx_o; _efx++) {
	                                        var _epx_o = floor(_ecx_o + _efx * _bmp_step);
	                                        var _epy_o = floor(_ecy_o + _efy);
	                                        var _esx_o = (_epx_o div _bmp_step) * _bmp_step;
	                                        if (_esx_o >= 0 && _esx_o <= _ov_max_x && _epy_o >= 0 && _epy_o < 200) {
	                                            var _ov_px = _esx_o; var _ov_py = _epy_o;
	                                            var _ov_ok = (_ov_dmode == "NONE") ? true : (((_ov_px >= 0 && _ov_px < 320 && _ov_py >= 0 && _ov_py < 200) && array_length(_dither_cache) > 1) ? _dither_cache[_ov_py * 320 + _ov_px] : scr_check_dither_mask(_ov_dmode, _ov_px, _ov_py, _bmp_is_hires));
	                                            if (_ov_ok) {
	                                                if (_bmp_is_hires) {
	                                                    draw_rectangle(_esx_o, _epy_o, _esx_o + 1, _epy_o + 1, false);
	                                                } else {
	                                                    draw_rectangle(_esx_o, _epy_o, _esx_o + 2, _epy_o + 1, false);
	                                                }
	                                            }
	                                        }
	                                    }
	                                }
	                            } else {
	                                var _epx2 = 0; var _epy2 = _ery_o;
	                                var _ep1 = (_ery_o*_ery_o) - (_erx_o*_erx_o*_ery_o) + (0.25*_erx_o*_erx_o);
	                                var _edx2 = 2*_ery_o*_ery_o*_epx2; var _edy2 = 2*_erx_o*_erx_o*_epy2;
	                                var _epts = [];
	                                while (_edx2 < _edy2) {
	                                    array_push(_epts, [floor(_ecx_o+_epx2*_bmp_step),floor(_ecy_o+_epy2)]);
	                                    array_push(_epts, [floor(_ecx_o-_epx2*_bmp_step),floor(_ecy_o+_epy2)]);
	                                    array_push(_epts, [floor(_ecx_o+_epx2*_bmp_step),floor(_ecy_o-_epy2)]);
	                                    array_push(_epts, [floor(_ecx_o-_epx2*_bmp_step),floor(_ecy_o-_epy2)]);
	                                    _epx2++; _edx2 += 2*_ery_o*_ery_o;
	                                    if (_ep1 < 0) { _ep1 += _edx2 + _ery_o*_ery_o; }
	                                    else { _epy2--; _edy2 -= 2*_erx_o*_erx_o; _ep1 += _edx2 - _edy2 + _ery_o*_ery_o; }
	                                }
	                                var _ep2 = _ery_o*_ery_o*(_epx2+0.5)*(_epx2+0.5)+_erx_o*_erx_o*(_epy2-1)*(_epy2-1)-_erx_o*_erx_o*_ery_o*_ery_o;
	                                while (_epy2 >= 0) {
	                                    array_push(_epts, [floor(_ecx_o+_epx2*_bmp_step),floor(_ecy_o+_epy2)]);
	                                    array_push(_epts, [floor(_ecx_o-_epx2*_bmp_step),floor(_ecy_o+_epy2)]);
	                                    array_push(_epts, [floor(_ecx_o+_epx2*_bmp_step),floor(_ecy_o-_epy2)]);
	                                    array_push(_epts, [floor(_ecx_o-_epx2*_bmp_step),floor(_ecy_o-_epy2)]);
	                                    _epy2--; _edy2 -= 2*_erx_o*_erx_o;
	                                    if (_ep2 > 0) { _ep2 += _erx_o*_erx_o - _edy2; }
	                                    else { _epx2++; _edx2 += 2*_ery_o*_ery_o; _ep2 += _edx2 - _edy2 + _erx_o*_erx_o; }
	                                }
	                                for (var _epi = 0; _epi < array_length(_epts); _epi++) {
	                                    var _esx_o = (_epts[_epi][0] div _bmp_step) * _bmp_step;
	                                    var _esy_o = _epts[_epi][1];
	                                    if (_esx_o >= 0 && _esx_o <= _ov_max_x && _esy_o >= 0 && _esy_o < 200) {
	                                        var _ov_px = _esx_o; var _ov_py = _esy_o;
	                                        var _ov_ok = (_ov_dmode == "NONE") ? true : (((_ov_px >= 0 && _ov_px < 320 && _ov_py >= 0 && _ov_py < 200) && array_length(_dither_cache) > 1) ? _dither_cache[_ov_py * 320 + _ov_px] : scr_check_dither_mask(_ov_dmode, _ov_px, _ov_py, _bmp_is_hires));
	                                        if (_ov_ok) {
	                                            if (_bmp_is_hires) {
	                                                draw_rectangle(_esx_o, _esy_o, _esx_o + 1, _esy_o + 1, false);
	                                            } else {
	                                                draw_rectangle(_esx_o, _esy_o, _esx_o + 2, _esy_o + 1, false);
	                                            }
	                                        }
	                                    }
	                                }
	                            }
	                        }
	                    }
                        
	                    if (_asset.meta.active_tool == "GRADIENT" && _asset.meta.gradient_drawing) {
	                        // Lightweight direction indicator only (not a pixel-accurate
	                        // brush stamp) — a thin line from seed to current endpoint,
	                        // plus a small marker at each end, same idea as the Amiga
	                        // Dev Machine bitmap editor's gradient-line preview.
	                        var _gx1o = _asset.meta.gradient_x1, _gy1o = _asset.meta.gradient_y1;
	                        var _gx2o = (_raw_px div _bmp_step) * _bmp_step, _gy2o = _raw_py;
	                        draw_set_color(c_white);
	                        draw_line(_gx1o, _gy1o, _gx2o, _gy2o);
	                        draw_rectangle(_gx1o - 1, _gy1o - 1, _gx1o + 1, _gy1o + 1, false);
	                        draw_rectangle(_gx2o - 1, _gy2o - 1, _gx2o + 1, _gy2o + 1, true);
	                    }

	                    surface_reset_target();
						}
                        
	                    // Now draw the overlay on top of the canvas at screen scale
	                    var _ov_sx_scale = window_get_width()  / _gui_w;
	                    var _ov_sy_scale = window_get_height() / display_get_gui_height();
	                    gpu_set_scissor(
	                        floor(_sx * _ov_sx_scale), floor(_sy * _ov_sy_scale),
	                        ceil(_sw * _ov_sx_scale),  ceil(_sh * _ov_sy_scale)
	                    );
	                    gpu_set_texfilter(false);
	                   // draw_set_alpha(0.85);
	                    if (_z <= bmp_ui_zoom_cap) {
	                        draw_surface_stretched(_asset.meta.preview_overlay, _sx, _sy, _sw, _sh);
	                    } else {
	                        var _ov_src_w = max(1, 320 / (_z / bmp_ui_zoom_cap));
	                        var _ov_src_h = max(1, 200 / (_z / bmp_ui_zoom_cap));
	                        var _ov_src_x = clamp(_asset.meta.bmp_pan_x, 0, 320 - _ov_src_w);
	                        var _ov_src_y = clamp(_asset.meta.bmp_pan_y, 0, 200 - _ov_src_h);
	                        draw_surface_part_ext(_asset.meta.preview_overlay,
	                            _ov_src_x, _ov_src_y, _ov_src_w, _ov_src_h,
	                            _sx, _sy, _sw / _ov_src_w, _sh / _ov_src_h,
	                            c_white, 0.85);
	                    }
	                    draw_set_alpha(1.0);
	                    gpu_set_scissor(0, 0, window_get_width(), window_get_height());
                        
	                } else {
	                    // No active shape drag — free overlay to save VRAM
	                    if (surface_exists(_asset.meta.preview_overlay)) {
	                        surface_free(_asset.meta.preview_overlay);
	                        _asset.meta.preview_overlay = -1;
	                    }
	                }
                    
	                // Draw Active Grab Box Marquee
	                if (_asset.meta.active_tool == "GRAB" && _asset.meta.is_grabbing) {
	                    var _gx1 = floor(min(_asset.meta.grab_x1, _raw_px)) + _asset.meta.grab_off_x1;
	                            var _gy1 = floor(min(_asset.meta.grab_y1, _raw_py)) + _asset.meta.grab_off_y1;
	                            var _gx2 = floor(max(_asset.meta.grab_x1, _raw_px)) + _asset.meta.grab_off_x2;
	                            var _gy2 = floor(max(_asset.meta.grab_y1, _raw_py)) + _asset.meta.grab_off_y2;;
                                
						_gx1 = (_gx1 div 2) * 2;
	                    _gx2 = (_gx2 div 2) * 2 + 1; // Last pixel of MC pair — matches capture snap

					    var _screen_x1 = 0, _screen_y1 = 0, _screen_x2 = 0, _screen_y2 = 0;
	                    if (_z <= bmp_ui_zoom_cap) {
	                        var _cell_w = _sw / 320;
	                        var _cell_h = _sh / 200;
	                        _screen_x1 = _sx + (_gx1 * _cell_w);
	                        _screen_y1 = _sy + (_gy1 * _cell_h);
	                        _screen_x2 = _sx + ((_gx2 + 1) * _cell_w);
	                        _screen_y2 = _sy + ((_gy2 + 1) * _cell_h);
	                    } else {
	                        _screen_x1 = _sx + ((_gx1 - _src_x2) / _src_w2 * _sw);
	                        _screen_y1 = _sy + ((_gy1 - _src_y2) / _src_h2 * _sh);
	                        _screen_x2 = _sx + (((_gx2 + 1) - _src_x2) / _src_w2 * _sw);
	                        _screen_y2 = _sy + (((_gy2 + 1) - _src_y2) / _src_h2 * _sh);
	                    }
                        
	                    draw_set_color(c_red);
	                    draw_rectangle(_screen_x1, _screen_y1, _screen_x2, _screen_y2, true);
	                    draw_set_color(c_white);
	                    draw_set_alpha(0.5);
	                    draw_rectangle(_screen_x1, _screen_y1, _screen_x2, _screen_y2, true);
	                    draw_set_alpha(1.0);
	                }
                    
// COLOR PICKER (Eye-dropper)
if (_in_bounds && keyboard_check(vk_alt) && !_png_mode) {
	if (mouse_check_button_pressed(mb_left)) {
	    if (_bmp_is_hires) {
	        // A HiRes character cell owns a two-colour pair. Pick the roles,
	        // rather than just the RGB beneath the cursor, so the palette UI
	        // and the next LMB/RMB strokes accurately show FG and BG.
	        var _pick_cell = ((_raw_py div 8) * 40) + (_raw_px div 8);
	        _asset.meta.active_color    = _asset.meta.hr_cell_fg_col[_pick_cell];
	        _asset.meta.secondary_color = _asset.meta.hr_cell_bg_col[_pick_cell];
	    } else {
	        var _pick_rgb = surface_getpixel(_asset.meta.preview_surf, _raw_px, _raw_py);
	        // Loop through the 16 C64 colours to find the match.
	        for (var _i = 0; _i < 16; _i++) {
	            if (_pick_rgb == scr_c64_pepto_colour(_i)) {
	                _asset.meta.active_color = _i;
	                break;
	            }
	        }
	    }
	}
}

// Draw cursor preview (Hidden if Alt is held for picking)
draw_set_alpha(1.0);
if (!variable_struct_exists(_asset.meta, "active_color")) _asset.meta.active_color = 1;
if (_in_bounds && !keyboard_check(vk_alt) && !_png_mode) {
	var _cur_snap_px = (_raw_px div _bmp_step) * _bmp_step;
	var _cur_snap_py = _raw_py;
	var _scale_x_cur = (_z <= bmp_ui_zoom_cap) ? (_sw / 320) : (_sw / _src_w2);
	var _scale_y_cur = (_z <= bmp_ui_zoom_cap) ? (_sh / 200) : (_sh / _src_h2);
	var _cur_sx, _cur_sy;
	if (_z <= bmp_ui_zoom_cap) {
	    _cur_sx = floor(_sx + (_cur_snap_px * _scale_x_cur));
	    _cur_sy = floor(_sy + (_cur_snap_py * _scale_y_cur));
	} else {
	    _cur_sx = floor(_sx + ((_cur_snap_px - _src_x2) / _src_w2 * _sw));
	    _cur_sy = floor(_sy + ((_cur_snap_py - _src_y2) / _src_h2 * _sh));
	}
	var _bsz_screen_x = _scale_x_cur * _asset.meta.brush_size;
	var _bsz_screen_y = _scale_y_cur * _asset.meta.brush_size;
	draw_set_color(c_white);
	//draw_set_alpha(0.6);
if (_asset.meta.active_tool == "DRAW" && !surface_exists(_asset.meta.grab_surf)) {
	    var _bsz  = _asset.meta.brush_size;
	    var _brad = max(0, _bsz);
	    var _pxw  = _bmp_is_hires ? max(1, _scale_x_cur) : max(1, _scale_x_cur * 2); // MC pixel = 2 canvas px wide; HiRes = 1
	    var _pxh  = max(1, _scale_y_cur);      // one canvas px tall
	    var _bcx  = _cur_snap_px;
	    var _bcy  = _cur_snap_py;
	    draw_set_color(scr_c64_pepto_colour(_asset.meta.active_color));
	    //draw_set_alpha(0.8);
	    if (_brad == 0) {
	        // Single pixel (HiRes) or 2x1 MC pixel
	        var _spx = 0, _spy = 0;
	        if (_z <= bmp_ui_zoom_cap) {
	            _spx = floor(_sx + (_bcx * _scale_x_cur));
	            _spy = floor(_sy + (_bcy * _scale_y_cur));
	        } else {
	            _spx = floor(_sx + ((_bcx - _src_x2) / _src_w2 * _sw));
	            _spy = floor(_sy + ((_bcy - _src_y2) / _src_h2 * _sh));
	        }
	        draw_rectangle(_spx, _spy, _spx + _pxw - 1, _spy + _pxh - 1, false);
	    } else {
	        for (var _bpy = -_brad; _bpy <= _brad; _bpy++) {
	            for (var _bpx = -_brad; _bpx <= _brad; _bpx++) {
	                // MC pixels are 2:1 aspect (double X to normalize); HiRes is square.
	                var _dx = _bmp_is_hires ? (_bpx / _brad) : ((_bpx * 2) / _brad);
	                var _dy = _bpy / _brad;
	                if (_dx * _dx + _dy * _dy > 1.0) continue;
	                var _wpx = ((_bcx + _bpx * _bmp_step) div _bmp_step) * _bmp_step;
	                var _wpy = _bcy + _bpy;
	                var _spx = 0, _spy = 0;
	                if (_z <= bmp_ui_zoom_cap) {
	                    _spx = floor(_sx + (_wpx * _scale_x_cur));
	                    _spy = floor(_sy + (_wpy * _scale_y_cur));
	                } else {
	                    _spx = floor(_sx + ((_wpx - _src_x2) / _src_w2 * _sw));
	                    _spy = floor(_sy + ((_wpy - _src_y2) / _src_h2 * _sh));
	                }
	                draw_rectangle(_spx, _spy, _spx + _pxw - 1, _spy + _pxh - 1, false);
	            }
	        }
	    }
	    draw_set_alpha(1.0);
	}

	if (_asset.meta.active_tool == "LINE" && _asset.meta.line_x1 < 0) {
	    // No anchor placed yet — show a hollow box at the cursor so the user
	    // can see where the first LINE click will land, same as DRAW's cursor
	    // preview but outlined rather than filled to distinguish "not yet
	    // committed" from an actual brush stamp.
	    var _lpxw = _bmp_is_hires ? max(1, _scale_x_cur) : max(1, _scale_x_cur * 2);
	    var _lpxh = max(1, _scale_y_cur);
	    var _lspx = 0, _lspy = 0;
	    if (_z <= bmp_ui_zoom_cap) {
	        _lspx = floor(_sx + (_cur_snap_px * _scale_x_cur));
	        _lspy = floor(_sy + (_cur_snap_py * _scale_y_cur));
	    } else {
	        _lspx = floor(_sx + ((_cur_snap_px - _src_x2) / _src_w2 * _sw));
	        _lspy = floor(_sy + ((_cur_snap_py - _src_y2) / _src_h2 * _sh));
	    }
	    draw_set_color(scr_c64_pepto_colour(_asset.meta.active_color));
	    draw_rectangle(_lspx, _lspy, _lspx + _lpxw - 1, _lspy + _lpxh - 1, true);
	}
}

// Draw Grab Stamp Preview (If holding one)
// Added !keyboard_check(vk_alt) to hide the stamp while color picking
if (_asset.meta.active_tool == "DRAW" && surface_exists(_asset.meta.grab_surf) && _in_bounds && !keyboard_check(vk_alt) && !_png_mode) {
	                    var _screen_x = 0, _screen_y = 0;
	                    // Snap to MC pixel boundary (even x) then snap screen position to whole pixels
	                    var _snap_px = (_raw_px div _bmp_step) * _bmp_step;
	                    var _snap_py = _raw_py;
                        
	                    // Anchor must also be step-snapped so grab_cx aligns with placement.
	                    // Use -_bmp_step to match the placement path; keeping preview and
	                    // placement identical removes any 1px visual drift.
	                    var _flip_bias = (!_bmp_is_hires && _asset.meta.grab_flip_x) ? -1 : 0; // MC mirror half-pair compensation
	                    var _draw_x = _snap_px - _asset.meta.grab_cx - _bmp_step + _flip_bias;
	                    _draw_x = ((_draw_x div _bmp_step) * _bmp_step) - _flip_bias;
	                    var _draw_y = _snap_py - _asset.meta.grab_cy;
                        
	                    var _scale_x = (_z <= bmp_ui_zoom_cap) ? (_sw / 320) : (_sw / _src_w2);
	                    var _scale_y = (_z <= bmp_ui_zoom_cap) ? (_sh / 200) : (_sh / _src_h2);
                        
	                    if (_z <= bmp_ui_zoom_cap) {
	                        // Floor to whole screen pixels to prevent sub-pixel filtering
	                        _screen_x = floor(_sx + (_draw_x * _scale_x));
	                        _screen_y = floor(_sy + (_draw_y * _scale_y));
	                    } else {
	                        _screen_x = floor(_sx + ((_draw_x - _src_x2) / _src_w2 * _sw));
	                        _screen_y = floor(_sy + ((_draw_y - _src_y2) / _src_h2 * _sh));
	                    }
	                    // Also snap scale_x so each stamp pixel lands on exact screen pixel multiples
	                    var _scale_x = floor(_scale_x * _asset.meta.grab_w) / _asset.meta.grab_w;
	                    var _scale_y = floor(_scale_y * _asset.meta.grab_h) / _asset.meta.grab_h;
                        
gpu_set_texfilter(false);
	                    if (_asset.meta.dither_mode == "NONE") {
	                        draw_surface_ext(_asset.meta.grab_surf, _screen_x, _screen_y, _scale_x, _scale_y, 0, c_white, 1.0);
	                    } else {
	                        // Draw stamp pixel-by-pixel respecting dither mask
	                        var _gdmode = _asset.meta.dither_mode;
	                        var _gdinv  = _asset.meta.dither_invert;
	                        var _gpxw   = max(1, _scale_x);
	                        var _gpxh   = max(1, _scale_y);
	                        var _buf_prev = buffer_create(_asset.meta.grab_w * _asset.meta.grab_h * 4, buffer_fixed, 1);
	                        buffer_get_surface(_buf_prev, _asset.meta.grab_surf, 0);
	                        for (var _gpy = 0; _gpy < _asset.meta.grab_h; _gpy++) {
	                            for (var _gpx = 0; _gpx < _asset.meta.grab_w; _gpx += 2) {
	                                var _gidx = (_gpy * _asset.meta.grab_w + _gpx) * 4;
	                                var _ga   = buffer_peek(_buf_prev, _gidx + 3, buffer_u8);
	                                if (_ga == 0) continue; // transparent — skip
	                                // World canvas position of this stamp pixel
	                                var _gwx = _draw_x + _gpx;
	                                var _gwy = _draw_y + _gpy;
	                                var _gok = ((_gwx >= 0 && _gwx < 320 && _gwy >= 0 && _gwy < 200) && array_length(_dither_cache) > 1)
		                                        ? _dither_cache[_gwy * 320 + _gwx]
		                                        : scr_check_dither_mask(_gdmode, _gwx, _gwy, _bmp_is_hires);
		                            if (!_gok) continue;
	                                var _gr = buffer_peek(_buf_prev, _gidx,     buffer_u8);
	                                var _gg = buffer_peek(_buf_prev, _gidx + 1, buffer_u8);
	                                var _gb = buffer_peek(_buf_prev, _gidx + 2, buffer_u8);
	                                draw_set_color(make_color_rgb(_gr, _gg, _gb));
	                                var _gsx = floor(_screen_x + _gpx * _scale_x);
	                                var _gsy = floor(_screen_y + _gpy * _scale_y);
	                                draw_rectangle(_gsx, _gsy, _gsx + ceil(_gpxw * 2), _gsy + ceil(_gpxh), false);
	                            }
	                        }
	                        buffer_delete(_buf_prev);
	                    }
	                    gpu_set_texfilter(true);
	                }

	                // Scan for clashes on mouse release
	                if (variable_struct_exists(_asset.meta, "needs_clash_check") && _asset.meta.needs_clash_check) {
	                    if (!mouse_check_button(mb_left) && !mouse_check_button(mb_right)) {
	                        // We pass auto_clean here. 
	                        // If OFF: It just updates the clash_grid (Red Boxes).
	                        // If ON: It updates the grid AND fixes the pixels.
	                        scr_asset_kla_process_surface(_asset, _asset.meta.auto_clean, -1); 
	                        _asset.meta.needs_clash_check = false;
	                    }
	                }


	                // Draw Clash Overlays
                var _clash_sx_scale = window_get_width()  / _gui_w;
                var _clash_sy_scale = window_get_height() / display_get_gui_height();
                gpu_set_scissor(
                    floor(_sx * _clash_sx_scale),
                    floor(_sy * _clash_sy_scale),
                    ceil(_sw * _clash_sx_scale),
                    ceil(_sh * _clash_sy_scale)
                );
                for(var _cyg = 0; _cyg < 25; _cyg++) {
                    for(var _cxg = 0; _cxg < 40; _cxg++) {
                        if (_asset.meta.clash_grid[_cyg * 40 + _cxg]) {
                            var _ox = 0, _oy = 0, _ox2 = 0, _oy2 = 0;
                            if (_z <= bmp_ui_zoom_cap) {
                                var _cell_px = _sw / 320;
                                _ox  = _sx + floor(_cxg * 8 * _cell_px);
                                _oy  = _sy + floor(_cyg * 8 * _cell_px);
                                _ox2 = _sx + floor((_cxg + 1) * 8 * _cell_px);
                                _oy2 = _sy + floor((_cyg + 1) * 8 * _cell_px);
                            } else {
                                _ox  = _sx + floor((_cxg * 8 - _src_x2) / _src_w2 * _sw);
                                _oy  = _sy + floor((_cyg * 8 - _src_y2) / _src_h2 * _sh);
                                _ox2 = _sx + floor(((_cxg + 1) * 8 - _src_x2) / _src_w2 * _sw);
                                _oy2 = _sy + floor(((_cyg + 1) * 8 - _src_y2) / _src_h2 * _sh);
                            }
                            // Outer outline (3px, offset -3 outside cell)
                            draw_set_alpha(1.0);
                            draw_set_color(c_red);
                            for (var _t = 0; _t < 3; _t++) {
                                draw_rectangle(_ox - 3 + _t, _oy - 3 + _t, _ox2 + 3 - _t, _oy2 + 3 - _t, true);
                            }
                            // Inner inline (1px, offset +1 inside cell)
                            draw_set_alpha(0.6);
                            draw_rectangle(_ox + 1, _oy + 1, _ox2 - 1, _oy2 - 1, true);
                           draw_set_alpha(1.0);
                        }
                    }
                }
                gpu_set_scissor(0, 0, window_get_width(), window_get_height());

                // --- CLEANED UP TOOLBARS ---
	                // LEFT SIDE TOOLS
	                var _ltx = _vx1 + 10;
	                var _lty = _vy1 + 110; 

	                var _tools_l = ["GRAB", "FLIP X", "FLIP Y", "REPLACE"];
	                for(var _i = 0; _i < array_length(_tools_l); _i++) {
	                    var _tname = _tools_l[_i];
	                    var _active = (_asset.meta.active_tool == _tname);
	                    if (_tname == "REPLACE") _active = _asset.meta.replace_mode;
                        
	                    var _hov = point_in_rectangle(_mx, _my, _ltx, _lty, _ltx + 60, _lty + 16);
                        
	                    draw_set_color(_hov ? make_color_rgb(80, 80, 100) : (_active ? make_color_rgb(20, 60, 20) : make_color_rgb(40, 40, 60)));
	                    draw_rectangle(_ltx, _lty, _ltx + 60, _lty + 16, false);
	                    draw_set_color(_hov ? c_white : (_active ? c_lime : c_black));
	                    draw_rectangle(_ltx, _lty, _ltx + 60, _lty + 16, true);
	                    draw_set_font(fnt_c64_tiny);
	                    draw_set_color(_active ? c_lime : c_white);
	                    draw_text(_ltx + 4, _lty + 3, _tname);
                        
	                    if (_hov && mouse_check_button_pressed(mb_left)) {
	                        if (_tname == "REPLACE") {
	                            _asset.meta.replace_mode = !_asset.meta.replace_mode;
	                        } else if (_tname == "FLIP X") {
	                            if (surface_exists(_asset.meta.grab_surf)) {
	                                // Flip the grab brush horizontally
	                                var _tw = _asset.meta.grab_w;
	                                var _th = _asset.meta.grab_h;
	                                var _tsurf = surface_create(_tw, _th);
	                                surface_set_target(_tsurf);
	                                var _p_fil = gpu_get_texfilter(); gpu_set_texfilter(false);
	                                draw_clear_alpha(c_black, 0);
	                                gpu_set_blendmode_ext(bm_one, bm_zero); // clean 1:1 copy — no alpha accumulation
	                                draw_surface_ext(_asset.meta.grab_surf, _tw, 0, -1, 1, 0, c_white, 1);
	                                gpu_set_blendmode(bm_normal);
	                                gpu_set_texfilter(_p_fil);
	                                surface_reset_target();
	                                surface_copy(_asset.meta.grab_surf, 0, 0, _tsurf);
	                                surface_free(_tsurf);
                                    
	                                // Flip the mask array inside the brush
	                                var _old_m = array_create(_tw * _th);
	                                array_copy(_old_m, 0, _asset.meta.grab_mask, 0, _tw * _th);
	                                for(var _gy = 0; _gy < _th; _gy++) {
	                                    for(var _gx = 0; _gx < _tw; _gx++) {
	                                        _asset.meta.grab_mask[_gy * _tw + _gx] = _old_m[_gy * _tw + (_tw - 1 - _gx)];
	                                    }
	                                }
	                                // Toggle X-flip parity (matches hotkey path)
	                                if (!variable_struct_exists(_asset.meta, "grab_flip_x")) _asset.meta.grab_flip_x = false;
	                                _asset.meta.grab_flip_x = !_asset.meta.grab_flip_x;
	                                // Invalidate cached preview anchor so the stamp preview re-evaluates this frame
	                                _asset.meta._ov_last_mx = -1;
	                                _asset.meta._ov_last_my = -1;
	                            } else {
	                                scr_asset_bmp_flip(_asset, true, false);
	                            }
	                        } else if (_tname == "FLIP Y") {
	                            if (surface_exists(_asset.meta.grab_surf)) {
	                                // Flip the grab brush vertically
	                                var _tw = _asset.meta.grab_w;
	                                var _th = _asset.meta.grab_h;
	                                var _tsurf = surface_create(_tw, _th);
	                                surface_set_target(_tsurf);
	                                var _p_fil = gpu_get_texfilter(); gpu_set_texfilter(false);
	                                draw_clear_alpha(c_black, 0);
	                                gpu_set_blendmode_ext(bm_one, bm_zero); // clean 1:1 copy — no alpha accumulation
	                                draw_surface_ext(_asset.meta.grab_surf, 0, _th, 1, -1, 0, c_white, 1);
	                                gpu_set_blendmode(bm_normal);
	                                gpu_set_texfilter(_p_fil);
	                                surface_reset_target();
	                                surface_copy(_asset.meta.grab_surf, 0, 0, _tsurf);
	                                surface_free(_tsurf);
                                    
	                                // Flip mask array inside the brush
	                                var _old_m = array_create(_tw * _th);
	                                array_copy(_old_m, 0, _asset.meta.grab_mask, 0, _tw * _th);
	                                for(var _gy = 0; _gy < _th; _gy++) {
	                                    for(var _gx = 0; _gx < _tw; _gx++) {
	                                        _asset.meta.grab_mask[_gy * _tw + _gx] = _old_m[(_th - 1 - _gy) * _tw + _gx];
	                                    }
	                                }
	                                // Invalidate cached preview anchor so the stamp preview re-evaluates this frame
	                                _asset.meta._ov_last_mx = -1;
	                                _asset.meta._ov_last_my = -1;
	                            } else {
	                                scr_asset_bmp_flip(_asset, false, true);
	                            }
	                        } else {
	                            // Clear the stamp if we switch away from it
	                            if (_tname != "GRAB" && surface_exists(_asset.meta.grab_surf)) {
	                                surface_free(_asset.meta.grab_surf);
	                                _asset.meta.grab_surf = -1;
	                            }
	                            _asset.meta.active_tool = _tname;
	                        }
	                    }
	                    _lty += 20;
	                }

	                _lty += 10; 

	                // Replace Color Selectors
	                if (_asset.meta.replace_mode) {
	                    draw_set_color(scr_c64_pepto_colour(_asset.meta.replace_col_detect));
	                    draw_rectangle(_ltx, _lty, _ltx + 28, _lty + 12, false);
	                    draw_set_color(c_white);
	                    draw_rectangle(_ltx, _lty, _ltx + 28, _lty + 12, true); 
	                    if (point_in_rectangle(_mx, _my, _ltx, _lty, _ltx + 28, _lty + 12) && mouse_check_button_pressed(mb_left))
	                        _asset.meta.replace_col_detect = _asset.meta.active_color;
                        
	                    draw_set_color(c_white); draw_text(_ltx + 32, _lty + 2, "COL1");
	                    _lty += 18;
                        
	                    draw_set_color(scr_c64_pepto_colour(_asset.meta.replace_col_target));
	                    draw_rectangle(_ltx, _lty, _ltx + 28, _lty + 12, false);
	                    draw_set_color(c_white);
	                    draw_rectangle(_ltx, _lty, _ltx + 28, _lty + 12, true); 
	                    if (point_in_rectangle(_mx, _my, _ltx, _lty, _ltx + 28, _lty + 12) && mouse_check_button_pressed(mb_left))
	                        _asset.meta.replace_col_target = _asset.meta.active_color;
                        
	                    draw_set_color(c_white); draw_text(_ltx + 32, _lty + 2, "COL2");
	                    _lty += 24;
	                } else {
	                    _lty += 42; 
	                }

	                // Zoom Buttons
	                var _zhov_in = point_in_rectangle(_mx, _my, _ltx, _lty, _ltx + 24, _lty + 24);
	                draw_set_color(_zhov_in ? make_color_rgb(80, 80, 100) : make_color_rgb(40, 40, 60)); 
	                draw_rectangle(_ltx, _lty, _ltx + 24, _lty + 24, false);
	                draw_set_color(_zhov_in ? c_white : c_black); 
	                draw_rectangle(_ltx, _lty, _ltx + 24, _lty + 24, true);
	                draw_set_color(c_white); draw_text(_ltx + 6, _lty + 6, "Z+");
                    
	                if (_zhov_in && mouse_check_button_pressed(mb_left)) _asset.meta.bmp_zoom += 0.2;

	                _lty += 30;
	                var _zhov_out = point_in_rectangle(_mx, _my, _ltx, _lty, _ltx + 24, _lty + 24);
	                var _at_min_z = (_asset.meta.bmp_zoom <= bmp_ui_zoom_cap);
	                draw_set_color(_at_min_z ? make_color_rgb(25, 25, 35) : (_zhov_out ? make_color_rgb(80, 80, 100) : make_color_rgb(40, 40, 60))); 
	                draw_rectangle(_ltx, _lty, _ltx + 24, _lty + 24, false);
	                draw_set_color(_at_min_z ? make_color_rgb(40, 40, 50) : (_zhov_out ? c_white : c_black)); 
	                draw_rectangle(_ltx, _lty, _ltx + 24, _lty + 24, true);
	                draw_set_color(_at_min_z ? make_color_rgb(50, 50, 60) : c_white);
	                draw_text(_ltx + 6, _lty + 6, "Z-");
                    
	                if (_zhov_out && mouse_check_button_pressed(mb_left) && _asset.meta.bmp_zoom > bmp_ui_zoom_cap) {
	                    var _old_z = _asset.meta.bmp_zoom;
	                    _asset.meta.bmp_zoom = max(bmp_ui_zoom_cap, _asset.meta.bmp_zoom - 0.2);
	                    if (_asset.meta.bmp_zoom != _old_z) {
	                        _asset.meta.bmp_pan_x *= (_asset.meta.bmp_zoom / _old_z);
	                        _asset.meta.bmp_pan_y *= (_asset.meta.bmp_zoom / _old_z);
	                    }
	                }

					// RIGHT SIDE TOOLS
	                var _rtx = _thumb_x + _thumb_w + 45;
	                var _rty = _thumb_y;

	                var _tools_r = ["DRAW", "LINE", "CIRCLE", "RECT", "FILL", "GRADIENT"];
	                for(var _i = 0; _i < array_length(_tools_r); _i++) {
	                    var _tname = _tools_r[_i];
	                    var _active = (_asset.meta.active_tool == _tname);
	                    var _hov = point_in_rectangle(_mx, _my, _rtx, _rty, _rtx + 70, _rty + 16);
                        
	                    var _label = _tname;
	                    if ((_tname == "CIRCLE" || _tname == "RECT") && _active) {
	                        _label += _asset.meta.fill_toggle ? " (F)" : " (NF)";
	                    }

	                    draw_set_color(_hov ? make_color_rgb(80, 80, 100) : (_active ? make_color_rgb(20, 60, 60) : make_color_rgb(40, 40, 60)));
	                    draw_rectangle(_rtx, _rty, _rtx + 70, _rty + 16, false);
	                    draw_set_color(_hov ? c_white : (_active ? c_aqua : c_black));
	                    draw_rectangle(_rtx, _rty, _rtx + 70, _rty + 16, true);
	                    draw_set_color(_active ? c_aqua : c_white);
	                    draw_text(_rtx + 4, _rty , _label);
                        
	                    if (_hov && mouse_check_button_pressed(mb_left)) {
	                        if (_active && (_tname == "CIRCLE" || _tname == "RECT")) {
	                            _asset.meta.fill_toggle = !_asset.meta.fill_toggle;
	                        } else {
	                            if (_tname != "GRAB" && surface_exists(_asset.meta.grab_surf)) {
	                                surface_free(_asset.meta.grab_surf);
	                                _asset.meta.grab_surf = -1;
	                            }
	                            _asset.meta.active_tool = _tname;
	                        }
	                    }
	                    _rty += 20;
	                }

	                // HiRes role recalibration. The current primary/secondary
	                // swatches are treated as the intended FG/BG pair. A cell
	                // is changed only when BOTH colours actually occur in its
	                // 8x8 pixels; every other cell is left exactly as it was.
	                if (_bmp_is_hires && !_asset.meta.replace_mode) {
	                    var _cal_enabled = (_asset.meta.active_color != _asset.meta.secondary_color)
	                                    && surface_exists(_asset.meta.preview_surf);
	                    var _cal_hov = _cal_enabled
	                                && point_in_rectangle(_mx, _my, _rtx, _rty, _rtx + 70, _rty + 16);
	                    draw_set_color(!_cal_enabled ? make_color_rgb(25, 25, 35)
	                                   : (_cal_hov ? make_color_rgb(100, 80, 40) : make_color_rgb(60, 45, 25)));
	                    draw_rectangle(_rtx, _rty, _rtx + 70, _rty + 16, false);
	                    draw_set_color(!_cal_enabled ? make_color_rgb(50, 50, 60)
	                                   : (_cal_hov ? c_white : c_orange));
	                    draw_rectangle(_rtx, _rty, _rtx + 70, _rty + 16, true);
	                    draw_text(_rtx + 3, _rty, "UPDATE F/B");

	                    if (_cal_hov && mouse_check_button_pressed(mb_left)) {
	                        var _cal_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                        buffer_get_surface(_cal_buf, _asset.meta.preview_surf, 0);

	                        var _cal_fg_rgb = scr_c64_pepto_colour(_asset.meta.active_color);
	                        var _cal_bg_rgb = scr_c64_pepto_colour(_asset.meta.secondary_color);
	                        var _cal_fg_r = color_get_red(_cal_fg_rgb);
	                        var _cal_fg_g = color_get_green(_cal_fg_rgb);
	                        var _cal_fg_b = color_get_blue(_cal_fg_rgb);
	                        var _cal_bg_r = color_get_red(_cal_bg_rgb);
	                        var _cal_bg_g = color_get_green(_cal_bg_rgb);
	                        var _cal_bg_b = color_get_blue(_cal_bg_rgb);
	                        var _cal_count = 0;

	                        for (var _cal_cy = 0; _cal_cy < 25; _cal_cy++) {
	                            for (var _cal_cx = 0; _cal_cx < 40; _cal_cx++) {
	                                var _cal_has_fg = false;
	                                var _cal_has_bg = false;

	                                // First pass only tests eligibility.
	                                for (var _cal_py = 0; _cal_py < 8; _cal_py++) {
	                                    for (var _cal_px = 0; _cal_px < 8; _cal_px++) {
	                                        var _cal_x = _cal_cx * 8 + _cal_px;
	                                        var _cal_y = _cal_cy * 8 + _cal_py;
	                                        var _cal_off = (_cal_y * 320 + _cal_x) * 4;
	                                        var _cal_r = buffer_peek(_cal_buf, _cal_off,     buffer_u8);
	                                        var _cal_g = buffer_peek(_cal_buf, _cal_off + 1, buffer_u8);
	                                        var _cal_b = buffer_peek(_cal_buf, _cal_off + 2, buffer_u8);
	                                        if (_cal_r == _cal_fg_r && _cal_g == _cal_fg_g && _cal_b == _cal_fg_b) _cal_has_fg = true;
	                                        if (_cal_r == _cal_bg_r && _cal_g == _cal_bg_g && _cal_b == _cal_bg_b) _cal_has_bg = true;
	                                    }
	                                }

	                                if (_cal_has_fg && _cal_has_bg) {
	                                    var _cal_cell = _cal_cy * 40 + _cal_cx;
	                                    _asset.meta.hr_cell_fg_col[_cal_cell] = _asset.meta.active_color;
	                                    _asset.meta.hr_cell_bg_col[_cal_cell] = _asset.meta.secondary_color;

	                                    // Second pass assigns each selected-colour pixel
	                                    // to its matching role. Eligible HiRes cells have
	                                    // this two-colour pair, so non-FG pixels are BG.
	                                    for (var _cal_ry = 0; _cal_ry < 8; _cal_ry++) {
	                                        for (var _cal_rx = 0; _cal_rx < 8; _cal_rx++) {
	                                            var _cal_ax = _cal_cx * 8 + _cal_rx;
	                                            var _cal_ay = _cal_cy * 8 + _cal_ry;
	                                            var _cal_roff = (_cal_ay * 320 + _cal_ax) * 4;
	                                            var _cal_rr = buffer_peek(_cal_buf, _cal_roff,     buffer_u8);
	                                            var _cal_rg = buffer_peek(_cal_buf, _cal_roff + 1, buffer_u8);
	                                            var _cal_rb = buffer_peek(_cal_buf, _cal_roff + 2, buffer_u8);
	                                            _asset.meta.hr_role_mask[_cal_ay * 320 + _cal_ax]
	                                                = (_cal_rr == _cal_fg_r && _cal_rg == _cal_fg_g && _cal_rb == _cal_fg_b) ? 1 : 0;
	                                        }
	                                    }
	                                    _cal_count++;
	                                }
	                            }
	                        }

	                        buffer_delete(_cal_buf);
	                        _asset.meta.hr_recalibrated_cells = _cal_count;
	                        if (_cal_count > 0) {
	                            _asset.meta.pixels_dirty = true;
	                            _asset.meta.bmp_unsaved  = true;
	                        }
	                    }
	                    _rty += 20;
	                }

	                _rty += 5;
	                draw_set_color(make_color_rgb(60, 60, 80));
	                draw_line(_rtx, _rty, _rtx + 70, _rty);
	                _rty += 10;

// Dither Options
	                var _dithers = ["NONE","CHECKER","INTERLACE",
	                                "BAYER_4","BAYER_8","BAYER_12","BAYER_16",
	                                "BAYER_20","BAYER_24","BAYER_28","BAYER_32",
	                                "BAYER_36","BAYER_40","BAYER_44","BAYER_48",
	                                "BAYER_52","BAYER_56","BAYER_60"];
	                for (var _i = 0; _i < array_length(_dithers); _i++) {
	                    var _dname  = _dithers[_i];
	                    var _active = (_asset.meta.dither_mode == _dname);
	                    var _hov    = point_in_rectangle(_mx, _my, _rtx, _rty, _rtx + 70, _rty + 16);
                        
	                    draw_set_color(_hov ? make_color_rgb(80, 80, 100) : (_active ? make_color_rgb(60, 60, 20) : make_color_rgb(40, 40, 60)));
	                    draw_rectangle(_rtx, _rty, _rtx + 70, _rty + 16, false);
	                    draw_set_color(_hov ? c_white : (_active ? c_yellow : c_black));
	                    draw_rectangle(_rtx, _rty, _rtx + 70, _rty + 16, true);
	                    draw_set_color(_active ? c_yellow : c_white);
	                    draw_text(_rtx + 4, _rty -1, _dname);
                        
	                    if (_hov && mouse_check_button_pressed(mb_left)) _asset.meta.dither_mode = _dname;
	                    _rty += 18;
	                }
                    
	                // INVERT toggle (disabled when NONE)
	                _rty += 4;
	                var _inv_active  = _asset.meta.dither_invert;
	                var _inv_enabled = (_asset.meta.dither_mode != "NONE");
	                var _inv_hov     = _inv_enabled && point_in_rectangle(_mx, _my, _rtx, _rty, _rtx + 70, _rty + 16);
	                draw_set_color(_inv_enabled
	                    ? (_inv_hov ? make_color_rgb(100, 60, 120) : (_inv_active ? make_color_rgb(80, 20, 100) : make_color_rgb(40, 40, 60)))
	                    : make_color_rgb(25, 25, 35));
	                draw_rectangle(_rtx, _rty, _rtx + 70, _rty + 16, false);
	                draw_set_color(_inv_enabled ? (_inv_active ? make_color_rgb(200, 120, 255) : c_black) : make_color_rgb(50, 50, 60));
	                draw_rectangle(_rtx, _rty, _rtx + 70, _rty + 16, true);
	                draw_set_color(_inv_enabled ? (_inv_active ? make_color_rgb(200, 120, 255) : c_ltgray) : make_color_rgb(50, 50, 60));
	                draw_text(_rtx + 4, _rty + 3, "INVERT");
	                if (_inv_hov && mouse_check_button_pressed(mb_left)) _asset.meta.dither_invert = !_asset.meta.dither_invert;
	                _rty += 20;
                    
				var _px = _thumb_x + _thumb_w + 12;
	                var _py = _thumb_y;
	                var _pw = 24;
	                var _ph = min(20, floor(_thumb_h / 16) - 2); 
                    
	                // Safety check to prevent crash if meta isn't fully initialized yet
	                if (!variable_struct_exists(_asset.meta, "active_color")) _asset.meta.active_color = 1;
	                if (!variable_struct_exists(_asset.meta, "replace_col_detect")) _asset.meta.replace_col_detect = 0;
	                if (!variable_struct_exists(_asset.meta, "replace_col_target")) _asset.meta.replace_col_target = 1;

	                if (_bmp_is_hires && !_asset.meta.replace_mode) {
	                    draw_set_font(fnt_c64_tiny);
	                    draw_set_color(make_color_rgb(160,160,200));
	                    draw_text(_px -8, _py - 40, "MOUSE BUTTON:\nL = PEN / R = CELL BKG");
	                }

					for(var _c = 0; _c < 16; _c++) {
						var _pyc = _py + (_c * (_ph + 2));
						var _phov = point_in_rectangle(_mx, _my, _px, _pyc, _px + _pw, _pyc + _ph);
						draw_set_color(scr_c64_pepto_colour(_c));
						draw_rectangle(_px, _pyc, _px + _pw, _pyc + _ph, false);
						if (_asset.meta.active_color == _c) {
	                        // Primary (LMB / col1) — white double-border box outline.
	                        draw_set_color(c_white);
	                        draw_rectangle(_px-2, _pyc-2, _px + _pw+2, _pyc + _ph+2, true);
	                        draw_rectangle(_px-4, _pyc-4, _px + _pw+4, _pyc + _ph+4, true);
	                    }
	                    if (!_asset.meta.replace_mode && _asset.meta.secondary_color == _c) {
	                        // Secondary (RMB / col2) — aqua double-border box outline.
	                        // Shown in MC too (not just HiRes) now that GRADIENT reads it.
	                        draw_set_color(c_aqua);
	                        draw_rectangle(_px-2, _pyc-2, _px + _pw+2, _pyc + _ph+2, true);
	                        draw_rectangle(_px-6, _pyc-6, _px + _pw+6, _pyc + _ph+6, true);
	                    }
	                    if (_asset.meta.replace_mode) {
	                        if (_asset.meta.replace_col_detect == _c) {
	                            draw_set_color(c_lime);
	                            draw_rectangle(_px-2, _pyc-2, _px + _pw+2, _pyc + _ph+2, true);
	                        }
	                        if (_asset.meta.replace_col_target == _c) {
	                            draw_set_color(c_red);
	                            draw_rectangle(_px-2, _pyc-2, _px + _pw+2, _pyc + _ph+2, true);
	                        }
	                        if (_phov && mouse_check_button_pressed(mb_left))  _asset.meta.replace_col_detect = _c;
	                        if (_phov && mouse_check_button_pressed(mb_right)) _asset.meta.replace_col_target = _c;
	                    } else {
	                        if (_phov && mouse_check_button_pressed(mb_left)) _asset.meta.active_color = _c;
	                        if (_phov && mouse_check_button_pressed(mb_right)) _asset.meta.secondary_color = _c;
	                    }
	                }
	              
	            } // end !goto_end_editor
					// INITIALIZE TO INTEGER SWEET SPOT
                if (!variable_struct_exists(_asset.meta, "bmp_zoom")) {
                    _asset.meta.bmp_zoom = bmp_ui_zoom_cap_base; 
                }
	                // ZOOM & PAN — available in all editor modes including PNG conversion
	                if (point_in_rectangle(_mx, _my, _sx, _sy, _sx + _sw, _sy + _sh)) {
	                    var _wheel = mouse_wheel_up() ? 1 : (mouse_wheel_down() ? -1 : 0);
	                    if (_wheel != 0) {
	                        var _old_z = _asset.meta.bmp_zoom;
	                        // Instead of 0.2, step by exactly 1.0 (or a factor that aligns with your specific UI math) 
							// to ensure the multiplier remains a clean integer.
							// Replaced bmp_ui_zoom_cap with a hard floor of 2 so you can always zoom out
var _new_z = max(2, _old_z + (_wheel * 1.0));
	                        _asset.meta.bmp_zoom = _new_z;
	                        if (_new_z > bmp_ui_zoom_cap) {
	                            var _px_zoom_old = max(1.0, _old_z / bmp_ui_zoom_cap);
	                            var _px_zoom_new = _new_z / bmp_ui_zoom_cap;
	                            var _src_w_old = 320 / _px_zoom_old;
	                            var _src_h_old = 200 / _px_zoom_old;
	                            var _src_w_new = 320 / _px_zoom_new;
	                            var _src_h_new = 200 / _px_zoom_new;
	                            var _mouse_surf_x = _asset.meta.bmp_pan_x + ((_mx - _sx) / _sw) * _src_w_old;
	                            var _mouse_surf_y = _asset.meta.bmp_pan_y + ((_my - _sy) / _sh) * _src_h_old;
	                            _asset.meta.bmp_pan_x = _mouse_surf_x - ((_mx - _sx) / _sw) * _src_w_new;
	                            _asset.meta.bmp_pan_y = _mouse_surf_y - ((_my - _sy) / _sh) * _src_h_new;
	                        } else {
	                            _asset.meta.bmp_pan_x = 0;
	                            _asset.meta.bmp_pan_y = 0;
	                        }
	                        var _px_zoom_clamp = max(1.0, _new_z / bmp_ui_zoom_cap);
	                        var _src_w_clamp = 320 / _px_zoom_clamp;
	                        var _src_h_clamp = 200 / _px_zoom_clamp;
	                        _asset.meta.bmp_pan_x = clamp(_asset.meta.bmp_pan_x, 0, 320 - _src_w_clamp);
	                        _asset.meta.bmp_pan_y = clamp(_asset.meta.bmp_pan_y, 0, 200 - _src_h_clamp);
	                    }
	                    if (mouse_check_button_pressed(mb_middle) || keyboard_check_pressed(vk_space)) {
	                        _asset.meta.bmp_pan_dragging = true;
	                        _asset.meta.bmp_pan_start_mx = _mx;
	                        _asset.meta.bmp_pan_start_my = _my;
	                        _asset.meta.bmp_pan_start_x  = _asset.meta.bmp_pan_x;
	                        _asset.meta.bmp_pan_start_y  = _asset.meta.bmp_pan_y;
	                    }
	                }
	                if (!variable_struct_exists(_asset.meta, "bmp_pan_dragging")) _asset.meta.bmp_pan_dragging = false;
	                if ((mouse_check_button_pressed(mb_middle) || keyboard_check_pressed(vk_space)) && point_in_rectangle(_mx, _my, _sx, _sy, _sx + _sw, _sy + _sh)) {
	                    _asset.meta.bmp_pan_dragging = true;
	                    _asset.meta.bmp_pan_start_mx = _mx;
	                    _asset.meta.bmp_pan_start_my = _my;
	                    _asset.meta.bmp_pan_start_x  = _asset.meta.bmp_pan_x;
	                    _asset.meta.bmp_pan_start_y  = _asset.meta.bmp_pan_y;
	                }
	                if (mouse_check_button_released(mb_middle) || keyboard_check_released(vk_space)) _asset.meta.bmp_pan_dragging = false;
	                if (_asset.meta.bmp_pan_dragging && (mouse_check_button(mb_middle) || keyboard_check(vk_space))) {
	                    var _z = _asset.meta.bmp_zoom;
	                    if (_z > bmp_ui_zoom_cap) {
	                        var _px_zoom_d = _z / bmp_ui_zoom_cap;
	                        var _src_w_d   = 320 / _px_zoom_d;
	                        var _src_h_d   = 200 / _px_zoom_d;
	                        var _dpx = -(_mx - _asset.meta.bmp_pan_start_mx) / _sw * _src_w_d;
	                        var _dpy = -(_my - _asset.meta.bmp_pan_start_my) / _sh * _src_h_d;
	                        _asset.meta.bmp_pan_x = clamp(_asset.meta.bmp_pan_start_x + _dpx, 0, 320 - _src_w_d);
	                        _asset.meta.bmp_pan_y = clamp(_asset.meta.bmp_pan_start_y + _dpy, 0, 200 - _src_h_d);
	                    }
                }
                    
                 
                    
            } // end _is_ed
	                

	                
	            // ── COORD READOUT BAR (two lines, directly under the canvas) ──
	            // Line 1: cursor position in hi-res pixels + the char cell it lands in.
	            // Line 2: the active marquee / grab stamp, in pixels AND cells — read
	            //         these straight off and type them into MOVE_BMP_BLOCK.
	            _cy = _thumb_y + _thumb_h + 16;
	            draw_set_font(fnt_c64_tiny);

	            var _hud_x = _asset.meta.hud_px;
	            var _hud_y = _asset.meta.hud_py;

	            // ---- LINE 1: MOUSE ----
	            draw_set_color(make_color_rgb(90, 90, 120));
	            draw_text(_thumb_x, _cy, "MOUSE:");
	            if (_hud_x >= 0) {
	                var _hud_col = _hud_x div 8;
	                var _hud_row = _hud_y div 8;
	                var _hud_mc  = (_hud_x div 2) * 2;
	                draw_set_color(c_ltgray);  draw_text(_thumb_x + 60,  _cy, "X:");
	                draw_set_color(c_aqua);    draw_text(_thumb_x + 78,  _cy, string(_hud_x));
	                draw_set_color(make_color_rgb(70, 110, 140));
	                draw_text(_thumb_x + 112, _cy, "(MC " + string(_hud_mc) + ")");
	                draw_set_color(c_ltgray);  draw_text(_thumb_x + 176, _cy, "Y:");
	                draw_set_color(c_aqua);    draw_text(_thumb_x + 194, _cy, string(_hud_y));
	                draw_set_color(c_ltgray);  draw_text(_thumb_x + 240, _cy, "COL:");
	                draw_set_color(c_yellow);  draw_text(_thumb_x + 274, _cy, string(_hud_col));
	                draw_set_color(c_ltgray);  draw_text(_thumb_x + 308, _cy, "ROW:");
	                draw_set_color(c_yellow);  draw_text(_thumb_x + 342, _cy, string(_hud_row));
	            } else {
	                draw_set_color(make_color_rgb(60, 60, 80));
	                draw_text(_thumb_x + 60, _cy, "OFF CANVAS");
	            }
	            _cy += 14;

	            // ---- LINE 2: SELECTION / STAMP ----
	            draw_set_color(make_color_rgb(90, 90, 120));
	            draw_text(_thumb_x, _cy, "SEL:");

	            var _sel_shown = false;

	            // (a) Live GRAB marquee — mirrors the capture snap so what the bar
	            //     says is exactly what the stamp will contain.
	            if (variable_struct_exists(_asset.meta, "is_grabbing")
	            &&  _asset.meta.is_grabbing
	            &&  _hud_x >= 0) {
	                var _sgx1 = floor(min(_asset.meta.grab_x1, _hud_x));
	                var _sgy1 = floor(min(_asset.meta.grab_y1, _hud_y));
	                var _sgx2 = floor(max(_asset.meta.grab_x1, _hud_x));
	                var _sgy2 = floor(max(_asset.meta.grab_y1, _hud_y));
	                _sgx1 = (_sgx1 div 2) * 2;
	                _sgx2 = (_sgx2 div 2) * 2;
	                var _sgw = (_sgx2 - _sgx1) + 2;
	                var _sgh = (_sgy2 - _sgy1) + 1;
	                var _scol = _sgx1 div 8;
	                var _srow = _sgy1 div 8;
	                var _scw  = ceil(_sgw / 8);
	                var _sch  = ceil(_sgh / 8);
	                draw_set_color(c_ltgray);  draw_text(_thumb_x + 60,  _cy, "X:");
	                draw_set_color(c_lime);    draw_text(_thumb_x + 78,  _cy, string(_sgx1));
	                draw_set_color(c_ltgray);  draw_text(_thumb_x + 112, _cy, "Y:");
	                draw_set_color(c_lime);    draw_text(_thumb_x + 130, _cy, string(_sgy1));
	                draw_set_color(c_ltgray);  draw_text(_thumb_x + 164, _cy, "W:");
	                draw_set_color(c_lime);    draw_text(_thumb_x + 182, _cy, string(_sgw));
	                draw_set_color(c_ltgray);  draw_text(_thumb_x + 216, _cy, "H:");
	                draw_set_color(c_lime);    draw_text(_thumb_x + 234, _cy, string(_sgh));
	                draw_set_color(c_ltgray);  draw_text(_thumb_x + 276, _cy, "CELL:");
	                draw_set_color(c_yellow);
	                draw_text(_thumb_x + 318, _cy,
	                    "COL " + string(_scol) + "  ROW " + string(_srow)
	                    + "  W " + string(_scw) + "  H " + string(_sch));
	                _sel_shown = true;
	            }

	            // (b) Held grab stamp — no live marquee, but a captured brush exists.
	            if (!_sel_shown
	            &&  variable_struct_exists(_asset.meta, "grab_surf")
	            &&  surface_exists(_asset.meta.grab_surf)) {
	                var _hgw = _asset.meta.grab_w;
	                var _hgh = _asset.meta.grab_h;
	                var _hcw = ceil(_hgw / 8);
	                var _hch = ceil(_hgh / 8);
	                draw_set_color(make_color_rgb(200, 140, 255));
	                draw_text(_thumb_x + 60, _cy, "STAMP HELD");
	                draw_set_color(c_ltgray);  draw_text(_thumb_x + 164, _cy, "W:");
	                draw_set_color(c_lime);    draw_text(_thumb_x + 182, _cy, string(_hgw));
	                draw_set_color(c_ltgray);  draw_text(_thumb_x + 216, _cy, "H:");
	                draw_set_color(c_lime);    draw_text(_thumb_x + 234, _cy, string(_hgh));
	                draw_set_color(c_ltgray);  draw_text(_thumb_x + 276, _cy, "CELL:");
	                draw_set_color(c_yellow);
	                draw_text(_thumb_x + 318, _cy,
	                    "W " + string(_hcw) + "  H " + string(_hch));
	                _sel_shown = true;
	            }

	            if (!_sel_shown) {
	                draw_set_color(make_color_rgb(60, 60, 80));
	                draw_text(_thumb_x + 60, _cy, "-- NO SELECTION --");
	            }
	            _cy += 16;

	            // ── GRADIENT: CUSTOM stop row (shown whenever GRADIENT is the
	            // active tool; only applied to the fill when the CUSTOM toggle
	            // is on — otherwise the plain col1->col2 gradient is used). ──
	            if (_asset.meta.active_tool == "GRADIENT") {
	                draw_set_font(fnt_c64_tiny);
	                draw_set_color(make_color_rgb(90, 90, 120));
	                draw_text(_thumb_x, _cy, "GRADIENT:");

	                var _gc_btn_x1 = _thumb_x + 63;
	                var _gc_btn_x2 = _gc_btn_x1 + 60;
	                var _gc_btn_y1 = _cy ;
	                var _gc_btn_y2 = _cy + 14;
	                var _gc_hov = point_in_rectangle(_mx, _my, _gc_btn_x1, _gc_btn_y1, _gc_btn_x2, _gc_btn_y2);
	                draw_set_color(_asset.meta.gradient_custom_active ? make_color_rgb(20, 60, 60) : (_gc_hov ? make_color_rgb(80, 80, 100) : make_color_rgb(40, 40, 60)));
	                draw_rectangle(_gc_btn_x1, _gc_btn_y1, _gc_btn_x2, _gc_btn_y2, false);
	                draw_set_color(_asset.meta.gradient_custom_active ? c_aqua : (_gc_hov ? c_white : c_black));
	                draw_rectangle(_gc_btn_x1, _gc_btn_y1, _gc_btn_x2, _gc_btn_y2, true);
	                draw_set_color(_asset.meta.gradient_custom_active ? c_aqua : c_white);
	                draw_text(_gc_btn_x1 + 8, _cy, "CUSTOM");
	                if (_gc_hov && mouse_check_button_pressed(mb_left)) {
	                    _asset.meta.gradient_custom_active = !_asset.meta.gradient_custom_active;
	                }

	                // 12 stop slots. Left-click a slot to set it to the current
	                // col1 (active_color) — pick col1 from the main palette above,
	                // then click a slot; repeat per slot to build the stop run.
	                var _gc_sw = 18, _gc_sh = 14, _gc_gap = 2;
	                var _gc_slots_x = _gc_btn_x2 + 12;
	                for (var _gs = 0; _gs < 12; _gs++) {
	                    var _gsx1 = 6+ _gc_slots_x + _gs * (_gc_sw + _gc_gap);
	                    var _gsx2 = _gsx1 + _gc_sw;
	                    var _gsy1 = _cy - 2;
	                    var _gsy2 = _cy + 12;
	                    var _gs_hov = point_in_rectangle(_mx, _my, _gsx1, _gsy1, _gsx2, _gsy2);
	                    draw_set_color(scr_c64_pepto_colour(_asset.meta.gradient_custom_cols[_gs]));
	                    draw_rectangle(_gsx1, _gsy1, _gsx2, _gsy2, false);
	                    draw_set_color(_gs_hov ? c_white : make_color_rgb(90, 90, 110));
	                    draw_rectangle(_gsx1, _gsy1, _gsx2, _gsy2, true);
	                    if (_gs_hov && mouse_check_button_pressed(mb_left)) {
	                        _asset.meta.gradient_custom_cols[_gs] = _asset.meta.active_color;
	                    }
	                }
	                _cy += 20;
	            }

	            // Metadata Details (Pushed below the canvas)
	            draw_set_font(fnt_c64_tiny);
	            if (variable_struct_exists(_asset.meta, "bg_col")) {
                    
	                // BG Color Cyclying Logic
	                var _bg_rect_x1 = _thumb_x + 26;
	                var _bg_rect_x2 = _thumb_x + 42;
	                var _bg_rect_y1 = _cy;
	                var _bg_rect_y2 = _cy + 12;
	                var _bg_hov = point_in_rectangle(_mx, _my, _bg_rect_x1, _bg_rect_y1, _bg_rect_x2, _bg_rect_y2);
                    
	                var _display_bg = _png_mode ? _asset.meta.png_pending_bg : _asset.meta.bg_col;
	                draw_set_color(scr_c64_pepto_colour(_display_bg));
	                draw_rectangle(_bg_rect_x1, _bg_rect_y1, _bg_rect_x2, _bg_rect_y2, false);
                    
					if (_bg_hov && _is_ed && _png_mode) {
	                draw_set_color(c_white);
	                draw_rectangle(_bg_rect_x1-1, _bg_rect_y1-1, _bg_rect_x2+1, _bg_rect_y2+1, true);
	                if (mouse_check_button_pressed(mb_left))
	                    _asset.meta.png_pending_bg = (_asset.meta.png_pending_bg + 1) mod 16;
	                if (mouse_check_button_pressed(mb_right))
	                    _asset.meta.png_pending_bg = (_asset.meta.png_pending_bg + 15) mod 16;
	            }
	            if (_bg_hov && _is_ed && !_png_mode && !_bmp_is_hires) {
	                // HiRes has no editable background concept anymore — untouched
	                // canvas is always a fixed black, and every touched cell's second
	                // colour is decided per-cell by the secondary swatch instead. So
	                // this swatch is MC-only; in HiRes it's a static readout below.
	                draw_set_color(c_white);
	                draw_rectangle(_bg_rect_x1-1, _bg_rect_y1-1, _bg_rect_x2+1, _bg_rect_y2+1, true);
	                var _clicked = false;
	                var _old_bg = _asset.meta.bg_col;
	                if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
	                    _asset.meta.bg_col = (_old_bg + 1) mod 16;
	                    _clicked = true;
	                }
	                if (mouse_check_button_pressed(mb_right)) {
	                    _asset.meta.bg_col = (_old_bg + 15) mod 16;
	                    _clicked = true;
	                }
	                if (_clicked) {
	                    // Push pre-change snapshot storing OLD bg_col so undo restores it.
	                    if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
	                        var _bg_buf = buffer_create(320 * 200 * 4, buffer_fixed, 1);
	                        buffer_get_surface(_bg_buf, _asset.meta.preview_surf, 0);
	                        var _bg_mask_snap = array_create(64000, 0);
	                        array_copy(_bg_mask_snap, 0, _asset.meta.bg_mask, 0, 64000);
	                        var _bg_entry = { buf: _bg_buf, mask: _bg_mask_snap, bg_col: _old_bg };
	                        array_push(_asset.meta.undo_stack, _bg_entry);
	                        if (array_length(_asset.meta.undo_stack) > 25) {
	                            var _bgdrop0 = _asset.meta.undo_stack[0];
	                            if (is_struct(_bgdrop0) && buffer_exists(_bgdrop0.buf)) {
	                                buffer_delete(_bgdrop0.buf);
	                            } else if (buffer_exists(_bgdrop0)) {
	                                buffer_delete(_bgdrop0);
	                            }
	                            array_delete(_asset.meta.undo_stack, 0, 1);
	                        }
	                        _asset.meta.redo_stack = [];
	                    }
	                    scr_asset_kla_process_surface(_asset, false, _old_bg);
	                    _asset.meta.needs_clash_check = true;
	                    _asset.meta.pixels_dirty = true;
	                    _asset.meta.bmp_unsaved = true;
	                }
	            }
                    
	                draw_set_color(c_white);
	                draw_text(_thumb_x + 46, _cy, string(_asset.meta.bg_col));
	            }
				_cy+=40;
	            draw_set_color(c_ltgray); draw_text(_vx1 + 120, _vy1 + 76, "SIZE:");
	            draw_set_color(c_aqua);    draw_text(_vx1 + 158, _vy1 + 76, "320 x 200");
	            draw_set_color(c_ltgray); draw_text(_vx1 + 260, _vy1 + 76, "FORMAT:");
	            draw_set_color(c_yellow); draw_text(_vx1 + 312, _vy1 + 76, "KOALA PAINT");
	            draw_set_color(c_ltgray); draw_text(_vx1 + 410, _vy1 + 76, "ADDR:");
	            var _bah = string_upper(decimal_to_hex(_asset.address));
	            while (string_length(_bah) < 4) _bah = "0" + _bah;
	            draw_set_color(c_aqua);    draw_text(_vx1 + 448, _vy1 + 76, "$" + _bah);
	        } else {
	            draw_set_color(make_color_rgb(40,40,40));
	            draw_rectangle(_thumb_x, _thumb_y, _thumb_x + _thumb_w, _thumb_y + _thumb_h, false);
	            draw_set_color(make_color_rgb(80,80,80));
	            draw_rectangle(_thumb_x, _thumb_y, _thumb_x + _thumb_w, _thumb_y + _thumb_h, true);
	            draw_set_font(fnt_c64_tiny);
	            draw_set_color(make_color_rgb(80,80,80));
	            draw_set_halign(fa_center);
	            draw_text(_thumb_x + _thumb_w * 0.5, _thumb_y + _thumb_h * 0.5 - 4, "NO FILE LOADED");
	            draw_set_halign(fa_left);
	            _cy = _thumb_y + _thumb_h + 8;
				
				
				
	        }
	        gpu_set_texfilter(_bmp_prev_filter);
			
			// ══ PREVIEW WINDOW DRAW — rendered last so it sits over everything ══
	        if (_asset.meta.prev_win_visible && _has_canvas) {
	            // ── SHADOW ────────────────────────────────────────────────────────
	            draw_set_alpha(0.45);
	            draw_set_color(c_black);
	            draw_rectangle(_pw_x + 4, _pw_y + 4, _pw_x + _pw_w + 4, _pw_y + _hdr_h + _pw_h + 4, false);
	            draw_set_alpha(1);

	            // ── TITLE BAR ─────────────────────────────────────────────────────
	            draw_set_color(_asset.meta.prev_win_drag ? make_color_rgb(50,50,90) : make_color_rgb(30,30,55));
	            draw_rectangle(_pw_x, _pw_y, _pw_x + _pw_w, _pw_y + _hdr_h, false);
	            draw_set_color(make_color_rgb(80, 80, 140));
	            draw_rectangle(_pw_x, _pw_y, _pw_x + _pw_w, _pw_y + _hdr_h, true);
	            draw_set_color(_asset.meta.prev_win_drag ? c_yellow : c_ltgray);
	            draw_set_font(fnt_c64_tiny);
	            draw_text(_pw_x + 6, _pw_y + (_hdr_h * 0.15), "PREVIEW  320x200  --- drag to move "+string(_pw_x)+":"+string(_pw_y));

	            // ── CANVAS BORDER ─────────────────────────────────────────────────
	            draw_set_color(make_color_rgb(80,80,140));
	            draw_rectangle(_pw_x - 1, _pw_y + _hdr_h - 1, _pw_x + _draw_w + 1, _pw_y + _hdr_h + _draw_h + 1, true);

	            // ── BITMAP ────────────────────────────────────────────────────────
	            if (!_asset.meta.prev_win_drag) {
	                if (variable_struct_exists(_asset.meta, "preview_surf") && surface_exists(_asset.meta.preview_surf)) {
	                gpu_set_texfilter(false);
	                draw_surface_stretched(_asset.meta.preview_surf, _pw_x, _pw_y + _hdr_h, _draw_w, _draw_h);
	                gpu_set_texfilter(_bmp_prev_filter);
	                }
	            } else {
	                // While dragging just show a placeholder so it's snappy
	                draw_set_color(make_color_rgb(20,20,35));
	                draw_rectangle(_pw_x, _pw_y + _hdr_h, _pw_x + _draw_w, _pw_y + _hdr_h + _draw_h, false);
	                draw_set_color(make_color_rgb(60,60,100));
	                draw_text(_pw_x + _draw_w * 0.5 - 20, _pw_y + _hdr_h + _draw_h * 0.5 - 6, "MOVING...");
	            }
	        }
	        // ══ END PREVIEW WINDOW DRAW ══════════════════════════════════════════
			
	    } break;
		
case "BYTE_DATA": {
    var _sf_on   = variable_struct_exists(_asset.meta, "is_save_file") && _asset.meta.is_save_file;
    var _sfx1    = _vx1 + 10;
    var _sfx2    = _vx1 + 260;
    var _sfy1    = _cy;
    var _sfy2    = _cy + 22;
    var _sf_hov  = point_in_rectangle(_mx, _my, _sfx1, _sfy1, _sfx2, _sfy2);
    draw_set_color(_sf_on
        ? make_color_rgb(200, 120, 40)
        : (_sf_hov ? make_color_rgb(140, 90, 40) : make_color_rgb(70, 50, 25)));
    draw_rectangle(_sfx1, _sfy1, _sfx2, _sfy2, false);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_sfx1 + 125, _sfy1 + 6, "USE AS SAVE FILE: " + (_sf_on ? "ON" : "OFF"));
    draw_set_halign(fa_left);
    if (_sf_hov && mouse_check_button_pressed(mb_left)) {
        _asset.meta.is_save_file = !_sf_on;
        if (_asset.meta.is_save_file) {
            _asset.meta.inline_edit_open = false;
            global.is_any_text_active    = false;
            var _sf_size = variable_struct_exists(_asset.meta, "save_file_size") ? _asset.meta.save_file_size : 256;
            scr_asset_save_file_resize(_asset, _sf_size);
        }
    }
    _cy += 30;

    if (_sf_on) {
        var _bc_sf = buffer_exists(_asset.buffer) ? buffer_get_size(_asset.buffer) : 0;
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_text(_vx1 + 10, _cy, "RESERVED: " + string(_bc_sf) + " BYTES   $"
            + string_upper(decimal_to_hex(_asset.address))
            + " - $" + string_upper(decimal_to_hex(_asset.address + max(0, _bc_sf - 1))));
        _cy += 24;

        var _steps = [
            { label: "-256", delta: -256 }, { label: "-16", delta: -16 }, { label: "-1", delta: -1 },
            { label: "+1",   delta: 1    }, { label: "+16", delta: 16  }, { label: "+256", delta: 256 }
        ];
        var _stp_x = _vx1 + 10;
        for (var _si = 0; _si < array_length(_steps); _si++) {
            var _stp_w   = 44;
            var _stp_x1  = _stp_x + (_si * (_stp_w + 4));
            var _stp_x2  = _stp_x1 + _stp_w;
            var _stp_hov = point_in_rectangle(_mx, _my, _stp_x1, _cy, _stp_x2, _cy + 22);
            draw_set_color(_stp_hov ? make_color_rgb(200, 120, 40) : make_color_rgb(70, 50, 25));
            draw_rectangle(_stp_x1, _cy, _stp_x2, _cy + 22, false);
            draw_set_color(c_white);
            draw_set_halign(fa_center);
            draw_text(_stp_x1 + (_stp_w / 2), _cy + 6, _steps[_si].label);
            draw_set_halign(fa_left);
            if (_stp_hov && mouse_check_button_pressed(mb_left)) {
                var _new_size = clamp(_bc_sf + _steps[_si].delta, 1, 16384);
                _asset.meta.save_file_size = _new_size;
                scr_asset_save_file_resize(_asset, _new_size);
            }
        }
        _cy += 34;
        draw_set_font(fnt_C64_Angled);
        draw_set_color(c_ltgray);
        draw_text(_vx1 + 10, _cy, "Zero-filled placeholder — link into a LOAD_ORG,");
        _cy += 16;
        draw_text(_vx1 + 10, _cy, "then MACRO_SAVE_GAME/MACRO_LOAD_GAME write and");
        _cy += 16;
        draw_text(_vx1 + 10, _cy, "read this exact address range at runtime.");
        _cy += 16;
    } else {
    // ── EDIT BUTTON ──────────────────────────────────────────────────────
	

    var _ebx1   = _vx1 + 10;
    var _ebx2   = _vx1 + 80;
    var _eby1   = _cy;
    var _eby2   = _cy + 22;
    var _eb_hov = point_in_rectangle(_mx, _my, _ebx1, _eby1, _ebx2, _eby2);
    var _ed_open = _asset.meta.inline_edit_open;

    draw_set_color(_ed_open
        ? make_color_rgb(120, 60, 200)
        : (_eb_hov ? make_color_rgb(180, 120, 255) : make_color_rgb(70, 40, 120)));
    draw_rectangle(_ebx1, _eby1, _ebx2, _eby2, false);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(_eb_hov ? c_black : c_white);
    draw_set_halign(fa_center);
    draw_text(_ebx1 + 35, _eby1 + 6, _ed_open ? "CLOSE" : "EDIT");
    draw_set_halign(fa_left);

    if (_eb_hov && mouse_check_button_pressed(mb_left)) {
        if (!_ed_open) {
            // Open — load working text from byte_string to preserve original formatting
            var _bstr = "";
            if (variable_struct_exists(_asset.meta, "byte_string") && string_length(string(_asset.meta.byte_string)) > 0) {
                _bstr = string(_asset.meta.byte_string);
            } else if (buffer_exists(_asset.buffer)) {
                var _bsz = buffer_get_size(_asset.buffer);
                for (var _bi = 0; _bi < _bsz; _bi++) {
                    var _bval = buffer_peek(_asset.buffer, _bi, buffer_u8);
                    var _hex  = string_upper(decimal_to_hex(_bval));
                    if (string_length(_hex) < 2) _hex = "0" + _hex;
                    _bstr += "$" + _hex;
                    if (_bi < _bsz - 1) _bstr += ", ";
                }
            }
            _asset.meta.inline_edit_open      = true;
            global.is_any_text_active         = true;
            _asset.meta.inline_edit_text      = _bstr;
            _asset.meta.inline_edit_cursor    = string_length(_bstr);
            _asset.meta.inline_edit_scroll_y  = 0;
            _asset.meta.inline_edit_sel_start = -1;
            _asset.meta.inline_edit_sel_end   = -1;
            _asset.meta.inline_edit_blink     = 0;
            _asset.meta.inline_edit_key_timer = 0;
        } else {
            // Close — parse and save
            scr_asset_byte_data_save(_asset);
            _asset.meta.inline_edit_open = false;
            global.is_any_text_active    = false;
        }
    }

    // ── SAVE BUTTON (only when editor open) ──────────────────────────────
    if (_ed_open) {
        var _sbx1   = _ebx2 + 8;
        var _sbx2   = _sbx1 + 60;
        var _sb_hov = point_in_rectangle(_mx, _my, _sbx1, _eby1, _sbx2, _eby2);
        draw_set_color(_sb_hov ? make_color_rgb(60, 200, 80) : make_color_rgb(20, 100, 40));
        draw_rectangle(_sbx1, _eby1, _sbx2, _eby2, false);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_sbx1 + 30, _eby1 + 6, "SAVE");
        draw_set_halign(fa_left);
        if (_sb_hov && mouse_check_button_pressed(mb_left)) {
            scr_asset_byte_data_save(_asset);
        }
    }

    _cy += 30;

    // ── BYTE COUNT / ADDRESS BAR ──────────────────────────────────────────
    var _bc = buffer_exists(_asset.buffer) ? buffer_get_size(_asset.buffer) : 0;
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(80, 80, 80));
    draw_text(_vx1 + 10, _cy, string(_bc) + " BYTES   $"
        + string_upper(decimal_to_hex(_asset.address))
        + " - $" + string_upper(decimal_to_hex(_asset.address + max(0, _bc - 1))));
    _cy += 38;

    // ── INLINE EDITOR ─────────────────────────────────────────────────────
    if (_ed_open) {
        var _ed_x1 = _vx1 + 180;
        var _ed_x2 = _vx2 - 80;
        var _ed_y1 = _cy - 80;
        var _ed_y2 = _vy2 - 120;
        scr_asset_inline_editor_draw(_asset, _ed_x1, _ed_y1, _ed_x2, _ed_y2,
            _mx, _my, make_color_rgb(180, 120, 255), "BYTE DATA");
        scr_asset_inline_editor_step(_asset, _mx, _my, _ed_x1, _ed_y1, _ed_x2, _ed_y2);
    } else {
        // Preview when closed
        draw_set_font(fnt_C64_Angled);
        draw_set_color(c_ltgray);
        draw_text(_vx1 + 10, _cy, "CONTENT:");
        _cy += 14;
        draw_set_color(make_color_rgb(180, 120, 255));
        var _bstr2 = variable_struct_exists(_asset.meta, "byte_string")
            ? string(_asset.meta.byte_string) : "";
        var _preview = _bstr2;
        if (string_length(_preview) > 600) _preview = string_copy(_preview, 1, 600) + "...";
        
        // Adjust this parameter as needed
        var _linemaxwidth = 1400; 
        var _str_w = string_width(_preview);
        var _xscale = 1;
        
        if (_str_w > _linemaxwidth) {
            _xscale = _linemaxwidth / _str_w;
        }
        
        draw_text_transformed(_vx1 + 10, _cy, _preview, _xscale, 1, 0);
    }
    }
} break;

case "TEXT_DATA": {
    // ── EDIT BUTTON ──────────────────────────────────────────────────────
    var _ebx1   = _vx1 + 10;
    var _ebx2   = _vx1 + 80;
    var _eby1   = _cy;
    var _eby2   = _cy + 22;
    var _eb_hov = point_in_rectangle(_mx, _my, _ebx1, _eby1, _ebx2, _eby2);
    var _ed_open = _asset.meta.inline_edit_open;

    draw_set_color(_ed_open
        ? make_color_rgb(140, 100, 20)
        : (_eb_hov ? make_color_rgb(255, 200, 60) : make_color_rgb(100, 80, 20)));
    draw_rectangle(_ebx1, _eby1, _ebx2, _eby2, false);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(_eb_hov ? c_black : c_white);
    draw_set_halign(fa_center);
    draw_text(_ebx1 + 35, _eby1 + 6, _ed_open ? "CLOSE" : "EDIT");
    draw_set_halign(fa_left);

    if (_eb_hov && mouse_check_button_pressed(mb_left)) {
        if (!_ed_open) {
            var _txt_src = variable_struct_exists(_asset.meta, "text")
                ? string(_asset.meta.text) : "";
            _asset.meta.inline_edit_open      = true;
            global.is_any_text_active         = true;
            _asset.meta.inline_edit_text      = _txt_src;
            _asset.meta.inline_edit_cursor    = string_length(_txt_src);
            _asset.meta.inline_edit_scroll_y  = 0;
            _asset.meta.inline_edit_sel_start = -1;
            _asset.meta.inline_edit_sel_end   = -1;
            _asset.meta.inline_edit_blink     = 0;
            _asset.meta.inline_edit_key_timer = 0;
        } else {
            scr_asset_text_data_save(_asset);
            _asset.meta.inline_edit_open = false;
            global.is_any_text_active    = false;
        }
    }

    // ── SAVE BUTTON ───────────────────────────────────────────────────────
    if (_ed_open) {
        var _sbx1   = _ebx2 + 8;
        var _sbx2   = _sbx1 + 60;
        var _sb_hov = point_in_rectangle(_mx, _my, _sbx1, _eby1, _sbx2, _eby2);
        draw_set_color(_sb_hov ? make_color_rgb(60, 200, 80) : make_color_rgb(20, 100, 40));
        draw_rectangle(_sbx1, _eby1, _sbx2, _eby2, false);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_sbx1 + 30, _eby1 + 6, "SAVE");
        draw_set_halign(fa_left);
        if (_sb_hov && mouse_check_button_pressed(mb_left)) {
            scr_asset_text_data_save(_asset);
        }
    }

    _cy += 30;

    // ── BYTE COUNT / ADDRESS BAR ──────────────────────────────────────────
    var _bc = buffer_exists(_asset.buffer) ? buffer_get_size(_asset.buffer) : 0;
    var _txt_val = variable_struct_exists(_asset.meta, "text") ? string(_asset.meta.text) : "";
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(120, 180, 240));
    draw_text(_vx1 + 10, _cy,
        string(string_length(_txt_val)) + " CHARS   "
        + string(_bc) + " BYTES\n (INC. NULL)");
    _cy += 38;

    // ── CARET / SELECTION OFFSET READOUT (for START/END in MACRO_PRINT) ────
    // Offsets are 0-based into the asset buffer. The editor cursor is a
    // 1-based string position sitting AFTER the caret, so "chars before caret"
    // == the offset a user would type into START.
    if (_ed_open) {
        var _cur_pos = variable_struct_exists(_asset.meta, "inline_edit_cursor")
                     ? real(_asset.meta.inline_edit_cursor) : 0;
        var _sel_s   = variable_struct_exists(_asset.meta, "inline_edit_sel_start")
                     ? real(_asset.meta.inline_edit_sel_start) : -1;
        var _sel_e   = variable_struct_exists(_asset.meta, "inline_edit_sel_end")
                     ? real(_asset.meta.inline_edit_sel_end) : -1;

        draw_set_font(fnt_c64_tiny);
        if (_sel_s >= 0 && _sel_e >= 0 && _sel_s != _sel_e) {
            // A range is selected — show it directly as START -> END + span
            var _lo   = min(_sel_s, _sel_e);
            var _hi   = max(_sel_s, _sel_e);
            var _span = _hi - _lo;
            draw_set_color(c_yellow);
            draw_text(_vx1 + 10, _cy,
                "SEL  START:" + string(_lo) + "  END:" + string(_hi)
                + "\nSPAN:" + string(_span));
            _cy += 12;
            // Span guard for the 8-bit copy loop
            if (_span > 255) {
                draw_set_color(make_color_rgb(230, 70, 70));
                draw_text(_vx1 + 10, _cy, "\nSPAN > 255\nWon't fit one PRINT");
                _cy += 12;
            }
        } else {
            // No selection — just the caret offset
            draw_set_color(make_color_rgb(120, 200, 220));
            draw_text(_vx1 + 10, _cy, "CHAR POS: " + string(_cur_pos));
            _cy += 12;
        }
    }

    // ── INLINE EDITOR ─────────────────────────────────────────────────────
    if (_ed_open) {
		
        var _ed_x1 = _vx1 + 180;
        var _ed_x2 = _vx2 - 80;
        var _ed_y1 = _cy - 80;
        var _ed_y2 = _vy2 - 120;
        scr_asset_inline_editor_draw(_asset, _ed_x1, _ed_y1, _ed_x2, _ed_y2,
            _mx, _my, make_color_rgb(160, 230, 160), "TEXT DATA");
        scr_asset_inline_editor_step(_asset, _mx, _my, _ed_x1, _ed_y1, _ed_x2, _ed_y2);
    } else {
        // Preview when closed
        draw_set_font(fnt_C64_Angled);
        draw_set_color(c_ltgray);
        draw_text(_vx1 + 10, _cy, "CONTENT PREVIEW:");
        _cy += 14;
        draw_set_color(make_color_rgb(160, 230, 160));
        var _preview_lines = string_split(_txt_val, "\n");
        for (var _pli = 0; _pli < min(array_length(_preview_lines), 6); _pli++) {
            var _pl = _preview_lines[_pli];
            if (string_length(_pl) > 600) _pl = string_copy(_pl, 1, 600) + "...";
            draw_text(_vx1 + 10, _cy, _pl);
            _cy += 14;
        }
        if (array_length(_preview_lines) > 20) {
            draw_set_color(make_color_rgb(80, 80, 80));
            draw_text(_vx1 + 10, _cy,
                "(" + string(array_length(_preview_lines) - 6) + " more lines...)");
        }
    }
	// Consume keyboard input so it doesn't leak to other systems —
    // but ONLY when the editor is closed. When it's open, the editor
    // step owns the keyboard buffer and reads it itself.
    if (!_ed_open) {
        keyboard_string = "";
    }

} break;

case "LINE_COLL": {
    // ── TEXT EDIT TOGGLE (bulk paste path — same data as the visual canvas) ──
    var _ebx1   = _vx1 + 10;
    var _ebx2   = _vx1 + 90;
    var _eby1   = _cy;
    var _eby2   = _cy + 22;
    var _eb_hov = point_in_rectangle(_mx, _my, _ebx1, _eby1, _ebx2, _eby2);
    var _ed_open = _asset.meta.inline_edit_open;

    draw_set_color(_ed_open
        ? make_color_rgb(200, 60, 60)
        : (_eb_hov ? make_color_rgb(255, 100, 100) : make_color_rgb(120, 30, 30)));
    draw_rectangle(_ebx1, _eby1, _ebx2, _eby2, false);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(_eb_hov ? c_black : c_white);
    draw_set_halign(fa_center);
    draw_text(_ebx1 + 40, _eby1 + 6, _ed_open ? "CLOSE" : "TEXT EDIT");
    draw_set_halign(fa_left);

    if (_eb_hov && mouse_check_button_pressed(mb_left)) {
        if (!_ed_open) {
            // Open — load working text from line_string to preserve original formatting
            var _lstr = variable_struct_exists(_asset.meta, "line_string") ? string(_asset.meta.line_string) : "";
            _asset.meta.inline_edit_open      = true;
            global.is_any_text_active         = true;
            _asset.meta.inline_edit_text      = _lstr;
            _asset.meta.inline_edit_cursor    = string_length(_lstr);
            _asset.meta.inline_edit_scroll_y  = 0;
            _asset.meta.inline_edit_sel_start = -1;
            _asset.meta.inline_edit_sel_end   = -1;
            _asset.meta.inline_edit_blink     = 0;
            _asset.meta.inline_edit_key_timer = 0;
        } else {
            // Close — parse and save
            scr_line_coll_save(_asset);
            _asset.meta.inline_edit_open = false;
            global.is_any_text_active    = false;
        }
    }

    if (_ed_open) {
        var _sbx1   = _ebx2 + 8;
        var _sbx2   = _sbx1 + 60;
        var _sb_hov = point_in_rectangle(_mx, _my, _sbx1, _eby1, _sbx2, _eby2);
        draw_set_color(_sb_hov ? make_color_rgb(60, 200, 80) : make_color_rgb(20, 100, 40));
        draw_rectangle(_sbx1, _eby1, _sbx2, _eby2, false);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_sbx1 + 30, _eby1 + 6, "SAVE");
        draw_set_halign(fa_left);
        if (_sb_hov && mouse_check_button_pressed(mb_left)) {
            scr_line_coll_save(_asset);
        }
    }

    _cy += 30;

    // ── LINE COUNT / ADDRESS BAR ────────────────────────────────────────
    var _lc_count = variable_struct_exists(_asset.meta, "lines") ? array_length(_asset.meta.lines) : 0;
    var _lc_bytes = (_lc_count * 6) + 3; // 6 bytes/record + 3-byte sentinel
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(80, 80, 80));
    draw_text(_vx1 + 10, _cy, string(_lc_count) + " LINES   " + string(_lc_bytes) + " BYTES   $"
        + string_upper(decimal_to_hex(_asset.address))
        + " - $" + string_upper(decimal_to_hex(_asset.address + max(0, _lc_bytes - 1))));
    _cy += 30;

    if (_ed_open) {
        // ── TEXT EDITOR (bulk paste) ────────────────────────────────────
        var _ed_x1 = _vx1 + 180;
        var _ed_x2 = _vx2 - 80;
        var _ed_y1 = _cy - 20;
        var _ed_y2 = _vy2 - 120;
        scr_asset_inline_editor_draw(_asset, _ed_x1, _ed_y1, _ed_x2, _ed_y2,
            _mx, _my, make_color_rgb(255, 100, 100), "LINE COLL DATA (x1,y1,x2,y2,type)");
        scr_asset_inline_editor_step(_asset, _mx, _my, _ed_x1, _ed_y1, _ed_x2, _ed_y2);
        keyboard_string = ""; // editor step owns the keyboard buffer while open
    } else {
        // ── VISUAL CANVAS EDITOR ─────────────────────────────────────────
        scr_line_coll_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my);
    }
} break;

case "SID_MUSIC": {
            if (!buffer_exists(_asset.buffer)) {
                draw_set_font(fnt_c64_tiny);
                draw_set_color(make_color_rgb(80, 80, 80));
                draw_text(_vx1 + 10, _cy, "NO FILE LOADED");
                _cy += 16;
                break;
            }
            var _sid_sz   = buffer_get_size(_asset.buffer);
            var _sid_data = variable_struct_exists(_asset.meta, "sid_data_start") ? _asset.meta.sid_data_start : 0x76;
            var _sid_len  = _sid_sz - _sid_data;
            var _sid_end  = _asset.address + _sid_len - 1;
            var _init_hex = string_upper(decimal_to_hex(variable_struct_exists(_asset.meta, "sid_init_addr") ? _asset.meta.sid_init_addr : _asset.address));
            var _play_hex = string_upper(decimal_to_hex(variable_struct_exists(_asset.meta, "sid_play_addr") ? _asset.meta.sid_play_addr : _asset.address + 3));
            var _end_hex  = string_upper(decimal_to_hex(_sid_end));
            while (string_length(_init_hex) < 4) _init_hex = "0" + _init_hex;
            while (string_length(_play_hex) < 4) _play_hex = "0" + _play_hex;
            while (string_length(_end_hex)  < 4) _end_hex  = "0" + _end_hex;
            draw_set_font(fnt_c64_tiny);
            draw_set_color(c_ltgray);  draw_text(_vx1 + 10, _cy, "INIT:");
            draw_set_color(c_aqua);    draw_text(_vx1 + 60, _cy, "$" + _init_hex);
            draw_set_color(c_ltgray);  draw_text(_vx1 + 140, _cy, "PLAY:");
            draw_set_color(c_aqua);    draw_text(_vx1 + 190, _cy, "$" + _play_hex);
            _cy += 16;
            draw_set_color(c_ltgray);  draw_text(_vx1 + 10, _cy, "SIZE:");
            draw_set_color(c_white);   draw_text(_vx1 + 60, _cy, string(_sid_len) + " BYTES");
            draw_set_color(c_ltgray);  draw_text(_vx1 + 140, _cy, "END:");
            draw_set_color(c_aqua);    draw_text(_vx1 + 190, _cy, "$" + _end_hex);
            _cy += 20;
        } break;
	
case "LOAD_REU": {
    scr_reu_repack(_asset);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_ltgray); draw_text(_vx1 + 10, _cy, "REU IMAGE:");
    draw_set_color(make_color_rgb(100,200,180)); draw_text(_vx1 + 90, _cy, variable_struct_exists(_asset,"reu_filename") ? _asset.reu_filename : _asset.name + ".reu");
    _cy += 20;
    var _used = variable_struct_exists(_asset,"reu_used") ? _asset.reu_used : 0x100;
    draw_set_color(c_ltgray); draw_text(_vx1 + 10, _cy, "TARGET: 16 MB     USED: " + string(_used) + " BYTES");
    _cy += 22;
    scr_draw_reu_memory_bar(_vx1 + 10, _vx2 - 10, _cy, _asset);
    _cy += 40;
    var _cn=_vx1+30, _cc=_vx1+190, _cr=_vx1+280, _cs=_vx1+380, _cm=_vx1+465, _ci=_cm+95;
    draw_set_color(make_color_rgb(120,120,140));
    draw_text(_cn,_cy,"ASSET"); draw_text(_cc,_cy,"C64"); draw_text(_cr,_cy,"REU"); draw_text(_cs,_cy,"BYTES"); draw_text(_cm,_cy,"PACK"); draw_text(_ci,_cy,"IDX");
    _cy += 14;
    var _links=variable_struct_exists(_asset,"linked_assets")?_asset.linked_assets:[];
    load_reu_rows_y = _cy;
    var _bmp_idx = 0;
    for(var _li=0;_li<array_length(_links);_li++){
        var _lk=_links[_li], _la=scr_reu_find_asset(_lk.asset_name), _pl=scr_reu_asset_payload(_la);
        var _la_type    = is_undefined(_la) ? "" : _la.type;
        var _is_dragged = (reu_drag_row == _li);
        if (_is_dragged) draw_set_alpha(0.4);
        draw_set_color((_li mod 2==0)?make_color_rgb(22,30,34):make_color_rgb(18,25,29)); draw_rectangle(_vx1+8,_cy,_vx2-8,_cy+20,false);
        draw_set_color(make_color_rgb(130,150,200)); draw_text(_vx1+9,_cy+4,":::");
        draw_set_color(c_white); draw_text(_cn,_cy+4,_lk.asset_name);
        var _ch=is_undefined(_la)?"----":string_upper(decimal_to_hex(_la.address)); while(string_length(_ch)<4)_ch="0"+_ch;
        var _rh=string_upper(decimal_to_hex(real(_lk.reu_address))); while(string_length(_rh)<6)_rh="0"+_rh;
        draw_set_color(c_yellow); draw_text(_cc,_cy+4,"$"+_ch);
        var _conflict=variable_struct_exists(_lk,"reu_conflict")?_lk.reu_conflict:false;
        draw_set_color(_conflict?c_red:c_aqua); draw_text(_cr,_cy+4,"$"+_rh);
        draw_set_color(c_lime); draw_text(_cs,_cy+4,string(_pl.size));
        if(buffer_exists(_pl.buffer))buffer_delete(_pl.buffer);
        var _auto=variable_struct_exists(_lk,"auto_pack")?_lk.auto_pack:true;
        draw_set_color(_auto?make_color_rgb(25,80,55):make_color_rgb(90,65,25)); draw_rectangle(_cm,_cy+2,_cm+45,_cy+18,false);
        draw_set_color(c_white); draw_set_halign(fa_center); draw_text(_cm+22,_cy+4,_auto?"AUTO":"MAN"); draw_set_halign(fa_left);
        draw_set_color(make_color_rgb(45,55,65)); draw_rectangle(_cm+48,_cy+2,_cm+64,_cy+18,false); draw_rectangle(_cm+66,_cy+2,_cm+82,_cy+18,false);
        draw_set_color(c_white); draw_text(_cm+53,_cy+4,"-"); draw_text(_cm+71,_cy+4,"+");
        // IDX: position within MACRO_REU INDEXED mode's table — bitmaps only,
        // in link order, matching scr_compile_chain's filter exactly.
        var _is_bmp = !is_undefined(_la) && (_la.type == "BITMAP" || _la.type == "BITMAP_KLA");
        if (_is_bmp) {
            draw_set_color(c_white); draw_text(_ci,_cy+4,string(_bmp_idx));
            _bmp_idx++;
        } else {
            draw_set_color(make_color_rgb(90,90,100)); draw_text(_ci,_cy+4,"--");
        }
        draw_set_color(make_color_rgb(100,30,30)); draw_rectangle(_vx2-26,_cy+2,_vx2-8,_cy+18,false); draw_set_color(c_white); draw_text(_vx2-21,_cy+4,"X");
        draw_set_alpha(1.0);
        if (reu_drag_row >= 0 && !_is_dragged && _la_type != reu_drag_type) {
            draw_set_color(c_red); draw_set_alpha(0.15);
            draw_rectangle(_vx1+8,_cy,_vx2-8,_cy+20,false);
            draw_set_alpha(1.0);
        }
        if (reu_drag_row >= 0 && reu_drag_over == _li) {
            draw_set_color(c_yellow);
            draw_line(_vx1+8,_cy,_vx2-8,_cy);
        }
        _cy+=22;
    }
    load_reu_add_y = _cy;
    var _hov=point_in_rectangle(_mx,_my,_vx1+10,_cy,_vx1+90,_cy+20);
    draw_set_color(_hov?make_color_rgb(45,150,100):make_color_rgb(25,75,55)); draw_rectangle(_vx1+10,_cy+2,_vx1+90,_cy+20,false);
    draw_set_color(c_white); draw_set_halign(fa_center); draw_text(_vx1+50,_cy+5,"[+ ADD]"); draw_set_halign(fa_left);
    draw_set_color(make_color_rgb(40,70,90)); draw_rectangle(_vx1+100,_cy+2,_vx1+200,_cy+20,false); draw_set_color(c_white); draw_set_halign(fa_center); draw_text(_vx1+150,_cy+5,"[AUTO PACK]"); draw_set_halign(fa_left);
    _cy += 28;
} break;

case "LOAD_ORG": {
    // D64 filename row
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_ltgray);
    draw_text(_vx1 + 10, _cy, "D64 NAME:");
    var _dname = variable_struct_exists(_asset, "d64_filename") ? _asset.d64_filename : "";
    draw_set_color(make_color_rgb(200, 160, 40));
    draw_text(_vx1 + 80, _cy, _dname != "" ? _dname : "-- NOT SET --");
    _cy += 20;

    // Linked assets list
    draw_set_color(c_ltgray);
    draw_set_font(fnt_c64_tiny);
    draw_text(_vx1 + 10, _cy, "D64 CONTENTS:");
    _cy += 18;

    // Column header strip
    var _col_name   = _vx1 + 16;
    var _col_d64    = _vx1 + 160;
    var _col_bytes  = _vx1 + 320;
    var _col_blocks = _vx1 + 400;
    var _col_start  = _vx1 + 470;
    var _col_end    = _vx1 + 550;
    var _col_badge  = _vx2 - 60;
    var _col_x      = _vx2 - 26;

    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(120, 120, 140));
    draw_text(_col_name,   _cy, "ASSET");
    draw_text(_col_d64,    _cy, "D64 FILE");
    draw_text(_col_bytes,  _cy, "BYTES");
    draw_text(_col_blocks, _cy, "BLOCKS");
    draw_text(_col_start,  _cy, "$START");
    draw_text(_col_end,    _cy, "$END");
    _cy += 14;

    // Track totals for the summary line
    var _tot_bytes_now    = 0;
    var _tot_blocks_now   = 0;
    var _tot_bytes_later  = 0;
    var _tot_blocks_later = 0;
    var _link_count_now   = 0;
    var _link_count_later = 0;

    var _links = variable_struct_exists(_asset, "linked_assets") ? _asset.linked_assets : [];
    for (var _li = 0; _li < array_length(_links); _li++) {
        var _link   = _links[_li];
        var _lname  = _link.asset_name;
        var _ld64   = variable_struct_exists(_link, "d64_filename") ? _link.d64_filename : string_upper(_lname);
        var _lll    = variable_struct_exists(_link, "load_later")   ? _link.load_later   : false;

        // Look up the actual asset for size/address info
        var _la_tcol     = c_gray;
        var _link_bytes  = 0;
        var _link_start  = -1;
        var _link_end    = -1;
        var _link_type   = "";
        for (var _lti = 0; _lti < ds_list_size(asset_list); _lti++) {
            var _lta = ds_list_find_value(asset_list, _lti);
            if (_lta.name != _lname) continue;
            _link_type = _lta.type;
            _la_tcol = variable_struct_exists(type_colours, _lta.type)
                     ? variable_struct_get(type_colours, _lta.type) : c_gray;
            if (_lta.type == "BITMAP" || _lta.type == "BITMAP_KLA") {
                        _link_bytes = 0x27D0;
                    } else if (_lta.type == "SFX_DATA" && variable_struct_exists(_lta.meta, "instruments")) {
                        var _sfx_instrs = _lta.meta.instruments;
                        var _sfx_sz = 0;
                        for (var _sfi = 0; _sfi < array_length(_sfx_instrs); _sfi++) {
                            _sfx_sz += 3 + array_length(_sfx_instrs[_sfi].wavetable_rows) * 2;
                        }
                        _link_bytes = max(_sfx_sz, 1);
                    } else if (buffer_exists(_lta.buffer)) {
                        _link_bytes = buffer_get_size(_lta.buffer);
                    }
            _link_start = _lta.address;
            if (_link_start >= 0 && _link_bytes > 0) {
                _link_end = _link_start + _link_bytes - 1;
            }
            break;
        }
        // .d64 sector blocks: each holds 254 data bytes (+2 link bytes)
        var _link_blocks = (_link_bytes > 0) ? ceil(_link_bytes / 254) : 0;

        // Accumulate totals
        if (_lll) {
            _tot_bytes_later  += _link_bytes;
            _tot_blocks_later += _link_blocks;
            _link_count_later++;
        } else {
            _tot_bytes_now    += _link_bytes;
            _tot_blocks_now   += _link_blocks;
            _link_count_now++;
        }

        // Row background
        draw_set_color((_li mod 2 == 0) ? make_color_rgb(22, 22, 35) : make_color_rgb(18, 18, 28));
        draw_rectangle(_vx1 + 8, _cy, _vx2 - 8, _cy + 20, false);

        // Asset type colour tag
        draw_set_color(_la_tcol);
        draw_rectangle(_vx1 + 8, _cy, _vx1 + 12, _cy + 20, false);

        // Asset name
        draw_set_font(fnt_c64_code);
        draw_set_color(c_white);
        draw_text(_col_name, _cy + 3, _lname);

        // D64 filename
        draw_set_color(make_color_rgb(200, 160, 40));
        draw_text(_col_d64, _cy + 3, "→ " + _ld64);

        // Size info — only show if we actually found the asset
        draw_set_font(fnt_c64_tiny);
        if (_link_bytes > 0) {
            // BYTES
            draw_set_color(make_color_rgb(180, 200, 220));
            draw_text(_col_bytes, _cy + 5, string(_link_bytes));
            // BLOCKS
            draw_set_color(make_color_rgb(140, 200, 140));
            draw_text(_col_blocks, _cy + 5, string(_link_blocks));
            // $START
            if (_link_start >= 0) {
                var _hs = decimal_to_hex(_link_start);
                while (string_length(_hs) < 4) _hs = "0" + _hs;
                draw_set_color(make_color_rgb(120, 200, 240));
                draw_text(_col_start, _cy + 5, "$" + string_upper(_hs));
            }
            // $END
            if (_link_end >= 0) {
                var _he = decimal_to_hex(_link_end);
                while (string_length(_he) < 4) _he = "0" + _he;
                draw_set_color(make_color_rgb(120, 200, 240));
                draw_text(_col_end, _cy + 5, "$" + string_upper(_he));
            }
        } else {
            // Asset not found / no buffer
            draw_set_color(make_color_rgb(180, 80, 80));
            draw_text(_col_bytes, _cy + 5, "MISSING");
        }

        // load_later badge
        if (_lll) {
            draw_set_color(make_color_rgb(60, 100, 200));
            draw_rectangle(_vx2 - 60, _cy + 2, _vx2 - 28, _cy + 18, false);
            draw_set_font(fnt_c64_tiny);
            draw_set_color(c_white);
            draw_set_halign(fa_center);
            draw_text(_vx2 - 44, _cy + 5, "DISK");
            draw_set_halign(fa_left);
        }

        // Remove button (X)
        draw_set_color(make_color_rgb(100, 30, 30));
        draw_rectangle(_vx2 - 8, _cy + 2, _vx2 - 26, _cy + 18, false);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_vx2 - 17, _cy + 5, "X");
        draw_set_halign(fa_left);

        _cy += 22;
    }

    // ADD button
    var _abx1   = _vx1 + 10;
    var _abx2   = _vx1 + 80;
    var _aby1   = _cy;
    var _aby2   = _cy + 20;
    var _ab_hov = point_in_rectangle(_mx, _my, _abx1, _aby1, _abx2, _aby2);
    draw_set_color(_ab_hov ? make_color_rgb(60, 180, 80) : make_color_rgb(25, 70, 35));
    draw_rectangle(_abx1, _aby1+4, _abx2, _aby2+2, false);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_abx1 + 35, _aby1 + 5, "[+ ADD]");
    draw_set_halign(fa_left);
    _cy += 28;

    // -------------------------------------------------
    // D64 SUMMARY PANEL
    // -------------------------------------------------
    if (array_length(_links) > 0) {
        var _sum_y1 = _cy;
        var _sum_y2 = _cy + 104;
        draw_set_color(make_color_rgb(15, 15, 25));
        draw_rectangle(_vx1 + 8, _sum_y1, _vx2 - 8, _sum_y2, false);
        draw_set_color(make_color_rgb(50, 50, 70));
        draw_rectangle(_vx1 + 8, _sum_y1, _vx2 - 8, _sum_y2, true);

        // Header
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(200, 160, 40));
        draw_text(_vx1 + 16, _sum_y1 + 6, "D64 SUMMARY");

        // BOOT-time loads (not load_later)
        draw_set_color(c_ltgray);
        draw_text(_vx1 + 16, _sum_y1 + 22,
            "BOOT LOAD : " + string(_link_count_now) + " file(s)   "
            + string(_tot_bytes_now)  + " bytes   "
            + string(_tot_blocks_now) + " blocks");

        // Disk-loaded later
        if (_link_count_later > 0) {
            draw_set_color(make_color_rgb(120, 160, 220));
            draw_text(_vx1 + 16, _sum_y1 + 36,
                "ON DEMAND : " + string(_link_count_later) + " file(s)   "
                + string(_tot_bytes_later)  + " bytes   "
                + string(_tot_blocks_later) + " blocks");
        }

        // BOOT PRG size from last build (assembled code + 15-byte PRG/BASIC header)
        // global.last_bytes is populated by the F5 build path.
        var _boot_bytes  = 0;
        var _boot_blocks = 0;
        if (variable_global_exists("last_bytes") && is_array(global.last_bytes)) {
            // Same trim logic as scr_build_d64 — exclude LOAD_ORG asset regions
            // and trailing zero padding so we report what actually goes to disk.
            var _load_ranges_b = [];
            if (instance_exists(obj_asset_manager)) {
                for (var _lab = 0; _lab < ds_list_size(asset_list); _lab++) {
                    var _la_b = ds_list_find_value(asset_list, _lab);
                    if (_la_b.type != "LOAD_ORG") continue;
                    if (!variable_struct_exists(_la_b, "linked_assets")) continue;
                    var _ll_b = _la_b.linked_assets;
                    for (var _lli_b = 0; _lli_b < array_length(_ll_b); _lli_b++) {
                        var _lnk_b = _ll_b[_lli_b];
                        if (variable_struct_exists(_lnk_b, "load_later") && _lnk_b.load_later) continue;
                        var _lnk_name_b = _lnk_b.asset_name;
                        for (var _lbb = 0; _lbb < ds_list_size(asset_list); _lbb++) {
                            var _lb_b = ds_list_find_value(asset_list, _lbb);
                            if (_lb_b.name != _lnk_name_b) continue;
                            if (!buffer_exists(_lb_b.buffer)) break;
                            var _ls_b = _lb_b.address;
                            var _le_b = _ls_b + buffer_get_size(_lb_b.buffer);
                            if (_lb_b.type == "BITMAP") {
                                _le_b = _ls_b + 0x27D0;
                            }
                            array_push(_load_ranges_b, { s: _ls_b, e: _le_b });
                            break;
                        }
                    }
                }
            }

            var _bb_len     = array_length(global.last_bytes);
            var _bb_pc      = global.start_pc;
            var _bb_end_idx = -1;

            // Walk backwards looking for the last byte that:
            //  (a) is NOT inside a LOAD_ORG asset region
            //  (b) is non-zero
            for (var _bbi = _bb_len - 1; _bbi >= 0; _bbi--) {
                var _bb_addr = _bb_pc + _bbi;
                var _bb_in   = false;
                for (var _bri = 0; _bri < array_length(_load_ranges_b); _bri++) {
                    if (_bb_addr >= _load_ranges_b[_bri].s && _bb_addr < _load_ranges_b[_bri].e) {
                        _bb_in = true;
                        break;
                    }
                }
                if (_bb_in) continue;
                if (global.last_bytes[_bbi] == 0) continue;
                _bb_end_idx = _bbi;
                break;
            }

            var _bb_trim = 0;
            if (_bb_end_idx >= 0) {
                _bb_trim = _bb_end_idx + 1;
            }

            // FAIL-SAFE: walk forwards from the spine end address (highest non-ORG
            // pc_address on the spine chain) to make sure we include any trailing
            // RTS/RTI even if it happens to be the last real byte. Also catches
            // cases where the backwards walk gives a smaller answer than the
            // spine clearly produced.
            var _spine_high_addr = _bb_pc;
            for (var _shi = 0; _shi < ds_list_size(global.node_chain); _shi++) {
                var _shn = ds_list_find_value(global.node_chain, _shi);
                if (!instance_exists(_shn)) continue;
                if (_shn.node_type == "ORG") continue;
                var _shn_end = _shn.pc_address + _shn.total_node_size;
                if (_shn_end > _spine_high_addr) _spine_high_addr = _shn_end;
            }
            var _spine_trim = max(0, _spine_high_addr - _bb_pc);
            if (_spine_trim > _bb_trim) _bb_trim = _spine_trim;

            _boot_bytes  = 15 + _bb_trim; // 2-byte PRG header + 13-byte BASIC stub + code
            if (_boot_bytes > 0) {
                _boot_blocks = ceil(_boot_bytes / 254);
            }

            show_debug_message("BOOT SUMMARY: last_bytes len=" + string(_bb_len)
                + " start_pc=$" + string_upper(decimal_to_hex(_bb_pc))
                + " backwards_trim=" + string(_bb_end_idx + 1)
                + " spine_high=$" + string_upper(decimal_to_hex(_spine_high_addr))
                + " spine_trim=" + string(_spine_trim)
                + " final_trim=" + string(_bb_trim)
                + " boot_bytes=" + string(_boot_bytes)
                + " blocks=" + string(_boot_blocks));
        }

        // D64 capacity (664 blocks usable on a standard 35-track disk)
        var _tot_blocks_all = _tot_blocks_now + _tot_blocks_later + _boot_blocks;
        var _d64_cap        = 664;
        var _free_blocks    = max(0, _d64_cap - _tot_blocks_all);
        var _pct_used       = (_tot_blocks_all / _d64_cap) * 100;

        // BOOT line
        draw_set_color(make_color_rgb(200, 220, 160));
        if (_boot_bytes > 0) {
            draw_text(_vx1 + 16, _sum_y1 + 52,
                "BOOT PRG  : " + string(_boot_bytes)  + " bytes   "
                + string(_boot_blocks) + " blocks   (build first to update)");
        } else {
            draw_text(_vx1 + 16, _sum_y1 + 52,
                "BOOT PRG  : -- not built yet --");
        }

        draw_set_color(c_ltgray);
        draw_text(_vx1 + 16, _sum_y1 + 66,
            "DISK USE  : " + string(_tot_blocks_all) + " / " + string(_d64_cap)
            + " blocks   (" + string_format(_pct_used, 1, 1) + "%)   "
            + string(_free_blocks) + " free");

        // Capacity bar
        var _bar_x1 = _vx1 + 16;
        var _bar_x2 = _vx2 - 16;
        var _bar_y1 = _sum_y1 + 84;
        var _bar_y2 = _bar_y1 + 12;
        draw_set_color(make_color_rgb(30, 30, 45));
        draw_rectangle(_bar_x1, _bar_y1, _bar_x2, _bar_y2, false);

        var _bar_w     = _bar_x2 - _bar_x1;
        var _fill_frac = clamp(_tot_blocks_all / _d64_cap, 0, 1);
var _bar_col = make_color_rgb(80, 180, 100);
        if (_pct_used > 70) {
            _bar_col = make_color_rgb(220, 180, 60);
        }
        if (_pct_used > 90) {
            _bar_col = make_color_rgb(220, 80, 80);
        }
        draw_set_color(_bar_col);
        draw_rectangle(_bar_x1, _bar_y1, _bar_x1 + (_bar_w * _fill_frac), _bar_y2, false);
        draw_set_color(make_color_rgb(60, 60, 80));
        draw_rectangle(_bar_x1, _bar_y1, _bar_x2, _bar_y2, true);

        _cy = _sum_y2 + 10;
    }
} break;
	
case "META_TILESET": {
    var _m = _asset.meta;

    // ============================================================
    // 9b ROUTE: stamp_data is now 1 BYTE PER CELL (char index only).
    // Cell colour + mode come from char_lut[char]:
    //   char_lut[char] = (mc << 4) | (colour & 0x0F)   bit4 = MC, bits0-3 = colour
    // Painting a char BAKES its colour into char_lut[char], so it updates that
    // char everywhere it appears. Per-stamp stamp_override ($80 = none) still
    // forces one colour across a whole stamp at plot time.
    // active_stamp_grid_col / active_stamp_grid_ov are retired stubs (kept
    // allocated so nothing crashes, but no longer a colour source).
    // ============================================================

    // Helper: read a char's baked colour from char_lut (raw nibble, unmasked)
    var _clut_col = function(_mm, _ch) {
        if (_ch < array_length(_mm.char_lut)) return _mm.char_lut[_ch] & 0x0F;
        return 0;
    };
    // Helper: read a char's MC flag from char_lut (bit 4)
    var _clut_mc = function(_mm, _ch) {
        if (_ch < array_length(_mm.char_lut)) return (_mm.char_lut[_ch] >> 4) & 0x01;
        return 0;
    };

    // Write the live edit grid back into the selected stamp's stamp_data slot.
    // 1 byte/cell: just the char index. Colour/mode live in char_lut.
    var _sync_active_to_stamp = function(_mm) {
        if (_mm.edit_stamp < 0) return;
        var _cells_s = _mm.stamp_w * _mm.stamp_h;
        var _woff_s  = _mm.edit_stamp * _cells_s;
        if (_woff_s + _cells_s > array_length(_mm.stamp_data)) return;
        for (var _wi_s = 0; _wi_s < _cells_s; _wi_s++) {
            _mm.stamp_data[_woff_s + _wi_s] = _mm.active_stamp_grid_char[_wi_s];
        }
        _mm.is_dirty = true;
    };

    // ---- STAMP SIZE PICKERS ----
    // Size stays editable while there are no stamps, OR exactly one stamp that
    // hasn't been painted yet (all chars 0). Painting or adding a 2nd locks it.
    var _size_unlocked = (_m.stamp_count == 0);
    if (_m.stamp_count == 1) {
        var _su_cells = _m.stamp_w * _m.stamp_h;
        var _su_painted = false;
        for (var _su_i = 0; _su_i < _su_cells; _su_i++) {
            if (_su_i < array_length(_m.stamp_data) && _m.stamp_data[_su_i] != 0) {
                _su_painted = true;
                break;
            }
        }
        if (!_su_painted) _size_unlocked = true;
    }
    var _szx1  = _vx1 + 160;
    var _szby1 = _vy1 + 38;
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_ltgray);
    draw_text(_szx1 +8 , _szby1 + 5, "STAMP SIZE:");

    // X picker
    var _xbx1   = _szx1 + 90;
    var _xbx2   = _xbx1 + 14;
    var _xbhov  = point_in_rectangle(_mx, _my, _xbx1, _szby1, _xbx2, _szby1 + 18);
    draw_set_color(_xbhov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_xbx1, _szby1, _xbx2, _szby1 + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_xbx1 + 7, _szby1 + 4, "-");
    if (_xbhov && mouse_check_button_pressed(mb_left) && _size_unlocked) {
        _m.stamp_w = max(1, _m.stamp_w - 1);
    }

    draw_set_color(c_aqua);
    draw_text(_xbx2 + 10, _szby1 + 4, string(_m.stamp_w));

    var _xbx3   = _xbx2 + 22;
    var _xbx4   = _xbx3 + 14;
    var _xbhov2 = point_in_rectangle(_mx, _my, _xbx3, _szby1, _xbx4, _szby1 + 18);
    draw_set_color(_xbhov2 ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_xbx3, _szby1, _xbx4, _szby1 + 18, false);
    draw_set_color(c_white);
    draw_text(_xbx3 + 7, _szby1 + 4, "+");
    draw_set_halign(fa_left);
    if (_xbhov2 && mouse_check_button_pressed(mb_left) && _size_unlocked) {
        _m.stamp_w = min(8, _m.stamp_w + 1);
    }

    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_ltgray);
    draw_set_halign(fa_center);
    draw_text(_xbx2 + 50, _szby1 + 4, "x");

    // Y picker
    var _ybx1   = _xbx2 + 60;
    var _ybx2   = _ybx1 + 14;
    var _ybhov  = point_in_rectangle(_mx, _my, _ybx1, _szby1, _ybx2, _szby1 + 18);
    draw_set_color(_ybhov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_ybx1, _szby1, _ybx2, _szby1 + 18, false);
    draw_set_color(c_white);
    draw_text(_ybx1 + 7, _szby1 + 4, "-");
   if (_ybhov && mouse_check_button_pressed(mb_left) && _size_unlocked) {
        _m.stamp_h = max(1, _m.stamp_h - 1);
    }

    draw_set_color(c_aqua);
    draw_text(_ybx2 + 10, _szby1 + 4, string(_m.stamp_h));

    var _ybx3   = _ybx2 + 22;
    var _ybx4   = _ybx3 + 14;
    var _ybhov2 = point_in_rectangle(_mx, _my, _ybx3, _szby1, _ybx4, _szby1 + 18);
    draw_set_color(_ybhov2 ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_ybx3, _szby1, _ybx4, _szby1 + 18, false);
    draw_set_color(c_white);
    draw_text(_ybx3 + 7, _szby1 + 4, "+");
    draw_set_halign(fa_left);
   if (_ybhov2 && mouse_check_button_pressed(mb_left) && _size_unlocked) {
        _m.stamp_h = min(8, _m.stamp_h + 1);
    }

    // Re-fit the single untouched stamp if the size pickers just changed.
    // Only runs while unlocked (1 unpainted stamp), so it can't clobber data.
    // 1 byte/cell now.
    if (_size_unlocked && _m.stamp_count == 1) {
        var _need_cells = _m.stamp_w * _m.stamp_h;
        if (array_length(_m.stamp_data) != _need_cells) {
            _m.stamp_data = [];
            for (var _rf = 0; _rf < _need_cells; _rf++) {
                array_push(_m.stamp_data, 0);   // char only
            }
            _m.active_stamp_grid_char = array_create(_need_cells, 0);
            _m.active_stamp_grid_col  = array_create(_need_cells, 0);  // stub
            _m.active_stamp_grid_ov   = array_create(_need_cells, 0);  // stub
        }
    }

    // Lock warning if stamps are committed (locked from resizing)
    if (!_size_unlocked) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(180, 120, 40));
        draw_text(_ybx4 + 8, _szby1 + 4, "LOCKED - DELETE ALL STAMPS TO RESIZE");
    }

// ---- MAP W x H (read-only, shown under STAMP SIZE) ----
    // Map size is fixed at import (SLICE = 40x25, BIGMAP = source dims).
    // The editable VIEW + OFFSET pickers live above the map panel (below).
    var _mvx1 = _szx1;              // align with STAMP SIZE label column
    var _mvy1 = _szby1 + 24;        // one row below the stamp-size pickers

    var _map_disp_w = 0;
    var _map_disp_h = 0;
    if (_m.active_map >= 0 && _m.active_map < array_length(_m.map_w))
    {
        _map_disp_w = _m.map_w[_m.active_map];
        _map_disp_h = _m.map_h[_m.active_map];
    }
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_ltgray);
    draw_text(_mvx1 +20, _mvy1 , "MAP SIZE:");

    if (_m.active_map < 0 || _m.active_map >= array_length(_m.map_w) || _m.active_map >= array_length(_m.map_h))
    {
        draw_set_color(make_color_rgb(120, 160, 200));
        draw_text(_mvx1 + 90, _mvy1 , "(TEST)");
    }
    else
    {
        // Step size = one metatile in char cells. Typed values round down to a
        // whole metatile on commit (handled in the Step event).
        var _msz_x0 = _mvx1 + 90;

        // W minus (one metatile)
        var _mwm_x1 = _msz_x0;
        var _mwm_x2 = _mwm_x1 + 14;
        var _mwm_hov = point_in_rectangle(_mx, _my, _mwm_x1, _mvy1, _mwm_x2, _mvy1 + 14);
        draw_set_color(_mwm_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
        draw_rectangle(_mwm_x1, _mvy1, _mwm_x2, _mvy1 + 14, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_mwm_x1 + 7, _mvy1 + 2, "-");
        draw_set_halign(fa_left);
        if (_mwm_hov && mouse_check_button_pressed(mb_left))
        {
            var _mw_new = max(_m.stamp_w, _m.map_w[_m.active_map] - _m.stamp_w);
            scr_mts_resize_map(_m, _m.active_map, _mw_new, _m.map_h[_m.active_map]);
        }

        // W value (click to type)
        var _mwv_x1 = _mwm_x2 + 2;
        var _mwv_x2 = _mwv_x1 + 30;
        var _mwv_hov = point_in_rectangle(_mx, _my, _mwv_x1, _mvy1, _mwv_x2, _mvy1 + 14);
        draw_set_color(_mwv_hov ? make_color_rgb(40, 80, 60) : make_color_rgb(20, 35, 25));
        draw_rectangle(_mwv_x1, _mvy1, _mwv_x2, _mvy1 + 14, false);
        if (editing_map_dim && editing_map_field == "W" && editing_map_asset_idx == viewer_asset)
        {
            draw_set_color(c_lime);
            draw_text(_mwv_x1 + 3, _mvy1 + 2, editing_map_string + (((current_time mod 600) < 300) ? "_" : ""));
        }
        else
        {
            draw_set_color(_mwv_hov ? c_white : c_aqua);
            draw_text(_mwv_x1 + 3, _mvy1 + 2, string(_map_disp_w));
        }

        // W plus
        var _mwp_x1 = _mwv_x2 + 2;
        var _mwp_x2 = _mwp_x1 + 14;
        var _mwp_hov = point_in_rectangle(_mx, _my, _mwp_x1, _mvy1, _mwp_x2, _mvy1 + 14);
        draw_set_color(_mwp_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
        draw_rectangle(_mwp_x1, _mvy1, _mwp_x2, _mvy1 + 14, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_mwp_x1 + 7, _mvy1 + 2, "+");
        draw_set_halign(fa_left);
        if (_mwp_hov && mouse_check_button_pressed(mb_left))
        {
            var _mw_new2 = _m.map_w[_m.active_map] + _m.stamp_w;
            scr_mts_resize_map(_m, _m.active_map, _mw_new2, _m.map_h[_m.active_map]);
        }

        draw_set_color(c_ltgray);
        draw_text(_mwp_x2 + 6, _mvy1 + 2, "x");

        // H minus
        var _mhm_x1 = _mwp_x2 + 18;
        var _mhm_x2 = _mhm_x1 + 14;
        var _mhm_hov = point_in_rectangle(_mx, _my, _mhm_x1, _mvy1, _mhm_x2, _mvy1 + 14);
        draw_set_color(_mhm_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
        draw_rectangle(_mhm_x1, _mvy1, _mhm_x2, _mvy1 + 14, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_mhm_x1 + 7, _mvy1 + 2, "-");
        draw_set_halign(fa_left);
        if (_mhm_hov && mouse_check_button_pressed(mb_left))
        {
            var _mh_new = max(_m.stamp_h, _m.map_h[_m.active_map] - _m.stamp_h);
            scr_mts_resize_map(_m, _m.active_map, _m.map_w[_m.active_map], _mh_new);
        }

        // H value (click to type)
        var _mhv_x1 = _mhm_x2 + 2;
        var _mhv_x2 = _mhv_x1 + 30;
        var _mhv_hov = point_in_rectangle(_mx, _my, _mhv_x1, _mvy1, _mhv_x2, _mvy1 + 14);
        draw_set_color(_mhv_hov ? make_color_rgb(40, 80, 60) : make_color_rgb(20, 35, 25));
        draw_rectangle(_mhv_x1, _mvy1, _mhv_x2, _mvy1 + 14, false);
        if (editing_map_dim && editing_map_field == "H" && editing_map_asset_idx == viewer_asset)
        {
            draw_set_color(c_lime);
            draw_text(_mhv_x1 + 3, _mvy1 + 2, editing_map_string + (((current_time mod 600) < 300) ? "_" : ""));
        }
        else
        {
            draw_set_color(_mhv_hov ? c_white : c_aqua);
            draw_text(_mhv_x1 + 3, _mvy1 + 2, string(_map_disp_h));
        }

        // H plus
        var _mhp_x1 = _mhv_x2 + 2;
        var _mhp_x2 = _mhp_x1 + 14;
        var _mhp_hov = point_in_rectangle(_mx, _my, _mhp_x1, _mvy1, _mhp_x2, _mvy1 + 14);
        draw_set_color(_mhp_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
        draw_rectangle(_mhp_x1, _mvy1, _mhp_x2, _mvy1 + 14, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_mhp_x1 + 7, _mvy1 + 2, "+");
        draw_set_halign(fa_left);
        if (_mhp_hov && mouse_check_button_pressed(mb_left))
        {
            var _mh_new2 = _m.map_h[_m.active_map] + _m.stamp_h;
            scr_mts_resize_map(_m, _m.active_map, _m.map_w[_m.active_map], _mh_new2);
        }

        // ---- SLICE button (opens async W x H modal, re-slices active map) ----
        var _slc_x1  = _mhp_x2 + 18;
        var _slc_x2  = _slc_x1 + 42;
		var _slc_y1  = _mvy1;
        var _slc_hov = point_in_rectangle(_mx, _my, _slc_x1, _slc_y1, _slc_x2, _slc_y1 + 14);
        draw_set_color(_slc_hov ? make_color_rgb(200, 120, 40) : make_color_rgb(90, 55, 20));
        draw_rectangle(_slc_x1, _slc_y1, _slc_x2, _slc_y1 + 14, false);
        draw_set_color(c_white);
        draw_set_halign(fa_left);
        draw_text(_slc_x1+3 , _slc_y1-1  , "SLICE   <[ACTIVE MAP ONLY]");
        draw_set_halign(fa_left);
        if (_slc_hov && mouse_check_button_pressed(mb_left))
        {
            scr_show_integer(40, 25, "SLICE");
        }

        // Click-to-type activation for the value fields
        if (mouse_check_button_pressed(mb_left))
        {
            if (_mwv_hov)
            {
                editing_map_dim       = true;
                editing_map_field     = "W";
                editing_map_string    = string(_map_disp_w);
                editing_map_asset_idx = viewer_asset;
                keyboard_string       = "";
            }
            else if (_mhv_hov)
            {
                editing_map_dim       = true;
                editing_map_field     = "H";
                editing_map_string    = string(_map_disp_h);
                editing_map_asset_idx = viewer_asset;
                keyboard_string       = "";
            }
        }
    }

    // ---- CHARSET PICKER ----
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_ltgray);
    draw_text(_vx1 + 10, _cy, "CHARSET:");
    var _chr_name = _m.chr_asset;
    var _tscpx1   = _vx1 + 74;
    var _tscpx2   = _tscpx1 + 130;
    var _tscpy1   = _cy - 1;
    var _tscpy2   = _cy + 13;
    meta_ts_btn_y = _tscpy1;
    var _tscphov  = point_in_rectangle(_mx, _my, _tscpx1, _tscpy1, _tscpx2, _tscpy2);
    draw_set_color(_tscphov ? make_color_rgb(40, 80, 60) : make_color_rgb(20, 35, 25));
    draw_rectangle(_tscpx1, _tscpy1, _tscpx2, _tscpy2, false);
    draw_set_color(_chr_name != "" ? c_lime : make_color_rgb(150, 150, 150));
    draw_text(_tscpx1 + 4, _cy - 2, _chr_name != "" ? _chr_name : "-- PICK --");

    // ---- STAMP COUNT / CAP ----
    // 9b route: stamp-def is 1 byte/cell.
    var _bytes_per_stamp = _m.stamp_w * _m.stamp_h * 1;
    var _meta_idx_size   = floor(40 / _m.stamp_w) * floor(25 / _m.stamp_h);
    var _stamp_cap       = floor((8192 - _meta_idx_size) / max(1, _bytes_per_stamp));
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(120, 200, 255));
    draw_text(_tscpx2 + 10, _cy + 30, "STAMPS: " + string(_m.stamp_count) + " / " + string(_stamp_cap));
    // Byte breakdown (uses _m.total_bytes computed below; falls back to 0 first frame)
    var _tb_disp  = variable_struct_exists(_m, "total_bytes") ? _m.total_bytes : 0;
    var _mtd_disp  = variable_struct_exists(_m, "mt_data_bytes_disp") ? _m.mt_data_bytes_disp : 0;
    var _clut_disp = variable_struct_exists(_m, "clut_bytes_disp")    ? _m.clut_bytes_disp    : 0;
    var _map_disp  = variable_struct_exists(_m, "map_bytes_disp") ? _m.map_bytes_disp : 0;
    var _tb_col;
    if      (_tb_disp < 4096) _tb_col = c_white;
    else if (_tb_disp < 6144) _tb_col = c_yellow;
    else if (_tb_disp < 8192) _tb_col = make_color_rgb(255, 140, 0);
    else                      _tb_col = c_red;
    var _map_mem   = variable_struct_exists(_m, "cur_map_bytes_disp") ? _m.cur_map_bytes_disp : 0;
    var _mem_total = _tb_disp;  // all maps + metatile data + char_lut table
    var _tb_head = "CHAR LUT:  " + string(_clut_disp) + "b\nMETATILE:  " + string(_mtd_disp) + "b\nMAPS:      " + string(_map_disp) + "b\nMAP MEM:   " + string(_map_mem) + "b\nTOTAL:  ";
    draw_set_color(make_color_rgb(140, 140, 160));
    draw_text(_tscpx2 + 142, _cy + 36, _tb_head);
	draw_line(_tscpx2 + 142,_cy + 100,_tscpx2 + 230,_cy + 100)
    var _tb_lh = string_height("X");
    draw_set_color(_tb_col);
    draw_text(_tscpx2 + 200, _cy + 36 + _tb_lh * 4, string(_mem_total) + "b");
    _cy += 22;

    // ---- RESOLVE CHARSET ----
    var _ts_chr_ref = noone;
    if (_chr_name != "") {
        for (var _tci = 0; _tci < ds_list_size(asset_list); _tci++) {
            var _tca = ds_list_find_value(asset_list, _tci);
            if (_tca.type == "CHAR_SET" && _tca.name == _chr_name) {
                _ts_chr_ref = _tca;
                break;
            }
        }
    }
    var _ts_bg;
    if (_m.map_mc_bg >= 0) {
        _ts_bg = _m.map_mc_bg;
    } else if (_ts_chr_ref != noone) {
        _ts_bg = _ts_chr_ref.meta.mc_bg;
    } else {
        _ts_bg = 0;
    }

    // ---- ECM: 256 virtual slots (64 real chars x 4 BG bands) ----
    // A virtual char index >= 64 is the same glyph as (index mod 64), rendered
    // against a different VIC background register. char_lut / stamp_data /
    // active_char keep storing the full 0-255 virtual index unchanged — only
    // pixel lookups (mod 64) and background colour (div 64 -> band) differ.
    var _ecm_mode    = (_ts_chr_ref != noone) && variable_struct_exists(_ts_chr_ref.meta, "mc_mode") && (_ts_chr_ref.meta.mc_mode == 2);
    // Real MC-masking behaviour (colour & 0x07) only applies when actually in
    // MC mode — ECM must always keep the full 4-bit nibble regardless of the
    // global MIXED flag's current state (which may be stale from a different,
    // previously-viewed MC-mode asset).
    var _eff_mixed   = (obj_workspace_manager.map_global_mixed == 1) && !_ecm_mode;
    var _ecm_bg_cols = [
        _ts_bg,
        (_ts_chr_ref != noone && variable_struct_exists(_ts_chr_ref.meta, "ecm_bg1")) ? _ts_chr_ref.meta.ecm_bg1 : 6,
        (_ts_chr_ref != noone && variable_struct_exists(_ts_chr_ref.meta, "ecm_bg2")) ? _ts_chr_ref.meta.ecm_bg2 : 14,
        (_ts_chr_ref != noone && variable_struct_exists(_ts_chr_ref.meta, "ecm_bg3")) ? _ts_chr_ref.meta.ecm_bg3 : 3
    ];

// ---- GLOBAL MODE BUTTON ----
    var _ts_global_mixed = obj_workspace_manager.map_global_mixed;
    if (!variable_struct_exists(_m, "active_mode")) _m.active_mode = 0;

    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(80, 80, 100));
    draw_text(_vx1 + 10, _cy + 4, "MODE:");

    if (_ecm_mode) {
        // ECM: no HR/MIXED toggle — ECM and MC are hardware-exclusive on the
        // VIC-II, so this charset can only ever emit ECM. Static label only.
        var _ecmbx1 = _vx1 + 52;
        var _ecmbx2 = _ecmbx1 + 80;
        var _ecmby1 = _cy;
        var _ecmby2 = _cy + 18;
        draw_set_color(make_color_rgb(20, 60, 65));
        draw_rectangle(_ecmbx1, _ecmby1, _ecmbx2, _ecmby2, false);
        draw_set_color(make_color_rgb(80, 220, 240));
        draw_rectangle(_ecmbx1, _ecmby1, _ecmbx2, _ecmby2, true);
        draw_set_halign(fa_center);
        draw_text(_ecmbx1 + 40, _ecmby1 + 4, "ECM");
        draw_set_halign(fa_left);
        _m.active_mode = 0;
        _cy += 26;

        // ---- ECM BG0-3 PICKERS (full 16-swatch grid — matches CHAR_SET/MAP_DATA) ----
        var _ecm_labels = ["BG0", "BG1", "BG2", "BG3"];
        var _ecm_fields = ["mc_bg", "ecm_bg1", "ecm_bg2", "ecm_bg3"];
        var _ecm_sw     = 14;
        var _ecm_gap    = 1;
        draw_set_font(fnt_c64_tiny);
        for (var _ebi = 0; _ebi < 4; _ebi++) {
            var _eby = _cy + _ebi * (_ecm_sw + 4);
            draw_set_color(make_color_rgb(80, 80, 100));
            draw_text(_vx1 + 10, _eby + 4, _ecm_labels[_ebi] + ":");
            var _ebval = (_ts_chr_ref != noone && variable_struct_exists(_ts_chr_ref.meta, _ecm_fields[_ebi]))
                       ? variable_struct_get(_ts_chr_ref.meta, _ecm_fields[_ebi]) : 0;
            for (var _ebsi = 0; _ebsi < 16; _ebsi++) {
                var _ebx1  = _vx1 + 44 + _ebsi * (_ecm_sw + _ecm_gap);
                var _ebx2  = _ebx1 + _ecm_sw;
                var _ebhov = point_in_rectangle(_mx, _my, _ebx1, _eby, _ebx2, _eby + _ecm_sw);
                draw_set_color(scr_c64_pepto_colour(_ebsi));
                draw_rectangle(_ebx1, _eby, _ebx2, _eby + _ecm_sw, false);
                if (_ebval == _ebsi) {
                    draw_set_color(c_white);
                    draw_rectangle(_ebx1, _eby, _ebx2, _eby + _ecm_sw, true);
                }
                if (_ts_chr_ref != noone && _ebhov && mouse_check_button_pressed(mb_left)) {
                    variable_struct_set(_ts_chr_ref.meta, _ecm_fields[_ebi], _ebsi);
                    _ts_chr_ref.meta.is_dirty = true;
                }
            }
        }
        _cy += 4 * (_ecm_sw + 4) + 8;
    } else {
        // HR ONLY / MIXED toggle
        var _gmb_labels = ["HR ONLY", "MIXED"];
        var _gmb_bg     = [make_color_rgb(20, 20, 35), make_color_rgb(10, 50, 80)];
        var _gmb_border = [make_color_rgb(60, 60, 90), make_color_rgb(40, 160, 220)];
        var _gmb_tcols  = [make_color_rgb(100, 100, 130), make_color_rgb(80, 200, 255)];
        var _gmbx1      = _vx1 + 52;
        var _gmbx2      = _gmbx1 + 80;
        var _gmby1      = _cy;
        var _gmby2      = _cy + 18;
        var _gmbhov     = point_in_rectangle(_mx, _my, _gmbx1, _gmby1, _gmbx2, _gmby2);
        draw_set_color(_gmb_bg[_ts_global_mixed]);
        draw_rectangle(_gmbx1, _gmby1, _gmbx2, _gmby2, false);
        draw_set_color(_gmb_border[_ts_global_mixed]);
        draw_rectangle(_gmbx1, _gmby1, _gmbx2, _gmby2, true);
        draw_set_color(_gmb_tcols[_ts_global_mixed]);
        draw_set_halign(fa_center);
        draw_text(_gmbx1 + 40, _gmby1 + 4, _gmb_labels[_ts_global_mixed]);
        draw_set_halign(fa_left);
        if (_gmbhov && mouse_check_button_pressed(mb_left)) {
            obj_workspace_manager.map_global_mixed = (_ts_global_mixed == 0) ? 1 : 0;
            _m.active_mode = 0;
        }

        // PAINT HR / PAINT MC removed — per-char mode now lives in char_lut.
        _m.active_mode = 0;
        _cy += 26;

        // ---- MC COLOUR PICKERS ----
        var _ts_pal_labels = ["BG", "C1", "C2"];
        var _ts_pal_fields = ["map_mc_bg", "map_mc_col1", "map_mc_col2"];
        var _ts_pal_disp   = [_m.map_mc_bg, _m.map_mc_col1, _m.map_mc_col2];
        var _ts_sw         = 16;
        var _ts_gap        = 1;
        draw_set_font(fnt_c64_tiny);
        for (var _tpi = 0; _tpi < 3; _tpi++) {
            var _tpy = _cy + _tpi * (_ts_sw + 4);
            draw_set_color(make_color_rgb(80, 80, 100));
            draw_text(_vx1 + 10, _tpy + 3, _ts_pal_labels[_tpi] + ":");
            for (var _tsi = 0; _tsi < 16; _tsi++) {
                var _tsx   = _vx1 + 36 + _tsi * (_ts_sw + _ts_gap);
                var _tshov = point_in_rectangle(_mx, _my, _tsx, _tpy, _tsx + _ts_sw, _tpy + _ts_sw);
                draw_set_color(scr_c64_pepto_colour(_tsi));
                draw_rectangle(_tsx, _tpy, _tsx + _ts_sw, _tpy + _ts_sw, false);
                if (_ts_pal_disp[_tpi] == _tsi) {
                    draw_set_color(c_white);
                    draw_rectangle(_tsx, _tpy, _tsx + _ts_sw, _tpy + _ts_sw, true);
                }
                if (_tshov && mouse_check_button_pressed(mb_left)) {
                    variable_struct_set(_m, _ts_pal_fields[_tpi], _tsi);
                    // Picking BG/C1/C2 here also selects it as the active paint
                    // bit-pair in the char editor (0=BG,1=C1,2=C2).
                    chr_active_mc_colour = _tpi;
                }
                if (_tshov && mouse_check_button_pressed(mb_right)) {
                    variable_struct_set(_m, _ts_pal_fields[_tpi], -1);
                }
            }
        }
        _cy += 3 * (_ts_sw + 4) + 8;
    }

	// T toggles the per-cell tile-type overlay on the map/test area.
    if (keyboard_check_pressed(ord("T")) && !scr_ctrl_held()) {
        _m.show_types_overlay = !_m.show_types_overlay;
    }

	// Ctrl+D to deselect stamp
    if (scr_ctrl_held() && keyboard_check_pressed(ord("D"))) {
        _m.edit_stamp = -1;
        var _dc_cells2 = _m.stamp_w * _m.stamp_h;
        _m.active_stamp_grid_char = array_create(_dc_cells2, 0);
        _m.active_stamp_grid_col  = array_create(_dc_cells2, 0);
        _m.active_stamp_grid_ov   = array_create(_dc_cells2, 0);
    }

	// Ctrl+C: copy the edited stamp's cells (char indices) to the clipboard.
    if (scr_ctrl_held() && keyboard_check_pressed(ord("C"))) {
        if (_m.edit_stamp >= 0) {
            var _cc_cells = _m.stamp_w * _m.stamp_h;
            var _cc_off   = _m.edit_stamp * _cc_cells;
            _m.stamp_clip = array_create(_cc_cells, 0);
            for (var _cc_i = 0; _cc_i < _cc_cells; _cc_i++) {
                var _cc_idx = _cc_off + _cc_i;
                if (_cc_idx < array_length(_m.stamp_data)) {
                    _m.stamp_clip[_cc_i] = _m.stamp_data[_cc_idx];
                }
            }
            _m.stamp_clip_valid = true;
        }
    }

	// Ctrl+V: paste the clipboard cells into the currently selected stamp.
    // Only valid if the clipboard size matches the current stamp cell count
    // (same stamp dimensions), so a copy at one size can't corrupt another.
    if (scr_ctrl_held() && keyboard_check_pressed(ord("V"))) {
        var _cv_cells = _m.stamp_w * _m.stamp_h;
        var _cv_cells = _m.stamp_w * _m.stamp_h;
        if (_m.edit_stamp >= 0
         && _m.stamp_clip_valid
         && array_length(_m.stamp_clip) == _cv_cells) {
            var _cv_off = _m.edit_stamp * _cv_cells;
            for (var _cv_i = 0; _cv_i < _cv_cells; _cv_i++) {
                var _cv_idx = _cv_off + _cv_i;
                if (_cv_idx < array_length(_m.stamp_data)) {
                    _m.stamp_data[_cv_idx] = _m.stamp_clip[_cv_i];
                }
                _m.active_stamp_grid_char[_cv_i] = _m.stamp_clip[_cv_i];
            }
            _m.is_dirty = true;
        }
    }

    // ---- ACTIVE SWATCH ----
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_ltgray);
    draw_text(_vx1 + 10, _cy + 3, "PAINT:");
    draw_set_color(scr_c64_pepto_colour(_m.active_colour));
    draw_rectangle(_vx1 + 54, _cy + 2, _vx1 + 70, _cy + 14, false);
    draw_set_color(c_white);
    draw_rectangle(_vx1 + 54, _cy + 2, _vx1 + 70, _cy + 14, true);
    draw_text(_vx1 + 74, _cy + 3, "COL " + string(_m.active_colour));
    draw_text(_vx1 + 160, _cy + 3, "CHR " + string(_m.active_char));
    _cy += 20;

    // ---- LAYOUT ----
    var _store_btn_h = 22;
    var _list_x1     = _vx1 + 10;
    var _list_x2     = _vx1 + 220;
    var _canvas_x1   = _list_x2 + 10;
    var _canvas_x2   = _vx1 + floor((_vx2 - _vx1) * 0.38) - 5;
    var _test_x1     = _canvas_x2 + 10;
    var _test_x2     = _vx2 - 10;
    var _canvas_y1   = _cy;
    var _canvas_y2      = _vy2 - 235;
    var _test_char_cols = 40;
    var _test_char_rows = 25;
    var _map_top_fit    = _vy1 + 76;
    var _map_fit_w      = (_test_x2 - _test_x1) - 8;
    var _map_fit_h      = (_canvas_y2 - _map_top_fit) - 60;
    // Grid extents: a REAL map uses its own stored map_w/map_h (in metatiles),
    // so oversized (BIGMAP) rooms render at full size. The TEST map has no
    // stored dimensions, so it falls back to the screen-derived default.
    // Round UP so the partial bottom char-row (25 isn't divisible by 2) gets a
    // full metatile row on the screen-derived fallback.
    // map_w/map_h are the fixed map footprint in CHAR CELLS. The metatile grid
    // is that footprint divided by the current stamp size, so changing stamp
    // size only coarsens the grid — the on-screen char footprint is unchanged.
    var _test_cols = floor(_test_char_cols / _m.stamp_w);
    var _test_rows = ceil(_test_char_rows / _m.stamp_h);
    if (_m.active_map >= 0 && _m.active_map < array_length(_m.map_w))
    {
        _test_cols = floor(_m.map_w[_m.active_map] / _m.stamp_w);
        _test_rows = floor(_m.map_h[_m.active_map] / _m.stamp_h);
    }
    // On STAMP-SIZE CHANGE, clear every map (test + all real maps) to the new
    // _test_cols x _test_rows. Resizing the stamp changes the whole grid stride,
    // and preserving old placements at a new size is meaningless (a 2x2 layout
    // makes no sense as an 8x1 one), so we wipe. This also fixes the "MAP 0
    // renders offset / wrong stride until you toggle maps" bug: every map's
    // array length now always matches the current cols/rows on the same frame.
    var _map_size_key = string(_m.stamp_w) + "x" + string(_m.stamp_h);
    if (_m.map_size_key != _map_size_key) {
        var _blank_len = _test_cols * _test_rows;
        _m.test_grid = array_create(_blank_len, -1);
        for (var _clr = 0; _clr < _m.map_count; _clr++) {
            _m.maps[_clr] = array_create(_blank_len, -1);
        }
        _m.map_size_key = _map_size_key;
    }
    // CRITICAL: normalise the ACTIVE real map to _test_cols * _test_rows HERE,
    // before _test_cs is derived, so the cell-size fit and the render loop agree
    // on the same frame. Previously the map was only normalised in a later loop
    // (after sizing), so on the first frame after switching stamp size the grid
    // rendered at a cell size fitted to a stale row count — squashing the map
    // until you toggled maps to force a recompute. The TEST map never showed this
    // because it's reallocated to the current size every frame just above.
    if (_m.active_map >= 0 && _m.active_map < array_length(_m.maps) && _test_cols > 0) {
        var _want_len_early = _test_cols * _test_rows;
        var _amg_len = array_length(_m.maps[_m.active_map]);
        if (_amg_len == 0 || (_amg_len mod _test_cols) != 0) {
            _m.maps[_m.active_map] = array_create(_want_len_early, -1);
        } else if (_amg_len < _want_len_early) {
            var _grown_early = _m.maps[_m.active_map];
            for (var _pad_e = _amg_len; _pad_e < _want_len_early; _pad_e++) array_push(_grown_early, -1);
            _m.maps[_m.active_map] = _grown_early;
        } else if (_amg_len > _want_len_early) {
            array_resize(_m.maps[_m.active_map], _want_len_early);
        }
    }
    // The render loop iterates cell rows [_draw_col0.._draw_col1) x [_draw_row0.._draw_row1).
    // MAP mode  = whole map; cell size fits the full grid.
    // VIEW mode = only the view window (offset..offset+view in metatile cells);
    //             cell size fits just that window, so it appears zoomed in.
    // Draw range in metatile-cell units. In VIEW mode we want CHAR-accurate
    // framing: the window can start on any char, so we include the metatile that
    // straddles the left/top edge (floor) and the metatile that straddles the
    // right/bottom edge (ceil of the far char). The overhang is scissored away
    // later, and _view_shift_x/y nudges the draw origin so the exact char window
    // lands at the panel origin.
    var _draw_col0 = 0;
    var _draw_row0 = 0;
    var _draw_col1 = _test_cols;
    var _draw_row1 = _test_rows;
    var _view_shift_x = 0;   // pixels: how far the first drawn metatile sits left of the window edge
    var _view_shift_y = 0;
    var _map_vis_cols = _test_cols;   // metatile columns/rows the MAP-mode panel can show at once (drives scrollbars)
    var _map_vis_rows = _test_rows;
    var _test_cs = 8;
    // Shared zoom ceiling: the pixel-per-char size VIEW mode would use to fit
    // its view_w x view_h window. MAP mode zooms up to this and no further —
    // wheel hands off into VIEW mode instead of exceeding it — and zooming
    // out of VIEW mode drops back into MAP mode starting at this same value,
    // so the two modes read as one continuous zoom rather than two systems.
    var _view_zoom_cap = max(4, min(floor(_map_fit_w / max(1, _m.view_w)), floor(_map_fit_h / max(1, _m.view_h))));
    if (_m.edit_view_mode == 1 && _m.active_map >= 0)
    {
        // Char window [offset .. offset+view). First/last metatile that touches it.
        var _win_cx0 = _m.offset_x;
        var _win_cy0 = _m.offset_y;
        var _win_cx1 = _m.offset_x + _m.view_w;   // exclusive char edge
        var _win_cy1 = _m.offset_y + _m.view_h;
        _draw_col0 = floor(_win_cx0 / _m.stamp_w);
        _draw_row0 = floor(_win_cy0 / _m.stamp_h);
        _draw_col1 = min(_test_cols, ceil(_win_cx1 / _m.stamp_w));
        _draw_row1 = min(_test_rows, ceil(_win_cy1 / _m.stamp_h));
        // Sub-metatile remainder (char cells) of the window's top-left inside its
        // first metatile — used below (in pixels) to shift the draw origin.
        _view_shift_x = _win_cx0 - (_draw_col0 * _m.stamp_w);
        _view_shift_y = _win_cy0 - (_draw_row0 * _m.stamp_h);
        _test_cs = _view_zoom_cap;
    }
    else
    {
        // MAP mode: fixed pixel-per-char zoom, floored at 8px and ceilinged
        // at _view_zoom_cap — only the columns/rows that fit at the current
        // zoom are drawn, and map_pan_col/map_pan_row scroll the rest into
        // view (wheel zooms, space/mid-mouse drag pans, scrollbars below).
        // Backward-compat: old saves default to a one-time best-fit at the
        // 8px floor.
        if (!variable_struct_exists(_m, "map_zoom_px") || _m.map_zoom_px <= 0) {
            var _auto_fit_x = floor(_map_fit_w / max(1, _test_cols * _m.stamp_w));
            var _auto_fit_y = floor(_map_fit_h / max(1, _test_rows * _m.stamp_h));
            _m.map_zoom_px = max(8, min(_auto_fit_x, _auto_fit_y));
        }
        if (!variable_struct_exists(_m, "map_pan_col")) _m.map_pan_col = 0;
        if (!variable_struct_exists(_m, "map_pan_row")) _m.map_pan_row = 0;
        _m.map_zoom_px = clamp(_m.map_zoom_px, 8, max(8, _view_zoom_cap));
        _test_cs       = _m.map_zoom_px;
        // floor (not ceil) so the drawn window never overhangs the panel —
        // that overhang was what got scissored away and looked like the map
        // was "just shy" of showing its far right/left edge.
        _map_vis_cols  = max(1, floor(_map_fit_w / (_test_cs * _m.stamp_w)));
        _map_vis_rows  = max(1, floor(_map_fit_h / (_test_cs * _m.stamp_h)));
        _m.map_pan_col = clamp(_m.map_pan_col, 0, max(0, _test_cols - _map_vis_cols));
        _m.map_pan_row = clamp(_m.map_pan_row, 0, max(0, _test_rows - _map_vis_rows));
        _draw_col0 = _m.map_pan_col;
        _draw_row0 = _m.map_pan_row;
        _draw_col1 = min(_test_cols, _draw_col0 + _map_vis_cols);
        _draw_row1 = min(_test_rows, _draw_row0 + _map_vis_rows);
    }
    var _draw_cols = max(1, _draw_col1 - _draw_col0);
    var _draw_rows = max(1, _draw_row1 - _draw_row0);

    // Panel footprint in chars: VIEW mode fits the exact CHAR window
    // (view_w x view_h); MAP mode fits whatever metatile range is drawn.
    var _fit_chars_w = (_m.edit_view_mode == 1 && _m.active_map >= 0) ? _m.view_w : (_draw_cols * _m.stamp_w);
    var _fit_chars_h = (_m.edit_view_mode == 1 && _m.active_map >= 0) ? _m.view_h : (_draw_rows * _m.stamp_h);
    var _grid_chars_w = _draw_cols * _m.stamp_w;
    var _grid_chars_h = _draw_rows * _m.stamp_h;
    var _test_grid_pw = _fit_chars_w * _test_cs;   // panel footprint = the char window
    var _test_grid_ph = _fit_chars_h * _test_cs;

    // ---- STAMP LIST ----
    draw_set_color(make_color_rgb(12, 12, 20));
    draw_rectangle(_list_x1, _cy, _list_x2, _canvas_y2, false);
    draw_set_color(make_color_rgb(40, 40, 60));
    draw_rectangle(_list_x1, _cy, _list_x2, _canvas_y2, true);

    // Height scales with stamp_h so 1-tall stamps don't get a 60px floor.
    // Per metatile-row height (24) chosen so 2-tall lands on the old 60px;
    // 1-tall -> 36, 4-tall -> 108. Label/border budget is the +12.
    var _slot_h      = _m.stamp_h * 24 + 4;
    var _slot_w_est  = floor((_list_x2 - _list_x1) / max(1, floor(8 / _m.stamp_w)));
    var _slot_tpx    = max(4, min(floor((_slot_h - 12) / max(1, _m.stamp_h)), floor((_slot_w_est - 12) / max(1, _m.stamp_w))));
    var _list_area_h = _canvas_y2 - _cy - 24;
    var _vis_slots   = floor(_list_area_h / _slot_h);

    if (!variable_struct_exists(_m, "stamp_list_scroll")) _m.stamp_list_scroll = 0;
    var _scroll = _m.stamp_list_scroll;

    var _cols3       = max(1, floor(8 / _m.stamp_w));
    var _slot_w3     = floor((_list_x2 - _list_x1) / _cols3);
    var _total_rows3 = ceil((_m.stamp_count + 1) / _cols3);
    var _max_scroll3 = max(0, _total_rows3 - _vis_slots);
    if (point_in_rectangle(_mx, _my, _list_x1, _cy, _list_x2, _cy + _list_area_h)) {
        if (mouse_wheel_up())   _m.stamp_list_scroll = max(0, _scroll - 1);
        if (mouse_wheel_down()) _m.stamp_list_scroll = min(_max_scroll3, _scroll + 1);
        _scroll = _m.stamp_list_scroll;
    }

    var _lsx = window_get_width()  / global.gui_w;
    var _lsy = window_get_height() / display_get_gui_height();
    gpu_set_scissor(
        floor(_list_x1 * _lsx), floor(_cy * _lsy),
        ceil((_list_x2 - _list_x1) * _lsx), ceil(_list_area_h * _lsy)
    );

    for (var _si = 0; _si <= _m.stamp_count; _si++) {
        var _is_ghost = (_si == _m.stamp_count);
        var _scol3 = _si mod _cols3;
        var _srow3 = _si div _cols3;
        var _sx2   = _list_x1 + _scol3 * _slot_w3;
        var _sy2   = _cy + (_srow3 - _scroll) * _slot_h;
        if (_sy2 + _slot_h < _cy || _sy2 > _cy + _list_area_h) continue;

        // ---- GHOST [+] SLOT ----
        if (_is_ghost) {
            var _g_hov = point_in_rectangle(_mx, _my, _sx2, _sy2, _sx2 + _slot_w3 - 2, _sy2 + _slot_h - 2);
            draw_set_color(_g_hov ? make_color_rgb(30, 60, 45) : make_color_rgb(15, 22, 18));
            draw_rectangle(_sx2, _sy2, _sx2 + _slot_w3 - 2, _sy2 + _slot_h - 2, false);
            draw_set_color(make_color_rgb(60, 140, 90));
            draw_rectangle(_sx2, _sy2, _sx2 + _slot_w3 - 2, _sy2 + _slot_h - 2, true);
            draw_set_font(fnt_c64_tiny);
            draw_set_color(_g_hov ? c_white : make_color_rgb(80, 180, 110));
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            draw_text(_sx2 + (_slot_w3 - 2) * 0.5, _sy2 + (_slot_h - 2) * 0.5, "+");
            draw_set_halign(fa_left);
            draw_set_valign(fa_top);
            if (_g_hov && mouse_check_button_pressed(mb_left) &&
                _sy2 >= _cy && _sy2 < _cy + _list_area_h) {
                // Allocate a new empty stamp (1 byte/cell) and select it
                var _new_cells = _m.stamp_w * _m.stamp_h;
                for (var _ni = 0; _ni < _new_cells; _ni++) {
                    array_push(_m.stamp_data, 0);   // char only
                }
                _m.edit_stamp = _m.stamp_count;
                _m.stamp_count++;
                if (!variable_struct_exists(_m, "stamp_mc")) _m.stamp_mc = array_create(0, 0);
                array_push(_m.stamp_mc, 0);   // dormant legacy flag, kept sized
                if (!variable_struct_exists(_m, "stamp_override")) _m.stamp_override = array_create(0, 0x80);
                array_push(_m.stamp_override, 0x80);   // new stamp: no override
                _m.active_stamp_grid_char = array_create(_new_cells, 0);
                _m.active_stamp_grid_col  = array_create(_new_cells, 0);  // stub
                _m.active_stamp_grid_ov   = array_create(_new_cells, 0);  // stub
                _m.is_dirty = true;
            }
            continue;
        }

        var _foot_w = _m.stamp_w * _slot_tpx;
        var _foot_h = _m.stamp_h * _slot_tpx;
        var _ssel = (_m.edit_stamp == _si);
        var _shov = point_in_rectangle(_mx, _my, _sx2, _sy2, _sx2 + _slot_w3 - 2, _sy2 + _slot_h - 2);

        draw_set_color(_ssel ? make_color_rgb(30, 80, 60) : (_shov ? make_color_rgb(25, 25, 45) : make_color_rgb(15, 15, 28)));
        draw_rectangle(_sx2, _sy2, _sx2 + _slot_w3 - 2, _sy2 + _slot_h - 2, false);
        if (_ssel) {
            draw_set_color(make_color_rgb(80, 200, 120));
            draw_rectangle(_sx2 + 2, _sy2 + 2, _sx2 + 4 + _foot_w, _sy2 + 4 + _foot_h, true);
        }

        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(100, 100, 140));
        draw_text(_sx2 + 3, _sy2 + 2, string(_si));

        var _base_off = _si * _m.stamp_w * _m.stamp_h;
        for (var _row = 0; _row < _m.stamp_h; _row++) {
            for (var _col = 0; _col < _m.stamp_w; _col++) {
                var _cell_idx = _base_off + _row * _m.stamp_w + _col;
                if (_cell_idx >= array_length(_m.stamp_data)) continue;
                var _char_v = _m.stamp_data[_cell_idx];
                var _sl_rc  = _ecm_mode ? (_char_v mod 64) : _char_v;
                var _sl_bg  = _ecm_mode ? scr_c64_pepto_colour(_ecm_bg_cols[_char_v div 64]) : scr_c64_pepto_colour(_ts_bg);
                // Colour from char_lut; per-stamp override wins
                var _col_v  = _clut_col(_m, _char_v);
                if (_si < array_length(_m.stamp_override) && _m.stamp_override[_si] != 0x80) {
                    _col_v = _m.stamp_override[_si];
                }
                var _px         = _sx2 + 4 + _col * _slot_tpx;
                var _py         = _sy2 + 4 + _row * _slot_tpx;
                var _prev_is_mc = (_ts_global_mixed == 1) && (_clut_mc(_m, _char_v) == 1);
                if (_ts_chr_ref != noone && buffer_exists(_ts_chr_ref.buffer) && _slot_tpx >= 4) {
                    draw_set_color(_sl_bg);
                    draw_rectangle(_px, _py, _px + _slot_tpx - 1, _py + _slot_tpx - 1, false);
                    if (_prev_is_mc) {
                        var _prev_col1 = (_m.map_mc_col1 >= 0) ? _m.map_mc_col1 : 1;
                        var _prev_col2 = (_m.map_mc_col2 >= 0) ? _m.map_mc_col2 : 2;
                        var _prev_pal  = [_sl_bg, scr_c64_pepto_colour(_prev_col1), scr_c64_pepto_colour(_prev_col2), scr_c64_pepto_colour(_col_v & 0x07)];
                        var _ppw       = max(1, _slot_tpx / 4);
                        var _pph       = max(1, _slot_tpx / 8);
                        for (var _pr = 0; _pr < 8; _pr++) {
                            var _pboff = (_sl_rc * 8) + _pr;
                            if (_pboff >= buffer_get_size(_ts_chr_ref.buffer)) break;
                            var _pbyte = buffer_peek(_ts_chr_ref.buffer, _pboff, buffer_u8);
                            for (var _pb = 0; _pb < 4; _pb++) {
                                var _pbits = (_pbyte >> (6 - _pb * 2)) & 0x03;
                                if (_pbits == 0) continue;
                                draw_set_color(_prev_pal[_pbits]);
                                draw_rectangle(_px + _pb * _ppw, _py + _pr * _pph, _px + _pb * _ppw + _ppw, _py + _pr * _pph + _pph, false);
                            }
                        }
                    } else {
                        var _ppw    = max(1, _slot_tpx / 8);
                        var _pph    = max(1, _slot_tpx / 8);
                        var _hr_col = (!_eff_mixed) ? (_col_v & 0x0F) : (_col_v & 0x07);
                        draw_set_color(scr_c64_pepto_colour(_hr_col));
                        for (var _pr = 0; _pr < 8; _pr++) {
                            var _pboff = (_sl_rc * 8) + _pr;
                            if (_pboff >= buffer_get_size(_ts_chr_ref.buffer)) break;
                            var _pbyte = buffer_peek(_ts_chr_ref.buffer, _pboff, buffer_u8);
                            for (var _pb = 0; _pb < 8; _pb++) {
                                if (_pbyte & (0x80 >> _pb)) {
                                    draw_rectangle(_px + _pb * _ppw, _py + _pr * _pph, _px + _pb * _ppw + _ppw, _py + _pr * _pph + _pph, false);
                                }
                            }
                        }
                    }
                } else {
                    var _fb_col = (!_eff_mixed) ? (_col_v & 0x0F) : (_col_v & 0x07);
                    draw_set_color(scr_c64_pepto_colour(_fb_col));
                    draw_rectangle(_px, _py, _px + _slot_tpx - 1, _py + _slot_tpx - 1, false);
                }
            }
        }

	// Click empty space in list to deselect — only if no stamp slot was hovered
    var _any_stamp_hov = false;
    for (var _scheck = 0; _scheck < _m.stamp_count; _scheck++) {
        var _scol_c  = _scheck mod _cols3;
        var _srow_c  = _scheck div _cols3;
        var _sx_c    = _list_x1 + _scol_c * _slot_w3;
        var _sy_c    = _cy + (_srow_c - _scroll) * _slot_h;
        if (point_in_rectangle(_mx, _my, _sx_c, _sy_c, _sx_c + _slot_w3 - 2, _sy_c + _slot_h - 2) &&
            _sy_c >= _cy && _sy_c < _cy + _list_area_h) {
            _any_stamp_hov = true;
            break;
        }
    }
    if (mouse_check_button_pressed(mb_left) &&
        point_in_rectangle(_mx, _my, _list_x1, _cy, _list_x2, _cy + _list_area_h) &&
        !_any_stamp_hov) {
        _m.edit_stamp = -1;
        var _dc_cells = _m.stamp_w * _m.stamp_h;
        _m.active_stamp_grid_char = array_create(_dc_cells, 0);
        _m.active_stamp_grid_col  = array_create(_dc_cells, 0);
        _m.active_stamp_grid_ov   = array_create(_dc_cells, 0);
    }

        if (_shov && mouse_check_button_pressed(mb_left) && _sy2 >= _cy && _sy2 < _cy + _list_area_h) {
            _m.edit_stamp = _si;
            var _cells = _m.stamp_w * _m.stamp_h;
            _m.active_stamp_grid_char = array_create(_cells, 0);
            _m.active_stamp_grid_col  = array_create(_cells, 0);  // stub
            _m.active_stamp_grid_ov   = array_create(_cells, 0);  // stub
            var _boff = _si * _cells;
            for (var _ci3 = 0; _ci3 < _cells; _ci3++) {
                var _didx = _boff + _ci3;
                if (_didx < array_length(_m.stamp_data)) {
                    _m.active_stamp_grid_char[_ci3] = _m.stamp_data[_didx];
                }
            }
        }

        if (_shov && mouse_check_button_pressed(mb_right)) {
            var _del_cells = _m.stamp_w * _m.stamp_h;
            var _del_start = _si * _del_cells;
            array_delete(_m.stamp_data, _del_start, _del_cells);
            if (variable_struct_exists(_m, "stamp_mc") && _si < array_length(_m.stamp_mc)) {
                array_delete(_m.stamp_mc, _si, 1);
            }
            if (variable_struct_exists(_m, "stamp_override") && _si < array_length(_m.stamp_override)) {
                array_delete(_m.stamp_override, _si, 1);
            }
            _m.stamp_count = max(0, _m.stamp_count - 1);
            if (_m.edit_stamp == _si) {
                _m.edit_stamp = -1;
                _m.active_stamp_grid_char = array_create(_del_cells, 0);
                _m.active_stamp_grid_col  = array_create(_del_cells, 0);
                _m.active_stamp_grid_ov   = array_create(_del_cells, 0);
            } else if (_m.edit_stamp > _si) {
                _m.edit_stamp--;
            }
        }
    }

    gpu_set_scissor(0, 0, window_get_width(), window_get_height());

    // ---- STORE BUTTON (bottom of stamp list) ----
    var _store_y    = _canvas_y2 - _store_btn_h;
    var _grid_cells = _m.stamp_w * _m.stamp_h;
    if (!variable_struct_exists(_m, "active_stamp_grid_char") || array_length(_m.active_stamp_grid_char) != _grid_cells) {
        _m.active_stamp_grid_char = array_create(_grid_cells, 0);
        _m.active_stamp_grid_col  = array_create(_grid_cells, 0);
        _m.active_stamp_grid_ov   = array_create(_grid_cells, 0);
    } else if (!variable_struct_exists(_m, "active_stamp_grid_ov") || array_length(_m.active_stamp_grid_ov) != _grid_cells) {
        _m.active_stamp_grid_ov = array_create(_grid_cells, 0);
    }
    if (!variable_struct_exists(_m, "test_grid") || array_length(_m.test_grid) != _test_cols * _test_rows) {
        _m.test_grid = array_create(_test_cols * _test_rows, -1);
    }
    // Char-copy lut carry globals are the one pair NOT owned by the asset meta,
    // so they still need a lazy init here (set by scr_chr_editor_draw on Ctrl+C / Ctrl+V).
    if (!variable_struct_exists(global, "chr_clip_lut_src")) global.chr_clip_lut_src = -1;
    if (!variable_struct_exists(global, "chr_clip_lut_dst")) global.chr_clip_lut_dst = -1;
    // char_lut extent guard: keep the table 256 long. Cheap, and defends against
    // a truncated array arriving from a hand-edited or partial save.
    while (array_length(_m.char_lut) < 256) array_push(_m.char_lut, 1);

    if (!variable_struct_exists(_m, "stamp_mc")) {
        _m.stamp_mc = array_create(_m.stamp_count, 0);
    } else if (array_length(_m.stamp_mc) < _m.stamp_count) {
        var _smc_old = array_length(_m.stamp_mc);
        for (var _smc_i = _smc_old; _smc_i < _m.stamp_count; _smc_i++) {
            array_push(_m.stamp_mc, 0);
        }
    }
    if (!variable_struct_exists(_m, "stamp_override")) {
        _m.stamp_override = array_create(_m.stamp_count, 0x80);
    } else if (array_length(_m.stamp_override) < _m.stamp_count) {
        var _sov_old = array_length(_m.stamp_override);
        for (var _sov_i = _sov_old; _sov_i < _m.stamp_count; _sov_i++) {
            array_push(_m.stamp_override, 0x80);
        }
    }

    // Start a brand-new tileset with one empty stamp ready to edit (1 byte/cell).
    if (_m.stamp_count == 0) {
        var _first_cells = _m.stamp_w * _m.stamp_h;
        for (var _fc = 0; _fc < _first_cells; _fc++) {
            array_push(_m.stamp_data, 0);  // char only
        }
        _m.stamp_count = 1;
        if (!variable_struct_exists(_m, "stamp_mc")) _m.stamp_mc = [];
        array_push(_m.stamp_mc, 0);
        if (!variable_struct_exists(_m, "stamp_override")) _m.stamp_override = [];
        array_push(_m.stamp_override, 0x80);
        _m.edit_stamp = 0;
        _m.active_stamp_grid_char = array_create(_first_cells, 0);
        _m.active_stamp_grid_col  = array_create(_first_cells, 0);
        _m.active_stamp_grid_ov   = array_create(_first_cells, 0);
    }
    // Normalise every real-map grid to the current _test_cols * _test_rows.
    // - Width wrong (not a clean multiple of cols) or empty → reset to blank.
    // - Too SHORT (e.g. an old 240-cell/12-row map now that the grid is 13 rows)
    //   → GROW it, padding the new cells with -1 (empty) so existing tiles are
    //   preserved and bottom-row clicks land in-bounds (no out-of-range wipe).
    // - Too LONG → trim the surplus.
    var _want_len = _test_cols * _test_rows;
    for (var _mmi = 0; _mmi < _m.map_count; _mmi++) {
        var _mmi_len = array_length(_m.maps[_mmi]);
        if (_test_cols <= 0 || _mmi_len == 0 || (_mmi_len mod _test_cols) != 0) {
            // Malformed width or empty → blank grid at the expected size.
            _m.maps[_mmi] = array_create(_want_len, -1);
        } else if (_mmi_len < _want_len) {
            // Too short → pad with empty (-1), preserving existing cells.
            var _grown = _m.maps[_mmi];
            for (var _pad = _mmi_len; _pad < _want_len; _pad++) array_push(_grown, -1);
            _m.maps[_mmi] = _grown;
        } else if (_mmi_len > _want_len) {
            // Too long → trim surplus rows from the bottom.
            array_resize(_m.maps[_mmi], _want_len);
        }
    }
    // Active grid reference: test map (-1) or a real map (0+)
    var _active_grid = (_m.active_map >= 0 && _m.active_map < _m.map_count)
                     ? _m.maps[_m.active_map]
                     : _m.test_grid;



    // ---- BYTE COUNT (9b route: stamp-def 1b/cell + char_lut table + placements) ----
    var _mt_size_bytes = 2;
    var _mt_data_bytes = _m.stamp_count * (_m.stamp_w * _m.stamp_h * 1);
    // char_lut table emitted once per tileset; counted at char_lut_len extent.
    var _clut_table_bytes = (_m.char_lut_len > 0) ? _m.char_lut_len : 0;
    if (array_length(_m.map_bytes) != _m.map_count) {
        _m.map_bytes = array_create(_m.map_count, 0);
    }
    var _all_map_bytes = 0;
    for (var _mci = 0; _mci < _m.map_count; _mci++) {
        var _mgrid  = _m.maps[_mci];
        var _placed = 0;
        for (var _mgi = 0; _mgi < array_length(_mgrid); _mgi++) {
            if (_mgrid[_mgi] != -1) _placed++;
        }
        _m.map_bytes[_mci] = 1 + (_placed * 3);
        _all_map_bytes += _m.map_bytes[_mci];
    }
    var _mt_total_bytes = _mt_size_bytes + _mt_data_bytes + _clut_table_bytes + _all_map_bytes;
    _m.total_bytes        = _mt_total_bytes;
    // Split: CHAR LUT (fixed per-tileset) shown separately from METATILE stamp-def.
    _m.clut_bytes_disp    = _clut_table_bytes;                  // char_lut table, paid once
    _m.mt_data_bytes_disp = _mt_size_bytes + _mt_data_bytes;    // stamp-def only (2 header + 1b/cell)
    _m.map_bytes_disp     = _all_map_bytes;
    var _cur_placed = 0;
    for (var _cpi = 0; _cpi < array_length(_active_grid); _cpi++) {
        if (_active_grid[_cpi] != -1) _cur_placed++;
    }
    _m.cur_map_bytes_disp = 1 + (_cur_placed * 3);

    var _has_paint = false;
    var _cells2    = _grid_cells;
    for (var _ci4 = 0; _ci4 < _cells2; _ci4++) {
        if (_m.active_stamp_grid_char[_ci4] != 0) {
            _has_paint = true;
            break;
        }
    }
    draw_set_color(make_color_rgb(18, 22, 30));
    draw_rectangle(_list_x1, _store_y, _list_x2, _store_y + 18, false);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(110, 140, 170));
    draw_set_halign(fa_center);
    var _store_label = (_m.edit_stamp >= 0) ? "EDITING #" + string(_m.edit_stamp) + "  (LIVE)" : "CLICK [ + ] TO ADD";
    draw_text(_list_x1 + (_list_x2 - _list_x1) * 0.5, _store_y + 4, _store_label);
    draw_set_halign(fa_left);

    // ---- EDIT CANVAS ----
    var _canvas_w    = _canvas_x2 - _canvas_x1;
    var _canvas_h    = _canvas_y2 - _canvas_y1;
    // Best-fit zoom: largest whole zoom where the stamp fits both axes.
    // Reserve a little canvas height for the OVR strip at the top so a tall
    // stamp centred in the canvas doesn't run under it.
    var _canvas_h_fit = _canvas_h - 20;   // OVR strip clearance
    var _max_zoom_x   = floor(_canvas_w / (8 * _m.stamp_w));
    var _max_zoom_y   = floor(_canvas_h_fit / (8 * _m.stamp_h));
    var _max_zoom     = max(1, min(_max_zoom_x, _max_zoom_y));
    var _zoom_cap     = _max_zoom;         // best-fit is the max

    // Force best-fit whenever the editor is (re)entered or the stamp size
    // changes. We track the last-seen size + a "fitted" flag on the asset;
    // any mismatch re-snaps zoom to best-fit. Manual wheel-zoom still works
    // afterwards until the next entry/resize.
    var _fit_key = string(_m.stamp_w) + "x" + string(_m.stamp_h);
    if (!variable_struct_exists(_m, "zoom_fit_key") || _m.zoom_fit_key != _fit_key) {
        _m.zoom         = _zoom_cap;   // snap to best-fit
        _m.zoom_fit_key = _fit_key;
    }
    if (_m.zoom == 0)        _m.zoom = _zoom_cap;   // safety for legacy zoom==0
    if (_m.zoom > _zoom_cap) _m.zoom = _zoom_cap;   // never exceed best-fit
    if (_m.zoom == 0)        _m.zoom = _zoom_cap;   // default = best-fit
    if (_m.zoom > _zoom_cap) _m.zoom = _zoom_cap;
    var _zoom    = _m.zoom;
    var _cell_sz = 8 * _zoom;

    draw_set_color(c_black);
    draw_rectangle(_canvas_x1, _canvas_y1, _canvas_x2, _canvas_y2, false);
    draw_set_color(make_color_rgb(40, 40, 60));
    draw_rectangle(_canvas_x1, _canvas_y1, _canvas_x2, _canvas_y2, true);

    var _grid_px_w = _m.stamp_w * _cell_sz;
    var _grid_px_h = _m.stamp_h * _cell_sz;
    var _grid_ox   = floor(_canvas_x1 + ((_canvas_x2 - _canvas_x1) - _grid_px_w) * 0.5);
    var _grid_oy   = floor(_canvas_y1 + ((_canvas_y2 - _canvas_y1) - _grid_px_h) * 0.5);

for (var _row = 0; _row < _m.stamp_h; _row++) {
        for (var _col = 0; _col < _m.stamp_w; _col++) {
            var _cidx   = _row * _m.stamp_w + _col;
            var _char_v = _m.active_stamp_grid_char[_cidx];
            var _ec_rc  = _ecm_mode ? (_char_v mod 64) : _char_v;
            var _ec_bg  = _ecm_mode ? scr_c64_pepto_colour(_ecm_bg_cols[_char_v div 64]) : scr_c64_pepto_colour(_ts_bg);
            // Colour from char_lut; per-stamp override wins
            var _col_v  = _clut_col(_m, _char_v);
            if (_m.edit_stamp >= 0 && _m.edit_stamp < array_length(_m.stamp_override) && _m.stamp_override[_m.edit_stamp] != 0x80) {
                _col_v = _m.stamp_override[_m.edit_stamp];
            }
            var _cx2    = _grid_ox + _col * _cell_sz;
            var _cy3    = _grid_oy + _row * _cell_sz;

            draw_set_color(_ec_bg);
            draw_rectangle(_cx2, _cy3, _cx2 + _cell_sz - 1, _cy3 + _cell_sz - 1, false);

            var _cell_is_mc = (_ts_global_mixed == 1) && (_clut_mc(_m, _char_v) == 1);

            if (_ts_chr_ref != noone && buffer_exists(_ts_chr_ref.buffer)) {
                if (_cell_is_mc) {
                    var _mc_col1 = (_m.map_mc_col1 >= 0) ? _m.map_mc_col1 : 1;
                    var _mc_col2 = (_m.map_mc_col2 >= 0) ? _m.map_mc_col2 : 2;
                    var _mc_pal  = [_ec_bg, scr_c64_pepto_colour(_mc_col1), scr_c64_pepto_colour(_mc_col2), scr_c64_pepto_colour(_col_v & 0x07)];
                    var _mc_pxw  = max(1, _cell_sz / 4);
                    var _mc_pxh  = max(1, _cell_sz / 8);
                    draw_set_color(_mc_pal[0]);
                    draw_rectangle(_cx2, _cy3, _cx2 + _cell_sz - 1, _cy3 + _cell_sz - 1, false);
                    for (var _brow = 0; _brow < 8; _brow++) {
                        var _boff = (_ec_rc * 8) + _brow;
                        if (_boff >= buffer_get_size(_ts_chr_ref.buffer)) break;
                        var _byte = buffer_peek(_ts_chr_ref.buffer, _boff, buffer_u8);
                        for (var _pair = 0; _pair < 4; _pair++) {
                            var _bits = (_byte >> (6 - _pair * 2)) & 0x03;
                            if (_bits == 0) continue;
                            draw_set_color(_mc_pal[_bits]);
                            draw_rectangle(_cx2 + _pair * _mc_pxw, _cy3 + _brow * _mc_pxh, _cx2 + _pair * _mc_pxw + _mc_pxw, _cy3 + _brow * _mc_pxh + _mc_pxh, false);
                        }
                    }
                } else {
                    var _hr_pxw = max(1, _cell_sz / 8);
                    var _hr_pxh = max(1, _cell_sz / 8);
                    var _hr_col = (!_eff_mixed) ? (_col_v & 0x0F) : (_col_v & 0x07);
                    draw_set_color(_ec_bg);
                    draw_rectangle(_cx2, _cy3, _cx2 + _cell_sz - 1, _cy3 + _cell_sz - 1, false);
                    draw_set_color(scr_c64_pepto_colour(_hr_col));
                    for (var _brow = 0; _brow < 8; _brow++) {
                        var _boff = (_ec_rc * 8) + _brow;
                        if (_boff >= buffer_get_size(_ts_chr_ref.buffer)) break;
                        var _byte = buffer_peek(_ts_chr_ref.buffer, _boff, buffer_u8);
                        for (var _bit = 0; _bit < 8; _bit++) {
                            if (_byte & (0x80 >> _bit)) {
                                draw_rectangle(_cx2 + _bit * _hr_pxw, _cy3 + _brow * _hr_pxh, _cx2 + _bit * _hr_pxw + _hr_pxw, _cy3 + _brow * _hr_pxh + _hr_pxh, false);
                            }
                        }
                    }
                }
            } else {
                var _fb_col2 = (!_eff_mixed) ? (_col_v & 0x0F) : (_col_v & 0x07);
                draw_set_color(scr_c64_pepto_colour(_fb_col2));
                draw_rectangle(_cx2 + 2, _cy3 + 2, _cx2 + _cell_sz - 3, _cy3 + _cell_sz - 3, false);
            }

            draw_set_color(make_color_rgb(50, 50, 80));
            draw_rectangle(_cx2, _cy3, _cx2 + _cell_sz - 1, _cy3 + _cell_sz - 1, true);
        }
    }

    // Paint interaction on canvas
    if (point_in_rectangle(_mx, _my, _canvas_x1, _canvas_y1, _canvas_x2, _canvas_y2)) {
        var _hcol2 = floor((_mx - _grid_ox) / _cell_sz);
        var _hrow2 = floor((_my - _grid_oy) / _cell_sz);
        if (_hcol2 >= 0 && _hcol2 < _m.stamp_w && _hrow2 >= 0 && _hrow2 < _m.stamp_h) {
            var _hx2 = _grid_ox + _hcol2 * _cell_sz;
            var _hy2 = _grid_oy + _hrow2 * _cell_sz;
            draw_set_color(c_white);
            draw_set_alpha(0.4);
            draw_rectangle(_hx2, _hy2, _hx2 + _cell_sz, _hy2 + _cell_sz, false);
            draw_set_alpha(1.0);
            draw_rectangle(_hx2, _hy2, _hx2 + _cell_sz, _hy2 + _cell_sz, true);
            var _pidx2 = _hrow2 * _m.stamp_w + _hcol2;
            if (mouse_check_button(mb_left)) {
                // Place char in cell. Colour BAKES into char_lut[active_char]:
                // sets that char's inherited colour everywhere, preserving its
                // existing MC bit (bit 4). active_colour masked to the nibble.
                _m.active_stamp_grid_char[_pidx2] = _m.active_char;
                if (_m.active_char < array_length(_m.char_lut)) {
                    var _existing_mc = _m.char_lut[_m.active_char] & 0x10;
                    _m.char_lut[_m.active_char] = _existing_mc | (_m.active_colour & 0x0F);
                }
                _sync_active_to_stamp(_m);
            }
            if (mouse_check_button(mb_right)) {
                // Erase cell -> char 0 (BKG). Colour of char 0 untouched.
                _m.active_stamp_grid_char[_pidx2] = 0;
                _sync_active_to_stamp(_m);
            }
        }
        if (mouse_wheel_up())   _m.zoom = min(_zoom_cap, _m.zoom + 1);
        if (mouse_wheel_down()) _m.zoom = max(1, _m.zoom - 1);
    }

    // ---- STAMP COLOUR OVERRIDE STRIP (palette + RESET, acts on edit_stamp) ----
    // $80 = no override. MIXED shows lower 8 (wider); HR16 shows all 16.
    // Zoom buttons removed; canvas mouse-wheel still zooms.
    if (_m.edit_stamp >= 0 && _m.edit_stamp < array_length(_m.stamp_override)) {
        var _ov_cur   = _m.stamp_override[_m.edit_stamp];
        var _ov_count = _eff_mixed ? 8 : 16;
        // Single cell-width calc: base width + the ~45px spread across cells.
        var _ov_cw    = (_eff_mixed ? 16 : 8) + ceil(45 / _ov_count);
        var _ov_h     = 16;
        var _ov_y1    = _canvas_y1 + 2;
        var _ov_rst_w  = 44;
        var _ov_rst_x1 = _canvas_x2 - _ov_rst_w - 2;
        var _ov_rst_x2 = _canvas_x2 - 2;
        var _ov_pal_x1 = _ov_rst_x1 - 6 - (_ov_count * _ov_cw);

        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(150, 170, 190));
        draw_text(_canvas_x1 + 6, _ov_y1 + 3, "OVR:");

        for (var _ovi = 0; _ovi < _ov_count; _ovi++) {
            var _ovx1  = _ov_pal_x1 + _ovi * _ov_cw;
            var _ovhov = point_in_rectangle(_mx, _my, _ovx1, _ov_y1, _ovx1 + _ov_cw, _ov_y1 + _ov_h);
            draw_set_color(scr_c64_pepto_colour(_ovi));
            draw_rectangle(_ovx1, _ov_y1, _ovx1 + _ov_cw, _ov_y1 + _ov_h, false);
            if (_ov_cur == _ovi) {
                draw_set_color(c_white);
                draw_rectangle(_ovx1, _ov_y1, _ovx1 + _ov_cw, _ov_y1 + _ov_h, true);
                draw_rectangle(_ovx1 - 1, _ov_y1 - 1, _ovx1 + _ov_cw + 1, _ov_y1 + _ov_h + 1, true);
            }
            if (_ovhov && mouse_check_button_pressed(mb_left)) {
                _m.stamp_override[_m.edit_stamp] = _ovi;
                _m.is_dirty = true;
            }
        }

        var _ov_is_set  = (_ov_cur != 0x80);
        var _ov_rst_hov = point_in_rectangle(_mx, _my, _ov_rst_x1, _ov_y1, _ov_rst_x2, _ov_y1 + _ov_h);
        draw_set_color(_ov_rst_hov ? make_color_rgb(180, 60, 60) : (_ov_is_set ? make_color_rgb(90, 30, 30) : make_color_rgb(40, 40, 50)));
        draw_rectangle(_ov_rst_x1, _ov_y1, _ov_rst_x2, _ov_y1 + _ov_h, false);
        draw_set_color(_ov_is_set ? c_white : make_color_rgb(110, 110, 120));
        draw_set_halign(fa_center);
        draw_text((_ov_rst_x1 + _ov_rst_x2) * 0.5, _ov_y1 + 3, "RESET");
        draw_set_halign(fa_left);
        if (_ov_rst_hov && mouse_check_button_pressed(mb_left)) {
            _m.stamp_override[_m.edit_stamp] = 0x80;
            _m.is_dirty = true;
        }
    }

	// ---- VIEW + OFFSET PICKERS (above the map panel, centered over it) ----
    // VIEW = C64 window size in char cells (default 40x25). OFFSET = window
    // origin in char cells (top-left of the visible frame). OFFSET is bound so
    // the window can't run past the active map's edges. Editing only affects
    // real maps; the TEST map has no stored dimensions to bound against.
    // Clamp VIEW to the map size first, then clamp OFFSET to (map - view).
    var _vo_map_w = 40;
    var _vo_map_h = 25;
    if (_m.active_map >= 0 && _m.active_map < array_length(_m.map_w))
    {
        // map_w/map_h are char cells; align down to whole metatiles so the view
        // window and OFFSET can't extend past the last complete metatile.
        _vo_map_w = floor(_m.map_w[_m.active_map] / _m.stamp_w) * _m.stamp_w;
        _vo_map_h = floor(_m.map_h[_m.active_map] / _m.stamp_h) * _m.stamp_h;
    }
    if (_m.view_w > _vo_map_w) _m.view_w = _vo_map_w;
    if (_m.view_h > _vo_map_h) _m.view_h = _vo_map_h;
    if (_m.offset_x > _vo_map_w - _m.view_w) _m.offset_x = _vo_map_w - _m.view_w;
    if (_m.offset_y > _vo_map_h - _m.view_h) _m.offset_y = _vo_map_h - _m.view_h;
    if (_m.offset_x < 0) _m.offset_x = 0;
    if (_m.offset_y < 0) _m.offset_y = 0;

    // Center a two-group block (VIEW then OFFSET) over the map panel.
    var _vo_gap    = 40;
    var _vo_grp_w  = 150;   // approx width of one W x H group
    var _vo_total  = _vo_grp_w * 2 + _vo_gap;
    var _vo_cx     = _test_x1 + ((_test_x2 - _test_x1) - _vo_total) * 0.5;
    var _vo_y      = _vy1 + 40;

    draw_set_font(fnt_c64_tiny);

    // ===== VIEW GROUP =====
    var _view_lx = _vo_cx;
    draw_set_color(c_ltgray);
    draw_set_halign(fa_left);
    draw_text(_view_lx, _vo_y + 4, "VIEW:");

    // VIEW W - / value / +
    var _vwm_x1 = _view_lx + 40;
    var _vwm_x2 = _vwm_x1 + 14;
    var _vwm_hov = point_in_rectangle(_mx, _my, _vwm_x1, _vo_y, _vwm_x2, _vo_y + 18);
    draw_set_color(_vwm_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_vwm_x1, _vo_y, _vwm_x2, _vo_y + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_vwm_x1 + 7, _vo_y + 4, "-");
    if (_vwm_hov && mouse_check_button_pressed(mb_left))
    {
        _m.view_w = max(1, _m.view_w - 1);
    }
    draw_set_color(c_aqua);
    draw_text(_vwm_x2 + 14, _vo_y + 4, string(_m.view_w));
    var _vwp_x1 = _vwm_x2 + 26;
    var _vwp_x2 = _vwp_x1 + 14;
    var _vwp_hov = point_in_rectangle(_mx, _my, _vwp_x1, _vo_y, _vwp_x2, _vo_y + 18);
    draw_set_color(_vwp_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_vwp_x1, _vo_y, _vwp_x2, _vo_y + 18, false);
    draw_set_color(c_white);
    draw_text(_vwp_x1 + 7, _vo_y + 4, "+");
    if (_vwp_hov && mouse_check_button_pressed(mb_left))
    {
        _m.view_w = min(_vo_map_w, _m.view_w + 1);
    }

    draw_set_color(c_ltgray);
    draw_text(_vwp_x2 + 12, _vo_y + 4, "x");

    // VIEW H - / value / +
    var _vhm_x1 = _vwp_x2 + 22;
    var _vhm_x2 = _vhm_x1 + 14;
    var _vhm_hov = point_in_rectangle(_mx, _my, _vhm_x1, _vo_y, _vhm_x2, _vo_y + 18);
    draw_set_color(_vhm_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_vhm_x1, _vo_y, _vhm_x2, _vo_y + 18, false);
    draw_set_color(c_white);
    draw_text(_vhm_x1 + 7, _vo_y + 4, "-");
    if (_vhm_hov && mouse_check_button_pressed(mb_left))
    {
        _m.view_h = max(1, _m.view_h - 1);
    }
    draw_set_color(c_aqua);
    draw_text(_vhm_x2 + 14, _vo_y + 4, string(_m.view_h));
    var _vhp_x1 = _vhm_x2 + 26;
    var _vhp_x2 = _vhp_x1 + 14;
    var _vhp_hov = point_in_rectangle(_mx, _my, _vhp_x1, _vo_y, _vhp_x2, _vo_y + 18);
    draw_set_color(_vhp_hov ? make_color_rgb(60, 180, 200) : make_color_rgb(30, 80, 100));
    draw_rectangle(_vhp_x1, _vo_y, _vhp_x2, _vo_y + 18, false);
    draw_set_color(c_white);
    draw_text(_vhp_x1 + 7, _vo_y + 4, "+");
    if (_vhp_hov && mouse_check_button_pressed(mb_left))
    {
        _m.view_h = min(_vo_map_h, _m.view_h + 1);
    }

    // ===== OFFSET GROUP =====
    var _off_lx = _vo_cx + _vo_grp_w + _vo_gap;
    draw_set_color(c_ltgray);
    draw_set_halign(fa_left);
    draw_text(_off_lx, _vo_y + 4, "OFFSET:");

    // OFFSET X - / value / +
    var _oxm_x1 = _off_lx + 52;
    var _oxm_x2 = _oxm_x1 + 14;
    var _oxm_hov = point_in_rectangle(_mx, _my, _oxm_x1, _vo_y, _oxm_x2, _vo_y + 18);
    draw_set_color(_oxm_hov ? make_color_rgb(200, 160, 60) : make_color_rgb(90, 70, 20));
    draw_rectangle(_oxm_x1, _vo_y, _oxm_x2, _vo_y + 18, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_oxm_x1 + 7, _vo_y + 4, "-");
    if (_oxm_hov && mouse_check_button_pressed(mb_left))
    {
        _m.offset_x = max(0, _m.offset_x - 1);
    }
    draw_set_color(make_color_rgb(255, 200, 100));
    draw_text(_oxm_x2 + 16, _vo_y + 4, string(_m.offset_x));
    var _oxp_x1 = _oxm_x2 + 30;
    var _oxp_x2 = _oxp_x1 + 14;
    var _oxp_hov = point_in_rectangle(_mx, _my, _oxp_x1, _vo_y, _oxp_x2, _vo_y + 18);
    draw_set_color(_oxp_hov ? make_color_rgb(200, 160, 60) : make_color_rgb(90, 70, 20));
    draw_rectangle(_oxp_x1, _vo_y, _oxp_x2, _vo_y + 18, false);
    draw_set_color(c_white);
    draw_text(_oxp_x1 + 7, _vo_y + 4, "+");
    if (_oxp_hov && mouse_check_button_pressed(mb_left))
    {
        _m.offset_x = min(_vo_map_w - _m.view_w, _m.offset_x + 1);
    }

    draw_set_color(c_ltgray);
    draw_text(_oxp_x2 + 12, _vo_y + 4, "x");

    // OFFSET Y - / value / +
    var _oym_x1 = _oxp_x2 + 22;
    var _oym_x2 = _oym_x1 + 14;
    var _oym_hov = point_in_rectangle(_mx, _my, _oym_x1, _vo_y, _oym_x2, _vo_y + 18);
    draw_set_color(_oym_hov ? make_color_rgb(200, 160, 60) : make_color_rgb(90, 70, 20));
    draw_rectangle(_oym_x1, _vo_y, _oym_x2, _vo_y + 18, false);
    draw_set_color(c_white);
    draw_text(_oym_x1 + 7, _vo_y + 4, "-");
    if (_oym_hov && mouse_check_button_pressed(mb_left))
    {
        _m.offset_y = max(0, _m.offset_y - 1);
    }
    draw_set_color(make_color_rgb(255, 200, 100));
    draw_text(_oym_x2 + 16, _vo_y + 4, string(_m.offset_y));
    var _oyp_x1 = _oym_x2 + 30;
    var _oyp_x2 = _oyp_x1 + 14;
    var _oyp_hov = point_in_rectangle(_mx, _my, _oyp_x1, _vo_y, _oyp_x2, _vo_y + 18);
    draw_set_color(_oyp_hov ? make_color_rgb(200, 160, 60) : make_color_rgb(90, 70, 20));
    draw_rectangle(_oyp_x1, _vo_y, _oyp_x2, _vo_y + 18, false);
    draw_set_color(c_white);
    draw_text(_oyp_x1 + 7, _vo_y + 4, "+");
    if (_oyp_hov && mouse_check_button_pressed(mb_left))
    {
        _m.offset_y = min(_vo_map_h - _m.view_h, _m.offset_y + 1);
    }

    // ===== MAP / VIEW TOGGLE (right of the OFFSET pickers) =====
    // MAP  = show the whole map with the view window drawn over it.
    // VIEW = zoom to just the view window; space / middle-mouse still pans.
    var _mvt_x1 = _oyp_x2 + 40;
    var _mvt_x2 = _mvt_x1 + 70;
    var _mvt_hov = point_in_rectangle(_mx, _my, _mvt_x1, _vo_y, _mvt_x2, _vo_y + 18);
    var _mvt_is_view = (_m.edit_view_mode == 1);
    draw_set_color(_mvt_is_view ? make_color_rgb(10, 50, 80) : make_color_rgb(20, 40, 30));
    draw_rectangle(_mvt_x1, _vo_y, _mvt_x2, _vo_y + 18, false);
    draw_set_color(_mvt_is_view ? make_color_rgb(40, 160, 220) : make_color_rgb(60, 140, 90));
    draw_rectangle(_mvt_x1, _vo_y, _mvt_x2, _vo_y + 18, true);
    draw_set_color(_mvt_is_view ? make_color_rgb(80, 200, 255) : make_color_rgb(120, 220, 150));
    draw_set_halign(fa_center);
    draw_text((_mvt_x1 + _mvt_x2) * 0.5, _vo_y + 2, _mvt_is_view ? "VIEW MODE" : "MAP MODE");
    draw_set_halign(fa_left);
    if (_mvt_hov && mouse_check_button_pressed(mb_left))
    {
        if (_m.edit_view_mode == 0)
        {
            _m.edit_view_mode = 1;
        }
        else
        {
            _m.edit_view_mode = 0;
        }
    }

    // Mouse wheel over the map area zooms continuously: MAP mode zooms up to
    // (and hands off into VIEW mode at) VIEW's own fit zoom, and zooming out
    // from VIEW mode drops back into MAP mode at that same zoom level before
    // continuing to zoom out from there (8px floor). VIEW's W/H spinners
    // still resize the window itself.
    var _wheel_over_map = point_in_rectangle(_mx, _my, _test_x1, _canvas_y1, _test_x2, _canvas_y2);
    if (_wheel_over_map)
    {
        if (_m.edit_view_mode == 0)
        {
            if (!variable_struct_exists(_m, "map_zoom_px") || _m.map_zoom_px <= 0) _m.map_zoom_px = 8;
            var _map_zoom_ceiling = max(8, _view_zoom_cap);
            if (mouse_wheel_up())
            {
                var _next_zoom = _m.map_zoom_px + 4;
                if (_next_zoom >= _map_zoom_ceiling)
                {
                    _m.edit_view_mode = 1;   // zoomed past MAP's cap — hand off to VIEW mode
                }
                else
                {
                    _m.map_zoom_px = _next_zoom;
                }
            }
            if (mouse_wheel_down())
            {
                _m.map_zoom_px = max(8, _m.map_zoom_px - 4);
            }
        }
        else if (mouse_wheel_down())
        {
            // Zooming out from VIEW mode drops into MAP mode at the same
            // zoom level (seamless), ready to keep zooming out from there.
            _m.edit_view_mode = 0;
            _m.map_zoom_px    = max(8, _view_zoom_cap);
        }
    }

    draw_set_halign(fa_left);

	// ---- C: TEST META TILE AREA ----
    var _map_top      = _vy1 + 76;
    var _test_avail_w = _test_x2 - _test_x1;
    var _test_avail_h = _canvas_y2 - _map_top;
    var _test_ox      = _test_x1 + 4 + floor((_test_avail_w - 8 - _test_grid_pw) * 0.5);
    var _test_oy      = _map_top + 60;
    draw_set_color(c_black);
    draw_rectangle(_test_x1, _map_top, _test_x2, _canvas_y2, false);
    draw_set_color(make_color_rgb(40, 40, 60));
    draw_rectangle(_test_x1, _map_top, _test_x2, _canvas_y2, true);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(80, 200, 255));
    draw_text(_test_x1 - 64, _map_top - 3, (_m.active_map < 0) ? "TEST MAP" : "MAP " + string(_m.active_map));

// ---- MAP SELECTOR ROW (wraps + scrolls; 4 visible rows) ----
    var _msel_x0      = _test_x1 + 20;
    var _msel_y0      = _map_top;
    var _msel_bw      = 44;
    var _msel_bh      = 15;
    var _msel_gap     = 4;
    var _msel_lh      = _msel_bh + 7;
    var _msel_per_row = 15;
    var _msel_vis_rows = 3;
    if (!variable_struct_exists(_m, "map_tab_scroll")) _m.map_tab_scroll = 0;
    var _msel_total   = _m.map_count + 2;
    var _msel_rows    = ceil(_msel_total / _msel_per_row);
    var _msel_max_scr = max(0, _msel_rows - _msel_vis_rows);
    if (_m.map_tab_scroll > _msel_max_scr) _m.map_tab_scroll = _msel_max_scr;
    var _msel_scr     = _m.map_tab_scroll;
    var _msel_area_h  = _msel_vis_rows * _msel_lh;
    if (point_in_rectangle(_mx, _my, _msel_x0, _msel_y0, _msel_x0 + _msel_per_row * (_msel_bw + _msel_gap), _msel_y0 + _msel_area_h)) {
        if (mouse_wheel_up())   _m.map_tab_scroll = max(0, _msel_scr - 1);
        if (mouse_wheel_down()) _m.map_tab_scroll = min(_msel_max_scr, _msel_scr + 1);
        _msel_scr = _m.map_tab_scroll;
    }
    for (var _slot = 0; _slot < _msel_total; _slot++) {
        var _scol = _slot mod _msel_per_row;
        var _srow = _slot div _msel_per_row;
        if (_srow < _msel_scr || _srow >= _msel_scr + _msel_vis_rows) continue;
        var _scx  = _msel_x0 + _scol * (_msel_bw + _msel_gap);
        var _scy  = _msel_y0 + (_srow - _msel_scr) * _msel_lh;
        var _shov = point_in_rectangle(_mx, _my, _scx, _scy, _scx + _msel_bw, _scy + _msel_bh);
        if (_slot == 0) {
            var _sel = (_m.active_map < 0);
            draw_set_color(_sel ? make_color_rgb(20, 80, 100) : (_shov ? make_color_rgb(40, 60, 70) : make_color_rgb(20, 25, 30)));
            draw_rectangle(_scx, _scy, _scx + _msel_bw, _scy + _msel_bh, false);
            draw_set_color(_sel ? c_white : make_color_rgb(120, 160, 180));
            draw_set_halign(fa_center);
            draw_text(_scx + _msel_bw * 0.5, _scy , "TEST");
            draw_set_halign(fa_left);
            if (_shov && mouse_check_button_pressed(mb_left)) _m.active_map = -1;
        } else if (_slot <= _m.map_count) {
            var _mbi = _slot - 1;
            var _sel = (_m.active_map == _mbi);
            draw_set_color(_sel ? make_color_rgb(30, 90, 50) : (_shov ? make_color_rgb(40, 60, 45) : make_color_rgb(20, 28, 22)));
            draw_rectangle(_scx, _scy, _scx + _msel_bw, _scy + _msel_bh, false);
            draw_set_color(_sel ? c_white : make_color_rgb(120, 180, 140));
            draw_set_halign(fa_center);
            draw_text(_scx + _msel_bw * 0.5, _scy , "MAP " + string(_mbi));
            draw_set_halign(fa_left);
            if (_shov && mouse_check_button_pressed(mb_left)) _m.active_map = _mbi;
            if (_shov && mouse_check_button_pressed(mb_right) && _m.map_count > 0) {
                array_delete(_m.maps, _mbi, 1);
                if (array_length(_m.map_bytes) > _mbi) array_delete(_m.map_bytes, _mbi, 1);
                _m.map_count = max(0, _m.map_count - 1);
                if (_m.active_map >= _m.map_count) _m.active_map = _m.map_count - 1;
                _m.is_dirty = true;
            }
        } else {
            draw_set_color(_shov ? make_color_rgb(60, 180, 80) : make_color_rgb(25, 70, 35));
            draw_rectangle(_scx, _scy, _scx + _msel_bw, _scy + _msel_bh, false);
            draw_set_color(c_white);
            draw_set_halign(fa_center);
            draw_text(_scx + _msel_bw * 0.5, _scy , "+ ADD");
            draw_set_halign(fa_left);
            if (_shov && mouse_check_button_pressed(mb_left)) {
                // All maps in a tileset share one W/H. Inherit the existing size
                // (map 0), falling back to the screen default when no map exists.
                var _add_w = 40;
                var _add_h = 25;
                if (array_length(_m.map_w) > 0) {
                    _add_w = _m.map_w[0];
                    _add_h = _m.map_h[0];
                }
                var _add_cols = floor(_add_w / _m.stamp_w);
                var _add_rows = floor(_add_h / _m.stamp_h);
                array_push(_m.maps, array_create(_add_cols * _add_rows, -1));
                array_push(_m.map_bytes, 0);
                array_push(_m.map_w, _add_w);
                array_push(_m.map_h, _add_h);
                _m.map_count++;
                _m.active_map = _m.map_count - 1;
                _m.is_dirty = true;
                var _new_total = _m.map_count + 2;
                var _new_rows  = ceil(_new_total / _msel_per_row);
                _m.map_tab_scroll = max(0, _new_rows - _msel_vis_rows);
            }
        }
    }
    // ---- SCROLL ARROWS (right end of tab block) ----
    if (_msel_rows > _msel_vis_rows) {
        var _msarr_x = _msel_x0 + _msel_per_row * (_msel_bw + _msel_gap) + 2;
        var _msup_hov = point_in_rectangle(_mx, _my, _msarr_x, _msel_y0, _msarr_x + 16, _msel_y0 + 14);
        draw_set_color(_msup_hov ? c_white : (_msel_scr > 0 ? make_color_rgb(160, 160, 200) : make_color_rgb(50, 50, 70)));
        draw_rectangle(_msarr_x, _msel_y0, _msarr_x + 16, _msel_y0 + 14, false);
        draw_set_color(c_black);
        draw_set_halign(fa_center);
        draw_text(_msarr_x + 8, _msel_y0 + 2, "^");
        var _msdn_y = _msel_y0 + 16;
        var _msdn_hov = point_in_rectangle(_mx, _my, _msarr_x, _msdn_y, _msarr_x + 16, _msdn_y + 14);
        draw_set_color(_msdn_hov ? c_white : (_msel_scr < _msel_max_scr ? make_color_rgb(160, 160, 200) : make_color_rgb(50, 50, 70)));
        draw_rectangle(_msarr_x, _msdn_y, _msarr_x + 16, _msdn_y + 14, false);
        draw_set_color(c_black);
        draw_text(_msarr_x + 8, _msdn_y + 2, "v");
        draw_set_halign(fa_left);
        if (_msup_hov && mouse_check_button_pressed(mb_left)) _m.map_tab_scroll = max(0, _msel_scr - 1);
        if (_msdn_hov && mouse_check_button_pressed(mb_left)) _m.map_tab_scroll = min(_msel_max_scr, _msel_scr + 1);
    }

    var _tsx_scale   = window_get_width()  / global.gui_w;
    var _tsy_scale   = window_get_height() / display_get_gui_height();
    var _test_clip_h = _test_rows * _m.stamp_h * _test_cs;

    // VIEW mode: scissor to the exact char window so partial metatiles at the
    // edges are cropped, giving char-accurate framing. The draw origin is nudged
    // left/up by the sub-metatile shift (in pixels) so the window's char (0,0)
    // sits at the panel origin.
    var _view_px_shift_x = _view_shift_x * _test_cs;
    var _view_px_shift_y = _view_shift_y * _test_cs;
    if (_m.edit_view_mode == 1 && _m.active_map >= 0)
    {
        var _vclip_sx = window_get_width()  / global.gui_w;
        var _vclip_sy = window_get_height() / display_get_gui_height();
        gpu_set_scissor(
            floor(_test_ox * _vclip_sx), floor(_test_oy * _vclip_sy),
            ceil(_m.view_w * _test_cs * _vclip_sx), ceil(_m.view_h * _test_cs * _vclip_sy)
        );
    }
    else
    {
        // MAP mode (zoomed-out full map): _test_cs has a 4px-per-char floor,
        // so a big map (e.g. 300x6 metatiles) can render wider/taller than
        // the panel. Clip to the panel bounds so overflow is cropped instead
        // of leaking into the rest of the UI.
        var _mclip_sx = window_get_width()  / global.gui_w;
        var _mclip_sy = window_get_height() / display_get_gui_height();
        gpu_set_scissor(
            floor(_test_x1 * _mclip_sx), floor(_map_top_fit * _mclip_sy),
            ceil((_test_x2 - _test_x1) * _mclip_sx), ceil((_canvas_y2 - _map_top_fit) * _mclip_sy)
        );
    }

    for (var _trow = _draw_row0; _trow < _draw_row1; _trow++) {
        for (var _tcol = _draw_col0; _tcol < _draw_col1; _tcol++) {
            var _tidx = _trow * _test_cols + _tcol;
            if (_tidx >= array_length(_active_grid)) continue;
            var _tstamp_idx = _active_grid[_tidx];
            // Screen position is relative to the drawn range start, minus the
            // sub-metatile pixel shift so the exact char window aligns to origin.
            var _tax        = _test_ox + (_tcol - _draw_col0) * _m.stamp_w * _test_cs - _view_px_shift_x;
            var _tay        = _test_oy + (_trow - _draw_row0) * _m.stamp_h * _test_cs - _view_px_shift_y;
            var _tcw        = _m.stamp_w * _test_cs;
            var _tch        = _m.stamp_h * _test_cs;

            draw_set_color(scr_c64_pepto_colour(_ts_bg));
            draw_rectangle(_tax, _tay, _tax + _tcw - 1, _tay + _tch - 1, false);
            draw_set_color(make_color_rgb(30, 30, 50));
            draw_rectangle(_tax, _tay, _tax + _tcw - 1, _tay + _tch - 1, true);

            if (_tstamp_idx >= 0 && _tstamp_idx < _m.stamp_count) {
                for (var _scr2 = 0; _scr2 < _m.stamp_h; _scr2++) {
                    for (var _scc2 = 0; _scc2 < _m.stamp_w; _scc2++) {
                        var _scidx = _tstamp_idx * _m.stamp_w * _m.stamp_h + _scr2 * _m.stamp_w + _scc2;
                        if (_scidx >= array_length(_m.stamp_data)) continue;
                        var _tsc   = _m.stamp_data[_scidx];
                        var _tt_rc = _ecm_mode ? (_tsc mod 64) : _tsc;
                        var _tt_bg = _ecm_mode ? scr_c64_pepto_colour(_ecm_bg_cols[_tsc div 64]) : scr_c64_pepto_colour(_ts_bg);
                        // Colour from char_lut; per-stamp override wins
                        var _tscol = _clut_col(_m, _tsc);
                        if (_tstamp_idx < array_length(_m.stamp_override) && _m.stamp_override[_tstamp_idx] != 0x80) {
                            _tscol = _m.stamp_override[_tstamp_idx];
                        }
                        var _spx   = _tax + _scc2 * _test_cs;
                        var _spy   = _tay + _scr2 * _test_cs;
                        var _ts_mc = (_ts_global_mixed == 1) && (_clut_mc(_m, _tsc) == 1);

                        draw_set_color(_tt_bg);
                        draw_rectangle(_spx, _spy, _spx + _test_cs - 1, _spy + _test_cs - 1, false);

                        if (_ts_chr_ref != noone && buffer_exists(_ts_chr_ref.buffer)) {
                            if (_ts_mc) {
                                var _tmc1 = (_m.map_mc_col1 >= 0) ? _m.map_mc_col1 : 1;
                                var _tmc2 = (_m.map_mc_col2 >= 0) ? _m.map_mc_col2 : 2;
                                var _tpal = [_tt_bg, scr_c64_pepto_colour(_tmc1), scr_c64_pepto_colour(_tmc2), scr_c64_pepto_colour(_tscol & 0x07)];
                                var _tpxw = max(1, _test_cs / 4);
                                var _tpxh = max(1, _test_cs / 8);
                                draw_set_color(_tpal[0]);
                                draw_rectangle(_spx, _spy, _spx + _test_cs - 1, _spy + _test_cs - 1, false);
                                for (var _tbr = 0; _tbr < 8; _tbr++) {
                                    var _tboff = (_tt_rc * 8) + _tbr;
                                    if (_tboff >= buffer_get_size(_ts_chr_ref.buffer)) break;
                                    var _tbyte = buffer_peek(_ts_chr_ref.buffer, _tboff, buffer_u8);
                                    for (var _tpair = 0; _tpair < 4; _tpair++) {
                                        var _tbits = (_tbyte >> (6 - _tpair * 2)) & 0x03;
                                        if (_tbits == 0) continue;
                                        draw_set_color(_tpal[_tbits]);
                                        draw_rectangle(_spx + _tpair * _tpxw, _spy + _tbr * _tpxh, _spx + _tpair * _tpxw + _tpxw, _spy + _tbr * _tpxh + _tpxh, false);
                                    }
                                }
                            } else {
                                var _thr_col = (!_eff_mixed) ? (_tscol & 0x0F) : (_tscol & 0x07);
                                var _tpxw2   = max(1, _test_cs / 8);
                                var _tpxh2   = max(1, _test_cs / 8);
                                draw_set_color(scr_c64_pepto_colour(_thr_col));
                                for (var _tbr = 0; _tbr < 8; _tbr++) {
                                    var _tboff = (_tt_rc * 8) + _tbr;
                                    if (_tboff >= buffer_get_size(_ts_chr_ref.buffer)) break;
                                    var _tbyte = buffer_peek(_ts_chr_ref.buffer, _tboff, buffer_u8);
                                    for (var _tbit = 0; _tbit < 8; _tbit++) {
                                        if (_tbyte & (0x80 >> _tbit)) {
                                            draw_rectangle(_spx + _tbit * _tpxw2, _spy + _tbr * _tpxh2, _spx + _tbit * _tpxw2 + _tpxw2, _spy + _tbr * _tpxh2 + _tpxh2, false);
                                        }
                                    }
                                }
                            }
                        } else {
                            var _tfb = (!_eff_mixed) ? (_tscol & 0x0F) : (_tscol & 0x07);
                            draw_set_color(scr_c64_pepto_colour(_tfb));
                            draw_rectangle(_spx + 1, _spy + 1, _spx + _test_cs - 2, _spy + _test_cs - 2, false);
                        }

                        // ---- T OVERLAY: per-cell tile-type badge ----
                        // Shows the type COLL_ADV will scan for this char. One
                        // badge per char-cell of the metatile; only non-zero.
                        // Keyed on the REAL char so all 4 ECM bands share a type.
                        if (_m.show_types_overlay
                         && _ts_chr_ref != noone
                         && variable_struct_exists(_ts_chr_ref.meta, "tile_types")
                         && _tt_rc < array_length(_ts_chr_ref.meta.tile_types)) {
                            var _ov_tt = _ts_chr_ref.meta.tile_types[_tt_rc];
                            if (_ov_tt > 0) {
                                var _ov_badge_cols = [
                                    0,
                                    make_color_rgb(200,  60,  60),
                                    make_color_rgb( 60, 140, 220),
                                    make_color_rgb(200, 160,  60),
                                    make_color_rgb( 80, 200, 120),
                                    make_color_rgb(200,  80, 200),
                                    make_color_rgb(220, 220,  80),
                                    make_color_rgb( 80, 220, 220),
                                    make_color_rgb(220, 140,  60),
                                    make_color_rgb(140,  80, 220),
                                    make_color_rgb(120, 200,  60),
                                    make_color_rgb(220,  60, 140),
                                    make_color_rgb( 60, 200, 160),
                                    make_color_rgb(180, 100,  40),
                                    make_color_rgb(120, 120, 200),
                                    make_color_rgb(200, 200, 140),
                                    make_color_rgb(160, 160, 160)
                                ];
                                draw_set_color(_ov_badge_cols[clamp(_ov_tt, 0, 16)]);
                                draw_rectangle(_spx, _spy, _spx + 12, _spy + 8, false);
                                draw_set_color(c_black);
                                draw_rectangle(_spx, _spy, _spx + 12, _spy + 8, true);
                                draw_set_color(c_white);
                                draw_set_font(fnt_c64_tiny);
                                draw_set_halign(fa_left);
                                draw_text(_spx + 1, _spy, "T" + string(_ov_tt));
                            }
                        }
                    }
                }
            }
        }
    }
	gpu_set_scissor(0, 0, window_get_width(), window_get_height());

    // ---- MAP MODE SCROLLBARS (shown only when the map doesn't fit the panel) ----
    if (_m.edit_view_mode == 0 && _m.active_map >= 0) {
        var _sb_track_col = make_color_rgb(20, 20, 30);
        var _sb_thumb_col = make_color_rgb(90, 90, 130);
        var _sb_thumb_hov = make_color_rgb(130, 130, 190);

        if (_test_cols > _map_vis_cols) {
            var _hsb_x1 = _test_x1 + 4;
            var _hsb_x2 = _test_x2 - 4;
            var _hsb_y1 = _canvas_y2 - 10;
            var _hsb_y2 = _canvas_y2 - 4;
            var _hsb_w    = _hsb_x2 - _hsb_x1;
            var _hthumb_w = max(20, _hsb_w * (_map_vis_cols / _test_cols));
            var _hthumb_x = _hsb_x1 + (_hsb_w - _hthumb_w) * (_m.map_pan_col / max(1, _test_cols - _map_vis_cols));
            draw_set_color(_sb_track_col);
            draw_rectangle(_hsb_x1, _hsb_y1, _hsb_x2, _hsb_y2, false);
            var _hthumb_hov = point_in_rectangle(_mx, _my, _hthumb_x, _hsb_y1, _hthumb_x + _hthumb_w, _hsb_y2);
            draw_set_color(_hthumb_hov ? _sb_thumb_hov : _sb_thumb_col);
            draw_rectangle(_hthumb_x, _hsb_y1, _hthumb_x + _hthumb_w, _hsb_y2, false);
            if (_hthumb_hov && mouse_check_button_pressed(mb_left)) {
                _m.hsb_drag_active    = true;
                _m.hsb_drag_start_mx  = _mx;
                _m.hsb_drag_start_col = _m.map_pan_col;
            }
            if (variable_struct_exists(_m, "hsb_drag_active") && _m.hsb_drag_active) {
                if (mouse_check_button(mb_left)) {
                    var _hdx_cols = (_mx - _m.hsb_drag_start_mx) / max(1, _hsb_w - _hthumb_w) * (_test_cols - _map_vis_cols);
                    _m.map_pan_col = clamp(round(_m.hsb_drag_start_col + _hdx_cols), 0, max(0, _test_cols - _map_vis_cols));
                } else {
                    _m.hsb_drag_active = false;
                }
            }
        }

        if (_test_rows > _map_vis_rows) {
            var _vsb_y1 = _map_top + 4;
            var _vsb_y2 = _canvas_y2 - 14;
            var _vsb_x1 = _test_x2 - 10;
            var _vsb_x2 = _test_x2 - 4;
            var _vsb_h    = _vsb_y2 - _vsb_y1;
            var _vthumb_h = max(20, _vsb_h * (_map_vis_rows / _test_rows));
            var _vthumb_y = _vsb_y1 + (_vsb_h - _vthumb_h) * (_m.map_pan_row / max(1, _test_rows - _map_vis_rows));
            draw_set_color(_sb_track_col);
            draw_rectangle(_vsb_x1, _vsb_y1, _vsb_x2, _vsb_y2, false);
            var _vthumb_hov = point_in_rectangle(_mx, _my, _vsb_x1, _vthumb_y, _vsb_x2, _vthumb_y + _vthumb_h);
            draw_set_color(_vthumb_hov ? _sb_thumb_hov : _sb_thumb_col);
            draw_rectangle(_vsb_x1, _vthumb_y, _vsb_x2, _vthumb_y + _vthumb_h, false);
            if (_vthumb_hov && mouse_check_button_pressed(mb_left)) {
                _m.vsb_drag_active    = true;
                _m.vsb_drag_start_my  = _my;
                _m.vsb_drag_start_row = _m.map_pan_row;
            }
            if (variable_struct_exists(_m, "vsb_drag_active") && _m.vsb_drag_active) {
                if (mouse_check_button(mb_left)) {
                    var _vdy_rows = (_my - _m.vsb_drag_start_my) / max(1, _vsb_h - _vthumb_h) * (_test_rows - _map_vis_rows);
                    _m.map_pan_row = clamp(round(_m.vsb_drag_start_row + _vdy_rows), 0, max(0, _test_rows - _map_vis_rows));
                } else {
                    _m.vsb_drag_active = false;
                }
            }
        }
    }

	var _leftSide = 170;
    // Overlay status hint when active
    if (_m.show_types_overlay) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(180, 250, 230));
        draw_set_halign(fa_left);
        draw_text(_test_x1 + _leftSide, _canvas_y2 + 2, "TYPE OVERLAY PREVIEWING [T]");
    }
	if (!_m.show_types_overlay)
	{
		draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(130, 200, 170));
        draw_set_halign(fa_left);
        draw_text(_test_x1 + _leftSide, _canvas_y2 + 2, "TO SEE TYPE OVERLAY PRESS [T]");
	}

	// ---- SHORTCUT KEY LIST ----
    draw_set_font(fnt_c64_tiny);
    draw_set_halign(fa_left);
    draw_set_color(make_color_rgb(120, 190, 160));
    var _sk_line1 = "[CTRL+D] DESELECT     [CTRL+C/V] COPY/PASTE METATILE     [ALT+CLICK] PICK METATILE FROM MAP";
    var _sk_line2 = "[SPACE / MID-MOUSE] PAN VIEW     [ALT + LMB/RMB] CYCLE TILE TYPE (ON TILE STRIP)";
	
    draw_text(_test_x1 + _leftSide, _canvas_y2 + 14, _sk_line1);
    draw_text(_test_x1 + _leftSide, _canvas_y2 + 26, _sk_line2);

    // ---- TEST MAP overlay — red border + faded label (only on the test map) ----
    if (_m.active_map < 0) {
        var _tm_gx1 = _test_ox;
        var _tm_gy1 = _test_oy;
        var _tm_gx2 = _test_ox + _test_cols * _m.stamp_w * _test_cs;
        var _tm_gy2 = _test_oy + _test_rows * _m.stamp_h * _test_cs;
        draw_set_color(make_color_rgb(220, 40, 40));
        draw_rectangle(_tm_gx1 - 1, _tm_gy1 - 1, _tm_gx2 + 1, _tm_gy2 + 1, true);
        draw_rectangle(_tm_gx1 - 2, _tm_gy1 - 2, _tm_gx2 + 2, _tm_gy2 + 2, true);
        draw_set_font(fnt_C64_Angled_big);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_set_color(make_color_rgb(220, 40, 40));
        draw_set_alpha(0.5);
        var _tm_cx = (_tm_gx1 + _tm_gx2) * 0.5;
        var _tm_cy = (_tm_gy1 + _tm_gy2) * 0.3;
        // Scale the label to the grid so it stays proportionate as the cell
        // size changes. Reference grid width / nominal full-size width gives a
        // factor that shrinks the text in lockstep with the map.
        var _tm_scale = (_tm_gx2 - _tm_gx1) / 320;
        _tm_scale = clamp(_tm_scale, 0.5, 3);
        draw_text_transformed(_tm_cx, _tm_cy, "TEST MAP", _tm_scale, _tm_scale, 0);
        draw_set_alpha(1.0);
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
    }

  // Test area interaction (suppressed while the SLICE modal is open)
    if (!global.integer_box_open && point_in_rectangle(_mx, _my, _test_x1, _map_top, _test_x2, _canvas_y2)) {
        // Screen cell -> grid cell. VIEW mode draws from _draw_col0/_draw_row0
        // with a sub-metatile pixel shift, so add that shift back into the mouse
        // pixel before dividing, then add the draw-range start.
        var _thcol = floor((_mx - _test_ox + _view_px_shift_x) / (_m.stamp_w * _test_cs)) + _draw_col0;
        var _throw = floor((_my - _test_oy + _view_px_shift_y) / (_m.stamp_h * _test_cs)) + _draw_row0;

        // VIEW MOVE: space held OR middle-mouse held moves the view window so
        // its centre sits on the hovered cell (in char cells). Real maps only —
        // the TEST map has no stored dimensions to bound against. Clamped so
        // the window can't leave the map. Takes priority over paint/erase.
		var _view_move = (keyboard_check(vk_space) || mouse_check_button(mb_middle));
        if (_view_move && _m.active_map >= 0
         && _m.active_map < array_length(_m.map_w)
         && _m.active_map < array_length(_m.map_h))
        {
            if (_m.edit_view_mode == 1)
            {
                // VIEW MODE: GRAB-RELEASE pan. Mouse position in CHAR cells from
                // the panel origin, so we can measure raw travel.
                var _mouse_cx = (_mx - _test_ox) / _test_cs;
                var _mouse_cy = (_my - _test_oy) / _test_cs;

                // On the frame the grab begins, record the mouse point and the
                // offset then. pan_anchor < 0 means "not currently panning".
                if (_m.pan_anchor_x < 0)
                {
                    _m.pan_anchor_x = _mouse_cx;
                    _m.pan_anchor_y = _mouse_cy;
                    _m.pan_start_ox = _m.offset_x;
                    _m.pan_start_oy = _m.offset_y;
                }

                // Shift the offset opposite to the mouse travel so the grabbed
                // map point stays glued under the cursor.
                var _drag_dx = _mouse_cx - _m.pan_anchor_x;
                var _drag_dy = _mouse_cy - _m.pan_anchor_y;
                var _new_ox = _m.pan_start_ox - _drag_dx;
                var _new_oy = _m.pan_start_oy - _drag_dy;

                var _vm_map_w = _m.map_w[_m.active_map];
                var _vm_map_h = _m.map_h[_m.active_map];
                _new_ox = clamp(_new_ox, 0, max(0, _vm_map_w - _m.view_w));
                _new_oy = clamp(_new_oy, 0, max(0, _vm_map_h - _m.view_h));

                _m.offset_x = round(_new_ox);
                _m.offset_y = round(_new_oy);
            }
            else
            {
                // MAP MODE: drag-pan the camera in metatile units instead of
                // moving the (possibly offscreen) view window. Same
                // grab-release pattern as VIEW mode's pan above, just against
                // map_pan_col/map_pan_row.
                var _mouse_mcx = (_mx - _test_ox) / (_test_cs * _m.stamp_w);
                var _mouse_mcy = (_my - _test_oy) / (_test_cs * _m.stamp_h);

                if (!variable_struct_exists(_m, "map_pan_anchor_x"))  _m.map_pan_anchor_x  = -1;
                if (!variable_struct_exists(_m, "map_pan_anchor_y"))  _m.map_pan_anchor_y  = -1;
                if (!variable_struct_exists(_m, "map_pan_start_col")) _m.map_pan_start_col = 0;
                if (!variable_struct_exists(_m, "map_pan_start_row")) _m.map_pan_start_row = 0;

                if (_m.map_pan_anchor_x < 0)
                {
                    _m.map_pan_anchor_x  = _mouse_mcx;
                    _m.map_pan_anchor_y  = _mouse_mcy;
                    _m.map_pan_start_col = _m.map_pan_col;
                    _m.map_pan_start_row = _m.map_pan_row;
                }

                var _mdrag_dx = _mouse_mcx - _m.map_pan_anchor_x;
                var _mdrag_dy = _mouse_mcy - _m.map_pan_anchor_y;
                var _new_pan_col = _m.map_pan_start_col - _mdrag_dx;
                var _new_pan_row = _m.map_pan_start_row - _mdrag_dy;

                _new_pan_col = clamp(_new_pan_col, 0, max(0, _test_cols - _map_vis_cols));
                _new_pan_row = clamp(_new_pan_row, 0, max(0, _test_rows - _map_vis_rows));

                _m.map_pan_col = round(_new_pan_col);
                _m.map_pan_row = round(_new_pan_row);
            }
        }
        else if (_thcol >= 0 && _thcol < _test_cols && _throw >= 0 && _throw < _test_rows) {
            // Pan ended (not view-moving) — clear the anchors so the next pan
            // re-anchors at its own start point.
            _m.pan_anchor_x = -1;
            _m.pan_anchor_y = -1;
            if (variable_struct_exists(_m, "map_pan_anchor_x")) _m.map_pan_anchor_x = -1;
            if (variable_struct_exists(_m, "map_pan_anchor_y")) _m.map_pan_anchor_y = -1;
            var _thx = _test_ox + (_thcol - _draw_col0) * _m.stamp_w * _test_cs - _view_px_shift_x;
            var _thy = _test_oy + (_throw - _draw_row0) * _m.stamp_h * _test_cs - _view_px_shift_y;
            draw_set_color(c_white);
            draw_set_alpha(0.25);
            draw_rectangle(_thx, _thy, _thx + _m.stamp_w * _test_cs, _thy + _m.stamp_h * _test_cs, false);
            draw_set_alpha(1.0);
            draw_rectangle(_thx, _thy, _thx + _m.stamp_w * _test_cs, _thy + _m.stamp_h * _test_cs, true);
            var _tgidx = _throw * _test_cols + _thcol;
            if (mouse_check_button_pressed(mb_left) || mouse_check_button_pressed(mb_right)) {
                if (!variable_struct_exists(_m, "mt_undo_stack")) _m.mt_undo_stack = [];
                if (!variable_struct_exists(_m, "mt_redo_stack")) _m.mt_redo_stack = [];
                array_push(_m.mt_undo_stack, {
                    map_idx: _m.active_map,
                    grid:    array_copy_shallow(_active_grid)
                });
                _m.mt_redo_stack = [];
                if (array_length(_m.mt_undo_stack) > 50) array_delete(_m.mt_undo_stack, 0, 1);
            }
            // ALT + left-click: PICK the metatile under the cursor (select it as
            // the active stamp) instead of placing. Only if a real stamp is there.
            if (keyboard_check(vk_alt) && mouse_check_button_pressed(mb_left)) {
                var _picked = _active_grid[_tgidx];
                if (_picked >= 0 && _picked < _m.stamp_count) {
                    _m.edit_stamp = _picked;
                    var _pick_cells = _m.stamp_w * _m.stamp_h;
                    _m.active_stamp_grid_char = array_create(_pick_cells, 0);
                    _m.active_stamp_grid_col  = array_create(_pick_cells, 0);
                    _m.active_stamp_grid_ov   = array_create(_pick_cells, 0);
                    var _pick_off = _picked * _pick_cells;
                    for (var _pk = 0; _pk < _pick_cells; _pk++) {
                        var _pk_idx = _pick_off + _pk;
                        if (_pk_idx < array_length(_m.stamp_data)) {
                            _m.active_stamp_grid_char[_pk] = _m.stamp_data[_pk_idx];
                        }
                    }
                }
            }
            else if (mouse_check_button(mb_left) && _m.edit_stamp >= 0) {
                _active_grid[_tgidx] = _m.edit_stamp;
                _m.is_dirty = true;
            }
            if (mouse_check_button(mb_right)) {
                _active_grid[_tgidx] = -1;
                _m.is_dirty = true;
            }
        }
    }
	
    // Clear test area button
    var _tclr_x1  = _test_x1 - 64;
    var _tclr_x2  = _tclr_x1 + 50;
    var _tclr_y1  = _map_top + 20;
    var _tclr_y2  = _tclr_y1 + 16;
    var _tclr_hov = point_in_rectangle(_mx, _my, _tclr_x1, _tclr_y1, _tclr_x2, _tclr_y2);
    draw_set_color(_tclr_hov ? make_color_rgb(180, 40, 40) : make_color_rgb(80, 20, 20));
    draw_rectangle(_tclr_x1, _tclr_y1, _tclr_x2, _tclr_y2, false);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_tclr_x1 + 23, _tclr_y1 + 1, "CLEAR");
    draw_set_halign(fa_left);

    // ---- COPY MAP button ----
    var _cpym_y1  = _tclr_y2 + 4;
    var _cpym_y2  = _cpym_y1 + 16;
    var _cpym_hov = point_in_rectangle(_mx, _my, _tclr_x1, _cpym_y1, _tclr_x2, _cpym_y2);
    draw_set_color(_cpym_hov ? make_color_rgb(40, 110, 160) : make_color_rgb(20, 50, 75));
    draw_rectangle(_tclr_x1, _cpym_y1, _tclr_x2, _cpym_y2, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_text(_tclr_x1 + 23, _cpym_y1 + 1, "COPY");
    draw_set_halign(fa_left);
    if (_cpym_hov && mouse_check_button_pressed(mb_left)) {
        metamap_clip_grid = array_copy_shallow(_active_grid);
        metamap_clip_cols = _test_cols;
        metamap_clip_rows = _test_rows;
    }

    // ---- PASTE MAP button ----
    var _pstm_y1  = _cpym_y2 + 4;
    var _pstm_y2  = _pstm_y1 + 16;
    var _clip_ok  = (metamap_clip_grid != -1
                  && metamap_clip_cols == _test_cols
                  && metamap_clip_rows == _test_rows);
    var _pstm_hov = point_in_rectangle(_mx, _my, _tclr_x1, _pstm_y1, _tclr_x2, _pstm_y2);
    if (_clip_ok) {
        draw_set_color(_pstm_hov ? make_color_rgb(60, 160, 90) : make_color_rgb(25, 70, 40));
    } else {
        draw_set_color(make_color_rgb(35, 35, 40));
    }
    draw_rectangle(_tclr_x1, _pstm_y1, _tclr_x2, _pstm_y2, false);
    draw_set_color(_clip_ok ? c_white : make_color_rgb(90, 90, 100));
    draw_set_halign(fa_center);
    draw_text(_tclr_x1 + 23, _pstm_y1 + 1, "PASTE");
    draw_set_halign(fa_left);
    if (_clip_ok && _pstm_hov && mouse_check_button_pressed(mb_left)) {
        if (!variable_struct_exists(_m, "mt_undo_stack")) _m.mt_undo_stack = [];
        if (!variable_struct_exists(_m, "mt_redo_stack")) _m.mt_redo_stack = [];
        array_push(_m.mt_undo_stack, {
            map_idx: _m.active_map,
            grid:    array_copy_shallow(_active_grid)
        });
        _m.mt_redo_stack = [];
        if (array_length(_m.mt_undo_stack) > 50) array_delete(_m.mt_undo_stack, 0, 1);
        var _paste = array_copy_shallow(metamap_clip_grid);
        if (_m.active_map < 0) {
            _m.test_grid = _paste;
        } else {
            _m.maps[_m.active_map] = _paste;
        }
        _m.is_dirty = true;
    }
    if (_tclr_hov && mouse_check_button_pressed(mb_left)) {
        if (!variable_struct_exists(_m, "mt_undo_stack")) _m.mt_undo_stack = [];
        if (!variable_struct_exists(_m, "mt_redo_stack")) _m.mt_redo_stack = [];
        array_push(_m.mt_undo_stack, {
            map_idx: _m.active_map,
            grid:    array_copy_shallow(_active_grid)
        });
        _m.mt_redo_stack = [];
        if (array_length(_m.mt_undo_stack) > 50) array_delete(_m.mt_undo_stack, 0, 1);
        if (_m.active_map < 0) {
            _m.test_grid = array_create(_test_cols * _test_rows, -1);
        } else {
            _m.maps[_m.active_map] = array_create(_test_cols * _test_rows, -1);
        }
        _m.is_dirty  = true;
    }

    // ---- A: CHAR EDITOR (bottom left, below stamp list) ----
    if (_ts_chr_ref != noone) {
        var _ced_x    = _list_x1;
        var _ced_y    = _canvas_y2 + _store_btn_h + 30;
		draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(120, 200, 255));
        draw_text(_ced_x, _ced_y - 16, "CHAR EDIT PANEL");
        var _mtd_b = variable_struct_exists(_m, "mt_data_bytes_disp") ? _m.mt_data_bytes_disp : 0;
        draw_set_color(make_color_rgb(140, 160, 180));
        draw_text(_ced_x , _ced_y - 46, "METATILE DATA: " + string(_mtd_b) + " b");
		;

        // ---- PER-CHAR HR/MC TOGGLE (writes char_lut bit 4, preserves colour) ----
        _m.char_lut_len = _ts_chr_ref.meta.char_count;
        var _clut_mode  = (_m.active_char < array_length(_m.char_lut)) ? ((_m.char_lut[_m.active_char] >> 4) & 0x01) : 0;
        var _clbx1      = _ced_x + 138;
        var _clby1      = _ced_y - 40;
        var _clbx2      = _clbx1 + 64;
        var _clby2      = _clby1 + 32;
        var _clbhov     = point_in_rectangle(_mx, _my, _clbx1, _clby1, _clbx2, _clby2);
        draw_set_color((_clut_mode == 1) ? make_color_rgb(80, 35, 5) : make_color_rgb(20, 20, 35));
        draw_rectangle(_clbx1, _clby1, _clbx2, _clby2, false);
        draw_set_color((_clut_mode == 1) ? make_color_rgb(220, 110, 20) : make_color_rgb(60, 90, 140));
        draw_rectangle(_clbx1, _clby1, _clbx2, _clby2, true);
        draw_set_color((_clut_mode == 1) ? make_color_rgb(255, 160, 60) : make_color_rgb(120, 160, 210));
        draw_set_halign(fa_center);
        draw_text(_clbx1 + 30, _clby1 +8, (_clut_mode == 1) ? "CHAR: MC" : "CHAR: HR");
        draw_set_halign(fa_left);
        if (_clbhov && mouse_check_button_pressed(mb_left) && _m.active_char < array_length(_m.char_lut)) {
            // Flip bit 4, keep the colour nibble intact
            var _cur_col = _m.char_lut[_m.active_char] & 0x0F;
            _m.char_lut[_m.active_char] = ((_clut_mode == 1) ? 0x00 : 0x10) | _cur_col;
            _m.is_dirty = true;
        }
        // ECM: edit the REAL char (mod 64) — active_char may be a virtual
        // band-slot (real + band*64). Also force mc_mode=2 so the panel shows
        // BG0-3+FG swatches instead of the plain HR BG/FG pair. No colour swap
        // needed here — BG0-3 live directly on the linked CHAR_SET already,
        // unlike MC's map-level override (map_mc_bg/col1/col2), so temporarily
        // overwriting mc_bg would just stomp the real value every frame.
        if (_ecm_mode) {
            chr_edit_idx = _m.active_char mod 64;
            scr_chr_editor_draw(_ts_chr_ref, _ced_x, _ced_y, 2, false);
        } else {
            var _eff_col1 = (_m.map_mc_col1 >= 0) ? _m.map_mc_col1 : _ts_chr_ref.meta.mc_col1;
            var _eff_col2 = (_m.map_mc_col2 >= 0) ? _m.map_mc_col2 : _ts_chr_ref.meta.mc_col2;
            var _save_bg   = _ts_chr_ref.meta.mc_bg;
            var _save_col1 = _ts_chr_ref.meta.mc_col1;
            var _save_col2 = _ts_chr_ref.meta.mc_col2;
            var _save_fg   = _ts_chr_ref.meta.mc_fg;
            _ts_chr_ref.meta.mc_bg   = _ts_bg;
            _ts_chr_ref.meta.mc_col1 = _eff_col1;
            _ts_chr_ref.meta.mc_col2 = _eff_col2;
            _ts_chr_ref.meta.mc_fg   = _m.active_colour;

            chr_edit_idx = _m.active_char;
            scr_chr_editor_draw(_ts_chr_ref, _ced_x, _ced_y, (_ts_global_mixed == 1) ? _clut_mode : 0);

            _ts_chr_ref.meta.mc_bg   = _save_bg;
            _ts_chr_ref.meta.mc_col1 = _save_col1;
            _ts_chr_ref.meta.mc_col2 = _save_col2;
            _ts_chr_ref.meta.mc_fg   = _save_fg;
        }
        // If a single-tile paste just happened, carry char_lut (HR/MC + colour)
        // from the copied source char to the pasted destination char.
        if (global.chr_clip_lut_dst >= 0
         && global.chr_clip_lut_src >= 0
         && global.chr_clip_lut_src < array_length(_m.char_lut)
         && global.chr_clip_lut_dst < array_length(_m.char_lut)) {
            _m.char_lut[global.chr_clip_lut_dst] = _m.char_lut[global.chr_clip_lut_src];
            // Keep the PAINT swatch in step if the dst is the active char.
            if (global.chr_clip_lut_dst == _m.active_char) {
                _m.active_colour = _m.char_lut[_m.active_char] & 0x0F;
            }
            _m.is_dirty = true;
            global.chr_clip_lut_dst = -1;
        }
    }

    // ---- COLOUR PALETTE STRIP ----
    var _strip_x1 = _list_x2 + 10;
    var _strip_x2 = _vx2 - 10;
    var _pal_y2   = _canvas_y2 + 4;
    var _psh      = 14;
    var _psw      = 22;
    draw_set_font(fnt_c64_code);
    draw_set_color(make_color_rgb(200, 255, 255));
    draw_text(_strip_x1, _pal_y2, "COLOUR");
    for (var _pi2 = 0; _pi2 < 16; _pi2++) {
        var _ppx1   = _strip_x1 + 60 + _pi2 * (_psw + 2);
        var _pphov  = point_in_rectangle(_mx, _my, _ppx1, _pal_y2, _ppx1 + _psw, _pal_y2 + _psh);
        var _locked = (!_ecm_mode) && (_ts_global_mixed == 1) && (_pi2 >= 8);
        draw_set_color(scr_c64_pepto_colour(_pi2));
        draw_set_alpha(_locked ? 0.2 : 1.0);
        draw_rectangle(_ppx1, _pal_y2, _ppx1 + _psw, _pal_y2 + _psh, false);
        draw_set_alpha(1.0);
        if (_m.active_colour == _pi2) {
            draw_set_color(c_white);
            draw_rectangle(_ppx1, _pal_y2, _ppx1 + _psw, _pal_y2 + _psh, true);
        }
        if (_pphov && !_locked && mouse_check_button_pressed(mb_left)) {
            _m.active_colour = _pi2;
            // The PAINT colour feeds FG into the char editor, so picking it
            // also selects the FG bit-pair (3) for painting.
            chr_active_mc_colour = 3;
            // Selecting a colour with a char selected BAKES it into char_lut now,
            // so re-picking a colour updates the selected char immediately.
            if (_m.active_char < array_length(_m.char_lut)) {
                var _keep_mc = _m.char_lut[_m.active_char] & 0x10;
                _m.char_lut[_m.active_char] = _keep_mc | (_m.active_colour & 0x0F);
                _m.is_dirty = true;
            }
        }
    }

    // ---- CHAR STRIP ----
    var _cp_y2         = _pal_y2 + _psh + 30;
    var _cp_cnt2       = 32;
    var _cp_sz2        = clamp(floor((_strip_x2 - _strip_x1 - 45 - 20) / 32) - 2, 8, 40);
    var _cp_rows       = 4;
    var _cp_tot2       = (_ts_chr_ref != noone) ? (_ecm_mode ? 256 : _ts_chr_ref.meta.char_count) : 256;
    var _cp_max_scroll = max(0, ceil(_cp_tot2 / _cp_cnt2) - _cp_rows);

    if (!variable_struct_exists(_m, "char_strip_scroll_row")) _m.char_strip_scroll_row = 0;
    var _cp_start_row = _m.char_strip_scroll_row;
    var _cp_strip_h   = _cp_rows * (_cp_sz2 + 2);

    draw_set_color(make_color_rgb(200, 255, 255));
    draw_text(_strip_x1, _cp_y2, "TILE");

    var _ssx2 = window_get_width()  / global.gui_w;
    var _ssy2 = window_get_height() / display_get_gui_height();

    for (var _crow = 0; _crow < _cp_rows; _crow++) {
        for (var _pi2 = 0; _pi2 < _cp_cnt2; _pi2++) {
            var _ci2       = (_cp_start_row + _crow) * _cp_cnt2 + _pi2;
            if (_ci2 >= _cp_tot2) break;
            var _cpx1      = _strip_x1 + 45 + _pi2 * (_cp_sz2 + 2);
            var _cp_y2_row = _cp_y2 + _crow * (_cp_sz2 + 2);
            var _cphov     = point_in_rectangle(_mx, _my, _cpx1, _cp_y2_row, _cpx1 + _cp_sz2, _cp_y2_row + _cp_sz2);
            var _cpsel     = (_m.active_char == _ci2);

            var _strip_real_char = _ecm_mode ? (_ci2 mod 64) : _ci2;
            var _strip_band      = _ecm_mode ? (_ci2 div 64) : 0;
            var _strip_bg_col    = _ecm_mode ? scr_c64_pepto_colour(_ecm_bg_cols[_strip_band]) : scr_c64_pepto_colour(_ts_bg);

            draw_set_color(_cpsel ? make_color_rgb(60, 120, 80) : _strip_bg_col);
            draw_rectangle(_cpx1, _cp_y2_row, _cpx1 + _cp_sz2, _cp_y2_row + _cp_sz2, false);

            if (_ts_chr_ref != noone && buffer_exists(_ts_chr_ref.buffer)) {
                // Strip shows each char in its OWN char_lut mode + baked colour.
                var _strip_char_mc  = (_ci2 < array_length(_m.char_lut)) ? (((_m.char_lut[_ci2] >> 4) & 0x01) == 1) : false;
                var _strip_char_col = (_ci2 < array_length(_m.char_lut)) ? (_m.char_lut[_ci2] & 0x0F) : (_m.active_colour & 0x0F);
                if (_ts_global_mixed == 1 && _strip_char_mc) {
                    var _strip_col1 = (_m.map_mc_col1 >= 0) ? _m.map_mc_col1 : 1;
                    var _strip_col2 = (_m.map_mc_col2 >= 0) ? _m.map_mc_col2 : 2;
                    var _strip_pal  = [scr_c64_pepto_colour(_ts_bg), scr_c64_pepto_colour(_strip_col1), scr_c64_pepto_colour(_strip_col2), scr_c64_pepto_colour(_strip_char_col & 0x07)];
                    var _st_pxw2    = max(1, (_cp_sz2 - 4) / 4);
                    var _st_pxh2    = max(1, (_cp_sz2 - 4) / 8);
                    draw_set_color(_strip_pal[0]);
                    draw_rectangle(_cpx1 + 2, _cp_y2_row + 2, _cpx1 + _cp_sz2 - 2, _cp_y2_row + _cp_sz2 - 2, false);
                    for (var _str2 = 0; _str2 < 8; _str2++) {
                        var _stboff2 = (_strip_real_char * 8) + _str2;
                        if (_stboff2 >= buffer_get_size(_ts_chr_ref.buffer)) break;
                        var _stbyte2 = buffer_peek(_ts_chr_ref.buffer, _stboff2, buffer_u8);
                        for (var _stbit2 = 0; _stbit2 < 4; _stbit2++) {
                            var _stbits = (_stbyte2 >> (6 - _stbit2 * 2)) & 0x03;
                            if (_stbits == 0) continue;
                            draw_set_color(_strip_pal[_stbits]);
                            draw_rectangle(
                                _cpx1 + 2 + _stbit2 * _st_pxw2, _cp_y2_row + 2 + _str2 * _st_pxh2,
                                _cpx1 + 2 + _stbit2 * _st_pxw2 + _st_pxw2, _cp_y2_row + 2 + _str2 * _st_pxh2 + _st_pxh2,
                                false);
                        }
                    }
                } else {
                    var _st_pxw2    = max(1, (_cp_sz2 - 4) / 8);
                    var _st_pxh2    = max(1, (_cp_sz2 - 4) / 8);
                    var _strip_hcol = (!_eff_mixed) ? (_strip_char_col & 0x0F) : (_strip_char_col & 0x07);
                    // ECM: compare against THIS row's actual background, not
                    // band 0's (_ts_bg) — otherwise a char whose colour matches
                    // a non-zero band's real BG slips through invisible/blended.
                    var _strip_bg_idx = _ecm_mode ? _ecm_bg_cols[_strip_band] : _ts_bg;
                    if (_strip_hcol == _strip_bg_idx) _strip_hcol = (_strip_bg_idx == 0) ? 1 : 0;
                    draw_set_color(_strip_bg_col);
                    draw_rectangle(_cpx1 + 2, _cp_y2_row + 2, _cpx1 + _cp_sz2 - 2, _cp_y2_row + _cp_sz2 - 2, false);
                    draw_set_color(scr_c64_pepto_colour(_strip_hcol));
                    for (var _str2 = 0; _str2 < 8; _str2++) {
                        var _stboff2 = (_strip_real_char * 8) + _str2;
                        if (_stboff2 >= buffer_get_size(_ts_chr_ref.buffer)) break;
                        var _stbyte2 = buffer_peek(_ts_chr_ref.buffer, _stboff2, buffer_u8);
                        for (var _stbit2 = 0; _stbit2 < 8; _stbit2++) {
                            if (_stbyte2 & (0x80 >> _stbit2)) {
                                draw_rectangle(
                                    _cpx1 + 2 + _stbit2 * _st_pxw2, _cp_y2_row + 2 + _str2 * _st_pxh2,
                                    _cpx1 + 2 + _stbit2 * _st_pxw2 + _st_pxw2, _cp_y2_row + 2 + _str2 * _st_pxh2 + _st_pxh2,
                                    false);
                            }
                        }
                    }
                }
            } else {
                draw_set_font(fnt_c64_tiny);
                draw_set_color(c_gray);
                draw_set_halign(fa_center);
                draw_text(_cpx1 + _cp_sz2 * 0.5, _cp_y2_row + 6, string(_ci2));
                draw_set_halign(fa_left);
            }

            if (_cpsel) {
                draw_set_color(c_white);
                draw_rectangle(_cpx1 - 2, _cp_y2_row - 2, _cpx1 + _cp_sz2 + 2, _cp_y2_row + _cp_sz2 + 2, true);
                draw_rectangle(_cpx1, _cp_y2_row, _cpx1 + _cp_sz2, _cp_y2_row + _cp_sz2, true);
            }
            if (_cphov && mouse_check_button_pressed(mb_left)) {
                _m.active_char = _ci2;
                // Adopt this char's baked colour into the active swatch so the
                // PAINT readout reflects what you'll paint.
                if (_ci2 < array_length(_m.char_lut)) {
                    _m.active_colour = _m.char_lut[_ci2] & 0x0F;
                }
            }

            // Tile type cycle: ALT+CLICK or SPACE steps UP, RIGHT-CLICK steps
            // DOWN. Range 0=NONE, 1..16=T1..T16, wrapping at both ends.
            // Keyed on the REAL char (mod 64) so all 4 ECM bands of one glyph
            // share the same collision/tile type.
            var _tt_up2   = (_cphov && keyboard_check(vk_alt) && mouse_check_button_pressed(mb_left));
                       
            var _tt_down2 = (_cphov && mouse_check_button_pressed(mb_right));
            if (_tt_up2 || _tt_down2) {
                if (_ts_chr_ref != noone) {
                    if (!variable_struct_exists(_ts_chr_ref.meta, "tile_types")) {
                        _ts_chr_ref.meta.tile_types = array_create(256, 0);
                    }
                    var _cur_type = _ts_chr_ref.meta.tile_types[_strip_real_char];
                    if (_tt_up2) {
                        _cur_type = (_cur_type + 1) mod 17;
                    } else {
                        _cur_type = (_cur_type + 16) mod 17;
                    }
                    _ts_chr_ref.meta.tile_types[_strip_real_char] = _cur_type;
                }
            }
            // Draw tile type badge overlay
            if (_ts_chr_ref != noone && variable_struct_exists(_ts_chr_ref.meta, "tile_types")) {
                var _tt = _ts_chr_ref.meta.tile_types[_strip_real_char];
                if (_tt > 0) {
                    var _badge_cols = [
                        0,
                        make_color_rgb(200,  60,  60),
                        make_color_rgb( 60, 140, 220),
                        make_color_rgb(200, 160,  60),
                        make_color_rgb( 80, 200, 120),
                        make_color_rgb(200,  80, 200),
                        make_color_rgb(220, 220,  80),
                        make_color_rgb( 80, 220, 220),
                        make_color_rgb(220, 140,  60),
                        make_color_rgb(140,  120, 250),
                        make_color_rgb(120, 200,  60),
                        make_color_rgb(220,  60, 140),
                        make_color_rgb( 60, 200, 160),
                        make_color_rgb(180, 100,  40),
                        make_color_rgb(120, 130, 250),
                        make_color_rgb(200, 200, 140),
                        make_color_rgb(160, 160, 160)
                    ];
                    draw_set_color(_badge_cols[clamp(_tt, 0, 16)]);
                    draw_rectangle(_cpx1, _cp_y2_row, _cpx1 + 19, _cp_y2_row + 13, false);
                    draw_set_color(c_black);
                    draw_set_halign(fa_left);
                    draw_set_font(fnt_c64_tiny);
                    draw_text(_cpx1 + 1, _cp_y2_row -2, "T" + string(_tt));
                }
            }
        }
    }

    gpu_set_scissor(0, 0, window_get_width(), window_get_height());

    // Char strip row scroll
    var _strip_area_y2 = _cp_y2 + _cp_rows * (_cp_sz2 + 2);
    if (point_in_rectangle(_mx, _my, _strip_x1, _cp_y2 - 4, _strip_x2, _strip_area_y2 + 4)) {
        if (mouse_wheel_up())   _m.char_strip_scroll_row = max(0, _m.char_strip_scroll_row - 1);
        if (mouse_wheel_down()) _m.char_strip_scroll_row = min(_cp_max_scroll, _m.char_strip_scroll_row + 1);
    }

    // Up/down arrow buttons
    var _arr_x  = _strip_x2 - 20;
    var _up_hov = point_in_rectangle(_mx, _my, _arr_x, _cp_y2, _arr_x + 18, _cp_y2 + 14);
    var _dn_hov = point_in_rectangle(_mx, _my, _arr_x, _cp_y2 + 16, _arr_x + 18, _cp_y2 + 30);
    draw_set_color(_up_hov ? c_white : (_m.char_strip_scroll_row > 0 ? make_color_rgb(160, 160, 200) : make_color_rgb(50, 50, 70)));
    draw_rectangle(_arr_x, _cp_y2, _arr_x + 18, _cp_y2 + 14, false);
    draw_set_color(c_black);
    draw_set_halign(fa_center);
    draw_text(_arr_x + 9, _cp_y2 + 2, "^");
    draw_set_color(_dn_hov ? c_white : (_m.char_strip_scroll_row < _cp_max_scroll ? make_color_rgb(160, 160, 200) : make_color_rgb(50, 50, 70)));
    draw_rectangle(_arr_x, _cp_y2 + 16, _arr_x + 18, _cp_y2 + 30, false);
    draw_set_color(c_black);
    draw_text(_arr_x + 9, _cp_y2 + 18, "v");
    draw_set_halign(fa_left);
    if (_up_hov && mouse_check_button_pressed(mb_left)) _m.char_strip_scroll_row = max(0, _m.char_strip_scroll_row - 1);
    if (_dn_hov && mouse_check_button_pressed(mb_left)) _m.char_strip_scroll_row = min(_cp_max_scroll, _m.char_strip_scroll_row + 1);

} break;

	
	


        default: {
			gpu_set_tex_filter(true);
            draw_set_font(fnt_c64_code);
            draw_set_color(c_ltgray); draw_text(_vx1 + 10, _cy, "NAME:");
			
            draw_set_color(c_white);  draw_text(_vx1 + 90, _cy, _asset.name);
            _cy += 20;
            draw_set_color(c_ltgray); draw_text(_vx1 + 10, _cy, "TYPE:");
            draw_set_color(_tcol);    draw_text(_vx1 + 90, _cy, _asset.type);
            _cy += 20;
            draw_set_color(c_ltgray); draw_text(_vx1 + 10, _cy, "FILE:");
            draw_set_color(_asset.file != "" ? c_lime : make_color_rgb(200,60,60));
            draw_text(_vx1 + 360, _cy, _asset.file != "" ? _asset.file : "NO FILE LOADED");
            _cy += 30;
        } break;

    } // end switch
	
	
	
	// ---- SAVE & AUTOSAVE UI ----
    if (_asset.type != "CHAR_SET" && _asset.type != "META_TILESET" && _asset.type != "BITMAP_BUILDER") {
    if (!variable_struct_exists(_asset.meta, "autosave"))    _asset.meta.autosave    = true;
    if (!variable_struct_exists(_asset.meta, "is_dirty"))    _asset.meta.is_dirty    = false;
    if (!variable_struct_exists(_asset.meta, "flash_timer")) _asset.meta.flash_timer = 0;
	
    var _as_x = 0;
    var _as_y = 0;
	
    if (_asset.type == "META_TILESET") {
        _as_x = _vx1 + 20;
        _as_y = _vy2 - 305;
    } else {
        _as_x = _vx1 + 1090;
		_as_y = _vy1 +8;
    }
    var _ashov = point_in_rectangle(_mx, _my, _as_x, _as_y, _as_x + 100, _as_y + 16);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(_asset.meta.autosave ? make_color_rgb(255, 255, 255) : make_color_rgb(100, 100, 100));
    draw_text(_as_x, _as_y, "AUTOSAVE: " + (_asset.meta.autosave ? "ON" : "OFF"));
    if (_ashov && mouse_check_button_pressed(mb_left)) {
        _asset.meta.autosave = !_asset.meta.autosave;
    }
    var _sv_x  = _as_x + 100;
    var _sv_w  = 60;
    var _svhov = point_in_rectangle(_mx, _my, _sv_x, _as_y, _sv_x + _sv_w, _as_y + 16);
    if (_asset.meta.is_dirty) {
        _asset.meta.flash_timer = (_asset.meta.flash_timer + 1) mod 40;
        var _alpha = (_asset.meta.flash_timer < 20) ? 1.0 : 0.3;
        draw_set_color(make_color_rgb(200, 150, 50));
        draw_set_alpha(_alpha);
    } else {
        draw_set_color(make_color_rgb(40, 40, 40));
    }
    draw_rectangle(_sv_x, _as_y, _sv_x + _sv_w, _as_y + 14, false);
    draw_set_alpha(1.0);
    draw_set_color(c_white);
    draw_text(_sv_x + 10, _as_y, "SAVE");
	    if ((_svhov && mouse_check_button_pressed(mb_left)) || (_asset.meta.is_dirty && _asset.meta.autosave)) {
	        // SPRITE_SET is never written back to its source file. The
	        // workspace JSON already preserves the buffer + meta (including
	        // compositor and anim data), and the source may be a SPRED64
	        // text file that this script would corrupt with binary data.
	        // All other asset types still round-trip via buffer_save.
	        if (_asset.type != "SPRITE_SET") {
	            buffer_save(_asset.buffer, _asset.file);
	        }
	        _asset.meta.is_dirty    = false;
	        _asset.meta.flash_timer = 0;
	    }
	}
	

// REFERENCED BY (for BITMAP, default cases — SPRITE_SET and MAP_DATA handle their own above)
    if (_asset.type == "SFX_DATA") _cy = _vy2 - 100;
	 if (_asset.type == "BYTE_DATA" || _asset.type == "TEXT_DATA" || _asset.type == "LINE_COLL") _cy = _vy2 - 100;
   if (_asset.type != "SPRITE_SET" && _asset.type != "MAP_DATA" && _asset.type != "BITMAP" && _asset.type != "META_TILESET" && _asset.type != "META_MAP" && _asset.type != "BITMAP_BUILDER" && _asset.type != "MUSIC_MAKER") {
        draw_set_font(fnt_c64_code);
        draw_set_color(make_color_rgb(60,60,80));
        draw_line(_vx1 + 10, _cy, _vx2 - 10, _cy);
        _cy += 16;
        draw_set_color(c_ltgray);
        var _header_text = (_asset.type == "BYTE_DATA" || _asset.type == "LINE_COLL") ? "AUTOMATICALLY INJECTED" : "REFERENCED BY:";
        draw_text(_vx1 + 10, _cy, _header_text);
        _cy += 18;
        var _ref_count = 0;
// Collect refs first, then draw in columns of 3
        _ref_collect    = [];
        _ref_asset_name = _asset.name;
        with (obj_c64_node) {
            var _ref_name = "";
            switch (node_type) {
                case "MACRO_BMP": case "MACRO_SPR": case "MACRO_SID": case "MACRO_SFX": case "MACRO_MAP": case "MACRO_CHR": case "MACRO_LOADER": case "MACRO_SID_SONG": case "MACRO_COLL_LINE":
                    if (array_length(instructions[0]) > 1)
                        _ref_name = string(instructions[0][1]);
                    break;
                case "MACRO_TEXT_SCROLL":
                    if (array_length(instructions[0]) > 10)
                        _ref_name = string(instructions[0][10]);
                    break;
                case "NEW_STR":
                    if ((array_length(instructions[0]) > 4 && is_real(instructions[0][4]) && real(instructions[0][4]) == 1) &&
                        array_length(instructions[0]) > 5)
                        _ref_name = string(instructions[0][5]);
                    break;
            }
            if (_ref_name == other._ref_asset_name)
                array_push(other._ref_collect, node_title + " @ $" + string_upper(decimal_to_hex(pc_address)));
        }
        _ref_count = array_length(_ref_collect);
        if (_ref_count == 0) {
            draw_set_font(fnt_c64_tiny);
            draw_set_color(make_color_rgb(80, 80, 80));
            var _status_msg = (_asset.type == "BYTE_DATA" || _asset.type == "TEXT_DATA" || _asset.type == "LINE_COLL") ? "OCCUPIES RAM AT STATED ADDRESSES" : "NONE - ASSET NOT IN USE";
            draw_text(_vx1 + 20, _cy, _status_msg);
            _cy += 20;
        } else {
            var _rows_per_col = 3;
            var _col_w2       = 200;
            var _row_h2       = 16;
            draw_set_font(fnt_c64_tiny);
            for (var _ri = 0; _ri < _ref_count; _ri++) {
                var _rc = _ri div _rows_per_col;
                var _rr = _ri mod _rows_per_col;
                draw_set_color(c_yellow);
                draw_text(_vx1 + 20 + _rc * _col_w2, _cy + _rr * _row_h2, _ref_collect[_ri]);
            }
            var _used_rows = min(_ref_count, _rows_per_col);
            _cy += _used_rows * _row_h2 + 4;
        }
    }

    // ---- CHAR_SET GRID — drawn at bottom after REFERENCED BY ----
    if (_asset.type == "CHAR_SET") {
        _cy += 10;
        if (variable_struct_exists(_asset.meta, _chr_surf_key) &&
            surface_exists(variable_struct_get(_asset.meta, _chr_surf_key))) {
            var _ps  = variable_struct_get(_asset.meta, _chr_surf_key);
            var _psw = surface_get_width(_ps);
            var _psh = surface_get_height(_ps);
            // Fill remaining height
            var _avail = _vy2 - _cy - 30;
            var _sc    = min((_vw - 40) / _psw, _avail / _psh);
            var _dw    = floor(_psw * _sc);
            var _dh    = floor(_psh * _sc);
            var _dx    = _vx1 + (_vw - _dw) * 0.5;
             draw_surface_stretched(_ps, _dx, _cy, _dw, _dh);
            chr_grid_draw_x    = _dx;
            chr_grid_draw_y    = _cy;
            chr_grid_cell_px   = 32 * _sc; // _scale=4, so cell=32 surface px, scaled by _sc
            // Highlight selected tile
            var _sel_col  = floor(chr_edit_idx mod 16);
            var _sel_row  = floor(chr_edit_idx div 16);
            var _sel_cell = 32 * _sc; // matches _scale=4 surface cell
            var _sel_x    = _dx + _sel_col * _sel_cell;
            var _sel_y    = _cy + _sel_row * _sel_cell;
            draw_set_color(c_white);
            draw_set_alpha(1.0);
            draw_rectangle(_sel_x - 2, _sel_y - 2, _sel_x + _sel_cell + 2, _sel_y + _sel_cell + 2, true);
            draw_rectangle(_sel_x,     _sel_y,     _sel_x + _sel_cell,     _sel_y + _sel_cell,     true);

            // Highlight multi-selected tiles (Ctrl+click / Ctrl+drag selection)
            var _ms_len = array_length(chr_multi_select);
            if (_ms_len > 0) {
                var _ms_pulse = 0.35 + 0.25 * sin(current_time / 150);
                for (var _msi = 0; _msi < _ms_len; _msi++) {
                    var _ms_idx = chr_multi_select[_msi];
                    if (_ms_idx < 0 || _ms_idx >= _asset.meta.char_count) continue;
                    var _ms_col = floor(_ms_idx mod 16);
                    var _ms_row = floor(_ms_idx div 16);
                    var _ms_x   = _dx + _ms_col * _sel_cell;
                    var _ms_y   = _cy + _ms_row * _sel_cell;
                    // Filled pulsing tint
                    draw_set_color(make_color_rgb(255, 220, 60));
                    draw_set_alpha(_ms_pulse);
                    draw_rectangle(_ms_x, _ms_y, _ms_x + _sel_cell, _ms_y + _sel_cell, false);
                    // Solid outline on top
                    draw_set_alpha(1.0);
                    draw_set_color(c_yellow);
                    draw_rectangle(_ms_x,     _ms_y,     _ms_x + _sel_cell,     _ms_y + _sel_cell,     true);
                    draw_rectangle(_ms_x - 1, _ms_y - 1, _ms_x + _sel_cell + 1, _ms_y + _sel_cell + 1, true);
                }
                draw_set_alpha(1.0);
            }
            // Grid lines per char cell
            var _char_pw = 32 * _sc;
            var _char_ph = 32 * _sc;
            draw_set_color(make_color_rgb(60, 100, 180));
            draw_set_alpha(0.5);
            for (var _gx = _char_pw; _gx < _dw; _gx += _char_pw)
                draw_line_width(_dx + _gx, _cy, _dx + _gx, _cy + _dh, 3);
            for (var _gy = _char_ph; _gy < _dh; _gy += _char_ph)
                draw_line_width(_dx, _cy + _gy, _dx + _dw, _cy + _gy, 3);
            draw_set_alpha(1.0);
            draw_set_color(make_color_rgb(60, 60, 80));
            draw_rectangle(_dx, _cy, _dx + _dw, _cy + _dh, true);

                        // BKG-TILE label above tile 0
            var _cell_sz = 32 * _sc;
            draw_set_font(fnt_c64_tiny);
            draw_set_color(make_color_rgb(255, 180, 0));
            draw_text(_dx, _cy - 40, "BKG\nTILE");

            _cy += _dh + 6;
            // Info line
            draw_set_font(fnt_c64_tiny);
            draw_set_color(make_color_rgb(200, 200, 255));
            draw_set_halign(fa_center);
            var _fmt = variable_struct_exists(_asset.meta, "format")     ? string_upper(_asset.meta.format) : "BINARY";
            var _cnt = variable_struct_exists(_asset.meta, "char_count") ? string(_asset.meta.char_count)   : "256";
            var _sz  = variable_struct_exists(_asset.meta, "total_size") ? string(_asset.meta.total_size)   : "2048";
            draw_text(_vx1 + _vw * 0.5, _cy, "CHARS: " + _cnt + "   FORMAT: " + _fmt + "   SIZE: " + _sz + " BYTES");
            draw_set_halign(fa_left);
        } else {
            draw_set_color(make_color_rgb(40, 40, 60));
            draw_rectangle(_vx1 + 10, _cy, _vx2 - 10, _cy + 80, false);
            draw_set_font(fnt_c64_tiny);
            draw_set_color(make_color_rgb(80, 80, 80));
            draw_set_halign(fa_center);
            draw_text(_vx1 + _vw * 0.5, _cy + 32, "NO CHARSET LOADED");
            draw_set_halign(fa_left);
        }
    }
}




// -------------------------------------------------------
// MACRO_LOADER — LOAD_ORG PICKER DROPDOWN
// -------------------------------------------------------
if (loader_org_picker_open && instance_exists(loader_org_picker_node)) {
    var _lop_matches = [];
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _a = ds_list_find_value(asset_list, _i);
        if (_a.type == "LOAD_ORG") array_push(_lop_matches, _a);
    }

    // Convert node room-space to GUI-space
    var _vx_lop = camera_get_view_x(view_camera[0]);
    var _vy_lop = camera_get_view_y(view_camera[0]);
    var _vw_lop = camera_get_view_width(view_camera[0]);
    var _vh_lop = camera_get_view_height(view_camera[0]);
    var _sx_lop = global.gui_w / _vw_lop;
    var _sy_lop = display_get_gui_height() / _vh_lop;

    var _drop_x = (loader_org_picker_node.x + 68 - _vx_lop) * _sx_lop;
    var _drop_y = (loader_org_picker_node.y + 36 - _vy_lop) * _sy_lop;
    var _drop_w = 180;
    var _drop_h = max(20, array_length(_lop_matches) * 16 + 4);

    draw_set_color(make_color_rgb(10, 10, 20));
    draw_rectangle(_drop_x, _drop_y, _drop_x + _drop_w, _drop_y + _drop_h, false);
    draw_set_color(make_color_rgb(200, 160, 40));
    draw_rectangle(_drop_x, _drop_y, _drop_x + _drop_w, _drop_y + _drop_h, true);

    draw_set_font(fnt_c64_tiny);
    if (array_length(_lop_matches) == 0) {
        draw_set_color(make_color_rgb(150, 80, 80));
        draw_text(_drop_x + 4, _drop_y + 4, "(NO LOAD_ORG ASSETS)");
    } else {
        for (var _i = 0; _i < array_length(_lop_matches); _i++) {
            var _ry  = _drop_y + (_i * 16);
            var _hov = (loader_org_picker_hover == _i);
            if (_hov) {
                draw_set_color(make_color_rgb(60, 60, 100));
                draw_rectangle(_drop_x, _ry, _drop_x + _drop_w, _ry + 16, false);
            }
            draw_set_color(_hov ? c_white : c_aqua);
            draw_text(_drop_x + 4, _ry + 2, _lop_matches[_i].name);
        }
    }
}

// -------------------------------------------------------
// MACRO_LOADER — FILE PICKER DROPDOWN
// -------------------------------------------------------
if (loader_file_picker_open && instance_exists(loader_file_picker_node)) {
    var _lfp_org_name = "";
    if (array_length(loader_file_picker_node.instructions[0]) > 1) {
        _lfp_org_name = string(loader_file_picker_node.instructions[0][1]);
    }

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

    // Convert node room-space to GUI-space
    var _vx_lfp = camera_get_view_x(view_camera[0]);
    var _vy_lfp = camera_get_view_y(view_camera[0]);
    var _vw_lfp = camera_get_view_width(view_camera[0]);
    var _vh_lfp = camera_get_view_height(view_camera[0]);
    var _sx_lfp = global.gui_w / _vw_lfp;
    var _sy_lfp = display_get_gui_height() / _vh_lfp;

    var _drop_x = (loader_file_picker_node.x + 68 - _vx_lfp) * _sx_lfp;
    var _drop_y = (loader_file_picker_node.y + 48 - _vy_lfp) * _sy_lfp;
    var _drop_w = 220;
    var _drop_h = max(20, array_length(_lfp_matches) * 16 + 4);

    draw_set_color(make_color_rgb(10, 10, 20));
    draw_rectangle(_drop_x, _drop_y, _drop_x + _drop_w, _drop_y + _drop_h, false);
    draw_set_color(c_yellow);
    draw_rectangle(_drop_x, _drop_y, _drop_x + _drop_w, _drop_y + _drop_h, true);

    draw_set_font(fnt_c64_tiny);
    if (array_length(_lfp_matches) == 0) {
        draw_set_color(make_color_rgb(150, 80, 80));
        draw_text(_drop_x + 4, _drop_y + 4, "(NO LINKED FILES)");
    } else {
        for (var _i = 0; _i < array_length(_lfp_matches); _i++) {
            var _ry   = _drop_y + (_i * 16);
            var _hov  = (loader_file_picker_hover == _i);
            var _lk   = _lfp_matches[_i];
            var _name = _lk.asset_name;
            var _d64  = variable_struct_exists(_lk, "d64_filename") ? _lk.d64_filename : string_upper(_name);
            var _ll   = variable_struct_exists(_lk, "load_later")   ? _lk.load_later   : false;
            if (_hov) {
                draw_set_color(make_color_rgb(60, 60, 100));
                draw_rectangle(_drop_x, _ry, _drop_x + _drop_w, _ry + 16, false);
            }
            draw_set_color(_hov ? c_white : c_yellow);
            draw_text(_drop_x + 4, _ry + 2, _name);
            draw_set_color(_ll ? make_color_rgb(60, 100, 200) : make_color_rgb(80, 80, 80));
            draw_text(_drop_x + 110, _ry + 2, "→ " + _d64);
        }
    }
}
	
	// -------------------------------------------------------
// LOAD_ORG ASSET PICKER DROPDOWN
// -------------------------------------------------------
if (load_org_picker_open) {
    var _lpx     = _vx1 + 10;
    var _lpy     = _vy1 + 200;
    var _lpw     = 240;
    var _lih     = 20;
    var _matches = [];

    if (load_org_picker_asset >= 0 &&
        load_org_picker_asset < ds_list_size(asset_list)) {

        // Build the same unclaimed-asset list used by LOAD_REU.
        for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
            var _candidate = ds_list_find_value(asset_list, _i);

            // Manifests cannot be placed inside other manifests.
            if (_candidate.type == "LOAD_ORG" ||
                _candidate.type == "LOAD_REU") {
                continue;
            }

            var _claimed = false;

            // An asset may belong to only one LOAD_ORG or LOAD_REU.
            for (var _mi = 0;
                 _mi < ds_list_size(asset_list);
                 _mi++) {

                var _manifest =
                    ds_list_find_value(asset_list, _mi);

                if (_manifest.type != "LOAD_ORG" &&
                    _manifest.type != "LOAD_REU") {
                    continue;
                }

                if (!variable_struct_exists(
                        _manifest,
                        "linked_assets")) {
                    continue;
                }

                var _manifest_links =
                    _manifest.linked_assets;

                for (var _li = 0;
                     _li < array_length(_manifest_links);
                     _li++) {

                    if (_manifest_links[_li].asset_name ==
                        _candidate.name) {

                        _claimed = true;
                        break;
                    }
                }

                if (_claimed) break;
            }

            if (!_claimed) {
                array_push(_matches, _candidate);
            }
        }
    }

    var _total_h =
        max(1, array_length(_matches)) * _lih + 24;

    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(
        _lpx,
        _lpy,
        _lpx + _lpw,
        _lpy + _total_h,
        false
    );

    draw_set_color(make_color_rgb(200, 160, 40));
    draw_rectangle(
        _lpx,
        _lpy,
        _lpx + _lpw,
        _lpy + _total_h,
        true
    );

    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(200, 160, 40));
    draw_text(_lpx + 6, _lpy + 4, "ADD TO DISK");

    if (array_length(_matches) == 0) {
        draw_set_color(make_color_rgb(120, 100, 80));
        draw_text(
            _lpx + 8,
            _lpy + 24,
            "NO UNCLAIMED ASSETS"
        );
    } else {
        for (var _i = 0;
             _i < array_length(_matches);
             _i++) {

            var _iy  = _lpy + 20 + (_i * _lih);
            var _hov = load_org_picker_hover == _i;

            draw_set_color(
                _hov
                ? make_color_rgb(80, 60, 20)
                : make_color_rgb(25, 25, 40)
            );

            draw_rectangle(
                _lpx + 2,
                _iy,
                _lpx + _lpw - 2,
                _iy + _lih - 1,
                false
            );

            draw_set_color(_hov ? c_white : c_ltgray);
            draw_text(
                _lpx + 10,
                _iy + 3,
                _matches[_i].name
            );
        }
    }
}

// -------------------------------------------------------
// LOAD_REU ASSET PICKER DROPDOWN
// -------------------------------------------------------
if (load_reu_picker_open) {
    var _lpx     = _vx1 + 10;
    var _lpy     = _vy1 + 200;
    var _lpw     = 240;
    var _lih     = 20;
    var _matches = [];

    if (load_reu_picker_asset >= 0 &&
        load_reu_picker_asset < ds_list_size(asset_list)) {

        // Use the same ownership filtering as the Step event.
        for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
            var _candidate = ds_list_find_value(asset_list, _i);

            // Never show LOAD_ORG or LOAD_REU manifests.
            if (_candidate.type == "LOAD_ORG" ||
                _candidate.type == "LOAD_REU") {
                continue;
            }

            // Check every external-storage manifest.
            var _claimed = false;

            for (var _mi = 0;
                 _mi < ds_list_size(asset_list);
                 _mi++) {

                var _manifest = ds_list_find_value(asset_list, _mi);

                if (_manifest.type != "LOAD_ORG" &&
                    _manifest.type != "LOAD_REU") {
                    continue;
                }

                if (!variable_struct_exists(
                        _manifest,
                        "linked_assets")) {
                    continue;
                }

                var _manifest_links = _manifest.linked_assets;

                for (var _li = 0;
                     _li < array_length(_manifest_links);
                     _li++) {

                    if (_manifest_links[_li].asset_name ==
                        _candidate.name) {

                        _claimed = true;
                        break;
                    }
                }

                if (_claimed) break;
            }

            if (!_claimed) {
                array_push(_matches, _candidate);
            }
        }
    }

    var _total_h =
        max(1, array_length(_matches)) * _lih + 24;

    draw_set_color(make_color_rgb(18, 25, 28));
    draw_rectangle(
        _lpx,
        _lpy,
        _lpx + _lpw,
        _lpy + _total_h,
        false
    );

    draw_set_color(make_color_rgb(100, 200, 180));
    draw_rectangle(
        _lpx,
        _lpy,
        _lpx + _lpw,
        _lpy + _total_h,
        true
    );

    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(100, 200, 180));
    draw_text(_lpx + 6, _lpy + 4, "ADD TO REU IMAGE");

    if (array_length(_matches) == 0) {
        draw_set_color(make_color_rgb(100, 120, 120));
        draw_text(
            _lpx + 8,
            _lpy + 24,
            "NO UNCLAIMED ASSETS"
        );
    } else {
        for (var _i = 0;
             _i < array_length(_matches);
             _i++) {

            var _iy  = _lpy + 20 + (_i * _lih);
            var _hov = load_reu_picker_hover == _i;

            draw_set_color(
                _hov
                ? make_color_rgb(30, 90, 75)
                : make_color_rgb(22, 30, 34)
            );

            draw_rectangle(
                _lpx + 2,
                _iy,
                _lpx + _lpw - 2,
                _iy + _lih - 1,
                false
            );

            draw_set_color(c_white);
            draw_text(
                _lpx + 10,
                _iy + 3,
                _matches[_i].name
            );
        }
    }
}




// -------------------------------------------------------
// META TILESET CHARSET PICKER DROPDOWN
// -------------------------------------------------------
if (meta_ts_picker_open) {
    var _vx1   = 288;
    var _tspx  = _vx1 + 74;
    var _tspy  = meta_ts_btn_y + 14;
    var _tspw  = 180;
    var _tsih  = 20;
    var _ts_matches = [];
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _a = ds_list_find_value(asset_list, _i);
        if (_a.type == "CHAR_SET") array_push(_ts_matches, _a);
    }
    var _ts_total_h = max(1, array_length(_ts_matches)) * _tsih + 4;
    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(_tspx, _tspy, _tspx + _tspw, _tspy + _ts_total_h, false);
    draw_set_color(make_color_rgb(120, 200, 255));
    draw_rectangle(_tspx, _tspy, _tspx + _tspw, _tspy + _ts_total_h, true);
    if (array_length(_ts_matches) == 0) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_text(_tspx + 8, _tspy + 6, "NO CHARSET ASSETS");
    } else {
        for (var _i = 0; _i < array_length(_ts_matches); _i++) {
            var _iy  = _tspy + 2 + (_i * _tsih);
            var _hov = (meta_ts_picker_hover == _i);
            draw_set_color(_hov ? make_color_rgb(40, 100, 120) : make_color_rgb(25, 25, 40));
            draw_rectangle(_tspx + 2, _iy, _tspx + _tspw - 2, _iy + _tsih - 1, false);
            draw_set_font(fnt_c64_code);
            draw_set_color(_hov ? c_white : c_ltgray);
            draw_text(_tspx + 8, _iy + 3, _ts_matches[_i].name);
        }
    }
}


// -------------------------------------------------------
// CHR PICKER DROPDOWN
// -------------------------------------------------------
if (chr_picker_open && instance_exists(chr_picker_node)) {
    draw_set_alpha(1.0);
    gpu_set_scissor(0, 0, window_get_width(), window_get_height());
    var _cam_x    = obj_workspace_manager.cam_x;
    var _cam_y    = obj_workspace_manager.cam_y;
    var _cam_zoom = obj_workspace_manager.cam_zoom;
    var _node     = chr_picker_node;
    var _pdx      = ((_node.x + _node.width + 8) - _cam_x) / _cam_zoom;
    var _pdy      = ((_node.y + 24)              - _cam_y) / _cam_zoom;
    var _pw       = 180;
    var _ih       = 20;

    var _matches = [];
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _a = ds_list_find_value(asset_list, _i);
        if (_a.type == "CHAR_SET") array_push(_matches, _a);
    }

    var _total_h = max(1, array_length(_matches)) * _ih + 4;
    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, false);
    draw_set_color(make_color_rgb(100, 200, 255));
    draw_rectangle(_pdx, _pdy, _pdx + _pw, _pdy + _total_h, true);

    if (array_length(_matches) == 0) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_text(_pdx + 8, _pdy + 6, "NO CHARSET ASSETS");
    } else {
        for (var _i = 0; _i < array_length(_matches); _i++) {
            var _iy  = _pdy + 2 + (_i * _ih);
            var _hov = (chr_picker_hover == _i);
            draw_set_color(_hov ? make_color_rgb(30, 80, 100) : make_color_rgb(25, 25, 40));
            draw_rectangle(_pdx + 2, _iy, _pdx + _pw - 2, _iy + _ih - 1, false);
            draw_set_font(fnt_c64_code);
            draw_set_color(_hov ? c_white : c_ltgray);
            draw_text(_pdx + 8, _iy + 3, _matches[_i].name);
        }
    }
}


// -------------------------------------------------------
// MAP VIEWER CHARSET PICKER DROPDOWN
// MUST be at the very bottom of Draw GUI — after the viewer block —
// so it renders on top of the backdrop.
// -------------------------------------------------------
if (map_chr_picker_open) {
    draw_set_alpha(1.0);
    gpu_set_scissor(0, 0, window_get_width(), window_get_height());
    var _vx1  = 288;
    var _mcpx = _vx1 + 268;
    var _mcpy = map_chr_picker_draw_y;
    var _mcpw = 180;
    var _mcih = 20;

    var _mc_matches = [];
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _a = ds_list_find_value(asset_list, _i);
        if (_a.type == "CHAR_SET") array_push(_mc_matches, _a);
    }
    var _mc_total_h = max(1, array_length(_mc_matches)) * _mcih + 4;

    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(_mcpx, _mcpy, _mcpx + _mcpw, _mcpy + _mc_total_h, false);
    draw_set_color(make_color_rgb(80, 200, 120));
    draw_rectangle(_mcpx, _mcpy, _mcpx + _mcpw, _mcpy + _mc_total_h, true);

    if (array_length(_mc_matches) == 0) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_text(_mcpx + 8, _mcpy + 6, "NO CHARSET ASSETS");
    } else {
        for (var _i = 0; _i < array_length(_mc_matches); _i++) {
            var _iy  = _mcpy + 2 + (_i * _mcih);
            var _hov = (map_chr_picker_hover == _i);
            draw_set_color(_hov ? make_color_rgb(40, 100, 60) : make_color_rgb(25, 25, 40));
            draw_rectangle(_mcpx + 2, _iy, _mcpx + _mcpw - 2, _iy + _mcih - 1, false);
            draw_set_font(fnt_c64_code);
            draw_set_color(_hov ? c_white : c_ltgray);
            draw_text(_mcpx + 8, _iy + 3, _mc_matches[_i].name);
        }
    }
}



// -------------------------------------------------------
// BITMAP_BUILDER SRC/DST PICKER DROPDOWN
// -------------------------------------------------------
if (bbuild_picker_open) {
    draw_set_alpha(1.0);
    gpu_set_scissor(0, 0, window_get_width(), window_get_height());
    var _bbpx = bbuild_picker_x;
    var _bbpy = bbuild_picker_y;
    var _bbpw = 180;
    var _bbih = 18;

    var _bb_matches = [];
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _a = ds_list_find_value(asset_list, _i);
        if (_a.type == "BITMAP") array_push(_bb_matches, _a);
    }
    var _bb_total_h = max(1, array_length(_bb_matches)) * _bbih + 4;

    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(_bbpx, _bbpy, _bbpx + _bbpw, _bbpy + _bb_total_h, false);
    draw_set_color((bbuild_picker_field == "SRC") ? c_aqua : c_yellow);
    draw_rectangle(_bbpx, _bbpy, _bbpx + _bbpw, _bbpy + _bb_total_h, true);

    if (array_length(_bb_matches) == 0) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 80, 80));
        draw_text(_bbpx + 8, _bbpy + 4, "NO BITMAP ASSETS");
    } else {
        for (var _i = 0; _i < array_length(_bb_matches); _i++) {
            var _iy  = _bbpy + 2 + (_i * _bbih);
            var _hov = (bbuild_picker_hover == _i);
            draw_set_color(_hov ? make_color_rgb(60, 60, 100) : make_color_rgb(25, 25, 40));
            draw_rectangle(_bbpx + 2, _iy, _bbpx + _bbpw - 2, _iy + _bbih - 1, false);
            draw_set_font(fnt_c64_code);
            draw_set_color(_hov ? c_white : c_ltgray);
            draw_text(_bbpx + 8, _iy + 1, _bb_matches[_i].name);
        }
    }
}

// -------------------------------------------------------
// DELETE WARNING OVERLAY
// -------------------------------------------------------
if (variable_instance_exists(id, "delete_warn_timer") && delete_warn_timer > 0) {
    delete_warn_timer--;
    // 60 frames solid, then 120 frames fade
    var _alpha = (delete_warn_timer > 120)
               ? 1.0
               : (delete_warn_timer / 120.0);
    var _bw = 500;
    var _bh = 60;
    var _bx = _gui_w * 0.5 - _bw * 0.5;
    var _by = _gui_h * 0.5 - _bh * 0.5;
    draw_set_alpha(_alpha);
    draw_set_color(c_black);
    draw_rectangle(_bx, _by, _bx + _bw, _by + _bh, false);
    draw_set_color(make_color_rgb(255, 140, 0));
    draw_rectangle(_bx, _by, _bx + _bw, _by + _bh, true);
    draw_line_width(_bx,       _by,       _bx + _bw, _by,       3);
    draw_line_width(_bx,       _by + _bh, _bx + _bw, _by + _bh, 3);
    draw_line_width(_bx,       _by,       _bx,       _by + _bh, 3);
    draw_line_width(_bx + _bw, _by,       _bx + _bw, _by + _bh, 3);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(255, 140, 0));
    draw_set_halign(fa_center);
    draw_text(_bx + _bw * 0.5, _by + 10, "CANNOT DELETE - ASSET IN USE:");
    draw_set_font(fnt_c64_code);
    draw_set_color(c_white);
    draw_text(_bx + _bw * 0.5, _by + 28, delete_warn_name);
    draw_set_halign(fa_left);
    draw_set_alpha(1.0);
}

// -------------------------------------------------------
// RELOAD NOTIFICATION
// -------------------------------------------------------
if (reload_notify_timer > 0 && array_length(reload_notify_names) > 0) {
    var _alpha   = min(1.0, reload_notify_timer / 60.0);
    var _nx      = panel_x;
    var _nr      = panel_x + panel_w;
    var _count   = array_length(reload_notify_names);
    var _box_h   = 20 + (_count * 14) + 6;
    var _ny      = panel_y - _box_h - 6;

    draw_set_alpha(_alpha);
    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(_nx, _ny, _nr, _ny + _box_h, false);
    draw_set_color(make_color_rgb(50, 50, 70));
    draw_rectangle(_nx, _ny, _nr, _ny + _box_h, true);
    draw_set_color(make_color_rgb(50, 180, 80));
    draw_rectangle(_nx, _ny, _nx + 4, _ny + _box_h, false);

    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(120, 200, 140));
    draw_text(_nx + 8, _ny + 5, "AUTO RELOADED:");
    draw_set_font(fnt_c64_code);
    draw_set_color(c_white);
    for (var _ni = 0; _ni < _count; _ni++) {
        draw_text(_nx + 8, _ny + 18 + (_ni * 14), reload_notify_names[_ni]);
    }
    draw_set_alpha(1.0);
}
