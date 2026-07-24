import Foundation
import os

/// 構造化ログ（02_SYSTEM_ARCHITECTURE.md §9）
public enum CILogger {
    public static func logger(category: String) -> Logger {
        Logger(subsystem: "com.animetourism.carinspector", category: category)
    }
}
