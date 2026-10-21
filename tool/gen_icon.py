"""Generate the LogChard app icon programmatically.

Design: an orchard tree built from terminal glyphs — the canopy is a
stack of log lines, severity dots hang as fruit. Merges "log" and
"orchard" in one mark.

    python tool/gen_icon.py
"""

from PIL import Image, ImageDraw

BG = (30, 30, 30, 255)            # terminal background #1E1E1E
FG = (204, 204, 204, 255)         # terminal foreground #CCCCCC
TRUNK = (150, 150, 150, 255)      # slightly dimmer glyph for trunk
ACCENT = (59, 142, 234, 255)      # selection blue #3B8EEA
FRUIT = [                         # severity palette -> orchard fruit
    (11, 188, 121, 255),          # INFO  #0DBC79
    (229, 229, 16, 255),          # WARN  #E5E510
    (205, 49, 49, 255),           # ERROR #CD3131
]


def rounded(draw, box, radius, **kw):
    draw.rounded_rectangle(box, radius=radius, fill=kw.get('fill'),
                           outline=kw.get('outline'),
                           width=kw.get('width', 1))


def render(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size / 1024.0

    # tile
    d.rounded_rectangle([64*s, 64*s, 960*s, 960*s], 180*s, fill=BG,
                        outline=ACCENT, width=int(26*s))

    cx = 512*s

    # canopy: log lines as foliage — pyramid silhouette (narrow top,
    # wide middle, narrow bottom) reads as a tree at any size.
    canopy = [300, 520, 600, 480, 340]
    fruits = [0, 1, 2, 0, 1]      # severity color per line
    sides = [1, -1, 1, -1, 1]     # alternate left/right branch ends
    bar_h = 66*s
    gap = 24*s
    y = 190*s
    for i, w in enumerate(canopy):
        left = cx - w*s/2
        rounded(d, [left, y, left + w*s, y + bar_h], bar_h/2, fill=FG)
        # fruit hanging on a branch end — severity dot, orchard fruit
        fruit = FRUIT[fruits[i]]
        fx = left if sides[i] < 0 else left + w*s
        fy = y + bar_h/2
        d.ellipse([fx - 30*s, fy - 30*s, fx + 30*s, fy + 30*s],
                  fill=fruit)
        y += bar_h + gap

    # trunk: one solid vertical bar
    trunk_top = y - 6*s
    trunk_bot = trunk_top + 190*s
    rounded(d, [cx - 30*s, trunk_top, cx + 30*s, trunk_bot],
            20*s, fill=TRUNK)

    # ground line — one last log line, dimmer, spanning the roots
    rounded(d, [cx - 300*s, trunk_bot + 20*s, cx + 300*s,
                trunk_bot + 52*s], 16*s, fill=(90, 90, 90, 255))

    return img


def main() -> None:
    icon = render(1024)
    icon.save("assets/icon.png")

    sizes = [256, 128, 64, 48, 32, 24, 16]
    resized = [icon.resize((n, n), Image.LANCZOS) for n in sizes]
    resized[0].save(
        "windows/runner/resources/app_icon.ico",
        format="ICO",
        sizes=[(n, n) for n in sizes],
        append_images=resized[1:],
    )
    for n in (512, 256, 128, 64, 48):
        icon.resize((n, n), Image.LANCZOS).save(
            f"assets/icon-{n}.png")
    print("done")


if __name__ == "__main__":
    main()
