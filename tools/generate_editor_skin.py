"""Build the native, six-state GameMaker nine-slice editor skin (Pillow)."""
from pathlib import Path
import json
import re
import uuid
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[1] / "C64DevMachine_win.yyp"
NAME = "spr_editor_slate"
DEST = ROOT / "sprites" / NAME


def read_yy(path):
    return json.loads(re.sub(r",\s*([}\]])", r"\1", path.read_text(encoding="utf-8-sig")))


def build():
    DEST.mkdir(parents=True, exist_ok=True)
    template = read_yy(ROOT / "sprites/spr_glassSlice/spr_glassSlice.yy")
    # Stable IDs keep regeneration from churning resource references.
    uid = lambda key: str(uuid.uuid5(uuid.NAMESPACE_URL, NAME + "/" + key))
    layer = uid("layer")
    frames = [uid(str(i)) for i in range(6)]
    template["name"] = template["%Name"] = NAME
    template.update(width=24, height=24, bbox_left=0, bbox_top=0, bbox_right=23, bbox_bottom=23)
    template["layers"] = [template["layers"][0]]
    template["layers"][0].update(name=layer, **{"%Name": layer})
    for i, frame in enumerate(template["frames"]):
        frame.update(name=frames[i], **{"%Name": frames[i]})
    template["nineSlice"].update(left=6, right=6, top=6, bottom=6)
    seq = template["sequence"]
    seq["name"] = seq["%Name"] = NAME
    for i, key in enumerate(seq["tracks"][0]["keyframes"]["Keyframes"]):
        key["id"] = uid("key" + str(i))
        key["Channels"]["0"]["Id"] = {"name": frames[i], "path": f"sprites/{NAME}/{NAME}.yy"}
    # Raised, hover/recessed, selected, disabled, panel, empty well.
    colors = [
        ("#101821", "#657589", "#344355", "#293647"),
        ("#526377", "#0a111a", "#141f2c", "#1b2938"),
        ("#74c8d4", "#0c2430", "#203f4e", "#254857"),
        ("#263342", "#354354", "#26313e", "#26313e"),
        ("#101821", "#46566a", "#263242", "#263242"),
        ("#405064", "#0b121b", "#17222f", "#17222f"),
    ]
    preview = Image.new("RGBA", (6 * 144, 110), "#101821")
    for i, (edge, lip, top, bottom) in enumerate(colors):
        im = Image.new("RGBA", (24, 24))
        d = ImageDraw.Draw(im)
        d.rounded_rectangle((0, 0, 23, 23), radius=6, fill=edge)
        d.rounded_rectangle((1, 1, 22, 21), radius=5, fill=lip)
        d.rounded_rectangle((2, 3, 21, 20), radius=4, fill=top)
        # Solid centre avoids seams when the centre and edge slices stretch.
        d.rectangle((6, 6, 17, 17), fill=bottom)
        if top != bottom:
            d.rounded_rectangle((2, 6, 21, 20), radius=3, fill=bottom)
            d.rectangle((2, 6, 21, 17), fill=bottom)
        im.save(DEST / (frames[i] + ".png"))
        sub = DEST / "layers" / frames[i]
        sub.mkdir(parents=True, exist_ok=True)
        im.save(sub / (layer + ".png"))
        # A faithful nine-slice preview, with corners kept at native size.
        xs, ys = [0, 6, 18, 24], [0, 6, 18, 24]
        tx, ty = [0, 6, 122, 128], [0, 6, 58, 64]
        for row in range(3):
            for col in range(3):
                part = im.crop((xs[col], ys[row], xs[col+1], ys[row+1]))
                part = part.resize((tx[col+1]-tx[col], ty[row+1]-ty[row]), Image.Resampling.NEAREST)
                preview.alpha_composite(part, (i*144+8+tx[col], 12+ty[row]))
    pd = ImageDraw.Draw(preview)
    for i, label in enumerate(["Raised", "Hover", "Selected", "Disabled", "Panel", "Empty slot"]):
        pd.text((i*144+12, 85), label, fill="#dfe7ef")
    (ROOT.parent / "outputs").mkdir(exist_ok=True)
    preview.save(ROOT.parent / "outputs/editor-slate-skin.png")
    (DEST / (NAME + ".yy")).write_text(json.dumps(template, indent=2) + "\n", encoding="utf-8")


if __name__ == "__main__":
    build()
