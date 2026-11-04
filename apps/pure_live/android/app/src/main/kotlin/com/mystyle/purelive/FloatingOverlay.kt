package com.mystyle.purelive

import android.animation.ValueAnimator
import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.graphics.PixelFormat
import android.graphics.Rect
import android.net.Uri
import android.os.Build
import android.provider.Settings
import android.util.DisplayMetrics
import android.view.Gravity
import android.view.MotionEvent
import android.view.VelocityTracker
import android.view.WindowInsets
import android.view.WindowManager
import android.view.animation.LinearInterpolator
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.android.FlutterView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * The app's own floating window over other apps (A07.25, "小窗整体设计" c8):
 * the in-app mini window, or the playing room, goes on floating when the
 * app is left, with the app's own buttons, instead of becoming the system's
 * picture-in-picture. Needs "显示在其他应用的上层" (SYSTEM_ALERT_WINDOW).
 *
 * The app's one Flutter engine (kept by audio_service, it outlives the
 * activity) moves from the activity's view to a small [FlutterView] in a
 * `TYPE_APPLICATION_OVERLAY` window and back, so the player, its picture
 * and the danmaku go on untouched; Dart draws only the mini window while
 * [showing]. The app's lifecycle is not reported meanwhile (the app looks
 * on screen to Dart, which it is).
 *
 * The window behaves as the in-app one (`logic/mini_window.dart`): let go,
 * it springs to the nearer side, 16 dp in, between the status bar and the
 * gesture bar; flung past an edge it tucks in with a fifth of it showing
 * (at least 56 dp, and 32 dp beyond the back gesture's strip), that strip
 * kept out of the back gesture; the grip grows it towards the middle of the
 * screen (sideways, or down), two fingers about its centre.
 *
 * Channel `pure_live/overlay`: `status` (whether the permission is given),
 * `openSettings`, `arm {enabled, x, y, width, height}` (the window's place on
 * the screen in pixels), `close`, `backToApp`, `dragStart`, `resizeStart`,
 * `pinchStart`, `pinch {factor}`, `resizeEnd`, `untuck`; to Dart `changed`
 * (true / false), `tucked` (`left`, `right` or null) and, as the window goes,
 * `placed {x, y, width, height, tucked}`.
 */
object FloatingOverlay {
    const val CHANNEL = "pure_live/overlay"

    // The in-app window's numbers, in dp (logic/mini_window.dart).
    private const val MARGIN = 16f
    private const val PEEK_MIN = 56f
    private const val PEEK_BEYOND_GESTURE = 32f
    private const val SMALLEST = 160f
    private const val EXCLUSION_MAX = 200f

    // How far a fling carries the window: its speed × this many seconds.
    private const val FLING_SECONDS = 0.18f

    // AppMotion.floatingSpring: mass 1, stiffness 500, critically damped.
    private val SPRING_OMEGA = sqrt(500.0)

    private var channel: MethodChannel? = null
    private var engine: FlutterEngine? = null
    private var activity = WeakReference<Activity>(null)

    private var armed = false
    private var armedX = 0
    private var armedY = 0
    private var armedWidth = 0
    private var armedHeight = 0

    /** The app is being left with the window armed: lifecycle not reported. */
    var leaving = false
        private set

    /** The floating window shows. */
    var showing = false
        private set

    private var view: FlutterView? = null
    private var params: WindowManager.LayoutParams? = null

    /** The side the window is tucked into: -1 left, 1 right, 0 none. */
    private var tuckedSide = 0

    /** The window's buttons show: its grip is kept out of the back gesture. */
    private var gripExcluded = false

    // A drag or resize the Dart side started, followed with raw screen
    // coordinates (the window moves under the finger, so the view's own
    // coordinates cannot).
    private enum class Gesture { NONE, DRAG, RESIZE, PINCH }

    private var gesture = Gesture.NONE
    private var lastRawX = 0f
    private var lastRawY = 0f
    private var startRawX = 0f
    private var startRawY = 0f
    private var startX = 0
    private var startY = 0
    private var startWidth = 0
    private var startHeight = 0
    private var resizeLeft = false
    private var velocity: VelocityTracker? = null
    private var settle: ValueAnimator? = null

    fun attach(activity: Activity, engine: FlutterEngine) {
        this.activity = WeakReference(activity)
        if (this.engine === engine && channel != null) return
        this.engine = engine
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                val context = this@FloatingOverlay.activity.get()?.applicationContext
                when (call.method) {
                    "status" -> result.success(context != null && permitted(context))
                    "openSettings" -> result.success(context != null && openSettings(context))
                    "arm" -> {
                        armed = call.argument<Boolean>("enabled") ?: false
                        armedX = call.argument<Number>("x")?.toInt() ?: 0
                        armedY = call.argument<Number>("y")?.toInt() ?: 0
                        armedWidth = call.argument<Number>("width")?.toInt() ?: 0
                        armedHeight = call.argument<Number>("height")?.toInt() ?: 0
                        result.success(null)
                    }
                    "close" -> {
                        close()
                        result.success(null)
                    }
                    "backToApp" -> result.success(context != null && backToApp(context))
                    "dragStart" -> {
                        startGesture(Gesture.DRAG)
                        result.success(null)
                    }
                    "resizeStart" -> {
                        startGesture(Gesture.RESIZE)
                        result.success(null)
                    }
                    "pinchStart" -> {
                        startGesture(Gesture.PINCH)
                        result.success(null)
                    }
                    "pinch" -> {
                        pinch(call.argument<Number>("factor")?.toFloat() ?: 1f)
                        result.success(null)
                    }
                    "resizeEnd" -> {
                        endGesture()
                        result.success(null)
                    }
                    "untuck" -> {
                        untuck()
                        result.success(null)
                    }
                    "excludeGrip" -> {
                        gripExcluded = call.argument<Boolean>("on") ?: false
                        applyExclusion()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    fun permitted(context: Context): Boolean =
        Build.VERSION.SDK_INT < Build.VERSION_CODES.M || Settings.canDrawOverlays(context)

    private fun openSettings(context: Context): Boolean = try {
        context.startActivity(
            Intent(Settings.ACTION_MANAGE_OVERLAY_PERMISSION, Uri.parse("package:${context.packageName}"))
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
        )
        true
    } catch (_: ActivityNotFoundException) {
        false
    }

    /** Home or recents (`onUserLeaveHint`): the window shows once the activity stops. */
    fun onLeaving(activity: Activity) {
        leaving = armed && armedWidth > 0 && armedHeight > 0 && permitted(activity)
    }

    /** The activity stopped; false when the window did not show (the lifecycle goes on as usual). */
    fun show(activity: Activity): Boolean {
        val engine = engine ?: return false
        if (!leaving || showing) return showing
        val context = activity.applicationContext
        val windowManager = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val surface = FlutterSurfaceView(context)
        val overlay = FlutterView(context, surface)
        val layout = WindowManager.LayoutParams(
            armedWidth,
            armedHeight,
            WindowManager.LayoutParams.TYPE_APPLICATION_OVERLAY,
            WindowManager.LayoutParams.FLAG_NOT_FOCUSABLE or
                WindowManager.LayoutParams.FLAG_HARDWARE_ACCELERATED or
                WindowManager.LayoutParams.FLAG_LAYOUT_IN_SCREEN or
                // Tucked into a side, most of it is off the screen.
                WindowManager.LayoutParams.FLAG_LAYOUT_NO_LIMITS,
            PixelFormat.OPAQUE,
        ).apply {
            gravity = Gravity.TOP or Gravity.START
            x = armedX
            y = armedY
        }
        return try {
            activity.findViewById<FlutterView>(FlutterActivity.FLUTTER_VIEW_ID)?.detachFromFlutterEngine()
            overlay.attachToFlutterEngine(engine)
            overlay.setOnTouchListener { _, event ->
                follow(event)
                false
            }
            windowManager.addView(overlay, layout)
            view = overlay
            params = layout
            showing = true
            tuckedSide = 0
            gripExcluded = false
            engine.lifecycleChannel.appIsResumed()
            channel?.invokeMethod("changed", true)
            true
        } catch (error: RuntimeException) {
            // Refused (the permission was taken away meanwhile): back to the
            // activity's view.
            overlay.detachFromFlutterEngine()
            activity.findViewById<FlutterView>(FlutterActivity.FLUTTER_VIEW_ID)?.attachToFlutterEngine(engine)
            leaving = false
            false
        }
    }

    /** The activity comes back (or a new one starts): the window goes, the activity's view draws again. */
    fun onReturn(activity: Activity) {
        leaving = false
        if (!showing) return
        removeWindow()
        engine?.let { activity.findViewById<FlutterView>(FlutterActivity.FLUTTER_VIEW_ID)?.attachToFlutterEngine(it) }
        channel?.invokeMethod("changed", false)
    }

    /** Explicit task removal must not leave this application-owned window alive. */
    fun onTaskRemoved() {
        armed = false
        leaving = false
        if (!showing) return
        removeWindow()
        channel?.invokeMethod("changed", false)
    }

    /** A new activity is created while the window shows: its own view takes the engine. */
    fun onNewActivity() {
        leaving = false
        if (!showing) return
        removeWindow()
        channel?.invokeMethod("changed", false)
    }

    /** The window's ✕: it goes and the app stays in the background. */
    private fun close() {
        leaving = false
        if (!showing) return
        removeWindow()
        val engine = engine ?: return
        activity.get()?.findViewById<FlutterView>(FlutterActivity.FLUTTER_VIEW_ID)?.attachToFlutterEngine(engine)
        channel?.invokeMethod("changed", false)
        engine.lifecycleChannel.appIsPaused()
    }

    /** Takes the window away; Dart learns where it was (the in-app window opens there). */
    private fun removeWindow() {
        val overlay = view
        val layout = params
        settle?.cancel()
        settle = null
        if (layout != null) {
            channel?.invokeMethod(
                "placed",
                mapOf(
                    "x" to layout.x,
                    "y" to layout.y,
                    "width" to layout.width,
                    "height" to layout.height,
                    "tucked" to sideName(tuckedSide),
                ),
            )
        }
        view = null
        params = null
        showing = false
        gesture = Gesture.NONE
        tuckedSide = 0
        velocity?.recycle()
        velocity = null
        if (overlay == null) return
        overlay.setOnTouchListener(null)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) overlay.systemGestureExclusionRects = emptyList()
        overlay.detachFromFlutterEngine()
        val windowManager = overlay.context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        try {
            windowManager.removeView(overlay)
        } catch (_: IllegalArgumentException) {
            // Already gone.
        }
    }

    private fun backToApp(context: Context): Boolean = try {
        context.startActivity(
            Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_REORDER_TO_FRONT),
        )
        true
    } catch (_: ActivityNotFoundException) {
        false
    }

    private fun sideName(side: Int): String? = when (side) {
        -1 -> "left"
        1 -> "right"
        else -> null
    }

    /** The screen in pixels and what the system takes of it. */
    private class Screen(
        val width: Int,
        val height: Int,
        val top: Int,
        val bottom: Int,
        val gestureLeft: Int,
        val gestureRight: Int,
        val density: Float,
    )

    private fun screen(overlay: FlutterView): Screen {
        val windowManager = overlay.context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val density = overlay.resources.displayMetrics.density
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val metrics = windowManager.currentWindowMetrics
            val bars = metrics.windowInsets.getInsets(WindowInsets.Type.systemBars())
            val gestures = metrics.windowInsets.getInsets(WindowInsets.Type.systemGestures())
            return Screen(
                metrics.bounds.width(),
                metrics.bounds.height(),
                bars.top,
                bars.bottom,
                gestures.left,
                gestures.right,
                density,
            )
        }
        val real = DisplayMetrics()
        @Suppress("DEPRECATION")
        windowManager.defaultDisplay.getRealMetrics(real)
        val resources = overlay.resources
        fun dimension(name: String): Int {
            val id = resources.getIdentifier(name, "dimen", "android")
            return if (id > 0) resources.getDimensionPixelSize(id) else 0
        }
        return Screen(
            real.widthPixels,
            real.heightPixels,
            dimension("status_bar_height"),
            dimension("navigation_bar_height"),
            0,
            0,
            density,
        )
    }

    /** How much of a window [width] wide tucked into [side] shows (`inAppMiniPeekFor`). */
    private fun peek(screen: Screen, width: Int, side: Int): Int {
        val gesture = if (side < 0) screen.gestureLeft else screen.gestureRight
        return max(max(width / 5f, PEEK_MIN * screen.density), gesture + PEEK_BEYOND_GESTURE * screen.density)
            .roundToInt()
    }

    /** The left edges a window [width] wide may have, 16 dp from the sides when it fits. */
    private fun across(screen: Screen, width: Int): Pair<Int, Int> {
        val margin = (MARGIN * screen.density).roundToInt()
        return if (screen.width - width >= margin * 2) {
            margin to screen.width - width - margin
        } else {
            0 to max(0, screen.width - width)
        }
    }

    private fun clampTop(screen: Screen, y: Int, height: Int): Int =
        y.coerceIn(min(screen.top, screen.height - screen.bottom - height), max(screen.top, screen.height - screen.bottom - height))

    private fun startGesture(kind: Gesture) {
        val layout = params ?: return
        val overlay = view ?: return
        settle?.cancel()
        settle = null
        gesture = kind
        startRawX = lastRawX
        startRawY = lastRawY
        startX = layout.x
        startY = layout.y
        startWidth = layout.width
        startHeight = layout.height
        // The grip grows the window towards the middle of the screen.
        resizeLeft = layout.x + layout.width / 2 > screen(overlay).width / 2
        if (kind == Gesture.DRAG) setTucked(0)
    }

    private fun follow(event: MotionEvent) {
        lastRawX = event.rawX
        lastRawY = event.rawY
        val layout = params ?: return
        val overlay = view ?: return
        when (event.actionMasked) {
            MotionEvent.ACTION_DOWN -> {
                velocity?.recycle()
                velocity = VelocityTracker.obtain()
                track(event)
            }
            MotionEvent.ACTION_MOVE -> {
                track(event)
                when (gesture) {
                    Gesture.DRAG -> {
                        val screen = screen(overlay)
                        // Past the sides as long as a peek stays on screen.
                        val left = min(peek(screen, layout.width, -1) - layout.width, 0)
                        val right = max(screen.width - peek(screen, layout.width, 1), 0)
                        layout.x = (startX + (event.rawX - startRawX).roundToInt()).coerceIn(left, right)
                        layout.y = clampTop(screen, startY + (event.rawY - startRawY).roundToInt(), layout.height)
                        update(overlay, layout)
                    }
                    Gesture.RESIZE -> resizeBy(overlay, layout, event.rawX - startRawX, event.rawY - startRawY)
                    Gesture.PINCH, Gesture.NONE -> Unit
                }
            }
            MotionEvent.ACTION_UP, MotionEvent.ACTION_CANCEL -> {
                track(event)
                if (gesture == Gesture.DRAG) {
                    val tracker = velocity
                    tracker?.computeCurrentVelocity(1000)
                    settleAfterDrag(overlay, layout, tracker?.xVelocity ?: 0f, tracker?.yVelocity ?: 0f)
                    gesture = Gesture.NONE
                } else if (gesture == Gesture.RESIZE) {
                    endGesture()
                }
                velocity?.recycle()
                velocity = null
            }
        }
    }

    private fun track(event: MotionEvent) {
        val tracker = velocity ?: return
        // On the screen: the window moves under the finger.
        val copy = MotionEvent.obtain(event)
        copy.setLocation(event.rawX, event.rawY)
        tracker.addMovement(copy)
        copy.recycle()
    }

    /** The grip moved by [dx], [dy] (`inAppMiniGripExtent`): towards the middle or down grows it. */
    private fun resizeBy(overlay: FlutterView, layout: WindowManager.LayoutParams, dx: Float, dy: Float) {
        val screen = screen(overlay)
        val ratio = startWidth.toFloat() / max(1, startHeight)
        val wider = if (resizeLeft) -dx else dx
        val byHeight = dy * ratio
        val grow = if (byHeight > 0 && byHeight > wider) byHeight else wider
        val width = sized(screen, startWidth + grow, ratio)
        val height = (width / ratio).roundToInt()
        layout.width = width
        layout.height = height
        layout.x = if (resizeLeft) startX + startWidth - width else startX
        layout.y = startY
        update(overlay, layout)
    }

    /** Two fingers: [factor] of the size they began with, about its centre. */
    private fun pinch(factor: Float) {
        val layout = params ?: return
        val overlay = view ?: return
        if (gesture != Gesture.PINCH) return
        val screen = screen(overlay)
        val ratio = startWidth.toFloat() / max(1, startHeight)
        val width = sized(screen, startWidth * factor, ratio)
        val height = (width / ratio).roundToInt()
        layout.x = startX + (startWidth - width) / 2
        layout.y = startY + (startHeight - height) / 2
        layout.width = width
        layout.height = height
        update(overlay, layout)
    }

    /** A width from 160 dp on the long side up to the screen's width and the room between the bars. */
    private fun sized(screen: Screen, wanted: Float, ratio: Float): Int {
        val smallest = if (ratio >= 1) SMALLEST * screen.density else SMALLEST * screen.density * ratio
        val room = (screen.height - screen.top - screen.bottom).toFloat()
        val largest = min(screen.width.toFloat(), room * ratio)
        return wanted.coerceIn(smallest, max(smallest, largest)).roundToInt()
    }

    /** A resize let go: the window stays where it is, on the screen. */
    private fun endGesture() {
        val layout = params ?: return
        val overlay = view ?: return
        if (gesture == Gesture.NONE) return
        gesture = Gesture.NONE
        val screen = screen(overlay)
        val (from, to) = across(screen, layout.width)
        slideTo(overlay, layout, layout.x.coerceIn(from, to), clampTop(screen, layout.y, layout.height), 0f, 0f, 0)
    }

    /** `inAppMiniSettle`: carried on by the fling, then to the nearer side or, past an edge, tucked in. */
    private fun settleAfterDrag(overlay: FlutterView, layout: WindowManager.LayoutParams, vx: Float, vy: Float) {
        val screen = screen(overlay)
        val carriedX = layout.x + vx * FLING_SECONDS
        val carriedY = layout.y + vy * FLING_SECONDS
        val centre = carriedX + layout.width / 2f
        val top = clampTop(screen, carriedY.roundToInt(), layout.height)
        when {
            centre < 0 -> slideTo(overlay, layout, peek(screen, layout.width, -1) - layout.width, top, vx, vy, -1)
            centre > screen.width -> slideTo(overlay, layout, screen.width - peek(screen, layout.width, 1), top, vx, vy, 1)
            else -> {
                val (from, to) = across(screen, layout.width)
                slideTo(overlay, layout, if (centre < screen.width / 2f) from else to, top, vx, vy, 0)
            }
        }
    }

    /** A tap on the tucked strip: back to that side. */
    private fun untuck() {
        val layout = params ?: return
        val overlay = view ?: return
        if (tuckedSide == 0) return
        val screen = screen(overlay)
        val (from, to) = across(screen, layout.width)
        slideTo(overlay, layout, if (tuckedSide < 0) from else to, layout.y, 0f, 0f, 0)
    }

    /**
     * Springs the window to [x], [y] leaving at the finger's [vx], [vy] and
     * never past the end (`ReleaseSpringSimulation` on `AppMotion.floatingSpring`);
     * then it is tucked into [side] (or not).
     */
    private fun slideTo(overlay: FlutterView, layout: WindowManager.LayoutParams, x: Int, y: Int, vx: Float, vy: Float, side: Int) {
        settle?.cancel()
        val x0 = layout.x.toFloat()
        val y0 = layout.y.toFloat()
        val done = {
            layout.x = x
            layout.y = y
            update(overlay, layout)
            setTucked(side)
        }
        if (abs(x0 - x) < 1 && abs(y0 - y) < 1) {
            done()
            return
        }
        val animator = ValueAnimator.ofFloat(0f, 1f).apply {
            duration = 600
            interpolator = LinearInterpolator()
        }
        animator.addUpdateListener {
            val time = it.currentPlayTime / 1000.0
            val nx = spring(x0.toDouble(), x.toDouble(), vx.toDouble(), time)
            val ny = spring(y0.toDouble(), y.toDouble(), vy.toDouble(), time)
            layout.x = nx.roundToInt()
            layout.y = ny.roundToInt()
            update(overlay, layout)
            if (abs(nx - x) < 0.5 && abs(ny - y) < 0.5) it.cancel()
        }
        animator.addListener(object : android.animation.AnimatorListenerAdapter() {
            private var ended = false

            override fun onAnimationEnd(animation: android.animation.Animator) {
                if (ended) return
                ended = true
                if (settle === animator) settle = null
                if (view === overlay) done()
            }
        })
        settle = animator
        if (side == 0) setTucked(0)
        animator.start()
    }

    /** A critically damped spring from [start] to [end] leaving at [speed], held at [end] once there. */
    private fun spring(start: Double, end: Double, speed: Double, time: Double): Double {
        val offset = start - end
        val value = end + (offset + (speed + SPRING_OMEGA * offset) * time) * exp(-SPRING_OMEGA * time)
        // Never past the end: a fast release stops there.
        return if (offset != 0.0 && (value - end) * offset < 0) end else value
    }

    /** The window is tucked into [side] (or not): Dart draws the handle, the strip keeps out of back. */
    private fun setTucked(side: Int) {
        val overlay = view ?: return
        val layout = params ?: return
        if (side != tuckedSide) {
            tuckedSide = side
            channel?.invokeMethod("tucked", sideName(side))
        }
        applyExclusion()
    }

    /** The tucked strip, or the grip while the buttons show, kept out of the back gesture. */
    private fun applyExclusion() {
        val overlay = view ?: return
        val layout = params ?: return
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) return
        val screen = screen(overlay)
        val side = tuckedSide
        overlay.systemGestureExclusionRects = when {
            side != 0 -> {
                val shown = peek(screen, layout.width, side)
                val height = min(layout.height, (EXCLUSION_MAX * screen.density).roundToInt())
                val top = (layout.height - height) / 2
                val left = if (side < 0) layout.width - shown else 0
                listOf(Rect(left, top, left + shown, top + height))
            }
            gripExcluded -> {
                val grip = (48 * screen.density).roundToInt()
                listOf(Rect(layout.width - grip, layout.height - grip, layout.width, layout.height))
            }
            else -> emptyList()
        }
    }

    private fun update(overlay: FlutterView, layout: WindowManager.LayoutParams) {
        val windowManager = overlay.context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        try {
            windowManager.updateViewLayout(overlay, layout)
        } catch (_: IllegalArgumentException) {
            // The window went meanwhile.
        }
    }
}
