function scr_check_dither_mask(_mode, _x, _y, _is_hires = false) {
    if (_mode == "NONE") return true;
    
    if (!_is_hires) {
        // MC: pixels come in 2-wide pairs, so the pattern samples on MC
        // column (0-3) x raw row (0-7) — a 4x8 = 32-level grid.
        var _mc_x = (((_x div 2) mod 4) + 4) mod 4;
        var _mc_y = ((_y mod 8) + 8) mod 8;
        
        if (_mode == "CHECKER")   return ((_mc_x + _mc_y) mod 2 == 0);
        if (_mode == "INTERLACE") return (_mc_y mod 2 == 0);
        
        // True MC-aware Bayer: 4 columns x 8 rows = 32 threshold levels
        // Derived from standard Bayer8 by sampling even columns only
        static _bayer_mc = [
             0, 8, 2,10,
            24,16,26,18,
            12, 4,14, 6,
            28,20,30,22,
             3,11, 1, 9,
            27,19,25,17,
            15, 7,13, 5,
            31,23,29,21
        ];
        
        var _threshold = -1;
        switch (_mode) {
            case "BAYER_4":  _threshold =  1; break;  // ~6%
            case "BAYER_8":  _threshold =  3; break;  // ~12%
            case "BAYER_12": _threshold =  5; break;  // ~18%
            case "BAYER_16": _threshold =  7; break;  // ~25%
            case "BAYER_20": _threshold =  9; break;  // ~31%
            case "BAYER_24": _threshold = 11; break;  // ~37%
            case "BAYER_28": _threshold = 15; break;  // ~43%
            case "BAYER_32": _threshold = 17; break;  // ~50%
            case "BAYER_36": _threshold = 19; break;  // ~56%
            case "BAYER_40": _threshold = 21; break;  // ~62%
            case "BAYER_44": _threshold = 23; break;  // ~68%
            case "BAYER_48": _threshold = 25; break;  // ~75%
            case "BAYER_52": _threshold = 27; break;  // ~81%
            case "BAYER_56": _threshold = 29; break;  // ~87%
            case "BAYER_60": _threshold = 31; break;  // ~93%
        }
        
        if (_threshold >= 0) {
            return (_bayer_mc[_mc_y * 4 + _mc_x] <= _threshold);
        }
        
        return true;
        
    } else {
        // HiRes: every pixel is independently addressable (no 2-wide pairing),
        // so the pattern samples a full 8x8 grid — 64 threshold levels.
        var _hr_x = ((_x mod 8) + 8) mod 8;
        var _hr_y = ((_y mod 8) + 8) mod 8;
        
        if (_mode == "CHECKER")   return ((_hr_x + _hr_y) mod 2 == 0);
        if (_mode == "INTERLACE") return (_hr_y mod 2 == 0);
        
        // Standard 8x8 ordered Bayer matrix, 64 threshold levels
        static _bayer_hr = [
             0,32, 8,40, 2,34,10,42,
            48,16,56,24,50,18,58,26,
            12,44, 4,36,14,46, 6,38,
            60,28,52,20,62,30,54,22,
             3,35,11,43, 1,33, 9,41,
            51,19,59,27,49,17,57,25,
            15,47, 7,39,13,45, 5,37,
            63,31,55,23,61,29,53,21
        ];
        
        // Thresholds doubled from the MC 32-level set (same count-doubling,
        // same intentional skip at BAYER_28/56) so each named preset keeps
        // roughly the same fill percentage between modes.
        var _threshold = -1;
        switch (_mode) {
            case "BAYER_4":  _threshold =  3; break;  // ~6%
            case "BAYER_8":  _threshold =  7; break;  // ~12%
            case "BAYER_12": _threshold = 11; break;  // ~18%
            case "BAYER_16": _threshold = 15; break;  // ~25%
            case "BAYER_20": _threshold = 19; break;  // ~31%
            case "BAYER_24": _threshold = 23; break;  // ~37%
            case "BAYER_28": _threshold = 31; break;  // ~43% (doubled skip preserved)
            case "BAYER_32": _threshold = 35; break;  // ~50%
            case "BAYER_36": _threshold = 39; break;  // ~56%
            case "BAYER_40": _threshold = 43; break;  // ~62%
            case "BAYER_44": _threshold = 47; break;  // ~68%
            case "BAYER_48": _threshold = 51; break;  // ~75%
            case "BAYER_52": _threshold = 55; break;  // ~81%
            case "BAYER_56": _threshold = 59; break;  // ~87%
            case "BAYER_60": _threshold = 63; break;  // ~93%
        }
        
        if (_threshold >= 0) {
            return (_bayer_hr[_hr_y * 8 + _hr_x] <= _threshold);
        }
        
        return true;
    }
}