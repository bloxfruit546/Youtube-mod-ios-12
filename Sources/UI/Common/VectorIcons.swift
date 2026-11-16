import UIKit

enum VectorIcons {
    private static func draw(size: CGSize, _ block: (CGContext, CGRect) -> Void) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            block(ctx.cgContext, CGRect(origin: .zero, size: size))
        }.withRenderingMode(.alwaysTemplate)
    }

    static func home(size: CGFloat = 22) -> UIImage {
        return draw(size: CGSize(width: size, height: size)) { cg, rect in
            let w = rect.width
            let h = rect.height
            let path = UIBezierPath()
            path.move(to: CGPoint(x: w * 0.5, y: h * 0.12))
            path.addLine(to: CGPoint(x: w * 0.9, y: h * 0.45))
            path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.45))
            path.addLine(to: CGPoint(x: w * 0.78, y: h * 0.88))
            path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.88))
            path.addLine(to: CGPoint(x: w * 0.58, y: h * 0.62))
            path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.62))
            path.addLine(to: CGPoint(x: w * 0.42, y: h * 0.88))
            path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.88))
            path.addLine(to: CGPoint(x: w * 0.22, y: h * 0.45))
            path.addLine(to: CGPoint(x: w * 0.1, y: h * 0.45))
            path.close()
            cg.setFillColor(UIColor.black.cgColor)
            path.fill()
        }
    }

    static func subscriptions(size: CGFloat = 22) -> UIImage {
        return draw(size: CGSize(width: size, height: size)) { cg, rect in
            let w = rect.width
            let h = rect.height
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(1.6)
            // Top bars
            cg.move(to: CGPoint(x: w * 0.24, y: h * 0.18))
            cg.addLine(to: CGPoint(x: w * 0.76, y: h * 0.18))
            cg.move(to: CGPoint(x: w * 0.16, y: h * 0.30))
            cg.addLine(to: CGPoint(x: w * 0.84, y: h * 0.30))
            cg.strokePath()
            // Main box
            let box = CGRect(x: w * 0.1, y: h * 0.40, width: w * 0.8, height: h * 0.48)
            cg.stroke(box)
            // Play triangle inside
            let tri = UIBezierPath()
            tri.move(to: CGPoint(x: w * 0.43, y: h * 0.52))
            tri.addLine(to: CGPoint(x: w * 0.64, y: h * 0.64))
            tri.addLine(to: CGPoint(x: w * 0.43, y: h * 0.76))
            tri.close()
            cg.setFillColor(UIColor.black.cgColor)
            tri.fill()
        }
    }

    static func library(size: CGFloat = 22) -> UIImage {
        return draw(size: CGSize(width: size, height: size)) { cg, rect in
            let w = rect.width
            let h = rect.height
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(1.6)
            let front = CGRect(x: w * 0.24, y: h * 0.16, width: w * 0.64, height: h * 0.58)
            cg.stroke(front)
            cg.move(to: CGPoint(x: w * 0.12, y: h * 0.30))
            cg.addLine(to: CGPoint(x: w * 0.12, y: h * 0.84))
            cg.addLine(to: CGPoint(x: w * 0.74, y: h * 0.84))
            cg.strokePath()
            let tri = UIBezierPath()
            tri.move(to: CGPoint(x: w * 0.48, y: h * 0.33))
            tri.addLine(to: CGPoint(x: w * 0.68, y: h * 0.45))
            tri.addLine(to: CGPoint(x: w * 0.48, y: h * 0.57))
            tri.close()
            cg.setFillColor(UIColor.black.cgColor)
            tri.fill()
        }
    }

    static func search(size: CGFloat = 20) -> UIImage {
        return draw(size: CGSize(width: size, height: size)) { cg, rect in
            let w = rect.width
            let h = rect.height
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(2.0)
            let circle = CGRect(x: w * 0.14, y: h * 0.14, width: w * 0.52, height: h * 0.52)
            cg.strokeEllipse(in: circle)
            cg.move(to: CGPoint(x: w * 0.58, y: h * 0.58))
            cg.addLine(to: CGPoint(x: w * 0.86, y: h * 0.86))
            cg.strokePath()
        }
    }

    static func play(size: CGFloat = 24) -> UIImage {
        return draw(size: CGSize(width: size, height: size)) { cg, rect in
            let w = rect.width
            let h = rect.height
            let path = UIBezierPath()
            path.move(to: CGPoint(x: w * 0.25, y: h * 0.16))
            path.addLine(to: CGPoint(x: w * 0.82, y: h * 0.5))
            path.addLine(to: CGPoint(x: w * 0.25, y: h * 0.84))
            path.close()
            cg.setFillColor(UIColor.black.cgColor)
            path.fill()
        }
    }

    static func pause(size: CGFloat = 24) -> UIImage {
        return draw(size: CGSize(width: size, height: size)) { cg, rect in
            let w = rect.width
            let h = rect.height
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(x: w * 0.24, y: h * 0.18, width: w * 0.18, height: h * 0.64))
            cg.fill(CGRect(x: w * 0.58, y: h * 0.18, width: w * 0.18, height: h * 0.64))
        }
    }

    static func close(size: CGFloat = 18) -> UIImage {
        return draw(size: CGSize(width: size, height: size)) { cg, rect in
            let w = rect.width
            let h = rect.height
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(2.0)
            cg.move(to: CGPoint(x: w * 0.22, y: h * 0.22))
            cg.addLine(to: CGPoint(x: w * 0.78, y: h * 0.78))
            cg.move(to: CGPoint(x: w * 0.78, y: h * 0.22))
            cg.addLine(to: CGPoint(x: w * 0.22, y: h * 0.78))
            cg.strokePath()
        }
    }

    static func chevronDown(size: CGFloat = 20) -> UIImage {
        return draw(size: CGSize(width: size, height: size)) { cg, rect in
            let w = rect.width
            let h = rect.height
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(2.2)
            cg.move(to: CGPoint(x: w * 0.18, y: h * 0.34))
            cg.addLine(to: CGPoint(x: w * 0.5, y: h * 0.68))
            cg.addLine(to: CGPoint(x: w * 0.82, y: h * 0.34))
            cg.strokePath()
        }
    }

    static func fullscreen(size: CGFloat = 20) -> UIImage {
        return draw(size: CGSize(width: size, height: size)) { cg, rect in
            let w = rect.width
            let h = rect.height
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(1.8)
            // Top-left
            cg.move(to: CGPoint(x: w * 0.15, y: h * 0.35))
            cg.addLine(to: CGPoint(x: w * 0.15, y: h * 0.15))
            cg.addLine(to: CGPoint(x: w * 0.35, y: h * 0.15))
            // Top-right
            cg.move(to: CGPoint(x: w * 0.65, y: h * 0.15))
            cg.addLine(to: CGPoint(x: w * 0.85, y: h * 0.15))
            cg.addLine(to: CGPoint(x: w * 0.85, y: h * 0.35))
            // Bottom-left
            cg.move(to: CGPoint(x: w * 0.15, y: h * 0.65))
            cg.addLine(to: CGPoint(x: w * 0.15, y: h * 0.85))
            cg.addLine(to: CGPoint(x: w * 0.35, y: h * 0.85))
            // Bottom-right
            cg.move(to: CGPoint(x: w * 0.65, y: h * 0.85))
            cg.addLine(to: CGPoint(x: w * 0.85, y: h * 0.85))
            cg.addLine(to: CGPoint(x: w * 0.85, y: h * 0.65))
            cg.strokePath()
        }
    }

    static func headphones(size: CGFloat = 20) -> UIImage {
        return draw(size: CGSize(width: size, height: size)) { cg, rect in
            let w = rect.width
            let h = rect.height
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(1.8)
            cg.addArc(center: CGPoint(x: w * 0.5, y: h * 0.52), radius: w * 0.34, startAngle: .pi, endAngle: 0, clockwise: false)
            cg.strokePath()
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(x: w * 0.12, y: h * 0.50, width: w * 0.14, height: h * 0.30))
            cg.fill(CGRect(x: w * 0.74, y: h * 0.50, width: w * 0.14, height: h * 0.30))
        }
    }

    static func settings(size: CGFloat = 20) -> UIImage {
        return draw(size: CGSize(width: size, height: size)) { cg, rect in
            let w = rect.width
            let h = rect.height
            let center = CGPoint(x: w * 0.5, y: h * 0.5)
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(2.0)
            cg.strokeEllipse(in: CGRect(x: w * 0.32, y: h * 0.32, width: w * 0.36, height: h * 0.36))
            for i in 0..<8 {
                let angle = CGFloat(i) * (.pi / 4.0)
                let p1 = CGPoint(x: center.x + cos(angle) * w * 0.25, y: center.y + sin(angle) * h * 0.25)
                let p2 = CGPoint(x: center.x + cos(angle) * w * 0.40, y: center.y + sin(angle) * h * 0.40)
                cg.move(to: p1)
                cg.addLine(to: p2)
            }
            cg.strokePath()
        }
    }

    static func themeToggle(size: CGFloat = 20) -> UIImage {
        return draw(size: CGSize(width: size, height: size)) { cg, rect in
            let w = rect.width
            let h = rect.height
            cg.setStrokeColor(UIColor.black.cgColor)
            cg.setLineWidth(1.8)
            cg.strokeEllipse(in: CGRect(x: w * 0.18, y: h * 0.18, width: w * 0.64, height: h * 0.64))
            cg.setFillColor(UIColor.black.cgColor)
            cg.addArc(center: CGPoint(x: w * 0.5, y: h * 0.5), radius: w * 0.32, startAngle: -.pi / 2, endAngle: .pi / 2, clockwise: false)
            cg.fillPath()
        }
    }
}
