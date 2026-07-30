function scr_is_address_conflicted(_addr) {
    if (_addr == undefined || _addr < 0) return false;
    for (var i = 0; i < array_length(global.conflict_ranges); i++) {
        var _c = global.conflict_ranges[i];
        if (_addr >= _c.addr_start && _addr <= _c.addr_end) return true;
    }
    return false;
}