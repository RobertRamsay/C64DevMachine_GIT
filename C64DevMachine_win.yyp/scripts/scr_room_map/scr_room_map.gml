/// ====================================================================
/// ROOM MAP — scenes that connect to one another.
///
/// ROOM_MAP asset (authoring only, no C64 payload of its own):
///   meta.rooms[]  one struct per scene:
///       name, bmp (BITMAP asset in the REU), coll (LINE_COLL asset or ""),
///       mx, my (position on the map view), sx, sy (spawn point, bitmap px),
///       exits[6]  { to, ax, ay } — exit e is LINE_COLL line type e + 2.
///                 to = target room index (-1 none); ax/ay = where the
///                 player lands in the target room, in bitmap pixels.
///   meta.reu      LOAD_REU manifest the bitmaps are fetched from.
///
/// MACRO_ROOMS node: ["macro_rooms", map, room_var, player_slots, hot_x,
///                    hot_y, enter_hook, auto_start]
///   Emits room tables plus three entry points, all prefixed RM_<MAP>_:
///     start  enter the room in ROOM at that room's spawn point
///     door   A = collider line type; follows that exit if it has one
///     enter  (re)load the room in ROOM at the current arrival point
///   and coll_lo/coll_hi — the current room's line table, which a
///   MACRO_COLL_LINE whose asset is this ROOM_MAP reads instead of a
///   fixed LINE_COLL.
/// ====================================================================

#macro ROOMMAP_EXITS 6

function scr_room_map_new_room(_name, _mx, _my) {
    var _ex = [];
    for (var _e = 0; _e < ROOMMAP_EXITS; _e++) {
        array_push(_ex, { to: -1, ax: 160, ay: 120 });
    }
    return { name: _name, bmp: "", coll: "", mask: "", mx: _mx, my: _my, sx: 160, sy: 120, exits: _ex };
}

/// Seed a complete meta (also used under a loaded file's saved keys).
function scr_room_map_create(_asset) {
    _asset.meta = {
        rooms       : [],
        reu         : "",
        zoom        : 1,
        sel_room    : -1,
        sel_exit    : -1,
        link_exit   : -1,
        drag_room   : -1,
        drag_dx     : 0,
        drag_dy     : 0,
        bmp_click_room : -1,
        bmp_click_time : -10000,
        bmp_click_x : 0,
        bmp_click_y : 0,
        pick_mode   : "",
        pick_scroll : 0,
        name_edit_active : false,
        name_edit_buf    : "",
        tone_sorted : false,
        mc_mode     : 0
    };
    array_push(_asset.meta.rooms, scr_room_map_new_room("ROOM0", 40, 40));
    _asset.meta.sel_room = 0;
    // First LOAD_REU in the project is the sensible default
    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
            var _a = ds_list_find_value(_am.asset_list, _i);
            if (_a.type == "LOAD_REU") {
                _asset.meta.reu = _a.name;
                break;
            }
        }
    }
}

/// Keys that are the asset (everything else in meta is editor state).
function scr_room_map_save_keys() {
    return ["rooms", "reu", "zoom", "sel_room"];
}

/// Rebuild a loaded asset: defaults first, saved keys over them, then make
/// every room complete so older/hand-built files never leave a gap.
function scr_room_map_restore(_asset, _saved_meta) {
    scr_room_map_create(_asset);
    _asset.meta.rooms = [];
    var _keys = scr_room_map_save_keys();
    for (var _k = 0; _k < array_length(_keys); _k++) {
        if (is_struct(_saved_meta) && variable_struct_exists(_saved_meta, _keys[_k])) {
            _asset.meta[$ _keys[_k]] = _saved_meta[$ _keys[_k]];
        }
    }
    var _rooms = _asset.meta.rooms;
    for (var _r = 0; _r < array_length(_rooms); _r++) {
        var _fresh = scr_room_map_new_room("ROOM" + string(_r), 40, 40);
        var _names = variable_struct_get_names(_fresh);
        for (var _n = 0; _n < array_length(_names); _n++) {
            if (!variable_struct_exists(_rooms[_r], _names[_n])) {
                _rooms[_r][$ _names[_n]] = _fresh[$ _names[_n]];
            }
        }
        while (array_length(_rooms[_r].exits) < ROOMMAP_EXITS) {
            array_push(_rooms[_r].exits, { to: -1, ax: 160, ay: 120 });
        }
    }
    if (_asset.meta.sel_room >= array_length(_rooms)) {
        _asset.meta.sel_room = array_length(_rooms) - 1;
    }
}

function scr_room_map_find_asset(_name) {
    if (_name == "" || !instance_exists(obj_asset_manager)) return undefined;
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.type == "ROOM_MAP" && _a.name == _name) return _a;
    }
    return undefined;
}

/// Label prefix shared by MACRO_ROOMS and MACRO_COLL_LINE.
function scr_room_map_prefix(_name) {
    var _clean = "";
    for (var _i = 1; _i <= string_length(_name); _i++) {
        var _ch = string_char_at(_name, _i);
        var _o  = ord(_ch);
        if ((_o >= 48 && _o <= 57) || (_o >= 65 && _o <= 90) || (_o >= 97 && _o <= 122) || _ch == "_") {
            _clean += _ch;
        }
    }
    return "RM_" + _clean + "_";
}

/// Cached (or freshly built) preview surface of a BITMAP asset, or -1.
function scr_room_map_bmp_surf(_bmp_name) {
    if (_bmp_name == "") return -1;
    var _a = scr_reu_find_asset(_bmp_name);
    if (is_undefined(_a) || _a.type != "BITMAP" || !is_struct(_a.meta)) return -1;
    if (variable_struct_exists(_a.meta, "preview_surf") && surface_exists(_a.meta.preview_surf)) {
        return _a.meta.preview_surf;
    }
    scr_asset_bmp_build_preview(_a);
    if (variable_struct_exists(_a.meta, "preview_surf") && surface_exists(_a.meta.preview_surf)) {
        return _a.meta.preview_surf;
    }
    return -1;
}

/// Colour for exit / line type t (1 = wall).
function scr_room_map_type_col(_t) {
    var _cols = [c_gray, make_color_rgb(230, 70, 70), make_color_rgb(250, 200, 60),
                 make_color_rgb(90, 220, 110), make_color_rgb(80, 180, 255),
                 make_color_rgb(220, 110, 240), make_color_rgb(255, 140, 60)];
    return _cols[clamp(_t, 1, 7) - 1];
}

// --------------------------------------------------------------------
// MAP VIEW EDITOR (wide asset panel)
// --------------------------------------------------------------------
function scr_room_map_editor(_asset, _vx1, _vy1, _vx2, _vy2, _cy, _mx, _my) {
    if (!is_struct(_asset.meta) || !variable_struct_exists(_asset.meta, "rooms")) {
        scr_room_map_create(_asset);
    }
    var _m     = _asset.meta;
    // Transient double-click state is intentionally not saved in the asset.
    if (!variable_struct_exists(_m, "bmp_click_room")) {
        _m.bmp_click_room = -1;
        _m.bmp_click_time = -10000;
        _m.bmp_click_x = 0;
        _m.bmp_click_y = 0;
    }
    var _rooms = _m.rooms;
    var _n     = array_length(_rooms);
    if (_m.sel_room >= _n) { _m.sel_room = _n - 1; }

    var _c_lbl  = make_color_rgb(140, 150, 180);
    var _c_dim  = make_color_rgb(95, 95, 115);
    var _c_box  = make_color_rgb(20, 22, 32);
    var _c_edge = make_color_rgb(56, 56, 78);
    var _press  = mouse_check_button_pressed(mb_left);

    var _button = function(_x1, _y1, _w, _h, _label, _col, _mx2, _my2, _info = "") {
        var _hov = point_in_rectangle(_mx2, _my2, _x1, _y1, _x1 + _w, _y1 + _h);
        scr_ui_info(_hov, _info);
        if (_hov) {
            draw_set_color(merge_color(_col, c_white, 0.25));
        } else {
            draw_set_color(_col);
        }
        draw_rectangle(_x1, _y1, _x1 + _w, _y1 + _h, false);
        draw_set_color(c_white);
        draw_set_halign(fa_center);
        draw_text_l(_x1 + _w * 0.5, _y1 + 3, _label);
        draw_set_halign(fa_left);
        return (_hov && mouse_check_button_pressed(mb_left));
    };

    draw_set_font_l(fnt_c64_tiny);

    // ── Geometry ──
    var _px1 = _vx2 - 470;           // right panel
    var _px2 = _vx2 - 10;
    var _cvx1 = _vx1 + 10;           // map canvas
    var _cvy1 = _cy + 28;
    var _cvx2 = _px1 - 10;
    var _cvy2 = _vy2 - 12;
    var _z    = 1;
    if (_m.zoom == 2) { _z = 0.75; }
    if (_m.zoom == 3) { _z = 0.5; }
    var _bw   = 128 * _z;            // room box
    var _bh   = 96 * _z;

    // ── Toolbar ──
    if (_button(_vx1 + 10, _cy, 70, 18, "+ ROOM", make_color_rgb(30, 80, 40), _mx, _my, "ADDS A NEW ROOM (TO THE RIGHT OF THE SELECTED ONE) AND SELECTS IT")) {
        var _nx = 40;
        var _ny = 40;
        if (_m.sel_room >= 0) {
            _nx = _rooms[_m.sel_room].mx + 160;
            _ny = _rooms[_m.sel_room].my;
        }
        array_push(_rooms, scr_room_map_new_room("ROOM" + string(_n), _nx, _ny));
        _m.sel_room = _n;
        _m.sel_exit = -1;
        _n += 1;
        global.addresses_dirty = true;
    }
    if (_button(_vx1 + 86, _cy, 70, 18, "DELETE", make_color_rgb(80, 30, 30), _mx, _my, "DELETES THE SELECTED ROOM AND UNLINKS EXITS TO IT (THE LAST ROOM STAYS)")) {
        if (_m.sel_room >= 0 && _n > 1) {
            var _dead = _m.sel_room;
            array_delete(_rooms, _dead, 1);
            _n -= 1;
            for (var _r = 0; _r < _n; _r++) {
                for (var _e = 0; _e < ROOMMAP_EXITS; _e++) {
                    var _ex = _rooms[_r].exits[_e];
                    if (_ex.to == _dead) {
                        _ex.to = -1;
                    } else if (_ex.to > _dead) {
                        _ex.to -= 1;
                    }
                }
            }
            _m.sel_room = min(_dead, _n - 1);
            _m.sel_exit = -1;
            global.addresses_dirty = true;
        }
    }
    // REU manifest cycler
    var _reu_lbl = "REU: (none)";
    if (_m.reu != "") { _reu_lbl = "REU: " + _m.reu; }
    if (_button(_vx1 + 170, _cy, 190, 18, _reu_lbl, make_color_rgb(25, 65, 80), _mx, _my, "CYCLES THE LOAD_REU MANIFEST WHOSE BITMAPS THE ROOMS CAN USE")) {
        var _mans = [];
        var _am = obj_asset_manager;
        for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
            var _a = ds_list_find_value(_am.asset_list, _i);
            if (_a.type == "LOAD_REU") { array_push(_mans, _a.name); }
        }
        if (array_length(_mans) > 0) {
            var _at = -1;
            for (var _i = 0; _i < array_length(_mans); _i++) {
                if (_mans[_i] == _m.reu) { _at = _i; break; }
            }
            _m.reu = _mans[(_at + 1) mod array_length(_mans)];
            global.addresses_dirty = true;
        }
    }
    var _zl = ["ZOOM 1", "ZOOM 2", "ZOOM 3"];
    if (_button(_vx1 + 366, _cy, 64, 18, _zl[clamp(_m.zoom, 1, 3) - 1], make_color_rgb(38, 38, 58), _mx, _my, "CYCLES THE MAP ZOOM (1 = LARGEST ROOM BOXES)")) {
        _m.zoom = (_m.zoom mod 3) + 1;
    }
    draw_set_color(_c_dim);
    var _hint = "DOUBLE-CLICK BITMAP TO EDIT  -  DRAG TO ARRANGE  -  EXIT [LINK], THEN CLICK TARGET ROOM";
    if (_m.link_exit >= 0) {
        _hint = "CLICK THE ROOM EXIT D" + string(_m.link_exit + 2) + " LEADS TO  -  EMPTY SPACE / ESC CANCELS";
    }
    draw_text_l(_vx1 + 440, _cy + 4, _hint);

    // ── Canvas ──
    draw_set_color(_c_box);
    draw_rectangle(_cvx1, _cvy1, _cvx2, _cvy2, false);
    draw_set_color(_c_edge);
    draw_rectangle(_cvx1, _cvy1, _cvx2, _cvy2, true);
    // light grid
    draw_set_alpha(0.25);
    for (var _gx = _cvx1 + 40 * _z; _gx < _cvx2; _gx += 40 * _z) {
        draw_line(_gx, _cvy1, _gx, _cvy2);
    }
    for (var _gy = _cvy1 + 40 * _z; _gy < _cvy2; _gy += 40 * _z) {
        draw_line(_cvx1, _gy, _cvx2, _gy);
    }
    draw_set_alpha(1);

    var _maxmx = max(0, (_cvx2 - _cvx1 - _bw) / _z);
    var _maxmy = max(0, (_cvy2 - _cvy1 - _bh) / _z);

    // Exit arrows first, so boxes sit on top
    for (var _r = 0; _r < _n; _r++) {
        var _ra  = _rooms[_r];
        var _ax1 = _cvx1 + clamp(_ra.mx, 0, _maxmx) * _z + _bw * 0.5;
        var _ay1 = _cvy1 + clamp(_ra.my, 0, _maxmy) * _z + _bh * 0.5;
        for (var _e = 0; _e < ROOMMAP_EXITS; _e++) {
            var _to = _ra.exits[_e].to;
            if (_to < 0 || _to >= _n) continue;
            var _rb  = _rooms[_to];
            var _bx2 = _cvx1 + clamp(_rb.mx, 0, _maxmx) * _z + _bw * 0.5;
            var _by2 = _cvy1 + clamp(_rb.my, 0, _maxmy) * _z + _bh * 0.5;
            var _dir = point_direction(_ax1, _ay1, _bx2, _by2);
            // Offset each direction sideways so a two-way link shows both arrows
            var _ox  = lengthdir_x(5 + _e * 2, _dir - 90);
            var _oy  = lengthdir_y(5 + _e * 2, _dir - 90);
            var _col = scr_room_map_type_col(_e + 2);
            draw_set_color(_col);
            var _len = point_distance(_ax1, _ay1, _bx2, _by2);
            var _stop = max(0, _len - min(_bw, _bh) * 0.6);
            var _tx = _ax1 + _ox + lengthdir_x(_stop, _dir);
            var _ty = _ay1 + _oy + lengthdir_y(_stop, _dir);
            draw_line_width(_ax1 + _ox, _ay1 + _oy, _tx, _ty, 2);
            draw_triangle(_tx, _ty,
                _tx + lengthdir_x(10, _dir + 150), _ty + lengthdir_y(10, _dir + 150),
                _tx + lengthdir_x(10, _dir - 150), _ty + lengthdir_y(10, _dir - 150), false);
            var _lx = _ax1 + _ox + lengthdir_x(_stop * 0.35, _dir);
            var _ly = _ay1 + _oy + lengthdir_y(_stop * 0.35, _dir);
            draw_set_color(c_black);
            draw_rectangle(_lx - 10, _ly - 6, _lx + 10, _ly + 6, false);
            draw_set_color(_col);
            draw_set_halign(fa_center);
            draw_text_l(_lx, _ly - 6, "D" + string(_e + 2));
            draw_set_halign(fa_left);
        }
    }

    // Room boxes
    var _hover_room = -1;
    var _hover_bitmap = -1;
    for (var _r = 0; _r < _n; _r++) {
        var _ro = _rooms[_r];
        var _x1 = _cvx1 + clamp(_ro.mx, 0, _maxmx) * _z;
        var _y1 = _cvy1 + clamp(_ro.my, 0, _maxmy) * _z;
        var _hov = point_in_rectangle(_mx, _my, _x1, _y1, _x1 + _bw, _y1 + _bh);
        if (_hov) { _hover_room = _r; }
        draw_set_color(make_color_rgb(14, 14, 22));
        draw_rectangle(_x1, _y1, _x1 + _bw, _y1 + _bh, false);
        var _th = _bh - 16 * _z;
        if (_hov) {
            _hover_bitmap = -1;
            if (_ro.bmp != "" && point_in_rectangle(_mx, _my, _x1 + 2, _y1 + 2, _x1 + _bw - 2, _y1 + _th)) {
                _hover_bitmap = _r;
            }
        }
        var _surf = scr_room_map_bmp_surf(_ro.bmp);
        if (_surf != -1) {
            var _fl = gpu_get_tex_filter();
            gpu_set_tex_filter(false);
            draw_surface_stretched(_surf, _x1 + 2, _y1 + 2, _bw - 4, _th - 2);
            gpu_set_tex_filter(_fl);
        } else {
            draw_set_color(_c_dim);
            draw_set_halign(fa_center);
            draw_text_l(_x1 + _bw * 0.5, _y1 + _th * 0.5 - 6, "NO BITMAP");
            draw_set_halign(fa_left);
        }
        var _ecol = _c_edge;
        if (_hov) { _ecol = make_color_rgb(120, 120, 160); }
        if (_r == _m.sel_room) { _ecol = c_yellow; }
        if (_m.link_exit >= 0 && _hov) { _ecol = scr_room_map_type_col(_m.link_exit + 2); }
        draw_set_color(_ecol);
        draw_rectangle(_x1, _y1, _x1 + _bw, _y1 + _bh, true);
        draw_rectangle(_x1 + 1, _y1 + 1, _x1 + _bw - 1, _y1 + _bh - 1, true);
        draw_set_color(c_white);
        var _nm = string(_r) + " " + _ro.name;
        if (_r == 0) { _nm += " *"; }
        draw_text_l(_x1 + 4, _y1 + _th + 1, string_copy(_nm, 1, max(4, floor(_bw / 7))));
    }

    // Canvas input
    var _on_canvas = point_in_rectangle(_mx, _my, _cvx1, _cvy1, _cvx2, _cvy2);
    if (_on_canvas) {
        if (_m.link_exit >= 0) {
            scr_ui_info(true, "LINKING D" + string(_m.link_exit + 2) + ": CLICK THE TARGET ROOM; EMPTY SPACE OR ESC CANCELS");
        } else if (_hover_bitmap >= 0) {
            scr_ui_info(true, "ROOM BITMAP: CLICK SELECTS, DRAG MOVES, DOUBLE-CLICK OPENS THE BITMAP EDITOR");
        } else if (_hover_room >= 0) {
            scr_ui_info(true, "ROOM: CLICK SELECTS IT, DRAG ARRANGES IT ON THE MAP (SNAPS TO 8)");
        } else {
            scr_ui_info(true, "ROOM MAP: ROOM 0 (*) IS THE START ROOM; ARROWS SHOW EXITS D2-D5 BETWEEN ROOMS");
        }
    }
    if (_press && (!_on_canvas || _hover_bitmap < 0 || _m.link_exit >= 0)) {
        _m.bmp_click_room = -1;
    }
    if (_press && _on_canvas) {
        if (_m.link_exit >= 0 && _m.sel_room >= 0) {
            if (_hover_room >= 0) {
                _rooms[_m.sel_room].exits[_m.link_exit].to = _hover_room;
                _m.sel_exit = _m.link_exit;
                global.addresses_dirty = true;
            }
            _m.link_exit = -1;
        } else if (_hover_room >= 0) {
            if (_hover_bitmap == _hover_room) {
                var _double = (_m.bmp_click_room == _hover_room
                    && current_time - _m.bmp_click_time < 350
                    && point_distance(_mx, _my, _m.bmp_click_x, _m.bmp_click_y) <= 6);
                _m.bmp_click_room = _hover_room;
                _m.bmp_click_time = current_time;
                _m.bmp_click_x = _mx;
                _m.bmp_click_y = _my;
                if (_double) {
                    _m.bmp_click_room = -1;
                    _m.drag_room = -1;
                    _m.sel_room = _hover_room;
                    _m.name_edit_active = false;
                    _m.pick_mode = "";
                    if (scr_room_map_open_bitmap(_rooms[_hover_room].bmp)) return;
                }
            }
            if (_m.sel_room != _hover_room) {
                _m.sel_exit = -1;
                _m.name_edit_active = false;
                _m.pick_mode = "";
            }
            _m.sel_room  = _hover_room;
            _m.drag_room = _hover_room;
            _m.drag_dx   = (_mx - _cvx1) / _z - clamp(_rooms[_hover_room].mx, 0, _maxmx);
            _m.drag_dy   = (_my - _cvy1) / _z - clamp(_rooms[_hover_room].my, 0, _maxmy);
        }
    }
    if (_m.drag_room >= 0) {
        if (mouse_check_button(mb_left) && _m.drag_room < _n) {
            // A drag must never count as the first click of an edit gesture.
            if (point_distance(_mx, _my, _m.bmp_click_x, _m.bmp_click_y) > 6) {
                _m.bmp_click_room = -1;
            }
            var _dr = _rooms[_m.drag_room];
            _dr.mx = clamp(round(((_mx - _cvx1) / _z - _m.drag_dx) / 8) * 8, 0, _maxmx);
            _dr.my = clamp(round(((_my - _cvy1) / _z - _m.drag_dy) / 8) * 8, 0, _maxmy);
        } else {
            _m.drag_room = -1;
        }
    }
    if (_m.link_exit >= 0 && keyboard_check_pressed(vk_escape)) {
        _m.link_exit = -1;
        keyboard_clear(vk_escape);
    }

    // ── Right panel ──
    draw_set_color(_c_box);
    draw_rectangle(_px1, _cvy1, _px2, _cvy2, false);
    draw_set_color(_c_edge);
    draw_rectangle(_px1, _cvy1, _px2, _cvy2, true);
    if (_m.sel_room < 0 || _m.sel_room >= _n) {
        draw_set_color(_c_dim);
        draw_text_l(_px1 + 10, _cvy1 + 10, "SELECT A ROOM");
        return;
    }
    var _ro  = _rooms[_m.sel_room];
    var _qx  = _px1 + 10;
    var _qy  = _cvy1 + 8;
    var _qw  = _px2 - _px1 - 20;

    draw_set_color(make_color_rgb(90, 220, 190));
    var _ttl = "ROOM " + string(_m.sel_room);
    if (_m.sel_room == 0) { _ttl += "  (START ROOM)"; }
    draw_text_l(_qx, _qy, _ttl);
    _qy += 18;

    // NAME
    draw_set_color(_c_lbl);
    draw_text_l(_qx, _qy + 3, "NAME");
    var _nbx1 = _qx + 70;
    var _nbx2 = _qx + _qw;
    var _nhov = point_in_rectangle(_mx, _my, _nbx1, _qy, _nbx2, _qy + 16);
    scr_ui_info(_nhov, "ROOM NAME: CLICK TO EDIT (A-Z, 0-9, _), ENTER KEEPS, ESC CANCELS");
    if (_m.name_edit_active) {
        draw_set_color(make_color_rgb(20, 60, 30));
    } else {
        draw_set_color(make_color_rgb(20, 35, 25));
    }
    draw_rectangle(_nbx1, _qy, _nbx2, _qy + 16, false);
    draw_set_color(c_lime);
    if (_m.name_edit_active) {
        var _blink = " ";
        if ((current_time mod 600) < 300) { _blink = "_"; }
        draw_text_l(_nbx1 + 5, _qy + 3, _m.name_edit_buf + _blink);
        if (keyboard_check_pressed(vk_backspace) && string_length(_m.name_edit_buf) > 0) {
            _m.name_edit_buf = string_delete(_m.name_edit_buf, string_length(_m.name_edit_buf), 1);
        }
        if (keyboard_string != "") {
            var _nt = scr_strip_key_ghosts(keyboard_string);
            for (var _ni = 1; _ni <= string_length(_nt); _ni++) {
                var _nch = string_upper(string_char_at(_nt, _ni));
                var _ok  = false;
                if (_nch >= "A" && _nch <= "Z") { _ok = true; }
                if (_nch >= "0" && _nch <= "9") { _ok = true; }
                if (_nch == "_") { _ok = true; }
                if (_ok && string_length(_m.name_edit_buf) < 16) { _m.name_edit_buf += _nch; }
            }
            keyboard_string = "";
        }
        if (keyboard_check_pressed(vk_enter) || keyboard_check_pressed(vk_escape)) {
            if (keyboard_check_pressed(vk_enter) && _m.name_edit_buf != "") {
                _ro.name = _m.name_edit_buf;
            }
            _m.name_edit_active = false;
            keyboard_string = "";
            keyboard_clear(vk_escape);
        }
    } else {
        draw_text_l(_nbx1 + 5, _qy + 3, _ro.name);
        if (_nhov && _press) {
            _m.name_edit_active = true;
            _m.name_edit_buf    = _ro.name;
            keyboard_string     = "";
        }
    }
    _qy += 22;

    // BITMAP / COLLIDERS pickers
    draw_set_color(_c_lbl);
    draw_text_l(_qx, _qy + 3, "BITMAP");
    var _bl = _ro.bmp;
    if (_bl == "") { _bl = "(choose)"; }
    if (_button(_qx + 70, _qy, _qw - 70, 16, string_copy(_bl, 1, 52), make_color_rgb(25, 55, 75), _mx, _my, "PICKS THE ROOM BITMAP FROM THE BITMAPS IN THE REU MANIFEST")) {
        _m.pick_mode = "BMP";
        _m.pick_scroll = 0;
    }
    _qy += 20;
    draw_set_color(_c_lbl);
    draw_text_l(_qx, _qy + 3, "COLLIDERS");
    var _cl = _ro.coll;
    if (_cl == "") { _cl = "(none)"; }
    if (_button(_qx + 70, _qy, _qw - 70, 16, string_copy(_cl, 1, 52), make_color_rgb(60, 45, 25), _mx, _my, "PICKS THE LINE_COLL ASSET WITH THIS ROOM COLLIDER LINES (DOOR LINES D2-D5)")) {
        _m.pick_mode = "COLL";
        _m.pick_scroll = 0;
    }
    _qy += 20;
    draw_set_color(_c_lbl);
    draw_text_l(_qx, _qy + 3, "MASK");
    var _mkl = _ro.mask;
    if (_mkl == "") { _mkl = "(none)"; }
    if (_button(_qx + 70, _qy, _qw - 70, 16, string_copy(_mkl, 1, 52), make_color_rgb(70, 30, 70), _mx, _my, "PICKS THE SPRITE_MASK ASSET FOR THIS ROOM")) {
        _m.pick_mode = "MASK";
        _m.pick_scroll = 0;
    }
    _qy += 24;

    // ── Picker list (replaces the rest of the panel while open) ──
    if (_m.pick_mode != "") {
        var _items = [""];
        var _am = obj_asset_manager;
        if (_m.pick_mode == "BMP") {
            var _man = scr_reu_find_asset(_m.reu);
            if (!is_undefined(_man) && variable_struct_exists(_man, "linked_assets")) {
                for (var _i = 0; _i < array_length(_man.linked_assets); _i++) {
                    var _la = scr_reu_find_asset(_man.linked_assets[_i].asset_name);
                    if (!is_undefined(_la) && _la.type == "BITMAP") { array_push(_items, _la.name); }
                }
            }
        } else {
            var _want = "LINE_COLL";
            if (_m.pick_mode == "MASK") { _want = "SPRITE_MASK"; }
            for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
                var _a = ds_list_find_value(_am.asset_list, _i);
                if (_a.type == _want) { array_push(_items, _a.name); }
            }
        }
        var _rows = floor((_cvy2 - _qy - 250) / 16);
        _rows = max(4, _rows);
        var _cnt = array_length(_items);
        if (point_in_rectangle(_mx, _my, _px1, _qy, _px2, _cvy2)) {
            if (mouse_wheel_up())   { _m.pick_scroll = max(0, _m.pick_scroll - 2); }
            if (mouse_wheel_down()) { _m.pick_scroll = min(max(0, _cnt - _rows), _m.pick_scroll + 2); }
        }
        var _hov_name = "";
        for (var _li = 0; _li < _rows; _li++) {
            var _ii = _li + _m.pick_scroll;
            if (_ii >= _cnt) break;
            var _ry = _qy + _li * 16;
            var _rh = point_in_rectangle(_mx, _my, _qx, _ry, _qx + _qw, _ry + 15);
            scr_ui_info(_rh, "CLICK TO USE THIS ASSET FOR THE ROOM ((NONE) CLEARS IT); MOUSE WHEEL SCROLLS");
            if (_rh) {
                draw_set_color(make_color_rgb(45, 105, 120));
                draw_rectangle(_qx, _ry, _qx + _qw, _ry + 15, false);
                _hov_name = _items[_ii];
            }
            var _lbl2 = _items[_ii];
            if (_lbl2 == "") { _lbl2 = "(none)"; }
            var _cur = _ro.bmp;
            if (_m.pick_mode == "COLL") { _cur = _ro.coll; }
            if (_m.pick_mode == "MASK") { _cur = _ro.mask; }
            if (_items[_ii] == _cur) {
                draw_set_color(c_lime);
            } else {
                draw_set_color(c_white);
            }
            draw_text_l(_qx + 4, _ry + 2, string_copy(_lbl2, 1, 60));
            if (_rh && _press) {
                if (_m.pick_mode == "BMP") {
                    _ro.bmp = _items[_ii];
                } else if (_m.pick_mode == "MASK") {
                    _ro.mask = _items[_ii];
                } else {
                    _ro.coll = _items[_ii];
                }
                _m.pick_mode = "";
                global.addresses_dirty = true;
            }
        }
        if (_button(_qx, _cvy2 - 26, 70, 16, "CANCEL", make_color_rgb(80, 30, 30), _mx, _my, "CLOSES THE LIST WITHOUT CHANGING THE ROOM")) {
            _m.pick_mode = "";
        }
        // Thumbnail of the hovered bitmap
        if (_m.pick_mode == "BMP" && _hov_name != "") {
            var _hs = scr_room_map_bmp_surf(_hov_name);
            if (_hs != -1) {
                var _pw2 = _qw;
                var _ph2 = _pw2 * 200 / 320;
                var _pyy = _cvy2 - 36 - _ph2;
                draw_set_color(c_black);
                draw_rectangle(_qx, _pyy, _qx + _pw2, _pyy + _ph2, false);
                var _fl2 = gpu_get_tex_filter();
                gpu_set_tex_filter(false);
                draw_surface_stretched(_hs, _qx, _pyy, _pw2, _ph2);
                gpu_set_tex_filter(_fl2);
            }
        }
        return;
    }

    // ── Exits ──
    draw_set_color(_c_lbl);
    draw_text_l(_qx, _qy, "EXITS  (LINE TYPE = DOOR NUMBER)");
    _qy += 16;
    for (var _e = 0; _e < ROOMMAP_EXITS; _e++) {
        var _ex = _ro.exits[_e];
        var _ry = _qy + _e * 18;
        var _rsel = (_m.sel_exit == _e);
        var _rhov = point_in_rectangle(_mx, _my, _qx, _ry, _qx + _qw - 110, _ry + 16);
        scr_ui_info(_rhov, "EXIT D" + string(_e + 2) + ": CLICK TO SELECT/DESELECT IT, THEN CLICK THE PREVIEW TO SET WHERE THE PLAYER ARRIVES");
        if (_rsel) {
            draw_set_color(make_color_rgb(50, 40, 70));
            draw_rectangle(_qx, _ry, _qx + _qw - 110, _ry + 16, false);
        } else if (_rhov) {
            draw_set_color(make_color_rgb(34, 34, 50));
            draw_rectangle(_qx, _ry, _qx + _qw - 110, _ry + 16, false);
        }
        draw_set_color(scr_room_map_type_col(_e + 2));
        draw_text_l(_qx + 4, _ry + 3, "D" + string(_e + 2));
        var _dest = "-";
        if (_ex.to >= 0 && _ex.to < _n) {
            _dest = string(_ex.to) + " " + _rooms[_ex.to].name + "   @ " + string(_ex.ax) + "," + string(_ex.ay);
        }
        draw_set_color(c_white);
        draw_text_l(_qx + 30, _ry + 3, string_copy(_dest, 1, 44));
        if (_rhov && _press) {
            if (_rsel) {
                _m.sel_exit = -1;
            } else {
                _m.sel_exit = _e;
            }
        }
        var _lk_col = make_color_rgb(30, 70, 90);
        if (_m.link_exit == _e) { _lk_col = make_color_rgb(160, 80, 20); }
        if (_button(_qx + _qw - 104, _ry, 56, 16, "LINK", _lk_col, _mx, _my, "LINK D" + string(_e + 2) + ": THEN CLICK THE ROOM ON THE MAP THIS DOOR LEADS TO (CLICK AGAIN TO CANCEL)")) {
            if (_m.link_exit == _e) {
                _m.link_exit = -1;
            } else {
                _m.link_exit = _e;
            }
        }
        if (_button(_qx + _qw - 44, _ry, 44, 16, "CLEAR", make_color_rgb(80, 30, 30), _mx, _my, "UNLINKS EXIT D" + string(_e + 2))) {
            _ex.to = -1;
            if (_m.sel_exit == _e) { _m.sel_exit = -1; }
            global.addresses_dirty = true;
        }
    }
    _qy += ROOMMAP_EXITS * 18 + 8;

    // ── Preview: this room with its lines + spawn, or the arrival point ──
    var _show_room = _m.sel_room;
    var _mode_txt  = "CLICK TO SET THE SPAWN POINT (USED BY _start)";
    var _mark_x    = _ro.sx;
    var _mark_y    = _ro.sy;
    var _ex_sel    = undefined;
    if (_m.sel_exit >= 0) {
        _ex_sel = _ro.exits[_m.sel_exit];
        if (_ex_sel.to >= 0 && _ex_sel.to < _n) {
            _show_room = _ex_sel.to;
            _mode_txt  = "D" + string(_m.sel_exit + 2) + " -> " + _rooms[_ex_sel.to].name + ": CLICK WHERE THE PLAYER ARRIVES";
            _mark_x    = _ex_sel.ax;
            _mark_y    = _ex_sel.ay;
        } else {
            _mode_txt  = "D" + string(_m.sel_exit + 2) + " IS NOT LINKED - PRESS LINK";
            _ex_sel    = undefined;
        }
    }
    draw_set_color(_c_lbl);
    draw_text_l(_qx, _qy, _mode_txt);
    _qy += 16;
    var _pw = _qw;
    var _ph = _pw * 200 / 320;
    var _sc = _pw / 320;
    draw_set_color(c_black);
    draw_rectangle(_qx, _qy, _qx + _pw, _qy + _ph, false);
    var _ps = scr_room_map_bmp_surf(_rooms[_show_room].bmp);
    if (_ps != -1) {
        var _fl3 = gpu_get_tex_filter();
        gpu_set_tex_filter(false);
        draw_surface_stretched(_ps, _qx, _qy, _pw, _ph);
        gpu_set_tex_filter(_fl3);
    }
    // Mask layer of the shown room
    var _mka = scr_sprmask_find_asset(_rooms[_show_room].mask);
    if (!is_undefined(_mka)) {
        scr_sprmask_overlay(_mka.meta);
        draw_surface_stretched(_mka.meta.ov_surf, _qx, _qy, _pw, _ph);
    }
    // Collider lines of the shown room, labelled by type
    var _lc = scr_line_coll_find_asset(_rooms[_show_room].coll);
    if (!is_undefined(_lc) && variable_struct_exists(_lc.meta, "lines")) {
        var _lwx = 1;
        if (_lc.meta.wide_x) { _lwx = 2; }
        for (var _li = 0; _li < array_length(_lc.meta.lines); _li++) {
            var _ln = _lc.meta.lines[_li];
            var _lt = real(_ln.type);
            draw_set_color(scr_room_map_type_col(_lt));
            draw_line_width(_qx + _ln.x1 * _lwx * _sc, _qy + _ln.y1 * _sc, _qx + _ln.x2 * _lwx * _sc, _qy + _ln.y2 * _sc, 2);
            if (_lt >= 2) {
                var _mxl = _qx + (_ln.x1 + _ln.x2) * 0.5 * _lwx * _sc;
                var _myl = _qy + (_ln.y1 + _ln.y2) * 0.5 * _sc;
                draw_set_color(c_black);
                draw_rectangle(_mxl - 9, _myl - 14, _mxl + 9, _myl - 3, false);
                draw_set_color(scr_room_map_type_col(_lt));
                draw_set_halign(fa_center);
                draw_text_l(_mxl, _myl - 15, "D" + string(_lt));
                draw_set_halign(fa_left);
            }
        }
    }
    // Marker
    var _kx = _qx + _mark_x * _sc;
    var _ky = _qy + _mark_y * _sc;
    draw_set_color(c_lime);
    draw_circle(_kx, _ky, 5, true);
    draw_line(_kx - 9, _ky, _kx + 9, _ky);
    draw_line(_kx, _ky - 9, _kx, _ky + 9);
    scr_ui_info(point_in_rectangle(_mx, _my, _qx, _qy, _qx + _pw, _qy + _ph), _mode_txt);
    if (_press && point_in_rectangle(_mx, _my, _qx, _qy, _qx + _pw, _qy + _ph)) {
        var _bx = clamp(round((_mx - _qx) / _sc), 0, 319);
        var _by = clamp(round((_my - _qy) / _sc), 0, 199);
        if (!is_undefined(_ex_sel)) {
            _ex_sel.ax = _bx;
            _ex_sel.ay = _by;
        } else if (_m.sel_exit < 0) {
            _ro.sx = _bx;
            _ro.sy = _by;
        }
        global.addresses_dirty = true;
    }
    draw_set_color(_c_dim);
    draw_text_l(_qx, _qy + _ph + 6, "POINTS ARE BITMAP PIXELS OF THE PLAYER HOTSPOT (SET ON THE ROOMS NODE)");
}

// --------------------------------------------------------------------
// MACRO_ROOMS NODE — draw / click / commit
// --------------------------------------------------------------------
function scr_rooms_node_defaults(_n) {
    var _inst = _n.instructions[0];
    var _def  = ["macro_rooms", "", "", "0", 12, 20, "", 1, 0xC000];
    while (array_length(_inst) < array_length(_def)) {
        array_push(_inst, _def[array_length(_inst)]);
    }
}

function scr_node_draw_macro_rooms(_draw_x) {
    scr_rooms_node_defaults(id);
    var _i   = instructions[0];
    var _lx  = _draw_x + 6;
    var _vx  = _draw_x + 70;
    var _x2  = _draw_x + width - 6;
    var _row = function(_yy, _lbl, _val, _vx1, _vx2, _col) {
        draw_set_font_l(fnt_c64_tiny);
        draw_set_color(make_color_rgb(160, 160, 160));
        scr_node_macro_text_l(_vx1 - 64, _yy, _lbl);
        scr_anim_set_draw_box(_vx1, _yy, _vx2, _yy + 15, _val, _col);
    };
    var _map = string(_i[1]);
    if (_map == "") { _map = "(pick ROOM_MAP)"; }
    var _var = string(_i[2]);
    if (_var == "") { _var = "(pick var)"; }
    _row(y + 28,  "MAP:",   _map, _vx, _x2, c_yellow);
    _row(y + 48,  "ROOM:",  _var, _vx, _x2, make_color_rgb(120, 220, 255));
    _row(y + 68,  "SPRITES:", string(_i[3]), _vx, _x2, c_lime);
    _row(y + 88,  "HOT X:", string(_i[4]), _vx, _vx + 40, c_lime);
    draw_set_color(make_color_rgb(160, 160, 160));
    scr_node_macro_text_l(_vx + 48, y + 88, "Y:");
    scr_anim_set_draw_box(_vx + 66, y + 88, _x2, y + 103, string(_i[5]), c_lime);
    var _hook = string(_i[6]);
    if (_hook == "") { _hook = "(none)"; }
    _row(y + 108, "HOOK:", _hook, _vx, _x2, make_color_rgb(255, 200, 120));
    var _as = "OFF";
    if (real(_i[7]) == 1) { _as = "ON - RUNS _start HERE"; }
    _row(y + 128, "AUTO:", _as, _vx, _x2, c_white);
    _row(y + 148, "MASK RAM:", scr_sprmask_hex(_i[8]), _vx, _x2, make_color_rgb(220, 120, 240));

    var _p = "RM_?_";
    if (string(_i[1]) != "") { _p = scr_room_map_prefix(string(_i[1])); }
    var _rm = scr_room_map_find_asset(string(_i[1]));
    var _cnt = 0;
    if (!is_undefined(_rm)) { _cnt = array_length(_rm.meta.rooms); }
    draw_set_font_l(fnt_c64_tiny);
    draw_set_color(make_color_rgb(140, 140, 140));
    scr_node_macro_text_l(_lx, y + 170, string(_cnt) + " ROOMS");
    draw_set_color(c_yellow);
    scr_node_macro_text_l(_lx, y + 184, _p + "start");
    scr_node_macro_text_l(_lx, y + 198, _p + "door  (A=TYPE)");
    scr_node_macro_text_l(_lx, y + 212, _p + "enter");
}

function scr_node_step_macro_rooms(_draw_x) {
    scr_rooms_node_defaults(id);
    var _vx = _draw_x + 70;
    var _x2 = _draw_x + width - 6;
    var _in = function(_yy, _x1, _x2b) { return point_in_rectangle(mouse_x, mouse_y, _x1, _yy, _x2b, _yy + 15); };

    if (_in(y + 28, _vx, _x2)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "ROOM_ASSET";
        label_picker_scroll     = 0;
        label_picker_target     = id;
        label_picker_index      = 1;
        exit;
    }
    if (_in(y + 48, _vx, _x2)) {
        label_picker_open       = true;
        global.any_picker_open  = true;
        label_picker_prev_depth = depth;
        depth                   = -9999;
        label_picker_mode       = "VAR";
        label_picker_word_only  = false;
        label_picker_byte_only  = false;
        label_picker_tab        = "UV";
        label_picker_scroll     = 0;
        label_picker_list       = [];
        label_picker_target     = id;
        label_picker_index      = 2;
        exit;
    }
    if (_in(y + 68, _vx, _x2))      { scr_anim_set_open_field(id, 3, string(instructions[0][3])); exit; }
    if (_in(y + 88, _vx, _vx + 40)) { scr_anim_set_open_field(id, 4, string(instructions[0][4])); exit; }
    if (_in(y + 88, _vx + 66, _x2)) { scr_anim_set_open_field(id, 5, string(instructions[0][5])); exit; }
    if (_in(y + 108, _vx, _x2))     { scr_anim_set_open_field(id, 6, string(instructions[0][6])); exit; }
    if (_in(y + 148, _vx, _x2)) { scr_anim_set_open_field(id, 8, scr_sprmask_hex(instructions[0][8])); exit; }
    if (_in(y + 128, _vx, _x2)) {
        if (real(instructions[0][7]) == 1) {
            instructions[0][7] = 0;
        } else {
            instructions[0][7] = 1;
        }
        global.addresses_dirty = true;
        exit;
    }
    exit;
}

function scr_rooms_commit(_t, _idx, _input) {
    scr_rooms_node_defaults(_t);
    _input = string_trim(string(_input));
    if (_idx == 3) {
        var _keep = "";
        for (var _i = 1; _i <= string_length(_input); _i++) {
            var _c = string_char_at(_input, _i);
            if ((_c >= "0" && _c <= "7") || _c == ",") { _keep += _c; }
        }
        _t.instructions[0][3] = _keep;
    } else if (_idx == 4 || _idx == 5) {
        var _d = string_digits(_input);
        var _v = 0;
        if (_d != "") { _v = real(_d); }
        _t.instructions[0][_idx] = clamp(_v, 0, 63);
    } else if (_idx == 6) {
        var _h = "";
        for (var _j = 1; _j <= string_length(_input); _j++) {
            var _ch = string_char_at(_input, _j);
            var _o  = ord(_ch);
            if ((_o >= 48 && _o <= 57) || (_o >= 65 && _o <= 90) || (_o >= 97 && _o <= 122) || _ch == "_") { _h += _ch; }
        }
        _t.instructions[0][6] = _h;
    } else if (_idx == 8) {
        var _mr = scr_sprmask_parse_num(_input);
        if (_mr >= 0) { _t.instructions[0][8] = _mr & 0xFFFF; }
    }
    _t.height_dirty = true;
    global.addresses_dirty = true;
}

// --------------------------------------------------------------------
// CODEGEN
// --------------------------------------------------------------------
function scr_rooms_emit(_id, _list) {
    scr_rooms_node_defaults(_id);
    var _inst    = _id.instructions[0];
    var _mapname = string(_inst[1]);
    var _p       = scr_room_map_prefix(_mapname);
    var _skip    = _p + "skip";
    var _rm      = scr_room_map_find_asset(_mapname);
    var _room_addr = scr_resolve_var_addr(string(_inst[2]));

    if (is_undefined(_rm) || _room_addr == 0 || array_length(_rm.meta.rooms) == 0) {
        show_debug_message("MACRO_ROOMS: skipping - map=[" + _mapname + "] room var=[" + string(_inst[2]) + "]");
        return;
    }
    var _rooms = _rm.meta.rooms;
    var _n     = min(array_length(_rooms), 42);   // n * 6 exits must index with X
    var _man   = scr_reu_find_asset(_rm.meta.reu);
    if (!is_undefined(_man) && _man.type == "LOAD_REU") {
        scr_reu_repack(_man);
    }

    // Player sprites
    var _mask = 0;
    var _slot_list = string_split(string(_inst[3]), ",");
    for (var _s = 0; _s < array_length(_slot_list); _s++) {
        var _sd = string_digits(_slot_list[_s]);
        if (_sd != "") { _mask |= (1 << clamp(real(_sd), 0, 7)); }
    }
    var _hx = real(_inst[4]);
    var _hy = real(_inst[5]);
    var _hook = string(_inst[6]);

    // ── Per-room columns ──
    var _t = {
        dma: [], col: [], cb: [], cl: [], ch: [], mb: [], ml: [], mh: [], dl: [], dh: [],
        ll: [], lh: [], dd: [], d18: [], d16: [], bg: [], sxl: [], sxh: [], sy: [], m6: [],
        kh: [], kb: [], kl: [], kx: [], kll: [], klh: []
    };
    var _mask_ram = real(_inst[8]) & 0xFFFF;
    var _coll_lbl = [];
    var _dto = [];
    var _dxl = [];
    var _dxh = [];
    var _dy  = [];
    for (var _r = 0; _r < _n; _r++) {
        var _ro   = _rooms[_r];
        var _bmp  = scr_reu_find_asset(_ro.bmp);
        var _link = undefined;
        if (!is_undefined(_man) && variable_struct_exists(_man, "linked_assets")) {
            for (var _li = 0; _li < array_length(_man.linked_assets); _li++) {
                if (_man.linked_assets[_li].asset_name == _ro.bmp) { _link = _man.linked_assets[_li]; break; }
            }
        }
        var _addr  = 0x4000;
        var _hires = false;
        var _bgc   = 0;
        if (!is_undefined(_bmp) && _bmp.type == "BITMAP") {
            _addr  = real(_bmp.address) & 0xFFFF;
            _hires = scr_asset_bmp_is_hires(_bmp);
            if (!_hires && buffer_exists(_bmp.buffer) && buffer_get_size(_bmp.buffer) >= 10003) {
                _bgc = buffer_peek(_bmp.buffer, 10002, buffer_u8) & 0x0F;
            }
        }
        var _br = scr_bmp_regions(_addr);
        var _has = !is_undefined(_link);
        if (!_has) {
            show_debug_message("MACRO_ROOMS: room " + string(_r) + " bitmap [" + _ro.bmp + "] is not in REU [" + _rm.meta.reu + "] - no fetch");
        }
        var _reu_at = 0;
        if (_has) { _reu_at = real(_link.reu_address); }
        var _len   = (_br.scr_addr + 1000 - _br.bmp_addr) & 0xFFFF;
        var _c_at  = _reu_at + (_br.col_addr - _br.bmp_addr);
        array_push(_t.dma, _has);
        array_push(_t.col, (_has && !_hires));
        array_push(_t.cb, (_c_at >> 16) & 0xFF);
        array_push(_t.cl, _c_at & 0xFF);
        array_push(_t.ch, (_c_at >> 8) & 0xFF);
        array_push(_t.mb, (_reu_at >> 16) & 0xFF);
        array_push(_t.ml, _reu_at & 0xFF);
        array_push(_t.mh, (_reu_at >> 8) & 0xFF);
        array_push(_t.dl, _br.bmp_addr & 0xFF);
        array_push(_t.dh, (_br.bmp_addr >> 8) & 0xFF);
        array_push(_t.ll, _len & 0xFF);
        array_push(_t.lh, (_len >> 8) & 0xFF);
        array_push(_t.dd, 3 - _br.bank);
        var _bmp_off = floor((_br.bmp_addr - _br.bank_base) / 0x2000) & 0x01;
        var _scr_off = floor((_br.scr_addr - _br.bank_base) / 0x0400) & 0x0F;
        array_push(_t.d18, (_scr_off << 4) | (_bmp_off << 3));
        if (_hires) {
            array_push(_t.d16, 0x08);
        } else {
            array_push(_t.d16, 0x18);
        }
        array_push(_t.bg, _bgc);
        var _spx = real(_ro.sx) + 24 - _hx;
        var _spy = real(_ro.sy) + 50 - _hy;
        array_push(_t.sxl, _spx & 0xFF);
        array_push(_t.sxh, (_spx >> 8) & 0x01);
        array_push(_t.sy, _spy & 0xFF);
        array_push(_t.m6, _r * ROOMMAP_EXITS);
        // Sprite mask blob (SPRITE_MASK asset linked in the same REU)
        var _mk = scr_sprmask_find_asset(_ro.mask);
        var _mlink = undefined;
        if (!is_undefined(_mk) && !is_undefined(_man) && variable_struct_exists(_man, "linked_assets")) {
            for (var _li = 0; _li < array_length(_man.linked_assets); _li++) {
                if (_man.linked_assets[_li].asset_name == _ro.mask) { _mlink = _man.linked_assets[_li]; break; }
            }
            if (is_undefined(_mlink)) {
                show_debug_message("MACRO_ROOMS: room " + string(_r) + " mask [" + _ro.mask + "] is not in REU [" + _rm.meta.reu + "] - no mask");
            }
        }
        var _mat = 0;
        var _mln = 0;
        if (!is_undefined(_mlink)) {
            scr_sprmask_flush(_mk);
            _mat = real(_mlink.reu_address);
            _mln = buffer_get_size(_mk.buffer);
        }
        array_push(_t.kh, !is_undefined(_mlink));
        array_push(_t.kb, (_mat >> 16) & 0xFF);
        array_push(_t.kl, _mat & 0xFF);
        array_push(_t.kx, (_mat >> 8) & 0xFF);
        array_push(_t.kll, _mln & 0xFF);
        array_push(_t.klh, (_mln >> 8) & 0xFF);
        var _lc = scr_line_coll_find_asset(_ro.coll);
        if (is_undefined(_lc)) {
            array_push(_coll_lbl, _p + "nocoll");
        } else {
            array_push(_coll_lbl, _ro.coll + "_LINE_LUT");
        }
        for (var _e = 0; _e < ROOMMAP_EXITS; _e++) {
            var _ex = _ro.exits[_e];
            var _to = real(_ex.to);
            if (_to < 0 || _to >= _n) {
                array_push(_dto, 0xFF);
            } else {
                array_push(_dto, _to);
            }
            var _ax = real(_ex.ax) + 24 - _hx;
            var _ay = real(_ex.ay) + 50 - _hy;
            array_push(_dxl, _ax & 0xFF);
            array_push(_dxh, (_ax >> 8) & 0x01);
            array_push(_dy, _ay & 0xFF);
        }
    }

    // ── Inline: optional auto start, then jump over everything ──
    if (real(_inst[7]) == 1) {
        array_push(_list, ["jsr", _p + "start", _id]);
    }
    array_push(_list, ["jmp_abs", _skip, _id]);

    // ── start: enter the current room at its spawn point ──
    array_push(_list, ["label",   _p + "start"]);
    array_push(_list, ["ldx_abs", _room_addr,  _id]);
    array_push(_list, ["lda_abx", _p + "sxl",  _id]);
    array_push(_list, ["sta_lab", _p + "ax",   _id]);
    array_push(_list, ["lda_abx", _p + "sxh",  _id]);
    array_push(_list, ["sta_lab", _p + "axh",  _id]);
    array_push(_list, ["lda_abx", _p + "sy",   _id]);
    array_push(_list, ["sta_lab", _p + "ay",   _id]);
    array_push(_list, ["jmp_abs", _p + "enter", _id]);

    // ── door: A = collider line type (2-7). No exit = RTS, nothing changes ──
    array_push(_list, ["label",   _p + "door"]);
    array_push(_list, ["sec",     0,           _id]);
    array_push(_list, ["sbc_imm", 2,           _id]);
    array_push(_list, ["bcc",     _p + "nodoor", _id]);
    array_push(_list, ["cmp_imm", ROOMMAP_EXITS, _id]);
    array_push(_list, ["bcs",     _p + "nodoor", _id]);
    array_push(_list, ["sta_lab", _p + "tmp",  _id]);
    array_push(_list, ["ldx_abs", _room_addr,  _id]);
    array_push(_list, ["lda_abx", _p + "m6",   _id]);
    array_push(_list, ["clc",     0,           _id]);
    array_push(_list, ["adc_abs", _p + "tmp",  _id]);
    array_push(_list, ["tax",     0,           _id]);
    array_push(_list, ["lda_abx", _p + "dto",  _id]);
    array_push(_list, ["cmp_imm", 0xFF,        _id]);
    array_push(_list, ["beq",     _p + "nodoor", _id]);
    array_push(_list, ["sta_abs", _room_addr,  _id]);
    array_push(_list, ["lda_abx", _p + "dxl",  _id]);
    array_push(_list, ["sta_lab", _p + "ax",   _id]);
    array_push(_list, ["lda_abx", _p + "dxh",  _id]);
    array_push(_list, ["sta_lab", _p + "axh",  _id]);
    array_push(_list, ["lda_abx", _p + "dy",   _id]);
    array_push(_list, ["sta_lab", _p + "ay",   _id]);
    array_push(_list, ["jmp_abs", _p + "enter", _id]);
    array_push(_list, ["label",   _p + "nodoor"]);
    array_push(_list, ["rts",     0,           _id]);

    // ── enter: blank, fetch, show, place the player ──
    array_push(_list, ["label",   _p + "enter"]);
    array_push(_list, ["lda_abs", 0xD011,      _id]);
    array_push(_list, ["and_imm", 0xEF,        _id]);   // blank the screen during the fetch
    array_push(_list, ["sta_abs", 0xD011,      _id]);
    array_push(_list, ["ldx_abs", _room_addr,  _id]);
    array_push(_list, ["lda_abx", _p + "clo",  _id]);   // this room's collider table
    array_push(_list, ["sta_lab", _p + "coll_lo", _id]);
    array_push(_list, ["lda_abx", _p + "chi",  _id]);
    array_push(_list, ["sta_lab", _p + "coll_hi", _id]);
    array_push(_list, ["lda_abx", _p + "dma",  _id]);
    array_push(_list, ["beq",     _p + "nodma", _id]);
    array_push(_list, ["lda_abx", _p + "col",  _id]);
    array_push(_list, ["beq",     _p + "nocol", _id]);
    // Colour block straight to $D800 (1000 bytes)
    array_push(_list, ["lda_abx", _p + "cb",   _id]);
    array_push(_list, ["sta_abs", 0xDF06,      _id]);
    array_push(_list, ["lda_abx", _p + "cl",   _id]);
    array_push(_list, ["sta_abs", 0xDF04,      _id]);
    array_push(_list, ["lda_abx", _p + "ch",   _id]);
    array_push(_list, ["sta_abs", 0xDF05,      _id]);
    array_push(_list, ["lda_imm", 0x00,        _id]);
    array_push(_list, ["sta_abs", 0xDF02,      _id]);
    array_push(_list, ["lda_imm", 0xD8,        _id]);
    array_push(_list, ["sta_abs", 0xDF03,      _id]);
    array_push(_list, ["lda_imm", 0xE8,        _id]);
    array_push(_list, ["sta_abs", 0xDF07,      _id]);
    array_push(_list, ["lda_imm", 0x03,        _id]);
    array_push(_list, ["sta_abs", 0xDF08,      _id]);
    array_push(_list, ["lda_imm", 0x00,        _id]);
    array_push(_list, ["sta_abs", 0xDF0A,      _id]);
    array_push(_list, ["lda_imm", 0x91,        _id]);   // execute, REU -> C64
    array_push(_list, ["sta_abs", 0xDF01,      _id]);
    array_push(_list, ["label",   _p + "nocol"]);
    // Bitmap + screen RAM
    array_push(_list, ["lda_abx", _p + "mb",   _id]);
    array_push(_list, ["sta_abs", 0xDF06,      _id]);
    array_push(_list, ["lda_abx", _p + "ml",   _id]);
    array_push(_list, ["sta_abs", 0xDF04,      _id]);
    array_push(_list, ["lda_abx", _p + "mh",   _id]);
    array_push(_list, ["sta_abs", 0xDF05,      _id]);
    array_push(_list, ["lda_abx", _p + "dl",   _id]);
    array_push(_list, ["sta_abs", 0xDF02,      _id]);
    array_push(_list, ["lda_abx", _p + "dh",   _id]);
    array_push(_list, ["sta_abs", 0xDF03,      _id]);
    array_push(_list, ["lda_abx", _p + "ll",   _id]);
    array_push(_list, ["sta_abs", 0xDF07,      _id]);
    array_push(_list, ["lda_abx", _p + "lh",   _id]);
    array_push(_list, ["sta_abs", 0xDF08,      _id]);
    array_push(_list, ["lda_imm", 0x00,        _id]);
    array_push(_list, ["sta_abs", 0xDF0A,      _id]);
    array_push(_list, ["lda_imm", 0x91,        _id]);
    array_push(_list, ["sta_abs", 0xDF01,      _id]);
    array_push(_list, ["label",   _p + "nodma"]);
    // Sprite mask for this room -> MASK RAM (mask_on tells MACRO_SPR_MASK)
    array_push(_list, ["lda_abx", _p + "kh",   _id]);
    array_push(_list, ["sta_lab", _p + "mask_on", _id]);
    array_push(_list, ["beq",     _p + "nomask", _id]);
    array_push(_list, ["lda_abx", _p + "kb",   _id]);
    array_push(_list, ["sta_abs", 0xDF06,      _id]);
    array_push(_list, ["lda_abx", _p + "kl",   _id]);
    array_push(_list, ["sta_abs", 0xDF04,      _id]);
    array_push(_list, ["lda_abx", _p + "kx",   _id]);
    array_push(_list, ["sta_abs", 0xDF05,      _id]);
    array_push(_list, ["lda_imm", _mask_ram & 0xFF, _id]);
    array_push(_list, ["sta_abs", 0xDF02,      _id]);
    array_push(_list, ["lda_imm", (_mask_ram >> 8) & 0xFF, _id]);
    array_push(_list, ["sta_abs", 0xDF03,      _id]);
    array_push(_list, ["lda_abx", _p + "kll",  _id]);
    array_push(_list, ["sta_abs", 0xDF07,      _id]);
    array_push(_list, ["lda_abx", _p + "klh",  _id]);
    array_push(_list, ["sta_abs", 0xDF08,      _id]);
    array_push(_list, ["lda_imm", 0x00,        _id]);
    array_push(_list, ["sta_abs", 0xDF0A,      _id]);
    array_push(_list, ["lda_imm", 0x91,        _id]);
    array_push(_list, ["sta_abs", 0xDF01,      _id]);
    array_push(_list, ["label",   _p + "nomask"]);
    // VIC bank, memory pointers, mode, background
    array_push(_list, ["lda_abx", _p + "dd",   _id]);
    array_push(_list, ["sta_lab", _p + "tmp",  _id]);
    array_push(_list, ["lda_abs", 0xDD00,      _id]);
    array_push(_list, ["and_imm", 0xFC,        _id]);
    array_push(_list, ["ora_abs", _p + "tmp",  _id]);
    array_push(_list, ["sta_abs", 0xDD00,      _id]);
    array_push(_list, ["lda_abx", _p + "d18",  _id]);
    array_push(_list, ["sta_abs", 0xD018,      _id]);
    array_push(_list, ["lda_abx", _p + "d16",  _id]);
    array_push(_list, ["sta_abs", 0xD016,      _id]);
    array_push(_list, ["lda_abx", _p + "bg",   _id]);
    array_push(_list, ["sta_abs", 0xD021,      _id]);
    // Player sprites to the arrival point
    if (_mask != 0) {
        for (var _sb = 0; _sb < 8; _sb++) {
            if ((_mask & (1 << _sb)) == 0) continue;
            array_push(_list, ["lda_lab", _p + "ax", _id]);
            array_push(_list, ["sta_abs", 0xD000 + _sb * 2, _id]);
            array_push(_list, ["lda_lab", _p + "ay", _id]);
            array_push(_list, ["sta_abs", 0xD001 + _sb * 2, _id]);
        }
        array_push(_list, ["lda_abs", 0xD010,              _id]);
        array_push(_list, ["and_imm", (~_mask) & 0xFF,     _id]);
        array_push(_list, ["sta_lab", _p + "tmp",          _id]);
        array_push(_list, ["lda_lab", _p + "axh",          _id]);
        array_push(_list, ["beq",     _p + "lowx",         _id]);
        array_push(_list, ["lda_lab", _p + "tmp",          _id]);
        array_push(_list, ["ora_imm", _mask,               _id]);
        array_push(_list, ["sta_lab", _p + "tmp",          _id]);
        array_push(_list, ["label",   _p + "lowx"]);
        array_push(_list, ["lda_lab", _p + "tmp",          _id]);
        array_push(_list, ["sta_abs", 0xD010,              _id]);
    }
    if (_hook != "") {
        array_push(_list, ["jsr", _hook, _id]);
    }
    array_push(_list, ["lda_abs", 0xD011, _id]);
    array_push(_list, ["ora_imm", 0x30,   _id]);            // bitmap mode + display back on
    array_push(_list, ["sta_abs", 0xD011, _id]);
    array_push(_list, ["rts",     0,      _id]);

    // ── State ──
    var _state = ["ax", "axh", "ay", "tmp", "coll_lo", "coll_hi", "mask_on"];
    for (var _k = 0; _k < array_length(_state); _k++) {
        array_push(_list, ["label", _p + _state[_k]]);
        array_push(_list, ["byte",  0, _id]);
    }
    array_push(_list, ["label", _p + "nocoll"]);
    array_push(_list, ["byte",  0xFF, _id]);                // empty line table

    // ── Tables ──
    var _emit = function(_lst, _lbl, _vals, _cnt, _tid) {
        array_push(_lst, ["label", _lbl]);
        for (var _v = 0; _v < _cnt; _v++) {
            var _b = _vals[_v];
            if (is_bool(_b)) {
                if (_b) { _b = 1; } else { _b = 0; }
            }
            array_push(_lst, ["byte", _b & 0xFF, _tid]);
        }
    };
    var _names = variable_struct_get_names(_t);
    for (var _k = 0; _k < array_length(_names); _k++) {
        _emit(_list, _p + _names[_k], _t[$ _names[_k]], _n, _id);
    }
    array_push(_list, ["label", _p + "clo"]);
    for (var _r = 0; _r < _n; _r++) {
        array_push(_list, ["byte_lab_lo", _coll_lbl[_r], _id]);
    }
    array_push(_list, ["label", _p + "chi"]);
    for (var _r = 0; _r < _n; _r++) {
        array_push(_list, ["byte_lab_hi", _coll_lbl[_r], _id]);
    }
    _emit(_list, _p + "dto", _dto, _n * ROOMMAP_EXITS, _id);
    _emit(_list, _p + "dxl", _dxl, _n * ROOMMAP_EXITS, _id);
    _emit(_list, _p + "dxh", _dxh, _n * ROOMMAP_EXITS, _id);
    _emit(_list, _p + "dy",  _dy,  _n * ROOMMAP_EXITS, _id);

    array_push(_list, ["label", _skip]);
}

/// Open the actual linked asset using the normal bitmap viewer/editor path.
function scr_room_map_open_bitmap(_name) {
    if (_name == "" || !instance_exists(obj_asset_manager)) return false;
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.type == "BITMAP" && _a.name == _name) {
            scr_asset_inline_editor_close_all();
            _am.viewer_asset = _i;
            _am.viewer_open = true;
            _am.bb_return_asset = -1;
            keyboard_string = "";
            // Do not carry the held second click into the bitmap paint tool.
            mouse_clear(mb_left);
            return true;
        }
    }
    return false;
}


/// ====================================================================
/// MAP_DATA "RLE ROOMS" export (raw_chars == 2)
///
/// The map is a grid of equal rooms, room_w x room_h chars each, read
/// left to right, top to bottom. Each room is emitted as:
///     band          rows that repeat the run list below (1..255)
///     count, char   horizontal runs, summing to exactly room_w
///   ...bands until room_h rows are covered.
/// The asset starts with a word table (lo, hi) - one absolute pointer per
/// room - followed by the room streams. Identical rooms share one stream.
/// This is the room format Saboteur (Durell) uses; any flip-screen engine
/// with a band/run decoder can read it.
/// ====================================================================
function scr_map_rle_rooms_encode(_a) {
    var _out = [];
    var _m   = _a.meta;
    // RLE STREAM maps share every caller of this function (emit, size,
    // memory bar, D64) - only the byte format differs.
    if (real(_m.raw_chars) == 3) {
        return scr_map_rle_stream_encode(_a);
    }
    var _mw  = real(_m.map_w);
    var _mh  = real(_m.map_h);
    var _rw  = real(_m.room_w);
    var _rh  = real(_m.room_h);
    if (_rw < 1 || _rh < 1 || !buffer_exists(_a.buffer)) return _out;
    var _rx_n = _mw div _rw;
    var _ry_n = _mh div _rh;
    var _n    = _rx_n * _ry_n;
    var _cnt  = real(_m.room_count);
    if (_cnt > 0 && _cnt < _n) _n = _cnt;
    if (_n < 1) return _out;

    var _bsz     = buffer_get_size(_a.buffer);
    var _streams = [];   // encoded bytes per unique room
    var _keys    = [];   // string key per unique room, for sharing
    var _room_of = [];   // room index -> unique stream index
    for (var _r = 0; _r < _n; _r++) {
        var _ox = (_r mod _rx_n) * _rw;
        var _oy = (_r div _rx_n) * _rh;
        var _st = [];
        var _y  = 0;
        while (_y < _rh) {
            // band: how many following rows are identical to row _y
            var _band = 1;
            while (_y + _band < _rh && _band < 255) {
                var _same = true;
                for (var _x = 0; _x < _rw; _x++) {
                    var _o1 = (_oy + _y) * _mw + _ox + _x;
                    var _o2 = (_oy + _y + _band) * _mw + _ox + _x;
                    var _c1 = 0;
                    var _c2 = 0;
                    if (_o1 < _bsz) _c1 = buffer_peek(_a.buffer, _o1, buffer_u8);
                    if (_o2 < _bsz) _c2 = buffer_peek(_a.buffer, _o2, buffer_u8);
                    if (_c1 != _c2) { _same = false; break; }
                }
                if (!_same) break;
                _band++;
            }
            array_push(_st, _band);
            var _x = 0;
            while (_x < _rw) {
                var _o  = (_oy + _y) * _mw + _ox + _x;
                var _ch = 0;
                if (_o < _bsz) _ch = buffer_peek(_a.buffer, _o, buffer_u8);
                var _run = 1;
                while (_x + _run < _rw && _run < 255) {
                    var _on = _o + _run;
                    var _cn = 0;
                    if (_on < _bsz) _cn = buffer_peek(_a.buffer, _on, buffer_u8);
                    if (_cn != _ch) break;
                    _run++;
                }
                array_push(_st, _run);
                array_push(_st, _ch);
                _x += _run;
            }
            _y += _band;
        }
        var _key = json_stringify(_st);
        var _found = -1;
        for (var _k = 0; _k < array_length(_keys); _k++) {
            if (_keys[_k] == _key) { _found = _k; break; }
        }
        if (_found == -1) {
            array_push(_keys, _key);
            array_push(_streams, _st);
            _found = array_length(_streams) - 1;
        }
        array_push(_room_of, _found);
    }

    // stream start offsets, after the pointer table
    var _offs = [];
    var _pos  = _n * 2;
    for (var _s = 0; _s < array_length(_streams); _s++) {
        array_push(_offs, _pos);
        _pos += array_length(_streams[_s]);
    }
    for (var _r = 0; _r < _n; _r++) {
        var _abs = real(_a.address) + _offs[_room_of[_r]];
        array_push(_out, _abs & 0xFF);
        array_push(_out, (_abs >> 8) & 0xFF);
    }
    for (var _s = 0; _s < array_length(_streams); _s++) {
        var _st2 = _streams[_s];
        for (var _b = 0; _b < array_length(_st2); _b++) array_push(_out, _st2[_b]);
    }
    return _out;
}


/// ====================================================================
/// MAP_DATA "RLE STREAM" export (raw_chars == 3)
///
/// Rooms are laid out as for RLE ROOMS (room_w x room_h chars, numbered
/// left to right, top to bottom). Emitted:
///     lo table      one byte per room - low byte of its stream address
///     hi table      one byte per room - high byte
///     streams       one per unique room, the room's chars row after row:
///         n, char       n = 1-127: n copies of char
///         $80+n, chars  n = 1-127: the next n chars as they are
///         $80           end of room
/// Identical rooms share one stream. This is the room format Bruce Lee
/// (Datasoft) reads; a split lo / hi table is what its ROOM_DRAW indexes.
///
/// stream_flag_colour (0-7, -1 = off): a cell painted that colour gets
/// bit 7 set on its char - Bruce Lee marks the cells it draws dark that
/// way. With it off the char is emitted as it is (0-255).
/// ====================================================================
function scr_map_rle_stream_encode(_a) {
    var _out = [];
    var _m   = _a.meta;
    var _mw  = real(_m.map_w);
    var _mh  = real(_m.map_h);
    var _rw  = real(_m.room_w);
    var _rh  = real(_m.room_h);
    if (_rw < 1 || _rh < 1) return _out;
    var _gw = real(_m.grid_w);
    if (_gw < _mw) _gw = _mw;
    var _cg = _m.char_grid;
    var _kg = _m.colour_grid;
    var _flag = real(_m.stream_flag_colour);
    var _rx_n = _mw div _rw;
    var _ry_n = _mh div _rh;
    var _n    = _rx_n * _ry_n;
    var _cnt  = real(_m.room_count);
    if (_cnt > 0 && _cnt < _n) _n = _cnt;
    if (_n < 1) return _out;

    var _streams = [];   // encoded bytes per unique room
    var _keys    = [];   // string key per unique room, for sharing
    var _room_of = [];   // room index -> unique stream index
    for (var _r = 0; _r < _n; _r++) {
        var _ox = (_r mod _rx_n) * _rw;
        var _oy = (_r div _rx_n) * _rh;
        // the room's bytes, row after row
        var _cells = [];
        for (var _y = 0; _y < _rh; _y++) {
            for (var _x = 0; _x < _rw; _x++) {
                var _gi = (_oy + _y) * _gw + _ox + _x;
                var _b  = 0;
                if (_gi < array_length(_cg)) _b = _cg[_gi] & 0xFF;
                if (_flag >= 0) {
                    _b = _b & 0x7F;
                    if (_gi < array_length(_kg)) {
                        if ((_kg[_gi] & 0x07) == _flag) _b = _b | 0x80;
                    }
                }
                array_push(_cells, _b);
            }
        }
        // runs of 3+ become n,char; everything else goes in literal blocks
        var _st  = [];
        var _lit = [];
        var _i   = 0;
        var _len = array_length(_cells);
        while (_i <= _len) {
            var _run = 0;
            if (_i < _len) {
                _run = 1;
                while (_i + _run < _len && _run < 127 && _cells[_i + _run] == _cells[_i]) _run++;
            }
            if (_run >= 3 || _i == _len) {
                var _lp = 0;
                while (_lp < array_length(_lit)) {
                    var _ln = min(127, array_length(_lit) - _lp);
                    array_push(_st, 0x80 | _ln);
                    for (var _k = 0; _k < _ln; _k++) array_push(_st, _lit[_lp + _k]);
                    _lp += _ln;
                }
                _lit = [];
                if (_i == _len) break;
                array_push(_st, _run, _cells[_i]);
                _i += _run;
            } else {
                array_push(_lit, _cells[_i]);
                _i++;
            }
        }
        array_push(_st, 0x80);
        var _key = json_stringify(_st);
        var _found = -1;
        for (var _k = 0; _k < array_length(_keys); _k++) {
            if (_keys[_k] == _key) { _found = _k; break; }
        }
        if (_found == -1) {
            array_push(_keys, _key);
            array_push(_streams, _st);
            _found = array_length(_streams) - 1;
        }
        array_push(_room_of, _found);
    }

    // stream start offsets, after the two tables
    var _offs = [];
    var _pos  = _n * 2;
    for (var _s = 0; _s < array_length(_streams); _s++) {
        array_push(_offs, _pos);
        _pos += array_length(_streams[_s]);
    }
    for (var _r = 0; _r < _n; _r++) {
        array_push(_out, (real(_a.address) + _offs[_room_of[_r]]) & 0xFF);
    }
    for (var _r = 0; _r < _n; _r++) {
        array_push(_out, ((real(_a.address) + _offs[_room_of[_r]]) >> 8) & 0xFF);
    }
    for (var _s = 0; _s < array_length(_streams); _s++) {
        var _st2 = _streams[_s];
        for (var _b = 0; _b < array_length(_st2); _b++) array_push(_out, _st2[_b]);
    }
    return _out;
}


/// Bytes a MAP_DATA asset really puts in C64 memory, from its address.
///   RAW CHARS  : the char plane only (map_w * map_h)
///   RLE ROOMS  : the pointer table + room streams (RLE STREAM: tables + streams)
///   FULL MAP   : the whole buffer (char + colour planes)
/// The buffer itself is always three planes, so its size must never be used
/// as the asset's memory extent for the first two modes - doing so claimed
/// up to 3x the map and swallowed everything above it (BOOT trim kept the
/// LOAD_ORG data that sat inside the claimed range).
function scr_map_emit_size(_a) {
    var _mode = 0;
    if (variable_struct_exists(_a.meta, "raw_chars") && is_real(_a.meta.raw_chars)) {
        _mode = real(_a.meta.raw_chars);
    }
    if (_mode == 1) {
        return _a.meta.map_w * _a.meta.map_h;
    }
    if (_mode == 2 || _mode == 3) {
        return array_length(scr_map_rle_rooms_encode(_a));
    }
    if (buffer_exists(_a.buffer)) {
        return buffer_get_size(_a.buffer);
    }
    return 0;
}


/// ====================================================================
/// MAP_DATA OBJECT LAYER (RLE ROOMS maps)
///
/// Objects placed per room on top of the tiles - crates, doors, the
/// helicopter cockpit... Each object is an entry of a BMP_OBJECTS asset
/// (meta.obj_asset). meta.room_objects[room] is an array of
/// [object, row, col] in ROOM cells; the game wants screen cells, so
/// obj_row_off / obj_col_off are added when emitting.
///
/// Emitted as the format Saboteur reads:
///     obj_table_addr : word table, one pointer per room (lo, hi)
///     each list      : count, then count x (object, row, col)
/// Identical lists are stored once, a list that already appears inside
/// emitted data is pointed at, and lists may overlap the tail of the
/// previous one. Lists fill meta.obj_regions in order: [[start, end], ...]
/// (end exclusive) - the first region normally starts right after the
/// table, later ones are spare holes elsewhere in memory.
///
/// Returns [{ addr, bytes[] }, ...] - one chunk per region used plus the
/// table - or [] when the layer is off (no obj_table_addr).
/// ====================================================================
function scr_map_objects_chunks(_a) {
    var _out = [];
    var _m = _a.meta;
    if (real(_m.obj_table_addr) <= 0) return _out;
    var _rw = real(_m.room_w);
    var _rh = real(_m.room_h);
    if (_rw < 1 || _rh < 1) return _out;
    var _n = (real(_m.map_w) div _rw) * (real(_m.map_h) div _rh);
    if (real(_m.room_count) > 0 && real(_m.room_count) < _n) _n = real(_m.room_count);

    // byte string per room
    var _lists = [];
    for (var _r = 0; _r < _n; _r++) {
        var _l = [0];
        if (_r < array_length(_m.room_objects)) {
            var _objs = _m.room_objects[_r];
            _l[0] = array_length(_objs);
            for (var _k = 0; _k < array_length(_objs); _k++) {
                array_push(_l, real(_objs[_k][0]) & 0xFF);
                array_push(_l, (real(_objs[_k][1]) + real(_m.obj_row_off)) & 0xFF);
                array_push(_l, (real(_objs[_k][2]) + real(_m.obj_col_off)) & 0xFF);
            }
        }
        array_push(_lists, _l);
    }

    // longest lists first gives shorter lists the best chance to be found
    var _order = array_create(_n, 0);
    for (var _r = 0; _r < _n; _r++) _order[_r] = _r;
    array_sort(_order, method({ L: _lists }, function(_x, _y) {
        return array_length(L[_y]) - array_length(L[_x]);
    }));

    var _regions = _m.obj_regions;
    var _reg_bytes = [];
    for (var _g = 0; _g < array_length(_regions); _g++) array_push(_reg_bytes, []);
    var _room_addr = array_create(_n, 0);

    for (var _oi = 0; _oi < _n; _oi++) {
        var _r = _order[_oi];
        var _l = _lists[_r];
        var _ll = array_length(_l);
        var _placed = false;
        // 1. already present in any region?
        for (var _g = 0; _g < array_length(_regions) && !_placed; _g++) {
            var _rb = _reg_bytes[_g];
            for (var _p = 0; _p + _ll <= array_length(_rb); _p++) {
                var _same = true;
                for (var _q = 0; _q < _ll; _q++) {
                    if (_rb[_p + _q] != _l[_q]) { _same = false; break; }
                }
                if (_same) {
                    _room_addr[_r] = real(_regions[_g][0]) + _p;
                    _placed = true;
                    break;
                }
            }
        }
        // 2. append (overlapping the region's tail where it matches)
        for (var _g = 0; _g < array_length(_regions) && !_placed; _g++) {
            var _rb = _reg_bytes[_g];
            var _cap = real(_regions[_g][1]) - real(_regions[_g][0]);
            var _ov = 0;
            for (var _o = min(_ll - 1, array_length(_rb)); _o > 0; _o--) {
                var _ok = true;
                for (var _q = 0; _q < _o; _q++) {
                    if (_rb[array_length(_rb) - _o + _q] != _l[_q]) { _ok = false; break; }
                }
                if (_ok) { _ov = _o; break; }
            }
            if (array_length(_rb) - _ov + _ll <= _cap) {
                _room_addr[_r] = real(_regions[_g][0]) + array_length(_rb) - _ov;
                for (var _q = _ov; _q < _ll; _q++) array_push(_rb, _l[_q]);
                _placed = true;
            }
        }
        // 3. no room left: spill past the last region (the memory bar
        //    shows the overlap as a conflict)
        if (!_placed) {
            var _g = array_length(_regions) - 1;
            var _rb = _reg_bytes[_g];
            _room_addr[_r] = real(_regions[_g][0]) + array_length(_rb);
            for (var _q = 0; _q < _ll; _q++) array_push(_rb, _l[_q]);
        }
    }

    var _tbl = [];
    for (var _r = 0; _r < _n; _r++) {
        array_push(_tbl, _room_addr[_r] & 0xFF);
        array_push(_tbl, (_room_addr[_r] >> 8) & 0xFF);
    }
    array_push(_out, { addr: real(_m.obj_table_addr), bytes: _tbl });
    for (var _g = 0; _g < array_length(_regions); _g++) {
        if (array_length(_reg_bytes[_g]) > 0) {
            array_push(_out, { addr: real(_regions[_g][0]), bytes: _reg_bytes[_g] });
        }
    }
    return _out;
}

/// The BMP_OBJECTS asset named by meta.obj_asset, or noone.
function scr_map_objects_asset(_a) {
    if (string(_a.meta.obj_asset) == "") return noone;
    if (!instance_exists(obj_asset_manager)) return noone;
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _b = ds_list_find_value(_am.asset_list, _i);
        if (_b.type == "BMP_OBJECTS" && _b.name == _a.meta.obj_asset) return _b;
    }
    return noone;
}


/// ====================================================================
/// PICKUP_TABLE asset
///
/// A per-room list of pickups (lanterns, coins, keys...) the game walks,
/// generated from a room map (meta.pick.map, RLE ROOMS / RLE STREAM layout:
/// room_w x room_h cells, rooms left to right, top to bottom).
///
/// meta.pick:
///   map     name of the MAP_DATA it reads
///   auto    true = entries follow the map (a cell with a pickup tile is an
///           entry; existing entries keep their settings, removed cells drop)
///   tiles   pickup tile numbers (bit 7 ignored)
///   repl    [[tile, replacement], ...] - default replacement per tile
///   fields  entry layout, in order: "FLAG" "REPL" "X" "Y" "TILE" "ROOM"
///   flag    value written for FLAG        x_off / y_off  added to X / Y
///   index   0 = 2-byte address per room (lo, hi)   1 = all lo, then all hi
///           2 = none (one list after another)
///   term    list end byte (-1 = count byte before each list instead)
///   empty   bytes written for a room with no pickups ([] = none)
///   rooms   [room][entry] = { x, y, tile, repl, on }  (on = emitted)
///   orig    the rooms as first set up - RESTORE goes back to them
///
/// Emitted at the asset address: the index, then each room's list. Labels
/// <NAME>_LO / <NAME>_HI mark the index (for lda NAME_LO,x / NAME_HI,x).
/// ====================================================================
function scr_pickup_default() {
    return {
        map: "", auto: true, tiles: [], repl: [],
        fields: ["FLAG", "REPL", "X", "Y"], flag: 1, x_off: 0, y_off: 0,
        index: 0, term: 255, empty: [], rooms: [], orig: []
    };
}

function scr_pickup_map(_a) {
    var _pk = _a.meta.pick;
    for (var _i = 0; _i < ds_list_size(obj_asset_manager.asset_list); _i++) {
        var _m = ds_list_find_value(obj_asset_manager.asset_list, _i);
        if (_m.type == "MAP_DATA" && _m.name == _pk.map) return _m;
    }
    return noone;
}

/// Room count and layout of the linked map: [rooms, rooms across, room_w, room_h, grid_w]
function scr_pickup_map_shape(_map) {
    var _m  = _map.meta;
    var _rw = max(1, real(_m.room_w));
    var _rh = max(1, real(_m.room_h));
    var _gw = max(real(_m.map_w), real(_m.grid_w));
    var _rx = max(1, real(_m.map_w) div _rw);
    var _n  = _rx * max(1, real(_m.map_h) div _rh);
    if (real(_m.room_count) > 0 && real(_m.room_count) < _n) _n = real(_m.room_count);
    return [_n, _rx, _rw, _rh, _gw];
}

function scr_pickup_default_repl(_pk, _tile) {
    for (var _i = 0; _i < array_length(_pk.repl); _i++) {
        if ((real(_pk.repl[_i][0]) & 0x7F) == _tile) return real(_pk.repl[_i][1]) & 0xFF;
    }
    return 0;
}

/// AUTO: rebuild the entries from the map. Returns true when they changed.
function scr_pickup_sync(_a) {
    var _pk = _a.meta.pick;
    if (!_pk.auto) return false;
    var _map = scr_pickup_map(_a);
    if (_map == noone) return false;
    var _sh = scr_pickup_map_shape(_map);
    var _cg = _map.meta.char_grid;
    var _old_key = json_stringify(_pk.rooms);
    var _new = [];
    for (var _r = 0; _r < _sh[0]; _r++) {
        var _old = [];
        if (_r < array_length(_pk.rooms)) _old = _pk.rooms[_r];
        var _ox  = (_r mod _sh[1]) * _sh[2];
        var _oy  = (_r div _sh[1]) * _sh[3];
        var _lst = [];
        for (var _y = 0; _y < _sh[3]; _y++) {
            for (var _x = 0; _x < _sh[2]; _x++) {
                var _gi = (_oy + _y) * _sh[4] + _ox + _x;
                if (_gi >= array_length(_cg)) continue;
                var _t = real(_cg[_gi]) & 0x7F;
                var _is = false;
                for (var _k = 0; _k < array_length(_pk.tiles); _k++) {
                    if ((real(_pk.tiles[_k]) & 0x7F) == _t) { _is = true; break; }
                }
                if (!_is) continue;
                var _e = undefined;
                for (var _k = 0; _k < array_length(_old); _k++) {
                    if (real(_old[_k].x) == _x && real(_old[_k].y) == _y) { _e = _old[_k]; break; }
                }
                if (is_undefined(_e)) {
                    _e = { x: _x, y: _y, tile: _t, repl: scr_pickup_default_repl(_pk, _t), on: true };
                } else {
                    _e.tile = _t;
                }
                array_push(_lst, _e);
            }
        }
        array_push(_new, _lst);
    }
    _pk.rooms = _new;
    return json_stringify(_pk.rooms) != _old_key;
}

/// The bytes this table emits from its address.
function scr_pickup_encode(_a) {
    var _pk = _a.meta.pick;
    var _n  = array_length(_pk.rooms);
    var _lists = [];
    for (var _r = 0; _r < _n; _r++) {
        var _b = [];
        var _cnt = 0;
        var _ents = _pk.rooms[_r];
        for (var _i = 0; _i < array_length(_ents); _i++) {
            var _e = _ents[_i];
            if (!_e.on) continue;
            _cnt++;
            for (var _f = 0; _f < array_length(_pk.fields); _f++) {
                switch (_pk.fields[_f]) {
                    case "FLAG": array_push(_b, real(_pk.flag) & 0xFF); break;
                    case "REPL": array_push(_b, real(_e.repl) & 0xFF); break;
                    case "X":    array_push(_b, (real(_e.x) + real(_pk.x_off)) & 0xFF); break;
                    case "Y":    array_push(_b, (real(_e.y) + real(_pk.y_off)) & 0xFF); break;
                    case "TILE": array_push(_b, real(_e.tile) & 0xFF); break;
                    case "ROOM": array_push(_b, _r & 0xFF); break;
                }
            }
        }
        if (_cnt == 0) {
            for (var _i = 0; _i < array_length(_pk.empty); _i++) array_push(_b, real(_pk.empty[_i]) & 0xFF);
        }
        if (real(_pk.term) >= 0) {
            array_push(_b, real(_pk.term) & 0xFF);
        } else {
            array_insert(_b, 0, _cnt & 0xFF);
        }
        array_push(_lists, _b);
    }
    var _out = [];
    var _ix  = real(_pk.index);
    var _pos = real(_a.address);
    if (_ix != 2) _pos += _n * 2;
    var _ptr = [];
    for (var _r = 0; _r < _n; _r++) {
        array_push(_ptr, _pos);
        _pos += array_length(_lists[_r]);
    }
    if (_ix == 0) {
        for (var _r = 0; _r < _n; _r++) array_push(_out, _ptr[_r] & 0xFF, (_ptr[_r] >> 8) & 0xFF);
    } else if (_ix == 1) {
        for (var _r = 0; _r < _n; _r++) array_push(_out, _ptr[_r] & 0xFF);
        for (var _r = 0; _r < _n; _r++) array_push(_out, (_ptr[_r] >> 8) & 0xFF);
    }
    for (var _r = 0; _r < _n; _r++) {
        var _b = _lists[_r];
        for (var _i = 0; _i < array_length(_b); _i++) array_push(_out, _b[_i]);
    }
    return _out;
}

/// Offset of <NAME>_HI from the asset address.
function scr_pickup_hi_offset(_a) {
    var _pk = _a.meta.pick;
    if (real(_pk.index) == 0) return 1;
    if (real(_pk.index) == 1) return array_length(_pk.rooms);
    return 0;
}

function scr_pickup_undo_push(_a) {
    array_push(_a.meta.pick_undo, json_stringify(_a.meta.pick.rooms));
    if (array_length(_a.meta.pick_undo) > 50) array_delete(_a.meta.pick_undo, 0, 1);
}

function scr_pickup_undo(_a) {
    var _u = _a.meta.pick_undo;
    if (array_length(_u) == 0) return;
    _a.meta.pick.rooms = json_parse(_u[array_length(_u) - 1]);
    array_delete(_u, array_length(_u) - 1, 1);
    _a.meta.pick.auto = false;   // keep the undone state - AUTO would re-derive it
    _a.meta.is_dirty = true;
    global.addresses_dirty = true;
}

function scr_pickup_restore(_a) {
    if (array_length(_a.meta.pick.orig) == 0) return;
    scr_pickup_undo_push(_a);
    _a.meta.pick.rooms = json_parse(json_stringify(_a.meta.pick.orig));
    _a.meta.is_dirty = true;
    global.addresses_dirty = true;
}

/// PICKUP_TABLE editor (asset viewer body). Laid out in four parts:
///   toolbar             MAP / AUTO / UNDO / RESTORE
///   SETTINGS  (left)    tiles, replacement per tile, entry layout, index...
///   ROOMS     (middle)  one button per room with its entry count
///   ENTRIES   (right)   the room's entries, scrollable (mouse wheel)
///   EMITTED BYTES       along the bottom
function scr_pickup_editor(_a, _x1, _y1, _x2, _y2, _mx, _my) {
    var _pk = _a.meta.pick;
    if (scr_pickup_sync(_a)) {
        _a.meta.is_dirty = true;
        global.addresses_dirty = true;
    }
    var _bh  = 24;      // button height
    var _gap = 8;
    var _bytes = scr_pickup_encode(_a);
    draw_set_font_l(fnt_c64_tiny);

    // ---- toolbar ----
    var _tx = _x1;
    var _ty = _y1 + 4;
    var _mlbl = "MAP: " + _pk.map;
    if (_pk.map == "") _mlbl = "MAP: (NONE)";
    scr_ui_info(point_in_rectangle(_mx, _my, _tx, _ty, _tx + 260, _ty + _bh), "MAP: CLICK TO CYCLE TO THE NEXT MAP_DATA ASSET THIS TABLE READS ITS PICKUPS FROM");
    if (scr_mrp_button(_tx, _ty, _tx + 260, _ty + _bh, _mlbl, false, _mx, _my) == 1) {
        var _names = [];
        for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
            var _m = ds_list_find_value(asset_list, _i);
            if (_m.type == "MAP_DATA") array_push(_names, _m.name);
        }
        if (array_length(_names) > 0) {
            var _at = -1;
            for (var _i = 0; _i < array_length(_names); _i++) {
                if (_names[_i] == _pk.map) { _at = _i; break; }
            }
            scr_pickup_undo_push(_a);
            _pk.map = _names[(_at + 1) mod array_length(_names)];
            _a.meta.is_dirty = true;
        }
    }
    _tx += 260 + _gap;
    var _alb = "AUTO: OFF";
    if (_pk.auto) _alb = "AUTO: ON (FOLLOWS MAP)";
    scr_ui_info(point_in_rectangle(_mx, _my, _tx, _ty, _tx + 200, _ty + _bh), "AUTO: ON REBUILDS EVERY ROOM'S ENTRIES FROM PICKUP TILES IN THE MAP; OFF LETS YOU EDIT BY HAND");
    if (scr_mrp_button(_tx, _ty, _tx + 200, _ty + _bh, _alb, _pk.auto, _mx, _my) == 1) {
        scr_pickup_undo_push(_a);
        _pk.auto = !_pk.auto;
        _a.meta.is_dirty = true;
        global.addresses_dirty = true;
    }
    _tx += 200 + _gap;
    var _ul = "UNDO (" + string(array_length(_a.meta.pick_undo)) + ")";
    scr_ui_info(point_in_rectangle(_mx, _my, _tx, _ty, _tx + 110, _ty + _bh), "UNDO (CTRL+Z): TAKES BACK THE LAST ENTRY CHANGE AND TURNS AUTO OFF SO IT STICKS");
    if (scr_mrp_button(_tx, _ty, _tx + 110, _ty + _bh, _ul, false, _mx, _my) == 1
        || (keyboard_check(vk_control) && keyboard_check_pressed(ord("Z")))) {
        scr_pickup_undo(_a);
    }
    _tx += 110 + _gap;
    if (array_length(_pk.orig) > 0) {
        scr_ui_info(point_in_rectangle(_mx, _my, _tx, _ty, _tx + 160, _ty + _bh), "RESTORE ORIGINAL: PUTS BACK THE ENTRIES AS FIRST IMPORTED AND TURNS AUTO OFF (UNDOABLE)");
        if (scr_mrp_button(_tx, _ty, _tx + 160, _ty + _bh, "RESTORE ORIGINAL", false, _mx, _my) == 1) {
            scr_pickup_restore(_a);
            _pk.auto = false;
        }
    }

    var _top = _ty + _bh + 18;
    var _bot = _y2 - 120;            // bytes box below
    var _lh  = 22;                   // settings line height

    // ---- SETTINGS (left column) ----
    var _sx = _x1;
    var _sy = _top;
    draw_set_color(c_yellow);
    draw_text(_sx, _sy - scr_lang_lift(), "SETTINGS");
    _sy += _lh;
    var _hx = function(_v) { return "$" + string_upper(decimal_to_hex(real(_v) & 0xFF)); };
    var _rows = [];
    var _t = "";
    for (var _i = 0; _i < array_length(_pk.tiles); _i++) _t += _hx(_pk.tiles[_i]) + " ";
    array_push(_rows, ["PICKUP TILES", _t]);
    _t = "";
    for (var _i = 0; _i < array_length(_pk.repl); _i++) _t += _hx(_pk.repl[_i][0]) + ">" + _hx(_pk.repl[_i][1]) + "  ";
    array_push(_rows, ["TAKEN TILE", _t]);
    _t = "";
    for (var _i = 0; _i < array_length(_pk.fields); _i++) _t += _pk.fields[_i] + " ";
    array_push(_rows, ["ENTRY", _t]);
    array_push(_rows, ["OFFSETS", "X+" + string(_pk.x_off) + "   Y+" + string(_pk.y_off)]);
    array_push(_rows, ["FLAG VALUE", _hx(_pk.flag)]);
    var _ixn = ["ADDRESS PER ROOM", "LO TABLE, HI TABLE", "NONE"];
    array_push(_rows, ["ROOM INDEX", _ixn[clamp(real(_pk.index), 0, 2)]]);
    if (real(_pk.term) >= 0) {
        array_push(_rows, ["LIST END", _hx(_pk.term)]);
    } else {
        array_push(_rows, ["LIST END", "COUNT BYTE FIRST"]);
    }
    _t = "";
    for (var _i = 0; _i < array_length(_pk.empty); _i++) _t += _hx(_pk.empty[_i]) + " ";
    if (_t == "") _t = "NOTHING";
    array_push(_rows, ["EMPTY ROOM", _t]);
    array_push(_rows, ["SIZE", string(array_length(_bytes)) + " BYTES"]);
    array_push(_rows, ["LABELS", _a.name + "_LO"]);
    array_push(_rows, ["", _a.name + "_HI"]);
    for (var _i = 0; _i < array_length(_rows); _i++) {
        draw_set_color(c_gray);
        draw_text(_sx, _sy - scr_lang_lift(), _rows[_i][0]);
        draw_set_color(c_white);
        draw_text(_sx + 110, _sy - scr_lang_lift(), _rows[_i][1]);
        _sy += _lh;
    }

    // ---- ROOMS (middle column) ----
    var _n = array_length(_pk.rooms);
    var _rx = _x1 + 400;
    var _ry = _top;
    draw_set_color(c_yellow);
    draw_text(_rx, _ry - scr_lang_lift(), "ROOMS");
    _ry += _lh;
    if (_n == 0) {
        draw_set_color(c_orange);
        draw_text(_rx, _ry - scr_lang_lift(), "LINK A ROOM MAP (RLE ROOMS / RLE STREAM) AND TURN AUTO ON");
        return;
    }
    pickup_room = clamp(pickup_room, 0, _n - 1);
    var _rbh  = 20;
    var _rcols = max(1, ceil(_n / max(1, floor((_bot - _ry) / (_rbh + 4)))));
    var _rper  = ceil(_n / _rcols);
    for (var _r = 0; _r < _n; _r++) {
        var _bx = _rx + (_r div _rper) * 128;
        var _by = _ry + (_r mod _rper) * (_rbh + 4);
        var _on = 0;
        for (var _k = 0; _k < array_length(_pk.rooms[_r]); _k++) if (_pk.rooms[_r][_k].on) _on++;
        scr_ui_info(point_in_rectangle(_mx, _my, _bx, _by, _bx + 120, _by + _rbh), "ROOM " + string(_r) + ": CLICK TO SHOW ITS ENTRIES; THE NUMBER IS HOW MANY ARE ON (EMITTED)");
        if (scr_mrp_button(_bx, _by, _bx + 120, _by + _rbh, "ROOM " + string(_r) + "   " + string(_on), _r == pickup_room, _mx, _my) == 1) {
            pickup_room = _r;
            pickup_scroll = 0;
        }
    }

    // ---- ENTRIES (right) ----
    var _ex = _rx + _rcols * 128 + 30;
    var _ey = _top;
    draw_set_color(c_yellow);
    draw_text(_ex, _ey - scr_lang_lift(), "ROOM " + string(pickup_room) + " ENTRIES    (L-CLICK +1 / R-CLICK -1)");
    _ey += _lh;
    var _cw   = 70;                                  // column width
    var _hdr  = ["X", "Y", "TILE", "TAKEN", "EMIT"];
    draw_set_color(c_gray);
    draw_set_halign(fa_center);
    for (var _k = 0; _k < 5; _k++) draw_text(_ex + _k * (_cw + 6) + _cw * 0.5, _ey - scr_lang_lift(), _hdr[_k]);
    draw_set_halign(fa_left);
    _ey += _lh;
    var _ents = _pk.rooms[pickup_room];
    var _rowh = _bh + 4;
    var _vis  = max(1, floor((_bot - _ey - _rowh - 8) / _rowh));
    if (point_in_rectangle(_mx, _my, _ex, _ey, _x2, _bot)) {
        scr_ui_info(true, "ENTRIES: THIS ROOM'S PICKUPS; MOUSE WHEEL SCROLLS THE LIST");
        if (mouse_wheel_up())   pickup_scroll--;
        if (mouse_wheel_down()) pickup_scroll++;
    }
    pickup_scroll = clamp(pickup_scroll, 0, max(0, array_length(_ents) - _vis));
    var _del = -1;
    var _chg = false;
    for (var _i = pickup_scroll; _i < min(array_length(_ents), pickup_scroll + _vis); _i++) {
        var _e = _ents[_i];
        var _vals = [real(_e.x), real(_e.y), real(_e.tile), real(_e.repl)];
        for (var _k = 0; _k < 4; _k++) {
            var _bx = _ex + _k * (_cw + 6);
            var _lbl = string(_vals[_k]);
            if (_k >= 2) _lbl = _hx(_vals[_k]);
            var _hit = scr_mrp_button(_bx, _ey, _bx + _cw, _ey + _bh, _lbl, false, _mx, _my);
            // X / Y / TILE come from the map in AUTO; TAKEN is always editable
            var _ok = (_k == 3) || !_pk.auto;
            if (point_in_rectangle(_mx, _my, _bx, _ey, _bx + _cw, _ey + _bh)) {
                if (_k == 3) {
                    scr_ui_info(true, "TAKEN: TILE PUT IN THE MAP ONCE PICKED UP; L-CLICK +1, R-CLICK -1");
                } else if (!_ok) {
                    scr_ui_info(true, _hdr[_k] + ": TAKEN FROM THE MAP WHILE AUTO IS ON; TURN AUTO OFF TO EDIT");
                } else if (_k == 2) {
                    scr_ui_info(true, "TILE: THE PICKUP'S CHARACTER; L-CLICK +1, R-CLICK -1");
                } else {
                    scr_ui_info(true, _hdr[_k] + ": CELL " + _hdr[_k] + " IN THE ROOM (0-255); L-CLICK +1, R-CLICK -1");
                }
            }
            if (_hit != 0 && _ok) {
                scr_pickup_undo_push(_a);
                var _d = 1;
                if (_hit == 2) _d = -1;
                if (_k == 0) _e.x = clamp(real(_e.x) + _d, 0, 255);
                if (_k == 1) _e.y = clamp(real(_e.y) + _d, 0, 255);
                if (_k == 2) _e.tile = (real(_e.tile) + _d + 256) & 0xFF;
                if (_k == 3) _e.repl = (real(_e.repl) + _d + 256) & 0xFF;
                _chg = true;
            }
        }
        var _bx4 = _ex + 4 * (_cw + 6);
        var _onl = "OFF";
        if (_e.on) _onl = "ON";
        scr_ui_info(point_in_rectangle(_mx, _my, _bx4, _ey, _bx4 + _cw, _ey + _bh), "EMIT: CLICK TO TOGGLE WHETHER THIS ENTRY IS WRITTEN TO THE TABLE");
        if (scr_mrp_button(_bx4, _ey, _bx4 + _cw, _ey + _bh, _onl, _e.on, _mx, _my) == 1) {
            scr_pickup_undo_push(_a);
            _e.on = !_e.on;
            _chg = true;
        }
        if (!_pk.auto) {
            var _bx5 = _bx4 + _cw + 6;
            scr_ui_info(point_in_rectangle(_mx, _my, _bx5, _ey, _bx5 + _bh, _ey + _bh), "X: DELETE THIS ENTRY (UNDOABLE)");
            if (scr_mrp_button(_bx5, _ey, _bx5 + _bh, _ey + _bh, "X", false, _mx, _my) == 1) _del = _i;
        }
        _ey += _rowh;
    }
    if (array_length(_ents) > _vis) {
        draw_set_color(c_gray);
        draw_text(_ex, _ey + 2 - scr_lang_lift(), string(pickup_scroll + 1) + "-" + string(min(array_length(_ents), pickup_scroll + _vis))
            + " OF " + string(array_length(_ents)) + "  (WHEEL TO SCROLL)");
        _ey += _lh;
    }
    if (!_pk.auto) {
        scr_ui_info(point_in_rectangle(_mx, _my, _ex, _ey + 4, _ex + 120, _ey + 4 + _bh), "+ ENTRY: ADDS AN ENTRY AT 0,0 USING THE FIRST PICKUP TILE, SWITCHED ON");
        if (scr_mrp_button(_ex, _ey + 4, _ex + 120, _ey + 4 + _bh, "+ ENTRY", false, _mx, _my) == 1) {
            scr_pickup_undo_push(_a);
            var _t0 = 0;
            if (array_length(_pk.tiles) > 0) _t0 = real(_pk.tiles[0]) & 0x7F;
            array_push(_ents, { x: 0, y: 0, tile: _t0, repl: scr_pickup_default_repl(_pk, _t0), on: true });
            _chg = true;
        }
    }
    if (_del >= 0) {
        scr_pickup_undo_push(_a);
        array_delete(_ents, _del, 1);
        _chg = true;
    }
    if (_chg) {
        _a.meta.is_dirty = true;
        global.addresses_dirty = true;
    }

    // ---- ROOM PREVIEW (right) ----
    var _px1 = _ex + 5 * (_cw + 6) + _bh + 40;
    scr_pickup_room_preview(_a, pickup_room, _px1, _top, _x2, _bot, _mx, _my);

    // ---- EMITTED BYTES (bottom box) ----
    var _bx1 = _x1;
    var _by1 = _bot + 10;
    draw_set_color(make_color_rgb(12, 12, 20));
    draw_rectangle(_bx1, _by1, _x2, _y2, false);
    draw_set_color(make_color_rgb(60, 60, 80));
    draw_rectangle(_bx1, _by1, _x2, _y2, true);
    draw_set_color(c_yellow);
    var _a1 = real(_a.address);
    draw_text(_bx1 + 8, _by1 + 6 - scr_lang_lift(), "EMITTED BYTES  $" + string_upper(decimal_to_hex(_a1)) + "-$"
        + string_upper(decimal_to_hex(_a1 + max(0, array_length(_bytes) - 1))));
    var _cols = max(8, floor((_x2 - _bx1 - 16) / 26));
    var _ly = _by1 + 24;
    var _hxs = "";
    draw_set_color(c_aqua);
    for (var _i = 0; _i < array_length(_bytes); _i++) {
        _hxs += string_upper(decimal_to_hex(_bytes[_i])) + " ";
        if ((_i + 1) mod _cols == 0) {
            if (_ly + 12 < _y2) draw_text(_bx1 + 8, _ly - scr_lang_lift(), _hxs);
            _hxs = "";
            _ly += 14;
        }
    }
    if (_hxs != "" && _ly + 12 < _y2) draw_text(_bx1 + 8, _ly - scr_lang_lift(), _hxs);
}

/// PICKUP_TABLE room preview: the linked map's room (its charset and colour
/// bands, rows doubled with the map's Y x2) with every entry marked.
///   ALL           the room, entries outlined
///   HIGHLIGHT     the room dimmed, entries at full brightness
///   PICKUPS ONLY  just the entry cells
/// Outline: yellow = emitted, grey = OFF.
function scr_pickup_room_preview(_a, _r, _x1, _y1, _x2, _y2, _mx, _my) {
    var _pk  = _a.meta.pick;
    var _map = scr_pickup_map(_a);
    if (_map == noone || _x2 - _x1 < 120 || _y2 - _y1 < 80) return;
    var _mm  = _map.meta;
    var _sh  = scr_pickup_map_shape(_map);
    var _gw  = real(_mm.grid_w);
    var _gh  = real(_mm.grid_h);

    draw_set_font_l(fnt_c64_tiny);
    draw_set_color(c_yellow);
    draw_text(_x1, _y1 - scr_lang_lift(), "ROOM " + string(_r) + "  (" + _map.name + ")");

    // charset the map draws with
    var _chr = noone;
    for (var _i = 0; _i < ds_list_size(asset_list); _i++) {
        var _ca = ds_list_find_value(asset_list, _i);
        if (_ca.type == "CHAR_SET" && _ca.name == _mm.chr_asset) { _chr = _ca; break; }
    }
    var _ok = false;
    if (_chr != noone && buffer_exists(_chr.buffer)) {
        var _c1 = real(_mm.map_mc_col1);
        if (_c1 < 0) _c1 = 1;
        var _c2 = real(_mm.map_mc_col2);
        if (_c2 < 0) _c2 = 2;
        var _bg = real(_mm.map_mc_bg);
        if (_bg < 0) _bg = 0;
        _ok = scr_map_cache_update(map_view_cache, _map, _chr, {
            gw : _gw, gh : _gh, bg : _bg, mixed : real(_mm.map_mixed), ecm : 0,
            ecm_cols : [0, 0, 0, 0], col1 : _c1, col2 : _c2,
            vc0 : 0, vr0 : 0, vc1 : _gw, vr1 : _gh
        });
    }

    // layout: scale to the area, mode buttons underneath
    var _ysc = 1;
    if (_mm.view_y2) _ysc = 2;
    var _pw  = _sh[2] * 8;
    var _ph  = _sh[3] * 8 * _ysc;
    var _top = _y1 + 22;
    var _sc  = min((_x2 - _x1) / _pw, (_y2 - _top - 40) / _ph);
    _sc = max(0.25, _sc);
    var _vw  = _pw * _sc;
    var _vh  = _ph * _sc;
    var _ox  = (_r mod _sh[1]) * _sh[2] * 8;
    var _oy  = (_r div _sh[1]) * _sh[3] * 8;
    var _cw  = 8 * _sc;
    var _ch  = 8 * _sc * _ysc;

    draw_set_color(c_black);
    draw_rectangle(_x1, _top, _x1 + _vw, _top + _vh, false);
    var _tf = gpu_get_tex_filter();
    gpu_set_tex_filter(false);
    if (_ok && surface_exists(map_view_cache.surf)) {
        if (pickup_view != 2) {
            draw_surface_part_ext(map_view_cache.surf, _ox, _oy, _pw, _sh[3] * 8, _x1, _top, _sc, _sc * _ysc, c_white, 1);
        }
        if (pickup_view == 1) {
            draw_set_alpha(0.7);
            draw_set_color(c_black);
            draw_rectangle(_x1, _top, _x1 + _vw, _top + _vh, false);
            draw_set_alpha(1);
        }
        if (pickup_view != 0) {
            var _ents = _pk.rooms[_r];
            for (var _i = 0; _i < array_length(_ents); _i++) {
                var _e = _ents[_i];
                draw_surface_part_ext(map_view_cache.surf, _ox + real(_e.x) * 8, _oy + real(_e.y) * 8, 8, 8,
                    _x1 + real(_e.x) * _cw, _top + real(_e.y) * _ch, _sc, _sc * _ysc, c_white, 1);
            }
        }
    }
    gpu_set_tex_filter(_tf);
    // entry outlines
    var _ents2 = _pk.rooms[_r];
    for (var _i = 0; _i < array_length(_ents2); _i++) {
        var _e = _ents2[_i];
        var _ex1 = _x1 + real(_e.x) * _cw;
        var _ey1 = _top + real(_e.y) * _ch;
        if (_e.on) { draw_set_color(c_yellow); } else { draw_set_color(c_gray); }
        draw_rectangle(_ex1 - 1, _ey1 - 1, _ex1 + _cw, _ey1 + _ch, true);
    }
    draw_set_color(make_color_rgb(60, 60, 80));
    draw_rectangle(_x1 - 1, _top - 1, _x1 + _vw, _top + _vh, true);
    scr_ui_info(point_in_rectangle(_mx, _my, _x1, _top, _x1 + _vw, _top + _vh), "ROOM PREVIEW (VIEW ONLY): YELLOW BOXES ARE EMITTED ENTRIES, GREY ONES ARE SWITCHED OFF");
    if (!_ok) {
        draw_set_color(c_orange);
        draw_text(_x1 + 8, _top + 8 - scr_lang_lift(), "NO PREVIEW - THE MAP NEEDS A CHARSET");
    }

    // mode buttons
    var _lbl = ["ALL", "HIGHLIGHT", "PICKUPS ONLY"];
    var _by  = _top + _vh + 10;
    for (var _k = 0; _k < 3; _k++) {
        var _bx = _x1 + _k * 136;
        var _vinf = ["ALL: SHOW THE WHOLE ROOM WITH THE ENTRIES OUTLINED", "HIGHLIGHT: DIM THE ROOM SO THE ENTRY CELLS STAND OUT", "PICKUPS ONLY: SHOW JUST THE ENTRY CELLS"];
        scr_ui_info(point_in_rectangle(_mx, _my, _bx, _by, _bx + 130, _by + 24), _vinf[_k]);
        if (scr_mrp_button(_bx, _by, _bx + 130, _by + 24, _lbl[_k], pickup_view == _k, _mx, _my) == 1) pickup_view = _k;
    }
}
