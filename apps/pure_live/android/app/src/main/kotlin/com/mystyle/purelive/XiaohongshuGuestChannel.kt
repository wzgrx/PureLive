package com.mystyle.purelive

import android.annotation.SuppressLint
import android.app.Activity
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.webkit.WebResourceRequest
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.WebResourceError
import android.graphics.Bitmap
import android.view.View
import android.view.ViewGroup
import androidx.webkit.ProfileStore
import androidx.webkit.WebStorageCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/** Finite visitor bootstrap in its own profile, never the default CookieManager. */
internal class XiaohongshuGuestChannel(private val activityProvider: () -> Activity?) {
    private val main = Handler(Looper.getMainLooper())
    private var active: Run? = null
    private var closing: Run? = null
    private var poisoned = false

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "run" -> start(call, result)
            "cancel" -> {
                val id = call.argument<String>("id")
                val run = active ?: closing
                if (run != null && id == run.id) {
                    run.waiters.add(result)
                    if (active === run) finish("cancelled", null)
                } else result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    fun dispose() = finish("cancelled", null)

    private class Run(val id: String, val view: WebView, val result: MethodChannel.Result) {
        var stage = "created"
        var timeout: Runnable? = null
        val waiters = mutableListOf<MethodChannel.Result>()
    }

    private fun supported(): Boolean =
        WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE) &&
            WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT) &&
            WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER) &&
            WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)

    @SuppressLint("SetJavaScriptEnabled")
    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        val url = call.argument<String>("url")
        val capture = call.argument<String>("capture")
        val script = call.argument<String>("script")
        val uri = url?.let(Uri::parse)
        if (id.isNullOrBlank() || id.length > 100 || uri == null || uri.scheme != "https" ||
            uri.host != "www.xiaohongshu.com" || uri.query != null || uri.fragment != null ||
            !(uri.path == "/livelist" || Regex("/livestream/[0-9]{9,20}").matches(uri.path.orEmpty())) ||
            capture == null || capture.length > 32768 || script == null || script.length > 65536
        ) {
            result.error("invalid", "Invalid visitor request", null)
            return
        }
        if (active != null || closing != null || poisoned) {
            result.error("busy", "Visitor browser is busy", null)
            return
        }
        if (!supported()) {
            result.error("unsupported", "WebView visitor isolation unavailable", null)
            return
        }
        val activity = activityProvider()
        if (activity == null || activity.isFinishing) {
            result.error("unavailable", "Visitor initialization needs the application window", null)
            return
        }
        var view: WebView? = null
        try {
            // Profiles can remain loaded after WebView.destroy(). Reuse only
            // this application-owned profile and clear ALL of its browsing
            // data with an acknowledged, profile-scoped API before and after
            // each job. Default-profile cookies and storage remain untouched.
            val browser = WebView(activity)
            view = browser
            WebViewCompat.setProfile(browser, PROFILE)
            browser.visibility = View.INVISIBLE
            activity.findViewById<ViewGroup>(android.R.id.content).addView(browser, 0, ViewGroup.LayoutParams(1280, 900))
            browser.settings.apply {
                javaScriptEnabled = true
                domStorageEnabled = true
                mediaPlaybackRequiresUserGesture = true
                userAgentString = USER_AGENT
                allowFileAccess = false
                allowContentAccess = false
                javaScriptCanOpenWindowsAutomatically = false
            }
            // A real viewport mounts the site's comment subscription. The
            // unattached page is destroyed before native chat starts.
            browser.measure(
                android.view.View.MeasureSpec.makeMeasureSpec(1280, android.view.View.MeasureSpec.EXACTLY),
                android.view.View.MeasureSpec.makeMeasureSpec(900, android.view.View.MeasureSpec.EXACTLY),
            )
            browser.layout(0, 0, 1280, 900)
            val run = Run(id, browser, result)
            active = run
            val job = "(async()=>{window.$BRIDGE.postMessage(JSON.stringify({phase:'script'}));try{const value=await(async()=>{$script})();window.$BRIDGE.postMessage(JSON.stringify({ok:true,value}));}catch(_){window.$BRIDGE.postMessage(JSON.stringify({ok:false,hasHeaders:!!window.__pureLiveXhs?.headers,hasIdentity:!!window.__pureLiveXhs?.identity,signer:typeof window._webmsxyw==='function'}));}})();"
            WebViewCompat.addDocumentStartJavaScript(browser, "$capture\n$job", setOf(ORIGIN))
            WebViewCompat.addWebMessageListener(browser, BRIDGE, setOf(ORIGIN)) { _, message, source, isMainFrame, _ ->
                if (active !== run || !isMainFrame || source.scheme != "https" || source.host != "www.xiaohongshu.com") return@addWebMessageListener
                val body = message.data
                if (body == null || body.length > 2 * 1024 * 1024 + 65536) {
                    finish("invalid", null)
                } else {
                    try {
                        val decoded = JSONObject(body)
                        if (decoded.optString("phase") == "script") run.stage = "script"
                        else if (decoded.optBoolean("ok")) finish(null, body)
                        else finish("failed", null, mapOf("has_headers" to decoded.optBoolean("hasHeaders"), "has_identity" to decoded.optBoolean("hasIdentity"), "signer" to decoded.optBoolean("signer")))
                    } catch (_: Exception) { finish("invalid", null) }
                }
            }
            browser.webViewClient = object : WebViewClient() {
                override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
                    if (active === run && run.stage == "created") run.stage = "load_started"
                }

                override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
                    if (active === run && request.isForMainFrame) finish("network", null, mapOf("network_code" to error.errorCode))
                }

                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
                    request.isForMainFrame && (request.url.scheme != "https" || request.url.host != "www.xiaohongshu.com")

            }
            val timeout = Runnable { if (active === run) finish("timeout", null) }
            run.timeout = timeout
            main.postDelayed(timeout, 29000)
            WebStorageCompat.deleteBrowsingData(ProfileStore.getInstance().getOrCreateProfile(PROFILE).webStorage) {
                if (active === run) browser.loadUrl(url)
            }
        } catch (_: Exception) {
            if (active != null) finish("failed", null)
            else {
                view?.destroy()
                result.error("failed", "Visitor initialization failed", null)
            }
        }
    }

    private fun finish(error: String?, body: String?, diagnostics: Map<String, Any> = emptyMap()) {
        val run = active ?: return
        active = null
        closing = run
        run.timeout?.let(main::removeCallbacks)
        try { run.view.stopLoading() } catch (_: Exception) { }
        (run.view.parent as? ViewGroup)?.removeView(run.view)
        try { run.view.destroy() } catch (_: Exception) { }
        var completed = false
        fun done(clean: Boolean) {
            if (completed) return
            completed = true
            closing = null
            if (!clean) poisoned = true
            if (!clean) run.result.error("cleanup", "Visitor cleanup failed", null)
            else if (error == null) run.result.success(body)
            else run.result.error(error, "Visitor initialization $error", diagnostics + mapOf("stage" to run.stage))
            run.waiters.forEach { it.success(null) }
            run.waiters.clear()
        }
        val cleanupTimeout = Runnable { done(false) }
        main.postDelayed(cleanupTimeout, 4000)
        try {
            WebStorageCompat.deleteBrowsingData(ProfileStore.getInstance().getOrCreateProfile(PROFILE).webStorage) {
                main.removeCallbacks(cleanupTimeout)
                // A delayed acknowledgement makes future jobs safe again;
                // queued jobs remain refused until this callback arrives.
                poisoned = false
                done(true)
            }
        } catch (_: Exception) { main.removeCallbacks(cleanupTimeout); done(false) }
    }

    companion object {
        private const val PROFILE = "purelive_xiaohongshu_visitor"
        private const val ORIGIN = "https://www.xiaohongshu.com"
        private const val BRIDGE = "PureLiveXhsVisitor"
        private const val USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
    }
}
