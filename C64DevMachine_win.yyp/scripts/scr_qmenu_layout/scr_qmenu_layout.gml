function scr_qmenu_layout(_index, _cx, _cy) {
    var _btn_w = 100;
    var _btn_h = 24;

    // Circular ring, sized off the item list itself so adding/removing a
    // fixed entry here (e.g. COPY VAR) just reflows the ring automatically.
    // Same radius growth as the Q custom menu's single-ring tier, so the
    // two menus feel consistent at the same item count.
    var _count  = array_length(qmenu_items);
    var _radius = 90 + max(0, _count - 5) * 10;
    var _angle  = 90 - (_index * (360 / _count)); // index 0 sits at the top (90°)

    var _cx2 = _cx + lengthdir_x(_radius, _angle);
    var _cy2 = _cy + (lengthdir_y(_radius, _angle) )*.6;

    return [_cx2 - (_btn_w / 2), _cy2 - (_btn_h / 2), _cx2 + (_btn_w / 2), _cy2 + (_btn_h / 2)];
}