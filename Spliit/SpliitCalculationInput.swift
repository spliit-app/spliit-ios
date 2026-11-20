#if SKIP
import SkipUI
import androidx.compose.ui.text.TextRange
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalFocusManager

/// Compose selections use UTF-16 offsets, including reversed selections.
/* SKIP @bridge */ public final class SpliitCalculationInput: ContentComposer {
    private let dismissCount: Int

    /* SKIP @bridge */ public init(dismissCount: Int) {
        self.dismissCount = dismissCount
    }

    @Composable public func Compose(context: ComposeContext) {
        let focusManager = LocalFocusManager.current
        LaunchedEffect(dismissCount) {
            // Skip's focused(nil) updates the binding but does not clear Compose focus.
            if dismissCount > 0 { focusManager.clearFocus() }
        }
    }

    /* SKIP @bridge */ public static func insert(
        text: String, selection: TextSelection?, expression: String,
        update: @escaping (String, TextSelection) -> Void
    ) {
        /* SKIP INSERT:
        val range = selection?.asComposeTextRange() ?: TextRange(text.length)
        val start = range.min.coerceIn(0, text.length)
        val end = range.max.coerceIn(start, text.length)
        val updated = text.replaceRange(start, end, expression)
        update(updated, TextSelection(insertionPoint = start + expression.length))
        */
    }
}
#endif
