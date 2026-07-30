/// @function scr_spred64_v2_unpack_bits(_asset)
/// @desc Reads the SPRITE_SET asset's packed-byte buffer and produces a
///       flat 1-bit-per-pixel array (504 bits per slot, 64 slots).
///       Returns the array.
///
///       C64 sprite layout in the buffer: each sprite occupies 64 bytes
///       (63 bytes of pixel data — 24 wide x 21 high / 8 bits per byte —
///       plus 1 byte of padding/colour metadata at byte 63).
function scr_spred64_v2_unpack_bits(_asset) {

    var _bits = array_create(64 * 504, 0);

    if (!buffer_exists(_asset.buffer)) return _bits;

    var _bsz = buffer_get_size(_asset.buffer);

    var _rt_used    = clamp(variable_struct_exists(_asset.meta, "used_count") ? _asset.meta.used_count : 1, 1, 64);
    var _rt_mcs_len = array_length(_asset.meta.sprite_mcs);
    var _rt_ucs_len = array_length(_asset.meta.sprite_ucs);
    for (var _slot = 0; _slot < _rt_used; _slot++) {

        var _byte_base = _slot * 64;
        if (_byte_base >= _bsz) break;

        var _bit_base = _slot * 504;

        // 63 bytes of pixel data per sprite
        for (var _b = 0; _b < 63; _b++) {

            var _byte_off = _byte_base + _b;
            if (_byte_off >= _bsz) break;

            var _val = buffer_peek(_asset.buffer, _byte_off, buffer_u8);

            // High bit first — bit 7 is leftmost pixel in the row
            for (var _bp = 0; _bp < 8; _bp++) {
                var _on = (_val & (128 >> _bp)) ? 1 : 0;
                _bits[_bit_base + _b * 8 + _bp] = _on;
            }
        }
    }

    return _bits;
}