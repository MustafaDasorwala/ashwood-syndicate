"""Slice the SpriteCook villager sheet into a clean 4x4 walk atlas.

Source is 200x200: 4 rows (down, left, left-again, up) of 8 frames, cell 25x50.
Rows two and three both face left, so the right-facing row is a mirror.
Frames are chosen by measured leg spread and lead bias, skipping the frames
where the model lost the facing and drew the face front-on.
"""
from PIL import Image

SRC = "villager_raw.png"
OUT = "villager_base.png"
CELL_W, CELL_H = 25, 50

# (source row, [frame indices], mirror)  -- output row order: down, left, right, up
#
# Column 0 is the idle pose and the cycle is idle-step-idle-step, so the two
# step frames must lead with opposite legs; they were picked by the measured
# lead bias, not by eye. Source frames where the model lost the facing and drew
# the face front-on (row 1 frames 3 and 4, row 3 frame 2) are excluded.
ROWS = [
    (0, [0, 1, 0, 7], False),
    (1, [0, 1, 0, 2], False),
    (1, [0, 1, 0, 2], True),
    (3, [5, 3, 5, 7], False),
]


def frame(im, row, col):
    return im.crop((col * CELL_W, row * CELL_H, (col + 1) * CELL_W, (row + 1) * CELL_H))


def bbox_alpha(tile, threshold=16):
    px = tile.load()
    xs, ys = [], []
    for y in range(tile.height):
        for x in range(tile.width):
            if px[x, y][3] > threshold:
                xs.append(x)
                ys.append(y)
    return (min(xs), min(ys), max(xs), max(ys)) if xs else None


def centred(tile):
    """Recentre horizontally and sit the feet on a fixed baseline.

    The generator drifts the character a pixel or two between frames; left
    uncorrected that drift reads as the sprite shivering in place.
    """
    box = bbox_alpha(tile)
    if box is None:
        return tile
    x0, y0, x1, y1 = box
    out = Image.new("RGBA", (CELL_W, CELL_H), (0, 0, 0, 0))
    content = tile.crop((x0, y0, x1 + 1, y1 + 1))
    dx = (CELL_W - content.width) // 2
    dy = CELL_H - content.height - 1  # one pixel of ground clearance
    out.alpha_composite(content, (dx, dy))
    return out


def main():
    src = Image.open(SRC).convert("RGBA")
    sheet = Image.new("RGBA", (CELL_W * 4, CELL_H * 4), (0, 0, 0, 0))
    for out_row, (src_row, cols, mirror) in enumerate(ROWS):
        for out_col, src_col in enumerate(cols):
            tile = centred(frame(src, src_row, src_col))
            if mirror:
                tile = tile.transpose(Image.FLIP_LEFT_RIGHT)
            sheet.alpha_composite(tile, (out_col * CELL_W, out_row * CELL_H))

    # Hard alpha: the generator leaves a faint halo that reads as grey fringing
    # once the tunic recolour shader multiplies it.
    px = sheet.load()
    for y in range(sheet.height):
        for x in range(sheet.width):
            r, g, b, a = px[x, y]
            px[x, y] = (r, g, b, 255 if a > 96 else 0)

    sheet.save(OUT)
    print(f"wrote {OUT} {sheet.size}")


main()
