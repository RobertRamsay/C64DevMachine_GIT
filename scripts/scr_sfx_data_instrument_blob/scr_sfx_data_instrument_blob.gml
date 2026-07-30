function scr_sfx_data_instrument_blob(_instr) {
    var _b = [];
    
    // Header: AD, SR, first waveform

    array_push(_b, _instr.ad);
    array_push(_b, _instr.sr);
    array_push(_b, 0x00);  // padding

// Pairs: [note, waveform] for ALL rows
    for (var _ri = 0; _ri < array_length(_instr.wavetable_rows); _ri++) {
        var _L = _instr.wavetable_rows[_ri].left;
        var _R = _instr.wavetable_rows[_ri].right;
        if (_L == 0xFF) break;
        
        var _note = (_R >= 0x82 && _R <= 0xDF) ? _R : 0xB0;
        var _wave = _L;
        
        array_push(_b, _note);
        array_push(_b, _wave);
    }

    array_push(_b, 0x00); // end
	array_push(_b, 0x00); // end
    return _b;
}