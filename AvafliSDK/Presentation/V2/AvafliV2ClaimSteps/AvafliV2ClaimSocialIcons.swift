//
//  AvafliV2ClaimSocialIcons.swift
//  AvafliSDK
//
//  Official Avafli brand glyphs for the step-4 "Share on Social Media:" row
//  (Instagram / Facebook / X / Snapchat / TikTok). Each glyph is the exact
//  Figma-exported SVG path data (48x48 viewBox), rendered in-code through a
//  minimal SVG path-data parser so the SDK ships no image assets for them.
//

import SwiftUI

struct AvafliSocialGlyph: View {
    enum Kind: CaseIterable {
        case instagram, facebook, x, snapchat, tiktok

        var displayName: String {
            switch self {
            case .instagram: return "Instagram"
            case .facebook: return "Facebook"
            case .x: return "X"
            case .snapchat: return "Snapchat"
            case .tiktok: return "TikTok"
            }
        }

        /// Figma-exported path data, 48x48 viewBox. Source of truth for the
        /// official brand set — do not hand-edit.
        var pathData: [String] {
            switch self {
            case .instagram: return AvafliSocialPathData.instagram
            case .facebook: return AvafliSocialPathData.facebook
            case .x: return AvafliSocialPathData.x
            case .snapchat: return AvafliSocialPathData.snapchat
            case .tiktok: return AvafliSocialPathData.tiktok
            }
        }
    }

    let kind: Kind

    var body: some View {
        AvafliSVGGlyphShape(pathData: kind.pathData)
            .fill(Color.white, style: FillStyle(eoFill: false, antialiased: true))
    }
}

/// A SwiftUI `Shape` built from SVG path-data strings (the `d` attribute),
/// scaled from the design viewBox to the layout rect.
///
/// Supports the absolute and relative forms of M, L, H, V, C, and Z — the
/// full command set used by the Avafli brand exports. Unknown commands stop
/// parsing (debug-asserting) rather than guessing.
struct AvafliSVGGlyphShape: Shape {
    let pathData: [String]
    var viewBoxSize: CGFloat = 48

    func path(in rect: CGRect) -> Path {
        var combined = Path()
        for d in pathData {
            combined.addPath(Self.parse(d))
        }
        let scale = min(rect.width, rect.height) / viewBoxSize
        let transform = CGAffineTransform(translationX: rect.minX, y: rect.minY)
            .scaledBy(x: scale, y: scale)
        return combined.applying(transform)
    }

    static func parse(_ d: String) -> Path {
        var path = Path()
        let bytes = Array(d.utf8)
        var i = 0
        var current = CGPoint.zero
        var subpathStart = CGPoint.zero
        var command: UInt8 = 0

        func isSeparator(_ c: UInt8) -> Bool {
            c == 0x20 || c == 0x2C || c == 0x09 || c == 0x0A || c == 0x0D
        }

        func skipSeparators() {
            while i < bytes.count, isSeparator(bytes[i]) { i += 1 }
        }

        func number() -> CGFloat? {
            skipSeparators()
            let start = i
            if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") {
                i += 1
            }
            var seenDot = false
            while i < bytes.count {
                let c = bytes[i]
                if c >= UInt8(ascii: "0"), c <= UInt8(ascii: "9") {
                    i += 1
                } else if c == UInt8(ascii: "."), !seenDot {
                    seenDot = true
                    i += 1
                } else {
                    break
                }
            }
            if i < bytes.count, bytes[i] == UInt8(ascii: "e") || bytes[i] == UInt8(ascii: "E") {
                i += 1
                if i < bytes.count, bytes[i] == UInt8(ascii: "+") || bytes[i] == UInt8(ascii: "-") {
                    i += 1
                }
                while i < bytes.count, bytes[i] >= UInt8(ascii: "0"), bytes[i] <= UInt8(ascii: "9") {
                    i += 1
                }
            }
            guard i > start, let value = Double(String(decoding: bytes[start..<i], as: UTF8.self)) else {
                return nil
            }
            return CGFloat(value)
        }

        func point(relative: Bool) -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return relative ? CGPoint(x: current.x + x, y: current.y + y) : CGPoint(x: x, y: y)
        }

        while i < bytes.count {
            skipSeparators()
            guard i < bytes.count else { break }

            let c = bytes[i]
            let isLetter = (c >= UInt8(ascii: "A") && c <= UInt8(ascii: "Z"))
                || (c >= UInt8(ascii: "a") && c <= UInt8(ascii: "z"))
            if isLetter {
                command = c
                i += 1
            } else if command == UInt8(ascii: "M") {
                // Implicit repeat after moveto is lineto (SVG spec).
                command = UInt8(ascii: "L")
            } else if command == UInt8(ascii: "m") {
                command = UInt8(ascii: "l")
            }

            switch command {
            case UInt8(ascii: "M"), UInt8(ascii: "m"):
                guard let p = point(relative: command == UInt8(ascii: "m")) else { return path }
                path.move(to: p)
                current = p
                subpathStart = p
            case UInt8(ascii: "L"), UInt8(ascii: "l"):
                guard let p = point(relative: command == UInt8(ascii: "l")) else { return path }
                path.addLine(to: p)
                current = p
            case UInt8(ascii: "H"), UInt8(ascii: "h"):
                guard let x = number() else { return path }
                let p = CGPoint(x: command == UInt8(ascii: "h") ? current.x + x : x, y: current.y)
                path.addLine(to: p)
                current = p
            case UInt8(ascii: "V"), UInt8(ascii: "v"):
                guard let y = number() else { return path }
                let p = CGPoint(x: current.x, y: command == UInt8(ascii: "v") ? current.y + y : y)
                path.addLine(to: p)
                current = p
            case UInt8(ascii: "C"), UInt8(ascii: "c"):
                let relative = command == UInt8(ascii: "c")
                guard let c1 = point(relative: relative),
                      let c2 = point(relative: relative),
                      let p = point(relative: relative) else { return path }
                path.addCurve(to: p, control1: c1, control2: c2)
                current = p
            case UInt8(ascii: "Z"), UInt8(ascii: "z"):
                path.closeSubpath()
                current = subpathStart
            default:
                assertionFailure("AvafliSVGGlyphShape: unsupported SVG path command \(Character(UnicodeScalar(command)))")
                return path
            }
        }
        return path
    }
}

/// Raw `d` attributes from the official Figma brand exports
/// (icon-instagram / icon-facebook / icon-x / icon-snapchat / icon-tiktok,
/// white fill, 48x48 viewBox).
enum AvafliSocialPathData {
    static let x = [
        "M36.6526 3.8078H43.3995L28.6594 20.6548L46 43.5797H32.4225L21.7881 29.6759L9.61989 43.5797H2.86886L18.6349 25.56L2 3.8078H15.9222L25.5348 16.5165L36.6526 3.8078ZM34.2846 39.5414H38.0232L13.8908 7.63406H9.87892L34.2846 39.5414Z"
    ]

    static let facebook = [
        "M24 0C10.7453 0 0 10.7453 0 24C0 35.255 7.74912 44.6995 18.2026 47.2934V31.3344H13.2538V24H18.2026V20.8397C18.2026 12.671 21.8995 8.8848 29.9194 8.8848C31.44 8.8848 34.0637 9.18336 35.137 9.48096V16.129C34.5706 16.0694 33.5866 16.0397 32.3645 16.0397C28.4294 16.0397 26.9088 17.5306 26.9088 21.4061V24H34.7482L33.4013 31.3344H26.9088V47.8243C38.7926 46.3891 48.001 36.2707 48.001 24C48 10.7453 37.2547 0 24 0Z"
    ]

    static let instagram = [
        "M24 4.32187C30.4125 4.32187 31.1719 4.35 33.6938 4.4625C36.0375 4.56562 37.3031 4.95938 38.1469 5.2875C39.2625 5.71875 40.0688 6.24375 40.9031 7.07812C41.7469 7.92188 42.2625 8.71875 42.6938 9.83438C43.0219 10.6781 43.4156 11.9531 43.5188 14.2875C43.6313 16.8187 43.6594 17.5781 43.6594 23.9813C43.6594 30.3938 43.6313 31.1531 43.5188 33.675C43.4156 36.0188 43.0219 37.2844 42.6938 38.1281C42.2625 39.2438 41.7375 40.05 40.9031 40.8844C40.0594 41.7281 39.2625 42.2438 38.1469 42.675C37.3031 43.0031 36.0281 43.3969 33.6938 43.5C31.1625 43.6125 30.4031 43.6406 24 43.6406C17.5875 43.6406 16.8281 43.6125 14.3063 43.5C11.9625 43.3969 10.6969 43.0031 9.85313 42.675C8.7375 42.2438 7.93125 41.7188 7.09688 40.8844C6.25313 40.0406 5.7375 39.2438 5.30625 38.1281C4.97813 37.2844 4.58438 36.0094 4.48125 33.675C4.36875 31.1438 4.34063 30.3844 4.34063 23.9813C4.34063 17.5688 4.36875 16.8094 4.48125 14.2875C4.58438 11.9437 4.97813 10.6781 5.30625 9.83438C5.7375 8.71875 6.2625 7.9125 7.09688 7.07812C7.94063 6.23438 8.7375 5.71875 9.85313 5.2875C10.6969 4.95938 11.9719 4.56562 14.3063 4.4625C16.8281 4.35 17.5875 4.32187 24 4.32187ZM24 0C17.4844 0 16.6688 0.028125 14.1094 0.140625C11.5594 0.253125 9.80625 0.665625 8.2875 1.25625C6.70312 1.875 5.3625 2.69062 4.03125 4.03125C2.69063 5.3625 1.875 6.70313 1.25625 8.27813C0.665625 9.80625 0.253125 11.55 0.140625 14.1C0.028125 16.6687 0 17.4844 0 24C0 30.5156 0.028125 31.3312 0.140625 33.8906C0.253125 36.4406 0.665625 38.1938 1.25625 39.7125C1.875 41.2969 2.69063 42.6375 4.03125 43.9688C5.3625 45.3 6.70313 46.125 8.27813 46.7344C9.80625 47.325 11.55 47.7375 14.1 47.85C16.6594 47.9625 17.475 47.9906 23.9906 47.9906C30.5063 47.9906 31.3219 47.9625 33.8813 47.85C36.4313 47.7375 38.1844 47.325 39.7031 46.7344C41.2781 46.125 42.6188 45.3 43.95 43.9688C45.2812 42.6375 46.1063 41.2969 46.7156 39.7219C47.3063 38.1938 47.7188 36.45 47.8313 33.9C47.9438 31.3406 47.9719 30.525 47.9719 24.0094C47.9719 17.4938 47.9438 16.6781 47.8313 14.1188C47.7188 11.5688 47.3063 9.81563 46.7156 8.29688C46.125 6.70312 45.3094 5.3625 43.9688 4.03125C42.6375 2.7 41.2969 1.875 39.7219 1.26562C38.1938 0.675 36.45 0.2625 33.9 0.15C31.3313 0.028125 30.5156 0 24 0Z",
        "M24 11.6719C17.1938 11.6719 11.6719 17.1938 11.6719 24C11.6719 30.8062 17.1938 36.3281 24 36.3281C30.8062 36.3281 36.3281 30.8062 36.3281 24C36.3281 17.1938 30.8062 11.6719 24 11.6719ZM24 31.9969C19.5844 31.9969 16.0031 28.4156 16.0031 24C16.0031 19.5844 19.5844 16.0031 24 16.0031C28.4156 16.0031 31.9969 19.5844 31.9969 24C31.9969 28.4156 28.4156 31.9969 24 31.9969Z",
        "M39.6937 11.1843C39.6937 12.778 38.4 14.0624 36.8156 14.0624C35.2219 14.0624 33.9375 12.7687 33.9375 11.1843C33.9375 9.59053 35.2313 8.30615 36.8156 8.30615C38.4 8.30615 39.6937 9.5999 39.6937 11.1843Z"
    ]

    static let snapchat = [
        "M47.8265 34.9152C47.4955 34.0082 46.8582 33.5179 46.135 33.1257C46.0001 33.0522 45.8776 32.9786 45.7673 32.9296C45.5466 32.8193 45.326 32.709 45.1054 32.5986C42.8501 31.3974 41.085 29.9021 39.8716 28.1125C39.5284 27.61 39.2219 27.0707 38.9768 26.5191C38.8665 26.2249 38.8787 26.0533 38.9523 25.894C39.0258 25.7714 39.1239 25.6733 39.2464 25.5875C39.6387 25.3301 40.0309 25.0727 40.3006 24.9011C40.7786 24.5824 41.1708 24.3373 41.416 24.1657C42.3353 23.5161 42.9849 22.8297 43.3894 22.0575C43.9655 20.9788 44.039 19.7163 43.5977 18.5764C42.9849 16.9585 41.465 15.9656 39.6142 15.9656C39.2219 15.9656 38.842 16.0024 38.4497 16.0882C38.3517 16.1127 38.2414 16.1372 38.1433 16.1618C38.1556 15.0586 38.131 13.8942 38.033 12.742C37.6898 8.7094 36.2679 6.60117 34.7971 4.92193C33.8533 3.86782 32.7501 2.97304 31.5122 2.27438C29.2814 0.999637 26.7441 0.350006 23.9863 0.350006C21.2284 0.350006 18.7034 0.999637 16.4726 2.27438C15.2346 2.97304 14.1315 3.86782 13.1877 4.92193C11.7168 6.60117 10.3073 8.72166 9.95179 12.742C9.85373 13.8942 9.82922 15.0586 9.84148 16.1618C9.74342 16.1372 9.64536 16.1127 9.53505 16.0882C9.15507 16.0024 8.76285 15.9656 8.38287 15.9656C6.53204 15.9656 5.01215 16.9707 4.39929 18.5764C3.95803 19.7163 4.03157 20.9788 4.60766 22.0575C5.01215 22.8297 5.66178 23.5161 6.58107 24.1657C6.82621 24.3373 7.20618 24.5824 7.69647 24.9011C7.95387 25.0727 8.33384 25.3179 8.71382 25.563C8.84864 25.6488 8.95896 25.7591 9.04476 25.894C9.1183 26.0533 9.13056 26.2249 9.00799 26.5436C8.76284 27.0829 8.46867 27.61 8.12547 28.1003C6.93653 29.8408 5.22052 31.3239 3.03874 32.5128C1.88657 33.1257 0.685365 33.5302 0.170564 34.9152C-0.209408 35.9571 0.035735 37.1338 1.00405 38.1389C1.35951 38.5066 1.77625 38.8253 2.22977 39.0704C3.17357 39.5852 4.17866 39.9897 5.23278 40.2716C5.45341 40.3329 5.64952 40.4187 5.83338 40.5413C6.18884 40.8477 6.13981 41.3135 6.60558 41.9999C6.83847 42.3554 7.1449 42.6618 7.4881 42.9069C8.48093 43.5933 9.59633 43.6301 10.773 43.6791C11.8394 43.7159 13.0406 43.7649 14.4257 44.2184C15.0017 44.4023 15.5901 44.77 16.2765 45.199C17.9312 46.2164 20.1865 47.6014 23.974 47.6014C27.7615 47.6014 30.029 46.2041 31.696 45.1868C32.3824 44.77 32.9708 44.4023 33.5223 44.2184C34.8951 43.7649 36.1086 43.7159 37.175 43.6791C38.3517 43.6301 39.4671 43.5933 40.4599 42.9069C40.8767 42.6128 41.2198 42.245 41.465 41.8038C41.8082 41.2277 41.7959 40.8232 42.1146 40.5413C42.2862 40.4187 42.4823 40.3329 42.6785 40.2839C43.7326 40.002 44.7622 39.5975 45.7182 39.0704C46.1963 38.813 46.6375 38.4698 47.0052 38.0653L47.0175 38.0531C47.9736 37.0725 48.2064 35.9203 47.8265 34.9152ZM44.468 36.7171C42.4211 37.8447 41.0483 37.7221 39.9941 38.4085C39.0871 38.9846 39.6264 40.2349 38.9768 40.6884C38.1678 41.2399 35.7899 40.6516 32.7256 41.6689C30.1884 42.5024 28.5827 44.9171 24.023 44.9171C19.4634 44.9171 17.8944 42.5147 15.3204 41.6689C12.2561 40.6516 9.87825 41.2522 9.06927 40.6884C8.41964 40.2349 8.9467 38.9846 8.05193 38.4085C6.98556 37.7221 5.62501 37.8447 3.57806 36.7171C2.26654 35.9939 3.01423 35.5526 3.44323 35.3442C10.8711 31.7529 12.06 26.2004 12.1091 25.7836C12.1703 25.2811 12.2439 24.8889 11.6923 24.3863C11.1653 23.896 8.81187 22.4374 8.14999 21.9839C7.07135 21.224 6.59333 20.4763 6.94878 19.5447C7.19393 18.9074 7.79453 18.6622 8.41964 18.6622C8.61576 18.6622 8.81187 18.6867 9.00799 18.7235C10.1969 18.9809 11.3491 19.5693 12.011 19.7409C12.0968 19.7654 12.1703 19.7776 12.2561 19.7776C12.6116 19.7776 12.7342 19.5938 12.7097 19.1893C12.6361 17.89 12.4523 15.365 12.6606 12.9994C12.9425 9.75126 13.9844 8.13331 15.2346 6.71148C15.8352 6.02508 18.6421 3.05884 24.023 3.05884C29.4039 3.05884 32.2108 6.01282 32.8114 6.69922C34.0617 8.12106 35.1035 9.739 35.3854 12.9872C35.5938 15.3528 35.4099 17.8778 35.3241 19.177C35.2996 19.606 35.4222 19.7654 35.7777 19.7654C35.8635 19.7654 35.937 19.7531 36.0228 19.7286C36.6847 19.5693 37.8369 18.9687 39.0258 18.7113C39.2219 18.6622 39.418 18.65 39.6142 18.65C40.2393 18.65 40.8399 18.8951 41.085 19.5325C41.4405 20.464 40.9625 21.2117 39.8838 21.9717C39.2342 22.4252 36.8808 23.8838 36.3415 24.3741C35.7899 24.8766 35.8635 25.2688 35.9248 25.7714C35.9738 26.1881 37.1627 31.7406 44.5906 35.332C45.0318 35.5404 45.7673 35.9939 44.468 36.7171Z"
    ]

    static let tiktok = [
        "M34.1451 0H26.0556V32.6956C26.0556 36.5913 22.9444 39.7913 19.0725 39.7913C15.2007 39.7913 12.0894 36.5913 12.0894 32.6956C12.0894 28.8696 15.1315 25.7391 18.8651 25.6V17.3913C10.6374 17.5304 4 24.2783 4 32.6956C4 41.1827 10.7757 48 19.1417 48C27.5075 48 34.2833 41.1131 34.2833 32.6956V15.9304C37.3255 18.1565 41.059 19.4783 45 19.5479V11.3391C38.9157 11.1304 34.1451 6.12173 34.1451 0Z"
    ]
}
