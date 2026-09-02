def lin(c):
    c = c/255
    return c/12.92 if c <= 0.04045 else ((c+0.055)/1.055)**2.4
def L(h):
    r,g,b = (h>>16)&255, (h>>8)&255, h&255
    return 0.2126*lin(r)+0.7152*lin(g)+0.0722*lin(b)
def ratio(a,b):
    la,lb = L(a),L(b)
    hi,lo = max(la,lb),min(la,lb)
    return (hi+0.05)/(lo+0.05)

print("=== 现状（工务主题）小标签对比度 ===")
for name,fg,bg in [("faint on surface(浅)",0x9AA3AF,0xFFFFFF),
                   ("faint on band(浅)",   0x9AA3AF,0xF2F4F7),
                   ("faint on surface(深)",0x6E7681,0x1A1D23),
                   ("faint on band(深)",   0x6E7681,0x22262E),
                   ("muted on surface(浅)",0x6B7480,0xFFFFFF),
                   ("muted on surface(深)",0x98A1AE,0x1A1D23)]:
    r = ratio(fg,bg)
    print(f"  {name:22s} {r:5.2f}:1  {'✓ AA' if r>=4.5 else '✗ 不达标（小字需 4.5:1）'}")
