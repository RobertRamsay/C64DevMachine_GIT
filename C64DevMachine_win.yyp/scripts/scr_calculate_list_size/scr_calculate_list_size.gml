function scr_calculate_list_size(_list) {
    var _size = 0;
    for (var _i = 0; _i < array_length(_list); _i++) {
        var _inst = _list[_i];
        var _type = string_lower(string(_inst[0]));
        switch (_type) {
            case "sei": case "cli": case "pha": case "pla": case "txa": case "tax": 
            case "tya": case "tay": case "rti": case "rts": case "dex": case "inx": 
            case "dey": case "iny": case "nop":
                _size += 1; break;
            case "lda_imm": case "ldx_imm": case "ldy_imm": case "bne": case "beq": case "bpl":
                _size += 2; break;
            case "sta_abs": case "jsr": case "jmp": case "asl_abs": case "inc_abs": case "dec_abs":
                _size += 3; break;
            case "byte": 
                _size += 1; break;
            default: 
                _size += 0; break;
        }
    }
    return _size;
}