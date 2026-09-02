exec(open('contrast.py').read().split('print("=== 现状')[0])

# 每套主题：浅色/深色各一组 token
P = {
"structural": {  # 工务：钢蓝 + 墨绿，中性偏冷。工程图纸的克制。
 "light": dict(surface=0xFFFFFF, band=0xEDF1F5, inset=0xE5EAF0,
               ink=0x0E1319, ink2=0x2F3944, muted=0x545E6C, faint=0x7C8797,
               rule=0xCFD7E0, beam=0x9BA7B6,
               plan=0x1B5183, planBG=0xDEEAF6, actual=0x115C48, actualBG=0xD8ECE4,
               mark=0x74510C, markBG=0xF4E9D4, stop=0x8B3020),
 "dark":  dict(surface=0x1A1D23, band=0x232830, inset=0x13161B,
               ink=0xEEF1F5, ink2=0xC8CFD9, muted=0x9CA6B3, faint=0x717A87,
               rule=0x353C47, beam=0x525C6A,
               plan=0x85B9EC, planBG=0x152738, actual=0x63D0AD, actualBG=0x0E2B22,
               mark=0xE0B366, markBG=0x2A2216, stop=0xEA9280)},

"paper": {  # 宣纸：暖纸底、墨、朱砂、竹青。长时间书写不刺眼。
 "light": dict(surface=0xFDFBF6, band=0xF2ECE0, inset=0xEAE3D4,
               ink=0x1A1813, ink2=0x3B372E, muted=0x635C4F, faint=0x8E8677,
               rule=0xD9D0BF, beam=0xB5AB97,
               plan=0x255468, planBG=0xE0EAEF, actual=0x3F6132, actualBG=0xE4EBDB,
               mark=0x8A4E18, markBG=0xF5E7D4, stop=0x993125),
 "dark":  dict(surface=0x201E19, band=0x292520, inset=0x171511,
               ink=0xF2EDE2, ink2=0xD3CBBB, muted=0xA79E8D, faint=0x7A7264,
               rule=0x3C3830, beam=0x5A5449,
               plan=0x88B6CB, planBG=0x18272E, actual=0x97BE84, actualBG=0x1A2416,
               mark=0xDCA063, markBG=0x2B2217, stop=0xE28575)},

"graphite": {  # 石墨：近乎单色，只留一点琥珀。计划/实际靠虚线-实心区分，不靠色相。
 "light": dict(surface=0xFFFFFF, band=0xEFEFEF, inset=0xE6E6E6,
               ink=0x0D0D0D, ink2=0x2E2E2E, muted=0x555555, faint=0x7E7E7E,
               rule=0xD2D2D2, beam=0x9E9E9E,
               plan=0x454B52, planBG=0xE9EBED, actual=0x14161A, actualBG=0xE0E2E4,
               mark=0x7A5500, markBG=0xF3EAD3, stop=0x8A2E20),
 "dark":  dict(surface=0x1B1B1D, band=0x242426, inset=0x141415,
               ink=0xF2F2F3, ink2=0xCBCBCD, muted=0x9E9EA2, faint=0x74747A,
               rule=0x36363A, beam=0x54545A,
               plan=0xAEB6C0, planBG=0x25272B, actual=0xF4F6F8, actualBG=0x2C2E32,
               mark=0xDDAE4A, markBG=0x2A2317, stop=0xE18B76)},

"pine": {  # 松墨：深绿偏蓝，安静。夜里久看不累。
 "light": dict(surface=0xFBFCFB, band=0xEAF0EC, inset=0xE1E9E4,
               ink=0x0E1513, ink2=0x2C3833, muted=0x4F5A54, faint=0x7B8781,
               rule=0xCDD8D1, beam=0x9AA8A0,
               plan=0x14586D, planBG=0xDEEBF0, actual=0x1F6543, actualBG=0xDCEDE3,
               mark=0x6F5310, markBG=0xF2EAD5, stop=0x8A3324),
 "dark":  dict(surface=0x171B19, band=0x1F2523, inset=0x111514,
               ink=0xEAF1ED, ink2=0xC4CFC9, muted=0x97A39D, faint=0x6D7973,
               rule=0x313935, beam=0x4D5852,
               plan=0x77BCD4, planBG=0x11252C, actual=0x6BCC9C, actualBG=0x102820,
               mark=0xD7AB5E, markBG=0x282116, stop=0xE28D79)},
}

TEXT = ["ink","ink2","muted","plan","actual","mark","stop"]
BGS  = ["surface","band","inset"]
fail = 0
for name, modes in P.items():
    for mode, t in modes.items():
        for fg in TEXT:
            for bg in BGS:
                r = ratio(t[fg], t[bg])
                if r < 4.5:
                    print(f"✗ {name}/{mode}: {fg} on {bg} = {r:.2f}")
                    fail += 1
        # 语义色压在自己的浅底上（时间胶囊、提示框）
        for fg, bg in [("plan","planBG"),("actual","actualBG"),("mark","markBG")]:
            r = ratio(t[fg], t[bg])
            if r < 4.5:
                print(f"✗ {name}/{mode}: {fg} on {bg} = {r:.2f}")
                fail += 1
        # 横梁要看得见：对 band 至少 1.6，对 surface 至少 1.6
        for bg in ["band","surface"]:
            r = ratio(t["beam"], t[bg])
            if r < 1.6:
                print(f"✗ {name}/{mode}: beam on {bg} = {r:.2f}（横梁看不见）")
                fail += 1
print(f"\n{'全部达标 ✓' if fail==0 else f'{fail} 项不达标'}")
