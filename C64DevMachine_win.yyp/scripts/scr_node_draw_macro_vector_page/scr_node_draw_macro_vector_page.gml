/// @function scr_node_draw_macro_vector_page(_draw_x, _y)
function scr_node_draw_macro_vector_page(_draw_x, _y) {
    var _header_h   = 24;
    var _line_h     = 12;
    // ---- normalise instruction layout to house convention ----
    // ["macro_vector_page", asset, use_var_flag, page_or_varname]
    // Legacy saves stored the literal page index in slot 2 with no slot 3.
    // Detect that (slot 3 absent) and migrate: slot 3 = old page, slot 2 = 0.
    while (array_length(instructions[0]) < 4) {
        array_push(instructions[0], 0);
    }
    if (!is_real(instructions[0][2])) instructions[0][2] = 0;
    var _asset_name = string(instructions[0][1]);
    var _use_var    = real(instructions[0][2]);
    var _page_idx   = (_use_var == 0 && is_real(instructions[0][3])) ? real(instructions[0][3]) : 0;
    var _var_name   = is_string(instructions[0][3]) ? instructions[0][3] : "";

    var _asset      = undefined;
    var _page_count = 0;
    var _cmd_count  = 0;
    var _pg_bg = 0, _pg_c1 = 1, _pg_c2 = 2, _pg_c3 = 3;
    if (instance_exists(obj_asset_manager) && _asset_name != "") {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "VECTOR_BITMAP" && _a.name == _asset_name) {
                _asset = _a;
                if (variable_struct_exists(_a.meta, "pages") && is_array(_a.meta.pages)) {
                    _page_count = array_length(_a.meta.pages);
                    if (_page_idx >= 0 && _page_idx < _page_count) {
                        var _pg = _a.meta.pages[_page_idx];
                        if (variable_struct_exists(_pg, "commands")) _cmd_count = array_length(_pg.commands);
                        _pg_bg = variable_struct_exists(_pg, "bg")   ? _pg.bg   : 0;
                        _pg_c1 = variable_struct_exists(_pg, "col1") ? _pg.col1 : 1;
                        _pg_c2 = variable_struct_exists(_pg, "col2") ? _pg.col2 : 2;
                        _pg_c3 = variable_struct_exists(_pg, "col3") ? _pg.col3 : 3;
                    }
                }
                break;
            }
        }
    }
    var _has_asset  = (_asset != undefined);
    var _page_valid = (_has_asset && _page_idx >= 0 && _page_idx < _page_count);

    draw_set_font(fnt_c64_tiny);
    var _ly = _y + _header_h + 4;

    // Row 1: Asset name (click to pick)
    var _name_hover = point_in_rectangle(mouse_x, mouse_y, _draw_x + 68, _ly, _draw_x + width - 8, _ly + 16);
    draw_set_color(make_color_rgb(120, 220, 120));
    draw_text(_draw_x + 10, _ly, "ASSET:");
    draw_set_color(_has_asset ? c_lime : (_name_hover ? c_white : make_color_rgb(200, 80, 80)));
    draw_text(_draw_x + 72, _ly, _asset_name == "" ? "CLICK TO SET" : _asset_name);
    _ly += _line_h;

    // Row 2: Page selector (literal) OR var name (var-driven) + VAR toggle button
    var _tog_w = 30;
    var _tog_x = _draw_x + width - _tog_w - 8;
    var _pg_hover = point_in_rectangle(mouse_x, mouse_y, _draw_x + 60, _ly, _tog_x - 4, _ly + 12);
    var _tog_hover = point_in_rectangle(mouse_x, mouse_y, _tog_x, _ly, _tog_x + _tog_w, _ly + 12);
    if (_use_var == 1) {
        draw_set_color(make_color_rgb(120, 220, 120));; draw_text(_draw_x + 10, _ly, "VAR:");
        var _has_var = (_var_name != "");
        draw_set_color(_has_var ? c_aqua : (_pg_hover ? c_white : make_color_rgb(200, 60, 60)));
        draw_text(_draw_x + 60, _ly, _has_var ? _var_name : "CLICK TO SET");
    } else {
        draw_set_color(c_gray); draw_text(_draw_x + 10, _ly, "PAGE:");
        draw_set_color(_page_valid ? (_pg_hover ? c_white : c_yellow) : make_color_rgb(200, 60, 60));
        var _pg_txt = string(_page_idx) + (_has_asset ? ("/" + string(max(0, _page_count - 1))) : "");
        draw_text(_draw_x + 60, _ly, _pg_txt);
    }
    // VAR toggle button (lit when active)
    draw_set_color(_use_var == 1 ? make_color_rgb(0, 150, 180) : make_color_rgb(50, 50, 60));
    draw_rectangle(_tog_x, _ly+4, _tog_x + _tog_w, _ly + 16, false);
    draw_set_color(_tog_hover ? c_white : make_color_rgb(120, 120, 140));
    draw_rectangle(_tog_x, _ly+4, _tog_x + _tog_w, _ly + 16, true);
    draw_set_color(_use_var == 1 ? c_white : make_color_rgb(140, 140, 150));
    draw_text(_tog_x + 3, _ly + 1, "VAR");
    _ly += _line_h;
    if (_use_var == 1) {
        // Var-driven: page resolved at runtime, editor owns the page data
        draw_set_color(c_gray); draw_text(_draw_x + 10, _ly, "MODE:");
        draw_set_color(c_aqua);
        draw_text(_draw_x + 60, _ly, "VAR DRIVEN");
        _ly += _line_h;
        draw_set_color(make_color_rgb(180, 130, 120));
        draw_text(_draw_x + 10, _ly, "CHECK EDITOR");
        _ly += _line_h;
    } else {
        // Row 3: this page's 4 colours as swatches
        draw_set_color(c_gray); draw_text(_draw_x + 10, _ly, "COLS:");
        if (_page_valid) {
            var _sw = 12;
            var _cx = _draw_x + 60;
            var _cols = [_pg_bg, _pg_c1, _pg_c2, _pg_c3];
            for (var _c = 0; _c < 4; _c++) {
                draw_set_color(scr_c64_pepto_colour(_cols[_c]));
                draw_rectangle(_cx, _ly+5, _cx + _sw, _ly + 13, false);
                draw_set_color(make_color_rgb(90, 90, 110));
                draw_rectangle(_cx, _ly+5, _cx + _sw, _ly + 13, true);
                _cx += _sw + 4;
            }
        } else {
            draw_set_color(make_color_rgb(200, 60, 60));
            draw_text(_draw_x + 60, _ly, _has_asset ? "BAD PAGE" : "NO ASSET");
        }
        _ly += _line_h;
        // Row 4: command count for this page
        draw_set_color(c_gray); draw_text(_draw_x + 10, _ly, "CMDS:");
        if (_page_valid) {
            draw_set_color(_cmd_count > 0 ? make_color_rgb(80, 200, 80) : c_orange);
            draw_text(_draw_x + 52, _ly, string(_cmd_count) + (_cmd_count > 0 ? " primitives" : " (EMPTY)"));
        } else {
            draw_set_color(make_color_rgb(120, 120, 120));
            draw_text(_draw_x + 52, _ly, "-");
        }
        _ly += _line_h;
    }
}