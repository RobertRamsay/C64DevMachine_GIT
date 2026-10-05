/// ====================================================================
/// CREATOR LAYER
///
/// A safe "skin" over a workspace. The developer (Pro) exposes values on
/// macro and code block nodes through the PARAMS tab on the node's right
/// side. The Creator view then lists only those values — colour swatches,
/// ranges and named modes — plus build / run / save / load. Everything else
/// is locked: the panel owns input through scr_workspace_input_blocked().
///
/// F9 toggles the Creator view, EDIT GRAPH leaves it, and the OPENS LOCKED
/// switch decides how the workspace opens next time. Light and Pro behave
/// the same here: Light's only restriction is editing code inside code
/// blocks, which the code editor enforces on its own.
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
    // Param cards: params drawn on the canvas beside their node, or
    // stacked under a folded ORG. Rebuilt every Begin Step.
    global.creator_cards        = [];
    global.creator_card_hot     = false;
    global.creator_card_bar     = { active: false, n: noone, pidx: 0, x1: 0, x2: 0, lo: 0, hi: 0, gui: false };
    // Where expanded param cards go: AUTO, RIGHT, LEFT, DOCK, OFF
    // (CREATOR_CARDS_*). Read from the ini on the first Begin Step.
    global.creator_card_mode    = CREATOR_CARDS_AUTO;
    global.creator_card_mode_ok = false;
    global.creator_dock         = { on: false, x1: 0, y1: 0, x2: 0, y2: 0, items: [] };
    // Pointer used for widget hover while drawing (room or GUI space).
    global.creator_hmx          = 0;
    global.creator_hmy          = 0;
    // TEXT params on a card or panel are typed into a small popup.
    global.creator_text_node    = noone;
    global.creator_text_pidx    = 0;
}

// --------------------------------------------------------------------
// PARAM DATA
// --------------------------------------------------------------------

function scr_param_new() {
    return {
        label:   "PARAM",
        kind:    "COLOUR",     // COLOUR, RANGE, MODE, TEXT
        sym:     "",           // MACRO_CODE target symbol
        row:     0,            // macro target row
        slot:    1,            // macro target slot
        vmin:    0,
        vmax:    255,
        options: "Off=0,On=1", // MODE: Label=value, comma separated
        pin:     false         // shown as a card on the canvas
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
    if (variable_struct_exists(_d, "pin"))     _p.pin     = bool(_d.pin);
    if (_p.kind != "COLOUR" && _p.kind != "RANGE" && _p.kind != "MODE" && _p.kind != "TEXT") {
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
    var _res = { ok: false, val: 0, str: "" };
    if (!instance_exists(_n)) {
        return _res;
    }
    // TEXT targets a string slot on a macro (code blocks have no string
    // constants the assembler could use, so they never link).
    if (_p.kind == "TEXT") {
        if (_n.node_type == "MACRO_CODE") {
            return _res;
        }
        if (_p.row >= array_length(_n.instructions)) {
            return _res;
        }
        var _trow = _n.instructions[_p.row];
        if (!is_array(_trow)) {
            return _res;
        }
        if (_p.slot >= array_length(_trow)) {
            return _res;
        }
        if (is_string(_trow[_p.slot])) {
            _res.ok  = true;
            _res.str = _trow[_p.slot];
        }
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

function scr_param_write_text(_n, _p, _s) {
    if (!instance_exists(_n)) {
        return;
    }
    var _cur = scr_param_read(_n, _p);
    if (!_cur.ok) {
        return;
    }
    var _max = max(1, round(_p.vmax));
    if (string_length(_s) > _max) {
        _s = string_copy(_s, 1, _max);
    }
    if (_cur.str == _s) {
        return;
    }
    _n.instructions[_p.row][_p.slot] = _s;
    if (_n.node_type == "MACRO_PRINT") {
        scr_print_sync_height(_n);
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
    if (instance_exists(global.creator_text_node)) {
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

    var _col = make_color_rgb(110, 110, 150);
    if (_np > 0) {
        _col = make_color_rgb(80, 200, 255);
    }
    if (_hot) {
        _col = make_color_rgb(255, 210, 80);
    }
    scr_creator_skin_node_frame(_r.x1, _r.y1, _r.x2 - _r.x1, _r.y2 - _r.y1, 4, _col);
    draw_set_color(c_white);

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
    global.creator_tab_hot  = noone;
    global.creator_card_hot = false;
    scr_creator_update_covered();
    if (!global.creator_card_mode_ok) {
        ini_open("c64devmachine.ini");
        global.creator_card_mode = clamp(round(ini_read_real("Settings", "param_cards", CREATOR_CARDS_AUTO)), 0, CREATOR_CARDS_COUNT - 1);
        ini_close();
        global.creator_card_mode_ok = true;
    }
    global.creator_cards = scr_creator_cards_build();
    scr_creator_cards_make_room();
    scr_creator_dock_build();

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

    if (!instance_exists(global.creator_edit_node)) {
        global.creator_edit_node = noone;
    }
    if (!instance_exists(global.creator_text_node)) {
        global.creator_text_node = noone;
    }
    if (global.creator_view_open || global.creator_edit_node != noone || global.creator_text_node != noone) {
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
    // F9: Creator view.
    if (scr_workspace_keyboard_check_pressed(vk_f9)) {
        if (scr_creator_param_count() > 0) {
            scr_creator_open_view();
        } else {
            scr_show_message("CREATOR VIEW\n\nNo params exposed yet.\nUse the P tab on a macro or code block to add some.");
        }
        exit;
    }

    // Param cards on the canvas own the pointer while it is over them.
    if (scr_creator_cards_step()) {
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

// --------------------------------------------------------------------
// THEME SKIN — the same sprites and style settings the rest of the UI uses:
//   panels  : spr_glassSlice, frame niceSliceFrm (Panel Style)
//   buttons : spr_menu_button, frame paletteStyle, or the cyber frame when
//             the panel style is cyber (uiChromeStyle), hover = additive glow
//   facades : spr_9s_tile1 with nodeStyle, like node bodies and headers
// --------------------------------------------------------------------

function scr_creator_skin_panel(_x1, _y1, _w, _h) {
    var _frm = 0;
    if (instance_exists(obj_workspace_manager)) {
        _frm = obj_workspace_manager.niceSliceFrm;
    }
    draw_sprite_stretched(spr_glassSlice, _frm, _x1, _y1, _w, _h);
}

function scr_creator_skin_btn_frame() {
    var _frm = 0;
    if (instance_exists(obj_workspace_manager)) {
        if (obj_workspace_manager.uiChromeStyle == 0) {
            _frm = obj_workspace_manager.paletteStyle;
        } else {
            _frm = sprite_get_number(spr_menu_button) - 1;
        }
    }
    return _frm;
}

/// Themed button body. _on = selected/active, _hov = pointer over it.
function scr_creator_skin_btn(_x1, _y1, _x2, _y2, _label, _on, _hov) {
    var _frm = scr_creator_skin_btn_frame();
    var _w   = max(1, _x2 - _x1);
    var _h   = max(1, _y2 - _y1);
    var _sx  = _w / sprite_get_width(spr_menu_button);
    var _sy  = _h / sprite_get_height(spr_menu_button);
    var _add = true;
    if (instance_exists(obj_workspace_manager)) {
        if (obj_workspace_manager.uiChromeStyle != 0) {
            _add = false;
        }
    }
    draw_sprite_ext(spr_menu_button, _frm, _x1, _y1, _sx, _sy, 0, c_white, 1);
    if (_hov || _on) {
        var _glow = 0.2;
        if (_on) {
            _glow = 0.35;
        }
        if (_add) {
            gpu_set_blendmode(bm_add);
        }
        draw_sprite_ext(spr_menu_button, _frm, _x1, _y1, _sx, _sy, 0, c_white, _glow);
        if (_add) {
            gpu_set_blendmode(bm_normal);
        }
    }
    draw_set_colour(c_white);
    if (_on) {
        draw_set_colour(c_yellow);
    }
    draw_set_halign(fa_center);
    draw_set_valign(fa_middle);
    draw_text_l((_x1 + _x2) / 2, (_y1 + _y2) / 2, _label);
    draw_set_halign(fa_left);
}

/// Node-style body + header, following the Node Style setting.
function scr_creator_skin_node_frame(_x1, _y1, _w, _h, _head_h, _col) {
    var _style = 0;
    if (instance_exists(obj_workspace_manager)) {
        _style = obj_workspace_manager.nodeStyle;
    }
    var _n9    = sprite_get_number(spr_9s_tile1);
    var _body  = merge_colour(_col, make_colour_rgb(20, 22, 40), 0.7);
    var _dark  = merge_colour(_body, c_black, 0.5);
    var _head  = _col;

    if (_style == _n9 - 1) {
        // Cyber: dark slab, yellow rail, coloured ID strip.
        draw_rectangle_colour(_x1, _y1, _x1 + _w, _y1 + _h,
            make_colour_rgb(22, 24, 26), make_colour_rgb(22, 24, 26),
            make_colour_rgb(10, 12, 14), make_colour_rgb(10, 12, 14), false);
        draw_set_colour(make_colour_rgb(238, 197, 38));
        draw_rectangle(_x1, _y1, _x1 + 3, _y1 + _h, false);
        draw_set_colour(merge_colour(_head, make_colour_rgb(18, 20, 22), 0.72));
        draw_rectangle(_x1, _y1, _x1 + _w, _y1 + _head_h, false);
        draw_set_colour(_head);
        draw_rectangle(_x1 + 3, _y1 + _head_h - 3, _x1 + _w - 10, _y1 + _head_h, false);
        exit;
    }
    if (_style == 0) {
        draw_rectangle_colour(_x1, _y1, _x1 + _w, _y1 + _h, _body, _body, _dark, _dark, false);
        draw_set_colour(_head);
        draw_rectangle(_x1, _y1, _x1 + _w, _y1 + _head_h, false);
        exit;
    }
    var _frm = clamp(_style, 1, max(1, _n9 - 2));
    if (_style >= _n9) {
        _frm = _n9 - 1;
    }
    draw_sprite_stretched_ext(spr_9s_tile1, _frm, _x1, _y1, _w, _h, _body, 1);
    draw_sprite_stretched_ext(spr_9s_tile1, _frm, _x1, _y1, _w, _head_h, _head, 1);
}

function scr_creator_btn(_x1, _y1, _x2, _y2, _label, _on) {
    var _hov = point_in_rectangle(global.creator_mx, global.creator_my, _x1, _y1, _x2, _y2);
    scr_creator_skin_btn(_x1, _y1, _x2, _y2, _label, _on, _hov);
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
    }
    var _ty = (_y1 + _y2) / 2;
    draw_text(_x1 + 6, _ty, _show);
    // Caret: the "_" glyph drawn 2px lower, twice (1px apart) for double
    // thickness, so it sits clear of the text instead of hugging it.
    if (_active) {
        if ((current_time div 500) mod 2 == 0) {
            var _cx = _x1 + 6 + string_width(_show);
            draw_text(_cx, _ty + 2, "_");
            draw_text(_cx, _ty + 3, "_");
        }
    }
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

    if (instance_exists(global.creator_text_node)) {
        scr_creator_draw_text_edit();
    } else if (instance_exists(global.creator_edit_node)) {
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

    scr_creator_skin_panel(_px, _py, _pw, _ph);

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
    var _kinds   = ["COLOUR", "RANGE", "MODE", "TEXT"];

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
            for (var _ki = 0; _ki < 4; _ki++) {
                if (_kinds[_ki] == _p.kind) {
                    _k = _ki;
                }
            }
            _p.kind  = _kinds[(_k + 1) mod 4];
            if (_p.kind == "TEXT") {
                _p.vmin = 0;
                _p.vmax = 40;
            }
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
            // Macros with a slot table step through their NAMED slots only
            // and fill in the label, kind and range; others step raw slots.
            var _names = scr_macro_slot_names(_n.node_type);
            if (scr_creator_btn(_px + 476, _ry, _px + 502, _ry + 26, "-", false)) {
                if (array_length(_names) > 0) {
                    scr_creator_slot_step(_p, _names, -1);
                } else {
                    _p.slot = max(1, _p.slot - 1);
                }
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
                if (array_length(_names) > 0) {
                    scr_creator_slot_step(_p, _names, 1);
                } else {
                    _p.slot = min(max(1, _row_len - 1), _p.slot + 1);
                }
                _changed = true;
            }
            var _sinfo = scr_macro_slot_find(_names, _p.slot);
            draw_set_valign(fa_middle);
            if (is_struct(_sinfo)) {
                draw_set_colour(make_colour_rgb(255, 210, 80));
                draw_text_l(_px + 588, _ry + 13, _sinfo.name);
            } else {
                draw_set_colour(make_colour_rgb(150, 150, 190));
                draw_text_l(_px + 588, _ry + 13, "UNNAMED");
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
        } else if (_p.kind == "TEXT") {
            draw_text_l(_px + 16, _ly + 13, "MAX LEN");
            var _rlen = scr_creator_field("len" + _si, _px + 110, _ly, _px + 190, _ly + 26, _p.vmax);
            if (!is_undefined(_rlen)) {
                _p.vmax  = clamp(round(scr_creator_num(_rlen)), 1, 48);
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
        if (_cur.ok && _p.kind == "TEXT") {
            draw_set_colour(make_colour_rgb(120, 255, 140));
            draw_text_l(_px + 590, _ly + 13, "\"" + string_copy(_cur.str, 1, 14) + "\"");
        } else if (_cur.ok) {
            draw_set_colour(make_colour_rgb(120, 255, 140));
            draw_text(_px + 590, _ly + 13, "VALUE " + string(_cur.val));
            if (_p.kind == "COLOUR") {
                draw_set_colour(scr_c64_pepto_colour(clamp(round(_cur.val), 0, 15)));
                draw_rectangle(_px + 720, _ly + 3, _px + 760, _ly + 23, false);
            }
        } else {
            draw_set_colour(make_colour_rgb(255, 110, 110));
            if (_p.kind == "TEXT") {
                draw_text_l(_px + 590, _ly + 13, "NEEDS A TEXT SLOT");
            } else if (_code) {
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
                // Start on the macro's first named slot, already labelled.
                var _new_names = scr_macro_slot_names(_n.node_type);
                if (array_length(_new_names) > 0) {
                    scr_creator_slot_apply(_np_new, _new_names[0]);
                }
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
    _foot_w += 30 + scr_creator_btn_w("OPENS LOCKED: OFF") + 10 + scr_creator_btn_w("EDIT GRAPH");
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

    scr_creator_skin_panel(_px, _py, _pw, _ph);

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
    draw_set_halign(fa_right);
    draw_text_l(_px + _pw - 16, _py + 56, "F9 / EDIT GRAPH returns to the node graph");
    draw_set_halign(fa_left);

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
            } else if (_p.kind == "TEXT") {
                var _rt = scr_creator_field("view" + string(_h) + "_" + string(_i), _cx, _cy - 13, _cx + 460, _cy + 13, _cur.str);
                if (!is_undefined(_rt)) {
                    scr_param_write_text(_n, _p, _rt);
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
#macro CREATOR_PANEL_ROW_STACK 52
#macro CREATOR_PANEL_ROW_COLOUR2 70   // stacked COLOUR: label + 2 rows of 8
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
        // Panels from older workspaces (and templates) carry no links yet:
        // link them to whatever they cover the first time they are seen.
        if (array_length(panel_links) == 0) {
            panel_links = scr_creator_panel_cover_uids(id);
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

/// stable_uids of the nodes with params whose centre is inside the box.
function scr_creator_panel_cover_uids(_b) {
    var _uids = [];
    var _nodes = scr_creator_panel_cover_nodes(_b);
    for (var _i = 0; _i < array_length(_nodes); _i++) {
        array_push(_uids, _nodes[_i].stable_uid);
    }
    return _uids;
}

/// The nodes this panel drives: its links when it has them, otherwise the
/// nodes it covers. Top to bottom, then left to right.
function scr_creator_panel_nodes(_b) {
    if (array_length(_b.panel_links) == 0) {
        return scr_creator_panel_cover_nodes(_b);
    }
    var _out   = [];
    var _links = _b.panel_links;
    with (obj_c64_node) {
        if (array_length(params) == 0) {
            continue;
        }
        for (var _i = 0; _i < array_length(_links); _i++) {
            if (_links[_i] == stable_uid) {
                array_push(_out, id);
                break;
            }
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

/// Unfold whatever hides a node. The camera is left alone on purpose.
function scr_creator_reveal_node(_n) {
    if (!instance_exists(_n)) {
        return;
    }
    if (_n.org_parent != noone) {
        if (instance_exists(_n.org_parent)) {
            if (_n.org_parent.collapsed) {
                scr_org_set_collapsed(_n.org_parent, false);
            }
        }
    } else if (global.init_collapsed) {
        with (obj_c64_node) {
            if (node_type == "INIT") {
                scr_org_set_collapsed(id, false);
                break;
            }
        }
    }
}

/// Nodes with params whose centre is inside the box, top to bottom.
function scr_creator_panel_cover_nodes(_b) {
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


/// One param's widgets appended to _items, inside content columns _x1.._x2
/// starting at _y. _stack puts the label above a full-width control; _lw is
/// the label column width when not stacked. Shared by panels and cards.
/// Height one param row takes. Stacked COLOUR rows split the palette over
/// two lines of 8 so the swatches stay a usable size.
function scr_creator_param_row_h(_p, _stack) {
    if (!_stack) {
        return CREATOR_PANEL_ROW;
    }
    if (_p.kind == "COLOUR") {
        return CREATOR_PANEL_ROW_COLOUR2;
    }
    return CREATOR_PANEL_ROW_STACK;
}

function scr_creator_param_row(_items, _n, _i, _x1, _x2, _y, _stack, _lw) {
    var _row_h = CREATOR_PANEL_ROW;
    if (_stack) {
        _row_h = CREATOR_PANEL_ROW_STACK;
    }
    var _cx = _x1 + _lw;
    var _cw = _x2 - _cx;
    var _p   = _n.params[_i];
    var _cy  = _y + _row_h * 0.5;
    var _cur = scr_param_read(_n, _p);

    var _lab = scr_creator_item("label", _x1, _y, _cx - 6, _y + _row_h);
    if (_stack) {
        _lab = scr_creator_item("label", _x1, _y, _x2, _y + 20);
        _cy  = _y + 20 + 15;
    }
    _lab.text = _p.label;
    array_push(_items, _lab);

    if (!_cur.ok) {
        var _bad = scr_creator_item("bad", _cx, _cy - 10, _x2, _cy + 10);
        _bad.text = "NOT LINKED";
        array_push(_items, _bad);
    } else if (_p.kind == "COLOUR" && _stack) {
        // Two rows of 8, under the label.
        var _step2 = max(10, floor(_cw / 8));
        for (var _c = 0; _c < 16; _c++) {
            var _sx = _cx + (_c mod 8) * _step2;
            var _sy = _y + 24 + (_c div 8) * 22;
            var _it = scr_creator_item("swatch", _sx, _sy, _sx + _step2 - 5, _sy + 16);
            _it.n    = _n;
            _it.pidx = _i;
            _it.v    = _c;
            _it.on   = (round(_cur.val) == _c);
            array_push(_items, _it);
        }
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
    } else if (_p.kind == "TEXT") {
        // Click to type it in a popup.
        var _tb = scr_creator_item("textbox", _cx, _cy - 11, _x2, _cy + 11);
        _tb.n    = _n;
        _tb.pidx = _i;
        _tb.text = _cur.str;
        array_push(_items, _tb);
    } else if (_p.kind == "MODE") {
        var _opts = scr_param_options(_p.options);
        var _ox   = _cx;
        for (var _o = 0; _o < array_length(_opts); _o++) {
            var _ow = string_width_l(_opts[_o].name) + 16;
            if (_ox + _ow > _x2) {
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

    var _nodes = scr_creator_panel_nodes(_b);
    var _multi = (array_length(_nodes) > 1);
    var _y     = _by1 + CREATOR_PANEL_HEAD + 6;
    // Narrow panels stack each param: label on one line, the control on a
    // full-width line under it. Wide panels keep label and control side by side.
    var _stack = (_b.box_w < 420);
    var _row_h = CREATOR_PANEL_ROW;
    var _lw    = floor(_b.box_w * 0.38);
    if (_stack) {
        _row_h = CREATOR_PANEL_ROW_STACK;
        _lw    = 0;
    }
    var _cx    = _bx1 + _pad + _lw;
    var _cw    = _bx2 - _pad - _cx;

    if (array_length(_nodes) == 0) {
        // Runs to the bottom of the box so the text can shrink to fit it.
        var _none = scr_creator_item("text", _bx1 + _pad, _y, _bx2 - _pad, _by2 - 4);
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
            var _rh = scr_creator_param_row_h(_n.params[_i], _stack);
            if (_y + _rh > _by2 - 4) {
                array_push(_items, scr_creator_item("more", _bx1, _by2 - 14, _bx2, _by2));
                return _items;
            }
            scr_creator_param_row(_items, _n, _i, _bx1 + _pad, _bx2 - _pad, _y, _stack, _lw);
            _y += _rh;
        }
    }
    return _items;
}

/// The one button above the box, left of its delete X (developer only):
///   UI   - plain box: turn panel mode on (facade drops over the nodes)
///   EDIT - panel: turn panel mode off (back to the normal node view)
function scr_creator_box_buttons(_b) {
    var _out = [];
    var _right = _b.x + _b.box_w - 22;
    var _bt = scr_creator_item("toggle", _right - 50, _b.y - 18, _right, _b.y);
    if (_b.is_panel) {
        _bt.text = "EDIT";
    } else {
        _bt.text = "UI";
    }
    array_push(_out, _bt);
    // GO: jump the view to the panel's nodes (each press steps to the next).
    if (_b.is_panel) {
        var _go = scr_creator_item("go", _right - 124, _b.y - 18, _right - 54, _b.y);
        _go.text = "GO TO";
        array_push(_out, _go);
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
        if (_bt.t == "toggle") {
            if (_b.is_panel) {
                // EDIT: back to a plain box, and take the view to the linked
                // nodes (unfolding their ORG) so they can be worked on.
                var _linked = scr_creator_panel_nodes(_b);
                _b.is_panel      = false;
                _b.panel_editing = false;
                if (array_length(_linked) > 0) {
                    scr_creator_reveal_node(_linked[0]);
                }
            } else {
                // UI: link to the param nodes the box covers. Covering none
                // keeps the previous links, so a panel can go back to being a
                // panel from anywhere.
                var _cover = scr_creator_panel_cover_uids(_b);
                if (array_length(_cover) > 0) {
                    _b.panel_links = _cover;
                }
                _b.is_panel      = true;
                _b.panel_editing = false;
            }
            global.selected_nodes = [];
        }
        if (_bt.t == "go") {
            // Asked for, so moving the camera is fine here (EDIT never does).
            var _gnodes = scr_creator_panel_nodes(_b);
            if (array_length(_gnodes) > 0) {
                _b.panel_go_idx = _b.panel_go_idx mod array_length(_gnodes);
                var _gn = _gnodes[_b.panel_go_idx];
                scr_creator_reveal_node(_gn);
                scr_focus_camera_on_node(_gn);
                global.selected_nodes = [_gn];
                _b.panel_go_idx += 1;
            }
            return true;
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

    // The header bar is a grab handle: start the box's own drag (Step_0
    // carries it on from the next frame). Panels move alone - no nodes.
    if (_my < _b.y + CREATOR_PANEL_HEAD) {
        scr_undo_snapshot();
        _b.is_dragging   = true;
        _b.drag_ox       = mouse_x;
        _b.drag_oy       = mouse_y;
        _b.drag_start_x  = _b.x;
        _b.drag_start_y  = _b.y;
        _b.drag_nodes    = [];
        _b.drag_offsets  = [];
        _b.drag_floats   = [];
        _b.drag_float_ox = [];
        _b.drag_float_oy = [];
        return true;
    }

    draw_set_font_l(fnt_c64_code);
    var _items = scr_creator_panel_layout(_b);
    if (scr_creator_items_press(_items, _mx, _my, _b.panel_bar)) {
        return true;
    }
    // The facade protects what is under it: a click anywhere on it stops here.
    return true;
}


/// A press on panel / card widgets. _bar is the slider-drag state to arm.
/// Returns true when a widget used the click.
function scr_creator_items_press(_items, _mx, _my, _bar) {
    for (var _i = 0; _i < array_length(_items); _i++) {
        var _it = _items[_i];
        if (!point_in_rectangle(_mx, _my, _it.x1, _it.y1 - 3, _it.x2, _it.y2 + 3)) {
            continue;
        }
        if (!instance_exists(_it.n)) {
            continue;
        }
        if (_it.pidx >= array_length(_it.n.params)) {
            continue;
        }
        var _p = _it.n.params[_it.pidx];
        if (_it.t == "textbox") {
            global.creator_text_node = _it.n;
            global.creator_text_pidx = _it.pidx;
            scr_creator_opened();
            global.creator_field      = "ptext";
            keyboard_string           = _it.text;
            global.creator_field_text = _it.text;
            return true;
        }
        if (_it.t == "swatch" || _it.t == "minus" || _it.t == "plus" || _it.t == "opt") {
            scr_param_write(_it.n, _p, _it.v);
            return true;
        }
        if (_it.t == "bar") {
            _bar.active = true;
            _bar.n      = _it.n;
            _bar.pidx     = _it.pidx;
            _bar.x1     = _it.x1;
            _bar.x2     = _it.x2;
            _bar.lo     = _it.lo;
            _bar.hi     = _it.hi;
            var _f = clamp((_mx - _it.x1) / max(1, _it.x2 - _it.x1), 0, 1);
            scr_param_write(_it.n, _p, _it.lo + _f * (_it.hi - _it.lo));
            return true;
        }
    }
    return false;
}

/// Facade buttons stay plain for readability: dark fill, coloured outline,
/// selected = filled in the colour with black text.
function scr_creator_draw_room_btn(_it, _on, _col) {
    var _hov = point_in_rectangle(global.creator_hmx, global.creator_hmy, _it.x1, _it.y1, _it.x2, _it.y2);
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


/// Draw panel / card widgets built by scr_creator_param_row. Font must be
/// fnt_c64_code. _col tints node sub-headings.
function scr_creator_draw_items(_items, _col) {
    for (var _i = 0; _i < array_length(_items); _i++) {
        var _it = _items[_i];
        var _my = (_it.y1 + _it.y2) * 0.5;
        draw_set_valign(fa_middle);
        draw_set_halign(fa_left);
        switch (_it.t) {
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
                // Word-wrapped to the item width, and scaled down (in 10%
                // steps, to 40%) when the wrapped text is taller than the item.
                draw_set_colour(make_colour_rgb(190, 190, 230));
                draw_set_valign(fa_top);
                var _tw  = max(20, _it.x2 - _it.x1);
                var _tah = max(10, _it.y2 - _it.y1 - 4);
                var _tsc = 1;
                while (_tsc > 0.4) {
                    if (string_height_ext_l(_it.text, 20, _tw / _tsc) * _tsc <= _tah) {
                        break;
                    }
                    _tsc -= 0.1;
                }
                draw_text_ext_transformed_l(_it.x1, _it.y1 + 4, _it.text, 20, _tw / _tsc, _tsc, _tsc, 0);
                draw_set_valign(fa_middle);
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
            case "textbox":
                var _thov = point_in_rectangle(global.creator_hmx, global.creator_hmy, _it.x1, _it.y1, _it.x2, _it.y2);
                draw_set_colour(make_colour_rgb(8, 8, 24));
                draw_rectangle(_it.x1, _it.y1, _it.x2, _it.y2, false);
                draw_set_colour(make_colour_rgb(180, 180, 255));
                if (_thov) {
                    draw_set_colour(make_colour_rgb(255, 210, 80));
                }
                draw_rectangle(_it.x1, _it.y1, _it.x2, _it.y2, true);
                draw_set_colour(c_white);
                var _tshow = _it.text;
                while (string_length(_tshow) > 0 && string_width_l(_tshow) > _it.x2 - _it.x1 - 12) {
                    _tshow = string_copy(_tshow, 1, string_length(_tshow) - 1);
                }
                draw_text_l(_it.x1 + 6, _my, _tshow);
                break;
            case "more":
                draw_set_colour(make_colour_rgb(190, 190, 230));
                draw_set_halign(fa_center);
                draw_text_l((_it.x1 + _it.x2) * 0.5, _my, "...");
                break;
        }
    }
}

/// obj_mapping_box Draw (room space). Buttons above the box always; the
/// facade itself only while the panel is up.
function scr_creator_box_draw(_b) {
    global.creator_hmx = mouse_x;
    global.creator_hmy = mouse_y;
    var _col      = _b.box_colours[_b.box_col_idx];
    var _font_b   = draw_get_font();
    var _halign_b = draw_get_halign();
    var _valign_b = draw_get_valign();
    draw_set_font_l(fnt_c64_code);

    // UI / EDIT: plain, like the box's own name tab.
    var _btns = scr_creator_box_buttons(_b);
    for (var _i = 0; _i < array_length(_btns); _i++) {
        var _bt = _btns[_i];
        draw_set_colour(_col);
        draw_rectangle(_bt.x1, _bt.y1, _bt.x2, _bt.y2, false);
        draw_set_colour(c_black);
        draw_set_halign(fa_center);
        draw_set_valign(fa_middle);
        draw_text_l((_bt.x1 + _bt.x2) * 0.5, (_bt.y1 + _bt.y2) * 0.5, _bt.text);
        draw_set_halign(fa_left);
    }

    if (_b.is_panel && !_b.panel_editing) {
        var _bx1 = _b.x;
        var _by1 = _b.y;
        var _bx2 = _b.x + _b.box_w;
        var _by2 = _b.y + _b.box_h;

        draw_set_alpha(1);
        scr_creator_skin_node_frame(_bx1, _by1, _b.box_w, _b.box_h, CREATOR_PANEL_HEAD, _col);
        draw_set_colour(c_white);
        draw_set_halign(fa_left);
        draw_set_valign(fa_middle);
        // Title shrinks to fit a narrow panel instead of running past it.
        var _title  = string_upper(_b.box_name);
        var _ttw    = string_width_l(_title);
        var _tfit   = _b.box_w - CREATOR_PANEL_PAD * 2;
        var _tscale = 1;
        if (_ttw > _tfit && _ttw > 0) {
            _tscale = max(0.4, _tfit / _ttw);
        }
        draw_text_transformed_l(_bx1 + CREATOR_PANEL_PAD, _by1 + CREATOR_PANEL_HEAD * 0.5, _title, _tscale, _tscale, 0);

        scr_creator_draw_items(scr_creator_panel_layout(_b), _col);
    }

    draw_set_font_l(_font_b);
    draw_set_halign(_halign_b);
    draw_set_valign(_valign_b);
    draw_set_alpha(1);
}


// ====================================================================
// MACRO SLOT NAMES
//
// What each value slot of a macro means, so the P-tab editor can say
// "SLOT 5 - BORDER" instead of a bare index, and fill in the label, kind
// and range when a slot is picked. Row 0 only; names come from each
// macro's spawn layout and draw code. Only slots a user could sensibly
// tweak are listed - addresses, asset names, ZP and var names are not.
// Macros not listed fall back to raw slot stepping ("UNNAMED").
// ====================================================================

function scr_slot(_slot, _name, _kind, _vmin, _vmax, _options) {
    return { slot: _slot, name: _name, kind: _kind, vmin: _vmin, vmax: _vmax, options: _options };
}

function scr_macro_slot_names(_type) {
    switch (_type) {
        case "MACRO_WAIT":
            return [scr_slot(1, "FRAMES", "RANGE", 1, 255, "")];
        case "MACRO_NOP_REPEAT":
            return [scr_slot(1, "NOP COUNT", "RANGE", 1, 255, "")];
        case "MACRO_VWAIT":
            return [scr_slot(1, "RASTER LINE", "RANGE", 0, 255, "")];
        case "MACRO_IRQ":
            return [scr_slot(1, "RASTER LINE", "RANGE", 0, 255, "")];
        case "MACRO_DISPLAY":
            return [scr_slot(1, "DISPLAY", "MODE", 0, 1, "Off=0,On=1")];
        case "MACRO_VIC":
            return [
                scr_slot(5, "BORDER",       "COLOUR", 0, 15, ""),
                scr_slot(6, "BACKGROUND",   "COLOUR", 0, 15, ""),
                scr_slot(7, "BACKGROUND 1", "COLOUR", 0, 15, ""),
                scr_slot(8, "BACKGROUND 2", "COLOUR", 0, 15, ""),
                scr_slot(9, "BACKGROUND 3", "COLOUR", 0, 15, "")
            ];
        case "MACRO_PRINT":
            return [
                scr_slot(1, "COLUMN",    "RANGE",  0, 39, ""),
                scr_slot(2, "ROW",       "RANGE",  0, 24, ""),
                scr_slot(3, "COLOUR",    "COLOUR", 0, 15, ""),
                scr_slot(4, "PRE-CLEAR", "MODE",   0, 1,  "Off=0,On=1"),
                scr_slot(5, "TEXT",      "TEXT",   0, 40, ""),
                scr_slot(7, "ALIGN H",   "MODE",   0, 3,  "Default=0,Left=1,Centre=2,Right=3"),
                scr_slot(8, "ALIGN V",   "MODE",   0, 3,  "Default=0,Top=1,Middle=2,Bottom=3")
            ];
        case "MACRO_PRINT_EXT":
            return [
                scr_slot(1, "COLUMN", "RANGE",  0, 39, ""),
                scr_slot(2, "ROW",    "RANGE",  0, 24, ""),
                scr_slot(3, "COLOUR", "COLOUR", 0, 15, "")
            ];
        case "MACRO_SPR":
            return [
                scr_slot(2, "SPRITE", "RANGE", 0, 7,   ""),
                scr_slot(3, "X",      "RANGE", 0, 344, ""),
                scr_slot(4, "Y",      "RANGE", 0, 255, ""),
                scr_slot(5, "FRAME",  "RANGE", 0, 255, "")
            ];
        case "MACRO_SPR_ENABLE":
            return [scr_slot(1, "SPRITE MASK", "RANGE", 0, 255, "")];
        case "MACRO_SPR_EXPAND":
            return [
                scr_slot(1, "EXPAND X MASK", "RANGE", 0, 255, ""),
                scr_slot(2, "EXPAND Y MASK", "RANGE", 0, 255, "")
            ];
        case "MACRO_PRIORITY":
            return [scr_slot(1, "BEHIND MASK", "RANGE", 0, 255, "")];
        case "MACRO_SID":
            return [
                scr_slot(2, "TRACK",  "RANGE", 0, 31, ""),
                scr_slot(3, "VOLUME", "RANGE", 0, 15, "")
            ];
        case "MACRO_SID_PAUSE":
            return [scr_slot(1, "MUSIC", "MODE", 0, 1, "Pause=0,Resume=1")];
        case "MACRO_METASCROLL":
            return [
                scr_slot(2,  "MAP",               "RANGE", 0, 15,  ""),
                scr_slot(8,  "BORDER BLANK CHAR", "RANGE", 0, 255, ""),
                scr_slot(11, "TOP ROWS OMITTED",  "RANGE", 0, 8,   ""),
                scr_slot(12, "BOTTOM ROWS OMITTED", "RANGE", 0, 8, "")
            ];
        case "MACRO_TEXT_SCROLL":
            return [
                scr_slot(1, "ROW",    "RANGE",  0, 24, ""),
                scr_slot(2, "COLOUR", "COLOUR", 0, 15, ""),
                scr_slot(3, "SPEED",  "RANGE",  1, 8,  ""),
                scr_slot(6, "TEXT",   "TEXT",   0, 48, ""),
                scr_slot(7, "PRE NOPS",  "RANGE", 0, 63, ""),
                scr_slot(8, "POST NOPS", "RANGE", 0, 63, "")
            ];
        case "MACRO_SEEK":
            return [
                scr_slot(2, "TARGET X",      "RANGE", 0, 344, ""),
                scr_slot(3, "TARGET Y",      "RANGE", 0, 255, ""),
                scr_slot(4, "SPEED",         "RANGE", 1, 8,   ""),
                scr_slot(5, "NEAR DISTANCE", "RANGE", 0, 255, ""),
                scr_slot(6, "NEAR SPEED",    "RANGE", 0, 8,   "")
            ];
        case "MACRO_MOVE":
            return [
                scr_slot(11, "MIN X",   "RANGE", 0,  344, ""),
                scr_slot(12, "MAX X",   "RANGE", 0,  344, ""),
                scr_slot(13, "MIN Y",   "RANGE", 0,  255, ""),
                scr_slot(14, "MAX Y",   "RANGE", 0,  255, "")
            ];
        case "MACRO_ANIM":
            return [scr_slot(1, "SPEED (FRAMES)", "RANGE", 1, 255, "")];
        case "MACRO_CLR_SCREEN":
            return [scr_slot(2, "FILL CHAR", "RANGE", 0, 255, "")];
        case "MACRO_MATH":
            return [scr_slot(4, "OPERAND", "RANGE", -128, 127, "")];
        case "MACRO_GET_CHAR":
            return [
                scr_slot(1, "COLUMN", "RANGE", 0, 39, ""),
                scr_slot(4, "ROW",    "RANGE", 0, 24, "")
            ];
        case "MACRO_RANDOM":
            return [
                scr_slot(3, "CLAMP",   "MODE",  0, 1,   "Off=0,On=1"),
                scr_slot(4, "MINIMUM", "RANGE", 0, 255, ""),
                scr_slot(5, "MAXIMUM", "RANGE", 0, 255, "")
            ];
        case "MACRO_MAP_SWITCH":
            return [scr_slot(2, "MAP", "RANGE", 0, 15, "")];
        case "MACRO_MAP":
            return [
                scr_slot(2, "WIDTH",  "RANGE", 1, 40, ""),
                scr_slot(3, "HEIGHT", "RANGE", 1, 25, "")
            ];
        case "MACRO_MOVE_BMP_BLOCK":
            return [
                scr_slot(3, "SOURCE COLUMN", "RANGE", 0, 39, ""),
                scr_slot(4, "SOURCE ROW",    "RANGE", 0, 24, ""),
                scr_slot(5, "DEST COLUMN",   "RANGE", 0, 39, ""),
                scr_slot(6, "DEST ROW",      "RANGE", 0, 24, ""),
                scr_slot(7, "WIDTH",         "RANGE", 1, 40, ""),
                scr_slot(8, "HEIGHT",        "RANGE", 1, 25, "")
            ];
        case "MACRO_CLEAR_BMP_RECT":
            return [
                scr_slot(2, "COLUMN", "RANGE", 0, 39, ""),
                scr_slot(3, "ROW",    "RANGE", 0, 24, ""),
                scr_slot(4, "WIDTH",  "RANGE", 1, 40, ""),
                scr_slot(5, "HEIGHT", "RANGE", 1, 25, "")
            ];
        case "MACRO_VOI64_MASTER":
            return [
                scr_slot(1, "PITCH",  "RANGE", 0, 255, ""),
                scr_slot(2, "SPEED",  "RANGE", 0, 255, ""),
                scr_slot(3, "THROAT", "RANGE", 0, 255, ""),
                scr_slot(4, "MOUTH",  "RANGE", 0, 255, "")
            ];
        case "MACRO_VECTOR_PAGE":
            return [scr_slot(2, "PAGE", "RANGE", 0, 7, "")];
    }
    return [];
}

/// The entry for a slot, or undefined when the slot has no name.
function scr_macro_slot_find(_names, _slot) {
    for (var _i = 0; _i < array_length(_names); _i++) {
        if (_names[_i].slot == _slot) {
            return _names[_i];
        }
    }
    return undefined;
}

/// Point a param at a named slot: label, kind and range follow it.
function scr_creator_slot_apply(_p, _info) {
    _p.slot    = _info.slot;
    _p.label   = string_upper(string_char_at(_info.name, 1)) + string_lower(string_delete(_info.name, 1, 1));
    _p.kind    = _info.kind;
    _p.vmin    = _info.vmin;
    _p.vmax    = _info.vmax;
    if (_info.options != "") {
        _p.options = _info.options;
    }
}

/// Step to the previous / next named slot. The label follows only if it
/// was still the old slot's name (or the default), so a label the
/// developer typed is never overwritten.
function scr_creator_slot_step(_p, _names, _dir) {
    var _cur = -1;
    for (var _i = 0; _i < array_length(_names); _i++) {
        if (_names[_i].slot == _p.slot) {
            _cur = _i;
        }
    }
    var _next = 0;
    if (_cur >= 0) {
        _next = clamp(_cur + _dir, 0, array_length(_names) - 1);
    } else if (_dir < 0) {
        _next = array_length(_names) - 1;
    }
    var _keep_label = true;
    if (_p.label == "PARAM") {
        _keep_label = false;
    }
    if (_cur >= 0) {
        var _old = _names[_cur].name;
        var _old_auto = string_upper(string_char_at(_old, 1)) + string_lower(string_delete(_old, 1, 1));
        if (_p.label == _old_auto) {
            _keep_label = false;
        }
    }
    var _label_was = _p.label;
    scr_creator_slot_apply(_p, _names[_next]);
    if (_keep_label) {
        _p.label = _label_was;
    }
}


// ====================================================================
// PARAM CARDS
//
// Every param is drawn on the canvas as a card UNLESS its node belongs to a
// UI panel - it is one or the other. Turn the panel off (EDIT) or delete
// the box and the node's params come back as cards:
//   ORG unfolded - the node's cards sit to the right of its P tab, joined
//                  to it by a bracket.
//   ORG folded   - every card in the block stacks under the ORG
//                  header, with a sub-heading per node. An ORG below that
//                  the stack would land on is pushed down out of the way.
// Cards are drawn in obj_workspace_manager Draw End, over the nodes, and
// own the pointer while it is over them (global.creator_card_hot).
// ====================================================================

#macro CREATOR_CARD_W     280
#macro CREATOR_CARD_GAP   22
#macro CREATOR_CARD_CLEAR 40

/// Every node a raised UI panel drives - those params live in the panel.
function scr_creator_panelled_nodes() {
    var _out = [];
    with (obj_mapping_box) {
        if (!is_panel) {
            continue;
        }
        var _nodes = scr_creator_panel_nodes(id);
        for (var _i = 0; _i < array_length(_nodes); _i++) {
            array_push(_out, _nodes[_i]);
        }
    }
    return _out;
}

/// The header a hidden node is folded under, or noone.
function scr_creator_fold_anchor(_n) {
    if (_n.org_parent != noone) {
        if (instance_exists(_n.org_parent)) {
            if (_n.org_parent.collapsed) {
                return _n.org_parent;
            }
        }
        return noone;
    }
    if (!global.init_collapsed) {
        return noone;
    }
    var _init = noone;
    with (obj_c64_node) {
        if (node_type == "INIT") {
            _init = id;
            break;
        }
    }
    return _init;
}

function scr_creator_card_new(_x1, _y1, _w) {
    return { x1: _x1, y1: _y1, x2: _x1 + _w, y2: _y1, items: [], anchor: noone, tab: noone, side: "R", col: make_colour_rgb(80, 200, 255) };
}

/// Lay one node's params into a card. _sub adds the node's name
/// as a heading. Returns the y under the last row.
function scr_creator_card_add_node(_card, _n, _y, _sub) {
    var _x1 = _card.x1 + CREATOR_PANEL_PAD;
    var _x2 = _card.x2 - CREATOR_PANEL_PAD;
    if (_sub) {
        var _it = scr_creator_item("sub", _x1, _y, _x2, _y + CREATOR_PANEL_SUB);
        _it.text = string_upper(scr_creator_node_name(_n));
        array_push(_card.items, _it);
        _y += CREATOR_PANEL_SUB;
    }
    for (var _i = 0; _i < array_length(_n.params); _i++) {
        scr_creator_param_row(_card.items, _n, _i, _x1, _x2, _y, true, 0);
        _y += scr_creator_param_row_h(_n.params[_i], true);
    }
    return _y;
}

/// Every card on the canvas this frame. Font is set for string widths.
function scr_creator_cards_build() {
    var _cards = [];
    var _font_b = draw_get_font();
    draw_set_font_l(fnt_c64_code);

    // Nodes with params: visible ones get a card beside them; folded ones are
    // grouped under their header. Nodes a UI panel drives are left to it.
    var _panelled = scr_creator_panelled_nodes();
    var _beside   = [];
    var _folded   = [];
    var _anchors  = [];
    with (obj_c64_node) {
        if (array_length(params) == 0) {
            continue;
        }
        if (macro_owner != noone) {
            continue;
        }
        if (creator_covered) {
            continue;
        }
        var _in_panel = false;
        for (var _k = 0; _k < array_length(_panelled); _k++) {
            if (_panelled[_k] == id) {
                _in_panel = true;
                break;
            }
        }
        if (_in_panel) {
            continue;
        }
        if (scr_node_is_hidden(id)) {
            var _a = scr_creator_fold_anchor(id);
            if (_a != noone) {
                array_push(_folded, id);
                array_push(_anchors, _a);
            }
        } else {
            array_push(_beside, id);
        }
    }

    var _mode = global.creator_card_mode;
    if (_mode == CREATOR_CARDS_DOCK) {
        // Everything goes to the screen-edge dock; nothing on the canvas.
        draw_set_font_l(_font_b);
        return _cards;
    }
    if (_mode == CREATOR_CARDS_OFF) {
        _beside = [];
    }
    for (var _i = 0; _i < array_length(_beside); _i++) {
        var _n  = _beside[_i];
        var _tr = scr_creator_tab_rect(_n);
        // Measure first (height does not depend on x), then pick a side.
        var _c  = scr_creator_card_new(0, _n.y, CREATOR_CARD_W);
        var _y  = scr_creator_card_add_node(_c, _n, _c.y1 + 6, false);
        var _h  = _y + 4 - _c.y1;
        var _rx = _tr.x2 + CREATOR_CARD_GAP;
        var _lx = _n.x + _n.x_indent - CREATOR_CARD_GAP - CREATOR_CARD_W;
        var _side = "R";
        if (_mode == CREATOR_CARDS_LEFT) {
            _side = "L";
        } else if (_mode == CREATOR_CARDS_AUTO) {
            if (scr_creator_card_blocked(_rx, _n.y, CREATOR_CARD_W, _h, _n)) {
                if (!scr_creator_card_blocked(_lx, _n.y, CREATOR_CARD_W, _h, _n)) {
                    _side = "L";
                }
            }
        }
        var _cx = _rx;
        if (_side == "L") {
            _cx = _lx;
        }
        _c       = scr_creator_card_new(_cx, _n.y, CREATOR_CARD_W);
        _c.tab   = _n;
        _c.side  = _side;
        _y       = scr_creator_card_add_node(_c, _n, _c.y1 + 6, false);
        _c.y2    = _y + 4;
        array_push(_cards, _c);
    }

    // One stack per folded header, nodes in spine order.
    var _done = [];
    for (var _i = 0; _i < array_length(_anchors); _i++) {
        var _a = _anchors[_i];
        var _seen = false;
        for (var _d = 0; _d < array_length(_done); _d++) {
            if (_done[_d] == _a) {
                _seen = true;
            }
        }
        if (_seen) {
            continue;
        }
        array_push(_done, _a);
        var _group = [];
        for (var _j = 0; _j < array_length(_folded); _j++) {
            if (_anchors[_j] == _a) {
                array_push(_group, _folded[_j]);
            }
        }
        array_sort(_group, function(_p, _q) {
            return _p.y - _q.y;
        });
        // As wide as the header plus one grid tile each side, centred on it.
        var _c = scr_creator_card_new(_a.x + _a.x_indent - 20, _a.y + _a.height + 8, _a.width + 40);
        _c.anchor = _a;
        var _y = _c.y1 + 4;
        for (var _g = 0; _g < array_length(_group); _g++) {
            _y = scr_creator_card_add_node(_c, _group[_g], _y, true);
        }
        _c.y2 = _y + 4;
        array_push(_cards, _c);
    }

    draw_set_font_l(_font_b);
    return _cards;
}

/// Push any ORG a folded stack would land on down below it, snapped to the
/// 20px grid with some clearance. Never while something is being dragged.
function scr_creator_cards_make_room() {
    if (global.any_node_dragging) {
        exit;
    }
    var _box_drag = false;
    with (obj_mapping_box) {
        if (is_dragging || is_resizing) {
            _box_drag = true;
        }
    }
    if (_box_drag) {
        exit;
    }
    var _moved = false;
    for (var _i = 0; _i < array_length(global.creator_cards); _i++) {
        var _c = global.creator_cards[_i];
        if (_c.anchor == noone) {
            continue;
        }
        var _a      = _c.anchor;
        var _bottom = _c.y2 + CREATOR_CARD_CLEAR;
        with (obj_c64_node) {
            if (id == _a) {
                continue;
            }
            if (node_type != "ORG") {
                continue;
            }
            if (org_parent != noone) {
                continue;
            }
            if (y <= _a.y || y >= _bottom) {
                continue;
            }
            var _ox1 = x + x_indent;
            var _ox2 = _ox1 + width;
            if (_ox2 <= _c.x1 || _ox1 >= _c.x2) {
                continue;
            }
            y = ceil(_bottom / 20) * 20;
            _moved = true;
        }
    }
    if (_moved) {
        global.addresses_dirty  = true;
        global.autosave_dirty   = true;
        global.relayout_frames  = max(global.relayout_frames, 3);
        obj_workspace_manager.flow_overlay_dirty = true;
    }
}

/// Begin Step pointer handling. True when a card owns the pointer.
function scr_creator_cards_step() {
    var _bar = global.creator_card_bar;
    var _mx  = mouse_x;
    var _my  = mouse_y;

    // Slider drag in progress: keeps the pointer until release. A dock
    // slider follows the GUI pointer, a canvas one the room pointer.
    if (_bar.active) {
        global.creator_card_hot = true;
        if (_bar.gui) {
            _mx = device_mouse_x_to_gui(0);
        }
        if (scr_workspace_mouse_check_button(mb_left) && instance_exists(_bar.n)) {
            if (_bar.pidx < array_length(_bar.n.params)) {
                var _f = clamp((_mx - _bar.x1) / max(1, _bar.x2 - _bar.x1), 0, 1);
                scr_param_write(_bar.n, _bar.n.params[_bar.pidx], _bar.lo + _f * (_bar.hi - _bar.lo));
            }
        } else {
            _bar.active = false;
        }
        return true;
    }

    // The dock (GUI space) sits over the canvas, so it is checked first.
    var _dk = global.creator_dock;
    if (_dk.on) {
        var _gmx = device_mouse_x_to_gui(0);
        var _gmy = device_mouse_y_to_gui(0);
        if (point_in_rectangle(_gmx, _gmy, _dk.x1, _dk.y1, _dk.x2, _dk.y2)) {
            global.creator_card_hot = true;
            if (scr_workspace_mouse_check_button_pressed(mb_left)) {
                if (scr_creator_items_press(_dk.items, _gmx, _gmy, _bar)) {
                    _bar.gui = true;
                }
            }
            return true;
        }
    }

    var _over = noone;
    for (var _i = 0; _i < array_length(global.creator_cards); _i++) {
        var _c = global.creator_cards[_i];
        if (point_in_rectangle(_mx, _my, _c.x1, _c.y1, _c.x2, _c.y2)) {
            _over = _c;
        }
    }
    if (!is_struct(_over)) {
        return false;
    }
    global.creator_card_hot = true;
    if (scr_workspace_mouse_check_button_pressed(mb_left)) {
        if (scr_creator_items_press(_over.items, _mx, _my, _bar)) {
            _bar.gui = false;
        }
    }
    return true;
}

/// obj_workspace_manager Draw End (room space, over the nodes).
function scr_creator_draw_cards() {
    if (array_length(global.creator_cards) == 0) {
        exit;
    }
    var _font_b   = draw_get_font();
    var _halign_b = draw_get_halign();
    var _valign_b = draw_get_valign();
    draw_set_font_l(fnt_c64_code);
    draw_set_alpha(1);
    global.creator_hmx = mouse_x;
    global.creator_hmy = mouse_y;

    for (var _i = 0; _i < array_length(global.creator_cards); _i++) {
        var _c = global.creator_cards[_i];
        // Card on the left: bracket from the node's left edge, level with
        // its P tab, across to the card's right edge.
        if (_c.tab != noone && _c.side == "L") {
            if (instance_exists(_c.tab)) {
                var _ltr = scr_creator_tab_rect(_c.tab);
                var _lty = (_ltr.y1 + _ltr.y2) * 0.5;
                var _lnx = _c.tab.x + _c.tab.x_indent;
                var _lbx = _lnx - floor(CREATOR_CARD_GAP * 0.5);
                draw_set_colour(_c.col);
                draw_line_width(_lnx, _lty, _lbx, _lty, 2);
                draw_line_width(_lbx, _c.y1 + 8, _lbx, _c.y2 - 8, 2);
                draw_line_width(_lbx, _c.y1 + 8, _c.x2, _c.y1 + 8, 2);
                draw_line_width(_lbx, _c.y2 - 8, _c.x2, _c.y2 - 8, 2);
            }
        }
        // Bracket from the node's P tab to its card.
        if (_c.tab != noone && _c.side == "R") {
            if (instance_exists(_c.tab)) {
                var _tr = scr_creator_tab_rect(_c.tab);
                var _ty = (_tr.y1 + _tr.y2) * 0.5;
                var _bx = _tr.x2 + floor(CREATOR_CARD_GAP * 0.5);
                draw_set_colour(_c.col);
                draw_line_width(_tr.x2, _ty, _bx, _ty, 2);
                draw_line_width(_bx, _c.y1 + 8, _bx, _c.y2 - 8, 2);
                draw_line_width(_bx, _c.y1 + 8, _c.x1, _c.y1 + 8, 2);
                draw_line_width(_bx, _c.y2 - 8, _c.x1, _c.y2 - 8, 2);
            }
        }
        scr_creator_skin_node_frame(_c.x1, _c.y1, _c.x2 - _c.x1, _c.y2 - _c.y1, 3, _c.col);
        scr_creator_draw_items(_c.items, _c.col);
    }

    draw_set_font_l(_font_b);
    draw_set_halign(_halign_b);
    draw_set_valign(_valign_b);
    draw_set_alpha(1);
}


/// TEXT popup for a card / panel param. Enter or OK saves, Esc or CANCEL
/// leaves the text as it was. Owns input while open (scr_creator_panel_active).
function scr_creator_draw_text_edit() {
    var _n = global.creator_text_node;
    if (global.creator_text_pidx >= array_length(_n.params)) {
        global.creator_text_node = noone;
        global.creator_field     = "";
        exit;
    }
    var _p  = _n.params[global.creator_text_pidx];
    var _gw = display_get_gui_width();
    var _gh = display_get_gui_height();
    var _pw = 720;
    var _ph = 170;
    var _px = floor((_gw - _pw) / 2);
    var _py = floor((_gh - _ph) / 2);
    scr_creator_skin_panel(_px, _py, _pw, _ph);

    draw_set_font_l(fnt_C64_Angled);
    draw_set_halign(fa_left);
    draw_set_valign(fa_top);
    draw_set_colour(c_white);
    draw_text_l(_px + 16, _py + 14, string_upper(_p.label));
    draw_set_font_l(fnt_c64_tiny);
    draw_set_colour(make_colour_rgb(190, 190, 230));
    draw_text_l(_px + 16, _py + 44, "UP TO " + string(round(_p.vmax)) + " CHARACTERS. ENTER SAVES, ESC CANCELS.");
    draw_set_font_l(fnt_C64_Angled);

    // Keep the field live: a click inside the popup must not drop it.
    if (global.creator_field == "") {
        global.creator_field = "ptext";
    }
    var _max = max(1, round(_p.vmax));
    if (string_length(keyboard_string) > _max) {
        keyboard_string = string_copy(keyboard_string, 1, _max);
    }
    // Clicks outside the field (OK / CANCEL) must not auto-commit it;
    // OK saves explicitly, CANCEL must not save at all.
    global.creator_commit = false;
    var _cur = scr_param_read(_n, _p);
    var _r   = scr_creator_field("ptext", _px + 16, _py + 72, _px + _pw - 16, _py + 102, _cur.str);
    var _done = false;
    if (!is_undefined(_r)) {
        scr_param_write_text(_n, _p, _r);
        _done = true;
    }
    var _by = _py + _ph - 46;
    if (scr_creator_btn(_px + _pw - 316, _by, _px + _pw - 166, _by + 30, "OK", false)) {
        scr_param_write_text(_n, _p, global.creator_field_text);
        _done = true;
    }
    if (scr_creator_btn(_px + _pw - 156, _by, _px + _pw - 16, _by + 30, "CANCEL", false)) {
        _done = true;
    }
    if (keyboard_check_pressed(vk_escape)) {
        _done = true;
    }
    if (_done) {
        global.creator_text_node = noone;
        global.creator_field     = "";
        global.creator_commit    = false;
    }
}


// ====================================================================
// CARD PLACEMENT MODES  (OPTIONS > PARAM CARDS, or P)
//   AUTO  - right of the node; flips left when the right side would cover
//           another node (stays right if both sides are blocked)
//   RIGHT - always right       LEFT - always left
//   DOCK  - no cards on the canvas; a strip at the right of the screen
//           shows the params of the nodes in view
//   OFF   - no cards beside unfolded nodes (panels, folded stacks and the
//           F9 view still show params)
// ====================================================================

#macro CREATOR_CARDS_AUTO  0
#macro CREATOR_CARDS_RIGHT 1
#macro CREATOR_CARDS_LEFT  2
#macro CREATOR_CARDS_DOCK  3
#macro CREATOR_CARDS_OFF   4
#macro CREATOR_CARDS_COUNT 5
#macro CREATOR_DOCK_W      300

function scr_creator_card_mode_name(_m) {
    switch (_m) {
        case CREATOR_CARDS_AUTO:  return "AUTO";
        case CREATOR_CARDS_RIGHT: return "RIGHT";
        case CREATOR_CARDS_LEFT:  return "LEFT";
        case CREATOR_CARDS_DOCK:  return "DOCK";
        case CREATOR_CARDS_OFF:   return "OFF";
    }
    return "AUTO";
}

/// Step the placement mode (_dir 1 / -1), save it, and say so.
function scr_creator_card_mode_cycle(_dir) {
    global.creator_card_mode = (global.creator_card_mode + _dir + CREATOR_CARDS_COUNT) mod CREATOR_CARDS_COUNT;
    ini_open("c64devmachine.ini");
    ini_write_real("Settings", "param_cards", global.creator_card_mode);
    ini_close();
    global.qmenu_toast_text = "PARAM CARDS: " + scr_creator_card_mode_name(global.creator_card_mode);
    global.qmenu_toast_col  = c_yellow;
    global.qmenu_toast_t    = global.qmenu_toast_dur;
}

/// True when a card rectangle would cover any visible node other than _self.
function scr_creator_card_blocked(_x1, _y1, _w, _h, _self) {
    var _hit = false;
    with (obj_c64_node) {
        if (id == _self) {
            continue;
        }
        if (macro_owner == _self) {
            continue;
        }
        if (scr_node_is_hidden(id)) {
            continue;
        }
        var _nx1 = x + x_indent;
        var _nx2 = _nx1 + width;
        var _ny2 = y + height;
        if (_nx2 > _x1 && _nx1 < _x1 + _w && _ny2 > _y1 && y < _y1 + _h) {
            _hit = true;
            break;
        }
    }
    return _hit;
}

/// DOCK mode: params of nodes in view (a folded node counts where its
/// header is), laid out in GUI space down the right of the screen.
function scr_creator_dock_build() {
    var _dk = global.creator_dock;
    _dk.on    = false;
    _dk.items = [];
    if (global.creator_card_mode != CREATOR_CARDS_DOCK) {
        exit;
    }
    if (obj_workspace_manager.hideui) {
        exit;
    }
    var _vx1 = camera_get_view_x(view_camera[0]);
    var _vy1 = camera_get_view_y(view_camera[0]);
    var _vx2 = _vx1 + camera_get_view_width(view_camera[0]);
    var _vy2 = _vy1 + camera_get_view_height(view_camera[0]);

    var _panelled = scr_creator_panelled_nodes();
    var _nodes    = [];
    with (obj_c64_node) {
        if (array_length(params) == 0) {
            continue;
        }
        if (macro_owner != noone) {
            continue;
        }
        if (creator_covered) {
            continue;
        }
        var _in_panel = false;
        for (var _k = 0; _k < array_length(_panelled); _k++) {
            if (_panelled[_k] == id) {
                _in_panel = true;
                break;
            }
        }
        if (_in_panel) {
            continue;
        }
        var _at = id;
        if (scr_node_is_hidden(id)) {
            _at = scr_creator_fold_anchor(id);
            if (_at == noone) {
                continue;
            }
        }
        if (_at.x + _at.width < _vx1 || _at.x > _vx2 || _at.y + _at.height < _vy1 || _at.y > _vy2) {
            continue;
        }
        array_push(_nodes, id);
    }
    if (array_length(_nodes) == 0) {
        exit;
    }
    array_sort(_nodes, function(_a, _b) {
        if (_a.x != _b.x) {
            return _a.x - _b.x;
        }
        return _a.y - _b.y;
    });

    var _font_b = draw_get_font();
    draw_set_font_l(fnt_c64_code);
    var _gw  = display_get_gui_width();
    var _gh  = display_get_gui_height();
    _dk.x1 = _gw - CREATOR_DOCK_W - 12;
    _dk.x2 = _gw - 12;
    _dk.y1 = 64;
    var _x1 = _dk.x1 + CREATOR_PANEL_PAD;
    var _x2 = _dk.x2 - CREATOR_PANEL_PAD;
    var _y  = _dk.y1 + 8;
    var _bottom = _gh - 24;
    var _full = false;
    for (var _i = 0; _i < array_length(_nodes); _i++) {
        var _n = _nodes[_i];
        if (_y + CREATOR_PANEL_SUB > _bottom) {
            _full = true;
            break;
        }
        var _sub = scr_creator_item("sub", _x1, _y, _x2, _y + CREATOR_PANEL_SUB);
        _sub.text = string_upper(scr_creator_node_name(_n));
        array_push(_dk.items, _sub);
        _y += CREATOR_PANEL_SUB;
        for (var _p = 0; _p < array_length(_n.params); _p++) {
            var _rh = scr_creator_param_row_h(_n.params[_p], true);
            if (_y + _rh > _bottom) {
                _full = true;
                break;
            }
            scr_creator_param_row(_dk.items, _n, _p, _x1, _x2, _y, true, 0);
            _y += _rh;
        }
        if (_full) {
            break;
        }
    }
    if (_full) {
        array_push(_dk.items, scr_creator_item("more", _x1, _y, _x2, _y + 14));
        _y += 14;
    }
    _dk.y2 = _y + 6;
    _dk.on = true;
    draw_set_font_l(_font_b);
}

/// obj_workspace_manager Draw GUI End, under any Creator popup.
function scr_creator_draw_dock() {
    var _dk = global.creator_dock;
    if (!_dk.on) {
        exit;
    }
    if (scr_creator_panel_active()) {
        exit;
    }
    if (instance_exists(obj_asset_manager)) {
        if (obj_asset_manager.viewer_open) {
            exit;
        }
    }
    var _font_b   = draw_get_font();
    var _halign_b = draw_get_halign();
    var _valign_b = draw_get_valign();
    var _col      = make_colour_rgb(80, 200, 255);
    global.creator_hmx = device_mouse_x_to_gui(0);
    global.creator_hmy = device_mouse_y_to_gui(0);
    scr_creator_skin_node_frame(_dk.x1, _dk.y1, _dk.x2 - _dk.x1, _dk.y2 - _dk.y1, 3, _col);
    draw_set_font_l(fnt_c64_code);
    draw_set_alpha(1);
    scr_creator_draw_items(_dk.items, _col);
    draw_set_font_l(_font_b);
    draw_set_halign(_halign_b);
    draw_set_valign(_valign_b);
    draw_set_alpha(1);
}
