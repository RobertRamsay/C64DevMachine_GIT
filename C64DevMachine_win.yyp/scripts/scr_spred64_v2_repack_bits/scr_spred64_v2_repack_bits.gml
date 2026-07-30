/// @function scr_spred64_v2_repack_bits(_asset)
/// @desc Writes the working bit array (spred64_v2.bits) back into the
///       asset's packed-byte buffer in C64 sprite format (64 bytes per
///       slot, 63 bytes of pixel data + 1 padding byte). Sizes the buffer
///       to used_count slots only — never a full bank of 64 — so blank
///       trailing sprites never reach the PRG.
function scr_spred64_v2_repack_bits(_asset) {
    var _bits     = obj_asset_manager.spred64_v2.bits;
    var _used     = clamp(obj_asset_manager.spred64_v2.used_count, 1, 64);
    var _required = _used * 64;  // used slots * 64 bytes per slot

    // Allocate fresh at the exact size, or resize an existing buffer to match.
    if (!buffer_exists(_asset.buffer)) {
        _asset.buffer = buffer_create(_required, buffer_fixed, 1);
    } else if (buffer_get_size(_asset.buffer) != _required) {
        buffer_resize(_asset.buffer, _required);
    }

    for (var _slot = 0; _slot < _used; _slot++) {
        var _byte_base = _slot * 64;
        var _bit_base  = _slot * 504;
        // 63 pixel-data bytes
        for (var _b = 0; _b < 63; _b++) {
            var _val = 0;
            for (var _bp = 0; _bp < 8; _bp++) {
                if (_bits[_bit_base + _b * 8 + _bp] == 1) {
                    _val = _val | (128 >> _bp);
                }
            }
            buffer_poke(_asset.buffer, _byte_base + _b, buffer_u8, _val);
        }
        // Byte 63 — padding. Colour state lives in meta, not here.
        buffer_poke(_asset.buffer, _byte_base + 63, buffer_u8, 0);
    }
}