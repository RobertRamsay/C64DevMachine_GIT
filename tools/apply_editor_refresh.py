"""One-off migration of existing editor chrome to shared nine-slice widgets."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1] / "C64DevMachine_win.yyp"


def read(path):
    return path.read_text(encoding="utf-8-sig")


def write(path, text):
    with path.open("w", encoding="utf-8", newline="") as f:
        f.write(text.replace("\r\n", "\n").replace("\n", "\r\n"))


def replace(text, old, new):
    assert old in text, old[:100]
    return text.replace(old, new, 1)


project = ROOT / "C64DevMachine_win.yyp"
t = read(project)
for kind, name in [("scripts", "scr_editor_skin"), ("sprites", "spr_editor_slate")]:
    entry = f'    {{"id":{{"name":"{name}","path":"{kind}/{name}/{name}.yy",}},}},\n'
    t = replace(t, '  "resources":[\n', '  "resources":[\n' + entry)
write(project, t)

names = ["scr_asset_inline_editor_draw", "scr_bitmap_builder_editor", "scr_bmp_objects",
         "scr_chr_editor_draw", "scr_code_editor_draw", "scr_code_editor_draw_find_dialogue",
         "scr_hud_editor", "scr_music_digi", "scr_room_map", "scr_sample_editor",
         "scr_sfx_maker", "scr_sound_editor_editor", "scr_sound_editor_draw_instruments",
         "scr_sound_editor_piano", "scr_sound_editor_cmd_menu", "scr_vbmp_editor"]
paths = [ROOT / "scripts" / n / (n + ".gml") for n in names]
paths += [ROOT / "objects/obj_asset_manager/Draw_64.gml"]

# Convert only explicit hover-dependent control fills; the original hover
# variable and rectangle are kept verbatim. Never touch C64 pixel drawing.
pat = re.compile(r'draw_set_colou?r\(([^;\n]+)\);\s*draw_rectangle\(([^;\n]+),\s*false\);')
counts = {}
for path in paths:
    t = read(path)
    count = [0]
    def button(m):
        expr, rect = m.groups()
        hot = re.findall(r'\b(_\w*(?:hov\w*|hot))\b', expr)
        if not hot or 'scr_c64' in expr or rect.count(',') != 3:
            return m.group(0)
        # Colour swatches and piano keys retain their actual preview colours.
        if any(x in rect for x in ['_key_', '_pk', '_pal', '_swatch']):
            return m.group(0)
        on = re.findall(r'\b(_\w*(?:_on|_sel|_selected)|_ssel|_bsel)\b', expr)
        selected = on[0] if on else 'false'
        count[0] += 1
        return f'scr_editor_control({rect}, {hot[0]}, {selected});'
    t = pat.sub(button, t)
    # Replace neutral chrome fill/border pairs, keeping coloured content alone.
    neutral = re.compile(r'draw_set_colou?r\(make_colou?r_rgb\((\d+),\s*(\d+),\s*(\d+)\)\);\s*draw_rectangle\(([^;\n]+),\s*false\);\s*draw_set_colou?r\(([^;\n]+)\);\s*draw_rectangle\(\4,\s*true\);')
    def panel(m):
        r,g,b = map(int, m.group(1,2,3))
        rect = m.group(4)
        if max(r,g,b) > 65 or max(r,g,b)-min(r,g,b) > 28 or rect.count(',') != 3:
            return m.group(0)
        return f'scr_editor_panel({rect}, {str(max(r,g,b) < 30).lower()});'
    t = neutral.sub(panel, t)
    # Rounded outlines must follow rounded fills, using the existing accent.
    t = re.sub(r'(scr_editor_control\([^;]+\);\s*draw_set_colou?r\([^;]+\);\s*)draw_rectangle\(([^;\n]+),\s*true\);',
               r'\1draw_roundrect_ext(\2, 5, 5, true);', t)
    # Dark chrome needs light text even where legacy buttons used bright fills.
    t = re.sub(r'draw_set_colou?r\(([^;\n]*\bc_black\b[^;\n]*)\);(?=((?:\s*draw_set_(?:h|v)align\([^;]+\);)*\s*draw_text))',
               lambda m: 'draw_set_color(' + m.group(1).replace('c_black', 'c_white') + ');', t)
    if t != read(path):
        write(path, t)
    counts[path.stem] = count[0]
print('Controls migrated:', counts)

# Common custom widgets whose fill was computed separately from their draw.
path = ROOT / 'scripts/scr_sample_editor/scr_sample_editor.gml'
t = read(path)
t = replace(t, 'draw_set_color(_bg);\n    draw_rectangle(_x1, _y1, _x1 + _w, _y1 + _h, false);',
            'scr_editor_control(_x1, _y1, _x1 + _w, _y1 + _h, _hov, _on, _enabled);')
write(path,t)
path = ROOT / 'scripts/scr_bmp_objects/scr_bmp_objects.gml'
t = read(path)
start = t.index('    var _bg =', t.index('function scr_bmpobj_ui_button'))
end = t.index('    draw_set_color(_enabled', start)
t = t[:start] + '    scr_editor_control(_x1, _y1, _x1 + _w, _y1 + _h, _hov, _on, _enabled);\n' + t[end:]
write(path,t)
path = ROOT / 'scripts/scr_creator/scr_creator.gml'
t = read(path)
start = t.index('    var _frm = 0;', t.index('function scr_creator_skin_panel'))
end = t.index('\n}', start)
t = t[:start] + '    scr_editor_panel(_x1, _y1, _x1 + _w, _y1 + _h);' + t[end:]
start = t.index('    var _frm =', t.index('function scr_creator_skin_btn('))
end = t.index('    draw_set_colour(c_white);', start)
t = t[:start] + '    scr_editor_control(_x1, _y1, _x2, _y2, _hov, _on);\n' + t[end:]
write(path,t)

# Match Step and Draw geometry, including Add Asset's full visible width.
for event in ['Draw_64.gml','Step_0.gml']:
    path = ROOT / 'objects/obj_asset_manager' / event
    t = read(path)
    t = replace(t, 'var _panel_w      = _panel_right - panel_x;\nvar _panel_h      = _panel_bottom - panel_y;', '')
    marker = 'panel_y = 345;   // just under the shortcuts column (ends at y 340)'
    t = replace(t, marker, marker + '\nvar _panel_w = _panel_right - panel_x;\nvar _panel_h = _panel_bottom - panel_y;')
    if event == 'Step_0.gml':
        t = replace(t, 'panel_x + panel_w - 4, panel_y + 26', '_panel_right - 4, panel_y + 26')
    write(path,t)
