import SwiftUI

/// 主要ボタン。ローディング状態内蔵（03 §2.4）。タップ領域 44pt 以上（03 §1）。
public struct PrimaryButton: View {
    private let title: String
    private let isLoading: Bool
    private let isEnabled: Bool
    private let action: () -> Void

    public init(_ title: String, isLoading: Bool = false, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isLoading = isLoading
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            HStack(spacing: CIToken.Space.s) {
                if isLoading {
                    ProgressView().tint(.white)
                }
                Text(title)
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.roundedRectangle(radius: CIToken.Radius.button))
        .tint(CIToken.Colors.primary)
        .disabled(!isEnabled || isLoading)
    }
}

/// 副次ボタン（iOS 26+ は Liquid Glass ボタンスタイル）
public struct SecondaryButton: View {
    private let title: String
    private let isEnabled: Bool
    private let action: () -> Void

    public init(_ title: String, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    public var body: some View {
        if #available(iOS 26.0, macOS 26.0, *) {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var button: some View {
        Button(action: action) {
            Text(title)
                .font(.headline)
                .frame(maxWidth: .infinity, minHeight: 50)
        }
        .buttonBorderShape(.roundedRectangle(radius: CIToken.Radius.button))
        .tint(CIToken.Colors.primary)
        .disabled(!isEnabled)
    }
}

/// カメラシャッター（72pt、03 §2.4 / SCREEN_CAMERA §2）
public struct ShutterButton: View {
    private let action: () -> Void

    public init(action: @escaping () -> Void) {
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .strokeBorder(.white, lineWidth: 4)
                    .frame(width: 72, height: 72)
                Circle()
                    .fill(.white)
                    .frame(width: 58, height: 58)
            }
        }
        .buttonStyle(.plain)
    }
}
