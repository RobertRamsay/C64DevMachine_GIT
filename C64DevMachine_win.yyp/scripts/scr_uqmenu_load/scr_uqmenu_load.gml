function scr_uqmenu_load() {
    ini_open("c64devmachine.ini");
    var _s = ini_read_string("QuickMenu", "items", "");
    ini_close();

    global.user_quick_menu = [];
    if (_s == "") {
        exit;
    }

    var _pairs = string_split(_s, "|");
    for (var _i = 0; _i < array_length(_pairs); _i++) {
        var _parts = string_split(_pairs[_i], ",");
        if (array_length(_parts) >= 2) {
            array_push(global.user_quick_menu, { type: _parts[0], label: _parts[1] });
        }
    }
}