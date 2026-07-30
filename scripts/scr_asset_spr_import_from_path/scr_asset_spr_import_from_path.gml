/// @desc scr_asset_spr_import_from_path(_asset, _path)
/// Imports a raw binary sprite file directly from a known path.
/// Same as scr_asset_spr_import binary branch but without the file dialog.
function scr_asset_spr_import_from_path(_asset, _path) {

    if (!file_exists(_path)) exit;

    var _buf = buffer_load(_path);
    if (!buffer_exists(_buf)) exit;

    var _sprites    = array_create(64, "");
    var _sprite_mcs = array_create(64, 0);
    var _sprite_ucs = array_create(64, 1);

var _buf_size    = buffer_get_size(_buf);
    var _max_sprites = 64; // always read full 64 — Spred64 always writes 64 sprites

    for (var _si = 0; _si < _max_sprites; _si++) {
        var _base  = _si * 64;
        var _bytes = "";
        for (var _bi = 0; _bi < 64; _bi++) {
            buffer_seek(_buf, buffer_seek_start, _base + _bi);
            var _val = buffer_read(_buf, buffer_u8);
            if (_bi == 63) {
                _sprite_mcs[_si] = (_val >> 7) & 1;
                _val = 0;
            }
            if (_bytes != "") _bytes += ",";
            _bytes += string(_val);
        }
        _sprites[_si] = _bytes;
    }
    buffer_delete(_buf);

    // Auto-detect used count
    var _used_count = 0;
    for (var _si = 63; _si >= 0; _si--) {
        if (_sprites[_si] == "") continue;
        var _vals     = string_split(_sprites[_si], ",");
        var _has_data = false;
        for (var _vi = 0; _vi < array_length(_vals); _vi++) {
            var _t = string_trim(_vals[_vi]);
            if (_t != "" && real(_t) != 0) { _has_data = true; break; }
        }
        if (_has_data) { _used_count = _si + 1; break; }
    }
    if (_used_count == 0) _used_count = 1;
    // Trim meta arrays so no blank-slot state is carried past used_count
    array_resize(_sprite_mcs, _used_count);
    array_resize(_sprite_ucs, _used_count);
    // Build buffer
    var _sprite_buf = buffer_create(_used_count * 64, buffer_fixed, 1);
    buffer_seek(_sprite_buf, buffer_seek_start, 0);
    for (var _si = 0; _si < _used_count; _si++) {
        var _s_data = _sprites[_si];
        if (_s_data == "") {
            repeat(64) buffer_write(_sprite_buf, buffer_u8, 0);
        } else {
            var _vals = string_split(_s_data, ",");
            for (var _vi = 0; _vi < 64; _vi++) {
                var _v = (_vi < array_length(_vals)) ? real(string_trim(_vals[_vi])) : 0;
                buffer_write(_sprite_buf, buffer_u8, _v);
            }
        }
    }

    // Build hex blob
    var _hex_blob = "";
    buffer_seek(_sprite_buf, buffer_seek_start, 0);
    repeat(_used_count * 64) {
        _hex_blob += decimal_to_hex(buffer_read(_sprite_buf, buffer_u8));
    }

    // Build JSON
    // Meta arrays resized to _used_count above, so bound the loop to that length.
    var _json = "[";
    var _json_count = array_length(_sprite_mcs);
    for (var _si = 0; _si < _json_count; _si++) {
        if (_si > 0) _json += ",";
        _json += "{\"b\":\"" + _sprites[_si] + "\",\"mc\":" + string(_sprite_mcs[_si]) + ",\"uc\":" + string(_sprite_ucs[_si]) + "}";
    }
    _json += "]";

   // Clean up old cache
    if (variable_struct_exists(_asset.meta, "spr_sprites")) {
        var _old_len = array_length(_asset.meta.spr_sprites);
        for (var _si = 0; _si < _old_len; _si++) {
            if (_asset.meta.spr_sprites[_si] != -1 &&
                sprite_exists(_asset.meta.spr_sprites[_si]))
                sprite_delete(_asset.meta.spr_sprites[_si]);
        }
    }
    if (variable_struct_exists(_asset.meta, "preview_surf") &&
        surface_exists(_asset.meta.preview_surf))
        surface_free(_asset.meta.preview_surf);
    if (buffer_exists(_asset.buffer))
        buffer_delete(_asset.buffer);
    // Store
    _asset.buffer = _sprite_buf;
    _asset.meta = {
        format      : "binary",
        has_colour  : false,
        bg_col      : 0,
        mc1_col     : 1,
        mc2_col     : 2,
        sprite_json : _json,
        sprite_mcs  : _sprite_mcs,
        sprite_ucs  : _sprite_ucs,
        found_count : _used_count,
        found_count : _used_count,
        used_count  : _used_count,
        hex_blob    : _hex_blob,
        total_size  : _used_count * 64
    };
    scr_asset_spr_cache_sprites(_asset, true);
}