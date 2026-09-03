/// @function scr_boot_resident_ranges()
/// @desc Address ranges of every asset that is BAKED INTO the program image
///       (i.e. emitted into p.bytes by the compile chain) rather than loaded
///       from disk at runtime.
///
/// WHY THIS EXISTS
/// The D64 BOOT trim scan walks the emitted bytes backwards looking for the
/// last real byte, skipping anything whose address falls inside a LOAD_ORG
/// asset's range — because those bytes arrive from disk, not from BOOT.
/// That test was keyed on ADDRESS ALONE, and addresses are not unique. A
/// resident BITMAP_3 sitting at $4000 shares its address with a LOAD_ORG
/// linked BITMAP that also targets $4000. Every byte of the resident bitmap
/// matched the LOAD_ORG range, every byte was skipped, and BOOT was cut off
/// at the end of the code (~$091C) with fourteen kilobytes of the payload
/// never written to the disk image. The first bitmap therefore never
/// displayed: it was never there.
///
/// The compile chain only emits an asset when it is NOT linked to a LOAD_ORG
/// (see the _load_org_linked gate in scr_compile_chain's asset pass), so the
/// same rule defines residency here. A byte inside a LOAD_ORG range AND
/// inside a resident range belongs to the resident asset and must be kept.
///
/// Ranges may over-claim by a couple of bytes (buffer sizes include the
/// 2-byte PRG header). That is the safe direction: the trim scan's zero
/// check still discards genuine padding, so an over-claimed tail costs
/// nothing while an under-claimed one truncates BOOT again.
///
/// @return {Array<Struct>} array of { s : start_address, e : end_address }
function scr_boot_resident_ranges() {
    var _ranges = [];
    if (!instance_exists(obj_asset_manager)) return _ranges;

    var _am = obj_asset_manager;

    // Names linked to any deferred container. LOAD_REU is included for the
    // same reason as LOAD_ORG — the data lives off-image until pulled in.
    var _deferred = ds_map_create();
    for (var _di = 0; _di < ds_list_size(_am.asset_list); _di++) {
        var _da = ds_list_find_value(_am.asset_list, _di);
        if (_da.type != "LOAD_ORG" && _da.type != "LOAD_REU") continue;
        if (!variable_struct_exists(_da, "linked_assets")) continue;
        var _dlinks = _da.linked_assets;
        for (var _dli = 0; _dli < array_length(_dlinks); _dli++) {
            var _dlnk = _dlinks[_dli];
            if (!variable_struct_exists(_dlnk, "asset_name")) continue;
            if (_dlnk.asset_name == "") continue;
            ds_map_replace(_deferred, _dlnk.asset_name, true);
        }
    }

    for (var _ai = 0; _ai < ds_list_size(_am.asset_list); _ai++) {
        var _a = ds_list_find_value(_am.asset_list, _ai);
        if (_a.type == "LOAD_ORG") continue;
        if (_a.type == "LOAD_REU") continue;
        if (ds_map_exists(_deferred, _a.name)) continue;
        if (!buffer_exists(_a.buffer)) continue;

        // A bitmap is three separate physical blocks, not one lump. Claim
        // each one — scr_bmp_regions is the single source of truth.
        if (_a.type == "BITMAP" || _a.type == "BITMAP_KLA") {
            var _br = scr_bmp_regions(_a.address);
            array_push(_ranges, { s: _br.bmp_addr, e: _br.bmp_addr + _br.bmp_size });
            array_push(_ranges, { s: _br.scr_addr, e: _br.scr_addr + _br.scr_size });
            array_push(_ranges, { s: _br.col_addr, e: _br.col_addr + _br.col_size });
            continue;
        }

        var _sz = buffer_get_size(_a.buffer);
        if (_sz <= 0) continue;
        array_push(_ranges, { s: _a.address, e: _a.address + _sz });
    }

    ds_map_destroy(_deferred);
    return _ranges;
}
