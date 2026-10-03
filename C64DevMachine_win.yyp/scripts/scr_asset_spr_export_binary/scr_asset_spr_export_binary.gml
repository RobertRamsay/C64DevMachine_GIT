/// @desc Writes a SPRITE_SET asset to a raw binary file: 64 bytes a sprite as
///       it sits in C64 memory, for the used sprites only. Byte 63 of each
///       sprite carries the SpritePad attribute (bit 7 multicolour, bits 0-3
///       colour), which the VIC never reads.
function scr_asset_spr_export_binary(_asset, _path) {
    var _n = max(1, scr_asset_spr_export_count(_asset));
    var _bsz = 0;
    if (buffer_exists(_asset.buffer)) {
        _bsz = buffer_get_size(_asset.buffer);
    }
    var _out = buffer_create(_n * 64, buffer_fixed, 1);
    for (var _si = 0; _si < _n; _si++) {
        for (var _bi = 0; _bi < 63; _bi++) {
            var _v = 0;
            if (_si * 64 + _bi < _bsz) {
                _v = buffer_peek(_asset.buffer, _si * 64 + _bi, buffer_u8);
            }
            buffer_poke(_out, _si * 64 + _bi, buffer_u8, _v);
        }
        buffer_poke(_out, _si * 64 + 63, buffer_u8, scr_asset_spr_export_attr(_asset, _si));
    }
    buffer_save(_out, _path);
    buffer_delete(_out);
}
