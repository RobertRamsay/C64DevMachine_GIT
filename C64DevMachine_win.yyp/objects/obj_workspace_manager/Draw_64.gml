/// @desc Draw GUI Event - Integrated Workspace UI
// ---- IDLE SNAPSHOT OVERLAY (direct switch instead of node fade) ----
// ---- IDLE SNAPSHOT OVERLAY (direct switch instead of node fade) ----
// Only covers the workspace/node canvas — this was captured from application_surface,
// which never includes Draw GUI content. Every panel below draws over it normally,
// live and interactive, exactly as it does when awake.
if (idle_snapshot_active && sprite_exists(idle_snapshot_spr)) {
    draw_sprite_stretched(idle_snapshot_spr, 0, 0, 0, global.gui_w, display_get_gui_height());
}
if hideui exit;
// Block draw + interaction when asset viewer is open
if (instance_exists(obj_asset_manager) && obj_asset_manager.viewer_open) {
    scr_draw_memory_bar(shelf_width + 60, global.gui_w - 60, display_get_gui_height() - 40);
    exit;
}

var gui_mouse_x = global.gui_mouse_x;
var gui_mouse_y = global.gui_mouse_y;
var gui_w       = global.gui_w;
var gui_h       = display_get_gui_height();


// SHADOW
// on the right
draw_sprite_ext(spr_baseGradient, 0,
    1920, 1080 , 2000, 3, 90, c_white, 1);
	
	
// on left
	draw_sprite_ext(spr_baseGradient, 0,
    shelf_width, 0 , 2000, 1.5, 270, c_white, 1);



/////////////////////////////////////////////////////////////////
///// -1. BOX SELECT OVERLAY
/////////////////////////////////////////////////////////////////
if (box_select_active) {
    var _vx = camera_get_view_x(view_camera[0]);
    var _vy = camera_get_view_y(view_camera[0]);
    var _vw = camera_get_view_width(view_camera[0]);
    var _vh = camera_get_view_height(view_camera[0]);
    var _sx = global.gui_w / _vw;
    var _sy = display_get_gui_height() / _vh;

    var _gx1 = (min(box_select_x1, box_select_x2) - _vx) * _sx;
    var _gy1 = (min(box_select_y1, box_select_y2) - _vy) * _sy;
    var _gx2 = (max(box_select_x1, box_select_x2) - _vx) * _sx;
    var _gy2 = (max(box_select_y1, box_select_y2) - _vy) * _sy;

    // Highlight overlapping nodes
with (obj_c64_node) {
        if (node_type == "INIT") continue;
        var _nx1 = (x + x_indent - _vx) * _sx;
        var _ny1 = (y - _vy) * _sy;
        var _nx2 = (x + x_indent + width  - _vx) * _sx;
        var _ny2 = (y + height - _vy) * _sy;
        if (_nx1 < _gx2 && _nx2 > _gx1 && _ny1 < _gy2 && _ny2 > _gy1) {
            draw_set_alpha(0.3);
            draw_set_color(c_white);
            draw_rectangle(_nx1, _ny1, _nx2, _ny2, false);
            draw_set_alpha(1.0);
        }
    }

    // Box fill
    draw_set_alpha(0.15);
    draw_set_color(c_white);
    draw_rectangle(_gx1, _gy1, _gx2, _gy2, false);
    // Box outline
    draw_set_alpha(1.0);
    draw_set_color(c_white);
    draw_rectangle(_gx1, _gy1, _gx2, _gy2, true);
}

// Draw selection highlights for committed selection
if (array_length(global.selected_nodes) > 0) {
    var _vx = camera_get_view_x(view_camera[0]);
    var _vy = camera_get_view_y(view_camera[0]);
    var _vw = camera_get_view_width(view_camera[0]);
    var _vh = camera_get_view_height(view_camera[0]);
    var _sx = global.gui_w / _vw;
    var _sy = display_get_gui_height() / _vh;
    for (var _si = 0; _si < array_length(global.selected_nodes); _si++) {
        var _sn = global.selected_nodes[_si];
        if (!instance_exists(_sn)) continue;
		var _nx1 = (_sn.x + _sn.x_indent - _vx) * _sx;
        var _ny1 = (_sn.y - _vy) * _sy;
        var _nx2 = (_sn.x + _sn.x_indent + _sn.width  - _vx) * _sx;
        var _ny2 = (_sn.y + _sn.height - _vy) * _sy;
        draw_set_alpha(0.25);
        draw_set_color(c_white);
        draw_rectangle(_nx1, _ny1, _nx2, _ny2, false);
        draw_set_alpha(1.0);
        draw_set_color(c_white);
        draw_rectangle(_nx1, _ny1, _nx2, _ny2, true);
    }
}



/////////////////////////////////////////////////////////////////
///// 0. MAPPING BOX DRAG CURSOR + LIVE PREVIEW (TOPMOST)
/////////////////////////////////////////////////////////////////
if (global.box_drag_active) {
    var _gmx = global.gui_mouse_x;
    var _gmy = global.gui_mouse_y;

    // Crosshair + hint text
    draw_set_font(fnt_C64_Angled);
    draw_set_color(c_yellow);
    draw_set_halign(fa_left);
    draw_text(_gmx + 18, _gmy - 8, box_drag_live ? "DRAGGING..." : "CLICK AND DRAG");
    draw_set_color(c_white);
    draw_line(_gmx - 8, _gmy, _gmx + 8, _gmy);
    draw_line(_gmx, _gmy - 8, _gmx, _gmy + 8);

    // Live rectangle preview
    if (box_drag_live) {
        // Convert room-space start point to GUI space
        var _view_x = camera_get_view_x(view_camera[0]);
        var _view_y = camera_get_view_y(view_camera[0]);
        var _view_w = camera_get_view_width(view_camera[0]);
        var _view_h = camera_get_view_height(view_camera[0]);
        var _port_w = global.gui_w;
        var _port_h = display_get_gui_height();
        var _scale_x = _port_w / _view_w;
        var _scale_y = _port_h / _view_h;

        var _gsx1 = (box_drag_start_x - _view_x) * _scale_x;
        var _gsy1 = (box_drag_start_y - _view_y) * _scale_y;
        // End point is already mouse GUI position
        var _gsx2 = _gmx;
        var _gsy2 = _gmy;

        var _rx1 = min(_gsx1, _gsx2);
        var _ry1 = min(_gsy1, _gsy2);
        var _rx2 = max(_gsx1, _gsx2);
        var _ry2 = max(_gsy1, _gsy2);

        // Fill
        draw_set_alpha(0.2);
        draw_set_color(c_white);
        draw_rectangle(_rx1, _ry1, _rx2, _ry2, false);
        // Outline
        draw_set_alpha(0.9);
        draw_set_color(c_yellow);
        draw_rectangle(_rx1, _ry1, _rx2, _ry2, true);
        draw_set_alpha(1.0);

        // Size readout in room pixels
        var _rw = abs(mouse_x - box_drag_start_x);
        var _rh = abs(mouse_y - box_drag_start_y);
        draw_set_font(fnt_c64_tiny);
        draw_set_color(c_yellow);
        draw_set_halign(fa_left);
        draw_text(_rx2 + 6, _ry2 - 12, string(_rw) + " x " + string(_rh));
    }
}



// Draw the page sprite (replaces all button draw calls)
var _sw_plus = shelf_width+30;

draw_sprite(spr_palette_page, paletteStyle, 0, 0);

draw_sprite_ext(spr_baseGradient, 0,
    0, 1080 , _sw_plus, 1, 0, c_white, 0.5);
	
draw_sprite(spr_logobadge,badgeStyle,6,5)

/////////////////////////////////////////////////////////////////
///// OPCODE FINDER BOX
/////////////////////////////////////////////////////////////////
var _finder_x1 = 53;
var _finder_y1 = 55;
var _finder_x2 = 213;
var _finder_y2 = _finder_y1 + 32;
var _finder_w  = _finder_x2 - _finder_x1;
var _finder_h  = _finder_y2 - _finder_y1;

// Build match list from all pages every frame when active
if (opcode_finder_active || opcode_finder_text != "") {
    opcode_finder_matches = [];
    var _ft = string_upper(opcode_finder_text);
    if (_ft != "") {
        for (var _fpi = 0; _fpi < 3; _fpi++) {
            for (var _fii = 0; _fii < array_length(palette_page[_fpi]); _fii++) {
                var _fitem = palette_page[_fpi][_fii];
                if (_fitem.type == "HEADER" || _fitem.type == "SPACER") continue;
                if (string_pos(_ft, string_upper(_fitem.title)) == 1) {
                    array_push(opcode_finder_matches, {
                        title: _fitem.title,
                        type:  _fitem.type,
                        instructions: _fitem.instructions,
                        page:  _fpi
                    });
                }
            }
        }
        // Auto-jump to the page of the first match
        if (array_length(opcode_finder_matches) > 0) {
            var _target_page = opcode_finder_matches[0].page;
            if (shelf_page != _target_page) {
                shelf_page = _target_page;
            }
        }
    } else {
        opcode_finder_matches = [];
    }
}

// Click to activate
var _finder_hov = point_in_rectangle(gui_mouse_x, gui_mouse_y, _finder_x1, _finder_y1, _finder_x2, _finder_y2);
if (_finder_hov && mouse_check_button_pressed(mb_left)) {
    if (!opcode_finder_active) {
        opcode_finder_was_active = false;
    }
    opcode_finder_active = true;
}
// Click outside to deactivate
if (!_finder_hov && mouse_check_button_pressed(mb_left) && opcode_finder_active) {
    opcode_finder_active = false;
    opcode_finder_text   = "";
    opcode_finder_matches = [];
}

// Background
draw_set_color(opcode_finder_active ? make_color_rgb(20, 20, 40) : make_color_rgb(12, 12, 20));
draw_rectangle(_finder_x1, _finder_y1, _finder_x2, _finder_y2, false);
draw_set_color(opcode_finder_active ? c_aqua : make_color_rgb(60, 60, 80));
draw_rectangle(_finder_x1, _finder_y1, _finder_x2, _finder_y2, true);

// Label
draw_set_font(fnt_c64_tiny);
draw_set_color(make_color_rgb(100, 100, 140));
draw_set_halign(fa_left);
draw_text(_finder_x1 + 4, _finder_y1 + 2, "FIND OPCODE");

// Input text with blinker
draw_set_font(fnt_c64_code);
var _blink_cur = opcode_finder_active ? ((current_time mod 600 < 300) ? "|" : " ") : "";
var _finder_display = (opcode_finder_text == "" && !opcode_finder_active)
                    ? "TYPE TO SEARCH..."
                    : (opcode_finder_text + _blink_cur);
draw_set_color(opcode_finder_text == "" ? make_color_rgb(60, 60, 80) : c_yellow);
draw_text(_finder_x1 + 4, _finder_y1 + 13, _finder_display);

// Match count hint
if (opcode_finder_active && opcode_finder_text != "") {
    var _mc = array_length(opcode_finder_matches);
    draw_set_font(fnt_c64_tiny);
    draw_set_color(_mc == 0 ? c_red : (_mc == 1 ? c_lime : c_aqua));
    draw_set_halign(fa_right);
    draw_text(_finder_x2 - 2, _finder_y1 + 2, string(_mc) + " MATCH" + (_mc == 1 ? "" : "ES"));
    draw_set_halign(fa_left);
}



// Highlight matching buttons in the palette loop — done via a helper array
// The actual highlight is applied inside the palette draw loop below by checking
// if opcode_finder_matches contains the item title.

if point_in_rectangle(gui_mouse_x,gui_mouse_y,12,10,36,32)
	{
		draw_sprite(spr_exitIcon,badgeStyle,24,22)
			if mouse_check_button_pressed(mb_left)
		    {
			 scr_show_question("You may have unsaved changes.\nSave before closing?", "exit_confirm");
		    }	
	}
	
	
	
// NEW menu bar here V099.81 

draw_sprite(spr_menu_bar, paletteStyle, _sw_plus ,0)

// Combine the active page with common assets
var active_palette = array_concat(palette_page[shelf_page], common_assets);

//  HIT DETECTION LOOP (no drawing, just hover glow + click spawn)
var start_y    = 100;
var btn_h      = 26;
var pad        = 6;
var current_row = 0;
var col_index   = 0;
var shelf_cols = 3;
var col_w      = 86;
shelf_width    = (col_w * shelf_cols) - 20;


for (var i = 0; i < array_length(active_palette); i++) {
    var item = active_palette[i];

    // Track row/col position for SPACER and HEADER (needed for hit alignment)
    if (item.type == "SPACER") {
        col_index++;
        if (col_index >= shelf_cols) { col_index = 0; current_row++; }
        continue;
    }
    if (item.type == "HEADER") {
        if (col_index != 0) { current_row++; col_index = 0; }
        var _hdr_y = start_y + (current_row * (btn_h + pad));
        draw_set_font(fnt_C64_Angled);
        draw_set_halign(fa_center);
		draw_set_color(make_color_rgb(70, 40, 20));
        draw_text(10 + (col_w * shelf_cols * 0.5) - 6, _hdr_y + (btn_h * 0.5) - 2, item.title);
        draw_set_color(make_color_rgb(200, 80, 40));
        draw_text(10 + (col_w * shelf_cols * 0.5) - 6, _hdr_y + (btn_h * 0.5) - 3, item.title);
        draw_set_halign(fa_left);
        current_row++;
        continue;
    }

    var btn_x    = 7 + (col_index * col_w);
    var btn_y    = start_y + (current_row * (btn_h + pad));
    var btn_w    = col_w - 6;
    var is_hover = (gui_mouse_x > btn_x && gui_mouse_x < btn_x + btn_w &&
                    gui_mouse_y > btn_y && gui_mouse_y < btn_y + btn_h);

    // Check if this button is a finder match
    var _is_finder_match = false;
    if (opcode_finder_text != "") {
        for (var _fmi = 0; _fmi < array_length(opcode_finder_matches); _fmi++) {
            if (opcode_finder_matches[_fmi].title == item.title) {
                _is_finder_match = true;
                break;
            }
        }
    }

    // Button background sprite
    if (is_hover) {
        draw_sprite_ext(spr_opcode_button, buttonStyle+1, btn_x, btn_y, 1, 1, 0, c_white, 1);
    } else {
        draw_sprite_ext(spr_opcode_button, buttonStyle, btn_x, btn_y, 1, 1, 0, c_white, 1);
    }

    // Draw mnemonic label
    draw_set_font(fnt_c64_code);
    draw_set_halign(fa_center);
    draw_set_color((is_hover || _is_finder_match) ? c_yellow : c_white);
    draw_text(btn_x + btn_w * 0.5, btn_y + (btn_h * 0.5) - 6, item.title);
    draw_set_halign(fa_left);

    // Additive hover glow (hover or finder highlight)
    if (is_hover || _is_finder_match) {
        gpu_set_blendmode(bm_add);
        draw_sprite(spr_hover_glow, 0, btn_x + btn_w * 0.5, btn_y + btn_h * 0.5);
        gpu_set_blendmode(bm_normal);
    }
    // Finder pulse glow
    if (_is_finder_match && !is_hover) {
        var _pulse_scale = 1.0 + 0.2 * sin(degtorad(current_time * 0.4));
        var _pulse_alpha = 0.5 + 0.4 * sin(degtorad(current_time * 0.4));
        gpu_set_blendmode(bm_add);
        draw_set_alpha(_pulse_alpha);
        draw_sprite_ext(spr_hover_glow, 0,
            btn_x + btn_w * 0.5, btn_y + btn_h * 0.5,
            _pulse_scale, _pulse_scale,
            0, c_aqua, 1.0);
        draw_set_alpha(1.0);
        gpu_set_blendmode(bm_normal);
    }

    // Spawn on click
    if (is_hover && mouse_check_button_pressed(mb_left)  && !obj_workspace_manager.code_editor_open ) {
        var _n          = instance_create_layer(mouse_x, mouse_y, "Layer_Nodes", obj_c64_node);
        _n.node_title   = item.title;
        _n.node_type    = item.type;
        _n.instructions = variable_clone(item.instructions);
        _n.is_dragging  = true;
        _n.depth        = -2000;
		if (_n.node_type == "BITMAP_KLA") {
			 _n.pc_address = 0x6000; // standard KLA load address, MACRO_BITMAP will override
		} else if (_n.node_type == "SPR64") {
            _n.pc_address = 0x7000;
        } else if (string_pos("DATA", _n.node_type) > 0) {
            _n.pc_address = 0x1200;
        } else {
            _n.pc_address = global.start_pc;
        }
        with(_n) { event_user(0); }
    }

    // Opcode helper hover tracking
    if (opcode_helper_on && is_hover) {
        var _hkey = string_lower(string(item.instructions[0][0]));
        // Normalise palette aliases to short form used in scr_opcode_helper
        _hkey = string_replace_all(_hkey, "_zp_x",  "_zpx");
		
        _hkey = string_replace_all(_hkey, "_abs_x", "_abx");
        _hkey = string_replace_all(_hkey, "_abs_y", "_aby");
        _hkey = string_replace_all(_hkey, "_ind_x", "_izx");
        _hkey = string_replace_all(_hkey, "_ind_y", "_izy");
        _hkey = string_replace_all(_hkey, "_zp_y",  "_zpy");
        if (opcode_hover_key != _hkey) {
            opcode_hover_key   = _hkey;
            opcode_hover_timer = 0;
        } else {
            opcode_hover_timer++;
        }
    } else if (!is_hover && opcode_hover_key != "") {
        // Check no other button is hovered — reset handled below
    }

    col_index++;
    if (col_index >= shelf_cols) { col_index = 0; current_row++; }
}

// Reset hover if mouse not over any button
if (opcode_helper_on) {
    var _any_btn_hover = (gui_mouse_x >= 7 && gui_mouse_x < shelf_width &&
                          gui_mouse_y >= 100);
    if (!_any_btn_hover) {
        opcode_hover_key   = "";
        opcode_hover_timer = 0;
    }
}
/////////////////////////////////////////////////////////////////
///// 1. OPCODE SHELF (PAGING SYSTEM) ON TOP : PAGE
/////////////////////////////////////////////////////////////////


// PAGE SELECTOR ARROWS (Centered Origin Fix)
var p_count = 3; 
var p_gap   = 164;
var start_x = 8;
var arrow_w = sprite_get_width(spr_arrow);
var arrow_h = sprite_get_height(spr_arrow);
var py      = 45;

// Half offsets for Middle-Center origin math
var hw = arrow_w / 2;
var hh = arrow_h / 2;

// 1. LEFT ARROW (Back)
if (shelf_page > 0) {
    var lx = start_x + hw; // Shift X to account for centered origin
    var ly = py + hh;      // Shift Y to account for centered origin
    
    // Hover check needs to look at the full box around the center
    var l_hover = (gui_mouse_x >= lx - hw && gui_mouse_x < lx + hw &&
                   gui_mouse_y >= ly - hh && gui_mouse_y < ly + hh);
    
    var l_frame = 0;
	if paletteStyle>1 l_frame=2
    if (l_hover) {
 
        if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
            shelf_page--;
            global.addresses_dirty = true;
        }
    }
    // With centered origin, xscale -1 flips it perfectly in place!
    draw_sprite_ext(spr_arrow, l_frame+l_hover, lx, ly, -1, 1, 0, c_white, 1);
}



// 2. RIGHT ARROW (Next)
if (shelf_page < p_count - 1) {
    var rx = start_x + arrow_w + p_gap + hw; 
    var ry = py + hh;
    
    var r_hover = (gui_mouse_x >= rx - hw && gui_mouse_x < rx + hw &&
                   gui_mouse_y >= ry - hh && gui_mouse_y < ry + hh);
    
    var r_frame = 0;
	if paletteStyle>1 r_frame=2
    if (r_hover) {

        if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
            shelf_page++;
            global.addresses_dirty = true;
        }
    }
    draw_sprite(spr_arrow, r_frame+r_hover, rx, ry);
}

/////////////////////////////////////////////////////////////////
///// 1B. MACRO COLUMN — COMMENTED OUT (now in menu bar)
/////////////////////////////////////////////////////////////////

/////////////////////////////////////////////////////////////////
///// MENU BAR
/////////////////////////////////////////////////////////////////

var _mbar_y      = 2;
var _mbar_btn_w  = 179;
var _mbar_btn_h  = 42;
var _mbar_start_x = shelf_width + 60;
var _menuitems =7;
var _menu_labels = [
    "MACROS", "EXTRA", "VARS", "PROJECT", "OPTIONS", "DOCUMENTS", "IMPORT", "TBA"
];

// OPTIONS DROPDOWN (button 2)
if (gui_menu_open == 4) {
    var _opt_list = [
        { title: "HELPER MODE",     action: "HELPER"          },
        { title: "PALETTE HELPER",  action: "PALETTE_HELPER"  },
        { title: "GRID",            action: "GRID"            },
        { title: "EFFECTS",         action: "EFFECTS"         },
        { title: "COMMENTS",        action: "COMMENTS"        },
        { title: "FULLSCREEN",      action: "FULLSCREEN"      },
        { title: "ADVANCE THEME",   action: "THEME"           },
        { title: "RESET CUSTOM UI",    action: "RESET_UI"           },
        { title: "OPCODE HEADERS",     action: "OPCODE_HEADERS"     },
		{ title: "OPCODE COMPACT",     action: "OPCODE_EXTRA_H"     },
		
    ];
    var _item_h_o   = 20;
    var _panel_w_o  = 220;
    var _mbar_btn_gap_o = _mbar_btn_w + 4;
    var _panel_x_o  = _mbar_start_x + (4 * _mbar_btn_gap_o);
    var _panel_y_o  = _mbar_btn_h;
    var _panel_h_o  = array_length(_opt_list) * _item_h_o + 28;

    draw_sprite_stretched(spr_glassSlice, 0,
                          _panel_x_o, _panel_y_o,
                          _panel_w_o, _panel_h_o);

    draw_set_font(fnt_C64_Angled);

    for (var _oi = 0; _oi < array_length(_opt_list); _oi++) {
        var _op   = _opt_list[_oi];
        var _iy   = _panel_y_o + 20 + (_oi * _item_h_o);
        var _ix1  = _panel_x_o;
        var _ix2  = _panel_x_o + _panel_w_o;
        var _ihov = (gui_mouse_x >= _ix1 && gui_mouse_x < _ix2 &&
                     gui_mouse_y >= _iy   && gui_mouse_y < _iy + _item_h_o);

        if (_ihov) {
            draw_set_alpha(0.35);
            draw_set_color(c_white);
            draw_rectangle(_ix1 + 4, _iy, _ix2 - 4, _iy + _item_h_o, false);
            draw_set_alpha(1.0);
        }

        draw_set_color(_ihov ? c_yellow : c_white);
        draw_set_halign(fa_left);
        draw_text(_ix1 + 10, _iy + 3, _op.title);

        // State indicator on right
        var _state_str = "";
        var _state_col = c_gray;
        if (_op.action == "HELPER") {
            _state_str = opcode_helper_on ? "ON" : "OFF";
            _state_col = opcode_helper_on ? c_lime : c_red;
        }
        if (_op.action == "PALETTE_HELPER") {
            _state_str = showPaletteHelper ? "ON" : "OFF";
            _state_col = showPaletteHelper ? c_lime : c_red;
        }
        if (_op.action == "GRID") {
            _state_str = showGrid ? "ON" : "OFF";
            _state_col = showGrid ? c_lime : c_red;
        }
        if (_op.action == "EFFECTS") {
            _state_str = global.visual_fx ? "ON" : "OFF";
            _state_col = global.visual_fx ? c_lime : c_red;
        }
        if (_op.action == "COMMENTS") {
            _state_str = global.comments_visible ? "ON" : "OFF";
            _state_col = global.comments_visible ? c_lime : c_red;
        }
        if (_op.action == "FULLSCREEN") {
            _shortcut_str = "F10";
        }
        if (_op.action == "OPCODE_HEADERS") {
            _state_str = opcode_headers_on ? "ON" : "OFF";
            _state_col = opcode_headers_on ? c_lime : c_red;
        }
		if (_op.action == "OPCODE_EXTRA_H") {
            _state_str = opcode_extra_height ? "OFF" : "ON";
            _state_col = opcode_extra_height ? c_red : c_lime;
			
        }
		
		
		
        if (_op.action == "THEME") {
            var _theme_labels = ["1", "2", "3", "4"];
            _state_str = _theme_labels[paletteStyle mod 4];
            _state_col = make_color_rgb(160, 160, 220);
        }
        if (_state_str != "") {
            draw_set_halign(fa_right);
            draw_set_color(_state_col);
            draw_text(_ix2 - 8, _iy + 3, _state_str);
            draw_set_halign(fa_left);
        }
        if (_op.action == "FULLSCREEN") {
            draw_set_halign(fa_right);
            draw_set_color(make_color_rgb(120, 120, 120));
            draw_text(_ix2 - 8, _iy + 3, "F10");
            draw_set_halign(fa_left);
        }

        

        if (_ihov && mouse_check_button_pressed(mb_left)) {
            gui_menu_open = -1;
            if (_op.action == "HELPER") {
                opcode_helper_on = !opcode_helper_on;
            }
            else if (_op.action == "PALETTE_HELPER") {
                showPaletteHelper = !showPaletteHelper;
            }
            else if (_op.action == "GRID") {
                showGrid = !showGrid;
            }
            else if (_op.action == "EFFECTS") {
                global.visual_fx       = !global.visual_fx;
                global.node_destroy_fx = global.visual_fx;
            }
            else if (_op.action == "COMMENTS") {
                global.comments_visible = !global.comments_visible;
            }
            else if (_op.action == "FULLSCREEN") {
                do_windowSizing();
            }
            else if (_op.action == "THEME") {
                paletteStyle++;
                if (paletteStyle > sprite_get_number(spr_bkg) - 1) {
                    paletteStyle = 0;
                }
                badgeStyle = 0;
                if (paletteStyle > 1) {
                    badgeStyle = 1;
                }
                buttonStyle = 0;
                if (paletteStyle > 1) {
                    buttonStyle = 2;
                }
                bkgImg++;
                if (bkgImg > sprite_get_number(spr_bkg) - 1) {
                    bkgImg = 0;
                }
                niceSliceFrm++;
            }
            else if (_op.action == "OPCODE_HEADERS") {
                opcode_headers_on = !opcode_headers_on;
            }
			else if (_op.action == "OPCODE_EXTRA_H") {
                opcode_extra_height = !opcode_extra_height;
				with (obj_c64_node) {
				    height_dirty = true;
				}
            }
			
            else if (_op.action == "RESET_UI") {
                niceSliceFrm = 0;
                bkgImg       = 0;
                paletteStyle = 0;
                buttonStyle  = 0;
            }
        }
    }

    var _in_panel_o = (gui_mouse_x >= _panel_x_o && gui_mouse_x < _panel_x_o + _panel_w_o &&
                       gui_mouse_y >= _panel_y_o  && gui_mouse_y < _panel_y_o + _panel_h_o);
    var _in_bar_o   = (gui_mouse_y >= _mbar_y && gui_mouse_y < _mbar_y + _mbar_btn_h);
    if (mouse_check_button_pressed(mb_left) && !_in_panel_o && !_in_bar_o) {
        gui_menu_open = -1;
    }
}

var _mbar_btn_gap = _mbar_btn_w + 4;

/////////////////////////////////////////////////////////////////
///// EXTRA DROPDOWN (button 1) — only available outside LITE mode
/////////////////////////////////////////////////////////////////
if (gui_menu_open == 1 && !global.lite) {

    var _extra_list = [
        { title: "IRQ",              type: "MACRO_IRQ"           },
        { title: "IRQ SHELL",        type: "MACRO_IRQ_HANDLER"   },
        { title: "CODE (ALT+C)",     type: "MACRO_CODE"          },
        { title: "MOVE MEM",         type: "MACRO_MOVE_MEM"      },
        { title: "MOVE BMP BLK",     type: "MACRO_MOVE_BMP_BLOCK"},
        { title: "BANK SWITCH",      type: "BANK_SWITCH"         },
        { title: "MATH",             type: "MACRO_MATH"          },
        { title: "RANDOM",           type: "MACRO_RANDOM"        },
    ];

    var _item_h_e     = 19;
    var _panel_w_e    = 200;
    var _slice_top_e  = 20;
    var _slice_bot_e  = 20;
    var _mbar_btn_gap_e = _mbar_btn_w + 4;
    var _panel_x_e    = _mbar_start_x + (1 * _mbar_btn_gap_e);
    var _panel_y_e    = _mbar_btn_h;
    var _panel_h_e    = array_length(_extra_list) * _item_h_e + _slice_top_e + _slice_bot_e;

    draw_sprite_stretched(spr_glassSlice, 0,
                          _panel_x_e, _panel_y_e,
                          _panel_w_e, _panel_h_e);

    draw_set_font(fnt_C64_Angled);

    for (var _ei = 0; _ei < array_length(_extra_list); _ei++) {
        var _ep   = _extra_list[_ei];
        var _iy   = _panel_y_e + _slice_top_e + (_ei * _item_h_e);
        var _ix1  = _panel_x_e;
        var _ix2  = _panel_x_e + _panel_w_e;
        var _ihov = (gui_mouse_x >= _ix1 && gui_mouse_x < _ix2 &&
                     gui_mouse_y >= _iy   && gui_mouse_y < _iy + _item_h_e);

        if (_ihov) {
            draw_set_alpha(0.35);
            draw_set_color(c_white);
            draw_rectangle(_ix1 + 4, _iy, _ix2 - 4, _iy + _item_h_e, false);
            draw_set_alpha(1.0);
        }

        draw_set_color(_ihov ? c_yellow : c_white);
        draw_set_halign(fa_left);
        draw_text(_ix1 + 10, _iy + 3, _ep.title);

        if (_ihov && mouse_check_button_pressed(mb_left)) {
            gui_menu_open         = -1;
            gui_menu_drag_active  = true;
            gui_menu_node_spawned = false;
            gui_menu_drag_type    = _ep.type;
            gui_menu_drag_title   = _ep.title;
        }
    }

    var _in_panel_e = (gui_mouse_x >= _panel_x_e && gui_mouse_x < _panel_x_e + _panel_w_e &&
                       gui_mouse_y >= _panel_y_e  && gui_mouse_y < _panel_y_e + _panel_h_e);
    var _in_bar_e   = (gui_mouse_y >= _mbar_y && gui_mouse_y < _mbar_y + _mbar_btn_h);
    if (mouse_check_button_pressed(mb_left) && !_in_panel_e && !_in_bar_e) {
        gui_menu_open = -1;
    }
}

/////////////////////////////////////////////////////////////////
///// VARS DROPDOWN (button 2)
/////////////////////////////////////////////////////////////////
if (gui_menu_open == 2) {

    var _vars_list = [
        { title: "IF BYTE",     type: "COND_IF"             },
		{ title: "IF WORD",     type: "COND_IF_WORD"        },
		{ title: "GET VAR",		type: "GET_VAR"             },
        { title: "SET VAR",      type: "SET_VAR"        },
        { title: "COPY VAR",     type: "COPY_VAR"       },
        { title: "INC VAR",      type: "INC_VAR"        },
        { title: "DEC VAR",      type: "DEC_VAR"        },
        { title: "--- CREATE ---", type: "HEADER"       },
        { title: "NEW BYTE",     type: "NEW_UV_BYTE"    },
        { title: "NEW SBYTE",    type: "NEW_UV_SBYTE"   },
        { title: "NEW WORD",     type: "NEW_UV_WORD"    },
        { title: "NEW BCD",      type: "NEW_UV_BCD"     },
        { title: "NEW STR",      type: "NEW_STR"        },
    ];

    var _item_h_v   = 20;
    var _panel_w_v  = 200;
    var _slice_top_v = 20;
    var _slice_bot_v = 20;
    var _mbar_btn_gap_v = _mbar_btn_w + 4;
    var _panel_x_v  = _mbar_start_x + (2 * _mbar_btn_gap_v);
    var _panel_y_v  = _mbar_btn_h;
    var _panel_h_v  = array_length(_vars_list) * _item_h_v + _slice_top_v + _slice_bot_v;

    draw_sprite_stretched(spr_glassSlice, 0,
                          _panel_x_v, _panel_y_v,
                          _panel_w_v, _panel_h_v);

    draw_set_font(fnt_C64_Angled);

    for (var _vi = 0; _vi < array_length(_vars_list); _vi++) {
        var _vp   = _vars_list[_vi];
        var _iy   = _panel_y_v + _slice_top_v + 4 + (_vi * _item_h_v);
        var _ix1  = _panel_x_v;
        var _ix2  = _panel_x_v + _panel_w_v;
        var _ihov = (gui_mouse_x >= _ix1 && gui_mouse_x < _ix2 &&
                     gui_mouse_y >= _iy   && gui_mouse_y < _iy + _item_h_v);

        if (_ihov) {
            draw_set_alpha(0.35);
            draw_set_color(c_white);
            draw_rectangle(_ix1 + 4, _iy, _ix2 - 4, _iy + _item_h_v, false);
            draw_set_alpha(1.0);
        }

        draw_set_color(_ihov ? c_yellow : c_white);
        draw_set_halign(fa_left);
        draw_text(_ix1 + 10, _iy + 3, _vp.title);

        if (_ihov && mouse_check_button_pressed(mb_left)) {
            gui_menu_open         = -1;
            gui_menu_drag_active  = true;
            gui_menu_node_spawned = false;
            gui_menu_drag_type    = _vp.type;
            gui_menu_drag_title   = _vp.title;
        }
    }

    var _in_panel_v = (gui_mouse_x >= _panel_x_v && gui_mouse_x < _panel_x_v + _panel_w_v &&
                       gui_mouse_y >= _panel_y_v  && gui_mouse_y < _panel_y_v + _panel_h_v);
    var _in_bar_v   = (gui_mouse_y >= _mbar_y && gui_mouse_y < _mbar_y + _mbar_btn_h);
    if (mouse_check_button_pressed(mb_left) && !_in_panel_v && !_in_bar_v) {
        gui_menu_open = -1;
    }
}

// --- Draw menu buttons ---
for (var _bi = 0; _bi < _menuitems; _bi++) {
    var _bx    = _mbar_start_x + (_bi * _mbar_btn_gap);
    var _by    = _mbar_y;
    var _bopen = (gui_menu_open == _bi);
    var _bdisabled = (_bi == 1 && global.lite);

    draw_sprite_ext(spr_menu_button, paletteStyle,
                    _bx, _by, 1, 1, 0, c_white, 1);

    var _bhover = (!_bdisabled &&
                   gui_mouse_x >= _bx && gui_mouse_x < _bx + _mbar_btn_w &&
                   gui_mouse_y >= _by && gui_mouse_y < _by + _mbar_btn_h);
    if (_bhover || _bopen) {
        gpu_set_blendmode(bm_add);
        draw_sprite_ext(spr_menu_button, paletteStyle,
                        _bx, _by, 1, 1, 0, c_white, 0.2);
        gpu_set_blendmode(bm_normal);
    }

    draw_set_font(fnt_C64_Angled);
    draw_set_halign(fa_center);
    draw_set_color(_bdisabled ? make_color_rgb(90, 90, 90) : (_bopen ? c_yellow : c_white));
    draw_text(_bx + _mbar_btn_w * 0.5, _by + _mbar_btn_h * 0.5 - 6, _menu_labels[_bi]);
    draw_set_halign(fa_left);

    // Click to toggle
    if (_bhover && mouse_check_button_pressed(mb_left)) {
        if (gui_menu_open == _bi) {
            gui_menu_open = -1;
        } else {
            gui_menu_open = _bi;
        }
    }
}

/////////////////////////////////////////////////////////////////
///// PROJECT DROPDOWN (button 3)
/////////////////////////////////////////////////////////////////
if (gui_menu_open == 3) {

    var _proj_list = [
        { title: "LOAD",            action: "LOAD"            },
        { title: "SAVE",            action: "SAVE"            },
        { title: "SAVE AS",         action: "SAVE_AS"         },
        { title: "AUTOSAVE MODE",   action: "AUTOSAVE"        },
        { title: "--- BUILD ---",   action: "HEADER"          },
        { title: "CLEANUP",         action: "CLEANUP"         },
        { title: "ASSEMBLY DUMP",   action: "DUMP"            },
        { title: "EXPORT .PRG/.D64", action: "EXPORT"          },
        { title: "BUILD & RUN",     action: "BUILD"           },
        { title: "RUN ON ULTIMATE", action: "C64U"            },
        { title: "RESET C64U IP",   action: "C64U_RESET"      },
        { title: "--- DANGER ---",  action: "HEADER"          },
        { title: "RESET/CLEAR",     action: "RESET"           },
		{ title: "OPEN AUTOSAVES",  action: "OPEN_AUTOSAVES"  },
    ];

    var _item_h_p   = 20;
    var _panel_w_p  = 220;
    var _mbar_btn_gap = _mbar_btn_w + 4;
    var _panel_x_p  = _mbar_start_x + (3 * _mbar_btn_gap);
    var _panel_y_p  = _mbar_btn_h;
    var _panel_h_p  = array_length(_proj_list) * _item_h_p + 28;

    draw_sprite_stretched(spr_glassSlice, 0,
                          _panel_x_p, _panel_y_p,
                          _panel_w_p, _panel_h_p);

    draw_set_font(fnt_C64_Angled);

    for (var _pi = 0; _pi < array_length(_proj_list); _pi++) {
        var _pp   = _proj_list[_pi];
        var _iy   = _panel_y_p + 20 + (_pi * _item_h_p);
        var _ix1  = _panel_x_p;
        var _ix2  = _panel_x_p + _panel_w_p;
        var _ihov = (_pp.action != "HEADER" &&
                     gui_mouse_x >= _ix1 && gui_mouse_x < _ix2 &&
                     gui_mouse_y >= _iy   && gui_mouse_y < _iy + _item_h_p);

        if (_ihov) {
            draw_set_alpha(0.35);
            draw_set_color(c_white);
            draw_rectangle(_ix1 + 4, _iy, _ix2 - 4, _iy + _item_h_p, false);
            draw_set_alpha(1.0);
        }

        if (_pp.action == "HEADER") {
            draw_set_color(make_color_rgb(220, 140, 40));
        } else {
            draw_set_color(_ihov ? c_yellow : c_white);
        }
        draw_set_halign(fa_left);
        if (_pp.action == "AUTOSAVE") {
            var _as_title_labels = ["3 MIN", "5 MIN", "10 MIN", "OFF"];
            var _as_title_cols   = [
                make_color_rgb(220, 100, 40),
                make_color_rgb(60,  200, 80),
                make_color_rgb(40,  220, 220),
                make_color_rgb(120, 120, 120)
            ];
            draw_text(_ix1 + 10, _iy + 3, "AUTOSAVE");
            draw_set_color(_as_title_cols[global.autosave_mode]);
            draw_text(_ix1 + 10 + string_width("AUTOSAVE "), _iy + 3, _as_title_labels[global.autosave_mode]);
        } else {
            draw_text(_ix1 + 10, _iy + 3, _pp.title);
        }

        // Right-justified shortcut hint
        if (_pp.action != "HEADER") {
            var _shortcut = "";
            if (_pp.action == "SAVE")       { _shortcut = "CTRL+S";       }
            else if (_pp.action == "LOAD")  { _shortcut = "CTRL+L";       }
            else if (_pp.action == "SAVE_AS") { _shortcut = "CTRL+SHFT+S"; }
            else if (_pp.action == "BUILD")      { _shortcut = "F5";     }
            else if (_pp.action == "DUMP")       { _shortcut = "F2";     }
            else if (_pp.action == "EXPORT")     { _shortcut = "F4";     }
            else if (_pp.action == "C64U")       { _shortcut = "F6";     }
            else if (_pp.action == "C64U_RESET") { _shortcut = "F8";     }
            else if (_pp.action == "CLEANUP")    { _shortcut = "F1";     }
            else if (_pp.action == "COMMENTS")   { _shortcut = "F3";     }
            else if (_pp.action == "AUTOSAVE") {
                var _as_mode_labels = ["3 MIN", "5 MIN", "10 MIN", "OFF"];
                _shortcut = "F7";
                draw_set_halign(fa_right);
                draw_set_color(make_color_rgb(120, 120, 120));
                draw_text(_ix2 - 8, _iy + 3, _shortcut);
                draw_set_halign(fa_left);
                _shortcut = "";
            }

            if (_shortcut != "") {
                draw_set_halign(fa_right);
                draw_set_color(make_color_rgb(120, 120, 120));
                draw_text(_ix2 - 8, _iy + 3, _shortcut);
                draw_set_halign(fa_left);
            }
        }

        if (_ihov && mouse_check_button_pressed(mb_left)) {
            gui_menu_open = -1;
            switch (_pp.action) {
                case "SAVE":
                    global.isSaving = true;
                    save_pending    = true;
                    break;
                case "LOAD":
                    scr_load_workspace_dialog();
                    break;
                case "SAVE_AS":
                    scr_save_workspace_as();
                    break;
                case "BUILD":
                    execute_shell_simple("taskkill", "/f /im x64sc.exe");
                    trigger_build = true;
                    break;
                case "DUMP":
                    silent_build  = true;
                    pending_dump  = true;
                    trigger_build = true;
                    break;
                case "EXPORT":
                    // A connected MACRO_LOADER, MACRO_SAVE_GAME, or MACRO_LOAD_GAME
                    // forces a .d64 build (no .prg dialog). The F4 handler detects
                    // this and writes program.d64 to export_dir.
                    var _menu_has_loader = false;
                    with (obj_c64_node) {
                        if ((node_type == "MACRO_LOADER" || node_type == "MACRO_SAVE_GAME" || node_type == "MACRO_LOAD_GAME") && is_connected) {
                            _menu_has_loader = true;
                        }
                    }
                    if (_menu_has_loader) {
                        var _d64_path_menu = get_save_filename("C64 Disk Image|*.d64", "program");
                        if (_d64_path_menu != "") {
                            if (string_lower(filename_ext(_d64_path_menu)) != ".d64") {
                                _d64_path_menu += ".d64";
                            }
                            pending_export_path = _d64_path_menu;
                            trigger_export      = true;
                        }
                    } else {
                        var _export_path = get_save_filename("C64 Program|*.prg", "export");
                        if (_export_path != "") {
                            if (string_lower(filename_ext(_export_path)) != ".prg") {
                                _export_path += ".prg";
                            }
                            pending_export_path = _export_path;
                            trigger_export      = true;
                        }
                    }
                    break;
                case "C64U":
                    if (global.c64u_ip == "") {
                        global.c64u_overlay_active = true;
                        global.c64u_overlay_text   = "";
                        global.c64u_overlay_error  = "";
                        global.c64u_overlay_after  = "send_prg";
                        global.canEditNode         = 0;
                        keyboard_string            = "";
                        keyboard_clear(vk_anykey);
                    } else {
                        trigger_c64u  = true;
                        trigger_build = true;
                    }
                    break;
                case "C64U_RESET":
                    scr_c64u_reset_ip();
                    break;
                case "CLEANUP":
                    scr_cleanup_nodes();
                    scr_c64_update_addresses();
                    break;
                case "COMMENTS":
                    global.comments_visible = !global.comments_visible;
                    break;
                case "AUTOSAVE":
                    global.autosave_mode = (global.autosave_mode + 1) mod 4;
                    var _ivs = [180, 300, 600, -1];
                    global.autosave_interval = _ivs[global.autosave_mode];
                    ini_open("c64devmachine.ini");
                    ini_write_real("autosave", "mode", global.autosave_mode);
                    ini_close();
                    var _next_iv = (global.autosave_mode != 3) ? global.autosave_interval : 9999;
                    alarm[4]           = game_get_speed(gamespeed_fps) * _next_iv;
                    autosave_countdown = _next_iv;
                    break;
                case "RESET":
                    game_restart();
                    break;
                case "OPEN_AUTOSAVES":
                    if (os_type == os_macosx) {
                        var _dir = working_directory + "autosave/";
                        if (!directory_exists(_dir)) directory_create(_dir);
                        execute_shell_simple("open", "\"" + _dir + "\"");
                    } else {
                        var _dir = working_directory + "autosave\\";
                        if (!directory_exists(_dir)) directory_create(_dir);
                        execute_shell_simple("explorer", "\"" + _dir + "\"");
                    }
                    break;
            }
        }
    }

    var _in_panel_p = (gui_mouse_x >= _panel_x_p && gui_mouse_x < _panel_x_p + _panel_w_p &&
                       gui_mouse_y >= _panel_y_p  && gui_mouse_y < _panel_y_p + _panel_h_p);
    var _in_bar_p   = (gui_mouse_y >= _mbar_y && gui_mouse_y < _mbar_y + _mbar_btn_h);
    if (mouse_check_button_pressed(mb_left) && !_in_panel_p && !_in_bar_p) {
        gui_menu_open = -1;
    }
}

/////////////////////////////////////////////////////////////////
///// DOCUMENTS DROPDOWN (button 5)
/////////////////////////////////////////////////////////////////
if (gui_menu_open == 5) {

    var _docs_list = [
        { title: "MANUAL",          url: "https://drive.google.com/file/d/1r-8fDv_DVx3g08g__E_lPZacmAgLBtsL/view?usp=sharing" }, // link under here
		{ title: "ITCH PAGE",			url: "https://polytricity.itch.io/the-c64-dev-machine" }, // link under here	
		{ title: "TUTORIALS",			url: "https://www.youtube.com/playlist?list=PLDwNUwlf8I7ejOY_kKW8uw60fUdK0YqU7" }, // link under here	
        { title: "--- REFS ---",    url: "HEADER" },
        { title: "C64 REGS WHITE",  url: "https://drive.google.com/file/d/1y8oW2eHtnjbsFUZ565K7qgD6iHuuqCUt/view?usp=drive_link" }, // link under here
        { title: "C64 REGS DARK",   url: "https://drive.google.com/file/d/1eGlAyC0saqDGNFNy73AbMyd5RozhyPKA/view?usp=drive_link" }, // link under here
        { title: "OPCODES WHITE",   url: "https://drive.google.com/file/d/1rW5vsqQpfmWgjt4899TVSSfv9a3WDWud/view?usp=drive_link" }, // link under here
        { title: "OPCODES DARK",    url: "https://drive.google.com/file/d/1kY_uqzc8J1rMjgW1K0dt5JhTeITqrO0b/view?usp=drive_link" }, // link under here
        { title: "GLOSS WHITE",     url: "https://drive.google.com/file/d/1ZQmRr0wzzCijig-zR7I9cOfg7DRQaIDG/view?usp=drive_link" }, // link under here
        { title: "GLOSS DARK",      url: "https://drive.google.com/file/d/1k_OaDIK1II1-M7eJ2JJrWMJOVPGEmE_z/view?usp=drive_link" }, // link under here
		{ title: "HELPER PAGE",			url: "https://robram78.github.io/C64_HELPER/" }, // link under here
		{ title: "HELPER V2+C64U",			url: "https://robram78.github.io/C64_HELPER/u64_registers.html" }, // link under here		
		
    ];

    var _item_h_d   = 20;
    var _panel_w_d  = 220;
    var _mbar_btn_gap_d = _mbar_btn_w + 4;
    var _panel_x_d  = _mbar_start_x + (5 * _mbar_btn_gap_d);
    var _panel_y_d  = _mbar_btn_h;
    var _panel_h_d  = array_length(_docs_list) * _item_h_d + 28;

    draw_sprite_stretched(spr_glassSlice, 0,
                          _panel_x_d, _panel_y_d,
                          _panel_w_d, _panel_h_d);

    draw_set_font(fnt_C64_Angled);

    for (var _di = 0; _di < array_length(_docs_list); _di++) {
        var _dp   = _docs_list[_di];
        var _iy   = _panel_y_d + 20 + (_di * _item_h_d);
        var _ix1  = _panel_x_d;
        var _ix2  = _panel_x_d + _panel_w_d;
        var _ihov = (_dp.url != "HEADER" &&
                     gui_mouse_x >= _ix1 && gui_mouse_x < _ix2 &&
                     gui_mouse_y >= _iy   && gui_mouse_y < _iy + _item_h_d);

        if (_ihov) {
            draw_set_alpha(0.35);
            draw_set_color(c_white);
            draw_rectangle(_ix1 + 4, _iy, _ix2 - 4, _iy + _item_h_d, false);
            draw_set_alpha(1.0);
        }

        if (_dp.url == "HEADER") {
            draw_set_color(make_color_rgb(220, 140, 40));
        } else {
            draw_set_color(_ihov ? c_yellow : c_white);
        }
        draw_set_halign(fa_left);
        draw_text(_ix1 + 10, _iy + 3, _dp.title);

        if (_ihov && mouse_check_button_pressed(mb_left)) {
            gui_menu_open = -1;
            if (_dp.url != "") {
                url_open(_dp.url);
            }
        }
    }

    var _in_panel_d = (gui_mouse_x >= _panel_x_d && gui_mouse_x < _panel_x_d + _panel_w_d &&
                       gui_mouse_y >= _panel_y_d  && gui_mouse_y < _panel_y_d + _panel_h_d);
    var _in_bar_d   = (gui_mouse_y >= _mbar_y && gui_mouse_y < _mbar_y + _mbar_btn_h);
    if (mouse_check_button_pressed(mb_left) && !_in_panel_d && !_in_bar_d) {
        gui_menu_open = -1;
    }
}

/////////////////////////////////////////////////////////////////
///// IMPORT DROPDOWN (button 6)
/////////////////////////////////////////////////////////////////
if (gui_menu_open == 6) {

    var _imp_list = [
        { title: "CHARPAD (RAW)",  action: "CHARPAD_RAW" },
        { title: "CHARPAD (.CTM)", action: "CHARPAD_CTM" },
    ];
	
    var _item_h_i   = 20;
    var _panel_w_i  = 220;
    var _mbar_btn_gap_i = _mbar_btn_w + 4;
    var _panel_x_i  = _mbar_start_x + (6 * _mbar_btn_gap_i);
    var _panel_y_i  = _mbar_btn_h;
    var _panel_h_i  = array_length(_imp_list) * _item_h_i + 28;

    draw_sprite_stretched(spr_glassSlice, 0,
                          _panel_x_i, _panel_y_i,
                          _panel_w_i, _panel_h_i);

    draw_set_font(fnt_C64_Angled);

    for (var _ii = 0; _ii < array_length(_imp_list); _ii++) {
        var _ip   = _imp_list[_ii];
        var _iy   = _panel_y_i + 20 + (_ii * _item_h_i);
        var _ix1  = _panel_x_i;
        var _ix2  = _panel_x_i + _panel_w_i;
        var _ihov = (gui_mouse_x >= _ix1 && gui_mouse_x < _ix2 &&
                     gui_mouse_y >= _iy   && gui_mouse_y < _iy + _item_h_i);

        if (_ihov) {
            draw_set_alpha(0.35);
            draw_set_color(c_white);
            draw_rectangle(_ix1 + 4, _iy, _ix2 - 4, _iy + _item_h_i, false);
            draw_set_alpha(1.0);
        }

        draw_set_color(_ihov ? c_yellow : c_white);
        draw_set_halign(fa_left);
        draw_text(_ix1 + 10, _iy + 3, _ip.title);

        if (_ihov && mouse_check_button_pressed(mb_left)) {
            gui_menu_open = -1;
            if (_ip.action == "CHARPAD_RAW") {
                scr_import_charpad_raw();
            }
            else if (_ip.action == "CHARPAD_CTM") {
                scr_import_charpad_ctm();
            }
        }
    }

    var _in_panel_i = (gui_mouse_x >= _panel_x_i && gui_mouse_x < _panel_x_i + _panel_w_i &&
                       gui_mouse_y >= _panel_y_i  && gui_mouse_y < _panel_y_i + _panel_h_i);
    var _in_bar_i   = (gui_mouse_y >= _mbar_y && gui_mouse_y < _mbar_y + _mbar_btn_h);
    if (mouse_check_button_pressed(mb_left) && !_in_panel_i && !_in_bar_i) {
        gui_menu_open = -1;
    }
}


/////////////////////////////////////////////////////////////////
///// MACRO DROPDOWN (button 0)
/////////////////////////////////////////////////////////////////
if (gui_menu_open == 0) {

    // ---- Build macro list (same order as old column) ----
    var _mac_list = [
        { title: "VIC",          type: "MACRO_VIC"           },
        { title: "PRINT",        type: "MACRO_PRINT"         },
        { title: "PRINT EXT",    type: "MACRO_PRINT_EXT"     },
        { title: "PLACE CHAR",   type: "MACRO_PLACE_CHAR"    },
		{ title: "GET CHAR",     type: "MACRO_GET_CHAR"      },
        { title: "CLR SCRN RAM", type: "MACRO_CLR_SCREEN"    },
        { title: "CLR BMP RECT", type: "MACRO_CLEAR_BMP_RECT" },
        { title: "VWAIT (ALT+V)",        type: "MACRO_VWAIT"         },
        { title: "WAIT",         type: "MACRO_WAIT"          },
        { title: "DISPLAY",      type: "MACRO_DISPLAY"       },
        { title: "TXT SCROLL",   type: "MACRO_TEXT_SCROLL"   },
        { title: "CHARSET",      type: "MACRO_CHR"           },
        { title: "MAP",          type: "MACRO_MAP"           },
		{ title: "METAMAP",      type: "MACRO_METAMAP"       },
		{ title: "MAP SWITCH",   type: "MACRO_MAP_SWITCH"    },
        { title: "MAP H-SCROLL", type: "MACRO_SCROLL"        },
		
        { title: "BITMAP",       type: "MACRO_BMP"           },
		{ title: "VECTOR BMP",   type: "MACRO_VECTOR_BMP"    },
		{ title: "VECTOR PAGE",  type: "MACRO_VECTOR_PAGE"   },
		{ title: "JOYSTICK (ALT+J)",     type: "MACRO_JOY"           },
        { title: "--- SPRITES ---", type: "HEADER"           },
        { title: "SPRITE",       type: "MACRO_SPR"           },
        { title: "MOVE (ALT+M)",         type: "MACRO_MOVE"          },
        { title: "SEEK",         type: "MACRO_SEEK"          },
        { title: "COLLIDE",      type: "MACRO_COLLISION"     },
        { title: "COLL.ADV",     type: "MACRO_COLL_ADV"      },
        { title: "PRIORITY",     type: "MACRO_PRIORITY"      },
        { title: "ENABLER",      type: "MACRO_SPR_ENABLE"    },
        { title: "EXPANDER",     type: "MACRO_SPR_EXPAND"    },
        { title: "ANIMATE",      type: "MACRO_ANIM"          },
        { title: "FLIP X",       type: "MACRO_FLIP_X"        },
        { title: "--- SOUND ---", type: "HEADER"              },
        { title: "SID",          type: "MACRO_SID"           },
        { title: "TRACK",        type: "MACRO_TRACK"         },
        { title: "SFX",          type: "MACRO_SFX"           },
		{ title: "SID SOUND",    type: "MACRO_SID_SOUND"     },
        { title: "SID SONG",     type: "MACRO_SID_SONG"      },
        { title: "--- DISK ---",  type: "HEADER"              },
        { title: "LOADER",       type: "MACRO_LOADER"        },
        { title: "SAVE GAME",    type: "MACRO_SAVE_GAME"     },
        { title: "LOAD GAME",    type: "MACRO_LOAD_GAME"     },
    ];

// ---- 9-slice panel geometry ----
    var _item_h     = 19;
    var _panel_w    = 200;
    var _slice_top  = 20;
    var _slice_bot  = 20;
    var _mbar_btn_gap = _mbar_btn_w + 4;
    var _panel_x    = _mbar_start_x;           // aligns with MACROS button
    var _panel_y    = _mbar_btn_h;             // sits just below the menu bar
    var _panel_h    = array_length(_mac_list) * _item_h + _slice_top + _slice_bot;

    // Draw spr_glassSlice using nine-slice stretching
    draw_sprite_stretched(spr_glassSlice, 0,
                          _panel_x, _panel_y,
                          _panel_w, _panel_h);

    // ---- Draw items & handle hover + drag ----
    draw_set_font(fnt_C64_Angled);
    hover_macro_type  = "";
    hover_macro_title = "";

    for (var _mi = 0; _mi < array_length(_mac_list); _mi++) {
        var _mp   = _mac_list[_mi];
        var _iy   = _panel_y + _slice_top + (_mi * _item_h);
        var _ix1  = _panel_x;
        var _ix2  = _panel_x + _panel_w;
        var _ihov = (string_pos("HEADER", _mp.type) == 0 &&
                     gui_mouse_x >= _ix1 && gui_mouse_x < _ix2 &&
                     gui_mouse_y >= _iy   && gui_mouse_y < _iy + _item_h);

        if (_ihov) {
            hover_macro_type  = _mp.type;
            hover_macro_title = _mp.title;
        }

        // Row background on hover
        if (_ihov) {
            draw_set_alpha(0.35);
            draw_set_color(c_white);
            draw_rectangle(_ix1 + 4, _iy, _ix2 - 4, _iy + _item_h, false);
            draw_set_alpha(1.0);
        }

        // Text
        if (_mp.type == "HEADER") {
            draw_set_color(make_color_rgb(220, 140, 40));
        } else {
            draw_set_color(_ihov ? c_yellow : c_white);
        }
        draw_set_halign(fa_left);
        draw_text(_ix1 + 10, _iy + 3, _mp.title);

        // Begin drag on mouse-down (no release needed — matches existing macro drag behaviour)
        if (_ihov && mouse_check_button_pressed(mb_left)) {
            gui_menu_open         = -1;
            gui_menu_drag_active  = true;
            gui_menu_node_spawned = false;
            gui_menu_drag_type    = _mp.type;
            gui_menu_drag_title   = _mp.title;
        }
    }

    // Close menu if user clicks outside the panel (and not on the bar buttons)
    var _in_panel = (gui_mouse_x >= _panel_x && gui_mouse_x < _panel_x + _panel_w &&
                     gui_mouse_y >= _panel_y  && gui_mouse_y < _panel_y + _panel_h);
    var _in_bar   = (gui_mouse_y >= _mbar_y   && gui_mouse_y < _mbar_y + _mbar_btn_h);
    if (mouse_check_button_pressed(mb_left) && !_in_panel && !_in_bar) {
        gui_menu_open = -1;
    }
}

/////////////////////////////////////////////////////////////////
///// MACRO DRAG FROM MENU
///// scr_node_spawn is the single source of truth for node defaults.
///// Only UV variable creation is special-cased — it opens the
///// name-entry modal rather than spawning a node.
/////////////////////////////////////////////////////////////////
if (gui_menu_drag_active && !gui_menu_node_spawned) {
    gui_menu_node_spawned = true;

    var _mtype = gui_menu_drag_type;
    var _n     = noone;

    var _is_uv_create = (_mtype == "NEW_UV_BYTE"  || _mtype == "NEW_UV_SBYTE" ||
                         _mtype == "NEW_UV_WORD"  || _mtype == "NEW_UV_BCD"   ||
                         _mtype == "NEW_STR");

    if (_is_uv_create) {
        var _sz = 1;
        if (_mtype == "NEW_UV_WORD") {
            _sz = 2;
        }
        var _enc = "sbyte";
        if (_mtype == "NEW_UV_BYTE") {
            _enc = "byte";
        } else if (_mtype == "NEW_UV_WORD") {
            _enc = "word";
        } else if (_mtype == "NEW_UV_BCD") {
            _enc = "bcd";
        } else if (_mtype == "NEW_STR") {
            _enc = "str";
        }
        var _hasVarsOrg = false;
        with (obj_c64_node) {
            if (node_type == "ORG" && node_title == "VARIABLES") {
                _hasVarsOrg = true;
            }
        }
        if (_hasVarsOrg) {
            with (obj_workspace_manager) {
                uv_pending_size      = _sz;
                uv_pending_enc       = _enc;
                is_entering_text     = true;
                input_target_node    = noone;
                input_target_index   = -99;
                current_input_string = "";
                keyboard_string      = "";
                cursor_pos           = 0;
            }
        } else {
            scr_show_message("There is no VARS ORG Holding node. Create one by pressing V");
        }
    } else {
        _n = scr_node_spawn(_mtype, mouse_x, mouse_y);
    }

    // Common node setup for anything that got spawned
    if (_n != noone && instance_exists(_n)) {
        _n.is_dragging   = true;
        _n.depth         = -2000;
        _n.pc_address    = global.start_pc;
        _n.drag_offset_x = 0;
        _n.drag_offset_y = 0;
        with (_n) { event_user(0); }
        global.undo_dirty = true;
        alarm[3] = 6;
    }

    // Drag ends when mouse is released
    if (mouse_check_button_released(mb_left)) {
        gui_menu_drag_active  = false;
        gui_menu_node_spawned = false;
        gui_menu_drag_type    = "";
        gui_menu_drag_title   = "";
    }
}



// Header
draw_set_font(fnt_C64_Angled_big);
//draw_set_color(make_color_rgb(220, 100, 45));
//draw_text(_mac_x1 + 8, 4, "MACROS");
draw_set_font(fnt_C64_Angled);




/////////////////////////////////////////////////////////////////
///// OPCODE HELPER TOOLTIP
/////////////////////////////////////////////////////////////////
if (opcode_helper_on && opcode_hover_key != "" && opcode_hover_timer >= opcode_hover_delay && !mouse_check_button(mb_left) && !mouse_check_button(mb_right) && !mouse_check_button(mb_middle)) {
    var _info = scr_opcode_helper(opcode_hover_key);
    if (_info != undefined) {
        var _tip_x = shelf_width + 80;
        var _tip_y = 120;
        var _tip_w = 1040;
        var _tip_h = 180;

        var _font_before = draw_get_font();

        // Panel
        draw_set_alpha(0.92);
        draw_set_color(make_color_rgb(12, 12, 22));
        draw_rectangle(_tip_x, _tip_y, _tip_x + _tip_w, _tip_y + _tip_h, false);
        draw_set_alpha(1.0);
        draw_set_color(make_color_rgb(80, 140, 220));
        draw_rectangle(_tip_x, _tip_y, _tip_x + _tip_w, _tip_y + _tip_h, true);

        draw_set_font(fnt_C64_Angled_big);
        var _lh = 29;
        var _tx = _tip_x + 10;
        var _ty = _tip_y + 8;

        // Line 1: name + hex + bytes + cycles
        draw_set_color(c_yellow);
        draw_text(_tx, _ty,
            string_upper(opcode_hover_key) + "  $" + string_upper(_info.hex) +
            "   " + string(_info.bytes) + " bytes  " + string(_info.cycles) + " cycles");

        // Line 2: format
        draw_set_color(c_aqua);
        draw_text(_tx, _ty + _lh, "FORMAT: " + _info.format);

        // Line 3: mode
        draw_set_color(c_white);
        draw_text(_tx, _ty + _lh * 2, _info.mode);

        // Line 4: use
        draw_set_color(make_color_rgb(160, 220, 160));
        draw_text(_tx, _ty + _lh * 3, _info.use);

        draw_set_font(_font_before);
    }
}

/////////////////////////////////////////////////////////////////
///// 2. GLOBAL SHORTCUTS (TOP RIGHT)
/////////////////////////////////////////////////////////////////
var sc_x_end   = gui_w - 2;
var sc_y_start = 50;
var sc_w       = 270;
var sc_h       = 21;

var shortcuts = [
    ["HOME",   "RESET VIEW"],
	["CTRL+L",   "LOAD FILE"],
    ["CTRL+S",   "SAVE"],
    ["CTRL+SHFT+S", "SAVE AS"],
    ["F5",     "BUILD & RUN"],
    ["F6",     "RUN ON ULTIMATE"],
    ["A",      "ADD ADDRESS LABEL"],
    ["J",      "ADD JMP NODE"],
    ["V",      "ADD ORG VARIABLES"],
    ["C",      "ADD COMMENT NODE"],
    ["B",      "ADD MAPPING BOX"],
    ["O",      "ADD ORG BLOCK"],
    ["X",      "TOGGLE HEX/DEC"],
    ["I",      "TOGGLE NODE INFO"],
];

for (var j = 0; j < array_length(shortcuts); j++) {
    var row_y  = sc_y_start + (j * (sc_h + 5));
    var box_x1 = sc_x_end - sc_w;
    var box_x2 = sc_x_end;
    var box_y1 = row_y;
    var box_y2 = row_y + sc_h;

    var btn_hover = (gui_mouse_x > box_x1 && gui_mouse_x < box_x2 &&
                     gui_mouse_y > box_y1 && gui_mouse_y < box_y2);
    var btn_click = btn_hover && mouse_check_button(mb_left);
    var is_toggle = (shortcuts[j][1] == "TOGGLE HEX/DEC" || shortcuts[j][1] == "TOGGLE AUTOSAVE MODE");

    var body_col = is_toggle
                 ? (global.use_hex_display ? make_color_rgb(20, 40, 45) : make_color_rgb(30, 30, 35))
                 : (btn_hover ? make_color_rgb(30, 30, 40) : make_color_rgb(10, 10, 15));

    draw_set_color(body_col);
    draw_rectangle(box_x1, box_y1, box_x2, box_y2, false);
    draw_set_color(btn_hover ? c_white : c_gray);
    draw_rectangle(box_x1, box_y1, box_x2, box_y2, true);

    var off = btn_click ? 2 : 0;
    draw_set_halign(fa_left);
    draw_set_color(c_white);
    draw_text_transformed(box_x1 + 15, row_y + 2 + off, shortcuts[j][0], 1.0, 1.2, 0);

    draw_set_halign(fa_right);
	
	if (shortcuts[j][1] == "RUN ON ULTIMATE") { // cant show until approved
		/*
		var _c64usc = 0.4;
		var _xscc64u = 1.0;
		var _tone = make_colour_rgb(220,220,220);
		if btn_hover 
			{
				_tone=c_white;
				_xscc64u = sin(degtorad(current_time * 0.16));
				draw_sprite_ext(spr_c64u,0,box_x1+62,row_y+2,_c64usc * _xscc64u ,_c64usc *1.1,0,c_black,0.4)
				(spr_c64u,0,box_x1+60,row_y+4,_c64usc * _xscc64u,_c64usc *1.2 ,0,c_black,0.25)
				if _xscc64u<0 _tone=c_dkgray
			}
			
		
		draw_sprite_ext(spr_c64u,0,box_x1+64,row_y,_c64usc * _xscc64u,_c64usc,0,_tone,1.0)
		*/
	}
	
	
	
   if (is_toggle) {
        var label_col, mode_text;
        if (shortcuts[j][1] == "TOGGLE AUTOSAVE MODE") {
            var _mode_labels = ["AUTOSAVE: 3 MIN", "AUTOSAVE: 5 MIN", "AUTOSAVE: 10 MIN", "AUTOSAVE: OFF"];
            var _mode_cols   = [c_lime, c_lime, c_lime, c_red];
            label_col = _mode_cols[global.autosave_mode];
            mode_text = _mode_labels[global.autosave_mode];
        } else {
            label_col = global.use_hex_display ? c_aqua : c_white;
            mode_text = global.use_hex_display ? "HEXADECIMAL" : "DECIMAL";
        }
        draw_set_color(label_col);
        draw_text_transformed(box_x2 - 10, row_y + 3 + off, mode_text, 1.0, 1.2, 0);
    } else {
        draw_set_color(btn_hover ? c_aqua : c_gray);
        draw_text_transformed(box_x2 - 10, row_y + 3 + off, shortcuts[j][1], 1.0, 1.2, 0);
    }
    draw_set_halign(fa_left);
	
	

    if (btn_hover && mouse_check_button_released(mb_left)) {
        switch (shortcuts[j][1]) {
            case "CLEANUP":
                scr_cleanup_nodes();
                scr_c64_update_addresses();
                break;
			case "ASSEMBLY DUMP":
		    silent_build = true;
		    pending_dump = true;
		    trigger_build = true;
		    break;
				
            case "BUILD & RUN":      execute_shell_simple("taskkill", "/f /im x64sc.exe"); trigger_build = true; break;
			case "RUN ON ULTIMATE":
			if (global.c64u_ip == "") {
				// No IP saved — open overlay; it sets trigger_c64u + trigger_build on confirm
				global.c64u_overlay_active = true;
				global.c64u_overlay_text   = "";
				global.c64u_overlay_error  = "";
				global.c64u_overlay_after  = "send_prg";
				global.canEditNode=0; // dont allow node editing until we close
				keyboard_string = "";
				keyboard_clear(vk_anykey);
			} else {
				trigger_c64u  = true;
				trigger_build = true;
			}
			break;
			
			case "RESET C64U IP":
			scr_c64u_reset_ip();
			
			break;
			
            case "TOGGLE FULLSCREEN": 
			
			
				do_windowSizing();
			break;
			case "EXPORT .PRG": {
			    var _export_path = get_save_filename("C64 Program|*.prg", "export");
			    if (_export_path != "") {
			        // Ensure .prg extension
			        if (string_lower(filename_ext(_export_path)) != ".prg") {
			            _export_path += ".prg";
			        }
			        with (obj_workspace_manager) {
			            pending_export_path = _export_path;
			            trigger_export      = true;
			        }
			    }
			} break;

            case "SAVE AS":           scr_save_workspace_as(); break;
            case "LOAD FILE":         scr_load_workspace_dialog(); break;
            case "RESET VIEW":
                cam_zoom_target = 1.0;
                cam_zoom        = 1.0;
                cam_x           = (room_width / 2) - (1920 / 2);
                cam_y           = -64;
                break;
            case "TOGGLE HEX/DEC":
                global.use_hex_display = !global.use_hex_display;
                scr_c64_update_addresses();
                break;
case "TOGGLE AUTOSAVE MODE":
                global.autosave_mode = (global.autosave_mode + 1) mod 4;
                var _ivs = [180, 300, 600, -1];
                global.autosave_interval = _ivs[global.autosave_mode];
                ini_open("c64devmachine.ini");
                ini_write_real("autosave", "mode", global.autosave_mode);
                ini_close();
                // Reset alarm to new interval
                var _next_iv = (global.autosave_mode != 3) ? global.autosave_interval : 9999;
                alarm[4] = game_get_speed(gamespeed_fps) * _next_iv;
                autosave_countdown = _next_iv;
                break;
            case "ADD ORG BLOCK":
                scr_spawn_org_node(mouse_x - 400, mouse_y);
                break;

			case "ADD JMP NODE": {
                var _n          = instance_create_layer(mouse_x - 400, mouse_y, "Layer_Nodes", obj_c64_node);
                _n.node_title   = "JMP";
                _n.node_type    = "NORMAL";
                _n.instructions = [["jmp_abs", "target"]];
                with(_n) { event_user(0); }
                _n.pc_address         = 0;
                _n.last_overlap_check = false;
                with (obj_c64_node) { last_overlap_check = false; }
            } break;
			
            case "ADD ORG VARIABLES": {
                var _n            = instance_create_layer(mouse_x - 400, mouse_y , "Layer_Nodes", obj_c64_node);
                _n.node_title     = "VARIABLES";
                _n.node_type      = "ORG";
                _n.proxy          = false;
                _n.is_draggable   = true;
                with (_n) { event_user(0); }
                _n.pc_address     = 0xC000;
                _n.proxy_address  = 0xC000;
                _n.end_address    = 0xC000;
            } break;
			
			case "TOGGLE NODE INFO":
				global.show_stats = !global.show_stats;
				break;
				
            case "ADD COMMENT NODE":
                scr_spawn_comment_node(mouse_x - 400, mouse_y );
                break;
            case "ADD ASCII DATA":
                scr_spawn_text_node(mouse_x - 400, mouse_y );
                break;
            case "ADD ADDRESS LABEL":
                var _nl        = instance_create_layer(mouse_x - 400, mouse_y , "Layer_Nodes", obj_c64_node);
                _nl.node_title   = "LABEL";
                _nl.node_type    = "LABEL";
                _nl.instructions = [["label", "target"]];
                _nl.pc_address   = global.start_pc;
                with(_nl) { event_user(0); }
                break;
            case "ADD SID MUSIC":
                var _n = instance_create_layer(mouse_x - 400, mouse_y , "Layer_Nodes", obj_c64_node);
                _n.node_title   = "SID MUSIC";
                _n.node_type    = "DATA_SID";
                _n.instructions = [["sid_file", "", 0, 0, 0, 0, 0, ""]];
                _n.pc_address   = 0x1000;
                with(_n) { event_user(0); }
                break;
			case "ADD BITMAP KLA":
			    var _n          = instance_create_layer(mouse_x - 400, mouse_y + 20, "Layer_Nodes", obj_c64_node);
			    _n.node_title   = "BITMAP KLA";
			    _n.node_type    = "BITMAP_KLA";
			    _n.instructions = [["bitmap_kla", "", 0]];
			    _n.pc_address   = 0x6000;
			    with (_n) { event_user(0); }
			    break;
				
				// Add TEXT_DATA asset
			case "ADD TEXT DATA":
				var _new = {
				    name:    "TEXT_" + string(ds_list_size(asset_list) + 1),
				    type:    "TEXT_DATA",
				    address: 0x2600,
				    file:    "",
				    buffer:  buffer_create(1, buffer_fixed, 1),
				    meta:    { text: "HELLO WORLD" }
				};
				scr_asset_text_flush(_new);
				ds_list_add(asset_list, _new);
			break;
				
				
				
            case "ADD SPR64":
                var _n = instance_create_layer(mouse_x - 400, mouse_y + 20, "Layer_Nodes", obj_c64_node);
                _n.node_title   = "SPR64";
                _n.node_type    = "SPR64";
                _n.instructions = [["spr", "", "", 0, "SPRITES", 0, 0, 0]];
                _n.pc_address   = 0x7000;
                with(_n) { event_user(0); }
                break;
            case "ADD RAW DATA":
                var _n = instance_create_layer(mouse_x - 400, mouse_y + 20, "Layer_Nodes", obj_c64_node);
                _n.node_title   = "RAW DATA";
                _n.node_type    = "RAW_DATA";
                _n.instructions = [["raw", "FF,FF,FF"]];
                _n.pc_address   = global.start_pc;
                with(_n) { event_user(0); }
                break;
            case "ADD HEX TABLE":
                var _n = instance_create_layer(mouse_x - 400, mouse_y + 20, "Layer_Nodes", obj_c64_node);
                _n.node_title   = "HEX TABLE";
                _n.node_type    = "RAW_DATA";
                _n.instructions = [["byte_row", "00,01,02"]];
                _n.pc_address   = global.start_pc;
                with(_n) { event_user(0); }
                break;
			case "TOGGLE COMMENTS" : global.comments_visible = !global.comments_visible; break;
            case "RESET/CLEAR": game_restart(); break;
			case "ADD SCROLL MACRO":
			    var _n          = instance_create_layer(mouse_x - 400, mouse_y + 20, "Layer_Nodes", obj_c64_node);
			    _n.node_title   = "MAP H SCROLL";
			    _n.node_type    = "MACRO_SCROLL";
			    _n.instructions = [["MACRO_SCROLL", 0, 25, 1, 1, 1, "", 0]];
			    _n.pc_address   = global.start_pc;
			    with(_n) { event_user(0); }
			    break;
			case "ADD VWAIT":
			    var _n          = instance_create_layer(mouse_x - 400, mouse_y + 20, "Layer_Nodes", obj_c64_node);
			    _n.node_title   = "VWAIT";
			    _n.node_type    = "MACRO_VWAIT";
			    _n.instructions = [["macro_vwait", 0xFB]];
			    _n.pc_address   = global.start_pc;
			    with(_n) { event_user(0); }
			    break;
			case "ADD MAPPING BOX":
				global.box_drag_active = true;
				box_drag_live          = false;
			//
				
				break;
        }
    }
}


/////////////////////////////////////////////////////////////////
///// 3. FOOTER & LOGO
/////////////////////////////////////////////////////////////////
draw_set_halign(fa_left);
draw_set_font(fnt_C64_Angled);

draw_set_halign(fa_right);

draw_set_colour(c_black);
draw_set_alpha(0.6);
draw_text(room_width-5, 8, (global.lite ? "LITE " : "FULL ") + "VERSION: "+string(GM_version)+"\n (C) POLYTRICITY LTD 2026");

draw_set_colour(c_white);
draw_set_alpha(1);
if global.lite draw_set_colour(c_lime);
draw_text(room_width-4, 7, (global.lite ? "LITE " : "FULL ") + "VERSION: "+string(GM_version)+"\n (C) POLYTRICITY LTD 2026");


// --- New version available banner ---
if (version_banner_visible && !version_banner_dismissed)
{
    // Set banner font FIRST so all measurements are correct
    draw_set_font(fnt_C64_Angled_big);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    
    // Build the three text segments separately so we can hit-test [CLOSE] precisely
    var _txt_main  = "NEW VERSION AVAILABLE: " + version_remote_string + "  ";
    var _txt_link  = "[GO TO LINK]";
    var _txt_gap   = "  ";
    var _txt_close = "[CLOSE]";
    
    var _w_main  = string_width(_txt_main);
    var _w_link  = string_width(_txt_link);
    var _w_gap   = string_width(_txt_gap);
    var _w_close = string_width(_txt_close);
    var _w_total = _w_main + _w_link + _w_gap + _w_close;
    var _h_total = string_height(_txt_main);
    
    // Position
    var _banner_x2 = room_width / 1.37;            // right edge
    var _banner_x1 = _banner_x2 - _w_total;       // left edge
    var _banner_y1 = 4 + (string_height("X") * 2) + 2;
    var _banner_y2 = _banner_y1 + _h_total;
    
    // Hit zones (computed against banner font)
    var _link_x1  = _banner_x1 + _w_main;
    var _link_x2  = _link_x1 + _w_link;
    var _close_x1 = _link_x2 + _w_gap;
    var _close_x2 = _close_x1 + _w_close;
    
    // Mouse
    var _mx = device_mouse_x_to_gui(0);
    var _my = device_mouse_y_to_gui(0);
    var _in_y       = (_my >= _banner_y1 && _my <= _banner_y2);
    var _over_link  = (_in_y && _mx >= _link_x1  && _mx <= _link_x2);
    var _over_close = (_in_y && _mx >= _close_x1 && _mx <= _close_x2);
    
    // Background strip
    draw_set_alpha(0.85);
    draw_set_colour(c_black);
    draw_rectangle(_banner_x1 - 4, _banner_y1 - 1, _banner_x2 + 2, _banner_y2 + 1, false);
    draw_set_alpha(1);
    
    // Draw segments in order, colouring hover state per-segment
    draw_set_colour(c_yellow);
    draw_text(_banner_x1, _banner_y1, _txt_main);
    
    if (_over_link)
    {
        draw_set_colour(c_white);
    }
    else
    {
        draw_set_colour(c_lime);
    }
    draw_text(_link_x1, _banner_y1, _txt_link);
    
    if (_over_close)
    {
        draw_set_colour(c_white);
    }
    else
    {
        draw_set_colour(c_red);
    }
    draw_text(_close_x1, _banner_y1, _txt_close);
    
    // Click handling — only the link and close are clickable, not the dead text in between
    if (mouse_check_button_pressed(mb_left))
    {
        if (_over_close)
        {
            version_banner_dismissed = true;
        }
        else if (_over_link)
        {
            url_open(version_remote_url);
            version_banner_dismissed = true;
        }
    }
    
    // Restore footer font for whatever draws after
    draw_set_font(fnt_c64_tiny);
    draw_set_colour(c_white);
    draw_set_halign(fa_left);
}

if (gui_menu_open == -1) {
    draw_set_colour(c_white);
    draw_set_halign(fa_left);
	draw_set_font(fnt_C64_Angled_tiny)
    var _path_str = string(global.workspace_path);
    var _path_x1  = shelf_width + 50;
    var _path_x2  = gui_w - 300;
    var _path_w   = _path_x2 - _path_x1;
    var _file_y = 48;
    var _auto_y = 64;
    // Format Last Saved Time (Manual)
    var _ls_h = string(last_save_hour);
    var _ls_m = string(last_save_minute);
    if (string_length(_ls_h) < 2) _ls_h = "0" + _ls_h;
    if (string_length(_ls_m) < 2) _ls_m = "0" + _ls_m;
    // Combine into one string for scaling
    var _display_str = "CURRENT FILE: " + _path_str + "    LAST SAVED: " + _ls_h + ":" + _ls_m;
    var _full_w    = string_width(_display_str);
    var _path_scl  = (_full_w > _path_w) ? (_path_w / _full_w) : 1.0;
    var _path_lower = string_lower(_path_str);
    var _cur_is_autosave = (string_pos("autosave", _path_lower) > 0);
    if (_cur_is_autosave) {
        draw_set_colour(make_color_rgb(255, 140, 0));
    } else {
        draw_set_colour(c_white);
    }
    draw_text_transformed(_path_x1, _file_y, _display_str, _path_scl, 1.0, 0);
    if (autosave_last_path != "")
    {
        var _h = string(autosave_hour);
        var _m = string(autosave_minute);
        if (string_length(_h) < 2)
        {
            _h = "0" + _h;
        }
        if (string_length(_m) < 2)
        {
            _m = "0" + _m;
        }
        var _auto_str = "AUTOSAVE: " + autosave_last_path + "   TIME: " + _h + ":" + _m;
        var _auto_w = string_width(_auto_str);
        var _auto_scl = 1.0;
        if (_auto_w > 1328)
        {
            _auto_scl = 1328 / _auto_w;
        }
        draw_set_color(make_color_rgb(80, 160, 80));
        draw_text_transformed(_path_x1, _auto_y, _auto_str, _auto_scl, 1.0, 0);
    }
}

/////////////////////////////////////////////////////////////////
///// 3B+3C. MEMORY MAP + WRITE ORDER BAR
/////////////////////////////////////////////////////////////////

var _bar_x1 = shelf_width + 60;
var _bar_x2 = gui_w - 60;
scr_draw_memory_bar(_bar_x1, _bar_x2, gui_h - 40);

 scr_code_editor_draw();

/////////////////////////////////////////////////////////////////
///// 4. DYNAMIC MODALS (EDITING & QUIT)
/////////////////////////////////////////////////////////////////
if (is_entering_text) {
    if (global.show_info_window) is_entering_text = false;

    var mid_x      = gui_w / 2;
    var mid_y      = gui_h / 2;
	
	var is_comment    = (instance_exists(input_target_node) &&
                        (input_target_node.node_type == "COMMENT" ||
                         input_target_node.node_title == "COMMENT"));
	var is_scrolltxt  = (instance_exists(input_target_node) &&
                         input_target_node.node_type == "MACRO_TEXT_SCROLL" &&
                         input_target_index == 6);
    var is_code_edit = (instance_exists(input_target_node) &&
                         input_target_node.node_type == "MACRO_CODE" &&
                         input_target_index == 0);
    var box_h = is_comment ? 120 : ((is_scrolltxt || is_code_edit) ? 160 : 60);


    draw_set_alpha(0.8);
    draw_set_color(c_black);
    draw_rectangle(0, 0, gui_w, gui_h, false);
    draw_set_alpha(1.0);

    draw_set_color(make_color_rgb(30, 30, 45));
    draw_rectangle(mid_x - 250, mid_y - box_h, mid_x + 250, mid_y + box_h, false);
    draw_set_color(c_aqua);
    draw_rectangle(mid_x - 250, mid_y - box_h, mid_x + 250, mid_y + box_h, true);

   // draw_set_halign(fa_center);
   // draw_set_color(c_white);
   // draw_text(mid_x, mid_y - (box_h - 25), "EDITING " + string_upper(input_target_node.node_title));
	
	draw_set_halign(fa_center);
	draw_set_color(c_white);
	var _modal_title = "";
	if (input_target_index == -99) {
	    _modal_title = "NEW VARIABLE NAME (UV_ AUTO-PREFIXED)";
	} else if (input_target_index == -77) {
	    _modal_title = "RENAME HEADER (BLANK = REVERT TO DEFAULT)";
	} else if (input_target_index == -78) {
	    _modal_title = "RENAME VARIABLE (MUST BE UNIQUE)";
	} else if (instance_exists(input_target_node)) {
	    _modal_title = "EDITING " + string_upper(input_target_node.node_title);
	}
	draw_text(mid_x, mid_y - (box_h - 25), _modal_title);

// Establish font once for the whole modal text block
    draw_set_font(fnt_c64_code);

    var _is_ml  = (is_comment || is_scrolltxt || is_code_edit);
    var _txt_x  = _is_ml ? ((is_scrolltxt || is_code_edit) ? mid_x - 250 : mid_x - 195) : mid_x;
    var _txt_y0 = mid_y - 60;
    var _lh_px  = 18 * 1.2;  // line height in pixels after scale

    // Draw selection highlight — per line so it never bleeds across lines
    var _has_sel_draw = (input_sel_start != -1 && input_sel_start != input_sel_end);
    if (_has_sel_draw) {
        var _slo = min(input_sel_start, input_sel_end);
        var _shi = max(input_sel_start, input_sel_end);
        draw_set_color(make_color_rgb(60, 100, 200));
        draw_set_alpha(0.5);
        if (_is_ml) {
            var _ml_lines = string_split(current_input_string, "\n");
            var _ml_off   = 0;
            for (var _mli = 0; _mli < array_length(_ml_lines); _mli++) {
                var _ml_line = _ml_lines[_mli];
                var _ml_len  = string_length(_ml_line);
                var _ml_end  = _ml_off + _ml_len;
                if (_slo <= _ml_end && _shi > _ml_off) {
                    var _hl_s = max(0, _slo - _ml_off);
                    var _hl_e = min(_ml_len, _shi - _ml_off);
                    var _hx1  = _txt_x + string_width(string_copy(_ml_line, 1, _hl_s)) * 1.2;
                    var _hx2  = _txt_x + string_width(string_copy(_ml_line, 1, _hl_e)) * 1.2;
                    var _hy   = _txt_y0 + (_mli * _lh_px);
                    draw_rectangle(_hx1, _hy, _hx2, _hy + _lh_px, false);
                }
                _ml_off += _ml_len + 1;
            }
        } else {
            var _before_sel = string_copy(current_input_string, 1, _slo);
            var _sel_text   = string_copy(current_input_string, _slo + 1, _shi - _slo);
            var _full_w     = string_width(current_input_string) * 1.5;
            var _bw         = string_width(_before_sel) * 1.5;
            var _sw         = string_width(_sel_text)   * 1.5;
            var _start_x    = mid_x - _full_w * 0.5;
            draw_rectangle(_start_x + _bw, mid_y - 14, _start_x + _bw + _sw, mid_y + 14, false);
        }
        draw_set_alpha(1.0);
    }

    // Draw text with cursor blinker
    var _blink      = (current_time mod 600 < 300);
    var _visual_str = _blink ? string_insert("|", current_input_string, cursor_pos + 1) : current_input_string;
    draw_set_color(c_yellow);
    if (_is_ml) {
        draw_set_halign(fa_left);
        draw_text_ext_transformed(_txt_x, _txt_y0, _visual_str, 18, 550, 1.2, 1.2, 0);
    } else {
        draw_set_halign(fa_center);
        draw_text_transformed(_txt_x, mid_y, _visual_str, 1.5, 1.5, 0);
    }
    draw_set_halign(fa_left);
}

if (readyToQuit == 1) {
    draw_set_font(fnt_big);
    var msg     = "Ready to quit.. You might need to save? Press Y to leave?";
    var padding = 4;
    var txt_w   = string_width(msg);
    var txt_h   = string_height(msg);
    var box_x1  = (gui_w / 2) - (txt_w / 2) - padding;
    var box_y1  = (gui_h / 2) - (txt_h / 2) - padding;
    var box_x2  = (gui_w / 2) + (txt_w / 2) + padding;
    var box_y2  = (gui_h / 2) + (txt_h / 2) + padding;
    draw_set_color(c_black);
    draw_rectangle(box_x1, box_y1, box_x2, box_y2, false);
    draw_set_color(c_white);
    draw_rectangle(box_x1, box_y1, box_x2, box_y2, true);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_text(gui_w / 2, gui_h / 2, msg);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_font(fnt_c64);
    if (mouse_check_button(mb_left)) readyToQuit = 0;
}

/////////////////////////////////////////////////////////////////
///// 5. PERFORMANCE MONITOR (BOTTOM LEFT)
/////////////////////////////////////////////////////////////////
draw_set_font(fnt_c64_tiny);
draw_set_halign(fa_left);
draw_set_valign(fa_bottom);
draw_set_colour(c_yellow)
draw_text(10, gui_h - 55, "Mx: " + string(gui_mouse_x) + " : My:  " + string(gui_mouse_y))
draw_text(10, gui_h - 40, "CAMx: " + string(cam_x) + " : CAMy:  " + string(cam_y))
var fps_col = (fps >= 55) ? c_lime : ((fps >= 30) ? c_yellow : c_red);
draw_set_color(fps_col);
draw_text(10, gui_h - 10, "FPS: " + string(fps) + " (REAL: " + string(fps_real) + ")");
draw_set_color(c_white);
draw_text(180, gui_h - 10, "NODES: " + string(instance_number(obj_c64_node)));
draw_set_valign(fa_top);
draw_set_halign(fa_left);

/////////////////////////////////////////////////////////////////
///// 6. MACRO BREAKDOWN OVERLAY
/////////////////////////////////////////////////////////////////
if (instance_exists(global.breakdown_node)) {
    var _node = global.breakdown_node;
    
    if (mouse_check_button_pressed(mb_left) && !global.ui_click_consumed && !global.any_picker_open) {
        global.breakdown_node = noone;
    } else {
        // Dark backdrop
        draw_set_alpha(0.85);
        draw_set_color(c_black);
        draw_rectangle(0, 0, gui_w, gui_h, false);
        draw_set_alpha(1.0);
        
        // Panel
        var _pw  = 560;
        var _ph  = 500;
        var _px1 = (gui_w / 2) - (_pw / 2);
        var _py1 = (gui_h / 2) - (_ph / 2);
        var _px2 = _px1 + _pw;
        var _py2 = _py1 + _ph;
        
        draw_set_color(make_color_rgb(20, 20, 35));
        draw_rectangle(_px1, _py1, _px2, _py2, false);
        draw_set_color(make_color_rgb(60, 100, 180));
        draw_rectangle(_px1, _py1, _px2, _py2, true);
        
        // Header bar
        draw_set_color(make_color_rgb(60, 100, 180));
        draw_rectangle(_px1, _py1, _px2, _py1 + 28, false);
        draw_set_font(fnt_c64_code);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text(gui_w / 2, _py1 + 6, "MACRO SPRITE — MACHINE CODE BREAKDOWN");
        draw_set_halign(fa_left);
        
        // --- FIXED: resolve spr_ptr from asset manager; ptr_reg shown as runtime-derived ---
        var _asset_name = string(_node.instructions[0][1]);
        var _slot       = clamp(real(_node.instructions[0][2]), 0, 7);
        var _sx         = real(_node.instructions[0][3]);
        var _sy         = real(_node.instructions[0][4]);
        var _frame      = is_real(_node.instructions[0][5]) ? real(_node.instructions[0][5]) : 0;

        // Resolve bank address from asset manager
        var _bank_addr = 0x2800;
        if (instance_exists(obj_asset_manager) && _asset_name != "") {
            var _am_bd = obj_asset_manager;
            for (var _ai_bd = 0; _ai_bd < ds_list_size(_am_bd.asset_list); _ai_bd++) {
                var _a_bd = ds_list_find_value(_am_bd.asset_list, _ai_bd);
                if (_a_bd.type == "SPRITE_SET" && _a_bd.name == _asset_name) {
                    _bank_addr = _a_bd.address;
                    break;
                }
            }
        }

        var _vic_bank  = _bank_addr >> 14;
        var _bank_base = _vic_bank * 0x4000;
        var _bank_hi   = (_bank_base >> 8) & 0xFF;
        var _cia_val   = (3 - _vic_bank) & 0x03;
        var _spr_ptr   = ((_bank_addr - _bank_base) / 64) + _frame;
        var _x_reg     = 0xD000 + (_slot * 2);
        var _y_reg     = 0xD001 + (_slot * 2);
        var _en_bit    = (1 << _slot);
        var _ptr_y     = 0xF8 + _slot;

        // Row format: [display_mnemonic, display_operand, comment, byte_count]
        var _rows = [
            // CIA bank select (RMW)
            ["LDA", "$DD00",                                      "Read CIA2 port A",             3],
            ["AND", "#$FC",                                       "Mask bank select bits",        2],
            ["ORA", "#$" + string_upper(decimal_to_hex(_cia_val)),"Set bank " + string(_vic_bank),2],
            ["STA", "$DD00",                                      "Write VIC bank",               3],
            // Runtime screen RAM derivation from $D018
            ["LDA", "$D018",                                      "Read VIC memory layout",       3],
            ["AND", "#$F0",                                       "Isolate screen RAM bits 7-4",  2],
            ["LSR", "A",                                          "Shift right 1",                1],
            ["LSR", "A",                                          "Shift right 2 = scr hi offset",1],
            ["CLC", "",                                           "Clear carry",                  1],
            ["ADC", "#$" + string_upper(decimal_to_hex(_bank_hi)),"Add bank base hi byte",        2],
            ["STA", "$FC",                                        "ZP $FC = screen_ram hi",       2],
            ["LDA", "#$00",                                       "Screen RAM lo always $00",     2],
            ["STA", "$FB",                                        "ZP $FB = screen_ram lo",       2],
            // Write sprite pointer via indirect Y
            ["LDY", "#$" + string_upper(decimal_to_hex(_ptr_y)), "Y = $F8+slot (ptr table idx)", 2],
            ["LDA", "#$" + string_upper(decimal_to_hex(_spr_ptr)),"Sprite ptr (bank-relative)",  2],
            ["STA", "($FB),Y",                                    "-> screen_ram+$03F8+slot",     2],
            // Position
            ["LDA", "#$" + string_upper(decimal_to_hex(_sx)),    "X position",                   2],
            ["STA", "$"  + string_upper(decimal_to_hex(_x_reg)), "VIC X register",               3],
            ["LDA", "#$" + string_upper(decimal_to_hex(_sy)),    "Y position",                   2],
            ["STA", "$"  + string_upper(decimal_to_hex(_y_reg)), "VIC Y register",               3],
            // Enable
            ["LDA", "$D015",                                      "Read sprite enable",           3],
            ["ORA", "#$" + string_upper(decimal_to_hex(_en_bit)),"Set enable bit",               2],
            ["STA", "$D015",                                      "Write sprite enable",          3],
            // Multicolour
            ["LDA", "$D01C",                                      "Read MC register",             3],
            ["AND", "#$" + string_upper(decimal_to_hex((~_en_bit) & 0xFF)), "Clear MC bit",      2],
            ["STA", "$D01C",                                      "Write MC register",            3],
        ];

        var _ly      = _py1 + 38;
        var _lh      = 18;
        var _pc      = _node.pc_address;
        var _col1_x  = _px1 + 16;
        var _col2_x  = _px1 + 90;
        var _col3_x  = _px1 + 185;
        var _col4_x  = _px1 + 350;
        var _col5_x  = _px1 + 490;

        // Column headers
        draw_set_font(fnt_c64_tiny);
        draw_set_color(c_gray);
        draw_text(_col1_x, _ly, "ADDR");
        draw_text(_col2_x, _ly, "INS");
        draw_text(_col3_x, _ly, "OPERAND");
        draw_text(_col4_x, _ly, "COMMENT");
        draw_text(_col5_x, _ly, "SZ");
        _ly += _lh + 2;
        draw_set_color(make_color_rgb(40, 40, 60));
        draw_rectangle(_px1 + 8, _ly - 2, _px2 - 8, _ly - 1, false);

        // Address info subheader
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(80, 120, 80));
        var _bank_hex = "$" + string_upper(decimal_to_hex(_bank_addr));
        var _scr_hex  = "$" + string_upper(decimal_to_hex(_screen_ram));
        draw_text(_col1_x, _ly,
            "ASSET: " + _asset_name + "  BANK: " + string(_vic_bank)
            + "  DATA@" + _bank_hex + "  SCRRAM@" + _scr_hex);
        _ly += _lh + 2;

        var _total_bytes = 0;
        draw_set_font(fnt_c64_code);
        for (var _i = 0; _i < array_length(_rows); _i++) {
            var _row    = _rows[_i];
            var _addr_h = decimal_to_hex(_pc);
            while (string_length(_addr_h) < 4) _addr_h = "0" + _addr_h;

            if (_i mod 2 == 0) {
                draw_set_color(make_color_rgb(25, 25, 40));
                draw_rectangle(_px1 + 8, _ly, _px2 - 8, _ly + _lh, false);
            }

            draw_set_color(c_aqua);
            draw_text(_col1_x, _ly, "$" + string_upper(_addr_h));
            draw_set_color(c_yellow);
            draw_text(_col2_x, _ly, _row[0]);
            draw_set_color(c_white);
            draw_text(_col3_x, _ly, _row[1]);
            draw_set_color(c_gray);
            draw_text(_col4_x, _ly, "; " + _row[2]);
            draw_set_color(c_lime);
            draw_text(_col5_x, _ly, string(_row[3]));

            _pc           += _row[3];
            _total_bytes  += _row[3];
            _ly           += _lh;
        }

        // Total
        _ly += 4;
        draw_set_color(make_color_rgb(40, 40, 60));
        draw_rectangle(_px1 + 8, _ly, _px2 - 8, _ly + 1, false);
        _ly += 6;
        draw_set_color(c_white);
        draw_text(_col4_x, _ly, "TOTAL:");
        draw_set_color(c_lime);
        draw_text(_col5_x, _ly, string(_total_bytes) + " BYTES");

        // Dismiss hint
        draw_set_font(fnt_c64_tiny);
        draw_set_color(c_gray);
        draw_set_halign(fa_center);
        draw_text(gui_w / 2, _py2 - 18, "CLICK ANYWHERE TO CLOSE");
        draw_set_halign(fa_left);
    }
}



/////////////////////////////////////////////////////////////////
///// 7. DYNAMIC MACRO INFO OVERLAY (MONITOR STYLE)
// Scrollable via mousewheel or UP/DOWN arrows when open.
// Scroll state lives in info_scroll_offset on obj_workspace_manager.
/////////////////////////////////////////////////////////////////


if (global.show_info_window && instance_exists(global.info_node)) {
    if (!variable_instance_exists(id, "info_timer"))         info_timer         = 0;
    if (!variable_instance_exists(id, "info_scroll_offset")) info_scroll_offset = 0;
    info_timer++;

    // Backdrop
    draw_set_alpha(0.6);
    draw_set_color(c_black);
    draw_rectangle(0, 0, gui_w, gui_h, false);
    draw_set_alpha(1.0);

    // Panel
    var shelf_offset = shelf_width;
    var work_w       = gui_w - shelf_offset;
    var win_w        = work_w * 0.7;
    var win_h        = gui_h * 0.7;
    var win_x        = shelf_offset + (work_w - win_w) / 2;
    var win_y        = (gui_h - win_h) / 2;
    draw_set_alpha(0.95);
    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(win_x, win_y, win_x + win_w, win_y + win_h, false);
    draw_set_alpha(1.0);
    draw_set_color(make_color_rgb(60, 100, 180));
    draw_rectangle(win_x, win_y, win_x + win_w, win_y + win_h, true);

    var _node  = global.info_node;
    var _title = string_upper(_node.node_type) + " ARCHITECTURE";
    var _rows  = [];

    // =========================================================
    // BUILD ROW DATA
    // =========================================================
    if (_node.node_type == "MACRO_SID") {
        var _v        = is_real(_node.instructions[0][3]) ? real(_node.instructions[0][3]) : 12;
        var _tr       = is_real(_node.instructions[0][2]) ? real(_node.instructions[0][2]) : 0;
        var _sid_init = 0x1000;
        var _sid_play = 0x1003;
        if (variable_instance_exists(_node, "sid_link") && instance_exists(_node.sid_link)) {
            _sid_init = _node.sid_link.sid_init_addr;
            _sid_play = _node.sid_link.sid_play_addr;
        }
        var _jump_dest = _node.pc_address + 74;

        _rows = [
            ["A9", scr_get_hex_val(0x00, 1),      "lda_imm",  0x00,       "Set black border/bg value"],
            ["8D", scr_get_hex_val(0xD020, 2),     "sta_abs",  0xD020,     "Border black"],
            ["8D", scr_get_hex_val(0xD021, 2),     "sta_abs",  0xD021,     "Background black"],
            ["A9", scr_get_hex_val(_v, 1),         "lda_imm",  _v,         "Master volume"],
            ["8D", scr_get_hex_val(0xD418, 2),     "sta_abs",  0xD418,     "SID volume register"],
            ["A9", scr_get_hex_val(0x00, 1),       "lda_imm",  0x00,       "Zero accumulator"],
            ["A2", scr_get_hex_val(0x18, 1),       "ldx_imm",  0x18,       "X = 24 (loop counter)"],
            ["9D", scr_get_hex_val(0xD400, 2),     "sta_abx",  0xD400,     "Clear SID reg $D400,X"],
            ["CA", "",                              "dex",      0,          "Decrement X"],
            ["10", "??",                            "bpl",      0,          "Loop until all 24 cleared"],
            ["A9", scr_get_hex_val(_tr, 1),        "lda_imm",  _tr,        "Track number"],
            ["A2", scr_get_hex_val(0x00, 1),       "ldx_imm",  0x00,       "X = 0 (required by player)"],
            ["A0", scr_get_hex_val(0x00, 1),       "ldy_imm",  0x00,       "Y = 0 (required by player)"],
            ["20", scr_get_hex_val(_sid_init, 2),  "jsr",      _sid_init,  "Call music init routine"],
            ["A9", scr_get_hex_val(0x37, 1),       "lda_imm",  0x37,       "BASIC+KERNAL+IO banking"],
            ["85", scr_get_hex_val(0x01, 1),       "sta_zp",   0x01,       "Restore banking ($01)"],
            ["78", "",                              "sei",      0,          "Disable IRQs during setup"],
            ["A9", scr_get_hex_val(0x99, 1),       "lda_imm",  0x99,       "IRQ handler lo (patched)"],
            ["8D", scr_get_hex_val(0x0314, 2),     "sta_abs",  0x0314,     "KERNAL IRQ vector lo"],
            ["A9", scr_get_hex_val(0x08, 1),       "lda_imm",  0x08,       "IRQ handler hi (patched)"],
            ["8D", scr_get_hex_val(0x0315, 2),     "sta_abs",  0x0315,     "KERNAL IRQ vector hi"],
            ["A9", scr_get_hex_val(0x7B, 1),       "lda_imm",  0x7B,       "Mask to disable CIA timer IRQ"],
            ["8D", scr_get_hex_val(0xDC0D, 2),     "sta_abs",  0xDC0D,     "CIA-1 interrupt control"],
            ["A9", scr_get_hex_val(0x81, 1),       "lda_imm",  0x81,       "Enable VIC raster IRQ bit"],
            ["8D", scr_get_hex_val(0xD01A, 2),     "sta_abs",  0xD01A,     "VIC interrupt mask register"],
            ["A9", scr_get_hex_val(0x1B, 1),       "lda_imm",  0x1B,       "Clear high raster bit"],
            ["8D", scr_get_hex_val(0xD011, 2),     "sta_abs",  0xD011,     "VIC control register 1"],
            ["A9", scr_get_hex_val(0x80, 1),       "lda_imm",  0x80,       "Raster line = $80 (128)"],
            ["8D", scr_get_hex_val(0xD012, 2),     "sta_abs",  0xD012,     "VIC raster compare register"],
            ["0E", scr_get_hex_val(0xD019, 2),     "asl_abs",  0xD019,     "Ack any pending VIC IRQ"],
            ["58", "",                              "cli",      0,          "Re-enable IRQs - music live"],
            ["4C", scr_get_hex_val(_jump_dest, 2), "jmp_abs",  _jump_dest, "Skip handler to user code"],
            ["AD", scr_get_hex_val(0xD019, 2),     "lda_abs",  0xD019,     "** HANDLER: Read VIC IRQ flag"],
            ["8D", scr_get_hex_val(0xD019, 2),     "sta_abs",  0xD019,     "Acknowledge VIC IRQ"],
            ["EE", scr_get_hex_val(0xD020, 2),     "inc_abs",  0xD020,     "Raster border flash ON"],
            ["A9", scr_get_hex_val(0x37, 1),       "lda_imm",  0x37,       "Restore banking before play"],
            ["85", scr_get_hex_val(0x01, 1),       "sta_zp",   0x01,       "Banking register $01"],
            ["20", scr_get_hex_val(_sid_play, 2),  "jsr",      _sid_play,  "Call music play routine"],
            ["A9", scr_get_hex_val(0x37, 1),       "lda_imm",  0x37,       "Restore banking after play"],
            ["85", scr_get_hex_val(0x01, 1),       "sta_zp",   0x01,       "Banking register $01"],
            ["CE", scr_get_hex_val(0xD020, 2),     "dec_abs",  0xD020,     "Raster border flash OFF"],
            ["68", "",                              "pla",      0,          "Restore A from stack"],
            ["A8", "",                              "tay",      0,          "Restore Y"],
            ["68", "",                              "pla",      0,          "Pull X (via A)"],
            ["AA", "",                              "tax",      0,          "Restore X"],
            ["68", "",                              "pla",      0,          "Restore A final"],
            ["20", scr_get_hex_val(0xFFE4, 2),     "jsr",      0xFFE4,     "KERNAL GETIN (keyboard scan)"],
            ["40", "",                              "rti",      0,          "Return from Interrupt"],
        ];

	} else if (_node.node_type == "MACRO_SPR") {
    var _slot  = clamp(real(_node.instructions[0][2]), 0, 7);
    var _sx    = real(_node.instructions[0][3]);
    var _sy    = real(_node.instructions[0][4]);
    var _frame = is_real(_node.instructions[0][5]) ? real(_node.instructions[0][5]) : 0;

    // Resolve asset to get correct bank address (mirrors compile chain)
    var _asset_name_s = string(_node.instructions[0][1]);
    var _bank_addr_s  = 0x2800;
    if (instance_exists(obj_asset_manager) && _asset_name_s != "") {
        var _am_s = obj_asset_manager;
        for (var _ai_s = 0; _ai_s < ds_list_size(_am_s.asset_list); _ai_s++) {
            var _a_s = ds_list_find_value(_am_s.asset_list, _ai_s);
            if (_a_s.type == "SPRITE_SET" && _a_s.name == _asset_name_s) {
                _bank_addr_s = _a_s.address;
                break;
            }
        }
    }

    var _vic_bank_s  = _bank_addr_s >> 14;
    var _bank_base_s = _vic_bank_s * 0x4000;
    var _cia_val_s   = (3 - _vic_bank_s) & 0x03;

    var _screen_ram_s = (array_length(_node.instructions[0]) > 7 && is_real(_node.instructions[0][7]))
                      ? real(_node.instructions[0][7])
                      : (_bank_base_s + 0x0400);

    var _ptr_s   = _screen_ram_s + 0x03F8 + _slot;
    var _spr_s   = ((_bank_addr_s - _bank_base_s) / 64) + _frame;
    var _x_reg_s = 0xD000 + (_slot * 2);
    var _y_reg_s = 0xD001 + (_slot * 2);
    var _en_s    = (1 << _slot);

    _rows = [
        // CIA bank select
        ["AD", scr_get_hex_val(0xDD00, 2), "lda_abs", 0xDD00, "Read CIA2 port A"],
        ["29", scr_get_hex_val(0xFC,   1), "and_imm", 0xFC,   "Mask bank select bits"],
        ["09", scr_get_hex_val(_cia_val_s, 1), "ora_imm", _cia_val_s, "Bank " + string(_vic_bank_s) + " select"],
        ["8D", scr_get_hex_val(0xDD00, 2), "sta_abs", 0xDD00, "Write VIC bank ($DD00)"],
        // Pointer
        ["A9", scr_get_hex_val(_spr_s, 1),   "lda_imm", _spr_s,  "Sprite ptr (bank-relative)"],
        ["8D", scr_get_hex_val(_ptr_s, 2),   "sta_abs", _ptr_s,  "Store to ptr table ($" + string_upper(decimal_to_hex(_ptr_s)) + ")"],
        // Position
        ["A9", scr_get_hex_val(_sx, 1),      "lda_imm", _sx,     "X position"],
        ["8D", scr_get_hex_val(_x_reg_s, 2), "sta_abs", _x_reg_s,"VIC X reg ($" + string_upper(decimal_to_hex(_x_reg_s)) + ")"],
        ["A9", scr_get_hex_val(_sy, 1),      "lda_imm", _sy,     "Y position"],
        ["8D", scr_get_hex_val(_y_reg_s, 2), "sta_abs", _y_reg_s,"VIC Y reg ($" + string_upper(decimal_to_hex(_y_reg_s)) + ")"],
        // Enable (OR — safe for multi-sprite programs)
        ["AD", scr_get_hex_val(0xD015, 2),   "lda_abs", 0xD015, "Read sprite enable"],
        ["09", scr_get_hex_val(_en_s, 1),    "ora_imm", _en_s,  "OR enable bit (slot " + string(_slot) + ")"],
        ["8D", scr_get_hex_val(0xD015, 2),   "sta_abs", 0xD015, "Write sprite enable"],
        // Multicolour (AND clear — safe for multi-sprite programs)
        ["AD", scr_get_hex_val(0xD01C, 2),   "lda_abs", 0xD01C, "Read MC register"],
        ["29", scr_get_hex_val((~_en_s) & 0xFF, 1), "and_imm", (~_en_s) & 0xFF, "Clear MC bit for slot"],
        ["8D", scr_get_hex_val(0xD01C, 2),   "sta_abs", 0xD01C, "Write MC register"],
    ];
} else if (_node.node_type == "MACRO_SCROLL") {
        _title = "MAP H SCROLL - JSR ENTRY POINTS";
        _rows  = [
            ["20", "?? ??", "jsr", 0, "JSR Scroller_L  scroll left  (call each frame)"],
            ["20", "?? ??", "jsr", 0, "JSR Scroller_R  scroll right (call each frame)"],
            ["--", "",      "nop", 0, "$D016 bits 0-2  fine H scroll (owned by this node)"],
            ["--", "",      "nop", 0, "$D018 bits 4-7  screen flip $0400 / $0C00"],
            ["--", "",      "nop", 0, "$0C00-$0FFF     screen buffer 2 (reserved)"],
        ];
    } else if (_node.node_type == "MACRO_VSCROLL") {
        _title = "MAP V SCROLL - JSR ENTRY POINTS";
        _rows  = [
            ["20", "?? ??", "jsr", 0, "JSR Scroller_U  scroll up   (call each frame)"],
            ["20", "?? ??", "jsr", 0, "JSR Scroller_D  scroll down (call each frame)"],
            ["--", "",      "nop", 0, "$D011 bits 0-2  fine V scroll (shadow register)"],
            ["--", "",      "nop", 0, "$D018 bits 4-7  screen flip $0400 / $0C00"],
            ["--", "",      "nop", 0, "$0C00-$0FFF     screen buffer 2 (reserved)"],
            ["--", "",      "nop", 0, "Combine: JSR Scroller_L then JSR Scroller_U same frame"],
        ];
    }


    // =========================================================
    // SCROLL INPUT
    // =========================================================
    var _row_h        = 18;
    var _total_rows   = array_length(_rows);
    var _header_h_px  = 108;
    var _dismiss_h    = 50;
    var _visible_h    = win_h - _header_h_px - _dismiss_h;
    var _visible_rows = floor(_visible_h / _row_h);
    var _max_scroll   = max(0, (_total_rows - _visible_rows) * _row_h);

    if (gui_mouse_x >= win_x && gui_mouse_x <= win_x + win_w &&
        gui_mouse_y >= win_y && gui_mouse_y <= win_y + win_h) {
        if (mouse_wheel_up())   info_scroll_offset = max(0,           info_scroll_offset - _row_h);
        if (mouse_wheel_down()) info_scroll_offset = min(_max_scroll, info_scroll_offset + _row_h);
    }
    if (keyboard_check_pressed(vk_up))   info_scroll_offset = max(0,           info_scroll_offset - _row_h);
    if (keyboard_check_pressed(vk_down)) info_scroll_offset = min(_max_scroll, info_scroll_offset + _row_h);

    // =========================================================
    // HEADER: TITLE + DESCRIPTION
    // =========================================================
    draw_set_font(fnt_C64_Angled_big);
    draw_set_color(c_white);
    draw_text(win_x + 30, win_y + 16, _title);

    var _desc = "";
    if (_node.node_type == "MACRO_SPR") {
        _desc = "Positions a hardware sprite using the VIC-II chip. Writes the sprite pointer, " +
                "X/Y coordinates and enable bit directly to VIC registers - 25 bytes, zero overhead.";
    } else if (_node.node_type == "MACRO_SID") {
        _desc = "Arms the SID chip with a raster IRQ player. Clears SID regs, restores banking after init, " +
                "redirects the KERNAL IRQ vector, sets VIC raster line $80, then embeds a 32-byte handler " +
                "inline. Handler: acks VIC, restores banking, calls play, scans keyboard, RTI. " +
                "106 bytes total - zero mainloop cost.";
    }
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(80, 180, 80));
    if (_desc != "") draw_text_ext(win_x + 30, win_y + 44, _desc, 14, win_w - 60);

    // =========================================================
    // COLUMN HEADERS + DIVIDER
    // =========================================================
    var _col_addr = win_x + 30;
    var _col_hex  = win_x + 130;
    var _col_ins  = win_x + 290;
    var _col_comm = win_x + 430;
    var _ly_hdr   = win_y + 88;
    draw_set_font(fnt_C64_Angled);
    draw_set_color(make_color_rgb(80, 80, 100));
    draw_text(_col_addr, _ly_hdr, "ADDR");
    draw_text(_col_hex,  _ly_hdr, "HEX BYTES");
    draw_text(_col_ins,  _ly_hdr, "ASM");
    draw_text(_col_comm, _ly_hdr, "; COMMENT");
    draw_set_color(make_color_rgb(40, 40, 60));
    draw_rectangle(win_x + 10, _ly_hdr + 14, win_x + win_w - 10, _ly_hdr + 15, false);

    // =========================================================
    // SCROLLABLE ROW LIST
    // =========================================================
    var _clip_y1    = win_y + 108;
    var _clip_y2    = win_y + win_h - 50;
    var _ly         = _clip_y1 - info_scroll_offset;
    var _running_pc = _node.pc_address;

    draw_set_color(make_color_rgb(18, 18, 28));
    draw_rectangle(win_x + 1, _clip_y1, win_x + win_w - 1, _clip_y2, false);

    for (var i = 0; i < _total_rows; i++) {
        var _row_y = _ly + (i * _row_h);
        var _size  = obj_opCodeManager.get_size(_rows[i][2]);

        if (_row_y + _row_h <= _clip_y1) { _running_pc += _size; continue; }
        if (_row_y > _clip_y2) break;

        if (i mod 2 == 0) {
            var _bg_y1 = max(_row_y - 1,  _clip_y1);
            var _bg_y2 = min(_row_y + 17, _clip_y2);
            if (_bg_y2 > _bg_y1) {
                draw_set_color(make_color_rgb(25, 25, 40));
                draw_rectangle(win_x + 10, _bg_y1, win_x + win_w - 10, _bg_y2, false);
            }
        }

        var _s_hex     = decimal_to_hex(_running_pc);
        while (string_length(_s_hex) < 4) _s_hex = "0" + _s_hex;
        var _bytes_str = _rows[i][0] + ((_rows[i][1] != "") ? " " + _rows[i][1] : "");

        draw_set_font(fnt_C64_Angled);
        draw_set_color(make_color_rgb(100, 100, 140)); draw_text(_col_addr, _row_y, "$" + string_upper(_s_hex));
        draw_set_color(make_color_rgb(180, 160, 80));  draw_text(_col_hex,  _row_y, string_upper(_bytes_str));
        draw_set_color(make_color_rgb(80, 180, 255));  draw_text(_col_ins,  _row_y, scr_format_asm(_rows[i][2], _rows[i][3]));
        draw_set_color(make_color_rgb(120, 80, 80));   draw_text(_col_comm, _row_y, "; " + string(_rows[i][4]));

        _running_pc += _size;
    }

    // =========================================================
    // SCROLLBAR
    // =========================================================
    if (_max_scroll > 0) {
        var _sb_x    = win_x + win_w - 8;
        var _sb_y1   = _clip_y1 + 2;
        var _sb_y2   = _clip_y2 - 2;
        var _sb_h    = _sb_y2 - _sb_y1;
        var _thumb_h = max(20, _sb_h * (_visible_rows / _total_rows));
        var _thumb_y = _sb_y1 + (_sb_h - _thumb_h) * (info_scroll_offset / _max_scroll);

        draw_set_color(make_color_rgb(30, 30, 50));
        draw_rectangle(_sb_x, _sb_y1, _sb_x + 6, _sb_y2, false);
        draw_set_color(make_color_rgb(80, 100, 180));
        draw_rectangle(_sb_x, _thumb_y, _sb_x + 6, _thumb_y + _thumb_h, false);

        if (info_timer < 180) {
            draw_set_alpha(max(0, 1 - (info_timer - 120) / 60));
            draw_set_font(fnt_c64_tiny);
            draw_set_color(c_gray);
            draw_set_halign(fa_center);
            draw_text(win_x + win_w / 2, _clip_y2 - 16, "SCROLL: MOUSEWHEEL OR UP/DOWN");
            draw_set_halign(fa_left);
            draw_set_alpha(1.0);
        }
    }

    // =========================================================
    // DISMISS
    // =========================================================
    if (info_timer > 60) {
        draw_set_font(fnt_big);
        draw_set_color(make_color_rgb(180, 40, 40));
        draw_set_halign(fa_center);
        draw_text(win_x + (win_w / 2), win_y + win_h - 30, "CLICK ANYWHERE TO DISMISS");
        draw_set_halign(fa_left);
        if (mouse_check_button_pressed(mb_any) || keyboard_check_pressed(vk_escape)) {
            global.show_info_window = false;
            info_scroll_offset      = 0;
            info_timer              = 0;
        }
    }

    exit; // block all workspace input while overlay is up
}

	/////////////////////////////////////////////////////////////////
	///// BOX NAME/COLOUR POPUP (MODAL)
	/////////////////////////////////////////////////////////////////
	if (box_popup_open && instance_exists(box_popup_target)) {

	    // Block everything else
	    draw_set_alpha(0.6);
	    draw_set_color(c_black);
	    draw_rectangle(0, 0, gui_w, gui_h, false);
	    draw_set_alpha(1.0);

	    var _pw  = 390;
	    var _ph  = 260;
	    var _px  = (gui_w - _pw) / 2;
	    var _py  = (gui_h - _ph) / 2;

	    // Panel
	    draw_set_color(make_color_rgb(20, 20, 35));
	    draw_rectangle(_px, _py, _px + _pw, _py + _ph, false);
	    draw_set_color(c_aqua);
	    draw_rectangle(_px, _py, _px + _pw, _py + _ph, true);

	    // Header bar
	    draw_set_color(make_color_rgb(30, 60, 100));
	    draw_rectangle(_px, _py, _px + _pw, _py + 24, false);
	    draw_set_font(fnt_C64_Angled);
	    draw_set_color(c_white);
	    draw_set_halign(fa_center);
	    draw_text(_px + _pw * 0.5, _py + 4,
	              box_popup_is_edit ? "EDIT MAPPING BOX" : "NEW MAPPING BOX");
	    draw_set_halign(fa_left);

	    // NAME label
	    draw_set_font(fnt_c64_tiny);
	    draw_set_color(c_gray);
	    draw_text(_px + 14, _py + 32, "NAME:");

	    // Name input field
	    var _nfx1 = _px + 14;
	    var _nfx2 = _px + _pw - 14;
	    var _nfy1 = _py + 44;
	    var _nfy2 = _nfy1 + 22;
	    draw_set_color(make_color_rgb(35, 35, 55));
	    draw_rectangle(_nfx1, _nfy1, _nfx2, _nfy2, false);
	    draw_set_color(c_aqua);
	    draw_rectangle(_nfx1, _nfy1, _nfx2, _nfy2, true);
	    var _blinker  = (current_time mod 600 < 300) ? "|" : " ";
	    var _vis_name = string_insert(_blinker, box_popup_name, box_cursor_pos + 1);
	    draw_set_font(fnt_c64_code);
	    draw_set_color(c_yellow);
	    draw_text(_nfx1 + 6, _nfy1 + 4, _vis_name);

	    // Duplicate warning
	    if (box_popup_name_dupe) {
	        draw_set_font(fnt_c64_tiny);
	        draw_set_color(c_red);
	        draw_text(_nfx1, _nfy2 + 2, "! NAME IN USE - WILL AUTO-NUMBER");
	    }

	    // COLOUR label
	    draw_set_font(fnt_c64_tiny);
	    draw_set_color(c_gray);
	    draw_text(_px + 14, _py + 80, "COLOUR:");

	    // Colour names for dropdown
	    var _col_names = [
	        "RED", "ORANGE", "YELLOW", "LIME", "GREEN", "TEAL",
	        "SKY", "BLUE", "VIOLET", "PINK", "ROSE", "BROWN",
	        "DARK", "GREY", "SILVER", "WHITE"
	    ];
	    var _box_colours = [
	        make_color_rgb(220, 60,  60),
	        make_color_rgb(220, 140, 40),
	        make_color_rgb(220, 220, 40),
	        make_color_rgb(100, 220, 60),
	        make_color_rgb(40,  180, 80),
	        make_color_rgb(40,  200, 180),
	        make_color_rgb(40,  140, 220),
	        make_color_rgb(60,  80,  220),
	        make_color_rgb(140, 60,  220),
	        make_color_rgb(220, 60,  180),
	        make_color_rgb(220, 60,  120),
	        make_color_rgb(180, 100, 60),
	        make_color_rgb(30,  30,  30),
	        make_color_rgb(80,  80,  80),
	        make_color_rgb(160, 160, 160),
	        make_color_rgb(240, 240, 240),
	    ];

	    // Dropdown button
	    var _ddx1 = _px + 14;
	    var _ddx2 = _px + _pw - 14;
	    var _ddy1 = _py + 92;
	    var _ddy2 = _ddy1 + 24;
	    var _dd_hov = (gui_mouse_x >= _ddx1 && gui_mouse_x <= _ddx2 &&
	                   gui_mouse_y >= _ddy1 && gui_mouse_y <= _ddy2);

	    draw_set_color(make_color_rgb(35, 35, 55));
	    draw_rectangle(_ddx1, _ddy1, _ddx2, _ddy2, false);
	    draw_set_color(_dd_hov ? c_white : c_aqua);
	    draw_rectangle(_ddx1, _ddy1, _ddx2, _ddy2, true);

	    // Swatch preview
	    draw_set_color(_box_colours[box_popup_col_idx]);
	    draw_rectangle(_ddx1 + 4, _ddy1 + 4, _ddx1 + 20, _ddy2 - 4, false);

	    draw_set_font(fnt_C64_Angled);
	    draw_set_color(c_white);
	    draw_text(_ddx1 + 26, _ddy1 + 5, _col_names[box_popup_col_idx]);

	    // Arrow
	    draw_set_color(c_gray);
	    draw_triangle(_ddx2 - 18, _ddy1 + 8, _ddx2 - 6, _ddy1 + 8, _ddx2 - 12, _ddy2 - 6, false);

	    if (_dd_hov && mouse_check_button_pressed(mb_left)) {
	        box_dropdown_open = !box_dropdown_open;
	    }

	    // Dropdown list
	    if (box_dropdown_open) {
	        var _item_h = 22;
	        for (var _ci = 0; _ci < array_length(_col_names); _ci++) {
	            var _lix1 = _ddx1;
	            var _lix2 = _ddx2;
	            var _liy1 = _ddy2 + (_ci * _item_h);
	            var _liy2 = _liy1 + _item_h;
	            var _li_hov = (gui_mouse_x >= _lix1 && gui_mouse_x <= _lix2 &&
	                           gui_mouse_y >= _liy1 && gui_mouse_y <= _liy2);

	            draw_set_color(_li_hov ? make_color_rgb(50, 50, 80) : make_color_rgb(25, 25, 40));
	            draw_rectangle(_lix1, _liy1, _lix2, _liy2, false);
	            draw_set_color(c_gray);
	            draw_rectangle(_lix1, _liy1, _lix2, _liy2, true);

	            // Swatch
	            draw_set_color(_box_colours[_ci]);
	            draw_rectangle(_lix1 + 4, _liy1 + 3, _lix1 + 18, _liy2 - 3, false);

	            draw_set_font(fnt_C64_Angled);
	            draw_set_color(_ci == box_popup_col_idx ? c_yellow : c_white);
	            draw_text(_lix1 + 24, _liy1 + 4, _col_names[_ci]);

	            if (_li_hov && mouse_check_button_pressed(mb_left)) {
	                box_popup_col_idx = _ci;
	                box_dropdown_open = false;
	            }
	        }
	    }

	    // CONFIRM / CANCEL buttons (only draw if dropdown closed)
	    if (!box_dropdown_open) {
	        var _ok_y  = _py + _ph - 36;
	        var _ok_x  = _px + 14;
	        var _ok_w  = 120;
	        var _cn_x  = _px + _pw - 134;

	        var _ok_hov = (gui_mouse_x >= _ok_x && gui_mouse_x <= _ok_x + _ok_w &&
	                       gui_mouse_y >= _ok_y && gui_mouse_y <= _ok_y + 24);
	        var _cn_hov = (gui_mouse_x >= _cn_x && gui_mouse_x <= _cn_x + _ok_w &&
	                       gui_mouse_y >= _ok_y && gui_mouse_y <= _ok_y + 24);

	        draw_set_color(_ok_hov ? c_lime : make_color_rgb(30, 100, 30));
	        draw_rectangle(_ok_x, _ok_y, _ok_x + _ok_w, _ok_y + 24, false);
	        draw_set_color(_ok_hov ? c_black : c_white);
	        draw_set_halign(fa_center);
	        draw_set_font(fnt_C64_Angled);
	        draw_text(_ok_x + _ok_w * 0.5, _ok_y + 5, "CONFIRM");

	        draw_set_color(_cn_hov ? c_red : make_color_rgb(100, 30, 30));
	        draw_rectangle(_cn_x, _ok_y, _cn_x + _ok_w, _ok_y + 24, false);
	        draw_set_color(_cn_hov ? c_black : c_white);
	        draw_text(_cn_x + _ok_w * 0.5, _ok_y + 5, "CANCEL");
	        draw_set_halign(fa_left);

	        if (_ok_hov && mouse_check_button_released(mb_left)) {
	            // Unique name enforcement
	            var _final_name = box_popup_name;
	            if (box_popup_name == "" ) _final_name = "BOX";
	            var _dupe_count = 0;
				
				var _target = box_popup_target;
					with (obj_mapping_box) {
					    if (id != _target &&
	                    string_lower(box_name) == string_lower(_final_name)) {
	                    _dupe_count++;
	                }
	            }
	            if (_dupe_count > 0) _final_name += "_" + string(_dupe_count);

	            box_popup_target.box_name    = _final_name;
	            box_popup_target.box_col_idx = box_popup_col_idx;
	            box_popup_open               = false;
	            box_popup_target             = noone;
	            box_dropdown_open            = false;
				global.undo_dirty            = true;alarm[3] = 3;
	        }
			
			// Absorb the spawning keypress on first frame
			if (!variable_instance_exists(id, "box_popup_ready")) box_popup_ready = false;
			if (!box_popup_ready) {
			    keyboard_string = "";
			    box_popup_ready = true;
				
			}

			// Ctrl+Backspace - clear name
			if (keyboard_check(vk_control) && keyboard_check_pressed(vk_backspace)) {
			    box_popup_name = "";
			    box_cursor_pos = 0;
			    keyboard_string = "";
		
			}

	        if (_cn_hov && mouse_check_button_released(mb_left)) {
	            if (!box_popup_is_edit) instance_destroy(box_popup_target);
	            box_popup_open    = false;
	            box_popup_target  = noone;
	            box_dropdown_open = false;
				global.undo_dirty            = true;alarm[3] = 3;
	        }

	        // Keyboard confirm/cancel				
	        if (keyboard_check_pressed(vk_enter) && !box_dropdown_open) {
				var _target = box_popup_target;
	            var _final_name = (box_popup_name == "") ? "BOX" : box_popup_name;
	            var _dupe_count = 0;
	            with (obj_mapping_box) {
	                if (id !=  _target &&
	                    string_lower(box_name) == string_lower(_final_name)) {
	                    _dupe_count++;
	                }
	            }
	            if (_dupe_count > 0) _final_name += "_" + string(_dupe_count);
	            box_popup_target.box_name    = _final_name;
	            box_popup_target.box_col_idx = box_popup_col_idx;
	            box_popup_open               = false;
	            box_popup_target             = noone;
	            box_dropdown_open            = false;
	            keyboard_string              = "";
				global.undo_dirty            = true;
				alarm[3]          = 3;
	        }
	        if (keyboard_check_pressed(vk_escape) && !box_dropdown_open) {
	            if (!box_popup_is_edit) instance_destroy(box_popup_target);
	            box_popup_open    = false;
	            box_popup_target  = noone;
	            box_dropdown_open = false;
	            keyboard_string   = "";
				global.undo_dirty            = true;
	        }
	    }
	}
	
	/////////////////////////////////////////////////////////////////
	///// LABEL SEARCH MODAL (CTRL/CMD+SHIFT+F)
	/////////////////////////////////////////////////////////////////
	if (label_search_open) {

	    draw_set_alpha(0.6);
	    draw_set_color(c_black);
	    draw_rectangle(0, 0, gui_w, gui_h, false);
	    draw_set_alpha(1.0);

	    var _lsw = 420;
	    var _lsh = 150;
	    var _lsx = (gui_w - _lsw) / 2;
	    var _lsy = (gui_h - _lsh) / 2;

	    draw_set_color(make_color_rgb(20, 20, 35));
	    draw_rectangle(_lsx, _lsy, _lsx + _lsw, _lsy + _lsh, false);
	    draw_set_color(c_aqua);
	    draw_rectangle(_lsx, _lsy, _lsx + _lsw, _lsy + _lsh, true);

	    draw_set_color(make_color_rgb(30, 60, 100));
	    draw_rectangle(_lsx, _lsy, _lsx + _lsw, _lsy + 24, false);
	    draw_set_font(fnt_C64_Angled);
	    draw_set_color(c_white);
	    draw_set_halign(fa_center);
	    draw_text(_lsx + _lsw * 0.5, _lsy + 4, "FIND LABEL");
	    draw_set_halign(fa_left);

	    // Close X
	    var _lsclose_x1 = _lsx + _lsw - 20;
	    var _lsclose_y1 = _lsy + 2;
	    var _lsclose_hov = point_in_rectangle(gui_mouse_x, gui_mouse_y, _lsclose_x1, _lsclose_y1, _lsclose_x1 + 18, _lsclose_y1 + 18);
	    draw_set_color(_lsclose_hov ? c_red : c_white);
	    draw_text(_lsclose_x1 + 3, _lsclose_y1, "X");
	    if (_lsclose_hov && mouse_check_button_pressed(mb_left)) {
	        label_search_open    = false;
	        label_search_results = [];
	        label_search_index   = -1;
	    }

	    // Hint
	    draw_set_font(fnt_c64_tiny);
	    draw_set_color(c_gray);
	    draw_text(_lsx + 14, _lsy + 32, "NAME / NAME* / *NAME / *NAME*");

	    // Input field
	    var _lfx1 = _lsx + 14;
	    var _lfx2 = _lsx + _lsw - 14;
	    var _lfy1 = _lsy + 46;
	    var _lfy2 = _lfy1 + 24;
	    draw_set_color(make_color_rgb(35, 35, 55));
	    draw_rectangle(_lfx1, _lfy1, _lfx2, _lfy2, false);
	    draw_set_color(c_aqua);
	    draw_rectangle(_lfx1, _lfy1, _lfx2, _lfy2, true);
	    var _ls_blink = (current_time mod 600 < 300) ? "|" : " ";
	    var _ls_vis   = string_insert(_ls_blink, label_search_query, label_search_cursor + 1);
	    draw_set_font(fnt_c64_code);
	    draw_set_color(c_yellow);
	    draw_text(_lfx1 + 6, _lfy1 + 4, _ls_vis);

	    // Search button
	    var _lsbx1 = _lsx + 14;
	    var _lsbx2 = _lsx + 120;
	    var _lsby1 = _lfy2 + 8;
	    var _lsby2 = _lsby1 + 24;
	    var _lsb_hov = point_in_rectangle(gui_mouse_x, gui_mouse_y, _lsbx1, _lsby1, _lsbx2, _lsby2);
	    draw_set_color(_lsb_hov ? c_lime : make_color_rgb(30, 100, 30));
	    draw_rectangle(_lsbx1, _lsby1, _lsbx2, _lsby2, false);
	    draw_set_color(_lsb_hov ? c_black : c_white);
	    draw_set_font(fnt_C64_Angled);
	    draw_set_halign(fa_center);
	    draw_text(_lsbx1 + (_lsbx2 - _lsbx1) * 0.5, _lsby1 + 5, "SEARCH");
	    draw_set_halign(fa_left);
	    if (_lsb_hov && mouse_check_button_pressed(mb_left)) {
	        label_search_results = scr_label_search_run(label_search_query);
	        label_search_index   = (array_length(label_search_results) > 0) ? 0 : -1;
	        if (label_search_index >= 0 && instance_exists(label_search_results[label_search_index])) {
	            scr_focus_camera_on_node_offset(label_search_results[label_search_index], 0.55);
	            camera_set_view_pos(cam_view, cam_x, cam_y);
	        }
	    }

	    // Results count + nav
	    var _lsr_x     = _lsx + 140;
	    var _lsr_y     = _lsby1 + 4;
	    var _lsr_count = array_length(label_search_results);

	    draw_set_font(fnt_c64_code);
	    if (_lsr_count > 0) {
	        draw_set_color(c_lime);
	        draw_text(_lsr_x, _lsr_y, string(label_search_index + 1) + " / " + string(_lsr_count));

	        // < prev
	        var _lsp_x1  = _lsr_x + 60;
	        var _lsp_x2  = _lsp_x1 + 24;
	        var _lsp_hov = point_in_rectangle(gui_mouse_x, gui_mouse_y, _lsp_x1, _lsby1, _lsp_x2, _lsby2);
	        draw_set_color(_lsp_hov ? c_white : c_aqua);
	        draw_text(_lsp_x1 + 6, _lsr_y, "<");
	        if (_lsp_hov && mouse_check_button_pressed(mb_left)) {
	            label_search_index = (label_search_index - 1 + _lsr_count) mod _lsr_count;
	            if (instance_exists(label_search_results[label_search_index])) {
	                scr_focus_camera_on_node_offset(label_search_results[label_search_index], 0.2);
	                camera_set_view_pos(cam_view, cam_x, cam_y);
	            }
	        }

	        // > next
	        var _lsn_x1  = _lsp_x2 + 8;
	        var _lsn_x2  = _lsn_x1 + 24;
	        var _lsn_hov = point_in_rectangle(gui_mouse_x, gui_mouse_y, _lsn_x1, _lsby1, _lsn_x2, _lsby2);
	        draw_set_color(_lsn_hov ? c_white : c_aqua);
	        draw_text(_lsn_x1 + 6, _lsr_y, ">");
	        if (_lsn_hov && mouse_check_button_pressed(mb_left)) {
	            label_search_index = (label_search_index + 1) mod _lsr_count;
	            if (instance_exists(label_search_results[label_search_index])) {
	                scr_focus_camera_on_node_offset(label_search_results[label_search_index], 0.2);
	                camera_set_view_pos(cam_view, cam_x, cam_y);
	            }
	        }

	        // Current label name
	        if (instance_exists(label_search_results[label_search_index])) {
	            var _lscur      = label_search_results[label_search_index];
	            var _lscur_name = (array_length(_lscur.instructions) > 0 && array_length(_lscur.instructions[0]) > 1)
	                             ? string(_lscur.instructions[0][1]) : "";
	            draw_set_font(fnt_c64_tiny);
	            draw_set_color(c_white);
	            draw_text(_lsr_x, _lsr_y + 20, _lscur_name);
	        }
	    } else if (label_search_query != "") {
	        draw_set_color(c_red);
	        draw_text(_lsr_x, _lsr_y, "NO MATCHES");
	    }
	}

	// FINDER
	
	if (global.show_map_nav) {
	    var _nav_x = global.map_nav_x;
	    var _nav_y = global.map_nav_y;
	    var _row_h = 20;
	    var _pw    = 200;

	    // build list
	    var _boxes = [];
	    with (obj_mapping_box) array_push(_boxes, id);

	    // background
	    draw_set_color(make_color_rgb(20, 20, 30));
	    draw_rectangle(_nav_x, _nav_y, _nav_x + _pw, _nav_y + 20 + array_length(_boxes) * _row_h + 8, false);
	    draw_set_color(c_gray);
	    draw_rectangle(_nav_x, _nav_y, _nav_x + _pw, _nav_y + 20 + array_length(_boxes) * _row_h + 8, true);

	    // header
	    draw_set_font(fnt_c64_tiny);
	    draw_set_color(make_color_rgb(120, 120, 180));
	    draw_text(_nav_x + 4, _nav_y + 4, "JUMP TO MAP BOX");

	    // rows
	    for (var _i = 0; _i < array_length(_boxes); _i++) {
	        var _box  = _boxes[_i];
	        var _ry   = _nav_y + 20 + (_i * _row_h);
	        var _rhov = point_in_rectangle(global.gui_mouse_x, global.gui_mouse_y,
	                    _nav_x, _ry, _nav_x + _pw, _ry + _row_h);
	        draw_set_color(_rhov ? make_color_rgb(40, 80, 120) : make_color_rgb(25, 25, 38));
	        draw_rectangle(_nav_x, _ry, _nav_x + _pw, _ry + _row_h, false);
	        draw_set_color(_rhov ? c_white : c_aqua);
	        draw_text(_nav_x + 6, _ry + 3, _box.box_name);
	    }
	}
	
/////////////////////////////////////////////////////////////////
///// 8. HELPER OVERLAY
/////////////////////////////////////////////////////////////////
if (global.show_helper_window && instance_exists(global.helper_node)) {
    if (!variable_instance_exists(id, "helper_timer")) helper_timer = 0;
    helper_timer++;

    draw_set_alpha(0.7);
    draw_set_color(c_black);
    draw_rectangle(0, 0, gui_w, gui_h, false);
    draw_set_alpha(1.0);

    var _hw  = 600;
    var _hh  = 400;
    var _hx1 = (gui_w / 2) - (_hw / 2);
    var _hy1 = (gui_h / 2) - (_hh / 2);
    var _hx2 = _hx1 + _hw;
    var _hy2 = _hy1 + _hh;

    draw_set_color(make_color_rgb(20, 30, 20));
    draw_rectangle(_hx1, _hy1, _hx2, _hy2, false);
    draw_set_color(make_color_rgb(40, 180, 80));
    draw_rectangle(_hx1, _hy1, _hx2, _hy2, true);

    var _node = global.helper_node;

    draw_set_font(fnt_C64_Angled_big);
    draw_set_color(make_color_rgb(40, 200, 80));
    draw_set_halign(fa_center);
    draw_text(gui_w / 2, _hy1 + 16, string_upper(_node.node_type) + " - WHAT DOES THIS DO?");

    var _desc = "";
    if (_node.node_type == "MACRO_SPR") {
        _desc = "Positions a hardware sprite using the VIC-II chip. Writes the sprite pointer, X/Y coordinates and enable bit directly to VIC registers - 25 bytes, zero overhead.";
    } else if (_node.node_type == "MACRO_SID") {
        _desc = "Arms the SID chip with a raster IRQ music player. Clears all SID registers, initialises the chosen track, redirects the KERNAL IRQ vector to an internal handler and calls the play routine every screen refresh - no mainloop cost.";
    } else if (_node.node_type == "MACRO_TRACK") {
        _desc = "Polls the keyboard each frame and routes control to labelled destinations based on which key is pressed. Ideal for track selection menus - reads the CIA matrix directly, no KERNAL dependency.";
    } else if (_node.node_type == "MACRO_PRINT") {
        _desc = "Writes a text string to the C64 screen at a specified X/Y position and colour. Converts PETSCII in a tight indexed loop - optional clear screen wipes $0400 to $07E7 preserving sprite pointers at $07F8.";
    } else if (_node.node_type == "MACRO_JOY") {
        _desc = "Reads a joystick port via the CIA chip and branches to labelled destinations based on directional input and fire combinations. Stores the live state to a zero page address for fast re-reads elsewhere in your code.";
	} else if (_node.node_type == "MACRO_VIC") {
    _desc = "Configures the VIC-II chip for the selected display mode. Sets bank, screen RAM, char/bitmap pointers, border and background colours. Supports TEXT, MCT, ECM, BITMAP and MCB modes - safe RMW on $DD00 preserves CIA serial bus bits.";
	
	} else if (_node.node_type == "MACRO_IRQ") {
        _desc = "Fires your code automatically at a specific screen scanline every frame. Set the raster line, pick a CALL label pointing to your subroutine, and it runs at that line 50 times per second without touching your main loop. Multiple MACRO_IRQ nodes daisy-chain automatically sorted by raster line. Requires KERNAL RAM UNLOCK on your spine. Your CALL routine must end with RTS.";
    } else if (_node.node_type == "MACRO_SCROLL") {
        _desc = "Horizontal map scroller using dual screen buffers at $0400 and $0C00. JSR Scroller_L each frame to scroll left, JSR Scroller_R to scroll right. Fine scroll via $D016 bits 0-2, coarse step loads one new column from MAP_DATA and flips $D018. Colour mode 0=none, 1=deferred, 2=inline. Combine with MACRO_VSCROLL by JSRing both entry points per frame.";
    } else if (_node.node_type == "MACRO_VSCROLL") {
        _desc = "Vertical map scroller using dual screen buffers at $0400 and $0C00. JSR Scroller_U each frame to scroll up, JSR Scroller_D to scroll down. Fine scroll via $D011 bits 0-2 shadow register, coarse step copies 24 rows into inactive buffer shifted by one row, loads new edge row, flips $D018. Safe to combine with MACRO_SCROLL - JSR both entry points in the same frame routine.";
    }

    draw_set_font(fnt_C64_Angled);
    draw_set_color(c_white);
    draw_set_halign(fa_left);
    draw_text_ext(gui_w / 2 - _hw / 2 + 20, _hy1 + 50, _desc, 20, _hw - 40);

    if (helper_timer > 60) {
        draw_set_font(fnt_c64_tiny);
        draw_set_color(c_gray);
        draw_set_halign(fa_center);
        draw_text(gui_w / 2, _hy2 - 18, "CLICK ANYWHERE TO CLOSE");
        draw_set_halign(fa_left);

        if (mouse_check_button_pressed(mb_any) || keyboard_check_pressed(vk_escape)) {
            global.show_helper_window = false;
            helper_timer = 0;
        }
    }
}

// DEBUG: undo state at mouse
if (keyboard_check(vk_control)) {
    var _undo_dir      = working_directory + "temp/undo/";
    var _manifest_path = _undo_dir + "manifest.json";
    var _state_str = "NO MANIFEST";
    if (file_exists(_manifest_path)) {
        var _f = file_text_open_read(_manifest_path);
        var _raw = "";
        while (!file_text_eof(_f)) { _raw += file_text_read_string(_f); file_text_readln(_f); }
        file_text_close(_f);
        var _m = json_parse(_raw);
        _state_str = "UNDO STATE " + string(_m.current + 1) + "/" + string(array_length(_m.states))                  
    }
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_yellow);
    draw_set_halign(fa_left);
    draw_text(global.gui_mouse_x + 14, global.gui_mouse_y + 14, _state_str);
}

// DEBUG: zoom level
// Autosave countdown display
if (global.autosave_dirty && autosave_countdown > 0 && autosave_countdown <= 5.5) {
    var _cd     = min(6, ceil(autosave_countdown));
    var _alpha  = lerp(1.0, 0.5, (_cd - 1) / 4.0);
    var _cd_str = (_cd <= 1) ? "SAVING..." : ("AUTOSAVE IN " + string(_cd-1) + "...");
    var _box_col = (_cd <= 1) ? c_lime : c_yellow;
    draw_set_font(fnt_C64_Angled_big);
    var _tw  = string_width(_cd_str);
    var _th  = string_height(_cd_str);
    var _px  = (gui_w / 2) - (_tw / 2) - 20;
    var _py  = (gui_h / 2) - 80;
    var _pw  = _tw + 40;
    var _ph  = _th + 20;
    draw_set_alpha(_alpha);
    draw_set_color(c_black);
    draw_rectangle(_px, _py, _px + _pw, _py + _ph, false);
	
	draw_set_color(_box_col);
    draw_rectangle(_px - 3, _py - 3, _px + _pw + 3, _py + _ph + 3, true);
    draw_rectangle(_px - 6, _py - 6, _px + _pw + 6, _py + _ph + 6, true);
    draw_set_color(_box_col);
	
    draw_set_halign(fa_center);
    draw_text(_px + _pw / 2, _py + 10, _cd_str);
    draw_set_halign(fa_left);
    draw_set_alpha(1.0);
}

// Manual save (CTRL+S) in-progress flash
if (global.isSaving) {
    var _msg = "SAVING...";
    draw_set_font(fnt_C64_Angled_big);
    var _tw  = string_width(_msg);
    var _th  = string_height(_msg);
    var _px  = (gui_w / 2) - (_tw / 2) - 20;
    var _py  = (gui_h / 2) - 80;
    var _pw  = _tw + 40;
    var _ph  = _th + 20;
    draw_set_alpha(1.0);
    draw_set_color(c_black);
    draw_rectangle(_px, _py, _px + _pw, _py + _ph, false);
    draw_set_color(c_lime);
    draw_rectangle(_px - 3, _py - 3, _px + _pw + 3, _py + _ph + 3, true);
    draw_rectangle(_px - 6, _py - 6, _px + _pw + 6, _py + _ph + 6, true);
    draw_set_color(c_lime);
    draw_set_halign(fa_center);
    draw_text(_px + _pw / 2, _py + 10, _msg);
    draw_set_halign(fa_left);
    draw_set_alpha(1.0);
}

// Autosave confirmation flash
if (autosave_flash_timer > 0) {
    autosave_flash_timer--;
    var _total = game_get_speed(gamespeed_fps) * 3;
    var _fade  = autosave_flash_timer / _total;
    var _msg   = "AUTOSAVED";
    draw_set_font(fnt_C64_Angled_big);
    var _tw  = string_width(_msg);
    var _th  = string_height(_msg);
    var _px  = (gui_w / 2) - (_tw / 2) - 20;
    var _py  = (gui_h / 2) - 80;
    var _pw  = _tw + 40;
    var _ph  = _th + 20;
    draw_set_alpha(_fade);
    draw_set_color(c_black);
    draw_rectangle(_px, _py, _px + _pw, _py + _ph, false);
    draw_set_color(c_lime);
    draw_rectangle(_px - 3, _py - 3, _px + _pw + 3, _py + _ph + 3, true);
    draw_rectangle(_px - 6, _py - 6, _px + _pw + 6, _py + _ph + 6, true);
    draw_set_color(c_lime);
    draw_set_halign(fa_center);
    draw_text(_px + _pw / 2, _py + 10, _msg);
    draw_set_halign(fa_left);
    draw_set_alpha(1.0);
}

draw_set_font(fnt_c64_tiny);
draw_set_color(c_white);
draw_text(10, 1040, "ZOOM: " + string(cam_zoom));

//color ref palette:
var _psc = 0.8
if showPaletteHelper draw_sprite_ext(spr_palette,0, 1640,980,_psc,_psc,0,c_white,1)

// --- C64U status toast ---
if (global.c64u_status_t > 0) {
    draw_set_font(fnt_C64_Angled_big);
    draw_set_halign(fa_center);
    draw_set_valign(fa_top);
    draw_set_colour(c_white);
    draw_text(1920/2, 80 , global.c64u_status);   
	draw_set_halign(fa_left);
	global.c64u_status_t -= 1;
	
}

// ============================================================
// VARIABLE DELETE — BLOCKED REFERENCE WARNING (left side)
// Populated by the RMB-delete guard in obj_c64_node Step.
// Holds until first click, then fades over 3s. Rows jump the camera.
// ============================================================
if (global.var_del_warn_active) {

    var _vw_alpha = 1.0;
    if (global.var_del_warn_clicked) {
        _vw_alpha = global.var_del_warn_fade;
    }

    if (_vw_alpha <= 0) {
        global.var_del_warn_active = false;
        global.var_del_warn_refs   = [];
    } else {
        var _vw_count    = array_length(global.var_del_warn_refs);
        var _vw_x1       = shelf_width + 40;
        var _vw_y1       = 120;
        var _vw_w        = 400;
        var _vw_row_h    = 22;
        var _vw_hdr_h    = 46;
        var _vw_max_rows = 14;
        var _vw_vis      = _vw_count;
        if (_vw_vis > _vw_max_rows) {
            _vw_vis = _vw_max_rows;
        }
        var _vw_h          = _vw_hdr_h + (_vw_vis * _vw_row_h) + 10;
        var _vw_x2         = _vw_x1 + _vw_w;
        var _vw_max_scroll = max(0, (_vw_count - _vw_max_rows) * _vw_row_h);

        // Scroll input (only while fully visible, before dismissal)
        if (!global.var_del_warn_clicked) {
            var _vw_in = (gui_mouse_x >= _vw_x1 && gui_mouse_x <= _vw_x2 &&
                          gui_mouse_y >= _vw_y1 && gui_mouse_y <= _vw_y1 + _vw_h);
            if (_vw_in) {
                if (mouse_wheel_up())   global.var_del_warn_scroll = max(0, global.var_del_warn_scroll - _vw_row_h);
                if (mouse_wheel_down()) global.var_del_warn_scroll = min(_vw_max_scroll, global.var_del_warn_scroll + _vw_row_h);
            }
            if (keyboard_check_pressed(vk_up))   global.var_del_warn_scroll = max(0, global.var_del_warn_scroll - _vw_row_h);
            if (keyboard_check_pressed(vk_down)) global.var_del_warn_scroll = min(_vw_max_scroll, global.var_del_warn_scroll + _vw_row_h);
        }

        // Panel
        draw_set_alpha(0.9 * _vw_alpha);
        draw_set_color(make_color_rgb(40, 12, 12));
        draw_rectangle(_vw_x1, _vw_y1, _vw_x2, _vw_y1 + _vw_h, false);
        draw_set_alpha(_vw_alpha);
        draw_set_color(make_color_rgb(200, 60, 60));
        draw_rectangle(_vw_x1, _vw_y1, _vw_x2, _vw_y1 + _vw_h, true);

        // Header
        draw_set_font(fnt_C64_Angled);
        draw_set_halign(fa_left);
        draw_set_color(make_color_rgb(255, 90, 90));
        draw_text(_vw_x1 + 10, _vw_y1 + 6, "CANNOT DELETE " + global.var_del_warn_name);

        var _vw_plural = "S";
        if (_vw_count == 1) {
            _vw_plural = "";
        }
        draw_set_font(fnt_c64_tiny);
        draw_set_color(make_color_rgb(220, 160, 160));
        var _vw_sub = "REFERENCED BY " + string(_vw_count) + " NODE" + _vw_plural + ". CLICK A ROW TO JUMP";
        if (global.var_del_warn_batch > 1) {
            _vw_sub = string(global.var_del_warn_batch) + " VARS REFERENCED BY " +
                      string(_vw_count) + " NODE" + _vw_plural + ". CLICK A ROW TO JUMP";
        }
        draw_text(_vw_x1 + 10, _vw_y1 + 30, _vw_sub);

        // Rows (clipped)
        var _vw_ly      = _vw_y1 + _vw_hdr_h - global.var_del_warn_scroll;
        var _vw_clip_y1 = _vw_y1 + _vw_hdr_h;
        var _vw_clip_y2 = _vw_y1 + _vw_h - 6;
        draw_set_font(fnt_C64_Angled);

        for (var _vwi = 0; _vwi < _vw_count; _vwi++) {
            var _vw_ry = _vw_ly + (_vwi * _vw_row_h);
            if (_vw_ry + _vw_row_h <= _vw_clip_y1) continue;
            if (_vw_ry >= _vw_clip_y2) break;

            var _vw_ref = global.var_del_warn_refs[_vwi];

            var _vw_hov = false;
            if (gui_mouse_x >= _vw_x1 + 4 && gui_mouse_x <= _vw_x2 - 4 &&
                gui_mouse_y >= _vw_ry && gui_mouse_y <= _vw_ry + _vw_row_h &&
                _vw_ry >= _vw_clip_y1 && _vw_ry + _vw_row_h <= _vw_clip_y2) {
                _vw_hov = true;
            }

            if (_vw_hov) {
                draw_set_alpha(0.35 * _vw_alpha);
                draw_set_color(c_white);
                draw_rectangle(_vw_x1 + 4, _vw_ry, _vw_x2 - 4, _vw_ry + _vw_row_h, false);
                draw_set_alpha(_vw_alpha);
            }

            if (_vw_hov) {
                draw_set_color(c_yellow);
            } else {
                draw_set_color(make_color_rgb(230, 210, 210));
            }
            draw_text(_vw_x1 + 12, _vw_ry + 3, string(_vwi + 1) + ". " + string(_vw_ref.label));

            if (_vw_hov && mouse_check_button_pressed(mb_left) && instance_exists(_vw_ref.node)) {
                scr_focus_camera_on_node(_vw_ref.node);
                global.var_del_warn_clicked = true; // begin fade
            }
        }

        // Scrollbar
        if (_vw_max_scroll > 0) {
            var _vw_sb_x  = _vw_x2 - 7;
            var _vw_sb_y1 = _vw_clip_y1 + 2;
            var _vw_sb_y2 = _vw_clip_y2 - 2;
            var _vw_sb_h  = _vw_sb_y2 - _vw_sb_y1;
            var _vw_th_h  = max(20, _vw_sb_h * (_vw_max_rows / _vw_count));
            var _vw_th_y  = _vw_sb_y1 + (_vw_sb_h - _vw_th_h) * (global.var_del_warn_scroll / _vw_max_scroll);
            draw_set_alpha(_vw_alpha);
            draw_set_color(make_color_rgb(60, 20, 20));
            draw_rectangle(_vw_sb_x, _vw_sb_y1, _vw_sb_x + 5, _vw_sb_y2, false);
            draw_set_color(make_color_rgb(200, 80, 80));
            draw_rectangle(_vw_sb_x, _vw_th_y, _vw_sb_x + 5, _vw_th_y + _vw_th_h, false);
        }

        draw_set_alpha(1.0);

        // First click anywhere begins the fade (row clicks handled above also set this)
        if (!global.var_del_warn_clicked && mouse_check_button_pressed(mb_left)) {
            global.var_del_warn_clicked = true;
        }

        // Fade decay once dismissed (3s, frame-rate scaled)
        if (global.var_del_warn_clicked) {
            global.var_del_warn_fade -= 1 / (game_get_speed(gamespeed_fps) * 3);
            if (global.var_del_warn_fade < 0) {
                global.var_del_warn_fade = 0;
            }
        }

        draw_set_halign(fa_left);
    }
}

// --- C64U IP entry overlay (drawn last so it sits on top) ---
scr_c64u_overlay_draw();

// --- Q quick-spawn menu (drawn absolute last so it's always on top) ---
if (qmenu_active && qmenu_open) {
    draw_set_font(fnt_c64_tiny);
    for (var _qi = 0; _qi < array_length(qmenu_items); _qi++) {
        var _qr  = scr_qmenu_layout(_qi, qmenu_gui_x, qmenu_gui_y);
        var _hov = (qmenu_hover == _qi);
        draw_set_color(make_color_rgb(10, 10, 20));
        draw_rectangle(_qr[0], _qr[1], _qr[2], _qr[3], false);
        draw_set_color(_hov ? make_color_rgb(200, 160, 40) : make_color_rgb(90, 90, 90));
        draw_rectangle(_qr[0], _qr[1], _qr[2], _qr[3], true);
        draw_set_color(_hov ? c_white : c_aqua);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_text((_qr[0] + _qr[2]) / 2, (_qr[1] + _qr[3]) / 2, qmenu_items[_qi].label);
    }
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_color(c_white);
    draw_circle(qmenu_gui_x, qmenu_gui_y, 2, false);
}

// --- Q custom quick-spawn menu (user-built, circular) ---
if (uqmenu_active && uqmenu_open) {
    var _ucount = array_length(global.user_quick_menu);
    draw_set_font(fnt_c64_tiny);
    if (_ucount == 0) {
        draw_set_halign(fa_center);
        draw_set_color(c_ltgray);
        draw_text(uqmenu_gui_x, uqmenu_gui_y - 8, "QUICK MENU EMPTY");
        draw_text(uqmenu_gui_x, uqmenu_gui_y + 6, "SHIFT+Q A MACRO TO ADD");
        draw_set_halign(fa_left);
    } else {
        for (var _ui = 0; _ui < _ucount; _ui++) {
            var _ur   = scr_uqmenu_layout_circular(_ui, _ucount, uqmenu_gui_x, uqmenu_gui_y, global.user_quick_menu[_ui].label);
            var _uhov = (uqmenu_hover == _ui);
            draw_set_color(make_color_rgb(10, 10, 20));
            draw_rectangle(_ur[0], _ur[1], _ur[2], _ur[3], false);
            draw_set_color(_uhov ? make_color_rgb(200, 160, 40) : make_color_rgb(90, 90, 90));
            draw_rectangle(_ur[0], _ur[1], _ur[2], _ur[3], true);
            draw_set_color(_uhov ? c_white : c_aqua);
            draw_set_halign(fa_center);
            draw_set_valign(fa_middle);
            draw_text((_ur[0] + _ur[2]) / 2, (_ur[1] + _ur[3]) / 2, global.user_quick_menu[_ui].label);
        }
        draw_set_halign(fa_left);
        draw_set_valign(fa_top);
    }
    draw_set_color(c_white);
    draw_circle(uqmenu_gui_x, uqmenu_gui_y, 2, false);
}

// --- WELCOME SCREEN (drawn absolute last, on top of everything) ---
if (welcome_open) {
    var _pw = 560;
    var _ph = 560;
    var _px = (global.gui_w - _pw) / 2;
    var _py = (display_get_gui_height() - _ph) / 2;

    draw_set_color(c_black);
    draw_set_alpha(0.55);
    draw_rectangle(0, 0, global.gui_w, display_get_gui_height(), false);
    draw_set_alpha(1.0);

    draw_sprite_stretched(spr_welcome_panel, 0, _px, _py, _pw, _ph);

    var _wmx = device_mouse_x_to_gui(0);
    var _wmy = device_mouse_y_to_gui(0);

    // Title
    draw_set_font(fnt_C64_Angled);
    draw_set_halign(fa_center);
    draw_set_color(c_white);
    draw_text(_px + _pw / 2, _py + 16, "WELCOME TO C64 DEV MACHINE");
    draw_set_font(fnt_c64_tiny);
    draw_set_color(make_color_rgb(200, 160, 40));
    draw_text(_px + _pw / 2, _py + 40, "VERSION: " + string(GM_version) + "   DATE: " + global.build_date);
    draw_set_halign(fa_left);

    // What's New
    var _wy = _py + 70;
    draw_set_font(fnt_C64_Angled);
    draw_set_color(make_color_rgb(220, 140, 40));
    draw_text(_px + 20, _wy, "WHAT'S NEW?");
    _wy += 22;
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_aqua);
    for (var _wi = 0; _wi < array_length(welcome_whats_new); _wi++) {
        draw_text(_px + 30, _wy, "- " + welcome_whats_new[_wi]);
        _wy += 16;
    }

    // Credits header
    _wy += 14;
    draw_set_font(fnt_C64_Angled);
    draw_set_color(make_color_rgb(220, 140, 40));
    draw_set_halign(fa_center);
    draw_text(_px + _pw / 2, _wy, "CREDITS");
    draw_set_halign(fa_left);
    _wy += 22;

    // Scissored, auto-scrolling credits crawl
    var _cr_x1 = _px + 20;
    var _cr_y1 = _wy;
    var _cr_x2 = _px + _pw - 20;
    var _cr_y2 = _cr_y1 + 180;
    var _cr_line_h = 16;

    var _sx_sc = window_get_width()  / global.gui_w;
    var _sy_sc = window_get_height() / display_get_gui_height();
    gpu_set_scissor(
        floor(_cr_x1 * _sx_sc),
        floor(_cr_y1 * _sy_sc),
        ceil((_cr_x2 - _cr_x1) * _sx_sc),
        ceil((_cr_y2 - _cr_y1) * _sy_sc)
    );

    draw_set_font(fnt_c64_tiny);
    var _cr_start_y = _cr_y2 - welcome_credits_y;
    for (var _ci = 0; _ci < array_length(welcome_credits_lines); _ci++) {
        var _cly = _cr_start_y + (_ci * _cr_line_h);
        if (_cly > _cr_y1 - _cr_line_h && _cly < _cr_y2 + _cr_line_h) {
            var _ctxt      = welcome_credits_lines[_ci];
            var _is_header = (_ctxt == "CODE and DESIGN" || _ctxt == "COMMUNITY INPUT" || _ctxt == "And...");
            draw_set_color(_is_header ? make_color_rgb(220, 140, 40) : c_white);
            draw_set_halign(fa_center);
            draw_text(_px + _pw / 2, _cly, _ctxt);
            draw_set_halign(fa_left);
        }
    }

    gpu_set_scissor(0, 0, window_get_width(), window_get_height());

    // Checkbox
    var _chkx1   = _px + 20;
    var _chky1   = _py + _ph - 40;
    var _chkx2   = _chkx1 + 18;
    var _chky2   = _chky1 + 18;
    var _chk_hov = point_in_rectangle(_wmx, _wmy, _chkx1, _chky1, _chkx2, _chky2);
    draw_set_color(_chk_hov ? make_color_rgb(200, 160, 40) : make_color_rgb(90, 90, 90));
    draw_rectangle(_chkx1, _chky1, _chkx2, _chky2, true);
    if (welcome_hide_checked) {
        draw_set_color(make_color_rgb(200, 160, 40));
        draw_text(_chkx1 + 3, _chky1 - 2, "X");
    }
    draw_set_font(fnt_c64_tiny);
    draw_set_color(c_white);
    draw_text(_chkx2 + 8, _chky1, "DON'T SHOW ON STARTUP");
    draw_set_color(make_color_rgb(140, 140, 140));
    draw_text(_chkx2 + 8, _chky1 + 14, welcome_hide_checked ? "(currently: hidden on startup)" : "(currently: shows on startup)");

    // Close button
    var _cbx1   = _px + _pw - 36;
    var _cby1   = _py + 8;
    var _cbx2   = _cbx1 + 28;
    var _cby2   = _cby1 + 28;
    var _cb_hov = point_in_rectangle(_wmx, _wmy, _cbx1, _cby1, _cbx2, _cby2);
    draw_set_color(_cb_hov ? make_color_rgb(200, 60, 60) : make_color_rgb(90, 90, 90));
    draw_rectangle(_cbx1, _cby1, _cbx2, _cby2, false);
    draw_set_color(c_white);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_text((_cbx1 + _cbx2) / 2, (_cby1 + _cby2) / 2, "X");
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
}
