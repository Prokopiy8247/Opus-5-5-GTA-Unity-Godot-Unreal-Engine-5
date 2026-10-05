"""Build labelled contact sheets from an autotest screenshot folder.

usage: python Tools/contact_sheets.py <run folder>   (e.g. QA/Game/run6)
Writes sheet_<group>.png into the same folder; the individual screenshots stay git-ignored.
"""
import os
import re
import sys

from PIL import Image, ImageDraw

GROUPS = [
    ("districts", lambda n: re.match(r"^\d\d_", n) is not None),
    ("vehicles", lambda n: n.startswith("veh_")),
    ("vehicle_action", lambda n: n.startswith(("drive_", "carjack", "driveby", "boat", "heli_flight", "plane_flight",
                                                 "vehicle_", "modded_car", "explosion"))),
    ("gameplay", lambda n: n.startswith(("cover", "dive", "parachute", "peds_", "police_", "busted", "hospital",
                                           "taxi", "weapons", "cam_view"))),
    ("ui", lambda n: n.startswith("ui_")),
    ("world", lambda n: n.startswith(("time_", "weather_", "wildlife", "traffic_"))),
]
TW, TH, COLS = 400, 225, 4


def main(folder):
    names = sorted(f for f in os.listdir(folder) if f.endswith(".png") and not f.startswith("sheet_"))
    for group, match in GROUPS:
        sel = [n for n in names if match(n)]
        if not sel:
            continue
        rows = (len(sel) + COLS - 1) // COLS
        sheet = Image.new("RGB", (COLS * TW, rows * (TH + 20)), (24, 24, 28))
        draw = ImageDraw.Draw(sheet)
        for i, n in enumerate(sel):
            im = Image.open(os.path.join(folder, n)).convert("RGB")
            im.thumbnail((TW, TH))
            x, y = (i % COLS) * TW, (i // COLS) * (TH + 20)
            sheet.paste(im, (x, y))
            draw.text((x + 4, y + TH + 3), n[:-4], fill=(230, 230, 230))
        out = os.path.join(folder, "sheet_" + group + ".png")
        sheet.save(out, optimize=True)
        print(out, len(sel))


if __name__ == "__main__":
    main(sys.argv[1])
