from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1] / 'C64DevMachine_win.yyp'
def read(p): return p.read_text(encoding='utf-8')
def write(p,t):
    with p.open('w',encoding='utf-8',newline='') as f: f.write(t.replace('\n','\r\n'))
def sub(t,old,new):
    assert old in t,old[:100]
    return t.replace(old,new,1)

# Remaining dedicated sprite, animation and collision editors.
for name in ['scr_spred64_v2_draw','scr_sprite_mask','scr_macro_anim_set','scr_line_coll_support']:
    p=ROOT/'scripts'/name/(name+'.gml'); t=read(p)
    pattern=r'draw_set_colou?r\(([^;]+)\);\s*draw_rectangle\(([^;]+),\s*false\);'
    def control(m):
        expr, rect=m.groups()
        hot=re.findall(r'\b(_\w*(?:hov\w*|hot))\b',expr)
        if not hot or rect.count(',')!=3 or 'scr_c64' in expr: return m.group(0)
        on=re.findall(r'\b(_\w*(?:_on|_sel|_selected)|_active)\b',expr)
        return f'scr_editor_control({rect}, {hot[0]}, {on[0] if on else "false"});'
    t=re.sub(pattern,control,t)
    neutral=r'draw_set_colou?r\(make_colou?r_rgb\((\d+),\s*(\d+),\s*(\d+)\)\);\s*draw_rectangle\(([^;]+),\s*false\);\s*draw_set_colou?r\(([^;]+)\);\s*draw_rectangle\(\4,\s*true\);'
    def panel(m):
        cols=list(map(int,m.group(1,2,3))); rect=m.group(4)
        if max(cols)>65 or max(cols)-min(cols)>28 or rect.count(',')!=3: return m.group(0)
        return f'scr_editor_panel({rect}, true);'
    t=re.sub(neutral,panel,t)
    t=re.sub(r'(scr_editor_control\([^;]+\);\s*draw_set_colou?r\([^;]+\);\s*)draw_rectangle\(([^;]+),\s*true\);',r'\1draw_roundrect_ext(\2, 5, 5, true);',t)
    write(p,t)

for name in ['scr_hud_editor','scr_room_map']:
    p=ROOT/'scripts'/name/(name+'.gml');t=read(p)
    if name=='scr_hud_editor':
        t=sub(t,'draw_set_color(_bg);\n        draw_rectangle(_x1, _y1, _x1 + _w, _y1 + _h, false);',
              'scr_editor_control(_x1, _y1, _x1 + _w, _y1 + _h, _hov, _on);')
    else:
        start=t.index('        if (_hov) {',t.index('var _button = function'))
        end=t.index('        draw_set_color(c_white);',start)
        t=t[:start]+'        scr_editor_control(_x1, _y1, _x1 + _w, _y1 + _h, _hov);\n'+t[end:]
    t=re.sub(r'draw_set_color\(_c_box\);\s*draw_rectangle\(([^;]+), false\);\s*draw_set_color\(_c_edge\);\s*draw_rectangle\(\1, true\);',r'scr_editor_panel(\1, true);',t)
    t=t.replace('make_color_rgb(24, 24, 36)','make_color_rgb(30, 40, 53)').replace('make_color_rgb(56, 56, 78)','make_color_rgb(66, 82, 103)')
    write(p,t)

# Inline/code editors: keep text and pixel canvases square; round the outer shell.
p=ROOT/'scripts/scr_asset_inline_editor_draw/scr_asset_inline_editor_draw.gml';t=read(p)
start=t.index('    // Panel background');end=t.index('    // Gutter background',start)
t=t[:start]+'''    // Recessed editor shell; text geometry remains shared with Step.
    scr_editor_panel(_x1 - 1, _y1 - 1, _x2 + 1, _y2 + 1, true);

'''+t[end:]
t=t.replace('make_color_rgb(20, 20, 32)','make_color_rgb(25, 35, 48)').replace('make_color_rgb(30, 30, 48)','make_color_rgb(38, 50, 65)')
write(p,t)

p=ROOT/'objects/obj_asset_manager/Draw_64.gml';t=read(p)
t=sub(t,'scr_editor_panel(_vx1, _vy1, _vx2, _vy2, true);','scr_editor_panel(_vx1, _vy1, _vx2, _vy2);')
t=sub(t,'draw_set_color(_tcol);\n    draw_rectangle(_vx1, _vy1, _vx2, _vy1 + 28, false);',
      '''scr_editor_panel(_vx1, _vy1, _vx2, _vy1 + 28);
    draw_set_color(_tcol);
    draw_rectangle(_vx1 + 8, _vy1 + 7, _vx1 + 10, _vy1 + 21, false);''')
t=sub(t,'draw_text_l(_vx1 + 10, _vy1 + 6, _viewer_title);','draw_text_l(_vx1 + 18, _vy1 + 6, _viewer_title);')
start=t.index('    var _cl_bg  =');end=t.index('    draw_set_font_l(fnt_c64_tiny);',start)
t=t[:start]+'    scr_editor_control(_cl_x1, _cl_y1, _cl_x2, _cl_y2, _cl_hov);\n'+t[end:]
t=t.replace('make_color_rgb(8, 8, 12)','make_color_rgb(13, 20, 29)')

# Blank asset library has stable, recessed row placeholders.
marker='asset_group_rows = [];   // Step_0 hit-tests group headers against this'
t=sub(t,marker,marker+'''
if (_disp_n == 0) {
    for (var _empty_row = 0; _empty_row < 3; _empty_row++) {
        var _empty_y = _list_y + _empty_row * (item_h + 6);
        if (_empty_y + item_h > _panel_bottom - 38) break;
        scr_editor_empty_slot(panel_x + 6, _empty_y, _panel_right - 6, _empty_y + item_h);
    }
    draw_set_font_l(fnt_c64_tiny);
    draw_set_color(make_color_rgb(151, 170, 192));
    draw_text_l(panel_x + 12, _list_y + 3 * (item_h + 6) + 8, "ADD AN ASSET TO GET STARTED");
}
''')
# Preserve per-type/conflict row colour, but give rows gutters and rounded edges.
t=sub(t,'draw_rectangle(panel_x, _iy, _panel_right, _iy + item_h, false);',
      'draw_roundrect_ext(panel_x + 2, _iy + 1, _panel_right - 2, _iy + item_h - 1, 5, 5, false);')

# Reserve label height when sizing metatile art and remove the old art outline.
t=sub(t,'floor((_slot_h - 12) / max(1, _m.stamp_h))','floor((_slot_h - 24) / max(1, _m.stamp_h))')
t=sub(t,'var _vis_slots   = floor(_list_area_h / _slot_h);','var _vis_slots   = max(1, floor(_list_area_h / _slot_h));')
t=sub(t,'''        if (_ssel) {
            draw_set_color(make_color_rgb(80, 200, 120));
            draw_rectangle(_sx2 + 2, _sy2 + 2, _sx2 + 4 + _foot_w, _sy2 + 4 + _foot_h, true);
        }
''','')
t=sub(t,'''        scr_editor_control(_sx2, _sy2, _sx2 + _slot_w3 - 2, _sy2 + _slot_h - 2, _shov, _ssel);''',
      '''        scr_editor_panel(_sx2, _sy2, _sx2 + _slot_w3 - 2, _sy2 + _slot_h - 2, true);
        if (_shov || _ssel) scr_editor_control(_sx2, _sy2, _sx2 + _slot_w3 - 2, _sy2 + _slot_h - 2, _shov, _ssel);''')
# Deselect was inside every stamp iteration (quadratic work), and could clear
# the newly-created stamp. Run it once, considering the [+] slot a real target.
start=t.index('\t// Click empty space in list to deselect')
end=t.index('        if (_shov && mouse_check_button_pressed(mb_left)',start)
block=t[start:end].replace('_scheck < _m.stamp_count','_scheck <= _m.stamp_count')
t=t[:start]+t[end:]
marker='    scr_mts_glyph_end();\n\n    gpu_set_scissor'
t=sub(t,marker,block+'    scr_mts_glyph_end();\n\n    gpu_set_scissor')
# Stop deletion from shifting another card under this same click.
needle='''            } else if (_m.edit_stamp > _si) {
                _m.edit_stamp--;
            }
        }
    }
'''
t=sub(t,needle,needle.replace('            }\n        }\n    }','            }\n            break;\n        }\n    }'))
write(p,t)

# Sprite-bank placeholders: preserve the existing full-cell click grid, inset
# preview art, and render blank sprites and unused positions as empty wells.
p=ROOT/'scripts/scr_spred64_v2_draw/scr_spred64_v2_draw.gml';t=read(p)
t=sub(t,'draw_rectangle(_cx + 1, _cy_p + 1, _cx + 1 + 96, _cy_p + 1 + 84, false);',
      'draw_rectangle(_cx + 6, _cy_p + 5, _cx + 90, _cy_p + 79, false);')
t=sub(t,'_cx + 1, _cy_p + 1, 2, 2, 0, c_white, 1);','_cx + 6, _cy_p + 5, 1.75, 1.75, 0, c_white, 1);')
marker='''            if (_slot_empty) {
                draw_set_font_l(fnt_c64_tiny);'''
t=sub(t,marker,'''            if (_slot_empty) {
                scr_editor_empty_slot(_cx, _cy_p, _cx + _pick_cell_w, _cy_p + _pick_cell_h);
                draw_set_font_l(fnt_c64_tiny);''')
marker='        // ----- "+" ADD-SLOT CELL -----'
t=sub(t,marker,'''        // Empty positions reserve the same footprint as populated sprites.
        for (var _empty_slot = _pick_used + 1; _empty_slot < 64; _empty_slot++) {
            var _ex = _pick_x1 + 2 + (_empty_slot mod _pick_cols) * (_pick_cell_w + _pick_gap);
            var _ey = _pick_y1 + 2 + (_empty_slot div _pick_cols) * (_pick_cell_h + _pick_gap);
            scr_editor_empty_slot(_ex, _ey, _ex + _pick_cell_w, _ey + _pick_cell_h);
        }

'''+marker)
write(p,t)
