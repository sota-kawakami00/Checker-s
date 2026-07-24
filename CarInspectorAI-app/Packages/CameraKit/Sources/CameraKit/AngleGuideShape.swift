import SwiftUI
import Core

/// アングル別ガイド枠シルエット（SCREEN_CAMERA §2 / §15-3: 画面固有のため CameraKit 側に置く）。
/// 透過白60%で描画し、合格範囲で accent へトランジションさせるのは View 側の責務。
public struct AngleGuideShape: Shape {
    public let angle: PhotoAngle

    public init(angle: PhotoAngle) {
        self.angle = angle
    }

    public func path(in rect: CGRect) -> Path {
        switch angle {
        case .front, .rear:
            return frontSilhouette(in: rect)
        case .left, .right:
            return sideSilhouette(in: rect, facingLeft: angle == .right)
        case .frontLeft, .frontRight, .rearLeft, .rearRight:
            return quarterSilhouette(in: rect, facingLeft: angle == .frontRight || angle == .rearRight)
        case .interiorFront, .interiorRear:
            return interiorGuide(in: rect)
        case .meter:
            return meterGuide(in: rect)
        case .engineRoom:
            return engineGuide(in: rect)
        case .damage:
            return Path(roundedRect: rect.insetBy(dx: rect.width * 0.08, dy: rect.height * 0.08), cornerRadius: 16)
        }
    }

    /// 正面/背面: 台形キャビン + ワイドボディ
    private func frontSilhouette(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let bodyTop = rect.minY + height * 0.35
        let cabinTop = rect.minY + height * 0.12
        // キャビン
        path.move(to: CGPoint(x: rect.minX + width * 0.28, y: bodyTop))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.34, y: cabinTop))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.66, y: cabinTop))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.72, y: bodyTop))
        // ボディ
        path.addLine(to: CGPoint(x: rect.minX + width * 0.9, y: bodyTop))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.92, y: rect.maxY - height * 0.18))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.08, y: rect.maxY - height * 0.18))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.1, y: bodyTop))
        path.closeSubpath()
        // タイヤ
        path.addEllipse(in: CGRect(x: rect.minX + width * 0.12, y: rect.maxY - height * 0.24, width: width * 0.14, height: height * 0.14))
        path.addEllipse(in: CGRect(x: rect.minX + width * 0.74, y: rect.maxY - height * 0.24, width: width * 0.14, height: height * 0.14))
        return path
    }

    /// 側面: ルーフライン + 2輪
    private func sideSilhouette(in rect: CGRect, facingLeft: Bool) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let beltLine = rect.minY + height * 0.45
        path.move(to: CGPoint(x: rect.minX + width * 0.05, y: beltLine))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + width * 0.3, y: rect.minY + height * 0.16),
            control: CGPoint(x: rect.minX + width * 0.12, y: rect.minY + height * 0.2)
        )
        path.addLine(to: CGPoint(x: rect.minX + width * 0.62, y: rect.minY + height * 0.14))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + width * 0.95, y: beltLine),
            control: CGPoint(x: rect.minX + width * 0.88, y: rect.minY + height * 0.2)
        )
        path.addLine(to: CGPoint(x: rect.minX + width * 0.95, y: rect.maxY - height * 0.2))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.05, y: rect.maxY - height * 0.2))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: rect.minX + width * 0.16, y: rect.maxY - height * 0.3, width: width * 0.16, height: height * 0.2))
        path.addEllipse(in: CGRect(x: rect.minX + width * 0.68, y: rect.maxY - height * 0.3, width: width * 0.16, height: height * 0.2))
        if facingLeft {
            return path.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -rect.width - rect.minX * 2, y: 0))
        }
        return path
    }

    /// 45°: 側面と正面の中間（奥行き付き台形）
    private func quarterSilhouette(in rect: CGRect, facingLeft: Bool) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        let beltLine = rect.minY + height * 0.42
        path.move(to: CGPoint(x: rect.minX + width * 0.06, y: beltLine))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + width * 0.34, y: rect.minY + height * 0.15),
            control: CGPoint(x: rect.minX + width * 0.14, y: rect.minY + height * 0.18)
        )
        path.addLine(to: CGPoint(x: rect.minX + width * 0.68, y: rect.minY + height * 0.13))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + width * 0.86, y: rect.minY + height * 0.3),
            control: CGPoint(x: rect.minX + width * 0.8, y: rect.minY + height * 0.16)
        )
        path.addLine(to: CGPoint(x: rect.minX + width * 0.94, y: rect.minY + height * 0.36))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.94, y: rect.maxY - height * 0.2))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.06, y: rect.maxY - height * 0.2))
        path.closeSubpath()
        path.addEllipse(in: CGRect(x: rect.minX + width * 0.14, y: rect.maxY - height * 0.31, width: width * 0.17, height: height * 0.21))
        path.addEllipse(in: CGRect(x: rect.minX + width * 0.66, y: rect.maxY - height * 0.29, width: width * 0.15, height: height * 0.19))
        if facingLeft {
            return path.applying(CGAffineTransform(scaleX: -1, y: 1).translatedBy(x: -rect.width - rect.minX * 2, y: 0))
        }
        return path
    }

    /// 内装: ダッシュボード/シートを囲む枠
    private func interiorGuide(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.1), cornerRadius: 20)
        let seatWidth = rect.width * 0.3
        let seatHeight = rect.height * 0.42
        path.addRoundedRect(in: CGRect(x: rect.minX + rect.width * 0.14, y: rect.midY - seatHeight * 0.3, width: seatWidth, height: seatHeight), cornerSize: CGSize(width: 14, height: 14))
        path.addRoundedRect(in: CGRect(x: rect.maxX - rect.width * 0.14 - seatWidth, y: rect.midY - seatHeight * 0.3, width: seatWidth, height: seatHeight), cornerSize: CGSize(width: 14, height: 14))
        return path
    }

    /// メーター: 中央の横長枠 + 円形メーター
    private func meterGuide(in rect: CGRect) -> Path {
        var path = Path(roundedRect: rect.insetBy(dx: rect.width * 0.15, dy: rect.height * 0.28), cornerRadius: 18)
        let diameter = min(rect.width, rect.height) * 0.28
        path.addEllipse(in: CGRect(x: rect.midX - diameter - 8, y: rect.midY - diameter / 2, width: diameter, height: diameter))
        path.addEllipse(in: CGRect(x: rect.midX + 8, y: rect.midY - diameter / 2, width: diameter, height: diameter))
        return path
    }

    /// エンジンルーム: 開いたボンネットの台形
    private func engineGuide(in rect: CGRect) -> Path {
        var path = Path()
        let width = rect.width
        let height = rect.height
        path.move(to: CGPoint(x: rect.minX + width * 0.16, y: rect.minY + height * 0.16))
        path.addLine(to: CGPoint(x: rect.maxX - width * 0.16, y: rect.minY + height * 0.16))
        path.addLine(to: CGPoint(x: rect.maxX - width * 0.06, y: rect.maxY - height * 0.16))
        path.addLine(to: CGPoint(x: rect.minX + width * 0.06, y: rect.maxY - height * 0.16))
        path.closeSubpath()
        return path
    }
}
