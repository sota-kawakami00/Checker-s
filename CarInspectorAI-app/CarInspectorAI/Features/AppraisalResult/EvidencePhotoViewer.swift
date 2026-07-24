import SwiftUI
import AppraisalKit
import DesignSystem

/// 注釈付き画像ビューア（SCREEN_APPRAISAL_RESULT §15-4: ズーム + 矩形描画）。
/// `evidences[].region`（正規化座標）を画像上に矩形+ラベルで描画する（§9: 描画のみ）。
struct EvidencePhotoViewer: View {
    let photoPath: String?
    let evidences: [RepairEvidence]

    @Environment(\.dismiss) private var dismiss
    @State private var scale: CGFloat = 1
    @GestureState private var magnification: CGFloat = 1

    var body: some View {
        NavigationStack {
            Group {
                if let photoPath, let uiImage = UIImage(contentsOfFile: photoPath) {
                    GeometryReader { proxy in
                        let fitted = fittedRect(imageSize: uiImage.size, in: proxy.size)
                        ZStack(alignment: .topLeading) {
                            Image(uiImage: uiImage)
                                .resizable()
                                .scaledToFit()
                            ForEach(evidences) { evidence in
                                annotation(evidence, in: fitted)
                            }
                        }
                        .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                        .scaleEffect(scale * magnification)
                        .gesture(
                            MagnifyGesture()
                                .updating($magnification) { value, state, _ in
                                    state = value.magnification
                                }
                                .onEnded { value in
                                    scale = min(4, max(1, scale * value.magnification))
                                }
                        )
                        .onTapGesture(count: 2) {
                            withAnimation { scale = scale > 1 ? 1 : 2 }
                        }
                    }
                } else {
                    EmptyStateView(
                        systemImage: "photo.badge.exclamationmark",
                        title: String(localized: "evidence.missing.title"),
                        message: String(localized: "evidence.missing.message")
                    )
                }
            }
            .background(.black)
            .navigationTitle(Text("evidence.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("common.close") { dismiss() }
                }
            }
        }
    }

    /// scaledToFit 後の画像実表示領域
    private func fittedRect(imageSize: CGSize, in container: CGSize) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        let size = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        return CGRect(
            x: (container.width - size.width) / 2,
            y: (container.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    private func annotation(_ evidence: RepairEvidence, in fitted: CGRect) -> some View {
        let rect = CGRect(
            x: fitted.minX + evidence.region.x * fitted.width,
            y: fitted.minY + evidence.region.y * fitted.height,
            width: evidence.region.w * fitted.width,
            height: evidence.region.h * fitted.height
        )
        return ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(CIToken.Colors.danger, lineWidth: 2)
                .frame(width: rect.width, height: rect.height)
            Text(LocalizedStringKey("repair.type." + evidence.type.rawValue))
                .font(CIToken.Fonts.caption.bold())
                .padding(CIToken.Space.xs)
                .background(CIToken.Colors.danger)
                .foregroundStyle(.white)
                .offset(y: -24)
        }
        .offset(x: rect.minX, y: rect.minY)
        .accessibilityLabel(Text(evidence.note))
    }
}
