/// ====================================================================
/// VOI64 — LETTER TO SOUND
///
/// This runs in GML, on the PC, at COMPILE TIME. It is the reason Voi64
/// can be small on the C64: SAM had to carry ~6K of rules because in 1982
/// the target machine was the only machine. Here, both text sources are
/// known at build time — an inline string on the node, or the contents of
/// a TEXT_DATA asset — so the letters never reach the 64. MACRO_VOI64_SAY
/// emits a phoneme stream and the player only ever plays phonemes.
///
/// RULE FORMAT
/// The engine is the context-rule scheme from the Naval Research
/// Laboratory work on English letter-to-sound (Elovitz et al., NRL Report
/// 7948, 1976), which is the standard approach and has been independently
/// reimplemented many times. Each rule is four strings:
///
///     [ left context, matched text, right context, phonemes out ]
///
/// The engine walks the word left to right. At each position it takes the
/// rules for the current letter IN ORDER and fires the first whose match
/// and both contexts hold, then advances past the matched text. Order is
/// everything: specific rules must precede general ones, and the last rule
/// for each letter is the unconditional fallback.
///
/// CONTEXT CLASSES (usable in the left and right context strings)
///     #   one or more vowels
///     .   one voiced consonant
///     ^   one consonant
///     +   one front vowel: E I Y
///     :   zero or more consonants
///     %   a suffix: E ES ED ER ING ELY
///     &   one sibilant: S C G Z X, or CH SH
///     @   one consonant after which long U is pronounced:
///         T S R D L Z N J, or TH CH SH
///     (space) a word boundary
///
/// EXTENDING IT
/// The rules are data, not code. To fix a mispronounced word, either add a
/// whole-word rule near the top of that letter's group, or put it in the
/// exceptions map below, which is checked first and costs nothing at
/// runtime on the C64 because none of this ships.
/// ====================================================================

/// @function scr_voi64_lts_is_vowel(_c)
function scr_voi64_lts_is_vowel(_c) {
    return (_c == "A" || _c == "E" || _c == "I" || _c == "O" || _c == "U");
}

/// @function scr_voi64_lts_is_cons(_c)
/// @desc A consonant is any letter that is not a vowel. Y counts as a
///       consonant here; the Y rules handle its vowel behaviour themselves.
function scr_voi64_lts_is_cons(_c) {
    if (_c == "") { return false; }
    if (string_pos(_c, "ABCDEFGHIJKLMNOPQRSTUVWXYZ") == 0) { return false; }
    return !scr_voi64_lts_is_vowel(_c);
}

/// @function scr_voi64_lts_class(_cls, _c)
/// @desc Does one character satisfy one single-character class?
function scr_voi64_lts_class(_cls, _c) {
    switch (_cls) {
        case "#": return scr_voi64_lts_is_vowel(_c);
        case "^": return scr_voi64_lts_is_cons(_c);
        case "+": return (_c == "E" || _c == "I" || _c == "Y");
        case ".": return (string_pos(_c, "BDVGJLMNRWZ") > 0 && _c != "");
        case "&": return (string_pos(_c, "SCGZXJ") > 0 && _c != "");
        case "@": return (string_pos(_c, "TSRDLZNJ") > 0 && _c != "");
        case " ": return (_c == " " || _c == "");
    }
    return (_cls == _c);
}

/// @function scr_voi64_lts_match_right(_txt, _pos, _ctx)
/// @desc Does the right context hold, reading forward from _pos?
///       _pos is 1-based and points at the first character AFTER the match.
function scr_voi64_lts_match_right(_txt, _pos, _ctx) {
    var _p = _pos;
    var _n = string_length(_txt);
    for (var _i = 1; _i <= string_length(_ctx); _i++) {
        var _cls = string_char_at(_ctx, _i);
        var _c   = (_p <= _n) ? string_char_at(_txt, _p) : "";

        if (_cls == "#") {
            // One or more vowels — greedy, but must take at least one.
            if (!scr_voi64_lts_is_vowel(_c)) { return false; }
            while (_p <= _n && scr_voi64_lts_is_vowel(string_char_at(_txt, _p))) { _p += 1; }
            continue;
        }
        if (_cls == ":") {
            // Zero or more consonants — never fails, just consumes.
            while (_p <= _n && scr_voi64_lts_is_cons(string_char_at(_txt, _p))) { _p += 1; }
            continue;
        }
        if (_cls == "%") {
            // A suffix. Longest first, or "ES" would match as "E" and leave
            // an S behind for the next rule to trip over.
            if (string_copy(_txt, _p, 3) == "ING") { _p += 3; continue; }
            if (string_copy(_txt, _p, 3) == "ELY") { _p += 3; continue; }
            if (string_copy(_txt, _p, 2) == "ES")  { _p += 2; continue; }
            if (string_copy(_txt, _p, 2) == "ED")  { _p += 2; continue; }
            if (string_copy(_txt, _p, 2) == "ER")  { _p += 2; continue; }
            if (string_copy(_txt, _p, 1) == "E")   { _p += 1; continue; }
            return false;
        }
        if (_cls == "&") {
            if (string_copy(_txt, _p, 2) == "CH" || string_copy(_txt, _p, 2) == "SH") { _p += 2; continue; }
            if (!scr_voi64_lts_class("&", _c)) { return false; }
            _p += 1;
            continue;
        }
        if (_cls == "@") {
            if (string_copy(_txt, _p, 2) == "TH" || string_copy(_txt, _p, 2) == "CH"
             || string_copy(_txt, _p, 2) == "SH") { _p += 2; continue; }
            if (!scr_voi64_lts_class("@", _c)) { return false; }
            _p += 1;
            continue;
        }

        if (!scr_voi64_lts_class(_cls, _c)) { return false; }
        _p += 1;
    }
    return true;
}

/// @function scr_voi64_lts_match_left(_txt, _pos, _ctx)
/// @desc Does the left context hold, reading BACKWARD from _pos?
///       _pos is 1-based and points at the first character OF the match, so
///       the character immediately to the left is at _pos - 1. The context
///       string is written left-to-right as it reads on the page, so it is
///       walked from its last character to its first.
function scr_voi64_lts_match_left(_txt, _pos, _ctx) {
    var _p = _pos - 1;
    for (var _i = string_length(_ctx); _i >= 1; _i--) {
        var _cls = string_char_at(_ctx, _i);
        var _c   = (_p >= 1) ? string_char_at(_txt, _p) : "";

        if (_cls == "#") {
            if (!scr_voi64_lts_is_vowel(_c)) { return false; }
            while (_p >= 1 && scr_voi64_lts_is_vowel(string_char_at(_txt, _p))) { _p -= 1; }
            continue;
        }
        if (_cls == ":") {
            while (_p >= 1 && scr_voi64_lts_is_cons(string_char_at(_txt, _p))) { _p -= 1; }
            continue;
        }
        if (!scr_voi64_lts_class(_cls, _c)) { return false; }
        _p -= 1;
    }
    return true;
}

/// @function scr_voi64_lts_exceptions()
/// @desc Whole words the rules get wrong and always will. Checked before
///       any rule fires, so one entry here beats fighting the rule order.
///       Keys are upper case, values are space-separated phonemes.
function scr_voi64_lts_exceptions() {
    if (variable_global_exists("voi64_lts_exc")) {
        return global.voi64_lts_exc;
    }
    var _e = {};
    _e[$ "THE"]     = "DH AX";
    _e[$ "A"]       = "AX";
    _e[$ "OF"]      = "AH V";
    _e[$ "TO"]      = "T UW";
    _e[$ "IS"]      = "IH Z";
    _e[$ "ARE"]     = "AA R";
    _e[$ "WAS"]     = "W AA Z";
    _e[$ "ONE"]     = "W AH N";
    _e[$ "TWO"]     = "T UW";
    _e[$ "ONCE"]    = "W AH N S";
    _e[$ "SAID"]    = "S EH D";
    _e[$ "AGAIN"]   = "AX G EH N";
    _e[$ "ANY"]     = "EH N IY";
    _e[$ "MANY"]    = "M EH N IY";
    _e[$ "WHO"]     = "HH UW";
    _e[$ "WHOSE"]   = "HH UW Z";
    _e[$ "DO"]      = "D UW";
    _e[$ "DOES"]    = "D AH Z";
    _e[$ "DONE"]    = "D AH N";
    _e[$ "GONE"]    = "G AO N";
    _e[$ "COME"]    = "K AH M";
    _e[$ "SOME"]    = "S AH M";
    _e[$ "THERE"]   = "DH EH R";
    _e[$ "WHERE"]   = "W EH R";
    _e[$ "THEIR"]   = "DH EH R";
    _e[$ "YOUR"]    = "Y AO R";
    _e[$ "PUT"]     = "P UH T";
    _e[$ "COULD"]   = "K UH D";
    _e[$ "WOULD"]   = "W UH D";
    _e[$ "SHOULD"]  = "SH UH D";
    _e[$ "LIVE"]    = "L IH V";
    _e[$ "GIVE"]    = "G IH V";
    _e[$ "HAVE"]    = "HH AE V";
    _e[$ "MOVE"]    = "M UW V";
    _e[$ "LOVE"]    = "L AH V";
    _e[$ "EYE"]     = "AY";
    _e[$ "IRON"]    = "AY ER N";
    // The -OWN words that the OW/AW split above gets wrong. Cheaper as
    // exceptions than as four more context rules that would each need
    // their own counter-exception.
    _e[$ "OWN"]     = "OW N";
    _e[$ "OWNER"]   = "OW N ER";
    _e[$ "OWE"]     = "OW";
    _e[$ "GROWN"]   = "G R OW N";
    _e[$ "KNOWN"]   = "N OW N";
    _e[$ "SHOWN"]   = "SH OW N";
    _e[$ "THROWN"]  = "TH R OW N";
    _e[$ "BLOWN"]   = "B L OW N";
    _e[$ "FLOWN"]   = "F L OW N";
    _e[$ "BOWL"]    = "B OW L";
    _e[$ "COMMODORE"] = "K AA M AX D AO R";
    global.voi64_lts_exc = _e;
    return _e;
}

/// @function scr_voi64_lts_rules()
/// @desc The rule table, grouped by leading character. Within a group,
///       ORDER IS THE ALGORITHM — the first rule that fits wins, so the
///       specific cases sit above the general ones and each group ends
///       with an unconditional fallback.
function scr_voi64_lts_rules() {
    if (variable_global_exists("voi64_lts_rules")) {
        return global.voi64_lts_rules;
    }
    var _r = {};

    _r[$ " "] = [
        [" ", " ", "",   "SIL"]
    ];

    _r[$ "A"] = [
        [" ", "ARE", " ",  "AA R"],
        [" ", "AR",  "O",  "AX R"],
        ["",  "AR",  "#",  "EH R"],
        ["^", "AS",  "#",  "EY S"],
        ["",  "A",   "WA", "AX"],
        ["",  "AW",  "",   "AO"],
        [" :","ANY", "",   "EH N IY"],
        ["",  "A",   "^+#","EY"],
        ["#:","ALLY","",   "AX L IY"],
        [" ", "AL",  "#",  "AX L"],
        ["",  "AGAIN","",  "AX G EH N"],
        ["#:","AG",  "E",  "IH JH"],
        ["",  "A",   "^+:#","AE"],
        [" :","A",   "^+ ", "EY"],
        ["",  "A",   "^%",  "EY"],
        ["",  "ARR", "",    "AX R"],
        ["",  "AR",  "",    "AA R"],
        ["",  "AIR", "",    "EH R"],
        ["",  "AI",  "",    "EY"],
        ["",  "AY",  "",    "EY"],
        ["",  "AU",  "",    "AO"],
        ["#:","AL",  " ",   "AX L"],
        ["#:","ALS", " ",   "AX L Z"],
        ["",  "ALK", "",    "AO K"],
        ["",  "AL",  "^",   "AO L"],
        [" :","ABLE","",    "EY B AX L"],
        ["",  "ABLE","",    "AX B AX L"],
        ["",  "ANG", "+",   "EY N JH"],
        ["",  "A",   " ",   "AX"],
        ["",  "A",   "",    "AE"]
    ];

    _r[$ "B"] = [
        [" ", "BE", "^#",  "B IH"],
        [" ", "BEING", "", "B IY IH NG"],
        [" ", "BOTH", " ", "B OW TH"],
        [" ", "BUS", "#",  "B IH Z"],
        ["",  "BUIL", "",  "B IH L"],
        ["",  "BB",  "",   "B"],
        ["",  "B",   "",   "B"]
    ];

    _r[$ "C"] = [
        [" ", "CH", "^",  "K"],
        ["^E","CH", "",   "K"],
        ["",  "CH", "",   "CH"],
        [" S","CI", "#",  "S AY"],
        ["",  "CI", "A",  "SH"],
        ["",  "CI", "O",  "SH"],
        ["",  "CI", "EN", "SH"],
        ["",  "CK", "",   "K"],
        ["",  "CO", "M",  "K AA"],
        ["",  "CC", "+",  "K S"],
        ["",  "C",  "+",  "S"],
        ["",  "C",  "",   "K"]
    ];

    _r[$ "D"] = [
        [" ", "DR",  "",   "D R"],
        ["#:","DED", " ",  "D IH D"],
        [".E","D",   " ",  "D"],
        ["#:^","E",  "D ",  "AX"],
        [" ", "DE",  "^#", "D IH"],
        [" ", "DO",  " ",  "D UW"],
        [" ", "DOES","",   "D AH Z"],
        [" ", "DOING","",  "D UW IH NG"],
        [" ", "DOW", "",   "D AW"],
        ["",  "DU",  "A",  "JH UW"],
        ["",  "DG",  "+",  "JH"],
        ["",  "DD",  "",   "D"],
        ["",  "D",   "",   "D"]
    ];

    _r[$ "E"] = [
        ["#:","E",   " ",   ""],
        ["' ^:","E", " ",   ""],
        [" :^","E",  " ",   "IY"],
        ["#","ED",   " ",   "D"],
        ["#:","E",   "D ",  ""],
        ["",  "EV",  "ER",  "EH V"],
        ["",  "ERR", "",    "EH R"],
        ["",  "E",   "^%",  "IY"],
        ["",  "ERI", "#",   "IY R IY"],
        ["",  "ERI", "",    "EH R IH"],
        ["#:","ER",  "#",   "ER"],
        ["",  "ER",  "#",   "EH R"],
        ["",  "ER",  "",    "ER"],
        [" ", "EVEN","",    "IY V EH N"],
        ["#:","E",   "W",   ""],
        ["@", "EW",  "",    "UW"],
        ["",  "EW",  "",    "Y UW"],
        ["",  "E",   "O",   "IY"],
        ["#:&","ES", " ",   "IH Z"],
        ["#:","E",   "S ",  ""],
        ["#:","ELY", " ",   "L IY"],
        ["#:","EMENT","",   "M EH N T"],
        ["",  "EFUL","",    "F UH L"],
        ["",  "EE",  "",    "IY"],
        ["",  "EARN","",    "ER N"],
        [" ", "EAR", "^",   "ER"],
        ["",  "EAD", "",    "EH D"],
        ["#:","EA",  " ",   "IY AX"],
        ["",  "EA",  "SU",  "EH"],
        ["",  "EA",  "",    "IY"],
        ["",  "EIGH","",    "EY"],
        ["",  "EI",  "",    "IY"],
        [" ", "EYE", "",    "AY"],
        ["",  "EY",  "",    "IY"],
        ["",  "EU",  "",    "Y UW"],
        ["",  "E",   "",    "EH"]
    ];

    _r[$ "F"] = [
        ["",  "FUL", "",   "F UH L"],
        ["",  "FF",  "",   "F"],
        ["",  "F",   "",   "F"]
    ];

    _r[$ "G"] = [
        ["",  "GIV", "",   "G IH V"],
        [" ", "G",   "I^", "G"],
        ["",  "GE",  "T",  "G EH"],
        ["SU","GGES","",   "G JH EH S"],
        ["",  "GG",  "",   "G"],
        [" B#","G",  "",   "G"],
        ["",  "G",   "+",  "JH"],
        ["",  "GREAT","",  "G R EY T"],
        ["#","GH",   "",   ""],
        ["",  "G",   "",   "G"]
    ];

    _r[$ "H"] = [
        [" ", "HAV", "",   "HH AE V"],
        [" ", "HERE","",   "HH IY R"],
        [" ", "HOUR","",   "AW ER"],
        ["",  "HOW", "",   "HH AW"],
        ["",  "H",   "#",  "HH"],
        ["",  "H",   "",   ""]
    ];

    _r[$ "I"] = [
        [" ", "IN",  "",   "IH N"],
        [" ", "I",   " ",  "AY"],
        ["",  "IN",  "D",  "AY N"],
        ["",  "IER", "",   "IY ER"],
        ["#:R","IED"," ",  "IY D"],
        ["",  "IED", " ",  "AY D"],
        ["",  "IEN", "",   "IY EH N"],
        ["",  "IE",  "T",  "AY EH"],
        [" :","I",   "%",  "AY"],
        ["",  "I",   "%",  "IY"],
        ["",  "IE",  "",   "IY"],
        ["",  "I",   "^+:#","IH"],
        ["",  "IR",  "#",  "AY R"],
        ["",  "IZ",  "%",  "AY Z"],
        ["",  "IS",  "%",  "AY Z"],
        ["",  "I",   "D%", "AY"],
        ["+^","I",   "^+", "IH"],
        ["",  "I",   "T%", "AY"],
        ["#:^","I",  "^+", "IH"],
        ["",  "I",   "^+", "AY"],
        ["",  "IR",  "",   "ER"],
        ["",  "IGH", "",   "AY"],
        ["",  "ILD", "",   "AY L D"],
        ["",  "IGN", " ",  "AY N"],
        ["",  "IGN", "^",  "AY N"],
        ["",  "IGN", "%",  "AY N"],
        ["",  "IQUE","",   "IY K"],
        ["",  "I",   "",   "IH"]
    ];

    _r[$ "J"] = [ ["", "J", "", "JH"] ];

    _r[$ "K"] = [
        [" ", "K",  "N",  ""],
        ["",  "K",  "",   "K"]
    ];

    _r[$ "L"] = [
        ["",  "LO", "C#", "L OW"],
        ["L", "L",  "",   ""],
        ["#:^","L", "%",  "AX L"],
        ["",  "LEAD","",  "L IY D"],
        ["",  "L",  "",   "L"]
    ];

    _r[$ "M"] = [
        ["",  "MOV","",  "M UW V"],
        ["",  "MM", "",  "M"],
        ["",  "M",  "",  "M"]
    ];

    _r[$ "N"] = [
        ["E", "NG", "+", "N JH"],
        ["",  "NG", "R", "NG G"],
        ["",  "NG", "#", "NG G"],
        ["",  "NGL","%", "NG G AX L"],
        ["",  "NG", "",  "NG"],
        ["",  "NK", "",  "NG K"],
        [" ", "NOW"," ", "N AW"],
        ["",  "NN", "",  "N"],
        ["",  "N",  "",  "N"]
    ];

    _r[$ "O"] = [
        ["",  "OF",  " ",  "AH V"],
        ["",  "OROUGH","", "ER OW"],
        ["#:","OR",  " ",  "ER"],
        ["#:","ORS", " ",  "ER Z"],
        ["",  "OR",  "",   "AO R"],
        [" ", "ONE", "",   "W AH N"],
        ["",  "OW",  " ",  "OW"],
        ["",  "OW",  "^",  "AW"],
        ["",  "OW",  "",   "OW"],
        [" ", "OVER","",   "OW V ER"],
        ["",  "OV",  "",   "AH V"],
        ["",  "O",   "^%", "OW"],
        ["",  "O",   "^EN","OW"],
        ["",  "O",   "^I#","OW"],
        ["",  "OL",  "D",  "OW L"],
        ["",  "OUGHT","",  "AO T"],
        ["",  "OUGH","",   "AH F"],
        [" ", "OU",  "",   "AW"],
        ["H", "OU",  "S#", "AW"],
        ["",  "OUS", "",   "AX S"],
        ["",  "OUR", "",   "AO R"],
        ["",  "OULD","",   "UH D"],
        ["^", "OU",  "^L", "AH"],
        ["",  "OUP", "",   "UW P"],
        ["",  "OU",  "",   "AW"],
        ["",  "OY",  "",   "OY"],
        ["",  "OING","",   "OW IH NG"],
        ["",  "OI",  "",   "OY"],
        ["",  "OOR", "",   "AO R"],
        ["",  "OOK", "",   "UH K"],
        ["",  "OOD", "",   "UH D"],
        ["",  "OO",  "",   "UW"],
        ["",  "O",   "E",  "OW"],
        ["",  "O",   " ",  "OW"],
        ["",  "OA",  "",   "OW"],
        [" ", "ONLY","",   "OW N L IY"],
        [" ", "ONCE","",   "W AH N S"],
        ["",  "ON'T","",   "OW N T"],
        ["C", "O",   "N",  "AA"],
        ["",  "O",   "NG", "AO"],
        [" :^","O",  "N",  "AH"],
        ["I", "ON",  "",   "AX N"],
        ["#:","ON",  " ",  "AX N"],
        ["#^","ON",  "",   "AX N"],
        ["",  "O",   "ST ","OW"],
        ["",  "OF",  "^",  "AO F"],
        ["",  "OTHER","",  "AH DH ER"],
        ["",  "OSS", " ",  "AO S"],
        ["#:^","OM", "",   "AH M"],
        ["",  "O",   "",   "AA"]
    ];

    _r[$ "P"] = [
        ["",  "PH", "",  "F"],
        ["",  "PEOP","", "P IY P"],
        ["",  "POW","",  "P AW"],
        ["",  "PUT"," ", "P UH T"],
        ["",  "PP", "",  "P"],
        ["",  "P",  "",  "P"]
    ];

    _r[$ "Q"] = [
        ["",  "QUAR","", "K W AO R"],
        ["",  "QU",  "", "K W"],
        ["",  "Q",   "", "K"]
    ];

    _r[$ "R"] = [
        [" ", "RE", "^#", "R IY"],
        ["",  "RR", "",   "R"],
        ["",  "R",  "",   "R"]
    ];

    _r[$ "S"] = [
        ["",  "SH",  "",   "SH"],
        ["#", "SION","",   "ZH AX N"],
        ["",  "SOME","",   "S AH M"],
        ["#", "SUR", "#",  "ZH ER"],
        ["",  "SUR", "#",  "SH ER"],
        ["#", "SU",  "#",  "ZH UW"],
        ["#", "SSU", "#",  "SH UW"],
        ["#", "SED", " ",  "Z D"],
        ["#", "S",   "#",  "Z"],
        ["",  "SAID","",   "S EH D"],
        ["^", "SION","",   "SH AX N"],
        ["",  "S",   "S",  ""],
        [".", "S",   " ",  "Z"],
        ["#:.E","S", " ",  "Z"],
        ["#:^^","S", " ",  "S"],
        ["#", "S",   " ",  "Z"],
        ["",  "SCH", "",   "S K"],
        ["",  "S",   "C+", ""],
        ["#", "SM",  "",   "Z M"],
        ["#", "SN",  "'",  "Z AX N"],
        ["",  "S",   "",   "S"]
    ];

    _r[$ "T"] = [
        [" ", "THE", " ",  "DH AX"],
        ["",  "TO",  " ",  "T UW"],
        ["",  "THAT"," ",  "DH AE T"],
        [" ", "THIS"," ",  "DH IH S"],
        [" ", "THEY","",   "DH EY"],
        [" ", "THERE","",  "DH EH R"],
        ["",  "THER","",   "DH ER"],
        ["",  "THEIR","",  "DH EH R"],
        [" ", "THAN"," ",  "DH AE N"],
        [" ", "THEM"," ",  "DH EH M"],
        ["",  "THESE"," ", "DH IY Z"],
        [" ", "THEN","",   "DH EH N"],
        ["",  "THROUGH","","TH R UW"],
        ["",  "THOSE","",  "DH OW Z"],
        ["",  "THOUGH"," ","DH OW"],
        [" ", "THUS","",   "DH AH S"],
        ["",  "TH",  "",   "TH"],
        ["#:","TED", " ",  "T IH D"],
        ["S", "TI",  "#N", "CH"],
        ["",  "TI",  "O",  "SH"],
        ["",  "TI",  "A",  "SH"],
        ["",  "TIEN","",   "SH AX N"],
        ["",  "TUR", "#",  "CH ER"],
        ["",  "TU",  "A",  "CH UW"],
        [" ", "TWO", "",   "T UW"],
        ["",  "TT",  "",   "T"],
        ["",  "T",   "",   "T"]
    ];

    _r[$ "U"] = [
        [" ", "UN",  "I",  "Y UW N"],
        [" ", "UN",  "",   "AH N"],
        [" ", "UPON","",   "AX P AO N"],
        ["@", "UR",  "#",  "UH R"],
        ["",  "UR",  "#",  "Y UH R"],
        ["",  "UR",  "",   "ER"],
        ["",  "U",   "^ ", "AH"],
        ["",  "U",   "^^", "AH"],
        ["",  "UY",  "",   "AY"],
        [" G","U",   "#",  ""],
        ["G", "U",   "%",  ""],
        ["G", "U",   "#",  "W"],
        ["#N","U",   "",   "Y UW"],
        ["@", "U",   "",   "UW"],
        ["",  "U",   "",   "Y UW"]
    ];

    _r[$ "V"] = [
        ["",  "VIEW","",  "V Y UW"],
        ["",  "V",   "",  "V"]
    ];

    _r[$ "W"] = [
        [" ", "WERE","",  "W ER"],
        ["",  "WA",  "S", "W AA"],
        ["",  "WA",  "T", "W AA"],
        ["",  "WHERE","", "W EH R"],
        ["",  "WHAT","",  "W AA T"],
        ["",  "WHOL","",  "HH OW L"],
        ["",  "WHO", "",  "HH UW"],
        ["",  "WH",  "",  "W"],
        ["",  "WAR", "",  "W AO R"],
        ["",  "WOR", "^", "W ER"],
        ["",  "WR",  "",  "R"],
        ["",  "W",   "",  "W"]
    ];

    _r[$ "X"] = [ ["", "X", "", "K S"] ];

    _r[$ "Y"] = [
        ["",  "YOUNG","", "Y AH NG"],
        [" ", "YOU", "",  "Y UW"],
        [" ", "YES", "",  "Y EH S"],
        [" ", "Y",   "",  "Y"],
        ["#:^","Y",  " ", "IY"],
        ["#:^","Y",  "I", "IY"],
        [" :","Y",   " ", "AY"],
        [" :","Y",   "#", "AY"],
        [" :","Y",   "^+:#","IH"],
        [" :","Y",   "^#","AY"],
        ["",  "Y",   "",  "IH"]
    ];

    _r[$ "Z"] = [
        ["", "ZZ", "", "Z"],
        ["", "Z",  "", "Z"]
    ];

    // Digits, spoken as words. Anything not listed anywhere is dropped by
    // the walker rather than guessed at.
    _r[$ "0"] = [ ["", "0", "", "Z IY R OW"] ];
    _r[$ "1"] = [ ["", "1", "", "W AH N"] ];
    _r[$ "2"] = [ ["", "2", "", "T UW"] ];
    _r[$ "3"] = [ ["", "3", "", "TH R IY"] ];
    _r[$ "4"] = [ ["", "4", "", "F AO R"] ];
    _r[$ "5"] = [ ["", "5", "", "F AY V"] ];
    _r[$ "6"] = [ ["", "6", "", "S IH K S"] ];
    _r[$ "7"] = [ ["", "7", "", "S EH V AX N"] ];
    _r[$ "8"] = [ ["", "8", "", "EY T"] ];
    _r[$ "9"] = [ ["", "9", "", "N AY N"] ];

    global.voi64_lts_rules = _r;
    return _r;
}

/// @function scr_voi64_text_to_phonemes(_txt)
/// @desc Convert English text to a space-separated phoneme string.
///       Runs on the PC at compile time; nothing here reaches the C64.
///
///       The word-boundary contexts need real spaces either side, so the
///       text is padded with one at each end before the walk and the
///       positions below are all against that padded copy.
function scr_voi64_text_to_phonemes(_txt) {
    var _rules = scr_voi64_lts_rules();
    var _exc   = scr_voi64_lts_exceptions();
    var _out   = [];

    // Normalise: upper case, sentence punctuation to pauses, everything
    // else that is not a letter, digit or apostrophe to a space.
    var _src = string_upper(string(_txt));
    var _clean = "";
    for (var _i = 1; _i <= string_length(_src); _i++) {
        var _c = string_char_at(_src, _i);
        if (_c == "." || _c == "!" || _c == "?" || _c == "," || _c == ";" || _c == ":") {
            _clean += " | ";
        } else if (string_pos(_c, "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'") > 0) {
            _clean += _c;
        } else {
            _clean += " ";
        }
    }

    // Whole-word exception pass. Done per word before any rule runs, so an
    // entry in the map always wins over the rule table.
    var _words = string_split(_clean, " ", true);
    var _rebuilt = [];
    for (var _wi = 0; _wi < array_length(_words); _wi++) {
        var _w = _words[_wi];
        if (_w == "") { continue; }
        if (_w == "|") {
            array_push(_rebuilt, "|");
            continue;
        }
        if (variable_struct_exists(_exc, _w)) {
            array_push(_rebuilt, "=" + _exc[$ _w]);
        } else {
            array_push(_rebuilt, _w);
        }
    }

    for (var _wi = 0; _wi < array_length(_rebuilt); _wi++) {
        var _w = _rebuilt[_wi];

        if (_w == "|") {
            array_push(_out, "PA");
            continue;
        }
        if (string_char_at(_w, 1) == "=") {
            // Pre-resolved by the exception map.
            var _ph = string_split(string_delete(_w, 1, 1), " ", true);
            for (var _pi = 0; _pi < array_length(_ph); _pi++) {
                if (_ph[_pi] != "") { array_push(_out, _ph[_pi]); }
            }
            array_push(_out, "SIL");
            continue;
        }

        var _pad = " " + _w + " ";
        var _pos = 2;                        // first real character
        var _end = string_length(_pad);      // trailing pad
        var _guard = 0;

        while (_pos < _end) {
            _guard += 1;
            if (_guard > 512) { break; }     // a malformed rule must not hang a build

            var _ch  = string_char_at(_pad, _pos);
            var _grp = variable_struct_exists(_rules, _ch) ? _rules[$ _ch] : undefined;

            if (is_undefined(_grp)) {
                _pos += 1;                   // apostrophes and anything unlisted
                continue;
            }

            var _fired = false;
            for (var _ri = 0; _ri < array_length(_grp); _ri++) {
                var _rule  = _grp[_ri];
                var _left  = _rule[0];
                var _match = _rule[1];
                var _right = _rule[2];
                var _phon  = _rule[3];

                if (string_copy(_pad, _pos, string_length(_match)) != _match) { continue; }
                if (!scr_voi64_lts_match_left(_pad, _pos, _left)) { continue; }
                if (!scr_voi64_lts_match_right(_pad, _pos + string_length(_match), _right)) { continue; }

                if (_phon != "") {
                    var _pl = string_split(_phon, " ", true);
                    for (var _pi = 0; _pi < array_length(_pl); _pi++) {
                        if (_pl[_pi] != "") { array_push(_out, _pl[_pi]); }
                    }
                }
                _pos += string_length(_match);
                _fired = true;
                break;
            }

            // Every group ends in an unconditional fallback, so this should
            // be unreachable. Advancing anyway means a bad edit to the table
            // costs a dropped letter rather than an infinite loop.
            if (!_fired) { _pos += 1; }
        }

        array_push(_out, "SIL");
    }

    // Trim a trailing word gap — the caller adds its own tail silence.
    while (array_length(_out) > 0 && _out[array_length(_out) - 1] == "SIL") {
        array_pop(_out);
    }

    return string_join_ext(" ", _out);
}
