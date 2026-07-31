function scr_uqmenu_save() {
    var _s = "";
    for (var _i = 0; _i < array_length(global.user_quick_menu); _i++) {
        var _it = global.user_quick_menu[_i];
        if (_i > 0) _s += "|";
        _s += _it.type + "," + _it.label;
    }
    ini_open("c64devmachine.ini");
    ini_write_string("QuickMenu", "items", _s);
    ini_close();
}