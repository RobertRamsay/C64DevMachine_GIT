function scr_uqmenu_add_item(_type, _label) {
    for (var _i = 0; _i < array_length(global.user_quick_menu); _i++) {
        if (global.user_quick_menu[_i].type == _type) {
            return false;
        }
    }
    if (array_length(global.user_quick_menu) >= 24) {
        return false;
    }
    array_push(global.user_quick_menu, { type: _type, label: _label });
    scr_uqmenu_save();
    return true;
}