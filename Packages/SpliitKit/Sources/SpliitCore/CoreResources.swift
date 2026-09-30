import Foundation
#if SKIP_BRIDGE
import SkipFuse
#endif

enum CoreResources {
    static let bundle: Bundle = {
        #if os(Android) && SKIP_BRIDGE
        if isJNIInitialized {
            // ponytail: swiftbuild's .bundle URL accessor bypasses Skip's .resources
            // path mapping. Use that mapping until Skip supports the generated URL accessor.
            return AndroidBundle(
                path: AndroidBundle.main.bundlePath + "/_SpliitCore.resources",
                moduleName: "SpliitCore"
            ) {
                try! AnyDynamicObject(className: "spliit.core._ModuleBundleAccessor_SpliitCore").moduleBundle!
            }!
        }
        #endif
        return Bundle.module
    }()
}
