/// ====================================================================
/// CREATOR LAYER
///
/// A safe "skin" over a workspace. The developer (Pro) exposes values on
/// macro and code block nodes through the PARAMS tab on the node's right
/// side. The Creator view then lists only those values — colour swatches,
/// ranges and named modes — plus build / run / save / load. Everything else
/// is locked: the panel owns input through scr_workspace_input_blocked().
///
/// LIGHT: a workspace saved with creator_locked opens in the Creator view
///        and cannot leave it. No PARAMS tabs are shown.
/// PRO:   F9 toggles the Creator view, EDIT GRAPH leaves it, and the
///        OPENS LOCKED switch decides how the workspace opens next time.
///
/// TARGETS
///   MACRO_CODE: a `NAME = value` line inside the code block (sym).
///   Other macros: instructions[row][slot].
/// The node itself stays the single source of truth for every value.
///
/// MODE params pair with .IF NAME == n / .ELSE / .ENDIF in code blocks
/// (scr_asm_preprocess_if): only the chosen branch is assembled.
/// ====================================================================

#macro CREATOR_MAX_PARAMS 8

function scr_creator_init() {
    global.creator_locked       = false;   // saved per workspace
    global.creator_view_open    = false;
    global.creator_edit_node    = noone;
    global.creator_open_pending = false;
    global.creator_open_frame   = -1;
    global.creator_tab_hot      = noone;
    global.creator_action       = "";      // deferred to Begin Step
    global.creator_scroll       = 0;
    global.creator_mx           = 0;
    global.creator_my           = 0;
    global.creator_click        = false;
    global.creator_field        = "";
    global.creator_field_text   = "";
    global.creator_field_rect   = [0, 0, 0, 0];
    global.creator_commit       = false;
    global.creator_esc_eaten    = false;
}

// --------------------------------------------------------------------
// PARAM DATA
// --------------------------------------------------------------------

function scr_param_new() {
    return {
        label:   "PARAM",
        kind:    "COLOUR",     // COLOUR, RANGE, MODE
        sym:     "",           // MACRO_CODE target symbol
        row:     0,            // macro target row
        slot:    1,            // macro target slot
        vmin:    0,
        vmax:    255,
        options: "Off=0,On=1"  // MODE: Label=value, comma separated
    };
}

/// Saved data may come from older or hand-written files, so every field is
/// copied onto a fully initialised param rather than trusted as-is.
function scr_param_from_data(_d) {
    var _p = scr_param_new();
    if (!is_struct(_d)) {
        return _p;
    }
    if (variable_struct_exists(_d, "label"))   _p.label   = string(_d.label);
    if (variable_struct_exists(_d, "kind"))    _p.kind    = string_upper(string(_d.kind));
    if (variable_struct_exists(_d, "sym"))     _p.sym     = string_upper(string(_d.sym));
    if (variable_struct_exists(_d, "row"))     _p.row     = max(0, round(real(_d.row)));
    if (variable_struct_exists(_d, "slot"))    _p.slot    = max(1, round(real(_d.slot)));
    if (variable_struct_exists(_d, "vmin"))    _p.vmin    = real(_d.vmin);
    if (variable_struct_exists(_d, "vmax"))    _p.vmax    = real(_d.vmax);
    if (variable_struct_exists(_d, "options")) _p.options = string(_d.options);
    if (_p.kind != "COLOUR" && _p.kind != "RANGE" && _p.kind != "MODE") {
        _p.kind = "COLOUR";
    }
    return _p;
}

/// @param _d  one saved node record
function scr_creator_params_from_data(_d) {
    var _out = [];
    if (!variable_struct_exists(_d, "params")) {
        return _out;
    }
    if (!is_array(_d.params)) {
        return _out;
    }
    for (var _i = 0; _i < array_length(_d.params); _i++) {
        if (_i >= CREATOR_MAX_PARAMS) {
            break;
        }
        array_push(_out, scr_param_from_data(_d.params[_i]));
    }
    return _out;
}

/// MODE options "Off=0,Slow=1,Fast=2" -> [{name, val}]. An option with no
/// "=value" takes its position as the value.
function scr_param_options(_str) {
    var _out   = [];
    var _parts = string_split(string(_str), ",");
    for (var _i = 0; _i < array_length(_parts); _i++) {
        var _part = string_trim(_parts[_i]);
        if (_part == "") {
            continue;
        }
        var _eq   = string_pos("=", _part);
        var _name = _part;
        var _val  = array_length(_out);
        if (_eq > 0) {
            _name = string_trim(string_copy(_part, 1, _eq - 1));
            _val  = _asm_val(string_trim(string_delete(_part, 1, _eq)));
        }
        array_push(_out, { name: _name, val: _val });
    }
    return _out;
}

function scr_creator_num(_s) {
    return _asm_val(string_trim(string(_s)));
}

function scr_creator_node_name(_n) {
    if (_n.custom_title != "") {
        return _n.custom_title;
    }
    if (_n.node_type == "MACRO_CODE") {
        return _n.code_descriptor;
    }
    return _n.node_title;
}

function scr_creator_param_count() {
    var _c = 0;
    with (obj_c64_node) {
        _c += array_length(params);
    }
    return _c;
}

// --------------------------------------------------------------------
// CODE BLOCK CONSTANTS  (NAME = value lines)
// --------------------------------------------------------------------

/// @return {struct} { found, line, val_str }
function scr_code_const_find(_text, _sym) {
    var _res   = { found: false, line: -1, val_str: "" };
    var _want  = string_upper(string_trim(_sym));
    if (_want == "") {
        return _res;
    }
    var _lines = string_split(string(_text), "\n");
    for (var _i = 0; _i < array_length(_lines); _i++) {
        var _ln   = _lines[_i];
        var _semi = string_pos(";", _ln);
        if (_semi > 0) {
            _ln = string_copy(_ln, 1, _semi - 1);
        }
        _ln = string_trim(_ln);
        var _eq = string_pos("=", _ln);
        if (_eq <= 1) {
            continue;
        }
        if (string_char_at(_ln, 1) == ".") {
            continue;
        }
        var _name = string_upper(string_trim(string_copy(_ln, 1, _eq - 1)));
        if (_name == _want) {
            _res.found   = true;
            _res.line    = _i;
            _res.val_str = string_trim(string_delete(_ln, 1, _eq));
            return _res;
        }
    }
    return _res;
}

/// Keep the author's number style: $hex stays hex, decimal stays decimal.
function scr_creator_format_like(_old, _v) {
    _old = string_trim(_old);
    if (string_char_at(_old, 1) == "$") {
        var _h   = string_upper(decimal_to_hex(_v));
        var _len = 2;
        if (_v > 255) {
            _len = 4;
        }
        while (string_length(_h) < _len) {
            _h = "0" + _h;
        }
        return "$" + _h;
    }
    if (string_char_at(_old, 1) == "%") {
        var _b = "";
        var _w = _v;
        for (var _bi = 0; _bi < 8; _bi++) {
            _b = string(_w & 1) + _b;
            _w = _w >> 1;
        }
        return "%" + _b;
    }
    return string(_v);
}

/// Rewrites only the value of the matching line; indentation, name and any
/// trailing ; comment are kept.
function scr_code_const_set(_text, _sym, _v) {
    var _hit = scr_code_const_find(_text, _sym);
    if (!_hit.found) {
        return _text;
    }
    var _lines   = string_split(string(_text), "\n");
    var _ln      = _lines[_hit.line];
    var _eq      = string_pos("=", _ln);
    var _head    = string_copy(_ln, 1, _eq);
    var _rest    = string_delete(_ln, 1, _eq);
    var _comment = "";
    var _semi    = string_pos(";", _rest);
    if (_semi > 0) {
        _comment = " " + string_copy(_rest, _semi, string_length(_rest) - _semi + 1);
    }
    _lines[_hit.line] = _head + " " + scr_creator_format_like(_hit.val_str, _v) + _comment;

    var _out = "";
    for (var _i = 0; _i < array_length(_lines); _i++) {
        if (_i > 0) {
            _out += "\n";
        }
        _out += _lines[_i];
    }
    return _out;
}

// --------------------------------------------------------------------
// READ / WRITE A PARAM ON ITS NODE
// --------------------------------------------------------------------

/// @return {struct} { ok, val }
function scr_param_read(_n, _p) {
    var _res = { ok: false, val: 0 };
    if (!instance_exists(_n)) {
        return _res;
    }
    if (_n.node_type == "MACRO_CODE") {
        if (array_length(_n.instructions) == 0) {
            return _res;
        }
        var _hit = scr_code_const_find(_n.instructions[0][1], _p.sym);
        if (_hit.found) {
            _res.ok  = true;
            _res.val = _asm_val(_hit.val_str);
        }
        return _res;
    }
    if (_p.row >= array_length(_n.instructions)) {
        return _res;
    }
    var _row = _n.instructions[_p.row];
    if (!is_array(_row)) {
        return _res;
    }
    if (_p.slot >= array_length(_row)) {
        return _res;
    }
    if (is_numeric(_row[_p.slot])) {
        _res.ok  = true;
        _res.val = _row[_p.slot];
    }
    return _res;
}

function scr_param_write(_n, _p, _v) {
    if (!instance_exists(_n)) {
        return;
    }
    if (_p.kind == "RANGE") {
        _v = clamp(round(_v), min(_p.vmin, _p.vmax), max(_p.vmin, _p.vmax));
    }
    if (_p.kind == "COLOUR") {
        _v = clamp(round(_v), 0, 15);
    }
    var _cur = scr_param_read(_n, _p);
    if (!_cur.ok) {
        return;
    }
    if (_cur.val == _v) {
        return;
    }
    if (_n.node_type == "MACRO_CODE") {
        _n.instructions[0][1] = scr_code_const_set(_n.instructions[0][1], _p.sym, _v);
    } else {
        _n.instructions[_p.row][_p.slot] = _v;
    }
    scr_creator_node_changed(_n);
}

function scr_creator_node_changed(_n) {
    with (_n) {
        height_dirty      = true;
        draw_cache_dirty  = true;
        stats_cache_dirty = true;
        code_cache_dirty  = true;
        macro_layout_type = "";
    }
    global.undo_dirty        = true;
    global.node_change_dirty = true;
    global.addresses_dirty   = true;
    global.autosave_dirty    = true;
    scr_c64_do_update_addresses();
    with (obj_c64_node) {
        last_overlap_check  = false;
        overlap_check_dirty = true;
        stats_cache_dirty   = true;
        if (node_type == "MACRO_CODE") {
            code_cache_dirty = true;
        }
    }
    with (obj_workspace_manager) {
        alarm[3] = 6;
    }
}

// --------------------------------------------------------------------
// PANEL STATE
// --------------------------------------------------------------------

/// True while a Creator panel is on screen and owns the pointer. Message
/// boxes, the Ultimate IP overlay, the welcome screen and asset editors
/// raised from the panel all sit above it, so it steps aside for them.
function scr_creator_panel_active() {
    var _open = global.creator_view_open;
    if (instance_exists(global.creator_edit_node)) {
        _open = true;
    }
    if (!_open) {
        return false;
    }
    if (global.c64u_overlay_active) {
        return false;
    }
    if (instance_exists(obj_message_box)) {
        return false;
    }
    if (instance_exists(obj_question_box)) {
        return false;
    }
    if (instance_exists(obj_workspace_manager)) {
        if (obj_workspace_manager.welcome_open) {
            return false;
        }
    }
    if (instance_exists(obj_asset_manager)) {
        if (obj_asset_manager.viewer_open) {
            return false;
        }
    }
    return true;
}

function scr_creator_opened() {
    global.creator_open_frame = global.frame_tick;
    global.creator_field      = "";
    global.creator_commit     = false;
    global.creator_scroll     = 0;
    keyboard_string           = "";
}

function scr_creator_open_view() {
    global.creator_edit_node = noone;
    global.creator_view_open = true;
    scr_creator_opened();
}

function scr_creator_close_view() {
    global.creator_view_open = false;
    global.creator_field     = "";
}

// --------------------------------------------------------------------
// PARAMS TAB (world space, right side of the node)
// --------------------------------------------------------------------

function scr_creator_node_tabbable(_n) {
    if (global.lite) {
        return false;
    }
    if (_n.macro_owner != noone) {
        return false;
    }
    if (string_copy(_n.node_type, 1, 6) != "MACRO_") {
        return false;
    }
    if (scr_node_is_hidden(_n)) {
        return false;
    }
    return true;
}

function scr_creator_tab_rect(_n) {
    var _r = { x1: 0, y1: 0, x2: 0, y2: 0 };
    _r.x1 = _n.x + _n.x_indent + _n.width + 2;
    _r.y1 = _n.y + 4;
    _r.x2 = _r.x1 + 18;
    _r.y2 = _r.y1 + 44;
    return _r;
}

/// Called from obj_c64_node Draw, as the node.
function scr_creator_draw_node_tab() {
    if (!scr_creator_node_tabbable(id)) {
        exit;
    }
    var _r   = scr_creator_tab_rect(id);
    var _np  = array_length(params);
    var _hot = (global.creator_tab_hot == id);

    draw_set_color(make_color_rgb(20, 14, 26));
    draw_rectangle(_r.x1, _r.y1, _r.x2, _r.y2, false);

    var _col = make_color_rgb(110, 110, 150);
    if (_np > 0) {
        _col = make_color_rgb(80, 200, 255);
    }
    if (_hot) {
        _col = make_color_rgb(255, 210, 80);
    }
    draw_set_color(_col);
    draw_rectangle(_r.x1, _r.y1, _r.x2, _r.y2, true);

    var _font_b   = draw_get_font();
    var _halign_b = draw_get_halign();
    var _valign_b = draw_get_valign();
    draw_set_font_l(fnt_c64_tiny);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    var _cx = (_r.x1 + _r.x2) / 2;
    draw_text(_cx, _r.y1 + 12, "P");
    draw_text(_cx, _r.y1 + 30, string(_np));
    draw_set_font_l(_font_b);
    draw_set_halign(_halign_b);
    draw_set_valign(_valign_b);
}

// --------------------------------------------------------------------
// BEGIN STEP
// --------------------------------------------------------------------

function scr_creator_begin_step() {
    global.creator_tab_hot = noone;
    scr_creator_update_covered();

    // Deferred panel actions: run here, never from inside a Draw event.
    if (global.creator_action != "") {
        var _act = global.creator_action;
        global.creator_action = "";
        scr_creator_run_action(_act);
    }

    // A loaded workspace decides whether it opens locked once its nodes exist.
    if (global.creator_open_pending) {
        global.creator_open_pending = false;
        if (global.creator_locked && scr_creator_param_count() > 0) {
            scr_creator_open_view();
        }
    }

    // Light: a locked workspace stays locked.
    if (global.lite && global.creator_locked && !global.creator_view_open) {
        if (scr_creator_param_count() > 0) {
            scr_creator_open_view();
        }
    }

    if (!instance_exists(global.creator_edit_node)) {
        global.creator_edit_node = noone;
    }
    if (global.creator_view_open || global.creator_edit_node != noone) {
        exit;
    }

    if (!instance_exists(obj_workspace_manager)) { exit; }
    if (!global.canEditNode)                     { exit; }
    if (global.idle_active && global.idle_fade < 0.1) { exit; }
    if (global.showcode_mouse_over)              { exit; }
    if (global.any_picker_open)                  { exit; }
    if (global.is_any_text_active)               { exit; }
    if (obj_workspace_manager.gui_menu_open != -1) { exit; }
    if (obj_workspace_manager.code_editor_open)  { exit; }
    if (obj_workspace_manager.is_entering_text)  { exit; }
    if (instance_exists(obj_asset_manager)) {
        if (obj_asset_manager.viewer_open) { exit; }
    }
    if (global.lite) { exit; }

    // F9: Creator view (Pro).
    if (scr_workspace_keyboard_check_pressed(vk_f9)) {
        if (scr_creator_param_count() > 0) {
            scr_creator_open_view();
        } else {
            scr_show_message("CREATOR VIEW\n\nNo params exposed yet.\nUse the P tab on a macro or code block to add some.");
        }
        exit;
    }

    var _mx  = mouse_x;
    var _my  = mouse_y;
    var _hot = noone;
    with (obj_c64_node) {
        if (!scr_creator_node_tabbable(id)) {
            continue;
        }
        var _r = scr_creator_tab_rect(id);
        if (point_in_rectangle(_mx, _my, _r.x1, _r.y1, _r.x2, _r.y2)) {
            _hot = id;
            break;
        }
    }
    global.creator_tab_hot = _hot;
    if (_hot == noone) {
        exit;
    }
    if (scr_workspace_mouse_check_button_pressed(mb_left)) {
        global.creator_edit_node = _hot;
        global.creator_view_open = false;
        scr_creator_opened();
    }
}

function scr_creator_run_action(_act) {
    if (!instance_exists(obj_workspace_manager)) {
        exit;
    }
    if (_act == "build") {
        with (obj_workspace_manager) {
            if (os_type == os_windows) {
                execute_shell_simple("taskkill", "/f /im x64sc.exe");
            }
            trigger_build = true;
        }
        exit;
    }
    if (_act == "ultimate") {
        if (global.c64u_ip == "") {
            global.c64u_overlay_active = true;
            global.c64u_overlay_text   = "";
            global.c64u_overlay_error  = "";
            global.c64u_overlay_after  = "send_prg";
            global.canEditNode         = 0;
            keyboard_string            = "";
            keyboard_clear(vk_anykey);
        } else {
            with (obj_workspace_manager) {
                trigger_c64u  = true;
                trigger_build = true;
            }
        }
        exit;
    }
    if (_act == "save") {
        global.isSaving = true;
        obj_workspace_manager.save_pending = true;
        exit;
    }
    if (_act == "load") {
        scr_load_workspace_dialog();
        exit;
    }
}

// --------------------------------------------------------------------
// IMMEDIATE-MODE WIDGETS (GUI space, Draw GUI End)
// --------------------------------------------------------------------

function scr_creator_btn(_x1, _y1, _x2, _y2, _label, _on) {
    var _hov = point_in_rectangle(global.creator_mx, global.creator_my, _x1, _y1, _x2, _y2);
    var _bg  = make_colour_rgb(30, 30, 70);
    if (_on) {
        _bg = make_colour_rgb(70, 70, 170);
    }
    if (_hov) {
        _bg = merge_colour(_bg, c_white, 0.18);
    }
    draw_set_colour(_bg);
    draw_rectangle(_x1, _y1, _x2, _y2, false);
    draw_set_colour(make_colour_rgb(180, 180, 255));
    draw_rectangle(_x1, _y1, _x2, _y2, true);
    draw_set_colour(c_white);
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_text_l((_x1 + _x2) / 2, (_y1 + _y2) / 2, _label);
    draw_set_halign(fa_left);
    var _clicked = false;
    if (_hov && global.creator_click) {
        _clicked = true;
    }
    return _clicked;
}

/// Width of a button that fits its label (current font) with padding.
function scr_creator_btn_w(_label) {
    return string_width_l(_label) + 28;
}

/// @return committed string, or undefined
function scr_creator_field(_fid, _x1, _y1, _x2, _y2, _value) {
    var _result = undefined;
    var _hov    = point_in_rectangle(global.creator_mx, global.creator_my, _x1, _y1, _x2, _y2);
    var _active = (global.creator_field == _fid);

    if (_active) {
        if (string_length(keyboard_string) > 48) {
            keyboard_string = string_copy(keyboard_string, 1, 48);
        }
        global.creator_field_text = keyboard_string;
        global.creator_field_rect = [_x1, _y1, _x2, _y2];
        if (keyboard_check_pressed(vk_enter) || global.creator_commit) {
            _result               = global.creator_field_text;
            global.creator_field  = "";
            global.creator_commit = false;
            _active               = false;
        } else if (keyboard_check_pressed(vk_escape)) {
            global.creator_field     = "";
            global.creator_esc_eaten = true;
            _active                  = false;
        }
    } else if (_hov && global.creator_click && global.creator_field == "") {
        global.creator_field      = _fid;
        keyboard_string           = string(_value);
        global.creator_field_text = keyboard_string;
        global.creator_field_rect = [_x1, _y1, _x2, _y2];
        _active                   = true;
    }

    draw_set_colour(c_black);
    draw_rectangle(_x1, _y1, _x2, _y2, false);
    var _edge = make_colour_rgb(120, 120, 200);
    if (_active) {
        _edge = make_colour_rgb(255, 210, 80);
    }
    draw_set_colour(_edge);
    draw_rectangle(_x1, _y1, _x2, _y2, true);
    draw_set_colour(c_white);
    draw_set_halign(fa_left);
    draw_set_valign(fa_middle);
    var _show = string(_value);
    if (_active) {
        _show = global.creator_field_text;
        if ((current_time div 500) mod 2 == 0) {
            _show += "_";
        }
    }
    draw_text(_x1 + 6, (_y1 + _y2) / 2, _show);
    return _result;
}

// --------------------------------------------------------------------
// DRAW GUI END
// --------------------------------------------------------------------

function scr_creator_draw() {
    if (!scr_creator_panel_active()) {
        exit;
    }

    global.creator_mx        = device_mouse_x_to_gui(0);
    global.creator_my        = device_mouse_y_to_gui(0);
    global.creator_click     = false;
    global.creator_esc_eaten = false;
    if (mouse_check_button_pressed(mb_left) && global.frame_tick != global.creator_open_frame) {
        global.creator_click = true;
    }
    // A click outside the field being typed in commits it.
    if (global.creator_field != "" && global.creator_click) {
        var _fr = global.creator_field_rect;
        if (!point_in_rectangle(global.creator_mx, global.creator_my, _fr[0], _fr[1], _fr[2], _fr[3])) {
            global.creator_commit = true;
        }
    }

    var _font_b   = draw_get_font();
    var _halign_b = draw_get_halign();
    var _valign_b = draw_get_valign();
    var _alpha_b  = draw_get_alpha();
    var _col_b    = draw_get_colour();
    gpu_set_scissor(0, 0, window_get_width(), window_get_height());

    draw_set_alpha(0.85);
    draw_set_colour(c_black);
    draw_rectangle(0, 0, display_get_gui_width(), display_get_gui_height(), false);
    draw_set_alpha(1.0);

    if (instance_exists(global.creator_edit_node)) {
        scr_creator_draw_editor(global.creator_edit_node);
    } else {
        scr_creator_draw_view();
    }

    // The field that was being typed in is gone (row deleted, panel closed).
    if (global.creator_commit) {
        global.creator_commit = false;
        global.creator_field  = "";
    }

    draw_set_font(_font_b);
    draw_set_halign(_halign_b);
    draw_set_valign(_valign_b);
    draw_set_alpha(_alpha_b);
    draw_set_colour(_col_b);
}

/// Developer panel: define what a node exposes.
function scr_creator_draw_editor(_n) {
    var _gw    = display_get_gui_width();
    var _gh    = display_get_gui_height();
    var _np    = array_length(_n.params);
    var _row_h = 74;
    var _pw    = 860;
    var _ph    = 130 + max(1, _np) * _row_h + 64;
    var _px    = floor((_gw - _pw) / 2);
    var _py    = floor((_gh - _ph) / 2);
    var _code  = (_n.node_type == "MACRO_CODE");

    draw_set_colour(make_colour_rgb(40, 40, 90));
    draw_rectangle(_px, _py, _px + _pw, _py + _ph, false);
    draw_set_colour(make_colour_rgb(180, 180, 255));
    draw_rectangle(_px, _py, _px + _pw, _py + _ph, true);

    draw_set_font_l(fnt_C64_Angled_big);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_colour(c_white);
    draw_text(_px + 16, _py + 12, "PARAMS - " + string_upper(scr_creator_node_name(_n)));

    draw_set_font_l(fnt_c64_tiny);
    draw_set_colour(make_colour_rgb(190, 190, 230));
    if (_code) {
        draw_text_l(_px + 16, _py + 52, "TARGET = a NAME = value line in this code block. MODE branches: .IF NAME == n / .ELSE / .ENDIF");
    } else {
        draw_text_l(_px + 16, _py + 52, "TARGET = one of this macro's value slots. Pick the slot showing the value you want to expose.");
    }

    draw_set_font_l(fnt_C64_Angled);
    var _changed = false;
    var _del     = -1;
    var _kinds   = ["COLOUR", "RANGE", "MODE"];

    for (var _i = 0; _i < _np; _i++) {
        var _p  = _n.params[_i];
        var _ry = _py + 84 + _i * _row_h;
        var _si = string(_i);

        draw_set_colour(make_colour_rgb(90, 90, 150));
        draw_line(_px + 10, _ry - 4, _px + _pw - 10, _ry - 4);

        // --- line 1: label, kind, target, delete ---
        var _r = scr_creator_field("lbl" + _si, _px + 16, _ry, _px + 286, _ry + 26, _p.label);
        if (!is_undefined(_r)) {
            _p.label = string_trim(_r);
            _changed = true;
        }

        if (scr_creator_btn(_px + 296, _ry, _px + 406, _ry + 26, _p.kind, true)) {
            var _k = 0;
            for (var _ki = 0; _ki < 3; _ki++) {
                if (_kinds[_ki] == _p.kind) {
                    _k = _ki;
                }
            }
            _p.kind  = _kinds[(_k + 1) mod 3];
            _changed = true;
        }

        if (_code) {
            draw_set_colour(c_white);
            draw_set_valign(fa_middle);
            draw_text_l(_px + 418, _ry + 13, "NAME");
            var _rs = scr_creator_field("sym" + _si, _px + 476, _ry, _px + 646, _ry + 26, _p.sym);
            if (!is_undefined(_rs)) {
                _p.sym   = string_upper(string_trim(_rs));
                _changed = true;
            }
        } else {
            draw_set_colour(c_white);
            draw_set_valign(fa_middle);
            draw_text_l(_px + 418, _ry + 13, "SLOT");
            if (scr_creator_btn(_px + 476, _ry, _px + 502, _ry + 26, "-", false)) {
                _p.slot  = max(1, _p.slot - 1);
                _changed = true;
            }
            draw_set_colour(c_white);
            draw_set_halign(fa_center);
            draw_text(_px + 527, _ry + 13, string(_p.slot));
            draw_set_halign(fa_left);
            var _row_len = 0;
            if (_p.row < array_length(_n.instructions)) {
                _row_len = array_length(_n.instructions[_p.row]);
            }
            if (scr_creator_btn(_px + 552, _ry, _px + 578, _ry + 26, "+", false)) {
                _p.slot  = min(max(1, _row_len - 1), _p.slot + 1);
                _changed = true;
            }
        }

        if (scr_creator_btn(_px + _pw - 86, _ry, _px + _pw - 16, _ry + 26, "DEL", false)) {
            _del = _i;
        }

        // --- line 2: kind-specific settings + live value ---
        var _ly = _ry + 34;
        draw_set_colour(c_white);
        draw_set_valign(fa_middle);
        if (_p.kind == "RANGE") {
            draw_text_l(_px + 16, _ly + 13, "MIN");
            var _rmin = scr_creator_field("min" + _si, _px + 60, _ly, _px + 140, _ly + 26, _p.vmin);
            if (!is_undefined(_rmin)) {
                _p.vmin  = scr_creator_num(_rmin);
                _changed = true;
            }
            draw_set_colour(c_white);
            draw_text_l(_px + 156, _ly + 13, "MAX");
            var _rmax = scr_creator_field("max" + _si, _px + 200, _ly, _px + 280, _ly + 26, _p.vmax);
            if (!is_undefined(_rmax)) {
                _p.vmax  = scr_creator_num(_rmax);
                _changed = true;
            }
        } else if (_p.kind == "MODE") {
            draw_text_l(_px + 16, _ly + 13, "OPTIONS");
            var _ro = scr_creator_field("opt" + _si, _px + 100, _ly, _px + 560, _ly + 26, _p.options);
            if (!is_undefined(_ro)) {
                _p.options = string_trim(_ro);
                _changed   = true;
            }
        } else {
            draw_set_font_l(fnt_c64_tiny);
            draw_text_l(_px + 16, _ly + 13, "C64 PALETTE 0-15");
            draw_set_font_l(fnt_C64_Angled);
        }

        var _cur = scr_param_read(_n, _p);
        draw_set_valign(fa_middle);
        if (_cur.ok) {
            draw_set_colour(make_colour_rgb(120, 255, 140));
            draw_text(_px + 590, _ly + 13, "VALUE " + string(_cur.val));
            if (_p.kind == "COLOUR") {
                draw_set_colour(scr_c64_pepto_colour(clamp(round(_cur.val), 0, 15)));
                draw_rectangle(_px + 720, _ly + 3, _px + 760, _ly + 23, false);
            }
        } else {
            draw_set_colour(make_colour_rgb(255, 110, 110));
            if (_code) {
                draw_text_l(_px + 590, _ly + 13, "NAME NOT FOUND");
            } else {
                draw_text_l(_px + 590, _ly + 13, "SLOT NOT NUMERIC");
            }
        }
    }

    if (_np == 0) {
        draw_set_colour(make_colour_rgb(190, 190, 230));
        draw_set_valign(fa_middle);
        draw_text_l(_px + 16, _py + 84 + 30, "No params yet. ADD PARAM exposes a value to the Creator view.");
    }

    if (_del >= 0) {
        array_delete(_n.params, _del, 1);
        global.creator_field = "";
        _changed = true;
    }

    var _by = _py + _ph - 46;
    if (array_length(_n.params) < CREATOR_MAX_PARAMS) {
        if (scr_creator_btn(_px + 16, _by, _px + 196, _by + 30, "+ ADD PARAM", false)) {
            var _np_new = scr_param_new();
            if (_code) {
                _np_new.sym = "";
            } else {
                _np_new.kind = "RANGE";
            }
            array_push(_n.params, _np_new);
            _changed = true;
        }
    }
    if (scr_creator_btn(_px + _pw - 166, _by, _px + _pw - 16, _by + 30, "CLOSE", false)) {
        if (global.creator_field != "") {
            global.creator_commit = true;
        }
        global.creator_edit_node = noone;
    }
    if (keyboard_check_pressed(vk_escape) && !global.creator_esc_eaten && global.creator_field == "") {
        global.creator_edit_node = noone;
    }

    if (_changed) {
        global.undo_dirty     = true;
        global.autosave_dirty = true;
        with (_n) {
            height_dirty     = true;
            draw_cache_dirty = true;
        }
    }
}

/// End-user panel: the only thing a locked workspace shows.
function scr_creator_draw_view() {
    var _gw = display_get_gui_width();
    var _gh = display_get_gui_height();

    // Nodes carrying params, top to bottom.
    var _hosts = [];
    with (obj_c64_node) {
        if (array_length(params) > 0) {
            array_push(_hosts, id);
        }
    }
    array_sort(_hosts, function(_a, _b) {
        if (_a.x != _b.x) {
            return _a.x - _b.x;
        }
        return _a.y - _b.y;
    });

    var _head_h = 34;
    var _row_h  = 46;
    var _content_h = 0;
    for (var _h = 0; _h < array_length(_hosts); _h++) {
        _content_h += _head_h + array_length(_hosts[_h].params) * _row_h;
    }

    // Footer buttons size to their text, and the panel grows to fit them.
    draw_set_font_l(fnt_C64_Angled);
    var _foot_w = 16 + scr_creator_btn_w("BUILD & RUN") + 10 + scr_creator_btn_w("RUN ON ULTIMATE") + 10
                + scr_creator_btn_w("SAVE") + 10 + scr_creator_btn_w("LOAD") + 16;
    if (!global.lite) {
        _foot_w += 30 + scr_creator_btn_w("OPENS LOCKED: OFF") + 10 + scr_creator_btn_w("EDIT GRAPH");
    }
    var _pw     = max(820, _foot_w);
    var _top_h  = 90;
    var _foot_h = 70;
    var _ph     = min(_gh - 60, _top_h + max(60, _content_h) + _foot_h);
    var _px     = floor((_gw - _pw) / 2);
    var _py     = floor((_gh - _ph) / 2);
    var _view_y1 = _py + _top_h;
    var _view_y2 = _py + _ph - _foot_h;
    var _view_h  = _view_y2 - _view_y1;

    // Scroll
    var _max_scroll = max(0, _content_h - _view_h);
    if (point_in_rectangle(global.creator_mx, global.creator_my, _px, _view_y1, _px + _pw, _view_y2)) {
        if (mouse_wheel_down()) {
            global.creator_scroll += 40;
        }
        if (mouse_wheel_up()) {
            global.creator_scroll -= 40;
        }
    }
    global.creator_scroll = clamp(global.creator_scroll, 0, _max_scroll);

    draw_set_colour(make_colour_rgb(24, 24, 60));
    draw_rectangle(_px, _py, _px + _pw, _py + _ph, false);
    draw_set_colour(make_colour_rgb(180, 180, 255));
    draw_rectangle(_px, _py, _px + _pw, _py + _ph, true);

    draw_set_font_l(fnt_C64_Angled_big);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_colour(c_white);
    draw_text_l(_px + 16, _py + 12, "CREATOR");
    draw_set_font_l(fnt_c64_tiny);
    draw_set_colour(make_colour_rgb(190, 190, 230));
    var _wsname = "UNTITLED";
    if (global.workspace_path != "") {
        _wsname = filename_name(global.workspace_path);
    }
    draw_text(_px + 16, _py + 56, string_upper(_wsname));
    if (!global.lite) {
        draw_set_halign(fa_right);
        draw_text_l(_px + _pw - 16, _py + 56, "F9 / EDIT GRAPH returns to the node graph");
        draw_set_halign(fa_left);
    }

    // --- rows (clipped to the view) ---
    var _scale_x = window_get_width() / max(1, _gw);
    var _scale_y = window_get_height() / max(1, _gh);
    gpu_set_scissor(_px * _scale_x, _view_y1 * _scale_y, _pw * _scale_x, _view_h * _scale_y);

    var _click_live = global.creator_click;
    if (!point_in_rectangle(global.creator_mx, global.creator_my, _px, _view_y1, _px + _pw, _view_y2)) {
        global.creator_click = false;
    }

    draw_set_font_l(fnt_C64_Angled);
    var _y = _view_y1 - global.creator_scroll;
    for (var _h = 0; _h < array_length(_hosts); _h++) {
        var _n = _hosts[_h];

        draw_set_colour(make_colour_rgb(50, 50, 110));
        draw_rectangle(_px + 8, _y + 4, _px + _pw - 8, _y + _head_h - 4, false);
        draw_set_colour(make_colour_rgb(255, 210, 80));
        draw_set_valign(fa_middle);
        draw_text(_px + 18, _y + _head_h / 2, string_upper(scr_creator_node_name(_n)));
        _y += _head_h;

        for (var _i = 0; _i < array_length(_n.params); _i++) {
            var _p   = _n.params[_i];
            var _cy  = _y + _row_h / 2;
            var _cur = scr_param_read(_n, _p);

            draw_set_colour(c_white);
            draw_set_valign(fa_middle);
            draw_text(_px + 24, _cy, _p.label);

            var _cx = _px + 300;
            if (!_cur.ok) {
                draw_set_colour(make_colour_rgb(255, 110, 110));
                draw_text_l(_cx, _cy, "NOT LINKED");
            } else if (_p.kind == "COLOUR") {
                for (var _c = 0; _c < 16; _c++) {
                    var _sx = _cx + _c * 30;
                    draw_set_colour(scr_c64_pepto_colour(_c));
                    draw_rectangle(_sx, _cy - 12, _sx + 24, _cy + 12, false);
                    if (round(_cur.val) == _c) {
                        draw_set_colour(c_white);
                        draw_rectangle(_sx - 2, _cy - 14, _sx + 26, _cy + 14, true);
                        draw_rectangle(_sx - 3, _cy - 15, _sx + 27, _cy + 15, true);
                    }
                    if (global.creator_click && point_in_rectangle(global.creator_mx, global.creator_my, _sx, _cy - 12, _sx + 24, _cy + 12)) {
                        scr_param_write(_n, _p, _c);
                    }
                }
            } else if (_p.kind == "RANGE") {
                var _lo = min(_p.vmin, _p.vmax);
                var _hi = max(_p.vmin, _p.vmax);
                if (scr_creator_btn(_cx, _cy - 13, _cx + 28, _cy + 13, "-", false)) {
                    scr_param_write(_n, _p, _cur.val - 1);
                }
                draw_set_colour(c_white);
                draw_set_halign(fa_center);
                draw_text(_cx + 62, _cy, string(_cur.val));
                draw_set_halign(fa_left);
                if (scr_creator_btn(_cx + 96, _cy - 13, _cx + 124, _cy + 13, "+", false)) {
                    scr_param_write(_n, _p, _cur.val + 1);
                }
                var _bx1 = _cx + 140;
                var _bx2 = _cx + 460;
                draw_set_colour(make_colour_rgb(10, 10, 30));
                draw_rectangle(_bx1, _cy - 6, _bx2, _cy + 6, false);
                var _t = 0;
                if (_hi > _lo) {
                    _t = clamp((_cur.val - _lo) / (_hi - _lo), 0, 1);
                }
                draw_set_colour(make_colour_rgb(80, 200, 255));
                draw_rectangle(_bx1, _cy - 6, _bx1 + (_bx2 - _bx1) * _t, _cy + 6, false);
                draw_set_colour(make_colour_rgb(180, 180, 255));
                draw_rectangle(_bx1, _cy - 6, _bx2, _cy + 6, true);
                // Click or drag along the bar.
                if (mouse_check_button(mb_left) && global.frame_tick != global.creator_open_frame
                && point_in_rectangle(global.creator_mx, global.creator_my, _bx1, _cy - 12, _bx2, _cy + 12)
                && point_in_rectangle(global.creator_mx, global.creator_my, _px, _view_y1, _px + _pw, _view_y2)) {
                    var _f = (global.creator_mx - _bx1) / (_bx2 - _bx1);
                    scr_param_write(_n, _p, _lo + _f * (_hi - _lo));
                }
            } else if (_p.kind == "MODE") {
                var _opts = scr_param_options(_p.options);
                var _ox   = _cx;
                for (var _o = 0; _o < array_length(_opts); _o++) {
                    var _ow = string_width(_opts[_o].name) + 28;
                    var _on = (round(_cur.val) == round(_opts[_o].val));
                    if (scr_creator_btn(_ox, _cy - 14, _ox + _ow, _cy + 14, _opts[_o].name, _on)) {
                        scr_param_write(_n, _p, _opts[_o].val);
                    }
                    _ox += _ow + 8;
                }
            }
            _y += _row_h;
        }
    }

    gpu_set_scissor(0, 0, window_get_width(), window_get_height());
    global.creator_click = _click_live;

    if (array_length(_hosts) == 0) {
        draw_set_colour(make_colour_rgb(190, 190, 230));
        draw_set_valign(fa_middle);
        draw_text_l(_px + 24, _view_y1 + 30, "This workspace has no exposed params.");
    }

    // --- footer ---
    draw_set_font_l(fnt_C64_Angled);
    var _by = _py + _ph - 50;
    var _bx = _px + 16;
    var _bw = scr_creator_btn_w("BUILD & RUN");
    if (scr_creator_btn(_bx, _by, _bx + _bw, _by + 34, "BUILD & RUN", false)) {
        global.creator_action = "build";
    }
    _bx += _bw + 10;
    _bw = scr_creator_btn_w("RUN ON ULTIMATE");
    if (scr_creator_btn(_bx, _by, _bx + _bw, _by + 34, "RUN ON ULTIMATE", false)) {
        global.creator_action = "ultimate";
    }
    _bx += _bw + 10;
    _bw = scr_creator_btn_w("SAVE");
    if (scr_creator_btn(_bx, _by, _bx + _bw, _by + 34, "SAVE", false)) {
        global.creator_action = "save";
    }
    _bx += _bw + 10;
    _bw = scr_creator_btn_w("LOAD");
    if (scr_creator_btn(_bx, _by, _bx + _bw, _by + 34, "LOAD", false)) {
        global.creator_action = "load";
    }

    if (!global.lite) {
        // Right-aligned group. The lock button is sized for its longer
        // label so it does not jump when toggled.
        var _ew = scr_creator_btn_w("EDIT GRAPH");
        var _lw = scr_creator_btn_w("OPENS LOCKED: OFF");
        var _ex = _px + _pw - 16 - _ew;
        var _lx = _ex - 10 - _lw;
        var _lk = "OPENS LOCKED: OFF";
        if (global.creator_locked) {
            _lk = "OPENS LOCKED: ON";
        }
        if (scr_creator_btn(_lx, _by, _lx + _lw, _by + 34, _lk, global.creator_locked)) {
            global.creator_locked = !global.creator_locked;
            global.autosave_dirty = true;
            global.undo_dirty     = true;
        }
        if (scr_creator_btn(_ex, _by, _ex + _ew, _by + 34, "EDIT GRAPH", false)) {
            scr_creator_close_view();
        }
        if (keyboard_check_pressed(vk_f9) && global.frame_tick != global.creator_open_frame) {
            scr_creator_close_view();
        }
    }
}

// ====================================================================
// UI PANELS (mapping boxes)
//
// A mapping box with UI PANEL switched on draws a facade over the nodes it
// covers: the box name, an EDIT button, and a widget for every param on
// those nodes. Covered nodes count as hidden (scr_node_is_hidden), so they
// are not drawn, clicked, selected or searched while the facade is up.
// EDIT lifts the facade; SHOW UI puts it back. Workspaces always load with
// the facade up.
// ====================================================================

#macro CREATOR_PANEL_HEAD 30
#macro CREATOR_PANEL_ROW  34
#macro CREATOR_PANEL_SUB  22
#macro CREATOR_PANEL_PAD  10

/// Begin Step: mark every node sitting under a raised facade.
function scr_creator_update_covered() {
    with (obj_c64_node) {
        creator_covered = false;
    }
    with (obj_mapping_box) {
        if (!is_panel || panel_editing) {
            continue;
        }
        var _bx1 = x;
        var _by1 = y;
        var _bx2 = x + box_w;
        var _by2 = y + box_h;
        with (obj_c64_node) {
            var _nx = x + (width * 0.5);
            var _ny = y + (height * 0.5);
            if (_nx >= _bx1 && _nx <= _bx2 && _ny >= _by1 && _ny <= _by2) {
                creator_covered = true;
            }
        }
    }
}

/// Nodes with params whose centre is inside the box, top to bottom.
function scr_creator_panel_nodes(_b) {
    var _out = [];
    var _bx1 = _b.x;
    var _by1 = _b.y;
    var _bx2 = _b.x + _b.box_w;
    var _by2 = _b.y + _b.box_h;
    with (obj_c64_node) {
        if (array_length(params) == 0) {
            continue;
        }
        var _nx = x + (width * 0.5);
        var _ny = y + (height * 0.5);
        if (_nx >= _bx1 && _nx <= _bx2 && _ny >= _by1 && _ny <= _by2) {
            array_push(_out, id);
        }
    }
    array_sort(_out, function(_a, _c) {
        if (_a.y != _c.y) {
            return _a.y - _c.y;
        }
        return _a.x - _c.x;
    });
    return _out;
}

function scr_creator_item(_t, _x1, _y1, _x2, _y2) {
    return { t: _t, x1: _x1, y1: _y1, x2: _x2, y2: _y2, n: noone, pidx: 0, v: 0, text: "", on: false, lo: 0, hi: 0 };
}

/// Room-space layout shared by the facade's Step (clicks) and Draw.
/// Font must be fnt_c64_code when called (string widths).
function scr_creator_panel_layout(_b) {
    var _items = [];
    var _pad   = CREATOR_PANEL_PAD;
    var _bx1   = _b.x;
    var _by1   = _b.y;
    var _bx2   = _b.x + _b.box_w;
    var _by2   = _b.y + _b.box_h;

    if (!global.lite) {
        var _ew = string_width_l("EDIT") + 20;
        var _edit = scr_creator_item("edit", _bx2 - _pad - _ew, _by1 + 5, _bx2 - _pad, _by1 + CREATOR_PANEL_HEAD - 5);
        _edit.text = "EDIT";
        array_push(_items, _edit);
    }

    var _nodes = scr_creator_panel_nodes(_b);
    var _multi = (array_length(_nodes) > 1);
    var _y     = _by1 + CREATOR_PANEL_HEAD + 6;
    var _lw    = floor(_b.box_w * 0.38);
    var _cx    = _bx1 + _pad + _lw;
    var _cw    = _bx2 - _pad - _cx;

    if (array_length(_nodes) == 0) {
        var _none = scr_creator_item("text", _bx1 + _pad, _y, _bx2 - _pad, _y + CREATOR_PANEL_ROW);
        _none.text = "No params in this panel. EDIT, then use the P tab on a node.";
        array_push(_items, _none);
        return _items;
    }

    for (var _ni = 0; _ni < array_length(_nodes); _ni++) {
        var _n = _nodes[_ni];
        if (_multi) {
            if (_y + CREATOR_PANEL_SUB > _by2 - 4) {
                array_push(_items, scr_creator_item("more", _bx1, _by2 - 14, _bx2, _by2));
                return _items;
            }
            var _sub = scr_creator_item("sub", _bx1 + _pad, _y, _bx2 - _pad, _y + CREATOR_PANEL_SUB);
            _sub.text = string_upper(scr_creator_node_name(_n));
            array_push(_items, _sub);
            _y += CREATOR_PANEL_SUB;
        }
        for (var _i = 0; _i < array_length(_n.params); _i++) {
            if (_y + CREATOR_PANEL_ROW > _by2 - 4) {
                array_push(_items, scr_creator_item("more", _bx1, _by2 - 14, _bx2, _by2));
                return _items;
            }
            var _p   = _n.params[_i];
            var _cy  = _y + CREATOR_PANEL_ROW * 0.5;
            var _cur = scr_param_read(_n, _p);

            var _lab = scr_creator_item("label", _bx1 + _pad, _y, _cx - 6, _y + CREATOR_PANEL_ROW);
            _lab.text = _p.label;
            array_push(_items, _lab);

            if (!_cur.ok) {
                var _bad = scr_creator_item("bad", _cx, _y, _bx2 - _pad, _y + CREATOR_PANEL_ROW);
                _bad.text = "NOT LINKED";
                array_push(_items, _bad);
            } else if (_p.kind == "COLOUR") {
                var _step = max(8, floor(_cw / 16));
                var _sw   = max(6, _step - 3);
                for (var _c = 0; _c < 16; _c++) {
                    var _sx = _cx + _c * _step;
                    var _it = scr_creator_item("swatch", _sx, _cy - _sw * 0.5, _sx + _sw, _cy + _sw * 0.5);
                    _it.n  = _n;
                    _it.pidx = _i;
                    _it.v  = _c;
                    _it.on = (round(_cur.val) == _c);
                    array_push(_items, _it);
                }
            } else if (_p.kind == "RANGE") {
                var _mi = scr_creator_item("minus", _cx, _cy - 10, _cx + 20, _cy + 10);
                _mi.n = _n; _mi.pidx = _i; _mi.v = _cur.val - 1; _mi.text = "-";
                array_push(_items, _mi);
                var _vt = scr_creator_item("value", _cx + 22, _cy - 10, _cx + 62, _cy + 10);
                _vt.text = string(_cur.val);
                array_push(_items, _vt);
                var _pl = scr_creator_item("plus", _cx + 64, _cy - 10, _cx + 84, _cy + 10);
                _pl.n = _n; _pl.pidx = _i; _pl.v = _cur.val + 1; _pl.text = "+";
                array_push(_items, _pl);
                if (_cw > 120) {
                    var _bar = scr_creator_item("bar", _cx + 94, _cy - 5, _cx + _cw, _cy + 5);
                    _bar.n  = _n;
                    _bar.pidx = _i;
                    _bar.lo = min(_p.vmin, _p.vmax);
                    _bar.hi = max(_p.vmin, _p.vmax);
                    _bar.v  = _cur.val;
                    array_push(_items, _bar);
                }
            } else if (_p.kind == "MODE") {
                var _opts = scr_param_options(_p.options);
                var _ox   = _cx;
                for (var _o = 0; _o < array_length(_opts); _o++) {
                    var _ow = string_width_l(_opts[_o].name) + 16;
                    if (_ox + _ow > _bx2 - _pad) {
                        break;
                    }
                    var _ob = scr_creator_item("opt", _ox, _cy - 11, _ox + _ow, _cy + 11);
                    _ob.n    = _n;
                    _ob.pidx   = _i;
                    _ob.v    = _opts[_o].val;
                    _ob.text = _opts[_o].name;
                    _ob.on   = (round(_cur.val) == round(_opts[_o].val));
                    array_push(_items, _ob);
                    _ox += _ow + 6;
                }
            }
            _y += CREATOR_PANEL_ROW;
        }
    }
    return _items;
}

/// Buttons above the box, left of its delete X (developer only).
function scr_creator_box_buttons(_b) {
    var _out = [];
    if (global.lite) {
        return _out;
    }
    var _right = _b.x + _b.box_w - 22;
    if (!_b.is_panel) {
        var _mk = scr_creator_item("make", _right - 76, _b.y - 18, _right, _b.y);
        _mk.text = "UI PANEL";
        array_push(_out, _mk);
        return _out;
    }
    if (_b.panel_editing) {
        var _sh = scr_creator_item("show", _right - 70, _b.y - 18, _right, _b.y);
        _sh.text = "SHOW UI";
        array_push(_out, _sh);
        var _un = scr_creator_item("unmake", _right - 70 - 4 - 56, _b.y - 18, _right - 74, _b.y);
        _un.text = "NO UI";
        array_push(_out, _un);
    }
    return _out;
}

/// obj_mapping_box Step. Returns true when this box used the click.
function scr_creator_box_step(_b) {
    var _mx = mouse_x;
    var _my = mouse_y;

    // Bar drag in progress.
    if (_b.panel_bar.active) {
        if (scr_workspace_mouse_check_button(mb_left) && instance_exists(_b.panel_bar.n)) {
            var _bn = _b.panel_bar.n;
            if (_b.panel_bar.pidx < array_length(_bn.params)) {
                var _f = clamp((_mx - _b.panel_bar.x1) / max(1, _b.panel_bar.x2 - _b.panel_bar.x1), 0, 1);
                scr_param_write(_bn, _bn.params[_b.panel_bar.pidx], _b.panel_bar.lo + _f * (_b.panel_bar.hi - _b.panel_bar.lo));
            }
            return true;
        }
        _b.panel_bar.active = false;
        return true;
    }

    if (!scr_workspace_mouse_check_button_pressed(mb_left)) {
        return false;
    }

    // Buttons above the box.
    var _btns = scr_creator_box_buttons(_b);
    for (var _i = 0; _i < array_length(_btns); _i++) {
        var _bt = _btns[_i];
        if (!point_in_rectangle(_mx, _my, _bt.x1, _bt.y1, _bt.x2, _bt.y2)) {
            continue;
        }
        if (_bt.t == "make") {
            _b.is_panel      = true;
            _b.panel_editing = false;
            global.selected_nodes = [];
        } else if (_bt.t == "show") {
            _b.panel_editing = false;
            global.selected_nodes = [];
        } else if (_bt.t == "unmake") {
            _b.is_panel      = false;
            _b.panel_editing = false;
        }
        global.undo_dirty     = true;
        global.autosave_dirty = true;
        return true;
    }

    if (!_b.is_panel || _b.panel_editing) {
        return false;
    }
    if (!point_in_rectangle(_mx, _my, _b.x, _b.y, _b.x + _b.box_w, _b.y + _b.box_h)) {
        return false;
    }
    // Leave the resize corner to the box.
    if (_mx >= _b.x + _b.box_w - 16 && _my >= _b.y + _b.box_h - 16) {
        return false;
    }

    draw_set_font_l(fnt_c64_code);
    var _items = scr_creator_panel_layout(_b);
    for (var _i = 0; _i < array_length(_items); _i++) {
        var _it = _items[_i];
        if (!point_in_rectangle(_mx, _my, _it.x1, _it.y1 - 3, _it.x2, _it.y2 + 3)) {
            continue;
        }
        if (_it.t == "edit") {
            _b.panel_editing = true;
            return true;
        }
        if (!instance_exists(_it.n)) {
            continue;
        }
        if (_it.pidx >= array_length(_it.n.params)) {
            continue;
        }
        var _p = _it.n.params[_it.pidx];
        if (_it.t == "swatch" || _it.t == "minus" || _it.t == "plus" || _it.t == "opt") {
            scr_param_write(_it.n, _p, _it.v);
            return true;
        }
        if (_it.t == "bar") {
            _b.panel_bar.active = true;
            _b.panel_bar.n      = _it.n;
            _b.panel_bar.pidx     = _it.pidx;
            _b.panel_bar.x1     = _it.x1;
            _b.panel_bar.x2     = _it.x2;
            _b.panel_bar.lo     = _it.lo;
            _b.panel_bar.hi     = _it.hi;
            var _f = clamp((_mx - _it.x1) / max(1, _it.x2 - _it.x1), 0, 1);
            scr_param_write(_it.n, _p, _it.lo + _f * (_it.hi - _it.lo));
            return true;
        }
    }
    // The facade protects what is under it: a click anywhere on it stops here.
    return true;
}

function scr_creator_draw_room_btn(_it, _on, _col) {
    var _hov = point_in_rectangle(mouse_x, mouse_y, _it.x1, _it.y1, _it.x2, _it.y2);
    var _bg  = make_colour_rgb(30, 30, 70);
    if (_on) {
        _bg = _col;
    }
    if (_hov) {
        _bg = merge_colour(_bg, c_white, 0.2);
    }
    draw_set_colour(_bg);
    draw_rectangle(_it.x1, _it.y1, _it.x2, _it.y2, false);
    draw_set_colour(_col);
    draw_rectangle(_it.x1, _it.y1, _it.x2, _it.y2, true);
    draw_set_colour(c_white);
    if (_on) {
        draw_set_colour(c_black);
    }
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_text_l((_it.x1 + _it.x2) * 0.5, (_it.y1 + _it.y2) * 0.5, _it.text);
    draw_set_halign(fa_left);
}

/// obj_mapping_box Draw (room space). Buttons above the box always; the
/// facade itself only while the panel is up.
function scr_creator_box_draw(_b) {
    var _col      = _b.box_colours[_b.box_col_idx];
    var _font_b   = draw_get_font();
    var _halign_b = draw_get_halign();
    var _valign_b = draw_get_valign();
    draw_set_font_l(fnt_c64_code);

    var _btns = scr_creator_box_buttons(_b);
    for (var _i = 0; _i < array_length(_btns); _i++) {
        scr_creator_draw_room_btn(_btns[_i], false, _col);
    }

    if (_b.is_panel && !_b.panel_editing) {
        var _bx1 = _b.x;
        var _by1 = _b.y;
        var _bx2 = _b.x + _b.box_w;
        var _by2 = _b.y + _b.box_h;

        draw_set_alpha(1);
        draw_set_colour(make_colour_rgb(18, 18, 40));
        draw_rectangle(_bx1, _by1, _bx2, _by2, false);
        draw_set_colour(merge_colour(_col, c_black, 0.35));
        draw_rectangle(_bx1, _by1, _bx2, _by1 + CREATOR_PANEL_HEAD, false);
        draw_set_colour(_col);
        draw_rectangle(_bx1, _by1, _bx2, _by2, true);
        draw_rectangle(_bx1 + 1, _by1 + 1, _bx2 - 1, _by2 - 1, true);
        draw_set_colour(c_white);
        draw_set_halign(fa_left);
        draw_set_valign(fa_middle);
        draw_text_l(_bx1 + CREATOR_PANEL_PAD, _by1 + CREATOR_PANEL_HEAD * 0.5, string_upper(_b.box_name));

        var _items = scr_creator_panel_layout(_b);
        for (var _i = 0; _i < array_length(_items); _i++) {
            var _it = _items[_i];
            var _my = (_it.y1 + _it.y2) * 0.5;
            draw_set_valign(fa_middle);
            draw_set_halign(fa_left);
            switch (_it.t) {
                case "edit":
                    scr_creator_draw_room_btn(_it, false, c_white);
                    break;
                case "sub":
                    draw_set_colour(_col);
                    draw_text_l(_it.x1, _my, _it.text);
                    draw_set_alpha(0.4);
                    draw_line(_it.x1, _it.y2 - 2, _it.x2, _it.y2 - 2);
                    draw_set_alpha(1);
                    break;
                case "label":
                    draw_set_colour(c_white);
                    draw_text(_it.x1, _my, _it.text);
                    break;
                case "text":
                    draw_set_colour(make_colour_rgb(190, 190, 230));
                    draw_text_l(_it.x1, _my, _it.text);
                    break;
                case "bad":
                    draw_set_colour(make_colour_rgb(255, 110, 110));
                    draw_text_l(_it.x1, _my, _it.text);
                    break;
                case "value":
                    draw_set_colour(c_white);
                    draw_set_halign(fa_center);
                    draw_text((_it.x1 + _it.x2) * 0.5, _my, _it.text);
                    break;
                case "swatch":
                    draw_set_colour(scr_c64_pepto_colour(_it.v));
                    draw_rectangle(_it.x1, _it.y1, _it.x2, _it.y2, false);
                    if (_it.on) {
                        draw_set_colour(c_white);
                        draw_rectangle(_it.x1 - 2, _it.y1 - 2, _it.x2 + 2, _it.y2 + 2, true);
                        draw_rectangle(_it.x1 - 3, _it.y1 - 3, _it.x2 + 3, _it.y2 + 3, true);
                    }
                    break;
                case "minus":
                case "plus":
                    scr_creator_draw_room_btn(_it, false, make_colour_rgb(180, 180, 255));
                    break;
                case "opt":
                    scr_creator_draw_room_btn(_it, _it.on, make_colour_rgb(180, 180, 255));
                    break;
                case "bar":
                    var _t = 0;
                    if (_it.hi > _it.lo) {
                        _t = clamp((_it.v - _it.lo) / (_it.hi - _it.lo), 0, 1);
                    }
                    draw_set_colour(make_colour_rgb(8, 8, 24));
                    draw_rectangle(_it.x1, _it.y1, _it.x2, _it.y2, false);
                    draw_set_colour(make_colour_rgb(80, 200, 255));
                    draw_rectangle(_it.x1, _it.y1, _it.x1 + (_it.x2 - _it.x1) * _t, _it.y2, false);
                    draw_set_colour(make_colour_rgb(180, 180, 255));
                    draw_rectangle(_it.x1, _it.y1, _it.x2, _it.y2, true);
                    break;
                case "more":
                    draw_set_colour(make_colour_rgb(190, 190, 230));
                    draw_set_halign(fa_center);
                    draw_text_l((_it.x1 + _it.x2) * 0.5, _my, "...");
                    break;
            }
        }
    }

    draw_set_font_l(_font_b);
    draw_set_halign(_halign_b);
    draw_set_valign(_valign_b);
    draw_set_alpha(1);
}
