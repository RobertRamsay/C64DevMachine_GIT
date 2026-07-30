/// scr_sfx_data_get_instrument(_asset, _index)
/// Returns instrument struct at 0-based index, or noone.
function scr_sfx_data_get_instrument(_asset, _index) {
    if (!variable_struct_exists(_asset.meta, "instruments")) return noone;
    var _instrs = _asset.meta.instruments;
    if (_index < 0 || _index >= array_length(_instrs)) return noone;
    return _instrs[_index];
}