package cn.com.omnimind.bot.activity

import android.content.Context
import android.content.res.Configuration
import cn.com.omnimind.bot.R

object StartupThemeResolver {
    private const val FLUTTER_SHARED_PREFS_NAME = "FlutterSharedPreferences"
    private const val KEY_THEME_OPTION = "flutter.theme_option"
    private const val THEME_OPTION_SYSTEM = "system"
    private const val THEME_OPTION_LIGHT = "light"
    private const val THEME_OPTION_DARK = "dark"

    fun resolveSplashTheme(context: Context): Int {
        val storedPreference = runCatching {
            context.getSharedPreferences(
                FLUTTER_SHARED_PREFS_NAME,
                Context.MODE_PRIVATE
            ).getString(KEY_THEME_OPTION, THEME_OPTION_SYSTEM)
        }.getOrNull()

        val useDark = when (storedPreference) {
            THEME_OPTION_DARK -> true
            THEME_OPTION_LIGHT -> false
            else -> isSystemDark(context)
        }

        return if (useDark) {
            R.style.Theme_OmnibotApp_Splash_Dark
        } else {
            R.style.Theme_OmnibotApp_Splash
        }
    }

    private fun isSystemDark(context: Context): Boolean {
        val nightModeFlags =
            context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
        return nightModeFlags == Configuration.UI_MODE_NIGHT_YES
    }
}
