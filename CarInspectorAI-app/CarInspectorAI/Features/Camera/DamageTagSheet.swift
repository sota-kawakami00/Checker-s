import SwiftUI
import DesignSystem

/// ダメージ部位タグシート（SCREEN_CAMERA §2: 部位グリッド選択 + 任意メモ）。
/// 部位コードは auction_comparison.schema.json の partCode enum と共通体系。
struct DamageTagSheet: View {
    let onSave: (String, String?) -> Void
    let onCancel: () -> Void

    @State private var selectedTag: String?
    @State private var memo = ""

    /// (コード, 表示キー)
    private static let parts: [(String, LocalizedStringKey)] = [
        ("frontBumper", "part.frontBumper"),
        ("rearBumper", "part.rearBumper"),
        ("hood", "part.hood"),
        ("roof", "part.roof"),
        ("trunk", "part.trunk"),
        ("leftFrontFender", "part.leftFrontFender"),
        ("rightFrontFender", "part.rightFrontFender"),
        ("leftRearFender", "part.leftRearFender"),
        ("rightRearFender", "part.rightRearFender"),
        ("leftFrontDoor", "part.leftFrontDoor"),
        ("rightFrontDoor", "part.rightFrontDoor"),
        ("leftRearDoor", "part.leftRearDoor"),
        ("rightRearDoor", "part.rightRearDoor"),
        ("leftSideStep", "part.leftSideStep"),
        ("rightSideStep", "part.rightSideStep"),
        ("windshield", "part.windshield"),
        ("other", "part.other")
    ]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: CIToken.Space.m) {
                    Text("camera.damage.selectPart")
                        .font(CIToken.Fonts.titleL)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: CIToken.Space.s)], spacing: CIToken.Space.s) {
                        ForEach(Self.parts, id: \.0) { code, labelKey in
                            Button {
                                selectedTag = code
                            } label: {
                                Text(labelKey)
                                    .font(CIToken.Fonts.caption)
                                    .lineLimit(1)
                                    .padding(.vertical, CIToken.Space.s)
                                    .frame(maxWidth: .infinity)
                                    .background(
                                        selectedTag == code ? CIToken.Colors.primary.opacity(0.2) : Color.gray.opacity(0.1),
                                        in: RoundedRectangle(cornerRadius: CIToken.Radius.button)
                                    )
                                    .foregroundStyle(selectedTag == code ? CIToken.Colors.primary : .primary)
                            }
                            .buttonStyle(.plain)
                        }
                    }

                    Text("camera.damage.memo")
                        .font(CIToken.Fonts.body.bold())
                    TextField("camera.damage.memo.placeholder", text: $memo, axis: .vertical)
                        .lineLimit(2...4)
                        .padding(CIToken.Space.s)
                        .background(Color.gray.opacity(0.08), in: RoundedRectangle(cornerRadius: CIToken.Radius.button))

                    PrimaryButton(String(localized: "common.save"), isEnabled: selectedTag != nil) {
                        if let selectedTag {
                            onSave(selectedTag, memo.isEmpty ? nil : memo)
                        }
                    }
                }
                .padding(CIToken.Space.m)
            }
            .navigationTitle(Text("camera.damage.sheetTitle"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.cancel") { onCancel() }
                }
            }
        }
    }
}
