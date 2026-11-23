import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum MealColors {
    static let paper = UIColor(red: 250/255, green: 247/255, blue: 241/255, alpha: 1)
    static let ink = UIColor(red: 31/255, green: 35/255, blue: 38/255, alpha: 1)
    static let accent = UIColor(red: 184/255, green: 40/255, blue: 58/255, alpha: 1)
    static let tint = UIColor(red: 248/255, green: 228/255, blue: 233/255, alpha: 1)
    static let line = UIColor(red: 229/255, green: 214/255, blue: 217/255, alpha: 1)
    static let surface = UIColor(red: 255/255, green: 253/255, blue: 249/255, alpha: 1)
    static let muted = UIColor(red: 102/255, green: 86/255, blue: 90/255, alpha: 1)
}

struct ShareContent: Identifiable {
    let id = UUID()
    var names: [String] = []
    var menu: [MenuItem] = []
    var milestone: Int?
    var weekly = false

    var title: String {
        if let milestone { return L.f("milestone_title", milestone) }
        return weekly ? L.t("week_card") : L.t("card_title")
    }
    var caption: String {
        if milestone != nil { return title + " " + L.t("hashtags") }
        return L.t(weekly ? "week_caption" : "caption") + " " + L.t("hashtags")
    }
}

enum ShareCard {
    static let size = CGSize(width: 1080, height: 1350)
    static let placeholder = URL(string: "https://hgsldswk-alt.github.io/mealrotation-support/")!

    static func png(_ content: ShareContent, showNames: Bool, link: URL?) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).pngData { renderer in
            let canvas = renderer.cgContext
            canvas.setFillColor(MealColors.paper.cgColor)
            canvas.fill(CGRect(origin: .zero, size: size))
            MealColors.tint.setFill()
            UIBezierPath(roundedRect: CGRect(x: 66, y: 68, width: 948, height: 965), cornerRadius: 52).fill()
            draw(L.t("app_name"), at: CGRect(x: 126, y: 130, width: 828, height: 54), size: 38, color: MealColors.accent)
            draw(content.title, at: CGRect(x: 126, y: 205, width: 828, height: 208), size: 84, color: MealColors.ink)
            let names = showNames ? content.names : []
            for (index, name) in names.prefix(7).enumerated() {
                draw(name, at: CGRect(x: 130, y: CGFloat(445 + index * 75), width: 810, height: 72), size: 39, color: MealColors.ink)
            }
            if names.isEmpty {
                draw(L.t(content.milestone == nil ? "home_tagline" : "milestone_note"),
                     at: CGRect(x: 126, y: 475, width: 808, height: 150), size: 51, color: MealColors.ink)
            }
            draw(L.t("hashtags"), at: CGRect(x: 74, y: 1091, width: 705, height: 94), size: 38, color: MealColors.accent)
            draw(L.t(link == nil ? "preview_qr" : "download_qr"),
                 at: CGRect(x: 74, y: 1210, width: 705, height: 70), size: 32, color: MealColors.muted)
            if let qr = qrImage(link ?? placeholder) {
                let box = CGRect(x: 788, y: 1062, width: 222, height: 222)
                canvas.setFillColor(UIColor.white.cgColor)
                canvas.fill(box)
                canvas.interpolationQuality = .none
                let side = CGFloat(qr.width) * floor(190 / CGFloat(qr.width))
                UIImage(cgImage: qr).draw(in: CGRect(x: box.midX - side / 2, y: box.midY - side / 2,
                                                    width: side, height: side))
            }
        }
    }

    private static func qrImage(_ link: URL) -> CGImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(link.absoluteString.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage else { return nil }
        return CIContext().createCGImage(output, from: output.extent)
    }

    private static func draw(_ text: String, at rect: CGRect, size: CGFloat, color: UIColor) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let options: NSStringDrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading, .truncatesLastVisibleLine]
        let string = text as NSString
        var font = size
        var attributes: [NSAttributedString.Key: Any] = [:]
        repeat {
            attributes = [.font: UIFont.systemFont(ofSize: font, weight: .semibold),
                          .foregroundColor: color, .paragraphStyle: paragraph]
            if string.boundingRect(with: CGSize(width: rect.width, height: .greatestFiniteMagnitude),
                                   options: options, attributes: attributes, context: nil).height <= rect.height { break }
            font -= 2
        } while font >= 22
        string.draw(with: rect, options: options, attributes: attributes, context: nil)
    }
}
