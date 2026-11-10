#!/usr/bin/env python3
"""Generate the SnipPin app icon (squircle + viewfinder + pin dot)."""
from PIL import Image, ImageDraw
import os

S = 4096  # supersampled canvas
M = S // 8  # outer margin (icon grid)


def lerp(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def rounded_mask(size, radius):
    mask = Image.new("L", (size, size), 0)
    d = ImageDraw.Draw(mask)
    d.rounded_rectangle([0, 0, size - 1, size - 1], radius=radius, fill=255)
    return mask


def main():
    # Background gradient (indigo -> violet).
    bg = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    grad = Image.new("RGBA", (S, S))
    gd = ImageDraw.Draw(grad)
    top = (86, 116, 255, 255)
    bottom = (122, 78, 246, 255)
    for y in range(S):
        gd.line([(0, y), (S, y)], fill=lerp(top, bottom, y / S))

    body = Image.new("RGBA", (S - 2 * M, S - 2 * M), (0, 0, 0, 0))
    body.paste(grad.resize((S - 2 * M, S - 2 * M)), (0, 0))
    mask = rounded_mask(S - 2 * M, int((S - 2 * M) * 0.225))
    body.putalpha(mask)

    # Soft highlight at the top.
    glow = Image.new("RGBA", body.size, (0, 0, 0, 0))
    ImageDraw.Draw(glow).ellipse(
        [body.size[0] * 0.05, -body.size[1] * 0.55, body.size[0] * 0.95, body.size[1] * 0.55],
        fill=(255, 255, 255, 46),
    )
    body = Image.alpha_composite(body, glow)

    d = ImageDraw.Draw(body)
    w, h = body.size
    stroke = int(w * 0.055)
    arm = int(w * 0.135)
    inset = int(w * 0.205)
    left, top_ = inset, inset
    right, bottom = w - inset, h - inset
    color = (255, 255, 255, 255)

    def bracket(x, y, dx, dy):
        d.line([(x, y + dy * arm), (x, y), (x + dx * arm, y)], fill=color, width=stroke, joint="curve")

    r = stroke // 2
    for (x, y, dx, dy) in [
        (left, top_, 1, 1),
        (right, top_, -1, 1),
        (left, bottom, 1, -1),
        (right, bottom, -1, -1),
    ]:
        bracket(x, y, dx, dy)
        d.ellipse([x - r, y - r, x + r, y + r], fill=color)

    # Pin dot: white ring + red centre, slightly above the viewfinder centre.
    cx, cy = w * 0.5, h * 0.485
    ring = w * 0.155
    d.ellipse([cx - ring, cy - ring, cx + ring, cy + ring], fill=(255, 255, 255, 255))
    dot = w * 0.105
    d.ellipse([cx - dot, cy - dot, cx + dot, cy + dot], fill=(255, 84, 84, 255))
    # Little shine on the dot.
    d.ellipse(
        [cx - dot * 0.55, cy - dot * 0.75, cx + dot * 0.05, cy - dot * 0.15],
        fill=(255, 255, 255, 120),
    )

    icon = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    icon.alpha_composite(body, (M, M))
    icon = icon.resize((1024, 1024), Image.LANCZOS)

    os.makedirs("Resources", exist_ok=True)
    icon.save("Resources/AppIcon-1024.png")

    iconset = "Resources/AppIcon.iconset"
    os.makedirs(iconset, exist_ok=True)
    for base in (16, 32, 128, 256, 512):
        icon.resize((base, base), Image.LANCZOS).save(f"{iconset}/icon_{base}x{base}.png")
        icon.resize((base * 2, base * 2), Image.LANCZOS).save(f"{iconset}/icon_{base}x{base}@2x.png")
    print("wrote Resources/AppIcon-1024.png and", iconset)


if __name__ == "__main__":
    main()
