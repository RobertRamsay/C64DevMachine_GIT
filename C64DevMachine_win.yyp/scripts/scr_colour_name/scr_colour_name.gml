function scr_colour_name(_idx) {
    var _names = ["BLACK","WHITE","RED","CYAN","PURPLE","GREEN","BLUE","YELLOW",
                  "ORANGE","BROWN","LT.RED","DK.GRY","GREY","LT.GRN","LT.BLU","LT.GRY"];
    if (_idx < 0 || _idx > 15) return "?";
    return _names[_idx];
}