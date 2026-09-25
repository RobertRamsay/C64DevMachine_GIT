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
    var _rooms = _m.rooms;
    var _n     = array_length(_rooms);
    if (_m.sel_room >= _n) { _m.sel_room = _n - 1; }

    var _c_lbl  = make_color_rgb(140, 150, 180);
    var _c_dim  = make_color_rgb(95, 95, 115);
    var _c_box  = make_color_rgb(20, 22, 32);
    var _c_edge = make_color_rgb(56, 56, 78);
    var _press  = mouse_check_button_pressed(mb_left);

    var _button = function(_x1, _y1, _w, _h, _label, _col, _mx2, _my2) {
        var _hov = point_in_rectangle(_mx2, _my2, _x1, _y1, _x1 + _w, _y1 + _h);
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
    if (_button(_vx1 + 10, _cy, 70, 18, "+ ROOM", make_color_rgb(30, 80, 40), _mx, _my)) {
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
    if (_button(_vx1 + 86, _cy, 70, 18, "DELETE", make_color_rgb(80, 30, 30), _mx, _my)) {
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
    if (_button(_vx1 + 170, _cy, 190, 18, _reu_lbl, make_color_rgb(25, 65, 80), _mx, _my)) {
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
    if (_button(_vx1 + 366, _cy, 64, 18, _zl[clamp(_m.zoom, 1, 3) - 1], make_color_rgb(38, 38, 58), _mx, _my)) {
        _m.zoom = (_m.zoom mod 3) + 1;
    }
    draw_set_color(_c_dim);
    var _hint = "DRAG ROOMS TO ARRANGE  -  SELECT AN EXIT, [LINK], THEN CLICK THE ROOM IT LEADS TO";
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
    for (var _r = 0; _r < _n; _r++) {
        var _ro = _rooms[_r];
        var _x1 = _cvx1 + clamp(_ro.mx, 0, _maxmx) * _z;
        var _y1 = _cvy1 + clamp(_ro.my, 0, _maxmy) * _z;
        var _hov = point_in_rectangle(_mx, _my, _x1, _y1, _x1 + _bw, _y1 + _bh);
        if (_hov) { _hover_room = _r; }
        draw_set_color(make_color_rgb(14, 14, 22));
        draw_rectangle(_x1, _y1, _x1 + _bw, _y1 + _bh, false);
        var _th = _bh - 16 * _z;
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
    if (_press && _on_canvas) {
        if (_m.link_exit >= 0 && _m.sel_room >= 0) {
            if (_hover_room >= 0) {
                _rooms[_m.sel_room].exits[_m.link_exit].to = _hover_room;
                _m.sel_exit = _m.link_exit;
                global.addresses_dirty = true;
            }
            _m.link_exit = -1;
        } else if (_hover_room >= 0) {
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
    if (_button(_qx + 70, _qy, _qw - 70, 16, string_copy(_bl, 1, 52), make_color_rgb(25, 55, 75), _mx, _my)) {
        _m.pick_mode = "BMP";
        _m.pick_scroll = 0;
    }
    _qy += 20;
    draw_set_color(_c_lbl);
    draw_text_l(_qx, _qy + 3, "COLLIDERS");
    var _cl = _ro.coll;
    if (_cl == "") { _cl = "(none)"; }
    if (_button(_qx + 70, _qy, _qw - 70, 16, string_copy(_cl, 1, 52), make_color_rgb(60, 45, 25), _mx, _my)) {
        _m.pick_mode = "COLL";
        _m.pick_scroll = 0;
    }
    _qy += 20;
    draw_set_color(_c_lbl);
    draw_text_l(_qx, _qy + 3, "MASK");
    var _mkl = _ro.mask;
    if (_mkl == "") { _mkl = "(none)"; }
    if (_button(_qx + 70, _qy, _qw - 70, 16, string_copy(_mkl, 1, 52), make_color_rgb(70, 30, 70), _mx, _my)) {
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
        if (_button(_qx, _cvy2 - 26, 70, 16, "CANCEL", make_color_rgb(80, 30, 30), _mx, _my)) {
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
        if (_button(_qx + _qw - 104, _ry, 56, 16, "LINK", _lk_col, _mx, _my)) {
            if (_m.link_exit == _e) {
                _m.link_exit = -1;
            } else {
                _m.link_exit = _e;
            }
        }
        if (_button(_qx + _qw - 44, _ry, 44, 16, "CLEAR", make_color_rgb(80, 30, 30), _mx, _my)) {
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
        for (var _li = 0; _li < array_length(_lc.meta.lines); _li++) {
            var _ln = _lc.meta.lines[_li];
            var _lt = real(_ln.type);
            draw_set_color(scr_room_map_type_col(_lt));
            draw_line_width(_qx + _ln.x1 * _sc, _qy + _ln.y1 * _sc, _qx + _ln.x2 * _sc, _qy + _ln.y2 * _sc, 2);
            if (_lt >= 2) {
                var _mxl = _qx + (_ln.x1 + _ln.x2) * 0.5 * _sc;
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
