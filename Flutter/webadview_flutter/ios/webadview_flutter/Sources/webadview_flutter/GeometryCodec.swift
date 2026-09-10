import CoreGraphics
import Foundation

/// Wire format for rectangles on the method channel: `[x, y, width, height]`
/// in Flutter logical pixels, which equal iOS points when the Flutter view
/// fills the window. Every value from Dart is treated as untrusted input and
/// validated before it reaches the SDK.
enum GeometryCodec {

    static func rect(from value: Any?) -> CGRect? {
        guard let list = value as? [Any], list.count == 4 else { return nil }
        var numbers: [CGFloat] = []
        for item in list {
            guard let number = item as? NSNumber else { return nil }
            let double = number.doubleValue
            guard double.isFinite else { return nil }
            numbers.append(CGFloat(double))
        }
        return CGRect(x: numbers[0], y: numbers[1], width: numbers[2], height: numbers[3])
    }

    static func string(_ value: Any?) -> String? {
        value as? String
    }

    static func bool(_ value: Any?, default defaultValue: Bool) -> Bool {
        (value as? NSNumber)?.boolValue ?? (value as? Bool) ?? defaultValue
    }

    static func double(_ value: Any?) -> Double? {
        guard let number = value as? NSNumber else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }

    /// `{key: [values]}` — only string keys and string values survive.
    static func targeting(from value: Any?) -> [String: [String]] {
        guard let dictionary = value as? [String: Any] else { return [:] }
        var result: [String: [String]] = [:]
        for (key, raw) in dictionary {
            if let list = raw as? [Any] {
                let values = list.compactMap { $0 as? String }
                if !values.isEmpty { result[key] = values }
            } else if let single = raw as? String {
                result[key] = [single]
            }
        }
        return result
    }
}
