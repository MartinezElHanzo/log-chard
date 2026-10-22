"""Generate the LogChard app icon — stylized orchard alley.

Two rows of apple trees recede toward a sunlit vanishing point, green
grass lane between them. Flat/geometric take on the reference orchard
photo; severity-red dots serve as the apples.

    python tool/gen_icon.py
"""

from PIL import Image, ImageDraw

BG = (30, 30, 30, 255)            # terminal dark #1E1E1E
ACCENT = (59, 142, 234, 255)      # selection blue border
SKY_GLOW = (255, 213, 79, 255)    # sun gold
SKY = (45, 62, 50, 255)           # dusky green sky
GRASS = (56, 142, 60, 255)        # lane green
GRASS_DARK = (39, 105, 42, 255)
LEAF = (67, 160, 71, 255)         # canopy green
LEAF_DARK = (46, 125, 50, 255)
APPLE = (205, 49, 49, 255)        # severity red
TRUNK = (109, 76, 65, 255)        # brown


def render(size: int) -> Image.Image:
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    s = size / 1024.0

    # tile with sky fill
    d.rounded_rectangle([64*s, 64*s, 960*s, 960*s], 180*s, fill=SKY)

    # sun at the vanishing point — soft halo + solid disc
    vx, vy = 512*s, 470*s
    for r, a in [(210, 35), (140, 70), (90, 120)]:
        d.ellipse([vx-r*s, vy-r*s, vx+r*s, vy+r*s],
                  fill=(SKY_GLOW[0], SKY_GLOW[1], SKY_GLOW[2], a))
    d.ellipse([vx-62*s, vy-62*s, vx+62*s, vy+62*s], fill=SKY_GLOW)

    # grass lane: trapezoid from bottom edge to vanishing point
    d.polygon([(64*s, 960*s), (960*s, 960*s), (vx+55*s, vy), (vx-55*s, vy)],
              fill=GRASS)
    d.polygon([(280*s, 960*s), (744*s, 960*s), (vx+18*s, vy), (vx-18*s, vy)],
              fill=GRASS_DARK)

    def tree(cx_, cy_, r, flip):
        """One apple tree: trunk, two-tone canopy, red apples."""
        # trunk
        d.rounded_rectangle([cx_-r*0.10*s, cy_, cx_+r*0.10*s,
                             cy_+r*1.05*s], r*0.08*s, fill=TRUNK)
        # canopy: dark under-layer, light top blob
        d.ellipse([cx_-r*s, cy_-r*0.95*s, cx_+r*s, cy_+r*0.55*s],
                  fill=LEAF_DARK)
        d.ellipse([cx_-r*0.82*s, cy_-r*1.12*s, cx_+r*0.82*s,
                   cy_+r*0.32*s], fill=LEAF)
        # apples — red dots scattered on the canopy
        for ax, ay, ar in [(-0.42, -0.35, 0.16), (0.30, -0.55, 0.14),
                           (0.05, -0.05, 0.15), (-0.15, -0.75, 0.12),
                           (0.55*flip, -0.15, 0.13)]:
            d.ellipse([cx_+(ax-ar)*r*s, cy_+(ay-ar)*r*s,
                       cx_+(ax+ar)*r*s, cy_+(ay+ar)*r*s], fill=APPLE)

    # two rows receding to the vanishing point — near big, far small
    # (x, canopy-center-y, radius, flip)
    trees = [
        (230, 720, 150, 1), (794, 720, 150, -1),
        (350, 630, 105, -1), (674, 630, 105, 1),
        (440, 560, 68, 1), (584, 560, 68, -1),
    ]
    for x, y, r, flip in trees:
        tree(x*s, y*s, r, flip)

    # clip the whole scene to the rounded tile, then stroke the border
    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [64*s, 64*s, 960*s, 960*s], 180*s, fill=255)
    clipped = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    clipped.paste(img, (0, 0), mask)
    ImageDraw.Draw(clipped).rounded_rectangle(
        [64*s, 64*s, 960*s, 960*s], 180*s,
        outline=ACCENT, width=int(26*s))

    return clipped


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
