import Foundation

/// パッケージ内文言の解決。
/// v1 は日本語のみ提供（NFR-11: 構造上多言語可能）のため、端末言語に ja が含まれない
/// 環境でも ja.lproj へ確実にフォールバックする。
enum L10n {
    static func string(_ key: String) -> String {
        let bundle = Bundle.module
        let resolved = bundle.localizedString(forKey: key, value: key, table: nil)
        if resolved == key,
           let path = bundle.path(forResource: "ja", ofType: "lproj"),
           let jaBundle = Bundle(path: path) {
            return jaBundle.localizedString(forKey: key, value: key, table: nil)
        }
        return resolved
    }

    static func format(_ key: String, _ args: CVarArg...) -> String {
        String(format: string(key), locale: Locale(identifier: "ja_JP"), arguments: args)
    }
}
