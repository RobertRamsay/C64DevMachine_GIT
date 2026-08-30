// A conflict range is built as { addr_start: max(s1.start, s2.start),
// addr_end: min(s1.finish, s2.finish) } and a segment's `finish` is the byte
// AFTER the last one it owns. addr_end is therefore exclusive — which is how
// the memory bar reads it (obj_asset_manager Draw GUI: `_asset.address <
// _cr.addr_end`). This test used <= and so claimed one byte past the overlap.
//
// That extra byte is not harmless. Nodes sit end-to-start on the spine, so the
// first byte of the next node IS the exclusive end of the one before it. Any
// conflict ending at a node boundary painted the following node red as well —
// most visibly on a pair of freshly converted code blocks, which are always
// exactly adjacent.
function scr_is_address_conflicted(_addr) {
    if (_addr == undefined || _addr < 0) return false;
    for (var i = 0; i < array_length(global.conflict_ranges); i++) {
        var _c = global.conflict_ranges[i];
        if (_addr >= _c.addr_start && _addr < _c.addr_end) return true;
    }
    return false;
}