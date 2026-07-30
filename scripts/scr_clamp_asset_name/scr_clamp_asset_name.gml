/// @desc Clamp an asset name to a max length (default 15), trimming trailing
///       underscores so we never leave a dangling separator after the cut.
function scr_clamp_asset_name(_name, _max) {
    _max = _max ?? 15;
    if (string_length(_name) <= _max) return _name;
    var _cut = string_copy(_name, 1, _max);
    // Don't leave a trailing "_" after truncation.
    while (string_length(_cut) > 0 && string_char_at(_cut, string_length(_cut)) == "_") {
        _cut = string_copy(_cut, 1, string_length(_cut) - 1);
    }
    return _cut;
}