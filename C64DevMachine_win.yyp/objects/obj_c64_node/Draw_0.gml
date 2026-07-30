/// @desc Render Node (Unified Gutter, Stats, Out-dent, ORG & Comment Nodes)
if obj_workspace_manager.code_editor_open or obj_asset_manager.viewer_open exit;
global.ui_click_consumed = (global.ui_click_block_timer > 0);
// =============================================================
// A. VIEW CULL — early exit before any setup cost
// =============================================================
var _cam_x    = obj_workspace_manager.cam_x;
var _cam_y    = obj_workspace_manager.cam_y;
var _cam_zoom = obj_workspace_manager.cam_zoom;
var _view_w   = 1920 * _cam_zoom;
var _view_h   = 1080 * _cam_zoom;
var _margin   = 200;

var _cull_bottom = (node_type == "ORG") ? (y + 9999) : (y + height);
if (x + x_indent + width < _cam_x - _margin ||
    x + x_indent         > _cam_x + _view_w + _margin ||
    _cull_bottom         < _cam_y - _margin ||
    y                    > _cam_y + _view_h + _margin) exit;

if (node_type == "COMMENT" && !global.comments_visible) exit;

// Skip drawing if node is too small on screen to be useful
var _screen_h = height / _cam_zoom;
var _screen_w = width / _cam_zoom;
if (_screen_h < 3 || _screen_w < 4) exit;

// =============================================================
// B. LATCH BURST FX
// =============================================================
// Depth management: bring node to front while dragging, restore on release
if (is_dragging && !is_depth_pushed) {
    pre_click_depth = depth;
    depth = -32000;
    is_depth_pushed = true;
}
if (!is_dragging && is_depth_pushed) {
    depth = pre_click_depth;
    is_depth_pushed = false;
}

if (latch_glow_alpha > 0) {
    draw_set_alpha(latch_glow_alpha * 0.5);
    draw_rectangle_color(x-6, y-6, x+width+6, y+height+6, c_white, c_white, c_white, c_white, false);
    draw_set_alpha(1.0);
    latch_glow_alpha -= 0.05;
}

// =============================================================
// C. LAYOUT CONSTANTS
// =============================================================
var header_h = 20;
var line_h   = 18;
var pad      = global.nodepad;
var text_w   = global.node_display_width - 20;
x += x_indent;
var draw_x = x;

// LOD thresholds — higher zoom = more zoomed out = less detail
var _lod_full      = global.show_stats && (_cam_zoom < 2.0);
var _lod_addresses = (_cam_zoom < 1.6);                      // ORG/INIT address gutter always
var _lod_header  = (_cam_zoom < 3.5);  // header title text
var _lod_body    = (_cam_zoom < 2.0);  // node body text + body drawing (J block)
var _screen_cx   = _cam_x + (_view_w * 0.5);
var _screen_cy   = _cam_y + (_view_h * 0.5);
var _dx          = x - _screen_cx;
var _dy          = y - _screen_cy;
var _near_centre = ((_dx * _dx + _dy * _dy) < 640000); // 800^2, no zoom gate0^2
// above 4.0 — header colour box only, no text at all

// =============================================================
// D. DYNAMIC HEIGHT  (cached, only recalculates when dirty)
// =============================================================
var _G = 20;

if (height_dirty) {
    height_dirty = false;
    switch (node_type) {
    case "COMMENT":
        draw_set_font(fnt_c64_code);
        var _comment_raw = (array_length(instructions) > 0) ? string(instructions[0][1]) : "";
        var _raw_h = header_h + max(line_h, string_height_ext(_comment_raw, line_h, text_w)) + 8;
        height = ceil(_raw_h / _G) * _G;
        break;
    case "EXECUTE":     height = _G * 2; break;          // 40
	case "INIT":        height = _G * 4; break;          // 80
    case "ORG":         height = _G * 4; break;          // 80
    case "LABEL":       height = _G * 2; break;          // 60
    case "MACRO_SPR":   height = _G * 7;  break;         // 180
    case "MACRO_SID":    height = _G * 5;  break;         //
    case "MACRO_LOADER": height = _G * 5;  break;         // 120 — picker + status rows
    case "MACRO_CHR":   height = _G * 6;  break;         // 120
    case "MACRO_TRACK": height = _G * 3;  break;         // 100
    case "MACRO_PRINT": height = _G * 10;  break;
	case "MACRO_CLEAR_BMP_RECT": height = _G * 4;  break;   
    case "MACRO_PRINT_EXT": height = _G * 8;  break; 
    case "MACRO_PLACE_CHAR": height = _G * 9;  break;
	case "MACRO_RANDOM":     height = _G * 8;  break;
	// 8 base rows, +2 for each list that's in ASSET mode (list row, index row,
	// info row). Recomputed whenever height_dirty fires, so the mode buttons
	// just need to set it.
	case "MACRO_SID_SOUND": {
	    var _ss_rows = 8;
	    if (array_length(instructions[0]) > 4 && is_real(instructions[0][4]) && real(instructions[0][4]) == 2) {
	        _ss_rows += 2;
	    }
	    if (array_length(instructions[0]) > 7 && is_real(instructions[0][7]) && real(instructions[0][7]) == 2) {
	        _ss_rows += 2;
	    }
	    height = _G * _ss_rows;
	} break;
	case "MACRO_SID_SONG":   height = _G * 7;  break;   // 3 rows + 5-line pico footer
	case "MACRO_GET_CHAR":   height = _G * 7;  break; 
    case "MACRO_CLR_SCREEN": height = _G * 4;  break;
	case "MACRO_MATH":       height = _G * 5;  break;    
    case "NAMED_LOC":   height = _G * 3;  break;         // 60
    case "NEW_STR":     height = _G * 5;  break;         // 100
    case "MACRO_JOY":   height = _G * 6;  break;
    case "MACRO_VWAIT": height = _G * 3;  break;        
    case "MACRO_DISPLAY": height = _G * 4;  break;
    case "MACRO_WAIT":    height = _G * 5;  break;        
    case "MACRO_BMP":   height = _G * 6;  break;         
    case "MACRO_VECTOR_BMP": height = _G * 6;  break;    // 6 rows + header + pad
	case "MACRO_VECTOR_PAGE": height = _G * 4;  break;   // asset + page + status         
    case "BITMAP_KLA":  height = _G * 8;  break;         
    case "MACRO_MAP":        height = _G * 10;  break;
	case "MACRO_METAMAP":    height = _G * 8;   break;
	case "MACRO_MAP_SWITCH": height = _G * 5;   break;         
    case "MACRO_VIC":   height = _G * 6; break;         
	case "MACRO_MOVE":    height = _G * 7; break;
	case "MACRO_SEEK":    height = _G * 11; break;
	case "MACRO_MOVE_MEM":    height = _G * 4; break;
	case "MACRO_MOVE_BMP_BLOCK": height = _G * 10; break;
	case "MACRO_FLIP_X":  height = _G * 3; break;
	case "MACRO_PRIORITY":    height = _G * 4; break;
	case "MACRO_SPR_ENABLE":  height = _G * 4; break;
	case "MACRO_SPR_EXPAND":  height = _G * 6; break;
    case "MACRO_SCROLL":      height = _G * 9; break;   
	case "MACRO_VSCROLL": height = _G * 6;  break;         // 160
    case "MACRO_TEXT_SCROLL": height = _G * 9; break;  
    case "MACRO_IRQ":         height = _G * 5;  break;   
    case "MACRO_IRQ_HANDLER": height = _G * 5;  break;   
    case "COND_IF":          height = _G * 4;  break;
	case "COND_IF_WORD":     height = _G * 4;  break;
    case "BANK_SWITCH":      height = _G * 6;  break;
    case "MACRO_COLLISION":  height = _G * 10;  break;
	case "MACRO_COLL_ADV":   height = _G * 19;  break;    
    case "MACRO_ANIM":       height = _G * 18;  break;
    case "MACRO_SFX":        height = _G * 6;   break;
	case "MACRO_CODE":       height = _G * 5;   break;
    case "GET_VAR":     height = _G * 5;  break;         
    case "SET_VAR":     height = _G * 5;  break;     
    case "INC_VAR":
    case "DEC_VAR":     height = _G * 4;  break;
    case "COPY_VAR":    height = _G * 5;  break;        
    default:
        var _is_code_node = (node_type == "NORMAL" || node_type == "INIT");
        var _line_gap     = _is_code_node ? 12 : 22;
        var _bottom_pad   = _is_code_node ? 6 : global.nodepad;
        var _extra = 0;
        if (array_length(instructions) > 0) {
            var _mn        = string_lower(instructions[0][0]);
            var _is_branch = (string_char_at(_mn, 1) == "b" && string_length(_mn) == 3);
            var _is_jump   = (_mn == "jmp_abs" || _mn == "jmp_ind" || _mn == "jsr");
            if (_is_branch || _is_jump) && !obj_workspace_manager.opcode_extra_height _extra = 15;
        }
var _raw_h = header_h + (array_length(instructions) * _line_gap) + _bottom_pad + _extra;
        height = (ceil(_raw_h / _G)+obj_workspace_manager.opcode_extra_height) * _G;
        break;
    } // end switch
    cached_height = height;
} else {
    height = cached_height;
}

// =============================================================
// E. DYNAMIC WIDTH
// =============================================================
switch (node_type) {
    case "DATA_TEXT":
        draw_set_font(fnt_c64_code);
        var _txt_raw = (array_length(instructions) > 0) ? string(instructions[0][1]) : "";
        width = max(global.node_display_width, string_width("\"" + _txt_raw + "\"") + 20);
        break;
    case "SPR64":
        width = 200;
        break;
    default:
        width = global.node_display_width;
        break;
}

// =============================================================
// F. LABEL PICKER
// =============================================================
if (label_picker_open) {

    if (label_picker_mode == "BYTE_ASSET" || label_picker_mode == "TEXT_ASSET"
     || label_picker_mode == "SOUND_ASSET") {
        // One picker, three asset types. TEXT_ASSET lists TEXT_DATA (SID SOUND
        // note lists, MACRO_PRINT text); BYTE_ASSET lists BYTE_DATA;
        // SOUND_ASSET lists SOUND_EDITOR songs (MACRO_SID_SONG).
        var _want_type = "BYTE_DATA";
        var _pick_hdr  = "BYTE_DATA ASSETS";
        if (label_picker_mode == "TEXT_ASSET") {
            _want_type = "TEXT_DATA";
            _pick_hdr  = "TEXT_DATA ASSETS";
        } else if (label_picker_mode == "SOUND_ASSET") {
            _want_type = "MUSIC_MAKER";
            _pick_hdr  = "SONG ASSETS";
        }
        var _px      = draw_x + width + 8;
        var _py      = y + 36;
        var _pw      = 160;
        var _row_h   = 16;
        var _visible = 24;
        var _list_y  = _py + 18;
        var _arrow_y = _list_y + (_visible * _row_h) + 2;
        var _total_h = _arrow_y + 20 - _py;

        var _alist = ["[clear]"];
        if (instance_exists(obj_asset_manager)) {
            var _am = obj_asset_manager;
            for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
                var _a = _am.asset_list[| _ai];
                if (_a.type == _want_type) array_push(_alist, _a.name);
            }
        }
        var _count = array_length(_alist);

        draw_set_color(make_color_rgb(20, 20, 30));
        draw_rectangle(_px, _py, _px + _pw, _py + _total_h, false);
        draw_set_color(c_gray);
        draw_rectangle(_px, _py, _px + _pw, _py + _total_h, true);

        var _xhov = point_in_rectangle(mouse_x, mouse_y, _px, _py - 16, _px + _pw, _py);
        draw_set_color(_xhov ? c_red : make_color_rgb(80, 30, 30));
        draw_rectangle(_px, _py - 16, _px + _pw, _py, false);
        draw_set_color(c_gray);
        draw_rectangle(_px, _py - 16, _px + _pw, _py, true);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_px + (_pw * 0.5), _py - 17, _pick_hdr);
        draw_set_halign(fa_left);

        for (var _li = 0; _li < _visible; _li++) {
            var _idx = _li + label_picker_scroll;
            if (_idx >= _count) break;
            var _ry   = _list_y + (_li * _row_h);
            var _rhov = point_in_rectangle(mouse_x, mouse_y, _px, _ry, _px + _pw, _ry + _row_h);
            draw_set_color(_rhov ? make_color_rgb(40, 80, 60) : make_color_rgb(25, 25, 38));
            draw_rectangle(_px + 1, _ry, _px + _pw - 1, _ry + _row_h, false);
            draw_set_color(_rhov ? c_lime : c_yellow);
            draw_set_font(fnt_c64_tiny);
            draw_text(_px + 4, _ry + 2, _alist[_idx]);
        }

        var _up_hov   = point_in_rectangle(mouse_x, mouse_y, _px + 4,        _arrow_y, _px + 20,        _arrow_y + 16);
        var _down_hov = point_in_rectangle(mouse_x, mouse_y, _px + _pw - 20, _arrow_y, _px + _pw - 4,   _arrow_y + 16);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(_up_hov   ? c_white : (label_picker_scroll > 0                 ? c_aqua : c_gray));
        draw_text(_px + 6,        _arrow_y + 2, "^");
        draw_set_color(_down_hov ? c_white : (_count > _visible + label_picker_scroll ? c_aqua : c_gray));
        draw_text(_px + _pw - 16, _arrow_y + 2, "v");
        draw_set_color(make_color_rgb(60, 60, 80));
        draw_text(_px + 24, _arrow_y + 2, string(label_picker_scroll + 1) + "-" +
                  string(min(_count, label_picker_scroll + _visible)) + "/" + string(_count));

    } else if (label_picker_mode == "VAR" || label_picker_mode == "VAR_SRC") {
        // VAR PICKER — UV + HW TABS
        // label_picker_tab initialised in Create
        // VAR_SRC shares the same UV var list (byte->byte source pick)

        var _px      = draw_x + width + 8;
        var _py      = y + 36;
        var _pw      = 160;
        var _row_h   = 16;
        var _visible = 24;
        var _tab_h   = 20;
        var _list_y  = _py + _tab_h + 18;
        var _arrow_y = _list_y + (_visible * _row_h) + 2;
        var _total_h = _arrow_y + 20 - _py;

var _active_list = [];
        if (label_picker_tab == "HW") {
            if (global.hw_picker_active_category == -1) {
                for (var _c = 0; _c < array_length(global.hw_picker_categories); _c++) {
                    var _cat_name = global.hw_picker_categories[_c].name;
                    if (label_picker_filter_char != "" &&
                        string_upper(string_char_at(_cat_name, 1)) != label_picker_filter_char) continue;
                    array_push(_active_list, _cat_name);
                }
            } else {
                var _hw_items = global.hw_picker_categories[global.hw_picker_active_category].items;
                for (var _hi = 0; _hi < array_length(_hw_items); _hi++) {
                    if (label_picker_filter_char != "" &&
                        string_upper(string_char_at(_hw_items[_hi], 1)) != label_picker_filter_char) continue;
                    array_push(_active_list, _hw_items[_hi]);
                }
            }
        } else {
            for (var _ki = 0; _ki < array_length(global.named_loc_meta); _ki++) {
                var _entry = global.named_loc_meta[_ki];
                if (_entry.type != "UV") continue;
                if (label_picker_word_only) {
                    var _wenc = variable_struct_exists(_entry, "encoding") ? _entry.encoding : "byte";
                    if (_wenc != "word") continue;
                }
                if (label_picker_byte_only) {
                    var _bsz = variable_struct_exists(_entry, "size") ? _entry.size : 1;
                    if (_bsz != 1) continue;
                }
                if (label_picker_filter_char != "") {
                    var _fc_name = _entry.name;
                    if (string_pos("UV_", _fc_name) == 1) _fc_name = string_delete(_fc_name, 1, 3);
                    if (string_upper(string_char_at(_fc_name, 1)) != label_picker_filter_char) continue;
                }
                array_push(_active_list, _entry.name);
            }
            array_sort(_active_list, true);
            array_insert(_active_list, 0, "[clear]");
        }
        var _count = array_length(_active_list);

        // Background + border
        draw_set_color(make_color_rgb(20, 20, 30));
        draw_rectangle(_px, _py, _px + _pw, _py + _total_h, false);
        draw_set_color(c_gray);
        draw_rectangle(_px, _py, _px + _pw, _py + _total_h, true);

        // Tabs
        var _tab_labels = ["UV", "HW"];
        var _tab_w      = _pw / 2;
        for (var _ti = 0; _ti < 2; _ti++) {
            var _tx      = _px + (_ti * _tab_w);
            var _tab_sel = (label_picker_tab == _tab_labels[_ti]);
            var _thov    = point_in_rectangle(mouse_x, mouse_y, _tx, _py, _tx + _tab_w, _py + _tab_h);
            draw_set_color(_tab_sel ? make_color_rgb(40, 80, 120)
                         : (_thov  ? make_color_rgb(35, 50, 70)
                                   : make_color_rgb(18, 18, 28)));
            draw_rectangle(_tx, _py, _tx + _tab_w, _py + _tab_h, false);
            draw_set_color(_tab_sel ? c_white : c_gray);
            draw_set_font(fnt_c64_tiny);
            draw_set_halign(fa_center);
            draw_text(_tx + _tab_w * 0.5, _py + 3,
                      _tab_labels[_ti] == "UV" ? "UV VARS" : "HW REGS");
            draw_set_halign(fa_left);
        }

        // Tab divider
        draw_set_color(make_color_rgb(50, 50, 80));
        draw_line(_px, _py + _tab_h, _px + _pw, _py + _tab_h);


		// X close (Full width header)
        var _xhov = point_in_rectangle(mouse_x, mouse_y, _px, _py - 16, _px + _pw, _py);
        draw_set_color(_xhov ? c_red : make_color_rgb(80, 30, 30));
        draw_rectangle(_px, _py - 16, _px + _pw, _py, false);
        draw_set_color(c_gray);
        draw_rectangle(_px, _py - 16, _px + _pw, _py, true);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_px + (_pw * 0.5), _py - 17, "CLOSE LIST");
        draw_set_halign(fa_left);
        if (_xhov && mouse_check_button_pressed(mb_left)) {
            label_picker_open = false;
            global.any_picker_open = false;
            depth = label_picker_prev_depth;
            label_picker_word_only = false;
            label_picker_byte_only = false;
        }

   // Sub-header (and Back button for HW items)
        draw_set_font(fnt_c64_tiny);
        if (label_picker_tab == "HW" && global.hw_picker_active_category != -1) {
            draw_set_color(c_aqua);
            draw_text(_px + 4, _py + _tab_h + 3, "< BACK TO GROUPS");
        } else {
            draw_set_color(make_color_rgb(120, 120, 180));
            var _uv_hdr = "UV VARS";
            if (label_picker_word_only) {
                _uv_hdr = "UV WORD VARS";
            }
            draw_text(_px + 4, _py + _tab_h + 3, label_picker_tab == "UV" ? _uv_hdr : "HW CATEGORIES");
        }

        // Rows
        for (var _li = 0; _li < _visible; _li++) {
            var _idx = _li + label_picker_scroll;
            if (_idx >= _count) break;
            var _ry   = _list_y + (_li * _row_h);
            var _rhov = point_in_rectangle(mouse_x, mouse_y, _px, _ry, _px + _pw, _ry + _row_h);
            draw_set_color(_rhov ? make_color_rgb(40, 80, 60) : make_color_rgb(25, 25, 38));
            draw_rectangle(_px, _ry, _px + _pw -2 , _ry + _row_h, false);
            draw_set_color(_rhov ? c_lime : c_yellow);
            draw_set_font(fnt_c64_tiny);
            draw_text(_px + 4, _ry + 2, _active_list[_idx]);
        }

        // Scroll arrows
        var _up_hov   = point_in_rectangle(mouse_x, mouse_y, _px + 4,        _arrow_y, _px + 20,        _arrow_y + 16);
        var _down_hov = point_in_rectangle(mouse_x, mouse_y, _px + _pw - 20, _arrow_y, _px + _pw - 4,   _arrow_y + 16);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(_up_hov   ? c_white : (label_picker_scroll > 0                   ? c_aqua : c_gray));
        draw_text(_px + 6,        _arrow_y + 2, "^");
        draw_set_color(_down_hov ? c_white : (_count > _visible + label_picker_scroll   ? c_aqua : c_gray));
        draw_text(_px + _pw - 16, _arrow_y + 2, "v");
        draw_set_color(make_color_rgb(60, 60, 80));
        draw_text(_px + 24, _arrow_y + 2, string(label_picker_scroll + 1) + "-" +
                  string(min(_count, label_picker_scroll + _visible)) + "/" + string(_count));

        if (label_picker_filter_char != "") {
            draw_set_font(fnt_c64_tiny);
            draw_set_halign(fa_center);
            draw_set_color(c_lime);
            draw_text(_px + (_pw * 0.5), _arrow_y + 20, "FILTERED: '" + label_picker_filter_char + "'");
            draw_set_color(make_color_rgb(140, 140, 140));
            draw_text(_px + (_pw * 0.5), _arrow_y + 32, "BACKSPACE TO CLEAR");
            draw_set_halign(fa_left);
        }

    } else {
        // JUMP/BRANCH PICKER
        var _px      = draw_x + width + 8;
        var _py      = y + 36;
        var _pw      = 140;
        var _row_h   = 16;
        var _visible = 24;
        var _arrow_y = _py + 18 + _row_h + (_visible * _row_h) + 2;


        // Background + border
        draw_set_color(make_color_rgb(20, 20, 30));
        draw_rectangle(_px, _py, _px + _pw, _arrow_y + 20, false);
        draw_set_color(c_gray);
        draw_rectangle(_px, _py, _px + _pw, _arrow_y + 20, true);


		// X close (Full width header)
        var _xhov = point_in_rectangle(mouse_x, mouse_y, _px, _py - 16, _px + _pw, _py);
        draw_set_color(_xhov ? c_red : make_color_rgb(80, 30, 30));
        draw_rectangle(_px, _py - 16, _px + _pw, _py, false);
        draw_set_color(c_gray);
        draw_rectangle(_px, _py - 16, _px + _pw, _py, true);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(_px + (_pw * 0.5), _py - 17, "CLOSE LIST");
        draw_set_halign(fa_left);
        if (_xhov && mouse_check_button_pressed(mb_left)) {
            label_picker_open = false;
            global.any_picker_open = false;
            depth = label_picker_prev_depth;
            
        }
       if (_xhov && mouse_check_button_pressed(mb_left)) {label_picker_open = false;global.any_picker_open = false;depth = label_picker_prev_depth;}

        // Row 1: group tabs — LABELS always, KERNAL only for jsr operands
        var _grp_labels_hov = point_in_rectangle(mouse_x, mouse_y, _px, _py + 2, _px + 68, _py + 19);
        draw_set_color(label_picker_group == "LABELS" ? make_color_rgb(40, 80, 120) : make_color_rgb(18, 18, 28));
        draw_rectangle(_px + 2, _py + 2, _px + 68, _py + 19, false);
        draw_set_color(label_picker_group == "LABELS" ? c_white : c_gray);
        draw_set_font(fnt_c64_tiny);
        draw_text(_px + 6, _py + 3, "LABELS");
        if (_grp_labels_hov && mouse_check_button_pressed(mb_left)) {
            label_picker_group  = "LABELS";
            label_picker_scroll = 0;
        }
        if (label_picker_is_jsr) {
            var _grp_krn_hov = point_in_rectangle(mouse_x, mouse_y, _px + 74, _py + 2, _px + 141, _py + 19);
            draw_set_color(label_picker_group == "KERNAL" ? make_color_rgb(80, 40, 100) : make_color_rgb(18, 18, 28));
            draw_rectangle(_px + 74, _py + 2, _px + 141, _py + 19, false);
            draw_set_color(label_picker_group == "KERNAL" ? c_white : c_gray);
            draw_text(_px + 78, _py + 3, "KERNAL");
            if (_grp_krn_hov && mouse_check_button_pressed(mb_left)) {
                label_picker_group  = "KERNAL";
                label_picker_scroll = 0;
            }
        }
        // Row 2: INC CODE toggle on its own line (LABELS group only)
        var _list_y = _py + 18 + _row_h;
        var _tbx1 = _px + 4;
        var _tbx2 = _tbx1 + 82;
        var _tby1 = _py + 18;
        var _tby2 = _py + 18 + _row_h;
        var _tbhov = (label_picker_group == "LABELS") && point_in_rectangle(mouse_x, mouse_y, _tbx1, _tby1, _tbx2, _tby2);
        if (label_picker_group == "LABELS") {
            draw_set_color(label_picker_inc_code ? make_color_rgb(30, 80, 30) : make_color_rgb(40, 30, 50));
            draw_rectangle(_tbx1, _tby1, _tbx2, _tby2, false);
            draw_set_color(_tbhov ? c_white : (label_picker_inc_code ? c_lime : c_gray));
            draw_set_font(fnt_c64_tiny);
            draw_text(_tbx1 + 12, _tby1 + 1, "INC CODE");
        }
        if (_tbhov && mouse_check_button_pressed(mb_left)) {
            label_picker_inc_code = !label_picker_inc_code;
            label_picker_list = ["[clear]"];
            with (obj_c64_node) {
                if (node_type == "LABEL") {
                    array_push(other.label_picker_list, string(instructions[0][1]));
                }
                if (node_type == "MACRO_ANIM") {
                    if (anim_alias == "") anim_alias = "anim" + string(real(id)); 
					array_push(other.label_picker_list, anim_alias + "_sub");
					array_push(other.label_picker_list, anim_alias + "_reset");
                }
                if (node_type == "MACRO_SCROLL") {
                    array_push(other.label_picker_list, "Scroller_L");
                    array_push(other.label_picker_list, "Scroller_R");
                }
                if (node_type == "MACRO_SID_SONG") {
                    array_push(other.label_picker_list, "sng" + string(stable_uid) + "_play");
                    array_push(other.label_picker_list, "sng" + string(stable_uid) + "_init");
                    array_push(other.label_picker_list, "sng" + string(stable_uid) + "_seek");
                }
                if (node_type == "MACRO_VSCROLL") {
                    array_push(other.label_picker_list, "Scroller_U");
                    array_push(other.label_picker_list, "Scroller_D");
                }
                if (node_type == "MACRO_TEXT_SCROLL") {
                    var _jsr_m = (array_length(instructions[0]) > 11 && is_real(instructions[0][11])) ? real(instructions[0][11]) : 0;
                    if (_jsr_m == 1) {
                        var _ts_alias = (array_length(instructions[0]) > 12 && is_string(instructions[0][12]) && string(instructions[0][12]) != "") ? string(instructions[0][12]) : ("ts" + string(real(id)));
                        array_push(other.label_picker_list, _ts_alias + "_scrl");
                    }
                }
                if (node_type == "MACRO_CODE" && other.label_picker_inc_code) {
                    var _code_txt = string(instructions[0][1]);
                    if (_code_txt != "") {
                        var _code_lines = string_split(_code_txt, "\n");
                        for (var _cli = 0; _cli < array_length(_code_lines); _cli++) {
                            var _cl = string_trim(_code_lines[_cli]);
                            var _colon_pos = string_pos(":", _cl);
                            if (_colon_pos > 1) {
                                var _lbl = string_trim(string_copy(_cl, 1, _colon_pos - 1));
                                if (_lbl != "" && string_pos(" ", _lbl) == 0 && string_char_at(_lbl, 1) != "." && string_char_at(_lbl, 1) != "_") {
                                    array_push(other.label_picker_list, _lbl);
                                }
                            }
                        }
                    }
                }
            }
            label_picker_scroll = 0;
        }
        // Build the active row source from the current group (filtered by first-letter keypress)
        var _rows_src = [];
        if (label_picker_group == "KERNAL") {
            var _krn = scr_kernal_routine_list();
            for (var _ki = 0; _ki < array_length(_krn); _ki++) {
                if (label_picker_filter_char != "" && _krn[_ki].name != "[clear]" &&
                    string_upper(string_char_at(_krn[_ki].name, 1)) != label_picker_filter_char) continue;
                array_push(_rows_src, _krn[_ki].name);
            }
        } else {
            for (var _li2 = 0; _li2 < array_length(label_picker_list); _li2++) {
                var _lp_name = label_picker_list[_li2];
                if (label_picker_filter_char != "" && _lp_name != "[clear]") {
                    var _fc_name3 = _lp_name;
                    if (string_pos("UV_", _fc_name3) == 1) _fc_name3 = string_delete(_fc_name3, 1, 3);
                    if (string_upper(string_char_at(_fc_name3, 1)) != label_picker_filter_char) continue;
                }
                array_push(_rows_src, _lp_name);
            }
        }
        var _count = array_length(_rows_src);

        // Rows
        for (var _li = 0; _li < _visible; _li++) {
            var _idx = _li + label_picker_scroll;
            if (_idx >= _count) break;
            var _ry   = _list_y + (_li * _row_h);
            var _row_txt = _rows_src[_idx];
            var _rhov = point_in_rectangle(mouse_x, mouse_y, _px, _ry, _px + _pw, _ry + _row_h);
            draw_set_color(_rhov ? make_color_rgb(40, 80, 60) : make_color_rgb(25, 25, 38));
            draw_rectangle(_px+1, _ry, _px + _pw-1, _ry + _row_h, false);
            draw_set_color(_rhov ? c_lime : (label_picker_group == "KERNAL" ? make_color_rgb(200, 160, 255) : c_yellow));
            draw_set_font(fnt_c64_tiny);
            draw_text(_px + 4, _ry + 2, _row_txt);
        }

        // Scroll arrows
        var _up_hov   = point_in_rectangle(mouse_x, mouse_y, _px + 4,        _arrow_y, _px + 20,        _arrow_y + 16);
        var _down_hov = point_in_rectangle(mouse_x, mouse_y, _px + _pw - 20, _arrow_y, _px + _pw - 4,   _arrow_y + 16);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(_up_hov   ? c_white : (label_picker_scroll > 0                 ? c_aqua : c_gray));
        draw_text(_px + 6,        _arrow_y + 2, "^");
        draw_set_color(_down_hov ? c_white : (_count > _visible + label_picker_scroll ? c_aqua : c_gray));
        draw_text(_px + _pw - 16, _arrow_y + 2, "v");
        draw_set_color(make_color_rgb(60, 60, 80));
        draw_text(_px + 24, _arrow_y + 2, string(label_picker_scroll + 1) + "-" +
                  string(min(_count, label_picker_scroll + _visible)) + "/" + string(_count));

        if (label_picker_filter_char != "") {
            draw_set_font(fnt_c64_tiny);
            draw_set_halign(fa_center);
            draw_set_color(c_lime);
            draw_text(_px + (_pw * 0.5), _arrow_y + 20, "FILTERED: '" + label_picker_filter_char + "'");
            draw_set_color(make_color_rgb(140, 140, 140));
            draw_text(_px + (_pw * 0.5), _arrow_y + 32, "BACKSPACE TO CLEAR");
            draw_set_halign(fa_left);
        }
    }
}
// =============================================================
// G. ADDRESS GUTTER
// =============================================================
draw_set_font(fnt_c64_code);
draw_set_halign(fa_right);

// Detect dangerous ORG with attached children — fires when ORG resolves
// to $0000 (zero page = unexecutable) OR when proxy failed to sense ($----).
// Children counted by org_parent only, regardless of is_connected flag.
var _org_at_zero_with_kids = false;
var _org_is_unsensed = false;
if (node_type == "ORG" && node_title != "VARIABLES" && node_title != "HW REGISTERS") {
    var _danger_addr = (pc_address == 0 || pc_address == -1);
    if (_danger_addr) {
        var _org_ref_zero = id;
        with (obj_c64_node) {
            if (org_parent == _org_ref_zero) {
                other._org_at_zero_with_kids = true;
                break;
            }
        }
        _org_is_unsensed = (pc_address == -1 || display_address == "$----");
    }
}
// Unified Address Gutter: Allow children of ORG blocks to show addresses
var _is_data = (string_pos("DATA", node_type) > 0 || node_type == "SPR64" || node_type == "BITMAP_KLA");
var _show_gutter = (node_type == "INIT" || node_type == "ORG") ? _lod_addresses : (_lod_full && _near_centre);
if (_show_gutter && node_type != "EXECUTE" && node_type != "COMMENT" && 
    node_type != "NAMED_LOC" && node_type != "NEW_STR" && node_title != "VARIABLES" && 
    x > 160 && proxy) {
    var _is_data = (string_pos("DATA", node_type) > 0 || node_type == "SPR64" || node_type == "BITMAP_KLA");
    
    // --- SYNCED CONFLICT COLOR ---
    var _use_col = (is_connected || _is_data || node_type == "ORG") ? c_aqua : c_gray;

    if (variable_instance_exists(id, "is_conflicted") && is_conflicted) {
        _use_col = c_red; // Flash removed, now solid red
    }

    // $0000 danger flash — ORG at zero with children, or proxy ORG that failed to sense
    if (_org_at_zero_with_kids) {
        var _zero_pulse = abs(sin(current_time * 0.006));
        _use_col = merge_colour(c_red, c_yellow, _zero_pulse);
    }

    draw_set_color(_use_col);

var _addr_str = "";
    if (is_connected || _is_data || node_type == "ORG") {
        if (node_type == "ORG" && proxy && display_address == "$????") {
            _addr_str = "$????";
        } else if (global.use_hex_display) {
            var _hex_raw = decimal_to_hex(pc_address);
            while (string_length(_hex_raw) < 4) _hex_raw = "0" + _hex_raw;
            _addr_str = "$" + string_upper(_hex_raw);
        } else {
            _addr_str = string(pc_address);
        }
    } else {
        _addr_str = "-";
    }

    var _actual_size = 0;
    if (node_type == "DATA_TEXT") {
        for (var _j = 0; _j < array_length(instructions); _j++)
            _actual_size += string_length(string(instructions[_j][1]));
    } else {
        _actual_size = total_node_size;
    }

    if (_is_data && _actual_size > 0) {
        var _end_addr = pc_address + _actual_size;
        var _end_str  = global.use_hex_display ? ("$" + string_upper(decimal_to_hex(_end_addr))) : string(_end_addr);
        if (global.use_hex_display) while (string_length(_end_str) < 5) _end_str = string_insert("0", _end_str, 2);
        draw_text(x - 12, y + 4, _addr_str);
        draw_set_color(c_green);
  

} else if (node_type == "INIT") {
        var _chain_end = pc_address + total_node_size;
        with (obj_c64_node) {
            if (is_connected && org_parent == noone && node_type != "ORG" && node_type != "INIT") {
                var _node_end = pc_address + total_node_size;
                if (_node_end > _chain_end) _chain_end = _node_end;
            }
        }
		
        var _init_end_str = global.use_hex_display ? ("$" + string_upper(decimal_to_hex(_chain_end))) : string(_chain_end); // keep and move down
        while (string_length(_init_end_str) < 5) _init_end_str = string_insert("0", _init_end_str, 2);
        draw_text(x - 12, y + 4, _addr_str);
		draw_set_font(fnt_c64_code);
        draw_set_color(c_orange);
        draw_text(x - 8, y + height-20, "> " + _init_end_str);
		

    } else if (node_type == "ORG" && end_address > pc_address && !proxy) {
        var _org_end_str = global.use_hex_display ? ("$" + string_upper(decimal_to_hex(end_address))) : string(end_address);
        while (string_length(_org_end_str) < 5) _org_end_str = string_insert("0", _org_end_str, 2);
        draw_text(x - 12, y + 4, _addr_str);
		draw_set_font(fnt_c64_code);
        draw_set_color(c_orange);
        draw_text(x - 8, y + 20, "> " + _org_end_str);

   } else {
        draw_text(x - 12, y + 4, _addr_str); // common instruction address label in gutter
    }

}
draw_set_halign(fa_left);

// =============================================================
// H. MAIN BOX & HEADER COLOUR
// =============================================================
var _body_col = is_connected ? make_color_rgb(30, 30, 45) : make_color_rgb(20, 20, 20);
switch (node_type) {
    case "COMMENT": _body_col = make_color_rgb(40, 40, 30); break;
    case "ORG":     _body_col = make_color_rgb(30, 20, 35); break;
    case "SPR64":   _body_col = make_color_rgb(25, 20, 15); break;
}
draw_set_color(_body_col);
// Calculate a slightly darker color for the bottom of the gradient
// make_color_rgb(r, g, b) math can be done directly or via a helper
var _dark_col = make_color_rgb(
    max(0, color_get_red(_body_col) + 20), 
    max(0, color_get_green(_body_col) + 20), 
    max(0, color_get_blue(_body_col) + 45)
);

var _label_edge_col = make_color_rgb(90,86,60)

// Draw the subtle gradient (Top colors = base, Bottom colors = darker)

var _box_alpha = clamp(1.0 - (_cam_zoom - 2.5) / 0.75, 0, 1);
_box_alpha *= global.idle_fade;
if (_box_alpha < 0.1) { x -= x_indent; draw_set_alpha(1.0); exit; }

if obj_workspace_manager.niceSliceFrm==0
	{
	draw_set_alpha(_box_alpha);
	if node_type!="LABEL" {draw_rectangle_color(draw_x, y, draw_x + width, y + height, 
	 _body_col, _body_col, _dark_col, _dark_col, false);}
	else{
		 draw_rectangle_color(draw_x, y, draw_x + width, y + height, 
	    _body_col, _label_edge_col, _label_edge_col, _dark_col, false);}
	
	}
	else
	{
	draw_sprite_stretched_ext(spr_9s_tile1, obj_workspace_manager.niceSliceFrm, draw_x, y, width, height, _body_col, _box_alpha);
	}


var _first_inst = (array_length(instructions) > 0) ? string_lower(instructions[0][0]) : "";
var _is_branch  = (string_char_at(_first_inst, 1) == "b" && string_length(_first_inst) == 3);
var _is_jump    = (_first_inst == "jmp" || _first_inst == "jsr" || _first_inst == "jmp_abs" || _first_inst == "jmp_ind");

var _head_col = is_connected ? make_color_rgb(64, 80, 192) : make_color_rgb(32, 40, 96);
var _text_col = c_white;

switch (node_type) {
    case "ORG":
        if (node_title == "VARIABLES")    _head_col = make_color_rgb(60, 140, 200);  // sky blue
        else if (node_title == "HW REGISTERS") _head_col = make_color_rgb(70, 100, 105); // teal-grey
        else                              _head_col = c_purple;
        break;
    case "LABEL":
        if (array_length(instructions) > 0 && array_length(instructions[0]) > 1 && string(instructions[0][1]) == "sid_exit") {
            _head_col = make_color_rgb(220, 0, 180); 
        } else {
            _head_col =  make_color_rgb(210, 200, 0);
        }
        break;
    case "EXECUTE":     _head_col = make_color_rgb(180, 40,  40); break;
    case "INIT":        _head_col = make_color_rgb( 40,180,  40); break;
    case "RAW_DATA":    _head_col = make_color_rgb( 40,160, 200); break;
    case "SPR64":       _head_col = make_color_rgb(200,120,  40); break;
    case "DATA_SID":    _head_col = make_color_rgb(230,110,  30); break;
    case "COMMENT":     _head_col = make_color_rgb(150,150, 150); break;
    case "MACRO_SID":
    case "MACRO_SPR":
    case "MACRO_TRACK":
    case "MACRO_PRINT":
	case "MACRO_PRINT_EXT":
    case "MACRO_JOY":
    case "MACRO_BMP":   _head_col = is_connected ? make_color_rgb(180, 60, 180) : make_color_rgb( 90, 30,  90); break;
    case "MACRO_VECTOR_BMP": _head_col = is_connected ? make_color_rgb(120, 200, 220) : make_color_rgb(50, 90, 100); break;
    case "MACRO_PLACE_CHAR": _head_col = is_connected ? make_color_rgb(200, 140, 80) : make_color_rgb(100, 70, 40); break;
    case "MACRO_CLR_SCREEN": _head_col = is_connected ? make_color_rgb(90, 150, 200) : make_color_rgb(45, 75, 100); break;
    case "MACRO_MATH":       _head_col = is_connected ? make_color_rgb(60, 170, 140) : make_color_rgb(30, 85, 70); break;
    case "MACRO_CLEAR_BMP_RECT": _head_col = is_connected ? make_color_rgb(200, 70, 90) : make_color_rgb(100, 35, 45); break;
    case "MACRO_RANDOM":     _head_col = is_connected ? make_color_rgb(150, 90, 200) : make_color_rgb(70, 45, 95); break;
	case "MACRO_SID_SOUND":  _head_col = is_connected ? make_color_rgb(200, 80, 170) : make_color_rgb(95, 40, 80); break;
	case "MACRO_SID_SONG":   _head_col = is_connected ? make_color_rgb(230, 60, 140) : make_color_rgb(110, 30, 65); break;
	case "MACRO_GET_CHAR":   _head_col = is_connected ? make_color_rgb(80, 160, 200) : make_color_rgb(40, 80, 100); break;
	case "MACRO_VECTOR_PAGE": _head_col = is_connected ? make_color_rgb(90, 180, 210) : make_color_rgb(40, 80, 95); break;
    case "MACRO_LOADER": _head_col = is_connected ? make_color_rgb(200, 160, 40) : make_color_rgb(100, 80, 20); break;
    case "MACRO_CHR":   _head_col = is_connected ? make_color_rgb(100,200, 255) : make_color_rgb( 30, 80, 120); break;
    case "MACRO_VWAIT":         _head_col = is_connected ? make_color_rgb( 40,180, 160) : make_color_rgb( 20, 90,  80); break;
    case "MACRO_DISPLAY":       _head_col = is_connected ? make_color_rgb(220,170,  50) : make_color_rgb(110, 85,  25); break;
    case "MACRO_WAIT":          _head_col = is_connected ? make_color_rgb( 60,190, 210) : make_color_rgb( 30, 95, 105); break;
    case "MACRO_IRQ_HANDLER":   _head_col = is_connected ? make_color_rgb(220, 80,  40) : make_color_rgb(110, 40,  20); break;
    case "MACRO_COLLISION":   _head_col = is_connected ? make_color_rgb(180, 60,  60) : make_color_rgb( 90, 30,  30); break;
	case "MACRO_COLL_ADV":    _head_col = is_connected ? make_color_rgb(220, 100, 40) : make_color_rgb(110, 50, 20); break;
    case "MACRO_ANIM":        _head_col = is_connected ? make_color_rgb( 60,180,  60) : make_color_rgb( 30, 90,  30); break;
    case "MACRO_SFX":         _head_col = is_connected ? make_color_rgb(255,160,  40) : make_color_rgb(120, 70,  10); break;
	case "MACRO_CODE":        _head_col = is_connected ? make_color_rgb( 50,140, 100) : make_color_rgb( 25, 70,  50); break;
	case "COND_IF":     _head_col = is_connected ? make_color_rgb(180, 120,  40) : make_color_rgb( 90, 60,  20);  break;
	case "COND_IF_WORD": _head_col = is_connected ? make_color_rgb(180,  90,  40) : make_color_rgb( 90, 45,  20);  break;
	case "BANK_SWITCH": _head_col = is_connected ? make_color_rgb(120, 80, 200) : make_color_rgb( 60, 40, 100);  break;
	case "GET_VAR":     _head_col = is_connected ? make_color_rgb( 40,120,  80) : make_color_rgb( 20, 60,  40); break;
    case "SET_VAR":     _head_col = is_connected ? make_color_rgb(140, 60,  40) : make_color_rgb( 70, 30,  20); break;
    case "INC_VAR":     _head_col = is_connected ? make_color_rgb( 30,100,  50) : make_color_rgb( 15, 50,  25); break;
    case "DEC_VAR":     _head_col = is_connected ? make_color_rgb(100, 30,  30) : make_color_rgb( 50, 15,  15); break;
    case "COPY_VAR":    _head_col = is_connected ? make_color_rgb(140, 100, 40) : make_color_rgb( 70, 50,  20); break;
    case "NAMED_LOC":
        _head_col = (array_length(instructions) > 0 && string_pos("HW_", string(instructions[0][1])) == 1)
                  ? make_color_rgb(60, 90, 95)    // teal-grey for HW
                  : make_color_rgb(30, 120, 180);   // pastel lime for UV
        
        break;
	case "MACRO_MAP":        _head_col = is_connected ? make_color_rgb(40, 180, 100) : make_color_rgb(20,  90, 50); break;
	case "MACRO_MAP_SWITCH": _head_col = is_connected ? make_color_rgb(40, 160, 180) : make_color_rgb(20,  80, 90); break;
	case "MACRO_VSCROLL": _head_col = is_connected ? make_color_rgb(40, 140, 200) : make_color_rgb(20, 70, 100); break;
    case "MACRO_SCROLL": _head_col = is_connected ? make_color_rgb(40, 180, 100) : make_color_rgb( 20, 90,  50); break;
	case "NEW_STR":     _head_col = make_color_rgb(30, 120, 180);  break;
    default:
        if (_is_jump || _is_branch) { 
            // Specific overrides for JMP and JSR
            if (_first_inst == "jmp" || _first_inst == "jmp_abs" || _first_inst == "jmp_ind") {
                _head_col = make_color_rgb(220, 80, 60); // Reddish
            } else if (_first_inst == "jsr") {
                _head_col = make_color_rgb(220, 140, 60); // Yellowish
            } else {
                _head_col = c_orange; // Default for branches
            }
        }
        else if (string_pos("DATA", node_type) > 0) {
            _head_col = is_connected ? make_color_rgb(120, 50, 150) : make_color_rgb(60, 40, 70);
        }
        break;
}

if obj_workspace_manager.niceSliceFrm==0
	{
	draw_set_color(_head_col);
	draw_set_alpha(_box_alpha);
	draw_rectangle(draw_x, y, draw_x + width, y + header_h, false);
	draw_set_alpha(1.0);
	}
	else
	{
	draw_sprite_stretched_ext(spr_9s_tile1, obj_workspace_manager.niceSliceFrm, draw_x, y, width, header_h, _head_col, _box_alpha);
	}

// =============================================================
// H2. WIRE DOTS (ORG nodes only)
// =============================================================
if (node_type == "ORG" && node_title != "VARIABLES" && node_title != "HW REGISTERS" && global.idle_fade > 0.1) {
    var _dot_r    = 5;
    var _dot_in_x  = draw_x;
    var _dot_out_x = draw_x + width;
    var _dot_y     = y + (header_h * 0.5);

    // Input dot (left side) — receives wire_in_source
    var _in_wired  = (wire_in_source != -1);
    var _in_hov    = point_in_circle(mouse_x, mouse_y, _dot_in_x, _dot_y, _dot_r + 4);
    var _in_col    = _in_wired  ? make_color_rgb(255, 140, 0) : (_in_hov ? c_white : make_color_rgb(100, 100, 100));
    draw_set_color(_in_col);
    draw_circle(_dot_in_x, _dot_y, _dot_r, false);
    draw_set_color(c_black);
    draw_circle(_dot_in_x, _dot_y, _dot_r, true);

    // Output dot (right side) — sends wire_out_target
    var _out_wired = (wire_out_target != -1);
    var _out_hov   = point_in_circle(mouse_x, mouse_y, _dot_out_x, _dot_y, _dot_r + 4);
    var _out_col   = _out_wired ? make_color_rgb(255, 140, 0) : (_out_hov ? c_white : make_color_rgb(100, 100, 100));
    draw_set_color(_out_col);
    draw_circle(_dot_out_x, _dot_y, _dot_r, false);
    draw_set_color(c_black);
    draw_circle(_dot_out_x, _dot_y, _dot_r, true);

    // Draw wire curve if wired out
    if (_out_wired) {
        var _target_inst = noone;
        with (obj_c64_node) {
            if (node_type == "ORG" && org_uid == other.wire_out_target) {
                _target_inst = id;
                break;
            }
        }
        if (instance_exists(_target_inst)) {
            var _tx = _target_inst.x + _target_inst.x_indent;
            var _ty = _target_inst.y + (header_h * 0.5);
            var _cx1 = _dot_out_x + 60;
            var _cx2 = _tx - 60;
			
			
            // Base wire — thick cyan or red in demo mode
            var _wire_col  = global.lite ? make_color_rgb(255, 40, 40)  : make_color_rgb(40, 200, 255);
            var _pulse_col = global.lite ? make_color_rgb(255, 180, 180) : make_color_rgb(180, 240, 255);
            var _glow_col  = global.lite ? make_color_rgb(255, 60, 40)   : make_color_rgb(40, 160, 255);
            draw_set_color(_wire_col);
            draw_set_alpha(0.85 * global.idle_fade);
            var _steps = 40;
            var _bx = _dot_out_x;
            var _by = _dot_y;
            for (var _si = 1; _si <= _steps; _si++) {
                var _t  = _si / _steps;
                var _t2 = _t * _t;
                var _t3 = _t2 * _t;
                var _mt  = 1 - _t;
                var _mt2 = _mt * _mt;
                var _mt3 = _mt2 * _mt;
                var _nx = _mt3 * _dot_out_x + 3 * _mt2 * _t * _cx1 + 3 * _mt * _t2 * _cx2 + _t3 * _tx;
                var _ny = _mt3 * _dot_y     + 3 * _mt2 * _t * _dot_y + 3 * _mt * _t2 * _ty  + _t3 * _ty;
                draw_line_width(_bx, _by, _nx, _ny, 3);
                _bx = _nx;
                _by = _ny;
            }

            // Pulse tracer — circle count based on wire length
            // Suppressed while idle so the animation stops the instant sleep starts
            if (!global.idle_active) {
            var _pulse_speed  = 0.0008;
            var _wire_dist    = point_distance(_dot_out_x, _dot_y, _tx, _ty);
            var _pulse_count  = clamp(floor(_wire_dist / 40), 2, 20);
            var _pulse_offset = (current_time * _pulse_speed) mod 1.0;
            for (var _pi = 0; _pi < _pulse_count; _pi++) {
                var _t = ((_pi / _pulse_count) + _pulse_offset) mod 1.0;
                var _t2 = _t * _t;
                var _t3 = _t2 * _t;
                var _mt  = 1 - _t;
                var _mt2 = _mt * _mt;
                var _mt3 = _mt2 * _mt;
                var _cx = _mt3 * _dot_out_x + 3 * _mt2 * _t * _cx1 + 3 * _mt * _t2 * _cx2 + _t3 * _tx;
                var _cy = _mt3 * _dot_y     + 3 * _mt2 * _t * _dot_y + 3 * _mt * _t2 * _ty  + _t3 * _ty;
                // Bright core
                draw_set_color(_pulse_col);
                draw_set_alpha(0.95);
                draw_circle(_cx, _cy, 3, false);
                // Soft glow ring
                draw_set_color(_glow_col);
                draw_set_alpha(0.3);
                draw_circle(_cx, _cy, 6, false);;
            }
            draw_set_alpha(1.0);
            } // end idle pulse gate
			
			
        }
    }

    // Draw live drag wire if dragging from this node
    if (global.wire_drag_node == id) {
        var _start_x = global.wire_drag_is_out ? _dot_out_x : _dot_in_x;
        var _start_y = _dot_y;
        draw_set_color(make_color_rgb(255, 180, 0));
        draw_set_alpha(0.7);
        draw_line(_start_x, _start_y, mouse_x, mouse_y);
        draw_set_alpha(1.0);
    }
}
// =============================================================
// I. HEADER TITLE & STATS
// =============================================================
draw_set_font(fnt_c64_code);
draw_set_color(_text_col);
if (_lod_header) {
    // Determine if this is a plain opcode node (default draw path)
    var _is_opcode_node = (
        node_type != "ORG"        && node_type != "LABEL"     && node_type != "EXECUTE"  &&
        node_type != "INIT"       && node_type != "COMMENT"   && node_type != "RAW_DATA" &&
        node_type != "DATA_TEXT"  && node_type != "DATA_SID"  && node_type != "SPR64"    &&
        node_type != "BITMAP_KLA" && node_type != "NAMED_LOC" && node_type != "NEW_STR"  &&
        node_type != "GET_VAR"    && node_type != "SET_VAR"   && node_type != "INC_VAR"  &&
        node_type != "DEC_VAR"    && node_type != "COPY_VAR"  &&
        node_type != "BANK_SWITCH" &&
        string_pos("MACRO", node_type) == 0 && string_pos("COND_", node_type) == 0
    );

    var _show_title = true;
    if (_is_opcode_node && !obj_workspace_manager.opcode_headers_on) {
        _show_title = false;
    }

    if (_show_title) {
        var _hdr_first = (array_length(instructions) > 0) ? string(instructions[0][0]) : "";
        var _hdr_sig   = string(custom_title) + "|" + string(node_title) + "|" + _hdr_first +
                         "|" + string(_is_opcode_node) + "|" + string(obj_workspace_manager.opcode_headers_on) +
                         "|" + string(width);

        if (draw_cache_dirty || hdr_cache_sig != _hdr_sig) {
            hdr_cache_sig = _hdr_sig;

            var _disp_title = (custom_title != "") ? custom_title : string(node_title);
            hdr_cache_opcode = false;

            if (_is_opcode_node && array_length(instructions) > 0 && obj_workspace_manager.opcode_headers_on) {
                var _op_key   = string_lower(instructions[0][0]);
                var _hex_byte = scr_opcode_hex(_op_key);
                _disp_title   = "Opcode: $" + string_upper(_hex_byte);
                hdr_cache_opcode = true;
                draw_set_font(fnt_C64_Angled_tiny);
            } else {
                draw_set_font(fnt_c64_code);
            }

            var _title_max_w = width - 16;
            if (string_width(_disp_title) > _title_max_w && string_length(_disp_title) > 1) {
                while (string_length(_disp_title) > 1 && string_width(_disp_title) > _title_max_w) {
                    _disp_title = string_copy(_disp_title, 1, string_length(_disp_title) - 1);
                }
            }
            hdr_cache_title = _disp_title;
        }

        if (hdr_cache_opcode) {
            draw_set_font(fnt_C64_Angled_tiny);
			
	        draw_set_color(_text_col);
	        draw_text(draw_x + 8, y+4 , hdr_cache_title);
	        
        } else {
            draw_set_font(fnt_c64_code);
			 draw_set_color(merge_colour(_head_col, c_black, 0.5));
		        draw_text(draw_x + 7, y + 3, hdr_cache_title);
		        draw_text(draw_x + 9, y + 3, hdr_cache_title);
		        draw_set_color(_text_col);
		        draw_text(draw_x + 8, y , hdr_cache_title);
		       
        }

        draw_set_font(fnt_c64_code);
    }
}


if (_lod_full && (is_connected || string_pos("DATA", node_type) > 0 || node_type == "ORG" || node_type == "SPR64")) {
    var _stats_x = draw_x + width - 60;

    if (node_type != "EXECUTE" && node_type != "ORG" && node_type != "COMMENT" &&
        node_type != "NAMED_LOC" && node_type != "NEW_STR" && node_type != "LABEL" && x > 160) {

        // --- rebuild cache on Shift press ---
        if (stats_cache_dirty) {
            stats_cache_dirty = false;

            var _size_to_draw = total_node_size;
            if (node_type == "MACRO_SPR"   && _size_to_draw == 0) _size_to_draw = 25;
            if (node_type == "MACRO_SID"   && _size_to_draw == 0) _size_to_draw = 78;
            if (node_type == "MACRO_CHR"   && _size_to_draw == 0) _size_to_draw = 15;
            if (node_type == "MACRO_VWAIT" && _size_to_draw == 0) _size_to_draw = 14;
            if (node_type == "MACRO_DISPLAY" && _size_to_draw == 0) _size_to_draw = 8;
            if (node_type == "MACRO_WAIT"    && _size_to_draw == 0) _size_to_draw = 24;
            if (node_type == "MACRO_BMP"   && _size_to_draw == 0) _size_to_draw = 163;
            stats_str_bytes = string(_size_to_draw) + " BYTES"; // BYTES INFO

            var _is_var_node = (node_type == "SET_VAR" || node_type == "GET_VAR" ||
                                node_type == "INC_VAR" || node_type == "DEC_VAR" ||
                                node_type == "COPY_VAR");
            var _cumul_cyc = round(cumulative_scanlines * 63);
    
			/*
			var _cumul_cyc_pal  = round(cumulative_scanlines * 63);
            var _cumul_cyc_ntsc = round(cumulative_scanlines * 65); // Real NTSC timing
            
            stats_str_cyc       = string(node_cycles) + " / " + string(_cumul_cyc_pal) + " CYC";
			stats_pal_line_cyc  = _cumul_cyc_pal mod 63;
            stats_ntsc_line_cyc = _cumul_cyc_ntsc mod 65;
			*/
			
			// Use the actual total cycle count if available, 
            // otherwise the drift remains invisible.
            // Calculate totals based on your existing scanline variable
            var _cumul_cyc_pal  = round(cumulative_scanlines * 63);
            var _cumul_cyc_ntsc = round(cumulative_scanlines * 65); 
            
            stats_str_cyc       = string(node_cycles) + " / " + string(_cumul_cyc_pal) + " CYC";
            stats_pal_line_cyc  = _cumul_cyc_pal  mod 63;
            stats_ntsc_line_cyc = _cumul_cyc_ntsc mod 65;
			
			
            stats_str_hint1 = "";
            stats_str_hint2 = "";
            stats_col_hint1 = c_white;
            stats_col_hint2 = c_white;

            if (_is_var_node) {
                var _pal_met  = (_cumul_cyc mod 63 == 0) && _cumul_cyc > 0;
                var _ntsc_met = (_cumul_cyc mod 65 == 0) && _cumul_cyc > 0;
                if (_pal_met)  { stats_str_hint1 = "PAL-MET";  stats_col_hint1 = make_color_rgb(180, 255, 240); }
                if (_ntsc_met) { stats_str_hint2 = "NTSC-MET"; stats_col_hint2 = make_color_rgb(220, 230, 180); }
                if (!_pal_met && !_ntsc_met && _cumul_cyc > 0) {
                    var _pal_rem  = _cumul_cyc mod 63;
                    var _pal_off  = (_pal_rem <= 31) ? _pal_rem : _pal_rem - 63;
                    var _ntsc_rem = _cumul_cyc mod 65;
                    var _ntsc_off = (_ntsc_rem <= 32) ? _ntsc_rem : _ntsc_rem - 65;
                    if (abs(_pal_off) <= 16) {
                        var _n = -_pal_off;
                        stats_str_hint1 = (_n >= 0 ? "+" : "") + string(_n) + " TO PAL";
                        stats_col_hint1 = make_color_rgb(40, 220, 180);
                    }
                    if (abs(_ntsc_off) <= 16) {
                        var _n = -_ntsc_off;
                        stats_str_hint2 = (_n >= 0 ? "+" : "") + string(_n) + " TO NTSC";
                        stats_col_hint2 = make_color_rgb(220, 180, 40);
                    }
                }
            } else {
                var _pal_frame  = 19656;
                var _ntsc_frame = 17095;
                var _pal_met  = (_cumul_cyc mod _pal_frame  == 0) && _cumul_cyc > 0;
                var _ntsc_met = (_cumul_cyc mod _ntsc_frame == 0) && _cumul_cyc > 0;
                if (_pal_met)  { stats_str_hint1 = "PAL-MET";  stats_col_hint1 = make_color_rgb(180, 255, 240); }
                if (_ntsc_met) { stats_str_hint2 = "NTSC-MET"; stats_col_hint2 = make_color_rgb(220, 230, 180); }
                if (!_pal_met && !_ntsc_met && _cumul_cyc > 0) {
                    var _pal_to  = _pal_frame  - (_cumul_cyc mod _pal_frame);
                    var _ntsc_to = _ntsc_frame - (_cumul_cyc mod _ntsc_frame);
                    if (_pal_to <= 500)  { stats_str_hint1 = "-" + string(_pal_to)  + " TO PAL";  stats_col_hint1 = make_color_rgb(40, 220, 180); }
                    if (_ntsc_to <= 500) { stats_str_hint2 = "-" + string(_ntsc_to) + " TO NTSC"; stats_col_hint2 = make_color_rgb(220, 180, 40); }
                }
            }
        }

        // --- draw from cache ---
        if (!global.any_picker_open) {
            draw_set_font(fnt_c64_pico);
            draw_set_color(c_black);
            draw_text(_stats_x, y + 4, stats_str_bytes);
			draw_set_color(c_white);
            draw_text(_stats_x+1, y + 3, stats_str_bytes);
            draw_set_font(fnt_c64_nano);
            draw_set_color(c_orange);
			// Display scanline cycle position (e.g., 23/63 for PAL)
            var _pal_part  = "PAL : " + string(stats_pal_line_cyc) + "/63  ";
            var _ntsc_part = "NTSC: " + string(stats_ntsc_line_cyc) + "/65  ";
			
			draw_set_halign(fa_center)
			
			
            draw_text(draw_x+(width/2), y + 19, _pal_part + _ntsc_part + stats_str_cyc);
			draw_set_halign(fa_left)
            var _hy = y + 19;
            if (stats_str_hint1 != "") { draw_set_color(stats_col_hint1); draw_text(_stats_x+60, _hy, stats_str_hint1); _hy += 10; }
            if (stats_str_hint2 != "") { draw_set_color(stats_col_hint2); draw_text(_stats_x+60, _hy, stats_str_hint2); }
        }
    }
    draw_set_font(fnt_c64_code);
}

// =============================================================
// J. BODY CONTENT — dispatched to per-type scripts
// =============================================================
if (_lod_body) switch (node_type) {
   // case "BITMAP_KLA":  scr_node_draw_bitmap_kla(draw_x, y);                            break;
    case "DATA_SID":    scr_node_draw_data_sid(draw_x, y);                              break;
    case "MACRO_SID":    scr_node_draw_macro_sid(draw_x, y, _cam_x, _cam_y, _cam_zoom);    break;
    case "MACRO_LOADER": scr_node_draw_macro_loader(draw_x, y, _cam_x, _cam_y, _cam_zoom); break;
    case "MACRO_CHR":   scr_node_draw_macro_chr(draw_x, y, _cam_x, _cam_y, _cam_zoom);  break;
    case "MACRO_TRACK": scr_node_draw_macro_track(draw_x, y);                           break;
    case "MACRO_BMP":   scr_node_draw_macro_bmp(draw_x, y);                             break;
    case "MACRO_VECTOR_BMP": scr_node_draw_macro_vector_bmp(draw_x, y);                 break;
	case "MACRO_VECTOR_PAGE": scr_node_draw_macro_vector_page(draw_x, y);               break;
    case "MACRO_PRINT": scr_node_draw_macro_print(draw_x, y);                           break;
	case "MACRO_CLEAR_BMP_RECT": scr_node_draw_macro_clear_bmp_rect(draw_x, y);         break;
    case "MACRO_PRINT_EXT": scr_node_draw_macro_print_ext(draw_x, y);                   break;
    case "MACRO_PLACE_CHAR": scr_node_draw_macro_place_char(draw_x, y); break;
    case "MACRO_CLR_SCREEN": scr_node_draw_macro_clr_screen(draw_x, y); break;
    case "MACRO_MATH":       scr_node_draw_macro_math(draw_x, y); break;
    case "MACRO_RANDOM":     scr_node_draw_macro_random(draw_x, y);                     break;
	case "MACRO_SID_SOUND":  scr_node_draw_macro_sid_sound(draw_x, y);                  break;
	case "MACRO_SID_SONG":   scr_node_draw_macro_sid_song(draw_x, y);                   break;
	case "MACRO_GET_CHAR":   scr_node_draw_macro_get_char(draw_x, y);                   break;
    case "MACRO_JOY":   scr_node_draw_macro_joy(draw_x, y);                             break;
	case "MACRO_VIC":   scr_node_draw_macro_vic(draw_x);							    break;
    case "MACRO_VWAIT": scr_node_draw_macro_vwait(draw_x, y);                           break;
    case "MACRO_DISPLAY": scr_node_draw_macro_display(draw_x, y);                       break;
    case "MACRO_WAIT":    scr_node_draw_macro_wait(draw_x, y);                          break;
	case "GET_VAR":     scr_node_draw_get_var();										break;
    case "SET_VAR":     scr_node_draw_set_var();									    break;
    case "INC_VAR":     scr_node_draw_inc_var();										break;
    case "DEC_VAR":     scr_node_draw_dec_var();										break;
    case "COPY_VAR":    scr_node_draw_copy_var(draw_x);										break;
    case "NAMED_LOC":   scr_node_draw_named_loc();										break;
    case "MACRO_SPR":   scr_node_draw_macro_spr(draw_x, y, _cam_x, _cam_y, _cam_zoom);  break;
	case "MACRO_MAP":        scr_node_draw_macro_map(draw_x, y, _cam_x, _cam_y, _cam_zoom);        break;
	case "MACRO_METAMAP":    scr_node_draw_macro_metamap(draw_x, y, _cam_x, _cam_y, _cam_zoom);    break;
	case "MACRO_MAP_SWITCH": scr_node_draw_macro_map_switch(draw_x, y, _cam_x, _cam_y, _cam_zoom); break;
	case "NEW_STR":      scr_node_draw_new_str();										break;
	case "MACRO_MOVE":    scr_node_draw_macro_move(draw_x);    break;
	case "MACRO_SEEK":    scr_node_draw_macro_seek(draw_x);    break;
	case "MACRO_MOVE_MEM": scr_node_draw_macro_move_mem(draw_x, y); break;
	case "MACRO_MOVE_BMP_BLOCK": scr_node_draw_macro_move_bmp_block(draw_x, y); break;
	case "MACRO_FLIP_X":  scr_node_draw_macro_flip_x(draw_x);  break;
	case "MACRO_PRIORITY":    scr_node_draw_macro_priority(draw_x);    break;
	case "MACRO_SPR_ENABLE":  scr_node_draw_macro_spr_enable(draw_x);  break;
	case "MACRO_SPR_EXPAND":  scr_node_draw_macro_spr_expand(draw_x);  break;
	case "MACRO_VSCROLL":  scr_node_draw_macro_vscroll(draw_x, y, _cam_x, _cam_y, _cam_zoom); break;
	case "MACRO_SCROLL": scr_node_draw_macro_scroll(draw_x, y, _cam_x, _cam_y, _cam_zoom); break;
	case "MACRO_IRQ":         scr_node_draw_macro_irq(draw_x, y, _cam_x, _cam_y, _cam_zoom);         break;
	case "MACRO_IRQ_HANDLER": scr_node_draw_macro_irq_handler(draw_x, y, _cam_x, _cam_y, _cam_zoom); break;
	case "MACRO_TEXT_SCROLL": scr_node_draw_macro_text_scroll(draw_x, y, _cam_x, _cam_y, _cam_zoom); break;
	case "COND_IF":           scr_node_draw_cond_if(draw_x, y);    break;
	case "COND_IF_WORD":      scr_node_draw_cond_if_word(draw_x, y); break;
	case "BANK_SWITCH":       scr_node_draw_bank_switch(draw_x, y); break;
	case "MACRO_COLLISION":   scr_node_draw_macro_collision(draw_x); break;
	case "MACRO_COLL_ADV":    scr_node_draw_macro_coll_adv(draw_x);  break;
	case "MACRO_ANIM":        scr_node_draw_macro_anim(draw_x);      break;
	case "MACRO_SFX":         scr_node_draw_macro_sfx(draw_x);       break;
	case "MACRO_CODE":        scr_node_draw_macro_code(draw_x, y);   break;   
    case "ORG": {
        var _org_hex = decimal_to_hex(pc_address);
        while (string_length(_org_hex) < 4) _org_hex = "0" + _org_hex;
        var _chk_x = draw_x + 10;

		//var _chk_y = y + header_h + 24;
		 var _chk_y   = y + 60;
		 
        draw_set_font(fnt_c64_code);
			// Never draw Proxy checkbox or text for VARIABLES or HW REGISTERS
			if (node_title != "HW REGISTERS" && node_title != "VARIABLES") {
			    draw_set_color(proxy ? c_lime : make_color_rgb(60, 60, 60));
			    draw_rectangle(_chk_x, _chk_y  , _chk_x + 12, _chk_y + 12 , false);
			    draw_set_color(c_dkgray);
			    draw_rectangle(_chk_x, _chk_y, _chk_x + 12, _chk_y + 12, true);
			    draw_set_font(fnt_c64_tiny);
			    draw_set_color(proxy ? c_lime : c_dkgray);
			    draw_text(_chk_x + 16, _chk_y -3 , "PROXY");
			    draw_set_font(fnt_c64_code);
			}

				
				
				if (node_title != "HW REGISTERS") {
				    draw_set_color(make_color_rgb(180, 100, 220));
				    draw_text(draw_x + 10, y + header_h + 10, "START ADDR:");
    
				    // Variables always show Aqua (Normal) because they shouldn't proxy
				    var _addr_color = (node_title == "VARIABLES") ? c_aqua : (proxy ? c_lime : c_aqua);

				    // $0000 danger override — flash red/yellow if ORG at zero has children
				    if (_org_at_zero_with_kids) {
				        var _zero_pulse_body = abs(sin(current_time * 0.006));
				        _addr_color = merge_colour(c_red, c_yellow, _zero_pulse_body);
				    }
				    draw_set_color(_addr_color);
    
				    draw_set_halign(fa_right);
				    var _org_addr_str = global.use_hex_display ? ("$" + string_upper(_org_hex)) : string(pc_address);
				    draw_text(draw_x + width - 8, y + header_h + 10, _org_addr_str);

				    // Warning glyph + text next to address when in danger state
				    if (_org_at_zero_with_kids) {
				        draw_set_halign(fa_left);
				        draw_set_font(fnt_c64_tiny);
				        draw_set_color(merge_colour(c_red, c_yellow, abs(sin(current_time * 0.006))));
				        draw_text(draw_x + 10, y + header_h + 26, "!! NOT SENSING - WILL CRASH !!");
				        draw_set_font(fnt_c64_code);
				    }
				    draw_set_halign(fa_left);


			        } else {
			            draw_set_color(make_color_rgb(180, 100, 220));
			            draw_text(draw_x + 10, y + header_h + 20, "HARDWIRED:");
			            draw_set_color(make_color_rgb(120, 180, 140));
			            draw_set_halign(fa_right);
			            draw_text(draw_x + width - 8, y + header_h + 20, "VIC/SID/CIA");
			            draw_set_halign(fa_left);
			        }

        // VARIABLES ORG — show byte tally
        if (node_title == "VARIABLES") {
            var _total_bytes = 0;
            var _child_count = 0;
            var _org_ref = id;
			with (obj_c64_node) {
                if (org_parent == _org_ref && node_type == "NAMED_LOC") {
                    var _m = scr_nloc_find_meta(string(instructions[0][1]));
                    if (_m != undefined) {
                        _total_bytes += _m.size;
                        _child_count++;
                    }
                }
                if (org_parent == _org_ref && node_type == "NEW_STR") {
                    _total_bytes += total_node_size;
                    _child_count++;
                }
            }
            var _end_uv = pc_address + _total_bytes ;
            var _end_hex = decimal_to_hex(_end_uv);
            while (string_length(_end_hex) < 4) _end_hex = "0" + _end_hex;
            draw_set_font(fnt_c64_pico);
            draw_set_color(make_color_rgb(120, 220, 250));
            draw_text(draw_x + 6, y + height - 16,
                string(_child_count) + " VARS / " + string(_total_bytes) + " BYTES  [$" +
                string_upper(_org_hex) + "-$" + string_upper(_end_hex) + "]");
        }

    } break;

    case "RAW_DATA": {
        var _raw_str = (array_length(instructions) > 0) ? string(instructions[0][1]) : "";
        var _bytes   = string_split(_raw_str, ",");
        var _count   = array_length(_bytes);
        var _preview = "";
        for (var _bi = 0; _bi < min(_count, 6); _bi++)
            _preview += "$" + string_upper(string_trim(_bytes[_bi])) + " ";
        if (_count > 6) _preview += "...";
        draw_set_font(fnt_c64_code);
        draw_set_color(make_color_rgb(180, 220, 255));
        draw_text(draw_x + 10, y + header_h + 4, string(_count) + " BYTES: ");
        draw_set_color(c_yellow);
        draw_text(draw_x + 110, y + header_h + 4, _preview);
    } break;

    case "SPR64": {
        var _frame_idx = (array_length(instructions[0]) > 3) ? real(instructions[0][3]) : 0;
        var _bg_col    = (array_length(instructions[0]) > 5) ? real(instructions[0][5]) : 0;
        var _mc1_col   = (array_length(instructions[0]) > 6) ? real(instructions[0][6]) : 0;
        var _mc2_col   = (array_length(instructions[0]) > 7) ? real(instructions[0][7]) : 0;

        if (_frame_idx != spr_cached_frame || !surface_exists(spr_surface)) {
            spr_cached_frame = _frame_idx;
            spr_cached_bytes = [];
            spr_cached_mc    = false;
            spr_cached_uc    = 1;

            var _json = (array_length(instructions[0]) > 1) ? string(instructions[0][1]) : "";
            if (_json != "" && _json != "0") {
                var _found = 0; var _depth = 0; var _obj_str = ""; var _obj_start = -1;
                for (var _ci = 1; _ci <= string_length(_json); _ci++) {
                    var _ch = string_char_at(_json, _ci);
                    if (_ch == "{") { if (_depth == 0) _obj_start = _ci; _depth++; }
                    else if (_ch == "}") {
                        _depth--;
                        if (_depth == 0 && _obj_start > 0) {
                            if (_found == _frame_idx) {
                                _obj_str = string_copy(_json, _obj_start, _ci - _obj_start + 1);
                                break;
                            }
                            _found++;
                            _obj_start = -1;
                        }
                    }
                }
                if (_obj_str != "") {
                    var _mc_pos = string_pos("\"mc\":", _obj_str);
                    if (_mc_pos > 0) spr_cached_mc = (string_char_at(_obj_str, _mc_pos + 5) == "1");
                    var _uc_pos = string_pos("\"uc\":", _obj_str);
                    if (_uc_pos > 0) spr_cached_uc = real(string_char_at(_obj_str, _uc_pos + 5));
                    var _b_pos = string_pos("\"b\":\"", _obj_str);
                    if (_b_pos > 0) {
                        var _b_start = _b_pos + 5;
                        var _b_end   = string_pos_ext("\"", _obj_str, _b_start);
                        if (_b_end > _b_start)
                            spr_cached_bytes = string_split(string_copy(_obj_str, _b_start, _b_end - _b_start), ",");
                    }
                }
            }
            if (!surface_exists(spr_surface)) spr_surface = surface_create(24 * 4, 21 * 4);
            surface_set_target(spr_surface);
            draw_clear(make_color_rgb(40, 40, 40));
            scr_draw_sprite_preview(spr_cached_bytes, spr_cached_mc, spr_cached_uc, _bg_col, _mc1_col, _mc2_col, 0, 0, 4);
            surface_reset_target();
        }

        var _spx   = draw_x + 10;
        var _spy   = y + 24 + 6;
        var _psize = 4;

        if (array_length(spr_cached_bytes) >= 63) {
            draw_surface(spr_surface, _spx, _spy);
        } else {
            draw_set_color(make_color_rgb(40, 40, 40));
            draw_rectangle(_spx, _spy, _spx + (24 * _psize), _spy + (21 * _psize), false);
            draw_set_font(fnt_c64_tiny);
            draw_set_color(c_gray);
            draw_set_halign(fa_center);
            draw_text(_spx + (24 * _psize * 0.5), _spy + (21 * _psize * 0.5) - 6, "NO DATA");
            draw_text(_spx + (24 * _psize * 0.5), _spy + (21 * _psize * 0.5) + 4, "CLICK TO IMPORT");
            draw_set_halign(fa_left);
        }

        var _schk_x = _spx + (24 * _psize) + 10;
        var _schk_y = _spy + 26;
        draw_set_color(spr_cached_mc ? make_color_rgb(200, 120, 40) : make_color_rgb(60, 60, 60));
        draw_rectangle(_schk_x, _schk_y, _schk_x + 12, _schk_y + 12, false);
        if (spr_cached_mc) {
            draw_set_color(c_white);
            draw_line(_schk_x + 2,  _schk_y + 6,  _schk_x + 5,  _schk_y + 10);
            draw_line(_schk_x + 5,  _schk_y + 10, _schk_x + 10, _schk_y + 3);
        }
        draw_set_color(c_gray);
        draw_rectangle(_schk_x, _schk_y, _schk_x + 12, _schk_y + 12, true);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(spr_cached_mc ? make_color_rgb(200, 120, 40) : c_gray);
        draw_text(_schk_x + 16, _schk_y, "MC");

        var _nav_y     = _schk_y + 22;
        var _nav_lx    = _schk_x;
        var _nav_mid_x = _schk_x + 30;
        var _nav_rx    = _schk_x + 56;
        var _arr_w = 24;
        var _arr_h = 28;
        var _hl = point_in_rectangle(mouse_x, mouse_y, _nav_lx, _nav_y, _nav_lx + _arr_w, _nav_y + _arr_h);
        var _hr = point_in_rectangle(mouse_x, mouse_y, _nav_rx, _nav_y, _nav_rx + _arr_w, _nav_y + _arr_h);
        draw_set_color(_hl ? c_white : c_aqua);
        draw_triangle(_nav_lx + _arr_w, _nav_y, _nav_lx + _arr_w, _nav_y + _arr_h, _nav_lx, _nav_y + (_arr_h * 0.5), false);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(c_yellow);
        draw_set_halign(fa_center);
        draw_text(_nav_mid_x + 4, _nav_y + 8, string(_frame_idx));
        draw_set_halign(fa_left);
        draw_set_color(_hr ? c_white : c_aqua);
        draw_triangle(_nav_rx, _nav_y, _nav_rx, _nav_y + _arr_h, _nav_rx + _arr_w, _nav_y + (_arr_h * 0.5), false);

        var _ibx1  = _spx + (24 * _psize) + 10;
        var _iby1  = _spy;
        var _ibx2  = draw_x + width - 8;
        var _iby2  = _iby1 + 20;
        var _ibhov = point_in_rectangle(mouse_x, mouse_y, _ibx1, _iby1, _ibx2, _iby2);
        draw_set_color(_ibhov ? make_color_rgb(80, 160, 80) : make_color_rgb(40, 80, 40));
        draw_rectangle(_ibx1, _iby1, _ibx2, _iby2, false);
        draw_set_color(c_white);
        draw_set_font(fnt_c64_tiny);
        draw_set_halign(fa_center);
        draw_text(_ibx1 + (_ibx2 - _ibx1) * 0.5, _iby1 + 4, "IMPORT");
        draw_set_halign(fa_left);
        var _src_path = (array_length(instructions[0]) > 2) ? string(instructions[0][2]) : "";
        draw_set_color(_src_path != "" ? make_color_rgb(140, 140, 100) : make_color_rgb(80, 80, 80));
        draw_text(_ibx1 - 105, _iby1 + 85, (_src_path != "") ? filename_name(_src_path) : "NO FILE");
    } break;

    default: {
        var _is_opcode_body = (
            node_type != "LABEL"     && node_type != "RAW_DATA"  && node_type != "DATA_TEXT" &&
            node_type != "DATA_SID"  && node_type != "SPR64"     && node_type != "BITMAP_KLA"
        );

        // ---- Cheap signature: rebuild display cache only when content changes ----
        var _body_sig = node_type + "|" + string(global.use_hex_display) + "|" + string(array_length(instructions));
        for (var _ss = 0; _ss < array_length(instructions); _ss++) {
            _body_sig += "~" + string(instructions[_ss][0]) +
                         ":" + string((array_length(instructions[_ss]) > 1) ? instructions[_ss][1] : "") +
                         ":" + string((array_length(instructions[_ss]) > 2) ? instructions[_ss][2] : "");
        }
        if (draw_cache_dirty || draw_cache_sig != _body_sig) {
            draw_cache_sig = _body_sig;
            draw_cache_dirty = false;
            draw_cache_lines = [];
            for (var _ci = 0; _ci < array_length(instructions); _ci++) {
                var _ci_inst    = instructions[_ci][0];
                var _ci_rawv    = (array_length(instructions[_ci]) > 1) ? instructions[_ci][1] : 0;
                var _ci_stored  = (array_length(instructions[_ci]) > 2) ? instructions[_ci][2] : "";
                var _ci_lower   = string_lower(_ci_inst);

                var _ci_implied = (
                    _ci_lower == "inx"   || _ci_lower == "iny"   || _ci_lower == "dex"   || _ci_lower == "dey"  ||
                    _ci_lower == "sei"   || _ci_lower == "cli"   || _ci_lower == "rts"   || _ci_lower == "rti"  ||
                    _ci_lower == "clc"   || _ci_lower == "sec"   || _ci_lower == "pha"   || _ci_lower == "pla"  ||
                    _ci_lower == "php"   || _ci_lower == "plp"   || _ci_lower == "tax"   || _ci_lower == "tay"  ||
                    _ci_lower == "txa"   || _ci_lower == "tya"   || _ci_lower == "tsx"   || _ci_lower == "txs"  ||
                    _ci_lower == "asl_a" || _ci_lower == "lsr_a" || _ci_lower == "nop"   || _ci_lower == "brk"
                );

                // Resolve display value once
                var _ci_dval = "";
                if (_is_jump || _is_branch || node_type == "LABEL") {
                    _ci_dval = (_ci_stored != "") ? _ci_stored : string(_ci_rawv);
                } else if (global.use_hex_display && is_real(_ci_rawv)) {
                    var _ci_dh = decimal_to_hex(_ci_rawv);
                    var _ci_16 = (string_pos("_abs", _ci_lower) > 0 ||
                                  string_pos("_abx", _ci_lower) > 0 ||
                                  string_pos("_aby", _ci_lower) > 0 ||
                                  string_pos("_ind", _ci_lower) > 0);
                    var _ci_pad = _ci_16 ? 4 : 2;
                    while (string_length(_ci_dh) < _ci_pad) _ci_dh = "0" + _ci_dh;
                    _ci_dval = "$" + string_upper(_ci_dh);
                } else {
                    _ci_dval = string(_ci_rawv);
                }

                // Resolve syntax parts + illegal flag once
                var _ci_prefix = "";
                var _ci_suffix = "";
                var _ci_illegal = false;
                if (node_type != "LABEL") {
                    var _ci_parts = scr_get_opcode_syntax_parts(_ci_inst);
                    _ci_prefix = _ci_parts[0];
                    _ci_suffix = _ci_parts[1];
                    _ci_illegal = (string_pos("lax", _ci_lower) || string_pos("sax", _ci_lower) || string_pos("dcp", _ci_lower));
                }

                array_push(draw_cache_lines, {
                    inst:    _ci_inst,
                    lower:   _ci_lower,
                    val:     _ci_dval,
                    prefix:  _ci_prefix,
                    suffix:  _ci_suffix,
                    implied: _ci_implied,
                    illegal: _ci_illegal
                });
            }
        }

        for (var _ii = 0; _ii < array_length(instructions); _ii++) {
            var _yy         = y + header_h + (_ii * 12) + 8;
            var _cache      = draw_cache_lines[_ii];
            var _inst       = _cache.inst;
            var _raw_val    = (array_length(instructions[_ii]) > 1) ? instructions[_ii][1] : 0;

            var _inst_lower = _cache.lower;
            var _stored_str = (array_length(instructions[_ii]) > 2) ? instructions[_ii][2] : "";

            var _is_implied = _cache.implied;

            if (node_type == "DATA_TEXT" || _inst_lower == "text" || _inst_lower == "ascii") {
                draw_set_color(c_lime);
                draw_text(draw_x + 10, _yy, "\"" + string(_raw_val) + "\"");
                continue;
            }
            if (node_type == "COMMENT") {
                draw_set_color(c_yellow);
                var _cmt_str    = string(_raw_val);
                var _cmt_area_w = width - 10;
                var _cmt_txt_w  = string_width(_cmt_str);
                var _cmt_scl    = (_cmt_txt_w > _cmt_area_w && _cmt_txt_w > 0)
                                  ? (_cmt_area_w / _cmt_txt_w)
                                  : 1.0;
                if (_cmt_scl < 1.0) {
                    draw_text_transformed(draw_x + 5, _yy, _cmt_str, _cmt_scl, 1.0, 0);
                } else {
                    draw_text_ext(draw_x + 5, _yy, _cmt_str, line_h, width - 10);
                }
                continue;
            }

            var _display_val = _cache.val;

// =============================================================
// FULL SEQUENTIAL DRAWING BLOCK (No big gaps)
// =============================================================
if (node_type == "LABEL") {
    draw_set_font(fnt_c64_tiny);
} else {
    draw_set_font(fnt_C64_Angled_tiny);
}
if (node_type == "LABEL") {
    draw_set_color(c_yellow);
    draw_text(draw_x + 8, _yy-6, "ID: " + _display_val);
    
// (removed: sid_exit auto-adjust hint no longer needed)

} else {
    var _prefix = _cache.prefix;
    var _suffix = _cache.suffix;

    // 1. Draw Mnemonic/Prefix (e.g., "LDA #")

    var _is_illegal = _cache.illegal;
    draw_set_color(_is_illegal ? make_color_rgb(200, 120, 255) : c_ltgray);
    draw_set_halign(fa_left);
    draw_text(draw_x + 10, _yy, _prefix);

    if (!_is_implied) {
        var _cursor_x = draw_x + 10 + string_width(_prefix);

        // 2. Draw Editable Value immediately after prefix (Yellow)
        draw_set_color(c_yellow);
        draw_text(_cursor_x, _yy, _display_val);
        
        // 3. Draw Suffix immediately after value (e.g., ",X")
        if (_suffix != "") {
            _cursor_x += string_width(_display_val);
            draw_set_color(_is_illegal ? make_color_rgb(180, 100, 230) : c_ltgray);
            draw_text(_cursor_x, _yy, _suffix);
        }
    }
}
			
			

            // LOOK UP button removed — operand text itself opens the picker.
        }
    } break;
}

// =============================================================
// K. BOTTOM-LEFT ADDRESS BADGE
// =============================================================
if ((_lod_addresses && node_type == "ORG" || (global.show_stats && _near_centre && string_pos("MACRO", node_type) > 0)) && node_title != "HW REGISTERS" && node_title != "VARIABLES") {
    draw_set_font(fnt_c64_tiny);

    if (node_type == "ORG" && node_title == "VARIABLES")  {
        var _total_bytes = 0;
        var _org_ref = id;
        with (obj_c64_node) {
            if (org_parent == _org_ref && node_type == "NAMED_LOC") {
                var _m = scr_nloc_find_meta(string(instructions[0][1]));
                if (_m != undefined) _total_bytes += _m.size;
            }
        }
        var _end_uv  = pc_address + _total_bytes;
        var _uv_hex  = decimal_to_hex(_end_uv);
        while (string_length(_uv_hex) < 4) _uv_hex = "0" + _uv_hex;
        draw_set_color(make_color_rgb(120, 180, 100));
		draw_set_font(fnt_c64_code);
        draw_text(draw_x - 60, y + height - 18, ">$" + string_upper(_uv_hex));
} else {
        // This handles standard ORGs and Macros
        var _end_addr = pc_address + total_node_size;
if (node_type == "ORG") {
            var _org_ref = id;
            var _best_end = _end_addr;
            with (obj_c64_node) {
                if (org_parent == _org_ref && is_connected &&
                    node_type != "NAMED_LOC" && node_type != "NEW_STR") {
                    var _child_end = pc_address + total_node_size;
                    if (_child_end > _best_end) _best_end = _child_end;
                }
            }
            _end_addr = _best_end;
        }
        var _ah = decimal_to_hex(_end_addr);
        while (string_length(_ah) < 4) _ah = "0" + _ah;
draw_set_font(fnt_c64_code);
        var _badge_str = global.use_hex_display ? (">$" + string_upper(_ah)) : ("> " + string(_end_addr));

		draw_set_color((node_type == "ORG") ? c_orange : make_color_rgb(30, 200, 80));
        if (is_connected || node_type == "ORG") draw_text(draw_x - 60, y + height - 18, _badge_str);
    }
}

// =============================================================
// L. OUTLINE + MEMORY OVERLAP WARNING
// Simply use the conflict status determined by the global scanner
// =============================================================
var _overlaps = is_conflicted;

// Safety net: structural nodes hold no memory, wipe their conflict/overlap states unconditionally
if (node_type == "COMMENT" || node_type == "LABEL" || node_type == "EXECUTE") {
    _overlaps = false;
    if (variable_instance_exists(id, "is_conflicted")) is_conflicted = false;
}

// Only show the red pulse if we aren't actively clicking/dragging it
// (this prevents the "State Transition Flash")
if (_overlaps && !is_dragging && !mouse_check_button(mb_left)) {
    var _pulse = abs(sin(current_time * 0.004));
    draw_set_alpha( (_pulse * 0.5));
    draw_set_color(c_red); // flash pulse red
    draw_rectangle(draw_x, y, draw_x + width, y + height, false);
    draw_set_alpha(1.0);
}

// Conflict fill — drawn after body content so it's not overwritten
// (Code completely removed to prevent overlapping flash effects)
/*
var _outline_col = is_dragging ? c_white : ((is_conflicted || _overlaps) ? c_red : c_gray);
draw_set_color(_outline_col);
draw_set_alpha(_box_alpha);
draw_rectangle(draw_x, y, draw_x + width, y + height, true);
draw_set_alpha(1.0);
*/

// =============================================================
// L2. GROUP DRAG HANDLE HIGHLIGHT
// =============================================================
if (array_length(global.selected_nodes) > 1 && instance_exists(global.group_drag_handle)) {
    var _ctrl_held = keyboard_check(vk_control) || scr_cmd_held();
    var _is_clone  = _ctrl_held || global.group_drag_is_clone;
    var _ring_col  = _is_clone ? c_lime : c_yellow;

    if (id == global.group_drag_handle) {
        var _hov_header = point_in_rectangle(mouse_x, mouse_y, draw_x, y, draw_x + width, y + 24);
        if (_hov_header || global.group_drag_active) {
            draw_set_color(_ring_col);
            draw_set_alpha(0.9);
            draw_rectangle(draw_x - 2, y - 2, draw_x + width + 2, y + height + 2, true);
            draw_rectangle(draw_x - 4, y - 4, draw_x + width + 4, y + height + 4, true);
            draw_set_alpha(1.0);
            if (_hov_header && !global.group_drag_active) {
                draw_set_font(fnt_c64_tiny);
                draw_set_color(_ring_col);
                draw_set_halign(fa_center);
                draw_text(draw_x + width * 0.5, y - 14,
                    _is_clone
                    ? "CLONE GROUP (" + string(array_length(global.selected_nodes)) + ")"
                    : "DRAG GROUP (" + string(array_length(global.selected_nodes)) + ") | CTRL=CLONE");
                draw_set_halign(fa_left);
            }
        }
    }
    var _in_sel = false;
    for (var _si = 0; _si < array_length(global.selected_nodes); _si++) {
        if (global.selected_nodes[_si] == id) { _in_sel = true; break; }
    }
    if (_in_sel && id != global.group_drag_handle) {
        draw_set_color(_ring_col);
        draw_set_alpha(0.12);
        draw_rectangle(draw_x, y, draw_x + width, y + height, false);
        draw_set_alpha(0.4);
        draw_rectangle(draw_x, y, draw_x + width, y + height, true);
        draw_set_alpha(1.0);
    }
}

// =============================================================
// M. DROP ZONE VISUALISATION
// =============================================================

// Wedge preview insertion line
if (global.wedge_preview_y >= 0 && global.any_node_dragging) {
    var _wpy     = global.wedge_preview_y;
    var _spine_x  = floor(((room_width / 2) - (global.node_display_width / 2)) / 20) * 20;
    var _wpx1    = _spine_x - 10;
    var _wpx2    = _spine_x + global.node_display_width + 10;



    // Only one node draws the line (INIT, or the anchor ORG)
var _draw_line = false;
    if (global.wedge_preview_spine && node_type == "INIT") _draw_line = true;
    if (!global.wedge_preview_spine && instance_exists(global.wedge_preview_anchor) && id == global.wedge_preview_anchor) _draw_line = true;
    if (global.wedge_preview_spine && node_type != "INIT") _draw_line = false;

if (_draw_line) {
        var _wedge_indent = 0;
        if (global.wedge_preview_spine) {
            var _wa = global.wedge_preview_node;
            var _wb = noone;
            with (obj_c64_node) {
                if (is_connected && org_parent == noone && !is_dragging &&
                    node_type != "ORG" && node_type != "EXECUTE" &&
                    y < (instance_exists(_wa) ? _wa.y : 999999) && y > 0) {
                    _wb = id;
                }
            }
            var _ind_above = (instance_exists(_wb) && _wb != noone) ? _wb.x_indent : 0;
            var _ind_below = instance_exists(_wa) ? _wa.x_indent : 0;
            _wedge_indent = max(_ind_above, _ind_below);
        }
        var _org_indent = 0;
        if (!global.wedge_preview_spine && instance_exists(global.wedge_preview_anchor)) {
            var _wa2 = global.wedge_preview_node;
            var _wb2 = noone;
            var _anch = global.wedge_preview_anchor;
            var _best_above2 = _anch.y;
            with (obj_c64_node) {
                if (org_parent == _anch && is_connected && !is_dragging &&
                    y < (instance_exists(_wa2) ? _wa2.y : 999999) && y > _best_above2) {
                    _best_above2 = y;
                    _wb2 = id;
                }
            }
            var _ind_above2 = instance_exists(_wb2) ? _wb2.x_indent : 0;
            var _ind_below2 = instance_exists(_wa2) ? _wa2.x_indent : 0;
            _org_indent = max(_ind_above2, _ind_below2);
        }
        var _lx1 = global.wedge_preview_spine ? (_wpx1 + _wedge_indent) : (x - 10 + _org_indent);
        var _lx2 = global.wedge_preview_spine ? (_wpx2 + _wedge_indent) : (x + width + 10 + _org_indent);
        draw_set_color(make_color_rgb(80, 220, 120));
        draw_set_alpha(0.9);
        draw_rectangle(_lx1, _wpy - 2, _lx2, _wpy + 2, false);
        draw_set_alpha(0.4);
        draw_rectangle(_lx1, _wpy - 6, _lx2, _wpy + 6, false);
        draw_set_alpha(1.0);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 220, 120));
        draw_set_halign(fa_center);
        draw_text((_lx1 + _lx2) * 0.5, _wpy + 6, ">> INSERT <<");
        draw_set_halign(fa_left);
    }
}
var _latch_h  = 120;
var _sticky_h = 300;
var _dash     = 8;
var _gap      = 6;
var _step     = _dash + _gap;

var _any_dragging = false;
var _ref_x        = 0;
var _ref_y        = 0;
with (obj_c64_node) {
    if (is_dragging && node_type != "ORG"  && node_type != "INIT" &&
        node_type != "SPR64" && string_pos("DATA", node_type) == 0 &&
        node_type != "NAMED_LOC" && node_type != "NEW_STR") {
        _any_dragging = true;
        _ref_x = x + (width * 0.5);
        _ref_y = y;
    }
}

if (_any_dragging) {
// Main spine drop zone
    if (is_connected && org_parent == noone && !is_dragging &&
        node_type != "ORG" && node_type != "EXECUTE" && node_type != "COMMENT") {
        var _is_bottom = true;
        var _my_id = id;
        var _my_y  = y;
        var _my_h  = height;
        with (obj_c64_node) {
            if (id != _my_id && is_connected && org_parent == noone && !is_dragging &&
                node_type != "ORG" && node_type != "EXECUTE" && y > _my_y)
                _is_bottom = false;
        }
        if (_is_bottom) {
            var _base_y = y + _my_h;
            var _lx1  = x - 10;
            var _lx2  = x + width + 10;
            var _ly1  = _base_y;
            var _ly2  = _base_y + _latch_h;
            var _dsy2 = _base_y + _sticky_h;
            var _in_latch  = point_in_rectangle(_ref_x, _ref_y, _lx1, _ly1, _lx2, _ly2);
            var _in_sticky = point_in_rectangle(_ref_x, _ref_y, _lx1, _ly1, _lx2, _dsy2);
// Light up when dragging within the spine column — but only show as active latch within _latch_h
            var _spine_top = 60;
            var _in_chain  = point_in_rectangle(_ref_x, _ref_y, _lx1, _spine_top, _lx2, _ly1);
            // in_chain shows dim zone only, snap fires via D2

            if (_in_sticky && !_in_latch) {
                draw_set_alpha(0.2);
                draw_set_color(make_color_rgb(40, 200, 80));
                var _cx = _lx1; while (_cx < _lx2)  { draw_line(_cx, _ly1,  min(_cx + _dash, _lx2), _ly1);  draw_line(_cx, _dsy2, min(_cx + _dash, _lx2), _dsy2); _cx += _step; }
                var _cy = _ly1; while (_cy < _dsy2) { draw_line(_lx1, _cy,  _lx1, min(_cy + _dash, _dsy2)); draw_line(_lx2, _cy,  _lx2, min(_cy + _dash, _dsy2)); _cy += _step; }
            }
            var _latch_col = _in_latch ? make_color_rgb(40, 220, 80) : make_color_rgb(20, 120, 40);
            draw_set_alpha(_in_latch ? 0.9 : 0.35);
            draw_set_color(_latch_col);
            var _cx = _lx1; while (_cx < _lx2)  { draw_line(_cx, _ly1, min(_cx + _dash, _lx2), _ly1); draw_line(_cx, _ly2, min(_cx + _dash, _lx2), _ly2); _cx += _step; }
            var _cy = _ly1; while (_cy < _ly2)  { draw_line(_lx1, _cy, _lx1, min(_cy + _dash, _ly2)); draw_line(_lx2, _cy, _lx2, min(_cy + _dash, _ly2)); _cy += _step; }
			if (_in_latch || _in_chain) {
                draw_set_alpha(0.8);
                draw_rectangle(_lx1, _ly1, _lx2, _ly1 + 6, false);
                draw_set_font(fnt_c64_tiny);
                draw_set_alpha(1.0);
                draw_text(x + 12, _ly1 + 30, "DROP TO ATTACH");
            }
            draw_set_alpha(1.0);
        }
    }

    // ORG chain drop zone

if (node_type == "ORG") {
        var _eligible = false;
        var _is_vars_org = (node_title == "VARIABLES");
        var _org_ref2 = id;
        with (obj_c64_node) {
            if (is_dragging && org_parent == noone && node_type != "ORG" && node_type != "INIT" &&
                node_type != "SPR64" && string_pos("DATA", node_type) == 0) {
                var _is_var_node = (node_type == "NAMED_LOC" || node_type == "NEW_STR");
                if (!_is_vars_org || _is_var_node) _eligible = true;
            }
            // Suppress if the dragging node is already a child of this ORG
            if (is_dragging && org_parent == _org_ref2) _eligible = false;
        }
		
	if (_eligible) {
            var _chain_bottom = y + height;
            var _org_ref = id;
            with (obj_c64_node) {
                if (org_parent == _org_ref && is_connected && y + height > _chain_bottom)
                    _chain_bottom = y + height;
            }
            var _olx1 = x - 10;
            var _olx2 = x + width + 10;
            var _oly1 = _chain_bottom;
            var _oly2 = _chain_bottom + _latch_h;
            var _osy2 = _chain_bottom + _sticky_h;
            var _oin_latch  = point_in_rectangle(_ref_x, _ref_y, _olx1, _oly1, _olx2, _oly2);
            var _oin_sticky = point_in_rectangle(_ref_x, _ref_y, _olx1, _oly1, _olx2, _osy2);
            // Also show drop zone when dragging inside the chain
            var _oin_chain  = point_in_rectangle(_ref_x, _ref_y, _olx1, y, _olx2, _chain_bottom);
            if (_oin_chain) _oin_latch = true;

            if (_oin_sticky && !_oin_latch) {
                draw_set_alpha(0.2);
                draw_set_color(make_color_rgb(200, 60, 240));
                var _cx = _olx1; while (_cx < _olx2)  { draw_line(_cx, _oly1, min(_cx + _dash, _olx2), _oly1); draw_line(_cx, _osy2, min(_cx + _dash, _olx2), _osy2); _cx += _step; }
                var _cy = _oly1; while (_cy < _osy2) { draw_line(_olx1, _cy, _olx1, min(_cy + _dash, _osy2)); draw_line(_olx2, _cy, _olx2, min(_cy + _dash, _osy2)); _cy += _step; }
            }
            var _olatch_col = _oin_latch ? make_color_rgb(220, 80, 255) : make_color_rgb(120, 40, 140);
            draw_set_alpha(_oin_latch ? 0.9 : 0.35);
            draw_set_color(_olatch_col);
            var _cx = _olx1; while (_cx < _olx2) { draw_line(_cx, _oly1, min(_cx + _dash, _olx2), _oly1); draw_line(_cx, _oly2, min(_cx + _dash, _olx2), _oly2); _cx += _step; }
            var _cy = _oly1; while (_cy < _oly2) { draw_line(_olx1, _cy, _olx1, min(_cy + _dash, _oly2)); draw_line(_olx2, _cy, _olx2, min(_cy + _dash, _oly2)); _cy += _step; }
            if (_oin_latch) {
                draw_set_alpha(0.8);
                draw_rectangle(_olx1, _oly1, _olx2, _oly1 + 6, false);
                draw_set_font(fnt_c64_tiny);
                draw_set_alpha(1.0);
                draw_text(x + 12, _oly1 + 30, "DROP TO ATTACH");
            }
            draw_set_alpha(1.0);
        }
    }
}


// ORG drag area indicator
// Only draw the purple search zone for standard ORG nodes, not Variables or HW Registers, and only when proxy is enabled
if (is_dragging && node_type == "ORG" && node_title != "VARIABLES" && node_title != "HW REGISTERS" && proxy && !global.box_drag_active) {
    var _sx1 = x - (global.node_display_width * 2);
    var _sx2 = x + global.node_display_width ;
    var _sy1 = y - 220;
    var _sy2 = y + 100;
	
	
    draw_set_alpha(0.25);
    draw_set_color(c_purple);
    draw_rectangle(_sx1, _sy1, _sx2, _sy2, false);
    draw_set_alpha(0.6);
    draw_set_color(c_purple);
    var _d  = 8; var _g = 6; var _st = _d + _g;
    var _cx = _sx1; while (_cx < _sx2) { draw_line(_cx, _sy1, min(_cx + _d, _sx2), _sy1); draw_line(_cx, _sy2, min(_cx + _d, _sx2), _sy2); _cx += _st; }
    var _cy = _sy1; while (_cy < _sy2) { draw_line(_sx1, _cy, _sx1, min(_cy + _d, _sy2)); draw_line(_sx2, _cy, _sx2, min(_cy + _d, _sy2)); _cy += _st; }
    draw_set_alpha(1.0);
}

// =============================================================
// N. FLASH OVERLAY (RMB or Editor Clash)
// =============================================================
// 1. RMB Flash
if (rmb_flash > 0) {
    var _flash_alpha = rmb_flash / 300;
    draw_set_color(c_white);
    draw_set_alpha(_flash_alpha);
   // draw_rectangle(x - 2, y - 2, x + width + 2, y + height + 2, true);
   // draw_rectangle(x - 1, y - 1, x + width + 1, y + height + 1, true);
    draw_set_alpha(1.0);
}
/*
// 2. Conflict Flash (When editor is closed but node is guilty)
if (is_conflicted) {
    var _cpulse = abs(sin(current_time * 0.004)) * 0.25;
    draw_set_color(c_purple);
    draw_set_alpha(_cpulse);
    draw_rectangle(x - 2, y - 2, x + width + 2, y + height + 2, true);
    draw_rectangle(x - 1, y - 1, x + width + 1, y + height + 1, true);
    draw_set_alpha(1.0);
}
   */ 
// (debug removed)


x -= x_indent;
draw_set_alpha(1.0);

// =============================================================
// Z. ON-NODE DEBUG STATE MONITOR ('@' Toggle)
// =============================================================
// 1. Initialize the global toggle if it doesn't exist
if (!variable_global_exists("debug_hud_active")) global.debug_hud_active = false;

// 2. Only let the FIRST node in the room handle the toggle math (prevents 50x flipping)
if (id == instance_find(obj_c64_node, 0)) {
    if (keyboard_check_pressed(vk_anykey) && keyboard_lastchar == "@") {
        global.debug_hud_active = !global.debug_hud_active;
        keyboard_lastchar = ""; // Clear it so we don't accidentally double-trigger
    }
}

// 3. Draw the HUD if active
if (global.debug_hud_active) {
    var _dbg_y = y - 20;
    
    // Background banner
    draw_set_color(c_black);
    draw_set_alpha(0.85);
    draw_rectangle(draw_x, _dbg_y, draw_x + width, y, false);
    draw_set_alpha(1.0);
    
    // Format values
    var _s_conn = is_connected ? "T" : "F";
    var _s_drag = is_dragging ? "T" : "F";
if (node_type == "INIT") {
    draw_text(x, y - 60, "claim:" + string(global.drag_claim_taken)
        + " pick:" + string(global.any_picker_open)
        + " edit:" + string(global.canEditNode)
        + " wasEd:" + string(global.was_editor_open));
}
    var _s_conf = is_conflicted ? "T" : "F";
    var _hx = string_upper(decimal_to_hex(pc_address));
    while (string_length(_hx) < 4) _hx = "0" + _hx;
    
    // Draw text
    draw_set_color(is_conflicted ? c_red : c_yellow);
    draw_set_font(fnt_c64_tiny);
    var _dbg_str = "CON:" + _s_conn + " DRG:" + _s_drag + " CNF:" + _s_conf + " | PC:$" + _hx + " SZ:" + string(total_node_size);
    draw_text(draw_x + 4, _dbg_y + 4, _dbg_str);
}

// =============================================================
// INIT NODE [CLEAR] BUTTON
// =============================================================
if (node_type == "INIT" && array_length(instructions) > 0) {
    var _btn_w  = 60;
    var _btn_h  = 20;
    var _btn_x1 = x + width - _btn_w - 8;
    var _btn_y1 = y + height - _btn_h - 6;
    var _btn_x2 = _btn_x1 + _btn_w;
    var _btn_y2 = _btn_y1 + _btn_h;

    var _is_active = (array_length(instructions) > 0);
    var _is_hover  = false;
    if (_is_active) {
        _is_hover = point_in_rectangle(mouse_x, mouse_y, _btn_x1, _btn_y1, _btn_x2, _btn_y2);
    }

    var _bg_col  = c_dkgray;
    var _br_col  = _is_active ? c_yellow : make_color_rgb(80, 30, 30);
    var _txt_col = _is_active ? c_yellow : make_color_rgb(80, 30, 30);
    if (_is_hover) {
        _bg_col  = make_color_rgb(60, 180, 30);
        _txt_col = c_white;
    }

    draw_set_alpha(_is_active ? 1.0 : 0.5);
    draw_set_color(_bg_col);
    draw_rectangle(_btn_x1, _btn_y1, _btn_x2, _btn_y2, false);
    draw_set_color(_br_col);
    draw_rectangle(_btn_x1, _btn_y1, _btn_x2, _btn_y2, true);

    draw_set_font(fnt_c64_tiny);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_color(_txt_col);
    draw_text(_btn_x1 + _btn_w * 0.5, _btn_y1 + _btn_h * 0.5, "CLEAR");
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_alpha(1.0);
}

// =============================================================
// INIT NODE EMPTY-STATE HINT
// =============================================================
if (node_type == "INIT" && array_length(instructions) == 0) {
    draw_set_font(fnt_c64_tiny);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_set_alpha(0.4);
    draw_set_color(c_white);
    draw_text(x + width * 0.5, (y + height * 0.5) +6, "START CODING\nBELOW");
    draw_set_alpha(1.0);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}

// =============================================================
// LABEL-REFERENCE HIGHLIGHT OVERLAY
// =============================================================
if (global.ref_highlight_source != noone && instance_exists(global.ref_highlight_source)
    && global.ref_highlight_name != "") {

    var _hx = x + x_indent;

    // Source LABEL — solid cyan ring so you can see what is broadcasting
    if (id == global.ref_highlight_source) {
        var _src_pulse = abs(sin(current_time * 0.005));
        draw_set_color(merge_colour(make_color_rgb(40, 200, 255), c_white, _src_pulse));
        draw_set_alpha(0.9);
        draw_rectangle(_hx - 3, y - 3, _hx + width + 3, y + height + 3, true);
        draw_rectangle(_hx - 4, y - 4, _hx + width + 4, y + height + 4, true);
        draw_set_alpha(1.0);
    } else {
        // Brute-force scan: does any string slot in this node match the label name?
        var _refs = false;
        for (var _ri = 0; _ri < array_length(instructions); _ri++) {
            for (var _rj = 0; _rj < array_length(instructions[_ri]); _rj++) {
                var _slot = instructions[_ri][_rj];
                if (is_string(_slot) && _slot == global.ref_highlight_name) {
                    _refs = true;
                    break;
                }
            }
            if (_refs) break;
        }
        if (_refs) {
            // Border pulses outward then fades — expanding ring radiating from the node edge
            var _phase  = (current_time * 0.0015) mod 1.0;   // 0..1 expansion cycle
            var _spread = _phase * 12;                        // how far the ring has travelled out
            var _fade   = 1.0 - _phase;                       // fades as it expands
            draw_set_color(merge_colour(make_color_rgb(255, 200, 40), make_color_rgb(255, 120, 0), _phase));
            draw_set_alpha(_fade * 0.9);
            draw_rectangle(_hx - 2 - _spread, y - 2 - _spread,
                           _hx + width + 2 + _spread, y + height + 2 + _spread, true);
            // Steady inner border so the node stays marked between pulses
            draw_set_color(make_color_rgb(255, 160, 30));
            draw_set_alpha(0.8);
            draw_rectangle(_hx - 2, y - 2, _hx + width + 2, y + height + 2, true);
            draw_set_alpha(1.0);
        }
    }
}