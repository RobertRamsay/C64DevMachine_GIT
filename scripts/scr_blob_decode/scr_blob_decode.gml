function scr_blob_decode(_blob) {
    // Decodes a save blob into a new buffer_fixed of exact byte length.
    // "b64:" prefix => base64 (HYBRID); otherwise => legacy hex string.
    // Returns noone for empty/missing input.
    if (!is_string(_blob)) return noone;
    if (string_length(_blob) == 0) return noone;

    if (string_copy(_blob, 1, 4) == "b64:") {
        var _b64  = string_delete(_blob, 1, 4);
        var _grow = buffer_base64_decode(_b64);
        var _sz   = buffer_get_size(_grow);
        var _buf  = buffer_create(_sz, buffer_fixed, 1);
        buffer_copy(_grow, 0, _sz, _buf, 0);
        buffer_delete(_grow);
        return _buf;
    }

    // Legacy hex path
    var _byte_len = string_length(_blob) div 2;
    var _buf = buffer_create(_byte_len, buffer_fixed, 1);
    buffer_seek(_buf, buffer_seek_start, 0);
    for (var _b = 0; _b < _byte_len; _b++) {
        var _hex = string_copy(_blob, 1 + (_b * 2), 2);
        buffer_write(_buf, buffer_u8, hex_to_decimal(string_upper(_hex)));
    }
    return _buf;
}