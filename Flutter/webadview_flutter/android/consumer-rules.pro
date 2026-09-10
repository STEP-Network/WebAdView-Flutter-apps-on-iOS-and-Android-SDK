# webadview_flutter — applied automatically to apps that minify (R8/ProGuard).
# The template bridge falls back to addJavascriptInterface on WebViews without
# WebMessageListener support; the annotated method must survive shrinking.
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}
