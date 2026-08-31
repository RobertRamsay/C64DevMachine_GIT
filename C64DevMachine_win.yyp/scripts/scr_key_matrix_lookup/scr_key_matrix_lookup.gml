/// ====================================================================
/// C64 KEYBOARD MATRIX
///
/// Eight lines out on CIA1 port A ($DC00), eight lines back on port B
/// ($DC01), both active LOW: drive one PA line low, and any key on that
/// line pulls its PB line low while it is held.
///
/// Table is PA0..PA7 by PB0..PB7, straight off the standard layout:
///
///   PA0  DEL  RETURN  CRSR L/R  F7  F1  F3  F5  CRSR U/D
///   PA1  3    W       A         4   Z   S   E   LSHIFT
///   PA2  5    R       D         6   C   F   T   X
///   PA3  7    Y       G         8   B   H   U   V
///   PA4  9    I       J         0   M   K   O   N
///   PA5  +    P       L         -   .   :   @   ,
///   PA6  £    *       ;         HOME RSHIFT =  ^  /
///   PA7  1    <-      CTRL      2   SPACE C= Q  RUN/STOP
///
/// Two keys are NOT in here and cannot be, whatever the node asks for:
///   RESTORE  — wired to the NMI line, not the matrix. It needs an NMI
///              handler; there is nothing to scan.
///   SHIFT LOCK — a mechanical latch wired in parallel with LSHIFT, so
///              it is indistinguishable from holding left shift.
///
/// Nor are the SHIFTED keys separate positions: F2 is SHIFT+F1, INST is
/// SHIFT+DEL, CRSR UP is SHIFT+CRSR U/D. Ask for the unshifted key and
/// test LSHIFT/RSHIFT as a second slot if the difference matters.
/// ====================================================================

/// @function scr_key_matrix_lookup(_name)
/// @desc Resolve a key name to its matrix position.
/// @return {struct} { ok, pa, pb, name } — pa/pb are BIT INDICES 0-7.
function scr_key_matrix_lookup(_name) {
    var _n = string_upper(string_trim(string(_name)));

    // Spellings people actually type, folded onto the table's own names.
    if (_n == "C=")        { _n = "CBM";     }
    if (_n == "COMMODORE") { _n = "CBM";     }
    if (_n == "STOP")      { _n = "RUNSTOP"; }
    if (_n == "RUN/STOP")  { _n = "RUNSTOP"; }
    if (_n == "SHIFT")     { _n = "LSHIFT";  }
    if (_n == "ENTER")     { _n = "RETURN";  }
    if (_n == "DELETE")    { _n = "DEL";     }
    if (_n == "INST")      { _n = "DEL";     }   // shifted DEL, same key
    if (_n == "SPACEBAR")  { _n = "SPACE";   }
    if (_n == "CRSR")      { _n = "CRSRUD";  }
    if (_n == "CRSRDN")    { _n = "CRSRUD";  }
    if (_n == "CRSRRT")    { _n = "CRSRLR";  }
    if (_n == "ARROWLEFT") { _n = "LARROW";  }
    if (_n == "ARROWUP")   { _n = "UARROW";  }

    var _rows = [
        ["DEL",    "RETURN", "CRSRLR", "F7",   "F1",    "F3",  "F5",     "CRSRUD" ],
        ["3",      "W",      "A",      "4",    "Z",     "S",   "E",      "LSHIFT" ],
        ["5",      "R",      "D",      "6",    "C",     "F",   "T",      "X"      ],
        ["7",      "Y",      "G",      "8",    "B",     "H",   "U",      "V"      ],
        ["9",      "I",      "J",      "0",    "M",     "K",   "O",      "N"      ],
        ["PLUS",   "P",      "L",      "MINUS",".",     ":",   "@",      ","      ],
        ["POUND",  "*",      ";",      "HOME", "RSHIFT","=",   "UARROW", "/"      ],
        ["1",      "LARROW", "CTRL",   "2",    "SPACE", "CBM", "Q",      "RUNSTOP"]
    ];

    for (var _pa = 0; _pa < 8; _pa++) {
        for (var _pb = 0; _pb < 8; _pb++) {
            if (_rows[_pa][_pb] == _n) {
                return { ok: true, pa: _pa, pb: _pb, name: _n };
            }
        }
    }

    return { ok: false, pa: 0, pb: 0, name: _n };
}

/// @function scr_key_matrix_is_nmi(_name)
/// @desc RESTORE is the one key people reach for that no scan can ever see.
///       Worth answering separately so the node can say so rather than just
///       reporting the name as unknown.
function scr_key_matrix_is_nmi(_name) {
    var _n = string_upper(string_trim(string(_name)));
    return (_n == "RESTORE");
}


/// @function scr_key_category_list(_node_type)
/// @desc The keys a given keyboard node offers, in grid order.
///
/// Split three ways because a single node listing all 64 positions would be
/// unusable, and because the three groups want different column widths: single
/// letters pack six across, the misc names need four.
///
/// F2/F4/F6/F8 are deliberately ABSENT. They are not matrix positions — they
/// are SHIFT plus F1/F3/F5/F7 — so a grid entry for them would either lie or
/// force every F-key test to also prove shift is NOT held. The shifts sit on
/// the Fn node itself so the pair can be tested from one ZP byte.
///
/// RESTORE is absent for the same class of reason: it is on the NMI line and
/// no scan can see it.
function scr_key_category_list(_node_type) {
    if (_node_type == "MACRO_LETTERS") {
        return {
            cols: 6,
            keys: ["A","B","C","D","E","F","G","H","I","J","K","L","M",
                   "N","O","P","Q","R","S","T","U","V","W","X","Y","Z"]
        };
    }

    if (_node_type == "MACRO_FNNUMBERS") {
        return {
            // Four across, not six: LSH and RSH are three characters and a
            // sixth-of-a-node column is only ~25px, so they ran into each
            // other. Sixteen keys divides into four rows of four exactly.
            cols: 4,
            // LSHIFT/RSHIFT live here as well as in MISC, on purpose. F2 is
            // SHIFT+F1, and with the shifts on THIS node their held-bits land
            // in the same ZP byte as the F-keys (bits 0-7 are the digits 0-7,
            // byte 1 holds 8, 9, F1, F3, F5, F7, LSHIFT, RSHIFT). So testing
            // "F2 is down" is one load and one mask:
            //     lda zp+1 / and #%01000100 / cmp #%01000100 / beq f2_held
            // rather than reading two different nodes' blocks.
            keys: ["0","1","2","3","4","5","6","7","8","9",
                   "F1","F3","F5","F7","LSHIFT","RSHIFT"]
        };
    }

    // MACRO_MISCKEYS
    return {
        cols: 4,
        keys: ["SPACE","RETURN","DEL","HOME",
               "RUNSTOP","CTRL","CBM","LSHIFT",
               "RSHIFT","CRSRUD","CRSRLR","PLUS",
               "MINUS",".",",",":",
               ";","@","/","*",
               "=","UARROW","LARROW","POUND"]
    };
}

/// @function scr_key_slot_label(_key)
/// @desc Short form for the grid cell. The lookup table's names are canonical
///       but a few are spelled for typing, not for a 30px column.
function scr_key_slot_label(_key) {
    var _k = string_upper(string(_key));
    if (_k == "PLUS")    { return "+";    }
    if (_k == "MINUS")   { return "-";    }
    // The C64 font has no glyph for the pound sign, so drawing it gives an
    // empty box. Name the key instead.
    if (_k == "POUND")   { return "PND";  }
    if (_k == "UARROW")  { return "UP^";  }
    if (_k == "LARROW")  { return "<-";   }
    if (_k == "SPACE")   { return "SPC";  }   // "SPACE" is wider than a column
    if (_k == "RUNSTOP") { return "STOP"; }
    if (_k == "CRSRUD")  { return "CRUD"; }
    if (_k == "CRSRLR")  { return "CRLR"; }
    if (_k == "RETURN")  { return "RET";  }
    if (_k == "LSHIFT")  { return "LSH";  }
    if (_k == "RSHIFT")  { return "RSH";  }
    return _k;
}
