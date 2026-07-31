function scr_asset_sorted_indices() {
    var _count   = ds_list_size(asset_list);
    var _sorted  = array_create(_count, 0);
    for (var _i = 0; _i < _count; _i++) _sorted[_i] = _i;

    if (asset_sort_mode == "NAME") {
        array_sort(_sorted, function(_a, _b) {
            var _an = string_upper(ds_list_find_value(asset_list, _a).name);
            var _bn = string_upper(ds_list_find_value(asset_list, _b).name);
            return (_an == _bn) ? 0 : (_an < _bn ? -1 : 1);
        });
    } else if (asset_sort_mode == "TYPE") {
        array_sort(_sorted, function(_a, _b) {
            var _at = ds_list_find_value(asset_list, _a).type;
            var _bt = ds_list_find_value(asset_list, _b).type;
            if (_at == _bt) {
                var _an = string_upper(ds_list_find_value(asset_list, _a).name);
                var _bn = string_upper(ds_list_find_value(asset_list, _b).name);
                return (_an == _bn) ? 0 : (_an < _bn ? -1 : 1);
            }
            return (_at < _bt) ? -1 : 1;
        });
    } else if (asset_sort_mode == "ADDR") {
        array_sort(_sorted, function(_a, _b) {
            var _aa = ds_list_find_value(asset_list, _a);
            var _bb = ds_list_find_value(asset_list, _b);
            var _a_no_addr = (_aa.type == "LOAD_ORG" || _aa.type == "MUSIC_MAKER" || _aa.type == "BITMAP_BUILDER");
            var _b_no_addr = (_bb.type == "LOAD_ORG" || _bb.type == "MUSIC_MAKER" || _bb.type == "BITMAP_BUILDER");

            if (_a_no_addr != _b_no_addr) {
                return _a_no_addr ? -1 : 1;
            }
            if (_a_no_addr) {
                var _a_rank = (_aa.type == "LOAD_ORG") ? 0 : 1;
                var _b_rank = (_bb.type == "LOAD_ORG") ? 0 : 1;
                if (_a_rank != _b_rank) return _a_rank - _b_rank;
                if (_aa.type != _bb.type) return (_aa.type < _bb.type) ? -1 : 1;
                var _an = string_upper(_aa.name);
                var _bn = string_upper(_bb.name);
                return (_an == _bn) ? 0 : (_an < _bn ? -1 : 1);
            }
            if (_aa.address != _bb.address) return _aa.address - _bb.address;
            var _an2 = string_upper(_aa.name);
            var _bn2 = string_upper(_bb.name);
            return (_an2 == _bn2) ? 0 : (_an2 < _bn2 ? -1 : 1);
        });
    }

    return _sorted;
}