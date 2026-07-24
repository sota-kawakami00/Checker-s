import SwiftUI
import Core
import CameraKit
import DesignSystem

/// 撮影画面（SCREEN_CAMERA.md §2）
struct CameraView: View {
    let appraisalId: String
    @Binding var path: [Route]

    @Environment(\.appContainer) private var container
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: CameraViewModel?
    @State private var shutterFlash = false

    var body: some View {
        Group {
            if let viewModel {
                content(viewModel)
            } else {
                Color.black.ignoresSafeArea()
            }
        }
        .navigationBarBackButtonHidden(true)
        .toolbar(.hidden, for: .tabBar)
        .task {
            if viewModel == nil {
                viewModel = CameraViewModel(
                    appraisalId: appraisalId,
                    photoService: container.photoService,
                    appraisalService: container.appraisalService,
                    session: container.cameraSession,
                    tiltProvider: container.tiltProvider
                )
                await viewModel?.onAppear()
            }
        }
        .onDisappear {
            viewModel?.onDisappear()
        }
    }

    @ViewBuilder
    private func content(_ viewModel: CameraViewModel) -> some View {
        @Bindable var viewModel = viewModel
        ZStack {
            // ファインダー（実機: AVCaptureVideoPreviewLayer / モック: 合成画像）
            viewfinder
                .ignoresSafeArea()

            if viewModel.phase == .permissionDenied {
                permissionDeniedView
            } else {
                VStack(spacing: 0) {
                    topBar(viewModel)
                    Spacer()

                    // ガイド枠（アングル別シルエット、透過白60%）
                    if viewModel.phase == .ready || viewModel.phase == .capturing || viewModel.phase == .checkingQuality {
                        AngleGuideShape(angle: viewModel.currentAngle)
                            .stroke(.white.opacity(0.6), lineWidth: 3)
                            .aspectRatio(4 / 3, contentMode: .fit)
                            .padding(.horizontal, CIToken.Space.l)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }

                    // 水平インジケータ（±7°超で表示）
                    if viewModel.isLevelWarning {
                        Label("camera.level.warning", systemImage: "gyroscope")
                            .font(CIToken.Fonts.caption.bold())
                            .foregroundStyle(CIToken.Colors.warning)
                            .padding(CIToken.Space.s)
                            .background(CIToken.Materials.glass, in: Capsule())
                            .transition(.opacity)
                    }

                    Spacer()

                    // 品質トースト
                    if viewModel.qualityToast != nil {
                        toast(viewModel)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if viewModel.phase == .damageCapture || viewModel.phase == .readyToSubmit {
                        damageSection(viewModel)
                    }

                    bottomBar(viewModel)
                }
                .animation(.spring(response: 0.35, dampingFraction: 0.8), value: viewModel.qualityToast != nil)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isLevelWarning)
            }

            // シャッターフラッシュ（白 0.1s）
            if shutterFlash {
                Color.white.ignoresSafeArea()
            }
        }
        .task {
            // 水平計の更新ループ
            while !Task.isCancelled {
                viewModel.refreshLevel()
                try? await Task.sleep(for: .milliseconds(200))
            }
        }
        .sheet(isPresented: $viewModel.isDamageTagSheetPresented) {
            DamageTagSheet(
                onSave: { tag, memo in
                    Task { await viewModel.setDamageTag(tag, memo: memo) }
                },
                onCancel: { viewModel.cancelDamageTag() }
            )
            .presentationDetents([.medium, .large])
        }
        .alert(item: alertBinding(viewModel)) { wrapper in
            Alert(
                title: Text("camera.error.title"),
                message: Text(wrapper.message),
                dismissButton: .default(Text("common.ok"))
            )
        }
    }

    private var viewfinder: some View {
        Group {
            #if os(iOS)
            if let avSession = container.cameraSession as? AVCameraSession {
                CameraPreviewLayerView(session: avSession)
            } else {
                MockViewfinderView()
            }
            #else
            MockViewfinderView()
            #endif
        }
    }

    // 上部バー(glass): 進捗・アングル名（§2）
    private func topBar(_ viewModel: CameraViewModel) -> some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
            }
            .accessibilityLabel(Text("common.close"))
            Spacer()
            VStack(spacing: 2) {
                Text(viewModel.guidedProgress)
                    .accessibilityIdentifier("camera.progress")
                    .font(CIToken.Fonts.mono.bold())
                Text(LocalizedStringKey(viewModel.currentAngle.localizationKey))
                    .font(CIToken.Fonts.caption)
            }
            .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, CIToken.Space.m)
        .padding(.vertical, CIToken.Space.s)
        .background(CIToken.Materials.glass)
    }

    private func toast(_ viewModel: CameraViewModel) -> some View {
        VStack(spacing: CIToken.Space.s) {
            QualityToast(
                lines: viewModel.toastLines.map { QualityToast.Line(passed: $0.passed, text: $0.text) },
                suggestion: viewModel.qualityToast?.issues.first?.suggestion
            )
            if viewModel.qualityToast?.passed == false {
                HStack(spacing: CIToken.Space.s) {
                    SecondaryButton(String(localized: "camera.retake")) {
                        viewModel.retake()
                    }
                    // 「このまま使う」は framing 等の非blocking NGのみ（SCR-CAM-03/04）
                    if viewModel.canAcceptDespiteWarning {
                        SecondaryButton(String(localized: "camera.acceptAnyway")) {
                            Task { await viewModel.acceptDespiteWarning() }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, CIToken.Space.m)
    }

    // サムネイル帯 + 操作（§2）
    private func bottomBar(_ viewModel: CameraViewModel) -> some View {
        VStack(spacing: CIToken.Space.s) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: CIToken.Space.s) {
                    ForEach(PhotoAngle.guided, id: \.self) { angle in
                        thumbnail(angle, viewModel: viewModel)
                    }
                }
                .padding(.horizontal, CIToken.Space.m)
            }

            HStack {
                Button {
                    viewModel.toggleTorch()
                } label: {
                    Image(systemName: viewModel.isTorchOn ? "bolt.fill" : "bolt.slash")
                        .font(.title2)
                        .foregroundStyle(viewModel.isTorchOn ? CIToken.Colors.warning : .white)
                        .frame(width: 56, height: 56)
                }
                .accessibilityLabel(Text("camera.torch"))

                Spacer()

                ShutterButton {
                    Task {
                        triggerShutterEffect()
                        await viewModel.capture()
                    }
                }
                .accessibilityIdentifier("camera.shutter")
                .disabled(viewModel.phase == .capturing || viewModel.phase == .checkingQuality)
                .accessibilityLabel(Text("camera.shutter.a11y \(String(localized: String.LocalizationValue(viewModel.currentAngle.localizationKey))) \(viewModel.capturedPhotos.count + 1)"))

                Spacer()

                Button {
                    viewModel.switchCamera()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath.camera")
                        .font(.title2)
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                }
                .accessibilityLabel(Text("camera.switch"))
            }
            .padding(.horizontal, CIToken.Space.l)
        }
        .padding(.vertical, CIToken.Space.s)
        .background(CIToken.Materials.glass)
    }

    private func thumbnail(_ angle: PhotoAngle, viewModel: CameraViewModel) -> some View {
        Button {
            viewModel.jumpTo(angle: angle)
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(viewModel.capturedPhotos[angle] != nil ? CIToken.Colors.accent.opacity(0.25) : .white.opacity(0.15))
                    .frame(width: 44, height: 44)
                if let asset = viewModel.capturedPhotos[angle],
                   let uiImage = UIImage(contentsOfFile: asset.localMaskedPath ?? asset.localOriginalPath) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 44, height: 44)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else {
                    Image(systemName: viewModel.currentAngle == angle ? "viewfinder" : "camera")
                        .font(.caption)
                        .foregroundStyle(.white)
                }
                if viewModel.currentAngle == angle {
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(CIToken.Colors.primary, lineWidth: 2)
                        .frame(width: 44, height: 44)
                }
            }
        }
        .accessibilityLabel(Text(LocalizedStringKey(angle.localizationKey)))
    }

    // ダメージ撮影セクション（12枚完了後、§2）
    private func damageSection(_ viewModel: CameraViewModel) -> some View {
        VStack(spacing: CIToken.Space.s) {
            GlassCard {
                VStack(alignment: .leading, spacing: CIToken.Space.s) {
                    Label("camera.damage.title", systemImage: "exclamationmark.circle")
                        .font(CIToken.Fonts.body.bold())
                        .foregroundStyle(.white)
                    Text("camera.damage.hint \(viewModel.damagePhotos.count)")
                        .font(CIToken.Fonts.caption)
                        .foregroundStyle(.white.opacity(0.85))
                    HStack(spacing: CIToken.Space.s) {
                        SecondaryButton(String(localized: "camera.damage.add")) {
                            Task { await viewModel.addDamagePhoto() }
                        }
                        if viewModel.phase == .damageCapture {
                            SecondaryButton(String(localized: "camera.damage.skip")) {
                                viewModel.skipDamageCapture()
                            }
                            .accessibilityIdentifier("camera.damage.skip")
                        }
                    }
                }
            }
            .environment(\.colorScheme, .dark)

            PrimaryButton(
                String(localized: "camera.submit \(viewModel.totalCount)"),
                isLoading: viewModel.isSubmitting,
                isEnabled: viewModel.canSubmit
            ) {
                Task {
                    if await viewModel.submitForAppraisal() {
                        path.append(.appraisalRunning(appraisalId: appraisalId))
                    }
                }
            }
            .accessibilityIdentifier("camera.submit")
        }
        .padding(.horizontal, CIToken.Space.m)
    }

    private var permissionDeniedView: some View {
        EmptyStateView(
            systemImage: "camera.badge.ellipsis",
            title: String(localized: "camera.permission.title"),
            message: String(localized: "camera.permission.message"),
            ctaTitle: String(localized: "camera.permission.openSettings")
        ) {
            #if os(iOS)
            if let url = URL(string: UIApplication.openSettingsURLString) {
                UIApplication.shared.open(url)
            }
            #endif
        }
        .background(CIToken.Colors.bgBase)
    }

    private func triggerShutterEffect() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        #endif
        shutterFlash = true
        Task {
            try? await Task.sleep(for: .milliseconds(100))
            shutterFlash = false
        }
    }

    private struct AlertWrapper: Identifiable {
        let id = UUID()
        let message: String
    }

    private func alertBinding(_ viewModel: CameraViewModel) -> Binding<AlertWrapper?> {
        Binding(
            get: {
                guard let error = viewModel.error, viewModel.phase != .permissionDenied else { return nil }
                return AlertWrapper(message: error.errorDescription ?? "")
            },
            set: { _ in viewModel.error = nil }
        )
    }
}

/// モック用ファインダー（シミュレータ・Preview）
struct MockViewfinderView: View {
    var body: some View {
        GeometryReader { proxy in
            Image(decorative: SyntheticImage.sharpCar(width: 1024, height: 768), scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: proxy.size.width, height: proxy.size.height)
                .clipped()
                .overlay(.black.opacity(0.15))
        }
    }
}

#if os(iOS)
import AVFoundation

/// AVCaptureVideoPreviewLayer の SwiftUI ラッパ
struct CameraPreviewLayerView: UIViewRepresentable {
    let session: AVCameraSession

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.previewLayer.session = session.session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {}

    final class PreviewHostView: UIView {
        override static var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer {
            guard let layer = layer as? AVCaptureVideoPreviewLayer else {
                preconditionFailure("layerClass mismatch")
            }
            return layer
        }
    }
}
#endif
