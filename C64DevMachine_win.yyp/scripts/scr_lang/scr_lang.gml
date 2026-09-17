/// scr_lang - UI language layer (English / Simplified Chinese).
///
/// Every UI text call in the project goes through the *_l wrappers below.
/// In English they fall straight through to the built-in. In Chinese they
/// look the WHOLE string up in lang_zh_CN.json (English -> Chinese) and swap
/// each font asset for its Noto Sans SC twin loaded with font_add().
/// Strings that are built by concatenation are wrapped piece-by-piece with
/// L("...") at the call site. 6502 mnemonics, emitted assembly, labels and
/// user text are never in the table, so they stay as typed.

// Script-scope defaults so the wrappers are safe before scr_lang_init() runs.
global.lang             = 0;      // 0 = English, 1 = Simplified Chinese
global.lang_unset       = false;  // true = no choice in the ini yet -> show picker
global.lang_map         = ds_map_create();
global.lang_font_map    = ds_map_create();
global.lang_missing     = ds_map_create();
global.lang_done        = ds_map_create(); // every Chinese value, so it is never logged as missing
global.lang_font_picker = -1;

#macro LANG_FONT_FILE  "C64DMResources/FONT/NotoSansSC-Medium-subset.ttf"
// Noto Sans SC sits lower in its line box than the C64 fonts, so top-aligned
// Chinese text is lifted by this many pixels. One number moves everything.
#macro LANG_Y_LIFT 4

#macro LANG_TABLE_FILE "C64DMResources/LANG/lang_zh_CN.json"

/// @desc Read the saved language, load the Chinese fonts and the table.
///       Call once, at the very top of obj_workspace_manager Create.
function scr_lang_init() {
    ini_open("c64devmachine.ini");
    var _saved = ini_read_string("Settings", "language", "");
    ini_close();

    global.lang       = 0;
    global.lang_unset = false;
    if (_saved == "zh") {
        global.lang = 1;
    } else if (_saved != "en") {
        global.lang_unset = true;
    }

    // Fonts are loaded in both languages: the first-run picker shows Chinese
    // before a language is chosen, and OPTIONS > LANGUAGE can switch live.
    if (file_exists(LANG_FONT_FILE)) {
        // [ base font asset, Chinese point size ]. The 7-8pt slots are bumped
        // because hanzi are not legible below roughly 9pt.
        var _pairs = [
            [ fnt_c64_nano,        9  ],
            [ fnt_c64_pico,        10 ],
            [ fnt_c64_tiny,        10 ],
            [ fnt_c64_opCode,      10 ],
            [ fnt_c64_code,        12 ],
            [ fnt_c64,             12 ],
            [ fnt_C64_Angled_tiny, 10 ],
            [ fnt_C64_Angled,      11 ],
            [ fnt_C64_Angled_big,  14 ],
            [ fnt_big,             20 ]
        ];
        for (var _i = 0; _i < array_length(_pairs); _i++) {
            var _zh = font_add(LANG_FONT_FILE, _pairs[_i][1], false, false, 32, 65519);
            if (font_exists(_zh)) {
                ds_map_set(global.lang_font_map, font_get_name(_pairs[_i][0]), _zh);
            }
        }
        global.lang_font_picker = font_add(LANG_FONT_FILE, 14, false, false, 32, 65519);
    }

    if (file_exists(LANG_TABLE_FILE)) {
        var _buf  = buffer_load(LANG_TABLE_FILE);
        var _json = buffer_read(_buf, buffer_text);
        buffer_delete(_buf);
        var _map = json_decode(_json);
        if (_map != -1) {
            ds_map_destroy(global.lang_map);
            global.lang_map = _map;
            var _vals = ds_map_values_to_array(_map);
            for (var _v = 0; _v < array_length(_vals); _v++) {
                ds_map_set(global.lang_done, _vals[_v], 1);
            }
        }
    }
}

/// @desc Switch language, remember it in the ini, force a re-layout.
/// @param {Real} _lang  0 = English, 1 = Chinese
function scr_lang_set(_lang) {
    global.lang       = _lang;
    global.lang_unset = false;
    ini_open("c64devmachine.ini");
    if (_lang == 1) {
        ini_write_string("Settings", "language", "zh");
    } else {
        ini_write_string("Settings", "language", "en");
    }
    ini_close();
    with (obj_c64_node) {
        height_dirty = true;
    }
}

/// @desc First-run picker. Reuses the Yes/No modal with its buttons
///       relabelled; the answer arrives as "lang_pick_yes" (English) or
///       "lang_pick_no" (Chinese) in global.question_result.
function scr_lang_show_picker() {
    scr_show_question("CHOOSE YOUR LANGUAGE\n\n请选择语言", "lang_pick");
    with (obj_question_box) {
        if (action == "lang_pick") {
            yes_label       = "ENGLISH";
            no_label        = "中文";
            use_picker_font = true;
        }
    }
}

/// @desc Translate a whole string. English, non-strings and anything not in
///       the table come back untouched.
function L(_s) {
    if (global.lang != 1) {
        return _s;
    }
    if (!is_string(_s)) {
        return _s;
    }
    var _t = ds_map_find_value(global.lang_map, _s);
    if (is_undefined(_t)) {
        // Already Chinese (an L() result passed through a *_l wrapper): done.
        if (ds_map_exists(global.lang_done, _s)) {
            return _s;
        }
        // Remember untranslated UI strings so they can be dumped on exit.
        // Anything with a digit in it is almost certainly a dynamic value.
        if (ds_map_size(global.lang_missing) < 4000) {
            if (string_length(_s) > 1 && string_length(_s) < 120 && string_digits(_s) == "") {
                ds_map_set(global.lang_missing, _s, 1);
            }
        }
        return _s;
    }
    return _t;
}

/// @desc Chinese mode only: write every string that had no translation to
///       lang_missing.txt in the save area. Call from Game End.
function scr_lang_dump_missing() {
    if (global.lang != 1) {
        return;
    }
    var _keys = ds_map_keys_to_array(global.lang_missing);
    array_sort(_keys, true);
    var _f = file_text_open_write("lang_missing.txt");
    for (var _i = 0; _i < array_length(_keys); _i++) {
        file_text_write_string(_f, string_replace_all(_keys[_i], "\n", "\\n"));
        file_text_writeln(_f);
    }
    file_text_close(_f);
}

/// @desc GameMaker only wraps draw_text_ext on spaces, and Chinese has none,
///       so in Chinese mode the line breaks are inserted by hand. Latin words
///       still break at the last space; hanzi break anywhere.
function scr_lang_wrap(_s, _w) {
    if (global.lang != 1) {
        return _s;
    }
    if (!is_string(_s) || _w <= 0) {
        return _s;
    }
    var _out  = "";
    var _line = "";
    var _n    = string_length(_s);
    for (var _i = 1; _i <= _n; _i++) {
        var _c = string_char_at(_s, _i);
        if (_c == "\n") {
            _out += _line + "\n";
            _line = "";
            continue;
        }
        if (_line != "" && string_width(_line + _c) > _w) {
            var _sp = string_last_pos(" ", _line);
            if (ord(_c) < 128 && _c != " " && _sp > 0) {
                _out += string_copy(_line, 1, _sp - 1) + "\n";
                _line = string_delete(_line, 1, _sp);
            } else {
                _out += _line + "\n";
                _line = "";
                if (_c == " ") {
                    continue;
                }
            }
        }
        _line += _c;
    }
    return _out + _line;
}

// ---------------------------------------------------------------------------
// Drop-in wrappers
// ---------------------------------------------------------------------------

function draw_set_font_l(_font) {
    if (global.lang == 1 && font_exists(_font)) {
        var _zh = ds_map_find_value(global.lang_font_map, font_get_name(_font));
        if (!is_undefined(_zh)) {
            draw_set_font(_zh);
            return;
        }
    }
    draw_set_font(_font);
}

/// @desc Pixels to lift text by: only in Chinese, only when top-aligned
///       (middle / bottom alignment already centres on the glyphs).
function scr_lang_lift() {
    if (global.lang != 1) {
        return 0;
    }
    if (draw_get_valign() != fa_top) {
        return 0;
    }
    return LANG_Y_LIFT;
}

function draw_text_l(_x, _y, _s) {
    draw_text(_x, _y - scr_lang_lift(), L(_s));
}

function draw_text_ext_l(_x, _y, _s, _sep, _w) {
    draw_text_ext(_x, _y - scr_lang_lift(), scr_lang_wrap(L(_s), _w), _sep, _w);
}

function draw_text_transformed_l(_x, _y, _s, _xs, _ys, _ang) {
    draw_text_transformed(_x, _y - scr_lang_lift() * _ys, L(_s), _xs, _ys, _ang);
}

function draw_text_ext_transformed_l(_x, _y, _s, _sep, _w, _xs, _ys, _ang) {
    draw_text_ext_transformed(_x, _y - scr_lang_lift() * _ys, scr_lang_wrap(L(_s), _w), _sep, _w, _xs, _ys, _ang);
}

function string_width_l(_s) {
    return string_width(L(_s));
}

function string_width_ext_l(_s, _sep, _w) {
    return string_width_ext(scr_lang_wrap(L(_s), _w), _sep, _w);
}

function string_height_ext_l(_s, _sep, _w) {
    return string_height_ext(scr_lang_wrap(L(_s), _w), _sep, _w);
}
