/// @desc Convert TEXT_DATA asset string → scroll-ready byte buffer
/// Encodes commands: _spdNN _colNN _wait _trkNN + normal screencodes
/// This matches the byte encoding used by MACRO_TEXT_SCROLL compile case exactly.
function scr_asset_text_flush(_asset) {
    var _str = (variable_struct_exists(_asset, "meta") &&
                variable_struct_exists(_asset.meta, "text"))
               ? string(_asset.meta.text) : "";

    _str = string_replace_all(_str, "\n", "");
    _str = string_replace_all(_str, "\r", "");

    var _bytes = [];
    var _si    = 1;

    while (_si <= string_length(_str)) {
        if (string_char_at(_str, _si) == "_") {
            var _cmd     = string_copy(_str, _si, 7);
            var _matched = false;

            // _spdNN (01-07)
            if (string_copy(_cmd, 1, 4) == "_spd") {
                var _sn = string_copy(_str, _si + 4, 2);
                if (string_digits(_sn) == _sn && string_length(_sn) == 2) {
                    array_push(_bytes, 0xF8 + clamp(real(_sn), 1, 7));
                    _si += 6; _matched = true;
                }
            }
            // _colNN (00-15)
            if (!_matched && string_copy(_cmd, 1, 4) == "_col") {
                var _cn = string_copy(_str, _si + 4, 2);
                if (string_digits(_cn) == _cn && string_length(_cn) == 2) {
                    array_push(_bytes, 0xE0 + clamp(real(_cn), 0, 15));
                    _si += 6; _matched = true;
                }
            }
            // _wait
            if (!_matched && string_copy(_str, _si, 5) == "_wait") {
                array_push(_bytes, 0xDF);
                _si += 5; _matched = true;
            }
            // _trkNN (00-14)
            if (!_matched && string_copy(_str, _si, 4) == "_trk") {
                var _tn = string_copy(_str, _si + 4, 2);
                if (string_digits(_tn) == _tn && string_length(_tn) == 2) {
                    array_push(_bytes, 0xD0 + clamp(real(_tn), 0, 14));
                    _si += 6; _matched = true;
                }
            }
            if (_matched) continue;
        }

        // Normal char → screencode (same mapping as compile case)
        var _b = string_ord_at(_str, _si);
        if      (_b >= 65  && _b <= 90)  _b -= 64;        // A-Z
        else if (_b >= 97  && _b <= 122) _b -= 96;        // a-z
        else if (_b == 163 || _b == 100) _b = 28;         // £
        // 32-64, 91-95 pass through unchanged
        array_push(_bytes, _b);
        _si++;
    }
    array_push(_bytes, 0x00); // null terminator

    var _len = array_length(_bytes);
    if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);
    _asset.buffer = buffer_create(_len, buffer_fixed, 1);
    buffer_seek(_asset.buffer, buffer_seek_start, 0);
    for (var _i = 0; _i < _len; _i++) {
        buffer_write(_asset.buffer, buffer_u8, _bytes[_i]);
    }
}