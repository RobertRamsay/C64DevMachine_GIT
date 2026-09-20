/// @function scr_asset_sorted_indices()
/// @description asset_list indices in panel display order.
///
/// Called once per frame by scr_asset_display_rows, which the draw event and
/// the hit-testing in Step_0 both go through. It used to re-sort the whole
/// list on every one of those calls, with comparators that did two
/// ds_list_find_value lookups and two string_upper conversions per
/// comparison. On a project with a few hundred assets that is thousands of
/// comparisons and many thousands of string conversions a frame, and it was
/// measured at roughly two thirds of the entire editor step.
///
/// Two changes. The sort keys are built once up front and the comparators
/// read plain arrays (decorate-sort-undecorate), and the finished order is
/// cached against a signature of everything the order depends on, so the
/// sort only runs again when the answer would actually differ.
///
/// @returns {array} A copy of the cached order, safe for the caller to keep.

function scr_asset_sorted_indices() {
    var _count = ds_list_size(asset_list);

    // Normalise the group field once, here, so nothing downstream has to test
    // for it. Assets from projects saved before grouping existed, and every
    // creation site that predates it, land as ungrouped. Group membership is
    // deliberately NOT part of the signature below: it changes which rows sit
    // under which header, which scr_asset_display_rows works out fresh each
    // frame, but it never changes this ordering.
    for (var _gi = 0; _gi < _count; _gi++) {
        var _ga = ds_list_find_value(asset_list, _gi);
        if (!variable_struct_exists(_ga, "group")) _ga.group = "";
        if (!is_string(_ga.group)) _ga.group = "";
    }

    // ---- SIGNATURE ----
    // One cheap pass. Anything that can move an asset in the order is here:
    // its name, its type, its address, how many there are, and the sort mode.
    var _stale = false;
    if (asset_sort_cache_mode != asset_sort_mode) _stale = true;
    if (array_length(asset_sort_sig_name) != _count) _stale = true;

    var _names = array_create(_count, "");
    var _types = array_create(_count, "");
    var _addrs = array_create(_count, 0);

    for (var _si = 0; _si < _count; _si++) {
        var _sa = ds_list_find_value(asset_list, _si);
        _names[_si] = _sa.name;
        _types[_si] = _sa.type;
        _addrs[_si] = _sa.address;

        if (!_stale) {
            if (_names[_si] != asset_sort_sig_name[_si]) {
                _stale = true;
            } else if (_types[_si] != asset_sort_sig_type[_si]) {
                _stale = true;
            } else if (_addrs[_si] != asset_sort_sig_addr[_si]) {
                _stale = true;
            }
        }
    }

    if (!_stale) {
        var _hit = array_create(_count, 0);
        for (var _hi = 0; _hi < _count; _hi++) {
            _hit[_hi] = asset_sort_cache[_hi];
        }
        return _hit;
    }

    // ---- REBUILD ----
    // Sort keys computed once per asset rather than twice per comparison.
    var _upper  = array_create(_count, "");
    var _noaddr = array_create(_count, false);
    var _rank   = array_create(_count, 0);

    for (var _ki = 0; _ki < _count; _ki++) {
        _upper[_ki] = string_upper(_names[_ki]);

        var _kt = _types[_ki];
        if (_kt == "LOAD_ORG" || _kt == "MUSIC_MAKER" || _kt == "BITMAP_BUILDER") {
            _noaddr[_ki] = true;
        } else {
            _noaddr[_ki] = false;
        }

        if (_kt == "LOAD_ORG") {
            _rank[_ki] = 0;
        } else {
            _rank[_ki] = 1;
        }
    }

    // A function literal in GML captures self, not the enclosing locals, so
    // the key arrays are handed to the comparator as its bound self.
    var _ctx = {
        u  : _upper,
        t  : _types,
        ad : _addrs,
        na : _noaddr,
        rk : _rank
    };

    var _sorted = array_create(_count, 0);
    for (var _i = 0; _i < _count; _i++) {
        _sorted[_i] = _i;
    }

    if (asset_sort_mode == "NAME") {
        array_sort(_sorted, method(_ctx, function(_a, _b) {
            var _an = u[_a];
            var _bn = u[_b];
            if (_an == _bn) {
                return 0;
            }
            if (_an < _bn) {
                return -1;
            }
            return 1;
        }));
    } else if (asset_sort_mode == "TYPE") {
        array_sort(_sorted, method(_ctx, function(_a, _b) {
            var _at = t[_a];
            var _bt = t[_b];
            if (_at == _bt) {
                var _an = u[_a];
                var _bn = u[_b];
                if (_an == _bn) {
                    return 0;
                }
                if (_an < _bn) {
                    return -1;
                }
                return 1;
            }
            if (_at < _bt) {
                return -1;
            }
            return 1;
        }));
    } else if (asset_sort_mode == "ADDR") {
        array_sort(_sorted, method(_ctx, function(_a, _b) {
            var _a_no = na[_a];
            var _b_no = na[_b];

            if (_a_no != _b_no) {
                if (_a_no) {
                    return -1;
                }
                return 1;
            }

            if (_a_no) {
                var _ar = rk[_a];
                var _br = rk[_b];
                if (_ar != _br) {
                    return _ar - _br;
                }
                var _at = t[_a];
                var _bt = t[_b];
                if (_at != _bt) {
                    if (_at < _bt) {
                        return -1;
                    }
                    return 1;
                }
                var _an = u[_a];
                var _bn = u[_b];
                if (_an == _bn) {
                    return 0;
                }
                if (_an < _bn) {
                    return -1;
                }
                return 1;
            }

            var _aa = ad[_a];
            var _bb = ad[_b];
            if (_aa != _bb) {
                return _aa - _bb;
            }
            var _an2 = u[_a];
            var _bn2 = u[_b];
            if (_an2 == _bn2) {
                return 0;
            }
            if (_an2 < _bn2) {
                return -1;
            }
            return 1;
        }));
    }

    asset_sort_cache      = _sorted;
    asset_sort_cache_mode = asset_sort_mode;
    asset_sort_sig_name   = _names;
    asset_sort_sig_type   = _types;
    asset_sort_sig_addr   = _addrs;

    // Hand back a copy. The cache is the authority, and a caller that sorted
    // or rewrote what it got back would silently corrupt every later frame.
    var _out = array_create(_count, 0);
    for (var _oi = 0; _oi < _count; _oi++) {
        _out[_oi] = _sorted[_oi];
    }
    return _out;
}
