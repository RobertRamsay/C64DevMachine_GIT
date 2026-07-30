/// @desc Writes SPRITE_SET asset to a raw binary file with correct MC mode bytes
function scr_asset_spr_export_binary(_asset, _path) {

    var _mcs     = variable_struct_exists(_asset.meta, "sprite_mcs") ? _asset.meta.sprite_mcs : array_create(64, 0);
    var _mcs_len = array_length(_mcs);
    var _buf_size = buffer_exists(_asset.buffer) ? buffer_get_size(_asset.buffer) : 0;
    var _out = buffer_create(64 * 64, buffer_fixed, 1);
    buffer_seek(_out, buffer_seek_start, 0);
    for (var _si = 0; _si < 64; _si++) {
        var _slot_mc = (_si < _mcs_len) ? _mcs[_si] : 0;
        var _base = _si * 64;
        // Write 63 pixel bytes
        for (var _bi = 0; _bi < 63; _bi++) {
            var _val = 0;
            if (_buf_size >= _base + _bi + 1) {
                buffer_seek(_asset.buffer, buffer_seek_start, _base + _bi);
                _val = buffer_read(_asset.buffer, buffer_u8);
            }
            buffer_seek(_out, buffer_seek_start, _base + _bi);
            buffer_write(_out, buffer_u8, _val);
        }
        // Write mode byte 63: 0=hires, 128=multicolour
        buffer_seek(_out, buffer_seek_start, _base + 63);
        buffer_write(_out, buffer_u8, (_slot_mc == 1) ? 128 : 0);
    }

    buffer_save(_out, _path);
    buffer_delete(_out);
}