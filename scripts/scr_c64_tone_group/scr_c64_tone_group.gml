/// @function scr_c64_tone_group(_col)
/// @desc Maps a C64 colour index (0-15) to its LUMA GROUP.
///
///   returns 1 = A / darks
///   returns 2 = B / mediums
///   returns 3 = C / lights
///
/// WHY THIS EXISTS
/// A masked blit (BLEND = MASK00) merges two cells that have DIFFERENT
/// palettes. Source %00 pairs are holes, so the destination's pixels show
/// through there — but the merged cell can only carry ONE palette, and the
/// source's palette is the one that wins.
///
/// That leaves the surviving destination pixels pointing at bit pairs whose
/// colours no longer exist. The groups are the mapping key: a surviving dest
/// pixel keeps its TONAL RANK by being repointed at whichever source slot
/// holds a colour of the same group. Light grey showing through a hole finds
/// the source's light colour, whatever that happens to be.
///
/// Groups are 5 / 5 / 6 across the 16-colour palette.
function scr_c64_tone_group(_col) {
    var _c = _col & 0x0F;
    switch (_c) {
        // A — darks
        case 0x00: return 1;   // black
        case 0x02: return 1;   // red
        case 0x06: return 1;   // dark blue
        case 0x09: return 1;   // brown
        case 0x0B: return 1;   // dark grey

        // B — mediums
        case 0x04: return 2;   // purple
        case 0x05: return 2;   // green
        case 0x08: return 2;   // light brown
        case 0x0A: return 2;   // pink
        case 0x0C: return 2;   // medium grey

        // C — lights
        case 0x01: return 3;   // white
        case 0x03: return 3;   // cyan
        case 0x07: return 3;   // yellow
        case 0x0D: return 3;   // light green
        case 0x0E: return 3;   // light blue
        case 0x0F: return 3;   // light grey
    }
    return 2;
}