/// @desc Returns the ordered array of C64 Kernal routine pseudo-labels.
///       Each entry: { name, addr }. Used by the JSR picker and compiler.
function scr_kernal_routine_list() {
    var _list = [
        { name: "CHROUT",  addr: 0xFFD2 },
        { name: "CHRIN",   addr: 0xFFCF },
        { name: "GETIN",   addr: 0xFFE4 },
        { name: "CLRSCR",  addr: 0xE544 },
        { name: "SCNKEY",  addr: 0xFF9F },
        { name: "STOP",    addr: 0xFFE1 },
        { name: "PLOT",    addr: 0xFFF0 },
        { name: "SETLFS",  addr: 0xFFBA },
        { name: "SETNAM",  addr: 0xFFBD },
        { name: "LOAD",    addr: 0xFFD5 },
        { name: "SAVE",    addr: 0xFFD8 },
        { name: "OPEN",    addr: 0xFFC0 },
        { name: "CLOSE",   addr: 0xFFC3 },
        { name: "CHKIN",   addr: 0xFFC6 },
        { name: "CHKOUT",  addr: 0xFFC9 },
        { name: "CLRCHN",  addr: 0xFFCC },
        { name: "READST",  addr: 0xFFB7 },
        { name: "SETMSG",  addr: 0xFF90 },
        { name: "CINT",    addr: 0xFF81 },
        { name: "IOINIT",  addr: 0xFF84 },
        { name: "RAMTAS",  addr: 0xFF87 },
        { name: "RESTOR",  addr: 0xFF8A }
    ];
    return _list;
}

/// @desc Resolve a Kernal routine name to its address.
///       Returns -1 if the name is not a Kernal routine.
function scr_kernal_routine_addr(_name) {
    var _list = scr_kernal_routine_list();
    for (var _i = 0; _i < array_length(_list); _i++) {
        if (_list[_i].name == _name) {
            return _list[_i].addr;
        }
    }
    return -1;
}