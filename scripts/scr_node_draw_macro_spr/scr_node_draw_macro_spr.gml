function scr_node_draw_macro_spr(_draw_x, _y, _cam_x, _cam_y, _cam_zoom) {
    var _header_h    = 24;
    var _line_h      = 14;
    var _asset_name  = string(instructions[0][1]);
    var _slot        = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0;
    var _msx         = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0;
    var _msy         = is_real(instructions[0][4]) ? real(instructions[0][4]) : 0;
    var _mframe      = is_real(instructions[0][5]) ? real(instructions[0][5]) : 0;
    var _set_globals = is_real(instructions[0][6]) ? real(instructions[0][6]) : 1;

    var _asset      = undefined;
    var _asset_addr = 0x7000;
    var _asset_mc   = false;
    if (instance_exists(obj_asset_manager) && _asset_name != "") {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "SPRITE_SET" && _a.name == _asset_name) {
                _asset      = _a;
                _asset_addr = _a.address;
                if (variable_struct_exists(_a.meta, "sprite_mcs") &&
                    _mframe < array_length(_a.meta.sprite_mcs)) {
                    _asset_mc = (_a.meta.sprite_mcs[_mframe] == 1);
                }
                break;
            }
        }
    }

    var _has_asset = (_asset != undefined);
    var _bank_hex  = string_upper(decimal_to_hex(_asset_addr));
    while (string_length(_bank_hex) < 4) _bank_hex = "0" + _bank_hex;
    var _vic_ptr = (_asset_addr / 64) + _mframe;

    draw_set_font(fnt_c64_tiny);
    var _mly = _y + _header_h + 4;
	
	    // Define colors locally to match the style
    var _c_edit = make_color_rgb(120, 220, 120); // Light Green (Interactive)
    var _c_dim  = make_color_rgb(120, 120, 120); // Grey (Static)
    var _c_warn = make_color_rgb(200, 60, 60);   // Red (None/Missing)

    // Row 1: Asset name
    var _name_hover = point_in_rectangle(mouse_x, mouse_y, _draw_x + 70, _mly, _draw_x + width - 8, _mly + 16);
    draw_set_color(_c_edit);
    draw_text(_draw_x + 10, _mly, "ASSET:");
    draw_set_color(_has_asset ? make_color_rgb(20, 60, 20) : make_color_rgb(60, 20, 20));
    draw_rectangle(_draw_x + 68, _mly + 3, _draw_x + width - 8, _mly + 13  , false);
    draw_set_color(_has_asset ? c_lime : (_name_hover ? c_white : make_color_rgb(200, 80, 80)));
    draw_text(_draw_x + 72, _mly, _asset_name == "" ? "CLICK TO SET" : _asset_name );
    _mly += _line_h;

// Row 2: Address / PTR
    draw_set_color(_c_dim);   draw_text(_draw_x + 10,  _mly, "ADDR:");
    draw_set_color(_has_asset ? c_aqua : c_gray);
    draw_text(_draw_x + 60, _mly, "$" + _bank_hex);
    
    draw_set_color(_c_dim);   draw_text(_draw_x + 110, _mly, "PTR:");
    draw_set_color(_has_asset ? c_yellow : c_gray);

    // Resolve screen RAM using same priority as compile: MACRO_BMP > MACRO_VIC > default
var _spr_vic_bank    = floor(_asset_addr / 0x4000);
var _spr_bank_base   = _spr_vic_bank * 0x4000;
var _draw_screen_ram = _spr_bank_base + 0x2000;
if (_spr_vic_bank == 0) _draw_screen_ram = 0x0400;
if (_spr_vic_bank == 2) _draw_screen_ram = _spr_bank_base + 0x3C00;
if (_spr_vic_bank == 3) _draw_screen_ram = _spr_bank_base + 0x0400;
    var _ptr_mem_loc  = _draw_screen_ram + 0x03F8 + _slot;
    var _vic_ptr_byte = ((_asset_addr / 64) + _mframe) & 0xFF;

    var _ptr_str = "$" + string_upper(decimal_to_hex(_ptr_mem_loc));
    draw_text(_draw_x + 146, _mly, _ptr_str);
    
    _mly += _line_h;

    // Row 3: Slot / Mode
    draw_set_color(_c_edit);   draw_text(_draw_x + 10,  _mly, "SPRITE:");
    draw_set_color(c_yellow); draw_text(_draw_x + 60,  _mly, string(_slot));

    draw_set_color(_c_edit);  draw_text(_draw_x + 80,  _mly, "X:");
    draw_set_color(c_aqua);  draw_text(_draw_x + 95,  _mly, string(_msx));
    draw_set_color(_c_edit);  draw_text(_draw_x + 140,  _mly, "Y:");
    draw_set_color(c_aqua);  draw_text(_draw_x + 155, _mly, string(_msy));
    _mly += _line_h;

    // Row 4: Frame navigator
    draw_set_color(_c_edit); draw_text(_draw_x + 10, _mly, "FRAME:");
	_mly+=4
    var _nav_lx = _draw_x + 70;
    var _nav_rx = _draw_x + 110;
    var _nav_hw = 16;
    var _nav_hh = 10;
    var _hl = point_in_rectangle(mouse_x, mouse_y, _nav_lx, _mly, _nav_lx + _nav_hw, _mly + _nav_hh);
    var _hr = point_in_rectangle(mouse_x, mouse_y, _nav_rx, _mly, _nav_rx + _nav_hw, _mly + _nav_hh);
    draw_set_color(_hl ? c_white : c_aqua);
    draw_triangle(_nav_lx + _nav_hw, _mly, _nav_lx + _nav_hw, _mly + _nav_hh, _nav_lx, _mly + _nav_hh * 0.5, false);
    draw_set_color(c_yellow);
    draw_set_halign(fa_left);
	_mly-=4
    draw_text(_draw_x + 96, _mly, string(_mframe) + "          $" + string_upper(decimal_to_hex(_vic_ptr_byte)));
	_mly+=4
    draw_set_color(_hr ? c_white : c_aqua);
    draw_triangle(_nav_rx, _mly, _nav_rx, _mly + _nav_hh, _nav_rx + _nav_hw, _mly + _nav_hh * 0.5, false);
    _mly += _line_h;

    // Sprite preview
    var _prev_x = _draw_x + 10;
    var _prev_y = _mly;
    var _cell_w = 24 * 2 + 4;
    var _cell_h = 21 * 2 + 4;
    // Cell background = the asset's C64 BG colour (so the sprite's
    // transparent BG pixels composite correctly). Falls back to a neutral
    // dim panel colour when there's no asset assigned yet.
    if (_has_asset && variable_struct_exists(_asset.meta, "bg_col")) {
        draw_set_color(scr_c64_pepto_colour(_asset.meta.bg_col));
    } else {
        draw_set_color(make_color_rgb(40, 40, 50));
    }
    draw_rectangle(_prev_x, _prev_y, _prev_x + _cell_w, _prev_y + _cell_h, false);
    // Thin border so the preview cell is visually distinct from the node BG
    draw_set_color(make_color_rgb(80, 60, 30));
    draw_rectangle(_prev_x, _prev_y, _prev_x + _cell_w, _prev_y + _cell_h, true);
    if (_has_asset &&
        variable_struct_exists(_asset.meta, "spr_sprites") &&
        _mframe < array_length(_asset.meta.spr_sprites) &&
        _asset.meta.spr_sprites[_mframe] != -1 &&
        sprite_exists(_asset.meta.spr_sprites[_mframe])) {
        gpu_set_tex_filter(false);
        draw_sprite(_asset.meta.spr_sprites[_mframe], 0, _prev_x+2, _prev_y+2);
		gpu_set_tex_filter(true);
    } else {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(60, 60, 80));
        draw_set_halign(fa_center);
        draw_text(_prev_x + _cell_w * 0.5, _prev_y + _cell_h * 0.5 - 4, _has_asset ? "NO CACHE" : "NO ASSET");
        draw_set_halign(fa_left);
    }
	// Warning message — tell user if sprite bank mismatches active VIC config
    draw_set_font(fnt_c64_tiny);
    var _active_bank = 0;
    var _bank_mismatch = false;
    with (obj_c64_node) {
        if (node_type == "MACRO_BMP" && is_connected) {
            var _chk_addr = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0x4000;
            _active_bank = floor(_chk_addr / 0x4000);
            break;
        }
    }
    with (obj_c64_node) {
        if (node_type == "MACRO_VIC" && is_connected) {
            _active_bank = is_real(instructions[0][2]) ? real(instructions[0][2]) : 0;
            break;
        }
    }
	
	
    var _spr_bank = floor(_asset_addr / 0x4000);
    if (_spr_bank != _active_bank) {
        _bank_mismatch = true;
    }
	
//var _need_base = _active_bank * 0x4000;
//    var _need_hex  = string_upper(decimal_to_hex(_need_base + 0x0800));
//    draw_set_color(_bank_mismatch ? c_red : c_orange);
//    var _msg = _bank_mismatch
//        ? ("USING VIC BANK " + string(_spr_bank) + "\nMOVE SPR TO $" + _need_hex + "+\nIF USING CHARMAP")
//        : ("AUTO BANK SWITCH\nBUT WITH BITMAP IT\nEXPECTS VIC BANK 1");
//    draw_text(_prev_x + _cell_w + 10, _prev_y, _msg);
	
    _mly += _cell_h + 4;

    //// SET GLOBALS checkbox
    //var _sgchk_x = _draw_x + 10;
    //var _sgchk_y = _mly;
    //draw_set_color(_set_globals ? c_lime : make_color_rgb(60, 60, 60));
    //draw_rectangle(_sgchk_x, _sgchk_y, _sgchk_x + 16, _sgchk_y + 16, false);
    //draw_set_font(fnt_c64_tiny);
    //draw_set_color(_set_globals ? c_lime : c_gray);
    //draw_text(_sgchk_x + 18, _sgchk_y, "SET GLOBALS");
    //_mly += 20;

  //  var _raw_h = _mly - _y + 4;
  //  height = ceil(_raw_h / 20) * 20;


}