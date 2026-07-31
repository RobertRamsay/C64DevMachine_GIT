function scr_asset_save_file_resize(_asset, _size) {
    var _new_size = max(1, floor(_size));

    if (buffer_exists(_asset.buffer)) {
        buffer_delete(_asset.buffer);
    }
    _asset.buffer = buffer_create(_new_size, buffer_fixed, 1);
    buffer_fill(_asset.buffer, 0, buffer_u8, 0, _new_size);

    _asset.meta.save_file_size = _new_size;
    _asset.size = _new_size;
}