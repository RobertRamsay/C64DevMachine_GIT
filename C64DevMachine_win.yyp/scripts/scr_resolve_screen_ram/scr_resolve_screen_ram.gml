/// @desc Resolve the active screen RAM base address from the connected MACRO_VIC node.
///       Returns $0400 if no MACRO_VIC is found (bank 0 default, no regression).
function scr_resolve_screen_ram() {
    var _scr_base = 0x0400;
    with (obj_c64_node) {
        if (node_type == "MACRO_VIC" && is_connected) {
            var _vic_mode = string(instructions[0][1]);
            if (_vic_mode == "BITMAP" || _vic_mode == "BMP" || _vic_mode == "MCB") {
                var _chr_s = is_real(instructions[0][4]) ? real(instructions[0][4]) : 0x4000;
                _scr_base = _chr_s + 0x2000;
            } else {
                _scr_base = is_real(instructions[0][3]) ? real(instructions[0][3]) : 0x0400;
            }
            break;
        }
    }
    return _scr_base;
}