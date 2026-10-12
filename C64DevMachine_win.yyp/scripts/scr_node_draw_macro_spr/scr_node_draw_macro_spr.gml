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

    draw_set_font_l(fnt_c64_tiny);
    var _mly = _y + _header_h + 4;
	
	    // Define colors locally to match the style
    var _c_edit = make_color_rgb(120, 220, 120); // Light Green (Interactive)
    var _c_dim  = make_color_rgb(120, 120, 120); // Grey (Static)
    var _c_warn = make_color_rgb(200, 60, 60);   // Red (None/Missing)

    // Row 1: Asset name
    var _name_hover = point_in_rectangle(mouse_x, mouse_y, _draw_x + 70, _mly, _draw_x + width - 8, _mly + 16);
    draw_set_color(_c_edit);
    scr_node_macro_text_l(_draw_x + 10, _mly, "ASSET:");
    draw_set_color(_has_asset ? make_color_rgb(20, 60, 20) : make_color_rgb(60, 20, 20));
    scr_macro_body_rectangle(_draw_x + 68, _mly + 3, _draw_x + width - 8, _mly + 13  , false);
    draw_set_color(_has_asset ? c_lime : (_name_hover ? c_white : make_color_rgb(200, 80, 80)));
    scr_node_macro_text_l(_draw_x + 72, _mly, _asset_name == "" ? L("CLICK TO SET") : _asset_name );
    if (global.tour_active && is_connected) {
        scr_tour_capture_world("FIELD:MACRO_SPR:asset", _draw_x + 68, _mly - 1, _draw_x + width - 8, _mly + 14);
    }
    _mly += _line_h;

// Row 2: Address / PTR
    draw_set_color(_c_dim);   scr_node_macro_text_l(_draw_x + 10,  _mly, "ADDR:");
    draw_set_color(_has_asset ? c_aqua : c_gray);
    scr_node_macro_text_l(_draw_x + 60, _mly, "$" + _bank_hex);
    
    draw_set_color(_c_dim);   scr_node_macro_text_l(_draw_x + 110, _mly, "PTR:");
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
    scr_node_macro_text_l(_draw_x + 146, _mly, _ptr_str);
    
    _mly += _line_h;

    // Row 3: Slot / Mode
    draw_set_color(_c_edit);   scr_node_macro_text_l(_draw_x + 10,  _mly, "SPRITE:");
    draw_set_color(c_yellow); scr_node_macro_text_l(_draw_x + 60,  _mly, string(_slot));

    draw_set_color(_c_edit);  scr_node_macro_text_l(_draw_x + 80,  _mly, "X:");
    draw_set_color(c_aqua);  scr_node_macro_text_l(_draw_x + 95,  _mly, string(_msx));
    draw_set_color(_c_edit);  scr_node_macro_text_l(_draw_x + 140,  _mly, "Y:");
    draw_set_color(c_aqua);  scr_node_macro_text_l(_draw_x + 155, _mly, string(_msy));
    _mly += _line_h;

    // Row 4: Frame navigator
    draw_set_color(_c_edit); scr_node_macro_text_l(_draw_x + 10, _mly, "FRAME:");
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
    scr_node_macro_text_l(_draw_x + 96, _mly, string(_mframe) + "          $" + string_upper(decimal_to_hex(_vic_ptr_byte)));
	_mly+=4
    draw_set_color(_hr ? c_white : c_aqua);
    draw_triangle(_nav_rx, _mly, _nav_rx, _mly + _nav_hh, _nav_rx + _nav_hw, _mly + _nav_hh * 0.5, false);
    _mly += _line_h;

    // Sprite preview: a tab on the node's left, so the node itself is only
    // as tall as its rows. The handle tucks it in and pulls it out again.
    // Drawn with plain draw_* calls: it sits outside the body, so it must
    // not count towards the node's measured height.
    var _tab = scr_macro_spr_tab(id, _draw_x);
    var _cell_w = 24 * 2 + 4;
    var _cell_h = 21 * 2 + 4;
    var _tab_col = make_color_rgb(180, 60, 180);
    if (_tab.out) {
        draw_set_color(make_color_rgb(42, 40, 72));
        draw_rectangle(_tab.px1, _tab.py1, _tab.px2, _tab.py2, false);
        draw_set_color(_tab_col);
        draw_rectangle(_tab.px1, _tab.py1, _tab.px2, _tab.py2, true);
        var _prev_x = _tab.cx;
        var _prev_y = _tab.cy;
        // Cell background = the asset's C64 BG colour (so the sprite's
        // transparent BG pixels composite correctly). Falls back to a neutral
        // dim panel colour when there's no asset assigned yet.
        if (_has_asset && variable_struct_exists(_asset.meta, "bg_col")) {
            draw_set_color(scr_c64_pepto_colour(_asset.meta.bg_col));
        } else {
            draw_set_color(make_color_rgb(40, 40, 50));
        }
        draw_rectangle(_prev_x, _prev_y, _prev_x + _cell_w, _prev_y + _cell_h, false);
        draw_set_color(make_color_rgb(80, 60, 30));
        draw_rectangle(_prev_x, _prev_y, _prev_x + _cell_w, _prev_y + _cell_h, true);
        if (_has_asset &&
            variable_struct_exists(_asset.meta, "spr_sprites") &&
            _mframe < array_length(_asset.meta.spr_sprites) &&
            _asset.meta.spr_sprites[_mframe] != -1 &&
            sprite_exists(_asset.meta.spr_sprites[_mframe])) {
            gpu_set_tex_filter(false);
            draw_sprite(_asset.meta.spr_sprites[_mframe], 0, _prev_x + 2, _prev_y + 2);
            gpu_set_tex_filter(true);
        } else {
            draw_set_font_l(fnt_c64_tiny);
            draw_set_color(make_color_rgb(90, 90, 110));
            draw_set_halign(fa_center);
            draw_text_l(_prev_x + _cell_w * 0.5, _prev_y + _cell_h * 0.5 - 6, _has_asset ? L("NO CACHE") : L("NO ASSET"));
            draw_set_halign(fa_left);
        }
    }
    // The handle: points left to pull the tab out, right to tuck it in
    var _h_hot = point_in_rectangle(mouse_x, mouse_y, _tab.hx1, _tab.hy1, _tab.hx2, _tab.hy2);
    draw_set_color(_h_hot ? make_color_rgb(220, 110, 220) : _tab_col);
    draw_rectangle(_tab.hx1, _tab.hy1, _tab.hx2, _tab.hy2, false);
    draw_set_color(c_white);
    var _tmx = (_tab.hx1 + _tab.hx2) * 0.5;
    var _tmy = (_tab.hy1 + _tab.hy2) * 0.5;
    if (_tab.out) {
        draw_triangle(_tmx - 3, _tmy - 5, _tmx - 3, _tmy + 5, _tmx + 3, _tmy, false);
    } else {
        draw_triangle(_tmx + 3, _tmy - 5, _tmx + 3, _tmy + 5, _tmx - 3, _tmy, false);
    }

    //// SET GLOBALS checkbox
    //var _sgchk_x = _draw_x + 10;
    //var _sgchk_y = _mly;
    //draw_set_color(_set_globals ? c_lime : make_color_rgb(60, 60, 60));
    //scr_macro_body_rectangle(_sgchk_x, _sgchk_y, _sgchk_x + 16, _sgchk_y + 16, false);
    //draw_set_font_l(fnt_c64_tiny);
    //draw_set_color(_set_globals ? c_lime : c_gray);
    //scr_node_macro_text_l(_sgchk_x + 18, _sgchk_y, "SET GLOBALS");
    //_mly += 20;

  //  var _raw_h = _mly - _y + 4;
  //  height = ceil(_raw_h / 20) * 20;


}

/// @desc Where a SPRITE node's preview tab sits, left of the node drawn at
///       _draw_x: the handle (hx/hy), the panel (px/py) and the preview
///       cell's corner (cx, cy). out: the tab is pulled out
///       (instructions[0][7]: 1 out, the default; 0 tucked in).
function scr_macro_spr_tab(_n, _draw_x) {
    var _i0  = _n.instructions[0];
    var _out = (array_length(_i0) < 8) || !is_real(_i0[7]) || (real(_i0[7]) != 0);
    var _t   = { out: _out };
    _t.hx2 = _draw_x;
    _t.hx1 = _draw_x - 12;
    _t.hy1 = _n.y + 28;
    _t.hy2 = _n.y + 80;
    _t.px2 = _t.hx1;
    _t.px1 = _t.px2 - 58;
    _t.py1 = _t.hy1;
    _t.py2 = _t.hy2;
    _t.cx  = _t.px1 + 3;
    _t.cy  = _t.py1 + 3;
    return _t;
}
