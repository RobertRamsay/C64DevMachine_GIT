/// =============================================================
/// scr_nloc_display_name(name)
/// Returns the var's original declared-case display name (from meta),
/// or the input unchanged if no meta entry exists. Use this everywhere
/// a var name is DRAWN, since instructions[0][1] itself is stored
/// uppercase for case-insensitive matching.
/// =============================================================
function scr_nloc_display_name(_name) {
    if (_name == "") return _name;
    var _m = scr_nloc_find_meta(_name);
    return (_m != undefined) ? _m.name : _name;
}