import Foundation

/// 品質判定の閾値（05_AI_PIPELINE.md §2.2 / SCREEN_CAMERA.md §15-2: 閾値はここに集約）。
/// 端末別チューニング値のテーブルを将来ここへ追加する。
public enum CameraKitConstants {
    /// ピント: ラプラシアン分散の下限
    public static let laplacianVarianceFloor: Double = 60

    /// 明るさ: 輝度中央値の許容レンジ（05 §2.2: 40〜215）
    public static let brightnessMedianRange: ClosedRange<Double> = 40...215

    /// 傾き: 水平許容（±7°）
    public static let tiltToleranceDegrees: Double = 7

    /// 見切れ: 車両BBoxが画像端に接していると見なすマージン（正規化座標）
    public static let framingEdgeMargin: Double = 0.005

    /// 車両が小さすぎる（近づき不足）と見なすBBox面積比の下限
    public static let minVehicleAreaRatio: Double = 0.18

    /// 品質判定SLA（NFR-01: 撮影後1.5秒以内）
    public static let qualityCheckSLA: TimeInterval = 1.5

    /// アップロード画像の規格（FR-306: 長辺2048px, JPEG 80%）
    public static let uploadLongEdge: CGFloat = 2048
    public static let uploadJPEGQuality: CGFloat = 0.8

    /// マスキングのぼかし半径（07 §2.2: ガウシアン r=20相当）
    public static let maskBlurRadius: Double = 20
}
