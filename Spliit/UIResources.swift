import Foundation
#if SKIP_BRIDGE
import SkipFuse
#endif

enum UIResources {
    static let bundle: Bundle = {
        #if os(Android) && SKIP_BRIDGE
        if isJNIInitialized {
            // ponytail: swiftbuild's .bundle URL accessor bypasses Skip's .resources
            // path mapping. Use that mapping until Skip supports the generated URL accessor.
            return AndroidBundle(
                path: AndroidBundle.main.bundlePath + "/_SpliitUI.resources",
                moduleName: "SpliitUI"
            ) {
                try! AnyDynamicObject(className: "spliit.ui._ModuleBundleAccessor_SpliitUI").moduleBundle!
            }!
        }
        #endif
        return Bundle.module
    }()
}
