package spliit.ui

import android.app.Application
import android.graphics.Color as AndroidColor
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.appcompat.app.AppCompatActivity
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.saveable.rememberSaveableStateHolder
import androidx.compose.ui.Alignment
import androidx.compose.ui.graphics.luminance
import androidx.compose.ui.platform.LocalContext
import skip.foundation.ProcessInfo
import skip.ui.*

class AndroidAppMain : Application() {
    override fun onCreate() {
        super.onCreate()
        ProcessInfo.launch(applicationContext)

    }
}

class MainActivity : AppCompatActivity() {
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        UIApplication.launch(this)
        // adb shell am start -S -n app.spliit.android.prototype/spliit.ui.MainActivity --ez checkLocalization true
        if (BuildConfig.DEBUG && intent.getBooleanExtra("checkLocalization", false)) {
            checkLocalization()
        }
        enableEdgeToEdge()

        setContent {
            val saveableStateHolder = rememberSaveableStateHolder()
            saveableStateHolder.SaveableStateProvider(true) {
                PresentationRootView(ComposeContext())
                SideEffect { saveableStateHolder.removeState(true) }
            }
        }
    }
}

@Composable
private fun SyncSystemBarsWithTheme() {
    val dark = MaterialTheme.colorScheme.background.luminance() < 0.5f
    val transparent = AndroidColor.TRANSPARENT
    val style = if (dark) {
        SystemBarStyle.dark(transparent)
    } else {
        SystemBarStyle.light(transparent, transparent)
    }
    val activity = LocalContext.current as? ComponentActivity
    DisposableEffect(style) {
        activity?.enableEdgeToEdge(statusBarStyle = style, navigationBarStyle = style)
        onDispose { }
    }
}

@Composable
private fun PresentationRootView(context: ComposeContext) {
    val colorScheme = if (isSystemInDarkTheme()) ColorScheme.dark else ColorScheme.light
    PresentationRoot(defaultColorScheme = colorScheme, context = context) { ctx ->
        SyncSystemBarsWithTheme()
        val contentContext = ctx.content()
        Box(modifier = ctx.modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            SpliitUIRootView().Compose(context = contentContext)
        }
    }
}

// Runs the actual generated bridge against APK resources and Android ICU, without a test framework.
private fun checkLocalization() {
    fun resolve(key: String, locale: String, vararg values: Any): String =
        SpliitLocalizationBridge.resolve(key, skip.lib.Array(values.toList()), null, locale, null)
    for (locale in listOf("en", "fr")) {
        for (count in 0L..2L) {
            val singular = count == 1L || (locale == "fr" && count == 0L)
            val participants = if (singular) "participant" else "participants"
            val documents = when {
                locale == "fr" && singular -> "document joint"
                locale == "fr" -> "documents joints"
                singular -> "document attached"
                else -> "documents attached"
            }
            check(resolve("%lld participants", locale, count) == "$count $participants")
            check(resolve("%lld documents attached", locale, count) == "$count $documents")
        }
        check(resolve("%2\$@ / %1\$@", locale, "Ana", "Bruno") == "Bruno / Ana")
        check(resolve("%lld%% for %@", locale, 50L, "Ana") == "50% for Ana")
    }
    android.util.Log.i("SpliitLocalizationCheck", "PASS: en/fr plurals, reordered arguments, percent escaping")
}
