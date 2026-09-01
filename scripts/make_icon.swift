#!/usr/bin/env swift
// 生成应用图标（方案二「双梁」）：深底 + 上横计划蓝 + 下横实际绿 + 中间腹板浅色。
//
// 图标本身就说明这个 app 干什么：把「意图」和「事实」两条横梁架起来。
// 形与 GongMark / 界面里的计划-实际配色同源，三处是同一个形，不是三个近似的形。
//
// 小尺寸（≤64px）单独走一套更粗的比例：按大图直接缩，15/128 的横梁在 16px 下
// 只有 1.9px，会糊成一条灰线。Apple 自己的图标也都为小尺寸另画简化版。
import AppKit
import CoreGraphics

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "./build/Rike.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func rgb(_ v: UInt32) -> CGColor {
    CGColor(srgbRed: CGFloat((v >> 16) & 0xFF) / 255,
            green: CGFloat((v >> 8) & 0xFF) / 255,
            blue: CGFloat(v & 0xFF) / 255, alpha: 1)
}
let tileTop  = rgb(0x1B2029)     // 深底，顶部略亮，给一点体积感
let tileBot  = rgb(0x0E1116)
let barTop   = rgb(0x79ADE0)     // 计划：意图
let barBot   = rgb(0x5CC5A5)     // 实际：事实
let web      = rgb(0xEDF1F6)

func render(px: Int) -> CGImage {
    let s = CGFloat(px)
    let cs = CGColorSpaceCreateDeviceRGB()
    let ctx = CGContext(data: nil, width: px, height: px, bitsPerComponent: 8, bytesPerRow: 0,
                        space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)

    let compact = px <= 64
    // 大图按 Apple 的 824/1024 内容框；小图少留白，否则形本身就没剩几个像素
    let inset = (compact ? 0.055 : 0.0977) * s
    let side = s - inset * 2
    let radius = side * 0.2246

    // 底
    let tile = CGPath(roundedRect: CGRect(x: inset, y: inset, width: side, height: side),
                      cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(tile); ctx.clip()
    let grad = CGGradient(colorsSpace: cs, colors: [tileTop, tileBot] as CFArray,
                          locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])
    ctx.restoreGState()

    // 「工」：比例取自 128 见方的源形；小图加粗横梁、收窄留白
    // 小图的腹板必须**明显窄于**它自己的高度，否则 工 会读成一个方块。
    // 大图 15/128 的横梁在 16px 下只剩 1.9px，所以小图整体加粗、减留白。
    let barH: CGFloat  = compact ? 0.160 : 0.117
    let barX: CGFloat  = compact ? 0.140 : 0.219
    let barW: CGFloat  = compact ? 0.720 : 0.562
    let webW: CGFloat  = compact ? 0.160 : 0.156
    let topY: CGFloat  = compact ? 0.170 : 0.234
    let botY: CGFloat  = 1 - topY - barH

    func fill(_ c: CGColor, _ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) {
        // CoreGraphics 原点在左下；设计稿从上往下量，这里翻一次
        var r = CGRect(x: inset + x * side, y: inset + (1 - y - h) * side,
                       width: w * side, height: h * side)
        ctx.setFillColor(c)
        if compact {
            // 对齐整像素：16/32px 下半像素边会被抗锯齿抹成灰边，形就糊了
            r = CGRect(x: r.minX.rounded(), y: r.minY.rounded(),
                       width: max(1, r.width.rounded()), height: max(1, r.height.rounded()))
            ctx.fill(r)          // 小图不倒角：1px 的圆角只会让边缘发灰
        } else {
            ctx.addPath(CGPath(roundedRect: r, cornerWidth: side * 0.012,
                               cornerHeight: side * 0.012, transform: nil))
            ctx.fillPath()
        }
    }
    // 腹板画到两条横梁**内部**（先画，横梁覆盖其上）：
    // 小图整像素取整时相邻矩形各自取整会留下 1px 缝，让它们重叠就没有缝。
    fill(web,    (1 - webW) / 2, topY, webW, botY + barH - topY)
    fill(barTop, barX, topY, barW, barH)
    fill(barBot, barX, botY, barW, barH)

    return ctx.makeImage()!
}

func write(_ img: CGImage, _ name: String) {
    let url = URL(fileURLWithPath: outDir).appendingPathComponent(name)
    let dst = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, img, nil)
    guard CGImageDestinationFinalize(dst) else { fatalError("写入失败 \(name)") }
}

for (px, name) in [(16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
                   (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
                   (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
                   (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
                   (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png")] {
    write(render(px: px), name)
}
print("iconset → \(outDir)")
