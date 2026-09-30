#if SKIP
import skip.foundation.Bundle
import skip.foundation.Locale
import android.icu.text.MessageFormat

/// Uses Skip's resource lookup and Android's locale-aware formatter.
/* SKIP @bridge */ public final class SpliitLocalizationBridge {
    /* SKIP @bridge */ nonisolated public static func resolve(
        key: String,
        values: [Any],
        table: String?,
        localeIdentifier: String?,
        bridgedBundle: Any?
    ) -> String {
        let bundle = bridgedBundle as? Bundle ?? Bundle.module
        let locale = localeIdentifier.map { Locale(identifier: $0) } ?? Locale.current
        let (_, format, _) = bundle.localizedInfo(forKey: key, value: nil, table: table, locale: locale)
        let platformLocale = java.util.Locale.forLanguageTag(locale.identifier.replace("_", "-"))
        let arguments = values.toList().toTypedArray()
        if (key == "%lld participants" || key == "%lld documents attached"),
           values.count == 1, format.contains("{0, plural,") {
            // ponytail: Skip's converter leaves these single-count printf slots inside ICU
            // branches. Remove this workaround when Skip handles unnumbered plural slots.
            return MessageFormat(format.replace("%d", "#"), platformLocale)
                .format(arguments)
        }
        // SKIP REPLACE: return java.lang.String.format(platformLocale, format, *arguments)
        return ""
    }
}
#elseif os(Android)
import Foundation
import SkipFuse

extension String {
    nonisolated init(
        localized value: AndroidLocalizedStringResource,
        table: String? = nil,
        bundle: Bundle? = nil,
        // Resolve the default on Android: native Foundation does not receive its app locale.
        locale: Foundation.Locale? = nil,
        comment: StaticString? = nil
    ) {
        self = SpliitLocalizationBridge.resolve(
            key: value.key,
            values: value.defaultValue.values,
            table: table,
            localeIdentifier: locale?.identifier,
            bridgedBundle: bundle
        )
    }
}
#endif
