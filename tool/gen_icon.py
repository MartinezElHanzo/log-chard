"""Generate the LogChard app icon programmatically.

Design: dark terminal tile + log lines + severity dots
(green/yellow/red — same palette as the app's terminal theme).
Renders assets/icon.png (1024) and windows/runner/resources/app_icon.ico.

    python tool/gen_icon.py
"""

from PIL import Image, ImageDraw

SIZE = 1024
BG = (30, 30, 30, 255)            # terminal background #1E1E1E
FG = (204, 204, 204, 255)         # terminal foreground #CCCCCC
DOTS = [                          # severity palette from TerminalTheme
    (11, 188, 121, 255),          # INFO  #0DBC79
    (229, 229, 16, 255),          # WARN  #E5E510
    (205, 49, 49, 255),           # ERROR #CD3131
]
ACCENT = (59, 142, 234, 255)      # selection blue #3B8EEA


def rounded(draw, box, radius, **kw):
    draw.rounded_rectangle(box, radius=radius, **kw)


def render(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size / 1024.0

    # tile
    rounded(d, [64*s, 64*s, 960*s, 960*s], 180*s, fill=BG)
    rounded(d, [64*s, 64*s, 960*s, 960*s], 180*s,
            outline=ACCENT, width=int(28*s))

    # title-bar dots (terminal chrome)
    for i, c in enumerate([(255, 95, 86, 255), (255, 189, 46, 255),
                           (39, 201, 63, 255)]):
        x = 128*s + i*72*s
        d.ellipse([x, 118*s, x+44*s, 162*s], fill=c)

    # log lines: severity dot + text bar, widths varied
    lines = [(0, 560), (1, 640), (2, 460), (0, 620)]
    y = 300*s
    for sev, w in lines:
        d.ellipse([128*s, y, 188*s, y + 60*s], fill=DOTS[sev])
        rounded(d, [228*s, y + 8*s, 228*s + w*s, y + 52*s],
                22*s, fill=FG)
        y += 150*s

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
    # linux/desktop-entry friendly sizes
    for n in (512, 256, 128, 64, 48):
        icon.resize((n, n), Image.LANCZOS).save(
            f"assets/icon-{n}.png")
    print("assets/icon.png + icon-{512,256,128,64,48}.png + app_icon.ico")


if __name__ == "__main__":
    main()
