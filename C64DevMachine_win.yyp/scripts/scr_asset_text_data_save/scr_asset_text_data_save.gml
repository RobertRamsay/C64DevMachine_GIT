/// @function scr_asset_text_data_save(asset)
function scr_asset_text_data_save(_asset) {
    var _txt = _asset.meta.inline_edit_text;

    // Store on meta for preview
    _asset.meta.text = _txt;

    // Write to buffer as string + null terminator
    var _byte_len = string_byte_length(_txt) + 1;
    if (buffer_exists(_asset.buffer)) buffer_delete(_asset.buffer);
    _asset.buffer = buffer_create(_byte_len, buffer_fixed, 1);
    buffer_write(_asset.buffer, buffer_string, _txt);
}