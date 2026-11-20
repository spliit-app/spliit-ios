#if SKIP
import skip.ui.ComposeContext
import skip.ui.ContentComposer
import androidx.activity.OnBackPressedCallback
import androidx.activity.findViewTreeOnBackPressedDispatcherOwner
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalView

/// Register on the sheet's dialog, whose dispatcher is separate from the activity's.
/* SKIP @bridge */ public final class SpliitSheetBackGuard: ContentComposer {
    private let isDisabled: Bool

    /* SKIP @bridge */ nonisolated public init(isDisabled: Bool) {
        self.isDisabled = isDisabled
    }

    @Composable public func Compose(context: ComposeContext) {
        /* SKIP INSERT:
        val view = LocalView.current
        val dispatcher = checkNotNull(view.findViewTreeOnBackPressedDispatcherOwner()).onBackPressedDispatcher
        val callback = remember(dispatcher) {
            object : OnBackPressedCallback(isDisabled) {
                override fun handleOnBackPressed() {}
            }
        }
        SideEffect { callback.isEnabled = isDisabled }
        DisposableEffect(dispatcher) {
            dispatcher.addCallback(callback)
            onDispose { callback.remove() }
        }
        */
    }
}
#else
import SwiftUI

extension View {
    /// Keep the draft visible until its write finishes, including Android system Back.
    func savingDismissDisabled(_ isSaving: Bool) -> some View {
        interactiveDismissDisabled(isSaving)
            #if os(Android)
            .background(ComposeView { SpliitSheetBackGuard(isDisabled: isSaving) })
            #endif
    }
}
#endif
