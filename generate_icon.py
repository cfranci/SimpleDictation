#!/usr/bin/env python3
"""Generate SimpleDictation app icon: dark 3D dome squircle with red aura microphone."""

from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math

SIZE = 1024
CENTER = SIZE // 2

img = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
draw = ImageDraw.Draw(img)


def squircle_mask(size, radius_factor=0.22):
    """Create a squircle (superellipse) mask."""
    mask = Image.new("L", (size, size), 0)
    n = 4.5  # squircle exponent
    half = size / 2
    r = half * (1 - 0.02)  # slight inset
    for y in range(size):
        for x in range(size):
            nx = abs((x - half) / r)
            ny = abs((y - half) / r)
            if nx == 0 and ny == 0:
                mask.putpixel((x, y), 255)
            elif nx ** n + ny ** n <= 1.0:
                # Anti-alias the edge
                val = 1.0 - max(0, (nx ** n + ny ** n - 0.97)) / 0.03
                mask.putpixel((x, y), min(255, int(val * 255)))
    return mask


def draw_squircle_bg(img):
    """Draw the dark 3D dome squircle background."""
    bg = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)

    # Create squircle shape
    mask = squircle_mask(SIZE)

    # Dark base fill
    base = Image.new("RGBA", (SIZE, SIZE), (18, 18, 22, 255))

    # 3D dome highlight (subtle radial gradient from top-center)
    dome = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    dome_draw = ImageDraw.Draw(dome)
    highlight_cx, highlight_cy = CENTER, int(SIZE * 0.35)
    max_r = int(SIZE * 0.55)
    for r in range(max_r, 0, -1):
        t = 1.0 - (r / max_r)
        alpha = int(35 * t * t)  # subtle highlight
        gray = int(60 * t * t)
        dome_draw.ellipse(
            [highlight_cx - r, highlight_cy - r, highlight_cx + r, highlight_cy + r],
            fill=(gray + 30, gray + 28, gray + 35, alpha),
        )

    # Composite: base + dome
    result = Image.alpha_composite(base, dome)

    # Apply squircle mask
    result.putalpha(mask)
    img.paste(result, (0, 0), result)

    # Subtle border/edge highlight
    edge = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    edge_draw = ImageDraw.Draw(edge)
    # Draw a slightly lighter version at the edge
    edge_mask = squircle_mask(SIZE)
    inner_mask = Image.new("L", (SIZE, SIZE), 0)
    inner = squircle_mask(SIZE - 6)
    inner_mask.paste(inner, (3, 3))
    # Edge = outer mask - inner mask
    from PIL import ImageChops
    border_mask = ImageChops.subtract(edge_mask, inner_mask)
    edge_layer = Image.new("RGBA", (SIZE, SIZE), (120, 115, 130, 80))
    edge_layer.putalpha(border_mask)
    img.paste(edge_layer, (0, 0), edge_layer)

    return mask


def draw_red_aura(img, mic_cx, mic_cy):
    """Draw a red aura glow behind where the microphone will be."""
    aura = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    aura_draw = ImageDraw.Draw(aura)

    # Paint directly onto a solid black layer so we can see true brightness
    aura_base = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 255))
    aura_base_draw = ImageDraw.Draw(aura_base)

    # Core glow layers - very bright, high alpha
    layers = [
        (350, 120, 0, 10, 220),    # wide deep red
        (280, 180, 10, 20, 240),   # mid crimson
        (220, 230, 20, 30, 250),   # bright red
        (160, 255, 50, 40, 255),   # hot red
        (100, 255, 100, 70, 255),  # warm center
        (50, 255, 160, 130, 200),  # white-hot center
    ]

    for max_r, r_col, g_col, b_col, max_alpha in layers:
        for radius in range(max_r, 0, -2):
            t = 1.0 - (radius / max_r)
            alpha = int(max_alpha * t * t * t)
            aura_base_draw.ellipse(
                [mic_cx - radius, mic_cy - radius, mic_cx + radius, mic_cy + radius],
                fill=(r_col, g_col, b_col, alpha),
            )

    # Secondary glow blobs for organic, varied look
    offsets = [
        (-120, -80, 160, 0, 10, 200, 200),
        (100, 70, 220, 30, 20, 180, 190),
        (-80, 100, 180, 10, 35, 170, 170),
        (90, -90, 200, 5, 15, 190, 180),
        (0, -120, 190, 20, 30, 160, 160),
        (0, 120, 150, 5, 20, 150, 150),
    ]
    for ox, oy, r_c, g_c, b_c, rad, ma in offsets:
        cx, cy = mic_cx + ox, mic_cy + oy
        for radius in range(rad, 0, -2):
            t = 1.0 - (radius / rad)
            alpha = int(ma * t * t)
            aura_base_draw.ellipse(
                [cx - radius, cy - radius, cx + radius, cy + radius],
                fill=(r_c, g_c, b_c, alpha),
            )

    aura_base = aura_base.filter(ImageFilter.GaussianBlur(radius=35))

    # Use screen-like blending: composite the aura onto the main image
    # by extracting the aura colors and applying with high alpha
    aura = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    aura_px = aura.load()
    base_px = aura_base.load()
    for y in range(SIZE):
        for x in range(SIZE):
            r, g, b, a = base_px[x, y]
            # Brightness of the glow pixel vs pure black background
            brightness = max(r, g, b)
            if brightness > 5:
                aura_px[x, y] = (r, g, b, min(255, brightness + 30))


    # Composite onto main image
    img.paste(Image.alpha_composite(Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)),
              aura), (0, 0), aura)


def draw_microphone(img, cx, cy, scale=1.0):
    """Draw a clean, white microphone icon with subtle glow."""
    mic = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    mic_draw = ImageDraw.Draw(mic)

    s = scale
    white = (255, 255, 255, 245)
    white_stroke = (255, 255, 255, 240)

    # Mic body (capsule shape)
    body_w = int(70 * s)
    body_h = int(130 * s)
    body_r = body_w // 2
    body_top = cy - int(20 * s)
    body_bottom = body_top + body_h
    body_left = cx - body_w // 2
    body_right = cx + body_w // 2

    # Draw capsule: rect + two semicircles
    mic_draw.rounded_rectangle(
        [body_left, body_top - body_r, body_right, body_bottom],
        radius=body_r,
        fill=white,
    )

    # Cradle arc (U-shape around bottom of mic body)
    arc_w = int(6 * s)
    arc_radius = int(55 * s)
    arc_cy = body_bottom - int(10 * s)

    # Draw arc as a thick curved line
    arc_bbox = [
        cx - arc_radius, arc_cy - arc_radius,
        cx + arc_radius, arc_cy + arc_radius,
    ]
    mic_draw.arc(arc_bbox, start=0, end=180, fill=white_stroke, width=int(arc_w))

    # Stand (vertical line from arc bottom to base)
    stand_top = arc_cy + arc_radius
    stand_bottom = stand_top + int(50 * s)
    stand_w = int(6 * s)
    mic_draw.rounded_rectangle(
        [cx - stand_w // 2, stand_top, cx + stand_w // 2, stand_bottom],
        radius=stand_w // 2,
        fill=white,
    )

    # Base (horizontal line)
    base_w = int(80 * s)
    base_h = int(6 * s)
    base_r = base_h // 2
    mic_draw.rounded_rectangle(
        [cx - base_w // 2, stand_bottom - base_h // 2,
         cx + base_w // 2, stand_bottom + base_h // 2],
        radius=base_r,
        fill=white,
    )

    # Glow effect around mic
    glow = mic.filter(ImageFilter.GaussianBlur(radius=12))
    # Boost glow brightness
    glow2 = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    glow2.paste(glow, (0, 0), glow)
    img.paste(Image.alpha_composite(
        Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)), glow2), (0, 0), glow2)

    # Composite sharp mic on top
    img.paste(Image.alpha_composite(
        Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0)), mic), (0, 0), mic)


# Build the icon
print("Drawing squircle background...")
sq_mask = draw_squircle_bg(img)

mic_cx, mic_cy = CENTER, CENTER - 10
print("Drawing red aura...")
draw_red_aura(img, mic_cx, mic_cy)

# Re-apply squircle mask to clip the aura
clipped = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
clipped.paste(img, (0, 0))
clipped.putalpha(sq_mask)
img = clipped

print("Drawing microphone...")
draw_microphone(img, mic_cx, mic_cy, scale=1.8)

# Final squircle mask clip
final = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
final.paste(img, (0, 0))
final.putalpha(sq_mask)

out_path = "/Users/cf/Projects/SimpleDictation/icon_1024.png"
final.save(out_path, "PNG")
print(f"Saved {out_path}")
