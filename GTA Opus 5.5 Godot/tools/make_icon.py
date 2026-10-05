import struct, math

W = H = 256
# Sunset Vector icon: night sky, sun disc, sea band, palm silhouette
def lerp(a, b, t): return tuple(a[i] + (b[i] - a[i]) * t for i in range(3))
SKY_TOP = (0.10, 0.07, 0.20)
SKY_MID = (0.62, 0.26, 0.35)
SUN = (1.00, 0.78, 0.32)
SEA = (0.10, 0.35, 0.45)
SEA_DARK = (0.05, 0.18, 0.28)
LAND = (0.12, 0.10, 0.14)

sun_c = (0.5 * W, 0.52 * H)
sun_r = 0.20 * W
horizon = 0.60 * H
px = bytearray()
for y in range(H - 1, -1, -1):          # ICO rows are bottom-up, pixels are BGRA
    for x in range(W):
        u, v = x / W, y / H
        if v < 0.45:
            c = lerp(SKY_TOP, SKY_MID, v / 0.45)
        elif v < horizon / H:
            c = lerp(SKY_MID, (0.98, 0.62, 0.42), (v - 0.45) / (horizon / H - 0.45))
        else:
            c = lerp(SEA, SEA_DARK, (v - horizon / H) / (1 - horizon / H))
        d = math.hypot(x - sun_c[0], y - sun_c[1])
        if v < horizon / H and d < sun_r:
            # sun with a soft rim halo
            t = min(1.0, max(0.0, (sun_r - d) / (0.06 * W)))
            c = lerp(c, SUN, 0.35 + 0.65 * t)
        elif v < horizon / H and d < sun_r * 1.35:
            c = lerp(c, SUN, 0.25 * (1.0 - (d - sun_r) / (0.35 * sun_r)))
        if horizon - 3 <= y <= horizon + 3:      # sun glitter line on the water
            c = lerp(c, SUN, 0.55)
        # palm on the left: leaning trunk with drooping fronds, in silhouette
        base_x, base_y = 0.34 * W, 0.78 * H
        top_x, top_y = 0.24 * W, 0.42 * H
        trunk = False
        if y > top_y:
            t = (base_y - y) / (base_y - top_y)
            trunk = abs(x - (top_x + (base_x - top_x) * t)) < 5.0
        frond = False
        # each frond is sampled into a polyline and tested as segments, so it reads as one solid leaf
        L = 0.56 * W
        for a in (-3.05, -2.70, -2.35, -2.00, -1.65, -1.30, -0.95):
            bend = -1.30
            pts = []
            for k in range(13):
                t = k / 12.0
                th = a + (bend - a) * t * t
                pts.append((top_x + math.cos(th) * L * t, top_y + math.sin(th) * L * t))
            for k in range(len(pts) - 1):
                if frond:
                    break
                t = (k + 1) / 12.0
                ax, ay = pts[k]
                bx, by = pts[k + 1]
                dx, dy = bx - ax, by - ay
                seg2 = dx * dx + dy * dy
                u = 0.0 if seg2 < 1e-6 else max(0.0, min(1.0, ((x - ax) * dx + (y - ay) * dy) / seg2))
                px_, py_ = ax + dx * u, ay + dy * u
                if math.hypot(x - px_, y - py_) < max(1.4, 5.0 * (1.0 - t) + 1.0):
                    frond = True
        if trunk or frond:
            c = LAND
        px += bytes((int(max(0, min(1, c[2])) * 255), int(max(0, min(1, c[1])) * 255), int(max(0, min(1, c[0])) * 255), 255))

# ICO container: one PNG-encoded entry per size (Windows Vista and later read PNG entries)
import zlib

PNG_SIG = bytes([137, 80, 78, 71, 13, 10, 26, 10])


def png(w, h, bgra_bottom_up):
    """PNG entry for an .ico: the buffer is raw ICO order (BGRA, bottom-up), PNG wants RGBA, top-down."""
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)
    raw = bytearray()
    for y in range(h):
        raw.append(0)
        src = (h - 1 - y) * w * 4
        for x in range(w):
            i = src + x * 4
            raw += bytes((bgra_bottom_up[i + 2], bgra_bottom_up[i + 1], bgra_bottom_up[i], bgra_bottom_up[i + 3]))
    return (PNG_SIG
            + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(raw), 9))
            + chunk(b"IEND", b""))


# `px` is stored bottom-up BGRA already (ICO row order), so it can be scaled as is
entries = []
for size in (256, 128, 64, 48, 32, 16):
    k = W // size
    small = bytearray(size * size * 4)
    for y in range(size):
        for x in range(size):
            acc = [0, 0, 0, 0]
            for dy in range(k):
                for dx in range(k):
                    i = ((y * k + dy) * W + x * k + dx) * 4
                    for c in range(4):
                        acc[c] += px[i + c]
            n = k * k
            j = (y * size + x) * 4
            for c in range(4):
                small[j + c] = acc[c] // n
    entries.append((size, png(size, size, bytes(small))))

out = struct.pack("<HHH", 0, 1, len(entries))
offset = 6 + 16 * len(entries)
body = b""
for size, data in entries:
    dim = 0 if size == 256 else size
    out += struct.pack("<BBBBHHII", dim, dim, 0, 0, 1, 32, len(data), offset)
    offset += len(data)
    body += data
open("icon.ico", "wb").write(out + body)
print("icon.ico written", len(out) + len(body), "bytes,", len(entries), "sizes")
