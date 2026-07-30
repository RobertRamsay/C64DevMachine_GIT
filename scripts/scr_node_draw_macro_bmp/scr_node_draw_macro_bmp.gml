function scr_node_draw_macro_bmp(_draw_x, _y) {
    var _header_h   = 24;
    var _line_h     = 12;
    var _asset_name = string(instructions[0][1]);
    var _bmp_addr = 0x4000;
    if (is_real(instructions[0][2])) {
        _bmp_addr = real(instructions[0][2]);
    }
    if (is_string(instructions[0][2]) && string_digits(instructions[0][2]) != "") {
        _bmp_addr = real(instructions[0][2]);
    }

    var _asset    = undefined;
    var _has_data = false;
    var _bg_col   = 0;
    if (instance_exists(obj_asset_manager) && _asset_name != "") {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "BITMAP" && _a.name == _asset_name) {
                _asset    = _a;
                
                // Check if file exists on disk OR the has_data flag is true
                var _file_exists = (_a.file != "" && file_exists(_a.file));
                _has_data = _file_exists || (variable_struct_exists(_a.meta, "has_data") && _a.meta.has_data);
                
                if (variable_struct_exists(_a.meta, "bg_col")) _bg_col = _a.meta.bg_col;
                instructions[0][2] = _a.address;
                _bmp_addr = _a.address;
                break;
            }
        }
    }
    var _has_asset = (_asset != undefined);
    var _vic_bank  = floor(_bmp_addr / 0x4000);
    var _cia_val   = 3 - _vic_bank;
	// Local standard colors
    var _c_edit = make_color_rgb(120, 220, 120); // Light Green for editable labels

    draw_set_font(fnt_c64_tiny);
    var _ly = _y + _header_h + 4;

    // Row 1: Asset name
    var _name_hover = point_in_rectangle(mouse_x, mouse_y, _draw_x + 68, _ly, _draw_x + width - 8, _ly + 16);
    draw_set_color(_c_edit);
    draw_text(_draw_x + 10, _ly, "ASSET:");
    draw_set_color(_has_asset ? make_color_rgb(20, 60, 20) : make_color_rgb(60, 20, 20));
   // draw_rectangle(_draw_x + 68, _ly - 1, _draw_x + width - 8, _ly, false);
    draw_set_color(_has_asset ? c_lime : (_name_hover ? c_white : make_color_rgb(200, 80, 80)));
    draw_text(_draw_x + 72, _ly, _asset_name == "" ? "CLICK TO SET \/" : _asset_name + " \/");
    _ly += _line_h;

    // Row 2: Bitmap addr
    var _bh = string_upper(decimal_to_hex(_bmp_addr));
    while (string_length(_bh) < 4) _bh = "0" + _bh;
    draw_set_color(c_gray);  draw_text(_draw_x + 10, _ly, "BITMAP:");
    draw_set_color(c_aqua);  draw_text(_draw_x + 80, _ly, "$" + _bh);
    if (_has_asset) {
        var _bmp_mode_lbl = scr_asset_bmp_is_hires(_asset) ? "HIRES" : "MC";
        draw_set_color(c_gray);
        draw_text(_draw_x + 140, _ly, _bmp_mode_lbl);
    }
    _ly += _line_h;



    // Row 4: VIC bank
    draw_set_color(c_gray);   draw_text(_draw_x + 10, _ly, "VIC BANK:");
    draw_set_color(c_yellow); draw_text(_draw_x + 90, _ly, string(_vic_bank) + "  CIA=$0" + string(_cia_val));
    _ly += _line_h;

    // Row 4b: char-ROM shadow advisory (set by scr_c64_do_update_addresses PASS 12)
    if (bmp_shadow_warn) {
        draw_set_color(c_orange);
        draw_text(_draw_x + 10, _ly, "! CHAR ROM SHADOW");
        _ly += _line_h;
        draw_set_color(make_color_rgb(160, 120, 60));
        if (_vic_bank == 2) {
            draw_text(_draw_x + 10, _ly, "  DATA OK / USE $A000 TO SHOW");
        } else {
            draw_text(_draw_x + 10, _ly, "  DATA OK / USE $2000 TO SHOW");
        }
        _ly += _line_h;
    }

// Row 5: Data status
    draw_set_color(c_gray); draw_text(_draw_x + 10, _ly, "DATA:");
    if (_has_data && _has_asset) {
        draw_set_color(make_color_rgb(80, 200, 80));
        var _fname = filename_name(_asset.file);
        
        // If filename is blank (newly created asset), show the expected name
        if (_fname == "") _fname = _asset.name + ".kla";
        
        draw_text(_draw_x + 52, _ly, string_copy(_fname,0,18) +"...");
    } else if (_has_asset) {
        draw_set_color(c_orange);
        draw_text(_draw_x + 60, _ly, "NO FILE LOADED");
    } else {
        draw_set_color(make_color_rgb(200, 60, 60));
        draw_text(_draw_x + 60, _ly, "NO ASSET");
    }
    _ly += _line_h;

// Row 6: Pre-clear toggle
    var _preclear = 0;
    if (array_length(instructions[0]) > 4 && is_real(instructions[0][4])) {
        _preclear = real(instructions[0][4]);
    }
    draw_set_color(c_gray);
    draw_text(_draw_x + 10, _ly, "PRECLEAR:");
    if (_preclear == 1) {
        draw_set_color(c_lime);
        draw_text(_draw_x + 90, _ly, "YES");
    } else {
        draw_set_color(make_color_rgb(120, 120, 120));
        draw_text(_draw_x + 90, _ly, "NO");
    }
 _ly += _line_h;


       // Detect if a TEXT_SCROLL node exists below us on the main spine
    var _show_warning = false;
    if (is_connected && org_parent == noone) {
        with (obj_c64_node) {
            if (is_connected && org_parent == noone && id != other.id && node_type == "MACRO_TEXT_SCROLL" && y < other.y) {
                _show_warning = true;
            }
        }
    }

    // Warning banner — draw BEFORE node_height is set so it renders within bounds
    if (_show_warning) {
        var _warn_y1     = _y + 20;
        var _warn_y2     = _y + height
        var _warn_cx     = _draw_x + (width / 2);
        var _warn_cy     = _y + (_ly - _y) / 2;
        var _flash_col   = (current_time mod 600 < 300) ? c_white : c_black;
        draw_set_alpha(0.8);
        draw_rectangle_colour(_draw_x, _warn_y1, _draw_x + width, _warn_y2, c_red, c_black, c_red, c_black, false);
        draw_set_alpha(1.0);
        draw_set_color(_flash_col);
        draw_set_halign(fa_center);
        draw_text(_warn_cx, _warn_cy, "! PUT ABOVE TEXT SCROLL !");
        draw_set_halign(fa_left);
    }

}