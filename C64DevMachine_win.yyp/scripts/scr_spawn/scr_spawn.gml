/// ====================================================================
/// ENTITY SPAWN LAYER  (v1.3.4)
///
/// Enemies, pickups and turrets placed straight onto a map, each one an
/// instance of an entity TYPE, and every type with a MOVEMENT from a fixed
/// library. Lives on META_TILESET maps (one list per map tab) and MAP_DATA
/// maps (one list for the whole map - rooms are worked out at build time).
///
/// meta.spawn = {
///     sprite_set : SPRITE_SET asset the types take their frames from
///     types[]    : { name, frame, col, hp, pts, speed, move, value, drop }
///     maps[]     : per META_TILESET map (MAP_DATA uses maps[0]):
///                  array of [x, y, type]  - x / y in chars, top-left of
///                  the entity's sprite
///     sel, mode, show : editor state
/// }
///
/// A MACRO_SPAWNER node turns one map's list into tables and the runtime
/// that launches the entities as the map scrolls (or a room is entered)
/// and moves them. Game code only does collisions, scoring and drawing,
/// reading the slot arrays the node publishes (see scr_spawn_compile).
/// ====================================================================

#macro SPAWN_MAX_TYPES 16
#macro SPAWN_MAX_SLOTS 8

/// Movement library, in the order the runtime dispatches them.
function scr_spawn_moves() {
    return ["STRAIGHT", "SINE", "CHASE", "ZIGZAG", "DIVE", "WALKER", "TURRET"];
}

function scr_spawn_move_name(_mv) {
    var _n = scr_spawn_moves();
    return _n[clamp(_mv, 0, array_length(_n) - 1)];
}

/// What VALUE means for each movement (editor hint).
function scr_spawn_move_value_hint(_mv) {
    switch (_mv) {
        case 0: return "VALUE: UNUSED";
        case 1: return "VALUE: SWING 0 SMALL - 3 WIDE";
        case 2: return "VALUE: TURN RATE 0 FAST - 3 LAZY";
        case 3: return "VALUE: SWING 0 SMALL - 3 WIDE";
        case 4: return "VALUE: FRAMES/8 BEFORE IT DIVES";
        case 5: return "VALUE: WALK SPEED 0 STILL - 3 FAST";
        case 6: return "VALUE: FIRE EVERY (VALUE+1)*16 FRAMES";
    }
    return "";
}

function scr_spawn_type_new(_name, _frame, _col, _move) {
    return { name: _name, frame: _frame, col: _col, hp: 1, pts: 1, speed: 2, move: _move, value: 1, drop: 0 };
}

/// The spawn layer of a map asset's meta, created on first use so older
/// projects and freshly made assets need no load / create code.
function scr_spawn_get(_m) {
    if (!variable_struct_exists(_m, "spawn") || !is_struct(_m.spawn)) {
        _m.spawn = {
            sprite_set: "",
            types: [scr_spawn_type_new("ENEMY", 0, 2, 0)],
            maps: [],
            sel: 0,
            mode: false,
            show: true
        };
    }
    var _s = _m.spawn;
    if (!variable_struct_exists(_s, "sprite_set")) _s.sprite_set = "";
    if (!variable_struct_exists(_s, "types") || !is_array(_s.types)) _s.types = [];
    if (!variable_struct_exists(_s, "maps") || !is_array(_s.maps)) _s.maps = [];
    if (!variable_struct_exists(_s, "sel")) _s.sel = 0;
    if (!variable_struct_exists(_s, "mode")) _s.mode = false;
    if (!variable_struct_exists(_s, "show")) _s.show = true;
    var _keys = ["frame", "col", "hp", "pts", "speed", "move", "value", "drop"];
    var _defs = [0, 1, 1, 1, 2, 0, 1, 0];
    for (var _i = 0; _i < array_length(_s.types); _i++) {
        var _t = _s.types[_i];
        if (!variable_struct_exists(_t, "name")) _t.name = "TYPE " + string(_i);
        for (var _k = 0; _k < array_length(_keys); _k++) {
            if (!variable_struct_exists(_t, _keys[_k])) variable_struct_set(_t, _keys[_k], _defs[_k]);
        }
    }
    if (array_length(_s.types) == 0) array_push(_s.types, scr_spawn_type_new("ENEMY", 0, 2, 0));
    _s.sel = clamp(_s.sel, 0, array_length(_s.types) - 1);
    return _s;
}

/// The placement list of one map (created empty when missing).
function scr_spawn_list(_m, _map) {
    var _s = scr_spawn_get(_m);
    _map = max(0, _map);
    while (array_length(_s.maps) <= _map) array_push(_s.maps, []);
    return _s.maps[_map];
}

/// Does this asset have any placed entity at all?
function scr_spawn_has_any(_m) {
    if (!variable_struct_exists(_m, "spawn") || !is_struct(_m.spawn)) return false;
    for (var _i = 0; _i < array_length(_m.spawn.maps); _i++) {
        if (array_length(_m.spawn.maps[_i]) > 0) return true;
    }
    return false;
}

/// A META_TILESET map tab was deleted: drop its list so later maps keep theirs.
function scr_spawn_map_removed(_m, _idx) {
    if (!variable_struct_exists(_m, "spawn") || !is_struct(_m.spawn)) return;
    if (_idx < array_length(_m.spawn.maps)) array_delete(_m.spawn.maps, _idx, 1);
}

function scr_spawn_find_asset(_name, _type) {
    if (_name == "" || !instance_exists(obj_asset_manager)) return noone;
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.name == _name && (_type == "" || _a.type == _type)) return _a;
    }
    return noone;
}

/// Sprite pointer of frame 0 of a SPRITE_SET (address within its VIC bank / 64).
function scr_spawn_sprite_base(_sprite_set_name) {
    var _a = scr_spawn_find_asset(_sprite_set_name, "SPRITE_SET");
    if (_a == noone) return 0;
    return ((real(_a.address) & 0x3FFF) div 64) & 0xFF;
}

// --------------------------------------------------------------------
// SPRITE PREVIEW - frames cached as surfaces, rebuilt every few seconds
// so sprite edits show up without any invalidation plumbing.
// --------------------------------------------------------------------
function scr_spawn_frame_surface(_asset, _frame, _col) {
    if (!variable_global_exists("spawn_surf_cache")) {
        global.spawn_surf_cache = ds_map_create();
        global.spawn_surf_time  = current_time;
    }
    if (current_time - global.spawn_surf_time > 3000) {
        var _k = ds_map_find_first(global.spawn_surf_cache);
        while (!is_undefined(_k)) {
            var _sf = global.spawn_surf_cache[? _k];
            if (surface_exists(_sf)) surface_free(_sf);
            _k = ds_map_find_next(global.spawn_surf_cache, _k);
        }
        ds_map_clear(global.spawn_surf_cache);
        global.spawn_surf_time = current_time;
    }
    var _key = _asset.name + ":" + string(_frame) + ":" + string(_col);
    var _surf = global.spawn_surf_cache[? _key];
    if (!is_undefined(_surf) && surface_exists(_surf)) return _surf;
    if (!buffer_exists(_asset.buffer)) return -1;
    var _size = buffer_get_size(_asset.buffer);
    if (_frame * 64 + 63 > _size) return -1;
    var _mc = 0;
    if (variable_struct_exists(_asset.meta, "sprite_mcs") && _frame < array_length(_asset.meta.sprite_mcs)) _mc = _asset.meta.sprite_mcs[_frame];
    var _mc1 = variable_struct_exists(_asset.meta, "mc1_col") ? _asset.meta.mc1_col : 1;
    var _mc2 = variable_struct_exists(_asset.meta, "mc2_col") ? _asset.meta.mc2_col : 2;
    _surf = surface_create(24, 21);
    surface_set_target(_surf);
    draw_clear_alpha(c_black, 0);
    for (var _y = 0; _y < 21; _y++) {
        for (var _b = 0; _b < 3; _b++) {
            var _v = buffer_peek(_asset.buffer, _frame * 64 + _y * 3 + _b, buffer_u8);
            if (_v == 0) continue;
            if (_mc) {
                for (var _p = 0; _p < 4; _p++) {
                    var _bits = (_v >> (6 - _p * 2)) & 3;
                    if (_bits == 0) continue;
                    var _c = (_bits == 1) ? _mc1 : ((_bits == 2) ? _col : _mc2);
                    draw_set_color(scr_c64_pepto_colour(_c));
                    draw_rectangle(_b * 8 + _p * 2, _y, _b * 8 + _p * 2 + 1, _y, false);
                }
            } else {
                draw_set_color(scr_c64_pepto_colour(_col));
                for (var _p = 0; _p < 8; _p++) {
                    if (_v & (0x80 >> _p)) draw_point(_b * 8 + _p, _y);
                }
            }
        }
    }
    surface_reset_target();
    global.spawn_surf_cache[? _key] = _surf;
    return _surf;
}

/// Draw one entity at screen pixel (_px, _py), _cs pixels per char.
function scr_spawn_draw_entity(_s, _t, _px, _py, _cs, _alpha) {
    var _ty = _s.types[_t];
    var _w = 3 * _cs;
    var _h = 21 * _cs / 8;
    var _spr = scr_spawn_find_asset(_s.sprite_set, "SPRITE_SET");
    var _drawn = false;
    if (_spr != noone) {
        var _surf = scr_spawn_frame_surface(_spr, _ty.frame, _ty.col);
        if (_surf != -1 && surface_exists(_surf)) {
            draw_surface_ext(_surf, _px, _py, _cs / 8, _cs / 8, 0, c_white, _alpha);
            _drawn = true;
        }
    }
    if (!_drawn) {
        draw_set_alpha(_alpha * 0.6);
        draw_set_color(scr_c64_pepto_colour(_ty.col));
        draw_rectangle(_px, _py, _px + _w - 1, _py + _h - 1, false);
        draw_set_alpha(1);
    }
    // type number + movement initial, so a busy map stays readable
    draw_set_alpha(_alpha);
    draw_set_font_l(fnt_c64_tiny);
    draw_set_halign(fa_left);
    var _tag = string(_t) + string_char_at(scr_spawn_move_name(_ty.move), 1);
    draw_set_color(make_color_rgb(20, 20, 30));
    draw_rectangle(_px, _py + _h - 9, _px + string_width_l(_tag) + 3, _py + _h - 1, false);
    draw_set_color(c_yellow);
    draw_text_l(_px + 2, _py + _h - 9, _tag);
    draw_set_alpha(1);
}

// --------------------------------------------------------------------
// MAP EDITOR LAYER
//
// _ctx = { m, map, ox, oy, cs, x1, y1, x2, y2, map_w, map_h }
//   ox / oy : screen pixel of map char (0, 0); cs : pixels per char
//   x1..y2  : the canvas (clip and hit area); map_w / map_h in chars
// Draws the placed entities, the SPAWNS button and, in SPAWN mode, the
// type panel; handles placing (L), deleting (R) and picking (ALT+L).
// Returns true while it owns the mouse, so the editor must not paint.
// --------------------------------------------------------------------
function scr_spawn_editor(_ctx, _mx, _my) {
    var _m = _ctx.m;
    var _s = scr_spawn_get(_m);
    var _list = scr_spawn_list(_m, _ctx.map);
    var _cs = _ctx.cs;
    var _busy = false;

    // ---- the placed entities ----
    if (_s.show || _s.mode) {
        // Build every type's preview first: creating a surface resets the
        // scissor, which made the markers flash through the clip.
        var _spr0 = scr_spawn_find_asset(_s.sprite_set, "SPRITE_SET");
        if (_spr0 != noone) {
            for (var _ti = 0; _ti < array_length(_s.types); _ti++) scr_spawn_frame_surface(_spr0, _s.types[_ti].frame, _s.types[_ti].col);
        }
        // gpu_set_scissor takes window pixels, not GUI units
        var _ssx = window_get_width() / global.gui_w;
        var _ssy = window_get_height() / display_get_gui_height();
        gpu_set_scissor(floor(_ctx.x1 * _ssx), floor(_ctx.y1 * _ssy), ceil((_ctx.x2 - _ctx.x1) * _ssx), ceil((_ctx.y2 - _ctx.y1) * _ssy));
        for (var _i = 0; _i < array_length(_list); _i++) {
            var _e = _list[_i];
            var _t = clamp(real(_e[2]), 0, array_length(_s.types) - 1);
            var _px = _ctx.ox + real(_e[0]) * _cs;
            var _py = _ctx.oy + real(_e[1]) * _cs;
            if (_px > _ctx.x2 || _py > _ctx.y2 || _px + 3 * _cs < _ctx.x1 || _py + 3 * _cs < _ctx.y1) continue;
            scr_spawn_draw_entity(_s, _t, _px, _py, _cs, _s.mode ? 1 : 0.8);
        }
        gpu_set_scissor(0, 0, window_get_width(), window_get_height());
    }

    // ---- SPAWNS toggle, top-right of the canvas ----
    var _bw = 74, _bh = 18;
    var _bx = _ctx.x2 - _bw - 6, _by = _ctx.y1 + 4;
    if (scr_bmpobj_ui_button(_bx, _by, _bw, _bh, "SPAWNS", _s.mode, _mx, _my,
        "SPAWN LAYER: PLACE ENEMIES, PICKUPS AND TURRETS ON THE MAP. A MACRO_SPAWNER NODE LAUNCHES THEM IN THE GAME (E)")) {
        _s.mode = !_s.mode;
    }
    if (point_in_rectangle(_mx, _my, _bx, _by, _bx + _bw, _by + _bh)) _busy = true;
    var _ex = _bx - 50;
    if (scr_bmpobj_ui_button(_ex, _by, 44, _bh, "SHOW", _s.show, _mx, _my, "SHOW / HIDE THE PLACED ENTITIES WHEN NOT IN SPAWN MODE")) {
        _s.show = !_s.show;
    }
    if (point_in_rectangle(_mx, _my, _ex, _by, _ex + 44, _by + _bh)) _busy = true;
    if (keyboard_check_pressed(ord("E")) && !scr_ctrl_held() && !global.integer_box_open) _s.mode = !_s.mode;
    if (!_s.mode) return _busy;

    // ---- type panel, top-left of the canvas ----
    var _pw = 236;
    var _px1 = _ctx.x1 + 6, _py1 = _ctx.y1 + 4;
    var _rows = array_length(_s.types);
    var _ph = 22 + 22 + _rows * 18 + 8 + 9 * 20 + 26;
    var _px2 = _px1 + _pw, _py2 = _py1 + _ph;
    scr_bmpobj_ui_panel(_px1, _py1, _px2, _py2, "SPAWN LAYER - " + string(array_length(_list)) + " PLACED");
    var _over_panel = point_in_rectangle(_mx, _my, _px1, _py1, _px2, _py2);
    if (_over_panel) _busy = true;
    var _lx = _px1 + 6;
    var _ly = _py1 + 24;
    draw_set_font_l(fnt_c64_tiny);

    // sprite set the types take their frames from
    draw_set_color(make_color_rgb(154, 175, 198));
    scr_editor_label(_lx, _ly, _lx + 50, _ly + 18, "SPRITES", fa_left, 0);
    var _sets = [];
    if (instance_exists(obj_asset_manager)) {
        var _am = obj_asset_manager;
        for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
            var _a = ds_list_find_value(_am.asset_list, _ai);
            if (_a.type == "SPRITE_SET") array_push(_sets, _a.name);
        }
    }
    var _sname = (_s.sprite_set == "") ? "<NONE>" : _s.sprite_set;
    if (scr_bmpobj_ui_button(_lx + 54, _ly, _pw - 66, 18, _sname, false, _mx, _my, "SPRITE SET THE ENTITY FRAMES COME FROM - CLICK FOR THE NEXT ONE")) {
        if (array_length(_sets) > 0) {
            var _cur = -1;
            for (var _si = 0; _si < array_length(_sets); _si++) if (_sets[_si] == _s.sprite_set) _cur = _si;
            _s.sprite_set = _sets[(_cur + 1) mod array_length(_sets)];
            global.addresses_dirty = true;
        }
    }
    _ly += 22;

    // the type list
    for (var _ti = 0; _ti < _rows; _ti++) {
        var _ty = _s.types[_ti];
        var _ry = _ly + _ti * 18;
        var _hov = point_in_rectangle(_mx, _my, _lx, _ry, _px2 - 6, _ry + 16);
        scr_editor_control(_lx, _ry, _px2 - 6, _ry + 16, _hov, _ti == _s.sel);
        scr_editor_swatch(_lx + 2, _ry + 3, _lx + 12, _ry + 13, scr_c64_pepto_colour(_ty.col));
        draw_set_color(c_white);
        scr_editor_label(_lx + 16, _ry, _px2 - 6, _ry + 16,
            string(_ti) + " " + string(_ty.name) + "  " + scr_spawn_move_name(_ty.move), fa_left, 0);
        scr_ui_info(_hov, "ENTITY TYPE " + string(_ti) + " - CLICK TO PLACE THIS ONE ON THE MAP");
        if (_hov && mouse_check_button_pressed(mb_left)) _s.sel = _ti;
    }
    _ly += _rows * 18 + 4;
    if (scr_bmpobj_ui_button(_lx, _ly, 52, 18, "+ TYPE", false, _mx, _my, "ADD AN ENTITY TYPE (COPY OF THE SELECTED ONE)", _rows < SPAWN_MAX_TYPES)) {
        var _src = _s.types[_s.sel];
        var _nt = scr_spawn_type_new("TYPE " + string(_rows), _src.frame, _src.col, _src.move);
        _nt.hp = _src.hp; _nt.pts = _src.pts; _nt.speed = _src.speed; _nt.value = _src.value; _nt.drop = _src.drop;
        array_push(_s.types, _nt);
        _s.sel = _rows;
        global.addresses_dirty = true;
    }
    if (scr_bmpobj_ui_button(_lx + 58, _ly, 52, 18, "- TYPE", false, _mx, _my, "DELETE THE SELECTED TYPE AND EVERY ENTITY OF IT", _rows > 1)) {
        scr_spawn_delete_type(_s, _s.sel);
        global.addresses_dirty = true;
        return true;
    }
    if (scr_bmpobj_ui_button(_lx + 116, _ly, 52, 18, "RENAME", false, _mx, _my, "RENAME THE SELECTED TYPE")) {
        scr_prompt_text("Entity type name", string(_s.types[_s.sel].name), scr_spawn_rename_cb, { s: _s, t: _s.sel });
    }
    if (scr_bmpobj_ui_button(_lx + 174, _ly, 50, 18, "CLEAR", false, _mx, _my, "REMOVE EVERY ENTITY FROM THIS MAP")) {
        array_resize(_list, 0);
        global.addresses_dirty = true;
    }
    _ly += 24;

    // the selected type's settings: L-click +1, R-click -1
    var _ty = _s.types[_s.sel];
    var _base = scr_spawn_sprite_base(_s.sprite_set);
    var _fields = [
        ["FRAME", "frame", 0, 63, "SPRITE FRAME IN THE SPRITE SET (POINTER $" + string_upper(decimal_to_hex(_base + _ty.frame)) + ")"],
        ["COLOUR", "col", 0, 15, "SPRITE COLOUR"],
        ["MOVE", "move", 0, 6, "MOVEMENT: STRAIGHT, SINE, CHASE, ZIGZAG, DIVE, WALKER (RIDES THE GROUND), TURRET (FIXED TO THE MAP)"],
        ["VALUE", "value", 0, 3, scr_spawn_move_value_hint(_ty.move)],
        ["SPEED", "speed", 0, 4, "PIXELS PER FRAME ALONG THE SCROLL (TOWARDS THE PLAYER)"],
        ["HP", "hp", 1, 15, "HITS IT TAKES (SPN_Hit COUNTS THEM DOWN)"],
        ["POINTS", "pts", 0, 99, "SCORE VALUE - YOUR CODE READS SPN_T_PTS"],
        ["DROP", "drop", 0, 15, "WHAT IT LEAVES BEHIND, 0 = NOTHING - YOUR CODE READS SPN_T_DROP"],
    ];
    for (var _fi = 0; _fi < array_length(_fields); _fi++) {
        var _f = _fields[_fi];
        var _fy = _ly + _fi * 20;
        draw_set_color(make_color_rgb(154, 175, 198));
        scr_editor_label(_lx, _fy, _lx + 64, _fy + 18, _f[0], fa_left, 0);
        var _v = variable_struct_get(_ty, _f[1]);
        var _vx1 = _lx + 70, _vx2 = _px2 - 6;
        var _vhov = point_in_rectangle(_mx, _my, _vx1, _fy, _vx2, _fy + 18);
        scr_editor_control(_vx1, _fy, _vx2, _fy + 18, _vhov, false);
        var _vtxt = string(_v);
        if (_f[1] == "move") _vtxt = scr_spawn_move_name(_v);
        if (_f[1] == "col") scr_editor_swatch(_vx2 - 22, _fy + 3, _vx2 - 4, _fy + 15, scr_c64_pepto_colour(_v));
        draw_set_color(c_white);
        scr_editor_label(_vx1, _fy, _vx2, _fy + 18, _vtxt, fa_left, 6);
        scr_ui_info(_vhov, _f[4] + " - L-CLICK UP, R-CLICK DOWN");
        if (_vhov) {
            var _nv = _v;
            if (mouse_check_button_pressed(mb_left)) _nv = (_v >= _f[3]) ? _f[2] : _v + 1;
            if (mouse_check_button_pressed(mb_right)) _nv = (_v <= _f[2]) ? _f[3] : _v - 1;
            if (_nv != _v) {
                variable_struct_set(_ty, _f[1], _nv);
                global.addresses_dirty = true;
            }
        }
    }
    _ly += array_length(_fields) * 20 + 4;
    draw_set_color(make_color_rgb(120, 130, 150));
    scr_editor_label(_lx, _ly, _px2 - 6, _ly + 16, "L PLACE  R DELETE  ALT+L PICK  E OFF", fa_left, 0);

    // ---- placing on the map ----
    var _in_canvas = point_in_rectangle(_mx, _my, _ctx.x1, _ctx.y1, _ctx.x2, _ctx.y2);
    if (_in_canvas && !_over_panel && !_busy) {
        _busy = true;
        var _cx = floor((_mx - _ctx.ox) / _cs);
        var _cy = floor((_my - _ctx.oy) / _cs);
        if (_cx >= 0 && _cy >= 0 && _cx < _ctx.map_w && _cy < _ctx.map_h) {
            // the entity under the pointer (sprite-sized, 3 x 3 chars)
            var _hit = -1;
            for (var _i = array_length(_list) - 1; _i >= 0; _i--) {
                var _e = _list[_i];
                if (_cx >= real(_e[0]) && _cx < real(_e[0]) + 3 && _cy >= real(_e[1]) && _cy < real(_e[1]) + 3) { _hit = _i; break; }
            }
            var _gx = _ctx.ox + _cx * _cs, _gy = _ctx.oy + _cy * _cs;
            if (keyboard_check(vk_alt)) {
                scr_ui_info(true, "SPAWN: ALT+CLICK PICKS THE TYPE UNDER THE POINTER");
                if (_hit >= 0) {
                    var _he = _list[_hit];
                    draw_set_color(c_yellow);
                    draw_rectangle(_ctx.ox + real(_he[0]) * _cs, _ctx.oy + real(_he[1]) * _cs,
                                   _ctx.ox + (real(_he[0]) + 3) * _cs - 1, _ctx.oy + (real(_he[1]) + 3) * _cs - 1, true);
                    if (mouse_check_button_pressed(mb_left)) _s.sel = clamp(real(_he[2]), 0, _rows - 1);
                }
            } else {
                scr_ui_info(true, "SPAWN: L-CLICK PLACES " + string(_ty.name) + " (TOP-LEFT OF ITS SPRITE), R-CLICK DELETES, ALT+CLICK PICKS");
                scr_spawn_draw_entity(_s, _s.sel, _gx, _gy, _cs, 0.6);
                draw_set_color(c_aqua);
                draw_rectangle(_gx, _gy, _gx + 3 * _cs - 1, _gy + 21 * _cs / 8 - 1, true);
                if (mouse_check_button_pressed(mb_left) && _hit < 0) {
                    if (array_length(_list) < 255) {
                        array_push(_list, [_cx, _cy, _s.sel]);
                        global.addresses_dirty = true;
                        _m.is_dirty = true;
                    }
                }
                if (mouse_check_button_pressed(mb_right) && _hit >= 0) {
                    array_delete(_list, _hit, 1);
                    global.addresses_dirty = true;
                    _m.is_dirty = true;
                }
            }
        }
    }
    return _busy;
}

function scr_spawn_rename_cb(_text, _ctx) {
    var _t = string_upper(string_trim(_text));
    if (_t == "") return;
    if (_ctx.t < array_length(_ctx.s.types)) _ctx.s.types[_ctx.t].name = string_copy(_t, 1, 12);
}

/// Remove a type: its entities go, later types move down one.
function scr_spawn_delete_type(_s, _t) {
    if (array_length(_s.types) <= 1) return;
    array_delete(_s.types, _t, 1);
    for (var _mi = 0; _mi < array_length(_s.maps); _mi++) {
        var _l = _s.maps[_mi];
        for (var _i = array_length(_l) - 1; _i >= 0; _i--) {
            if (real(_l[_i][2]) == _t) array_delete(_l, _i, 1);
            else if (real(_l[_i][2]) > _t) _l[_i][2] = real(_l[_i][2]) - 1;
        }
    }
    _s.sel = clamp(_s.sel, 0, array_length(_s.types) - 1);
}

// --------------------------------------------------------------------
// MACRO_SPAWNER node
//   instructions[0] = ["MACRO_SPAWNER", asset, map, axis, slots, col_off, row_off]
//   axis 0 = H scroll (enters from the right), 1 = V scroll (enters from the
//   top), 2 = ROOMS (JSR SPN_Room with A = room). col_off / row_off move the
//   ROOMS screen position (chars).
// --------------------------------------------------------------------
function scr_spawn_node_args(_n) {
    var _i = _n.instructions[0];
    var _get = function(_arr, _k, _d) { return (array_length(_arr) > _k && is_real(_arr[_k])) ? real(_arr[_k]) : _d; };
    return {
        asset: (array_length(_i) > 1) ? string(_i[1]) : "",
        map:   _get(_i, 2, 0),
        axis:  clamp(_get(_i, 3, 0), 0, 2),
        slots: clamp(_get(_i, 4, 4), 1, SPAWN_MAX_SLOTS),
        col_off: _get(_i, 5, 0),
        row_off: _get(_i, 6, 0)
    };
}

function scr_spawn_entry_labels(_axis) {
    var _l = ["SPN_Update", "SPN_Reset", "SPN_Hit"];
    if (_axis < 2) array_push(_l, "SPN_Scroll");
    if (_axis == 2) array_push(_l, "SPN_Room");
    return _l;
}

/// Map assets that can carry a spawn layer.
function scr_spawn_map_assets() {
    var _out = [];
    if (!instance_exists(obj_asset_manager)) return _out;
    var _am = obj_asset_manager;
    for (var _i = 0; _i < ds_list_size(_am.asset_list); _i++) {
        var _a = ds_list_find_value(_am.asset_list, _i);
        if (_a.type == "META_TILESET" || _a.type == "MAP_DATA") array_push(_out, _a.name);
    }
    return _out;
}

function scr_node_draw_macro_spawner(_draw_x, _draw_y) {
    var _a = scr_spawn_node_args(id);
    var _asset = scr_spawn_find_asset(_a.asset, "");
    draw_set_font_l(fnt_c64_tiny);
    draw_set_halign(fa_left);
    var _lh = 12;
    var _lx = _draw_x + 8;
    var _rx = _draw_x + width - 8;
    var _vx = _lx + string_width_l("COL/ROW:") + 8;
    var _ly = _draw_y + 28;
    msc_entry_rects = [];

    var _modes = ["SCROLL H", "SCROLL V", "ROOMS"];
    var _rows = [
        ["MAP:", (_a.asset == "") ? "<PICK>" : _a.asset, (_a.asset == "") ? c_red : c_aqua],
        ["MAP NO:", string(_a.map), c_aqua],
        ["MODE:", _modes[_a.axis], c_lime],
        ["SLOTS:", string(_a.slots), c_aqua],
        ["COL/ROW:", string(_a.col_off) + " / " + string(_a.row_off), c_aqua],
    ];
    for (var _r = 0; _r < array_length(_rows); _r++) {
        draw_set_color(c_gray);
        scr_node_macro_text_l(_lx, _ly, _rows[_r][0]);
        draw_set_color(_rows[_r][2]);
        scr_node_macro_text_l(_vx, _ly, _rows[_r][1], _rx - _vx);
        _ly += _lh;
    }
    var _count = 0, _types = 0;
    if (_asset != noone) {
        var _s = scr_spawn_get(_asset.meta);
        _types = array_length(_s.types);
        _count = array_length(scr_spawn_list(_asset.meta, (_asset.type == "MAP_DATA") ? 0 : _a.map));
    }
    draw_set_color(make_color_rgb(180, 100, 30));
    scr_node_macro_text_l(_lx, _ly, string(_count) + " ENTITIES, " + string(_types) + " TYPES");
    _ly += _lh + 2;
    draw_set_color(c_gray);
    scr_node_macro_text_l(_lx, _ly, "JSR:");
    var _ex = _vx;
    var _labels = scr_spawn_entry_labels(_a.axis);
    for (var _li = 0; _li < array_length(_labels); _li++) {
        if (_ex + string_width_l(_labels[_li]) > _rx) { _ex = _vx; _ly += _lh; }
        scr_msc_entry(_ex, _ly, _labels[_li]);
        _ex += string_width_l(_labels[_li]) + 8;
    }
}

function scr_node_step_macro_spawner(_draw_x) {
    if (!scr_workspace_mouse_check_button_pressed(mb_left) && !scr_workspace_mouse_check_button_pressed(mb_right)) return;
    if (global.ui_click_consumed) return;
    if (global.any_picker_open) return;
    var _left = scr_workspace_mouse_check_button_pressed(mb_left);
    if (_left) {
        for (var _ei = 0; _ei < array_length(msc_entry_rects); _ei++) {
            var _er = msc_entry_rects[_ei];
            if (point_in_rectangle(mouse_x, mouse_y, _er[0], _er[1], _er[2], _er[3])) {
                scr_msc_drop_jsr(_er[4]);
                exit;
            }
        }
    }
    while (array_length(instructions[0]) < 7) array_push(instructions[0], 0);
    if (!is_string(instructions[0][1])) instructions[0][1] = "";
    draw_set_font_l(fnt_c64_tiny);
    var _lh = 12;
    var _ly0 = y + 28;
    var _vx = _draw_x + 8 + string_width_l("COL/ROW:") + 8;
    var _rx = _draw_x + width - 8;
    if (mouse_x < _vx || mouse_x > _rx) return;
    var _row = floor((mouse_y - _ly0 + 2) / _lh);
    var _d = _left ? 1 : -1;
    var _a = scr_spawn_node_args(id);
    switch (_row) {
        case 0: {
            var _list = scr_spawn_map_assets();
            if (array_length(_list) == 0) return;
            var _cur = -1;
            for (var _i = 0; _i < array_length(_list); _i++) if (_list[_i] == _a.asset) _cur = _i;
            instructions[0][1] = _list[(_cur + _d + array_length(_list)) mod array_length(_list)];
        } break;
        case 1: instructions[0][2] = max(0, _a.map + _d); break;
        case 2: instructions[0][3] = (_a.axis + _d + 3) mod 3; break;
        case 3: instructions[0][4] = clamp(_a.slots + _d, 1, SPAWN_MAX_SLOTS); break;
        case 4:
            if (mouse_x < _vx + 20) instructions[0][5] = clamp(_a.col_off + _d, 0, 39);
            else instructions[0][6] = clamp(_a.row_off + _d, 0, 24);
            break;
        default: return;
    }
    global.ui_click_consumed = true;
    global.addresses_dirty = true;
    global.undo_dirty = true;
}

// --------------------------------------------------------------------
// COMPILE - the tables and the runtime, written as assembly text and fed
// through the same parser as a CODE BLOCK. Everything is jumped over on
// the spine, so the node can sit anywhere in a setup routine.
//
// Published (labels):
//   SPN_Update  once a frame: launch what has come into view, move all
//   SPN_Scroll  after every 1-pixel scroll step: TURRET / WALKER ride the map
//   SPN_Reset   start of a game / after a lost life: clear, launch what shows
//   SPN_Room    ROOMS: A = room number - clear and launch that room's list
//   SPN_Hit     X = slot, A = damage. Carry set = it died (slot freed)
//   SPN_ON SPN_XL SPN_XH SPN_Y SPN_TYPE SPN_HP SPN_FIRE  per slot (N bytes)
//   SPN_T_PTR SPN_T_COL SPN_T_PTS SPN_T_DROP SPN_T_HP ...  per type
//   SPN_TGT_XL SPN_TGT_XH SPN_TGT_Y  the target CHASE / DIVE home in on
// --------------------------------------------------------------------
function scr_spawn_h2(_v) { var _d = "0123456789ABCDEF"; _v = _v & 0xFF; return "$" + string_char_at(_d, (_v >> 4) + 1) + string_char_at(_d, (_v & 15) + 1); }
function scr_spawn_hex(_v) { return "$" + string_upper(decimal_to_hex(_v & 0xFFFF)); }
function scr_spawn_bytes(_arr) {
    if (array_length(_arr) == 0) return ".byte $00\n";
    var _out = "";
    for (var _i = 0; _i < array_length(_arr); _i += 16) {
        var _line = ".byte ";
        for (var _j = _i; _j < min(_i + 16, array_length(_arr)); _j++) {
            _line += ((_j > _i) ? "," : "") + "$" + string_upper(decimal_to_hex(_arr[_j] & 0xFF));
        }
        _out += _line + "\n";
    }
    return _out;
}

/// The scroller this spawner reads: zp base, omitted top / bottom rows.
function scr_spawn_scroller() {
    var _out = { zp: 0x60, omit_t: 0, omit_b: 0 };
    with (obj_c64_node) {
        if (node_type != "MACRO_METASCROLL") continue;
        var _live = is_connected;
        if (org_parent != noone && instance_exists(org_parent)) _live = true;
        if (!_live) continue;
        var _i = instructions[0];
        if (array_length(_i) > 4 && is_real(_i[4])) _out.zp = real(_i[4]);
        if (array_length(_i) > 11 && is_real(_i[11])) _out.omit_t = clamp(floor(real(_i[11])), 0, 8);
        if (array_length(_i) > 12 && is_real(_i[12])) _out.omit_b = clamp(floor(real(_i[12])), 0, 8);
        break;
    }
    return _out;
}

function scr_spawn_source(_a) {
    var _asset = scr_spawn_find_asset(_a.asset, "");
    var _out = { ok: false, types: [], list: [], room_w: 0, room_h: 0, rooms_x: 1, rooms: 1, sprite_base: 0 };
    if (_asset == noone) return _out;
    if (_asset.type != "META_TILESET" && _asset.type != "MAP_DATA") return _out;
    var _s = scr_spawn_get(_asset.meta);
    _out.ok = true;
    _out.types = _s.types;
    _out.list = scr_spawn_list(_asset.meta, (_asset.type == "MAP_DATA") ? 0 : _a.map);
    _out.sprite_base = scr_spawn_sprite_base(_s.sprite_set);
    if (_asset.type == "MAP_DATA" && variable_struct_exists(_asset.meta, "room_w") && real(_asset.meta.room_w) > 0) {
        _out.room_w = real(_asset.meta.room_w);
        _out.room_h = real(_asset.meta.room_h);
        _out.rooms_x = max(1, real(_asset.meta.map_w) div _out.room_w);
        _out.rooms = _out.rooms_x * max(1, real(_asset.meta.map_h) div _out.room_h);
        if (variable_struct_exists(_asset.meta, "room_count") && real(_asset.meta.room_count) > 0) _out.rooms = min(_out.rooms, real(_asset.meta.room_count));
    } else if (_asset.type == "META_TILESET") {
        // ROOMS on a stamp map: every map tab is one 40 x 25 screen
        _out.room_w = 40; _out.room_h = 25;
    }
    return _out;
}

/// The assembly for one MACRO_SPAWNER node.
function scr_spawn_asm(_node) {
    var _a = scr_spawn_node_args(_node);
    var _src = scr_spawn_source(_a);
    var _sc = scr_spawn_scroller();
    var _n = _a.slots;
    var _zp = _sc.zp;
    var _camx = scr_spawn_hex(_zp), _camy = scr_spawn_hex(_zp + 1);
    var _finex = scr_spawn_hex(_zp + 2), _finey = scr_spawn_hex(_zp + 3);
    var _rows_vis = 25 - _sc.omit_t - _sc.omit_b;
    var _nt = max(1, array_length(_src.types));

    // ---- type tables ----
    var _t_ptr = [], _t_frame = [], _t_col = [], _t_hp = [], _t_pts = [], _t_speed = [], _t_move = [], _t_val = [], _t_drop = [];
    for (var _i = 0; _i < _nt; _i++) {
        var _t = (_i < array_length(_src.types)) ? _src.types[_i] : scr_spawn_type_new("", 0, 1, 0);
        array_push(_t_frame, _t.frame);
        array_push(_t_ptr, _src.sprite_base + _t.frame);
        array_push(_t_col, _t.col);
        array_push(_t_hp, max(1, _t.hp));
        array_push(_t_pts, _t.pts);
        array_push(_t_speed, _t.speed);
        array_push(_t_move, clamp(_t.move, 0, 6));
        array_push(_t_val, clamp(_t.value, 0, 3));
        array_push(_t_drop, _t.drop);
    }

    // ---- placements, sorted along the scroll ----
    var _recs = [];
    for (var _i = 0; _i < array_length(_src.list); _i++) {
        var _e = _src.list[_i];
        array_push(_recs, [real(_e[0]), real(_e[1]), clamp(real(_e[2]), 0, _nt - 1)]);
    }
    var _l1 = [], _l2 = [], _lt = [];
    var _room_lo = [], _room_hi = [];
    var _txt = "";
    if (_a.axis == 0) {
        array_sort(_recs, function(_p, _q) { return (_p[0] != _q[0]) ? _p[0] - _q[0] : _p[1] - _q[1]; });
        for (var _i = 0; _i < array_length(_recs); _i++) { array_push(_l1, _recs[_i][0]); array_push(_l2, _recs[_i][1]); array_push(_lt, _recs[_i][2]); }
    } else if (_a.axis == 1) {
        array_sort(_recs, function(_p, _q) { return (_p[1] != _q[1]) ? _q[1] - _p[1] : _p[0] - _q[0]; });
        for (var _i = 0; _i < array_length(_recs); _i++) { array_push(_l1, _recs[_i][1]); array_push(_l2, _recs[_i][0]); array_push(_lt, _recs[_i][2]); }
    } else {
        // ROOMS: group by room; each room's run is count, then (col, row, type)
        var _rw = max(1, _src.room_w), _rh = max(1, _src.room_h);
        for (var _r = 0; _r < _src.rooms; _r++) {
            var _rx0 = (_r mod _src.rooms_x) * _rw, _ry0 = (_r div _src.rooms_x) * _rh;
            if (_src.room_w == 40 && _src.rooms == 1) { _rx0 = 0; _ry0 = 0; }
            var _run = [];
            for (var _i = 0; _i < array_length(_recs); _i++) {
                var _e = _recs[_i];
                if (_e[0] >= _rx0 && _e[0] < _rx0 + _rw && _e[1] >= _ry0 && _e[1] < _ry0 + _rh) {
                    array_push(_run, _e[0] - _rx0 + _a.col_off, _e[1] - _ry0 + _a.row_off, _e[2]);
                }
            }
            array_push(_l1, array_concat([array_length(_run) div 3], _run));
        }
    }
    var _count = array_length(_lt);

    _txt += "JMP SPN_Skip\n";
    // ---- data ----
    _txt += "SPN_ON:\n" + scr_spawn_bytes(array_create(_n, 0));
    _txt += "SPN_XL:\n" + scr_spawn_bytes(array_create(_n, 0));
    _txt += "SPN_XH:\n" + scr_spawn_bytes(array_create(_n, 0));
    _txt += "SPN_Y:\n" + scr_spawn_bytes(array_create(_n, 0));
    _txt += "SPN_TYPE:\n" + scr_spawn_bytes(array_create(_n, 0));
    _txt += "SPN_HP:\n" + scr_spawn_bytes(array_create(_n, 0));
    _txt += "SPN_FIRE:\n" + scr_spawn_bytes(array_create(_n, 0));
    _txt += "SPN_BL:\n" + scr_spawn_bytes(array_create(_n, 0));
    _txt += "SPN_BH:\n" + scr_spawn_bytes(array_create(_n, 0));
    _txt += "SPN_PH:\n" + scr_spawn_bytes(array_create(_n, 0));
    _txt += "SPN_TGT_XL:\n.byte $A0\nSPN_TGT_XH:\n.byte $00\nSPN_TGT_Y:\n.byte $90\n";
    _txt += "SPN_NEXT:\n.byte $00\nSPN_EDGE:\n.byte $00\nSPN_SLOT:\n.byte $00\nSPN_REC:\n.byte $00\nSPN_T0:\n.byte $00\nSPN_T1:\n.byte $00\nSPN_TICK:\n.byte $00\nSPN_WAIT:\n.byte $00\n";
    _txt += "SPN_T_PTR:\n" + scr_spawn_bytes(_t_ptr);
    _txt += "SPN_T_FRAME:\n" + scr_spawn_bytes(_t_frame);
    _txt += "SPN_T_COL:\n" + scr_spawn_bytes(_t_col);
    _txt += "SPN_T_HP:\n" + scr_spawn_bytes(_t_hp);
    _txt += "SPN_T_PTS:\n" + scr_spawn_bytes(_t_pts);
    _txt += "SPN_T_SPEED:\n" + scr_spawn_bytes(_t_speed);
    _txt += "SPN_T_MOVE:\n" + scr_spawn_bytes(_t_move);
    _txt += "SPN_T_VAL:\n" + scr_spawn_bytes(_t_val);
    _txt += "SPN_T_DROP:\n" + scr_spawn_bytes(_t_drop);
    // 64-step sine, +-32
    var _sine = [];
    for (var _i = 0; _i < 64; _i++) array_push(_sine, round(dsin(_i * 360 / 64) * 32) & 0xFF);
    _txt += "SPN_SINE:\n" + scr_spawn_bytes(_sine);
    if (_a.axis < 2) {
        _txt += "SPN_COUNT:\n.byte " + scr_spawn_hex(_count) + "\n";
        _txt += "SPN_L1:\n" + scr_spawn_bytes(_l1);
        _txt += "SPN_L2:\n" + scr_spawn_bytes(_l2);
        _txt += "SPN_LT:\n" + scr_spawn_bytes(_lt);
    } else {
        // every room's list in one table (count, then col / row / type),
        // and each room's offset into it - 255 bytes at most
        var _roff = [], _rdat = [];
        for (var _r = 0; _r < array_length(_l1); _r++) {
            array_push(_roff, min(255, array_length(_rdat)));
            _rdat = array_concat(_rdat, _l1[_r]);
        }
        if (array_length(_l1) == 0) { _roff = [0]; _rdat = [0]; }
        if (array_length(_rdat) > 255) show_debug_message("MACRO_SPAWNER: room lists over 255 bytes - trim the entities");
        _txt += "SPN_ROFF:\n" + scr_spawn_bytes(_roff);
        _txt += "SPN_RDAT:\n" + scr_spawn_bytes(_rdat);
    }

    var _last = scr_spawn_h2(_n - 1);
    // ================= runtime =================
    // SPN_Hit: X = slot, A = damage. Carry set = destroyed.
    _txt += "SPN_Hit:\nSTA SPN_T0\nLDA SPN_HP,X\nSEC\nSBC SPN_T0\nBEQ SPN_HitDead\nBCC SPN_HitDead\nSTA SPN_HP,X\nCLC\nRTS\nSPN_HitDead:\nLDA #$00\nSTA SPN_HP,X\nSTA SPN_ON,X\nSEC\nRTS\n";
    // SPN_Clear: every slot free
    _txt += "SPN_Clear:\nLDA #$00\nLDX #" + _last + "\nSPN_ClrLp:\nSTA SPN_ON,X\nSTA SPN_FIRE,X\nDEX\nBPL SPN_ClrLp\nRTS\n";
    // SPN_Free: X = a free slot, carry set = none
    _txt += "SPN_Free:\nLDX #" + _last + "\nSPN_FreeLp:\nLDA SPN_ON,X\nBEQ SPN_FreeOk\nDEX\nBPL SPN_FreeLp\nSEC\nRTS\nSPN_FreeOk:\nCLC\nRTS\n";
    // SPN_Start: launch type A at SPN_XL/XH/Y image in SPN_T0.. (X = slot set up by caller)
    //   in: X = slot, Y = type, SPN_T0/SPN_T1 = X lo/hi, A = Y
    _txt += "SPN_Start:\nSTA SPN_Y,X\nLDA SPN_T0\nSTA SPN_XL,X\nLDA SPN_T1\nSTA SPN_XH,X\nTYA\nSTA SPN_TYPE,X\nLDA SPN_T_HP,Y\nSTA SPN_HP,X\nLDA #$00\nSTA SPN_PH,X\nSTA SPN_FIRE,X\n";
    if (_a.axis == 1) {
        _txt += "LDA SPN_XL,X\nSTA SPN_BL,X\nLDA SPN_XH,X\nSTA SPN_BH,X\n";
    } else {
        _txt += "LDA SPN_Y,X\nSTA SPN_BL,X\n";
    }
    _txt += "LDA #$01\nSTA SPN_ON,X\nRTS\n";

    if (_a.axis < 2) {
        // SPN_Launch: record SPN_REC into a free slot (if there is one).
        // Screen position from the camera: X = 24 + 8 * (col - camx) + fineX,
        // Y = 47 + fineY + 8 * (row - camy + omitted top rows).
        _txt += "SPN_Launch:\nJSR SPN_Free\nBCC SPN_LaunchGo\nRTS\nSPN_LaunchGo:\nLDY SPN_REC\n";
        var _colsrc = (_a.axis == 0) ? "SPN_L1" : "SPN_L2";
        var _rowsrc = (_a.axis == 0) ? "SPN_L2" : "SPN_L1";
        _txt += ((_colsrc == "SPN_L1") ? "JSR SPN_Main\n" : "LDA " + _colsrc + ",Y\n") + "SEC\nSBC " + _camx + "\nSTA SPN_T0\nLDA #$00\nSTA SPN_T1\n";
        _txt += "ASL SPN_T0\nROL SPN_T1\nASL SPN_T0\nROL SPN_T1\nASL SPN_T0\nROL SPN_T1\n";
        _txt += "LDA SPN_T0\nCLC\nADC #$18\nSTA SPN_T0\nLDA SPN_T1\nADC #$00\nSTA SPN_T1\n";
        _txt += "LDA SPN_T0\nCLC\nADC " + _finex + "\nSTA SPN_T0\nLDA SPN_T1\nADC #$00\nSTA SPN_T1\n";
        _txt += ((_rowsrc == "SPN_L1") ? "JSR SPN_Main\n" : "LDA " + _rowsrc + ",Y\n") + "SEC\nSBC " + _camy + "\nCLC\nADC #" + scr_spawn_h2(_sc.omit_t) + "\nASL\nASL\nASL\nCLC\nADC #$2F\nCLC\nADC " + _finey + "\nPHA\n";
        _txt += "LDA SPN_LT,Y\nTAY\nPLA\nJMP SPN_Start\n";
        // SPN_Main: the record's column (H) / row (V) - or, when it had to
        // wait for a free slot (SPN_WAIT), the edge, so it flies in late
        // from the edge instead of popping up mid-screen
        _txt += "SPN_Main:\nLDA SPN_WAIT\nBEQ SPN_MainRec\nLDA SPN_EDGE\nRTS\nSPN_MainRec:\nLDA SPN_L1,Y\nRTS\n";
        // SPN_Edge: A = the map column / row just coming into view
        if (_a.axis == 0) {
            _txt += "SPN_Edge:\nLDA " + _camx + "\nCLC\nADC #$27\nRTS\n";
        } else {
            _txt += "SPN_Edge:\nLDA " + _camy + "\nBEQ SPN_EdgeTop\nSEC\nSBC #$01\nSPN_EdgeTop:\nRTS\n";   // row 0 stays 0 (no wrap to $FF)
        }
        // SPN_Reset: clear, then launch everything already on screen
        _txt += "SPN_Reset:\nJSR SPN_Clear\nLDA #$00\nSTA SPN_NEXT\nSTA SPN_WAIT\n";
        if (_a.axis == 0) {
            // skip what is left of the screen
            _txt += "SPN_RsSkip:\nLDY SPN_NEXT\nCPY SPN_COUNT\nBCS SPN_RsDone\nLDA SPN_L1,Y\nCMP " + _camx + "\nBCS SPN_RsDone\nINC SPN_NEXT\nJMP SPN_RsSkip\n";
        } else {
            // skip what is below the screen
            _txt += "SPN_RsSkip:\nLDY SPN_NEXT\nCPY SPN_COUNT\nBCS SPN_RsDone\nLDA " + _camy + "\nCLC\nADC #" + scr_spawn_h2(_rows_vis) + "\nCMP SPN_L1,Y\nBCS SPN_RsDone\nINC SPN_NEXT\nJMP SPN_RsSkip\n";
        }
        _txt += "SPN_RsDone:\nJSR SPN_Edge\nSTA SPN_EDGE\nJMP SPN_Spawn\n";
        // SPN_Spawn: launch every record up to the edge
        _txt += "SPN_Spawn:\nJSR SPN_Edge\n";
        if (_a.axis == 0) {
            // the camera wrapped back (looping map): start the list again,
            // skipping what would pop up in the middle of the screen
            _txt += "CMP SPN_EDGE\nSTA SPN_EDGE\nBCS SPN_SpLoop\nLDA #$00\nSTA SPN_NEXT\nSPN_WrSkip:\nLDY SPN_NEXT\nCPY SPN_COUNT\nBCS SPN_SpLoop\nLDA SPN_L1,Y\nCLC\nADC #$01\nCMP SPN_EDGE\nBCS SPN_SpLoop\nINC SPN_NEXT\nJMP SPN_WrSkip\n";
            _txt += "SPN_SpLoop:\nLDY SPN_NEXT\nCPY SPN_COUNT\nBCS SPN_SpDone\nLDA SPN_EDGE\nCMP SPN_L1,Y\nBCC SPN_SpDone\n";
        } else {
            _txt += "STA SPN_T0\nLDA SPN_EDGE\nCMP SPN_T0\nLDA SPN_T0\nSTA SPN_EDGE\nBCS SPN_SpLoop\nLDA #$00\nSTA SPN_NEXT\nSPN_WrSkip:\nLDY SPN_NEXT\nCPY SPN_COUNT\nBCS SPN_SpLoop\nLDA SPN_EDGE\nCLC\nADC #$01\nCMP SPN_L1,Y\nBCS SPN_SpLoop\nINC SPN_NEXT\nJMP SPN_WrSkip\n";
            _txt += "SPN_SpLoop:\nLDY SPN_NEXT\nCPY SPN_COUNT\nBCS SPN_SpDone\nLDA SPN_L1,Y\nCMP SPN_EDGE\nBCC SPN_SpDone\n";
        }
        // all slots busy: keep the record and try again next frame
        _txt += "JSR SPN_Free\nBCC SPN_SpGo\nLDA #$01\nSTA SPN_WAIT\nRTS\nSPN_SpGo:\nSTY SPN_REC\nINC SPN_NEXT\nJSR SPN_Launch\nJMP SPN_SpLoop\nSPN_SpDone:\nLDA #$00\nSTA SPN_WAIT\nRTS\n";
    } else {
        // ROOMS: A = room number
        _txt += "SPN_Room:\nPHA\nJSR SPN_Clear\nPLA\nTAY\nLDA SPN_ROFF,Y\nTAY\nJSR SPN_RByte\nSTA SPN_EDGE\nSPN_RmLoop:\nLDA SPN_EDGE\nBEQ SPN_RmDone\nDEC SPN_EDGE\n";
        _txt += "JSR SPN_Free\nBCS SPN_RmDone\n";
        // col -> X = 24 + 8 * col
        _txt += "JSR SPN_RByte\nSTA SPN_T0\nLDA #$00\nSTA SPN_T1\nASL SPN_T0\nROL SPN_T1\nASL SPN_T0\nROL SPN_T1\nASL SPN_T0\nROL SPN_T1\nLDA SPN_T0\nCLC\nADC #$18\nSTA SPN_T0\nLDA SPN_T1\nADC #$00\nSTA SPN_T1\n";
        _txt += "JSR SPN_RByte\nASL\nASL\nASL\nCLC\nADC #$32\nPHA\nJSR SPN_RByte\nSTY SPN_REC\nTAY\nPLA\nJSR SPN_Start\nLDY SPN_REC\nJMP SPN_RmLoop\nSPN_RmDone:\nRTS\n";
        _txt += "SPN_RByte:\nLDA SPN_RDAT,Y\nINY\nRTS\n";
        _txt += "SPN_Reset:\nLDA #$00\nJMP SPN_Room\n";
    }

    // SPN_Scroll: TURRET and WALKER are part of the map, so they ride the scroll
    if (_a.axis < 2) {
        _txt += "SPN_Scroll:\nLDX #" + _last + "\nSPN_ScLp:\nLDA SPN_ON,X\nBEQ SPN_ScNx\nLDY SPN_TYPE,X\nLDA SPN_T_MOVE,Y\nCMP #$05\nBCC SPN_ScNx\n";
        if (_a.axis == 0) {
            _txt += "LDA SPN_XL,X\nBNE SPN_ScLo\nDEC SPN_XH,X\nSPN_ScLo:\nDEC SPN_XL,X\n";
        } else {
            _txt += "INC SPN_Y,X\n";
        }
        _txt += "SPN_ScNx:\nDEX\nBPL SPN_ScLp\nRTS\n";
    }

    // SPN_Update: launch, then move every slot by its type's movement
    _txt += "SPN_Update:\nINC SPN_TICK\n";
    if (_a.axis < 2) _txt += "JSR SPN_Spawn\n";
    _txt += "LDX #" + _last + "\nSPN_UpLp:\nLDA #$00\nSTA SPN_FIRE,X\nLDA SPN_ON,X\nBNE SPN_UpGo\nJMP SPN_UpNx\nSPN_UpGo:\nINC SPN_PH,X\nLDY SPN_TYPE,X\nLDA SPN_T_MOVE,Y\nCMP #$05\nBCS SPN_UpSkipMain\n";
    // main axis: towards the player by SPEED (H: left, V: down, ROOMS: left)
    if (_a.axis == 1) {
        _txt += "LDA SPN_Y,X\nCLC\nADC SPN_T_SPEED,Y\nSTA SPN_Y,X\n";
    } else {
        _txt += "LDA SPN_XL,X\nSEC\nSBC SPN_T_SPEED,Y\nSTA SPN_XL,X\nLDA SPN_XH,X\nSBC #$00\nSTA SPN_XH,X\n";
    }
    _txt += "SPN_UpSkipMain:\nLDA SPN_T_MOVE,Y\nBEQ SPN_UpMoved\n";
    var _mv = ["SPN_MvSine", "SPN_MvChase", "SPN_MvZig", "SPN_MvDive", "SPN_MvWalk", "SPN_MvTurret"];
    for (var _k = 0; _k < array_length(_mv); _k++) {
        _txt += "CMP #" + scr_spawn_h2(_k + 1) + "\nBNE SPN_UpM" + string(_k) + "\nJSR " + _mv[_k] + "\nJMP SPN_UpMoved\nSPN_UpM" + string(_k) + ":\n";
    }
    _txt += "SPN_UpMoved:\n";
    // off screen? free the slot
    if (_a.axis == 1) {
        _txt += "LDA SPN_Y,X\nCMP #$FA\nBCC SPN_UpNx\nLDA #$00\nSTA SPN_ON,X\n";
    } else {
        _txt += "LDA SPN_XH,X\nBMI SPN_UpOff\nBNE SPN_UpRight\nLDA SPN_XL,X\nCMP #$04\nBCS SPN_UpNx\nJMP SPN_UpOff\nSPN_UpRight:\nLDA SPN_XL,X\nCMP #$78\nBCC SPN_UpNx\nSPN_UpOff:\nLDA #$00\nSTA SPN_ON,X\n";
    }
    _txt += "SPN_UpNx:\nDEX\nBMI SPN_UpDone\nJMP SPN_UpLp\nSPN_UpDone:\nRTS\n";

    // SPN_Cross: A = signed offset from the start line across the scroll
    if (_a.axis == 1) {
        _txt += "SPN_Cross:\nSTA SPN_T0\nLDY #$00\nCMP #$80\nBCC SPN_CrPos\nDEY\nSPN_CrPos:\nSTY SPN_T1\nLDA SPN_BL,X\nCLC\nADC SPN_T0\nSTA SPN_XL,X\nLDA SPN_BH,X\nADC SPN_T1\nSTA SPN_XH,X\nRTS\n";
        // step across towards the target: X (16-bit) by 1
        _txt += "SPN_Home:\nLDA SPN_XL,X\nCMP SPN_TGT_XL\nLDA SPN_XH,X\nSBC SPN_TGT_XH\nBCS SPN_HmLeft\nINC SPN_XL,X\nBNE SPN_HmDone\nINC SPN_XH,X\nRTS\nSPN_HmLeft:\nLDA SPN_XL,X\nCMP SPN_TGT_XL\nBEQ SPN_HmDone\nLDA SPN_XL,X\nBNE SPN_HmLo\nDEC SPN_XH,X\nSPN_HmLo:\nDEC SPN_XL,X\nSPN_HmDone:\nRTS\n";
    } else {
        _txt += "SPN_Cross:\nCLC\nADC SPN_BL,X\nSTA SPN_Y,X\nRTS\n";
        _txt += "SPN_Home:\nLDA SPN_Y,X\nCMP SPN_TGT_Y\nBEQ SPN_HmDone\nBCC SPN_HmDown\nDEC SPN_Y,X\nRTS\nSPN_HmDown:\nINC SPN_Y,X\nSPN_HmDone:\nRTS\n";
    }
    // movements - X = slot; each may use A / Y
    _txt += "SPN_MvNone:\nRTS\n";
    // SINE: start line + sine(phase), VALUE 0-3 = swing 4 / 8 / 16 / 32
    _txt += "SPN_MvSine:\nLDA SPN_PH,X\nAND #$3F\nTAY\nLDA SPN_SINE,Y\nSTA SPN_T0\nLDY SPN_TYPE,X\nLDA SPN_T_VAL,Y\nTAY\nLDA SPN_T0\nSPN_SnShift:\nCPY #$03\nBCS SPN_SnDone\nCMP #$80\nROR\nINY\nJMP SPN_SnShift\nSPN_SnDone:\nJMP SPN_Cross\n";
    // CHASE: one pixel towards the target every 1 / 2 / 4 / 8 frames
    _txt += "SPN_MvChase:\nLDY SPN_TYPE,X\nLDA SPN_T_VAL,Y\nTAY\nLDA SPN_ChMask,Y\nAND SPN_TICK\nBNE SPN_ChDone\nJMP SPN_Home\nSPN_ChDone:\nRTS\nSPN_ChMask:\n.byte $00,$01,$03,$07\n";
    // ZIGZAG: a triangle, VALUE 0-3 = swing 8 / 16 / 24 / 32
    _txt += "SPN_MvZig:\nLDA SPN_PH,X\nAND #$1F\nCMP #$10\nBCC SPN_ZgUp\nEOR #$1F\nSPN_ZgUp:\nSEC\nSBC #$08\nSTA SPN_T0\nLDY SPN_TYPE,X\nLDA SPN_T_VAL,Y\nTAY\nLDA SPN_T0\nCPY #$00\nBEQ SPN_ZgDone\nSPN_ZgMul:\nCLC\nADC SPN_T0\nDEY\nBNE SPN_ZgMul\nSPN_ZgDone:\nJMP SPN_Cross\n";
    // DIVE: straight for VALUE * 8 frames, then home in fast
    _txt += "SPN_MvDive:\nLDY SPN_TYPE,X\nLDA SPN_T_VAL,Y\nASL\nASL\nASL\nCMP SPN_PH,X\nBCS SPN_DvDone\nLDA #$FF\nCMP SPN_PH,X\nBNE SPN_DvGo\nDEC SPN_PH,X\nSPN_DvGo:\nJSR SPN_Home\nJSR SPN_Home\nSPN_DvDone:\nRTS\n";
    // WALKER: rides the map (SPN_Scroll) and walks towards the player
    _txt += "SPN_MvWalk:\nLDY SPN_TYPE,X\nLDA SPN_T_VAL,Y\nBEQ SPN_WkDone\nTAY\nLDA SPN_WkMask,Y\nAND SPN_TICK\nBNE SPN_WkDone\n";
    if (_a.axis == 1) {
        _txt += "INC SPN_Y,X\n";
    } else {
        _txt += "LDA SPN_XL,X\nBNE SPN_WkLo\nDEC SPN_XH,X\nSPN_WkLo:\nDEC SPN_XL,X\n";
    }
    _txt += "SPN_WkDone:\nRTS\nSPN_WkMask:\n.byte $00,$03,$01,$00\n";
    // TURRET: fixed to the map; SPN_FIRE,X = 1 for one frame every (VALUE+1)*16
    _txt += "SPN_MvTurret:\nLDY SPN_TYPE,X\nLDA SPN_T_VAL,Y\nTAY\nLDA SPN_PH,X\nAND #$0F\nBNE SPN_TuDone\nLDA SPN_PH,X\nLSR\nLSR\nLSR\nLSR\nAND SPN_TuMask,Y\nBNE SPN_TuDone\nLDA #$01\nSTA SPN_FIRE,X\nSPN_TuDone:\nRTS\nSPN_TuMask:\n.byte $00,$01,$03,$07\n";
    _txt += "SPN_Skip:\n";
    return _txt;
}

/// Compile case body: push the node's code onto the build list.
function scr_spawn_compile(_curr, _list) {
    var _parsed = scr_parse_asm_text(scr_spawn_asm(_curr));
    var _src_line = 0;
    for (var _pi = 0; _pi < array_length(_parsed); _pi++) {
        var _inst = _parsed[_pi];
        if (_inst[0] == "label") {
            array_push(_list, _inst);
        } else if (_inst[0] == "byte" && array_length(_inst) > 2) {
            for (var _bxi = 1; _bxi < array_length(_inst); _bxi++) array_push(_list, ["byte", _inst[_bxi], _curr]);
        } else {
            if (_inst[0] == "_line_map_") { _src_line = _inst[1]; continue; }
            if (_inst[0] == "const") continue;
            var _tagged = [_inst[0], _inst[1], _curr];
            if (array_length(_inst) > 2) array_push(_tagged, _inst[2]);
            _tagged[4] = _src_line;
            array_push(_list, _tagged);
        }
    }
    return _list;
}
