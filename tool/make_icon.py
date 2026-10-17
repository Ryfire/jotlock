# JotLock app icon generator.
# Renders the launcher icon (indigo gradient squircle + white padlock + pencil badge)
# and emits the Android adaptive-icon vector XMLs so PNG and vector stay in sync.
#
# Usage:  python tool/make_icon.py
# Requires: Pillow

import math
import os

from PIL import Image, ImageChops, ImageDraw, ImageFilter

S = 1024          # design space (all geometry defined here)
SS = 4            # supersampling factor for raster render
W = S * SS

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "tool", "out")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")

# Brand colors (Material indigo ramp, centered on the current #3F51B5)
IND_LIGHT = (0x5C, 0x6B, 0xC0)   # indigo 400 - top-left
IND_DARK = (0x30, 0x3F, 0x9F)    # indigo 700 - bottom-right
SHEEN_ALPHA = 30                 # peak white sheen (0-255)

# ---------------------------------------------------------------- geometry --
# Lock body (rounded rect)
BODY = (280, 520, 640, 830)
BODY_R = 72
# Keyhole: circle + narrow tapered slot, punched through the body.
# Slot top edge is tangent to the circle (no overlap -> safe for evenOdd).
KEY_C = (452, 634)
KEY_R = 34
SLOT = [(440, 668), (464, 668), (468, 706), (436, 706)]
# Shackle: ring segment on top of the body
SH_C = (460, 520)
SH_RO = 130
SH_RI = 74
SH_LEG_Y = 578          # legs sink into the body
# Pencil badge: pentagon (rect body + triangular tip), axis 45 deg down-left.
# The lock body's bottom-right corner is cut along a line parallel to the
# pencil (offset by GAP), so the pencil lies flush in a slot in the corner.
PEN_C = (660, 770)      # pencil center
PEN_LEN = 330           # overall length
PEN_TIP = 92            # tip length
PEN_HW = 46             # half width
GAP = 14                # gradient gap between body cut edge and pencil


def shackle_points():
    cx, cy = SH_C
    pts = [(cx - SH_RO, SH_LEG_Y), (cx - SH_RO, cy)]
    n = 48
    for i in range(n + 1):  # outer arc, pi..2pi (over the top)
        t = math.pi + math.pi * i / n
        pts.append((cx + SH_RO * math.cos(t), cy + SH_RO * math.sin(t)))
    pts += [(cx + SH_RO, SH_LEG_Y), (cx + SH_RI, SH_LEG_Y), (cx + SH_RI, cy)]
    for i in range(n + 1):  # inner arc, back 2pi..pi
        t = 2 * math.pi - math.pi * i / n
        pts.append((cx + SH_RI * math.cos(t), cy + SH_RI * math.sin(t)))
    pts += [(cx - SH_RI, SH_LEG_Y)]
    return pts


def keyhole_points():
    c = KEY_C
    n = 40
    return [(c[0] + KEY_R * math.cos(2 * math.pi * i / n),
             c[1] + KEY_R * math.sin(2 * math.pi * i / n)) for i in range(n)]


def slot_points():
    return SLOT


def pencil_points():
    s = math.cos(math.pi / 4)
    u = (-s, s)             # axis, pointing to the tip (down-left)
    n = (s, s)              # width direction
    hl = PEN_LEN / 2
    rear = (PEN_C[0] - u[0] * hl, PEN_C[1] - u[1] * hl)
    apex = (PEN_C[0] + u[0] * hl, PEN_C[1] + u[1] * hl)
    tb = (PEN_C[0] + u[0] * (hl - PEN_TIP), PEN_C[1] + u[1] * (hl - PEN_TIP))
    return [
        (rear[0] - n[0] * PEN_HW, rear[1] - n[1] * PEN_HW),
        (tb[0] - n[0] * PEN_HW, tb[1] - n[1] * PEN_HW),
        apex,
        (tb[0] + n[0] * PEN_HW, tb[1] + n[1] * PEN_HW),
        (rear[0] + n[0] * PEN_HW, rear[1] + n[1] * PEN_HW),
    ]


def rounded_rect_points(box, r, n=24):
    """Sample a rounded rectangle outline (for rasterization and clipping)."""
    x0, y0, x1, y1 = box
    arcs = [
        ((x1 - r, y0 + r), 270, 360),   # top-right
        ((x1 - r, y1 - r), 0, 90),      # bottom-right
        ((x0 + r, y1 - r), 90, 180),    # bottom-left
        ((x0 + r, y0 + r), 180, 270),   # top-left
    ]
    pts = []
    for (cx, cy), a0, a1 in arcs:
        for i in range(n + 1):
            t = math.radians(a0 + (a1 - a0) * i / n)
            pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    return pts


def clip_half_plane(pts, dist):
    """Sutherland-Hodgman clip of a polygon against the half-plane dist(p) >= 0."""
    out = []
    n = len(pts)
    for i in range(n):
        p, q = pts[i], pts[(i + 1) % n]
        dp, dq = dist(p), dist(q)
        if dp >= 0:
            out.append(p)
        if (dp >= 0) != (dq >= 0):
            t = dp / (dp - dq)
            out.append((p[0] + (q[0] - p[0]) * t, p[1] + (q[1] - p[1]) * t))
    return out


GLYPH_SHAPES = None  # filled by build_shapes()


def build_shapes():
    """All glyph geometry (design space) plus the composition bbox."""
    pencil = pencil_points()
    # cut line: parallel to the pencil axis, GAP away from its upper edge
    s = math.cos(math.pi / 4)
    cut_sum = (PEN_C[0] + PEN_C[1]) - (PEN_HW + GAP) / s
    body = clip_half_plane(rounded_rect_points(BODY, BODY_R),
                           lambda p: cut_sum - (p[0] + p[1]))
    shapes = {
        "body": body,
        "cut_sum": cut_sum,
        "keyhole_circle": keyhole_points(),
        "keyhole_slot": slot_points(),
        "shackle": shackle_points(),
        "pencil": pencil,
    }
    all_pts = shapes["shackle"] + pencil + body
    xs = [p[0] for p in all_pts]
    ys = [p[1] for p in all_pts]
    shapes["bbox"] = (min(xs), min(ys), max(xs), max(ys))
    return shapes


# ------------------------------------------------------------- transforms --
def legacy_transform(bbox):
    """Scale glyph so its largest side becomes FRAC of canvas, center it."""
    FRAC = 0.60
    cx = (bbox[0] + bbox[2]) / 2
    cy = (bbox[1] + bbox[3]) / 2
    k = FRAC * S / max(bbox[2] - bbox[0], bbox[3] - bbox[1])
    return lambda p: ((p[0] - cx) * k + S / 2, (p[1] - cy) * k + S / 2), k


def adaptive_transform(bbox):
    """Fit glyph inside the 66dp adaptive safe zone (center circle r=33)."""
    cx = (bbox[0] + bbox[2]) / 2
    cy = (bbox[1] + bbox[3]) / 2
    hx = (bbox[2] - bbox[0]) / 2
    hy = (bbox[3] - bbox[1]) / 2
    fs = 30.0 / math.hypot(hx, hy)
    tx = 54 - cx * fs
    ty = 54 - cy * fs
    return fs, tx, ty


# ---------------------------------------------------------------- drawing --
def linear_gradient(size, a, b):
    # oversized source so the rotated gradient fully covers the square,
    # then center-crop -> smooth diagonal gradient, no diamond banding
    d = int(size * 1.6)
    g = Image.linear_gradient("L").resize((d, d), Image.BICUBIC)
    g = g.rotate(45, expand=True, resample=Image.BICUBIC)
    w, h = g.size
    l, t = (w - size) // 2, (h - size) // 2
    g = g.crop((l, t, l + size, t + size))
    ca = Image.new("RGB", (size, size), a)
    cb = Image.new("RGB", (size, size), b)
    return Image.composite(cb, ca, g)


def rounded_rect_mask(size, box, radius):
    m = Image.new("L", (size * SS, size * SS), 0)
    d = ImageDraw.Draw(m)
    d.rounded_rectangle([c * SS for c in box], radius=radius * SS, fill=255)
    return m


def polygon_mask(size, pts):
    m = Image.new("L", (size * SS, size * SS), 0)
    d = ImageDraw.Draw(m)
    d.polygon([(x * SS, y * SS) for x, y in pts], fill=255)
    return m


def render_icon(size_out):
    """Render the full icon (squircle + glyph) and return an RGBA image."""
    shapes = GLYPH_SHAPES
    tr, _k = legacy_transform(shapes["bbox"])

    img = linear_gradient(W, IND_LIGHT, IND_DARK).convert("RGBA")

    # soft radial sheen, top-left
    sheen = Image.new("L", (W, W), 0)
    sd = ImageDraw.Draw(sheen)
    scx, scy, r = int(0.30 * W), int(0.24 * W), int(0.52 * W)
    sd.ellipse([scx - r, scy - r, scx + r, scy + r], fill=SHEEN_ALPHA)
    sheen = sheen.filter(ImageFilter.GaussianBlur(W // 9))
    white = Image.new("RGBA", (W, W), (255, 255, 255, 255))
    img.paste(white, (0, 0), sheen)

    # clip everything to the squircle
    squircle = rounded_rect_mask(S, (0, 0, S, S), int(0.223 * S))
    img.putalpha(squircle)

    # --- glyph layer ---------------------------------------------------
    mask_body = polygon_mask(S, [tr(p) for p in shapes["body"]])
    dkb = ImageDraw.Draw(mask_body)
    dkb.polygon([(x * SS, y * SS) for x, y in shapes["keyhole_circle"]], fill=0)
    dkb.polygon([(x * SS, y * SS) for x, y in shapes["keyhole_slot"]], fill=0)

    mask_shackle = polygon_mask(S, [tr(p) for p in shapes["shackle"]])
    mask_pencil = polygon_mask(S, [tr(p) for p in shapes["pencil"]])

    glyph_mask = ImageChops.lighter(mask_shackle, mask_body)
    glyph_mask = ImageChops.lighter(glyph_mask, mask_pencil)

    img.paste(white, (0, 0), glyph_mask)

    return img.resize((size_out, size_out), Image.LANCZOS)


# ------------------------------------------------------------- vector xml --
def fmt(v):
    s = f"{v:.2f}".rstrip("0").rstrip(".")
    return s if s else "0"


def path_poly(pts):
    d = f"M{fmt(pts[0][0])},{fmt(pts[0][1])}"
    for p in pts[1:]:
        d += f" L{fmt(p[0])},{fmt(p[1])}"
    return d + " Z"


def path_circle(c, r):
    return (f"M{fmt(c[0]-r)},{fmt(c[1])} "
            f"A{fmt(r)},{fmt(r)} 0 1 0 {fmt(c[0]+r)},{fmt(c[1])} "
            f"A{fmt(r)},{fmt(r)} 0 1 0 {fmt(c[0]-r)},{fmt(c[1])} Z")


def path_shackle():
    cx, cy = SH_C
    return (f"M{fmt(cx-SH_RO)},{fmt(SH_LEG_Y)} L{fmt(cx-SH_RO)},{fmt(cy)} "
            f"A{fmt(SH_RO)},{fmt(SH_RO)} 0 0 1 {fmt(cx+SH_RO)},{fmt(cy)} "
            f"L{fmt(cx+SH_RO)},{fmt(SH_LEG_Y)} L{fmt(cx+SH_RI)},{fmt(SH_LEG_Y)} "
            f"L{fmt(cx+SH_RI)},{fmt(cy)} "
            f"A{fmt(SH_RI)},{fmt(SH_RI)} 0 0 0 {fmt(cx-SH_RI)},{fmt(cy)} "
            f"L{fmt(cx-SH_RI)},{fmt(SH_LEG_Y)} Z")


def path_body_cut(cut_sum):
    """Rounded rect whose bottom-right corner is cut along x+y=cut_sum."""
    x0, y0, x1, y1 = BODY
    r = BODY_R
    y_rc = cut_sum - x1            # cut meets the right edge
    x_bc = cut_sum - y1            # cut meets the bottom edge
    assert y1 - r >= y_rc >= y0 + r, "cut misses the right edge"
    assert x1 - r >= x_bc >= x0 + r, "cut misses the bottom edge"
    return (f"M{fmt(x0+r)},{fmt(y0)} H{fmt(x1-r)} "
            f"A{fmt(r)},{fmt(r)} 0 0 1 {fmt(x1)},{fmt(y0+r)} "
            f"V{fmt(y_rc)} L{fmt(x_bc)},{fmt(y1)} "
            f"H{fmt(x0+r)} A{fmt(r)},{fmt(r)} 0 0 1 {fmt(x0)},{fmt(y1-r)} "
            f"V{fmt(y0+r)} A{fmt(r)},{fmt(r)} 0 0 1 {fmt(x0+r)},{fmt(y0)} Z")


def emit_foreground_xml(shapes):
    fs, tx, ty = adaptive_transform(shapes["bbox"])
    body = (path_body_cut(shapes["cut_sum"]) + " " +
            path_circle(KEY_C, KEY_R) + " " +
            path_poly(SLOT))
    xml = f"""<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <!-- JotLock: white padlock + pencil slotted into the cut corner, on an
         indigo gradient. Geometry lives in a 1024x1024 design space; the
         group maps it into the 108dp viewport and keeps it inside the 66dp
         safe zone. Regenerate with: python tool/make_icon.py -->
    <group
        android:scaleX="{fs:.6f}"
        android:scaleY="{fs:.6f}"
        android:translateX="{tx:.2f}"
        android:translateY="{ty:.2f}">
        <!-- shackle -->
        <path
            android:fillColor="#FFFFFFFF"
            android:pathData="{path_shackle()}" />
        <!-- body with punched keyhole (even-odd) -->
        <path
            android:fillColor="#FFFFFFFF"
            android:fillType="evenOdd"
            android:pathData="{body}" />
        <!-- pencil badge -->
        <path
            android:fillColor="#FFFFFFFF"
            android:pathData="{path_poly(shapes['pencil'])}" />
    </group>
</vector>
"""
    return xml


BACKGROUND_XML = """<vector xmlns:android="http://schemas.android.com/apk/res/android"
    xmlns:aapt="http://schemas.android.com/aapt"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <!-- indigo diagonal gradient, top-left to bottom-right -->
    <path android:pathData="M0,0 H108 V108 H0 Z">
        <aapt:attr name="android:fillColor">
            <gradient
                android:type="linear"
                android:startX="0"
                android:startY="0"
                android:endX="108"
                android:endY="108">
                <item android:offset="0" android:color="#FF5C6BC0" />
                <item android:offset="1" android:color="#FF303F9F" />
            </gradient>
        </aapt:attr>
    </path>
    <!-- soft sheen highlight, top-left -->
    <path android:pathData="M0,0 H108 V108 H0 Z">
        <aapt:attr name="android:fillColor">
            <gradient
                android:type="radial"
                android:centerX="32"
                android:centerY="26"
                android:gradientRadius="56">
                <item android:offset="0" android:color="#24FFFFFF" />
                <item android:offset="1" android:color="#00FFFFFF" />
            </gradient>
        </aapt:attr>
    </path>
</vector>
"""


# ====================== "J on a note" (About mark) ==========================
# Second glyph design: indigo squircle + off-white note sheet with a dog-eared
# top-right corner + a bold round-capped "J". Currently used as the About-page
# mark (assets/images/jot_next_icon.png); kept in this pipeline so it can
# graduate to the launcher icon later with the same geometry and transforms.
NEXT_SHEET = (312, 240, 712, 784)   # portrait note sheet, centered on canvas
NEXT_SHEET_R = 44                   # sheet corner radius
NEXT_CUT = 120                      # dog-ear size along top and right edges
NEXT_HOOK_C = (512, 560)            # J hook: semicircle center (bottom of stem)
NEXT_HOOK_R = 60
NEXT_STEM_X = 572                   # stem x = hook's right end
NEXT_STEM_TOP = 400
NEXT_STROKE = 64                    # J stroke width
SHEET_FILL = (0xF7, 0xF4, 0xEC)     # warm paper
FOLD_FILL = (0xDD, 0xD7, 0xCB)      # folded flap, slightly shaded
J_INK = IND_DARK                    # deep indigo, ties to the background
# Pencil resting in the dog-ear notch, parallel to the crease with the same
# 14-unit flush gap as the launcher icon's pencil-in-the-slot motif. Fully
# visible (a half-buried pencil reads as an abstract dart).
NEXT_PENCIL_REAR = (616, 220)
NEXT_PENCIL_AXIS = (math.cos(math.pi / 4), math.sin(math.pi / 4))
NEXT_PENCIL_LEN = 156            # rear end to tip apex
NEXT_PENCIL_TIP = 40
NEXT_PENCIL_HW = 17              # half width
PENCIL_FILL = (0xFF, 0xFF, 0xFF)


def next_pencil_points():
    ux, uy = NEXT_PENCIL_AXIS
    nx, ny = -uy, ux             # perpendicular (width direction)
    rx, ry = NEXT_PENCIL_REAR
    L, tip, hw = NEXT_PENCIL_LEN, NEXT_PENCIL_TIP, NEXT_PENCIL_HW
    apex = (rx + ux * L, ry + uy * L)
    tb = (rx + ux * (L - tip), ry + uy * (L - tip))
    return [
        (rx - nx * hw, ry - ny * hw),
        (tb[0] - nx * hw, tb[1] - ny * hw),
        apex,
        (tb[0] + nx * hw, tb[1] + ny * hw),
        (rx + nx * hw, ry + ny * hw),
    ]


def next_shapes(with_pencil=False):
    """Sheet with cut corner, fold flap, J path, and the composition bbox."""
    x0, y0, x1, y1 = NEXT_SHEET
    cut_x = x1 - NEXT_CUT          # cut meets the top edge here
    cut_y = y0 + NEXT_CUT          # cut meets the right edge here
    # cut line: x - y = cut_x - y0 ; interior lies at smaller x - y
    sheet = clip_half_plane(rounded_rect_points(NEXT_SHEET, NEXT_SHEET_R),
                            lambda p: (cut_x - y0) - (p[0] - p[1]))
    fold = [(cut_x, y0), (x1, cut_y), (cut_x, cut_y)]
    cx, cy = NEXT_HOOK_C
    r = NEXT_HOOK_R
    j_pts = [(NEXT_STEM_X, NEXT_STEM_TOP), (NEXT_STEM_X, cy)]
    n = 32
    for i in range(1, n + 1):      # 0..180 deg through the bottom (+y)
        t = math.pi * i / n
        j_pts.append((cx + r * math.cos(t), cy + r * math.sin(t)))
    shapes = {"sheet": sheet, "fold": fold, "j": j_pts}
    if with_pencil:
        shapes["pencil"] = next_pencil_points()
    all_pts = sheet + fold + j_pts
    if with_pencil:
        all_pts += shapes["pencil"]
    xs = [p[0] for p in all_pts]
    ys = [p[1] for p in all_pts]
    shapes["bbox"] = (min(xs), min(ys), max(xs), max(ys))
    return shapes


def render_next_icon(size_out, with_pencil=False):
    """Render the J-on-note icon (squircle + sheet + J) as RGBA."""
    sh = next_shapes(with_pencil)
    tr, _k = legacy_transform(sh["bbox"])

    img = linear_gradient(W, IND_LIGHT, IND_DARK).convert("RGBA")

    # soft radial sheen, top-left (same treatment as the launcher icon)
    sheen = Image.new("L", (W, W), 0)
    sd = ImageDraw.Draw(sheen)
    scx, scy, r = int(0.30 * W), int(0.24 * W), int(0.52 * W)
    sd.ellipse([scx - r, scy - r, scx + r, scy + r], fill=SHEEN_ALPHA)
    sheen = sheen.filter(ImageFilter.GaussianBlur(W // 9))
    white = Image.new("RGBA", (W, W), (255, 255, 255, 255))
    img.paste(white, (0, 0), sheen)

    # clip everything to the squircle
    squircle = rounded_rect_mask(S, (0, 0, S, S), int(0.223 * S))
    img.putalpha(squircle)

    sheet_mask = polygon_mask(S, [tr(p) for p in sh["sheet"]])
    img.paste(Image.new("RGBA", (W, W), SHEET_FILL + (255,)), (0, 0),
              sheet_mask)

    # pencil first, so the fold flap painted next hides its rear end
    if with_pencil:
        pencil_mask = polygon_mask(S, [tr(p) for p in sh["pencil"]])
        img.paste(Image.new("RGBA", (W, W), PENCIL_FILL + (255,)), (0, 0),
                  pencil_mask)

    fold_mask = polygon_mask(S, [tr(p) for p in sh["fold"]])
    img.paste(Image.new("RGBA", (W, W), FOLD_FILL + (255,)), (0, 0),
              fold_mask)

    # J: thick stroke with round caps and round joints
    stroke = Image.new("L", (W, W), 0)
    sd = ImageDraw.Draw(stroke)
    jpts = [(p[0] * SS, p[1] * SS) for p in map(tr, sh["j"])]
    sd.line(jpts, fill=255, width=NEXT_STROKE * SS, joint="curve")
    cap_r = NEXT_STROKE * SS / 2
    for end in (jpts[0], jpts[-1]):
        sd.ellipse([end[0] - cap_r, end[1] - cap_r,
                    end[0] + cap_r, end[1] + cap_r], fill=255)
    img.paste(Image.new("RGBA", (W, W), J_INK + (255,)), (0, 0), stroke)

    return img.resize((size_out, size_out), Image.LANCZOS)


def emit_next_foreground_xml(with_pencil=False):
    """Adaptive-icon foreground for the J-on-note design (future launcher)."""
    sh = next_shapes(with_pencil)
    fs, tx, ty = adaptive_transform(sh["bbox"])
    x0, y0, x1, y1 = NEXT_SHEET
    r = NEXT_SHEET_R
    cut_x = x1 - NEXT_CUT
    cut_y = y0 + NEXT_CUT
    cx, cy = NEXT_HOOK_C
    rr = NEXT_HOOK_R
    sheet_path = (f"M{fmt(x0 + r)},{fmt(y0)} H{fmt(cut_x)} "
                  f"L{fmt(x1)},{fmt(cut_y)} V{fmt(y1 - r)} "
                  f"A{fmt(r)},{fmt(r)} 0 0 1 {fmt(x1 - r)},{fmt(y1)} "
                  f"H{fmt(x0 + r)} "
                  f"A{fmt(r)},{fmt(r)} 0 0 1 {fmt(x0)},{fmt(y1 - r)} "
                  f"V{fmt(y0 + r)} "
                  f"A{fmt(r)},{fmt(r)} 0 0 1 {fmt(x0 + r)},{fmt(y0)} Z")
    j_path = (f"M{fmt(NEXT_STEM_X)},{fmt(NEXT_STEM_TOP)} "
              f"L{fmt(NEXT_STEM_X)},{fmt(cy)} "
              f"A{fmt(rr)},{fmt(rr)} 0 0 1 {fmt(cx - rr)},{fmt(cy)}")
    pencil_path = ""
    if with_pencil:
        pencil_path = (f"<!-- pencil resting in the notch -->\n"
                       f"        <path\n"
                       f"            android:fillColor=\"#FFFFFFFF\"\n"
                       f"            android:pathData=\"{path_poly(sh['pencil'])}\" />\n"
                       f"        ")
    xml = f"""<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <!-- JotLock "J on a note" mark: off-white dog-eared sheet with an
         indigo J, on the indigo gradient. Geometry lives in a 1024x1024
         design space; the group maps it into the 108dp viewport and keeps
         it inside the 66dp safe zone. Regenerate with: python tool/make_icon.py -->
    <group
        android:scaleX="{fs:.6f}"
        android:scaleY="{fs:.6f}"
        android:translateX="{tx:.2f}"
        android:translateY="{ty:.2f}">
        <!-- sheet with dog-eared top-right corner -->
        <path
            android:fillColor="#FFF7F4EC"
            android:pathData="{sheet_path}" />
        {pencil_path}<!-- folded flap -->
        <path
            android:fillColor="#FFDDD7CB"
            android:pathData="{path_poly(sh['fold'])}" />
        <!-- J monogram -->
        <path
            android:strokeColor="#FF303F9F"
            android:strokeWidth="{fmt(NEXT_STROKE)}"
            android:strokeLineCap="round"
            android:pathData="{j_path}" />
    </group>
</vector>
"""
    return xml


def emit_next_design():
    """Render + emit every artifact for the J-on-note design."""
    os.makedirs(OUT, exist_ok=True)
    master = render_next_icon(S)
    master.save(os.path.join(OUT, "jot_next_1024.png"))
    master.resize((512, 512), Image.LANCZOS).save(
        os.path.join(OUT, "jot_next_512.png"))

    for name, bg in (("dark", (28, 27, 31)), ("light", (250, 250, 250))):
        strip = Image.new("RGB", (5 * 200 + 60, 220), bg)
        for i, px in enumerate((48, 72, 96, 144, 192)):
            ic = master.resize((px, px), Image.LANCZOS)
            strip.paste(ic, (30 + i * 200 + (192 - px) // 2,
                             110 - px // 2), ic)
        strip.save(os.path.join(OUT, f"jot_next_preview_{name}.png"))

    with open(os.path.join(OUT, "jot_next_foreground.xml"), "w") as f:
        f.write(emit_next_foreground_xml())

    # pencil variant (candidate refinement of the mark)
    master_p = render_next_icon(S, with_pencil=True)
    master_p.save(os.path.join(OUT, "jot_next_pencil_1024.png"))
    master_p.resize((512, 512), Image.LANCZOS).save(
        os.path.join(OUT, "jot_next_pencil_512.png"))
    for name, bg in (("dark", (28, 27, 31)), ("light", (250, 250, 250))):
        strip = Image.new("RGB", (5 * 200 + 60, 220), bg)
        for i, px in enumerate((48, 72, 96, 144, 192)):
            ic = master_p.resize((px, px), Image.LANCZOS)
            strip.paste(ic, (30 + i * 200 + (192 - px) // 2,
                             110 - px // 2), ic)
        strip.save(os.path.join(OUT, f"jot_next_pencil_preview_{name}.png"))
    with open(os.path.join(OUT, "jot_next_pencil_foreground.xml"), "w") as f:
        f.write(emit_next_foreground_xml(with_pencil=True))

    print("next-design bbox:",
          tuple(round(v, 1) for v in next_shapes()["bbox"]))
    print("next-design outputs written to", OUT)


def main():
    os.makedirs(OUT, exist_ok=True)
    global GLYPH_SHAPES
    GLYPH_SHAPES = build_shapes()
    shapes = GLYPH_SHAPES

    # raster master + legacy densities
    master = render_icon(S)
    master.save(os.path.join(OUT, "icon_1024.png"))

    densities = {"mdpi": 48, "hdpi": 72, "xhdpi": 96, "xxhdpi": 144,
                 "xxxhdpi": 192}
    for dpi, px in densities.items():
        master.resize((px, px), Image.LANCZOS).save(
            os.path.join(OUT, f"ic_launcher_{dpi}_{px}.png"))

    # launcher-size preview strips (dark + light backgrounds)
    for name, bg in (("dark", (28, 27, 31)), ("light", (250, 250, 250))):
        strip = Image.new("RGB", (5 * 200 + 60, 220), bg)
        for i, px in enumerate((48, 72, 96, 144, 192)):
            ic = master.resize((px, px), Image.LANCZOS)
            strip.paste(ic, (30 + i * 200 + (192 - px) // 2,
                             110 - px // 2), ic)
        strip.save(os.path.join(OUT, f"preview_{name}.png"))

    # vector xml for the adaptive icon
    with open(os.path.join(OUT, "ic_launcher_foreground.xml"), "w") as f:
        f.write(emit_foreground_xml(shapes))
    with open(os.path.join(OUT, "ic_launcher_background.xml"), "w") as f:
        f.write(BACKGROUND_XML)

    fs, tx, ty = adaptive_transform(shapes["bbox"])
    print(f"bbox: {tuple(round(v, 1) for v in shapes['bbox'])}")
    print(f"adaptive: scale={fs:.4f} translate=({tx:.2f},{ty:.2f})")
    print("written to", OUT)


if __name__ == "__main__":
    main()
    emit_next_design()
