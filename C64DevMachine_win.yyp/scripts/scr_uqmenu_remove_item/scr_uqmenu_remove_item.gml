function scr_uqmenu_remove_item(_index) {
    if (_index < 0 || _index >= array_length(global.user_quick_menu)) {
        exit;
    }
    array_delete(global.user_quick_menu, _index, 1);
    scr_uqmenu_save();
}