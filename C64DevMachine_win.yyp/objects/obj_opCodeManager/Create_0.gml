/// @description C64 Opcodes Metadata Manager

// 1. Fetch the data from our management script
opcode_info = scr_define_opcodes();

get_cycles = function(_name) {
    var _n = string_trim(string_lower(_name));
    
// REDIRECTS: Match the specific keys in your scr_define_opcodes struct
    if (_n == "jmp" || _n == "jmp_abs") _n = "jmp_abs";
    if (_n == "jsr" || _n == "jsr_abs") _n = "jsr";
	
    // CLEANING: Standardize naming to match your opcode_info struct keys
    _n = string_replace_all(_n, "_abs_x", "_abx");
    _n = string_replace_all(_n, "_abs_y", "_aby");
    _n = string_replace_all(_n, "_zp_x",  "_zpx");
    _n = string_replace_all(_n, "_zp_y",  "_zpy");
	_n = string_replace_all(_n, "_ind_x", "_izx");
	_n = string_replace_all(_n, "_ind_y", "_izy");
    _n = string_replace_all(_n, "_imm_rep", "_imm");

    if (variable_struct_exists(opcode_info, _n)) {
        return opcode_info[$ _n][1];
    }
    
    // FALLBACK: Jumps usually take 3 cycles, JSR takes 6
    if (_n == "jmp_abs") return 3;
    if (_n == "jsr_abs") return 6;
    
    return 0; 
}

get_size = function(_name) {
    var _n = string_trim(string_lower(_name));
    
    if (_n == "jmp" || _n == "jmp_abs") _n = "jmp_abs";
    if (_n == "jsr" || _n == "jsr_abs") _n = "jsr";

    _n = string_replace_all(_n, "_abs_x",  "_abx");
    _n = string_replace_all(_n, "_abs_y",  "_aby");
    _n = string_replace_all(_n, "_zp_x",   "_zpx");
    _n = string_replace_all(_n, "_zp_y",   "_zpy");
    _n = string_replace_all(_n, "_ind_x",  "_izx");
    _n = string_replace_all(_n, "_ind_y",  "_izy");
    _n = string_replace_all(_n, "_imm_rep","_imm");

    if (variable_struct_exists(opcode_info, _n)) {
        return opcode_info[$ _n][0];
    }
    
    if (_n == "jmp_abs") return 3;
    return 0; 
}

// 3. Update the whole world
scr_c64_update_addresses();