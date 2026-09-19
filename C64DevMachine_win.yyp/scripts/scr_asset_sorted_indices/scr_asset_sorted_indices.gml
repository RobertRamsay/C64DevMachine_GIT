function scr_asset_sorted_indices() {
    var _count   = ds_list_size(asset_list);
    var _sorted  = array_create(_count, 0);
    for (var _i = 0; _i < _count; _i++) _sorted[_i] = _i;

    // Normalise the group field once, here, so nothing downstream has to test
    // for it. Assets from projects saved before grouping existed, and every
    // creation site that predates it, land as ungrouped.
    for (var _gi = 0; _gi < _count; _gi++) {
        var _ga = ds_list_find_value(asset_list, _gi);
        if (!variable_struct_exists(_ga, "group")) _ga.group = "";
        if (!is_string(_ga.group)) _ga.group = "";
    }

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

    // ---- GROUPING --------------------------------------------------------
    // Members of a group are pulled together behind whichever of them sorts
    // first, so a group stays contiguous in every sort mode. A closed group
    // contributes only that first row — Draw_64 renders it as the group
    // header, and because Step_0 hit-tests against this same array the two can
    // never disagree about what is on screen.
    var _display = [];
    var _seen    = ds_map_create();
    for (var _p = 0; _p < array_length(_sorted); _p++) {
        var _idx = _sorted[_p];
        var _g   = ds_list_find_value(asset_list, _idx).group;

        if (_g == "") {
            array_push(_display, _idx);
            continue;
        }
        if (ds_map_exists(_seen, _g)) continue;
        ds_map_add(_seen, _g, true);

        // Absent from asset_group_open means closed, so a freshly imported
        // group arrives folded without anything having to set a flag.
        var _open = ds_map_exists(asset_group_open, _g);

        for (var _q = _p; _q < array_length(_sorted); _q++) {
            var _mi = _sorted[_q];
            if (ds_list_find_value(asset_list, _mi).group != _g) continue;
            array_push(_display, _mi);
            if (!_open) break;
        }
    }
    ds_map_destroy(_seen);

    return _display;
}