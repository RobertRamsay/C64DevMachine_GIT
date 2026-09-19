/// @function scr_asset_display_rows()
/// @description The asset panel's row list, in display order, including group
///              headers. Draw_64 renders this and Step_0 hit-tests against it,
///              so the two can never disagree about what is on screen.
///
///              Each entry is one of:
///                { kind: "group", idx: -1, group: <name>, count: n, open: bool }
///                { kind: "asset", idx: <asset_list index>, group: <name or ""> }
///
///              A group is a name in obj_asset_manager.asset_groups. It lives
///              there rather than in asset_list on purpose: nothing that walks
///              the asset list — the compile chain, the memory bar, the asset
///              pickers, the address sort — ever has to know groups exist.

function scr_asset_display_rows() {
    var _sorted = scr_asset_sorted_indices();
    var _rows   = [];

    // Group membership counts, and the order groups first appear in the sort.
    var _counts = ds_map_create();
    var _order  = [];
    for (var _p = 0; _p < array_length(_sorted); _p++) {
        var _g = ds_list_find_value(asset_list, _sorted[_p]).group;
        if (_g == "") continue;
        if (!ds_map_exists(_counts, _g)) {
            ds_map_add(_counts, _g, 0);
            array_push(_order, _g);
        }
        _counts[? _g] = _counts[? _g] + 1;
    }

    // Registered groups that hold nothing still get a row, so a group created
    // from the panel has somewhere to drop assets onto.
    for (var _ri = 0; _ri < array_length(asset_groups); _ri++) {
        var _rg = asset_groups[_ri];
        if (ds_map_exists(_counts, _rg)) continue;
        ds_map_add(_counts, _rg, 0);
        array_push(_order, _rg);
    }

    // Groups first, in the order above, each header followed by its members
    // when open. Keeping them at the top stops a long open group from burying
    // the loose assets underneath it.
    for (var _oi = 0; _oi < array_length(_order); _oi++) {
        var _gn   = _order[_oi];
        var _open = ds_map_exists(asset_group_open, _gn);
        array_push(_rows, {
            kind  : "group",
            idx   : -1,
            group : _gn,
            count : _counts[? _gn],
            open  : _open
        });
        if (!_open) continue;
        for (var _q = 0; _q < array_length(_sorted); _q++) {
            var _mi = _sorted[_q];
            if (ds_list_find_value(asset_list, _mi).group != _gn) continue;
            array_push(_rows, { kind: "asset", idx: _mi, group: _gn });
        }
    }

    // Then everything ungrouped, in sort order.
    for (var _u = 0; _u < array_length(_sorted); _u++) {
        var _ui = _sorted[_u];
        if (ds_list_find_value(asset_list, _ui).group != "") continue;
        array_push(_rows, { kind: "asset", idx: _ui, group: "" });
    }

    ds_map_destroy(_counts);
    return _rows;
}
