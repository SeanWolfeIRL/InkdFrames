package com.inkdframes.app

import android.content.Intent
import android.net.Uri
import android.util.Log
import android.view.MotionEvent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val channelName = "com.inkdframes.app/share"
    private val penChannelName = "com.inkdframes.app/spen"
    private var penChannel: MethodChannel? = null

    // Passive S Pen diagnostic.
    //
    // Android MotionEvent MOVE packets can contain both the latest stylus
    // position and older high-frequency historical samples. Flutter's normal
    // Android pointer path may not expose those historical samples to Dart.
    //
    // This probe never consumes or modifies an event. It simply counts the
    // original Android samples and reports one summary when the stylus lifts.
    private var penMoveEvents = 0
    private var penHistoricalSamples = 0
    private var penMaximumHistorySize = 0
    private var penDownEventTime = 0L

    private fun stylusPointerIndex(event: MotionEvent): Int {
        for (index in 0 until event.pointerCount) {
            val toolType = event.getToolType(index)

            if (
                toolType == MotionEvent.TOOL_TYPE_STYLUS ||
                toolType == MotionEvent.TOOL_TYPE_ERASER
            ) {
                return index
            }
        }

        return -1
    }

    override fun dispatchTouchEvent(event: MotionEvent): Boolean {
        val stylusIndex = stylusPointerIndex(event)

        if (stylusIndex >= 0) {
            when (event.actionMasked) {
                MotionEvent.ACTION_DOWN,
                MotionEvent.ACTION_POINTER_DOWN -> {
                    penMoveEvents = 0
                    penHistoricalSamples = 0
                    penMaximumHistorySize = 0
                    penDownEventTime = event.eventTime

                    penChannel?.invokeMethod(
                        "down",
                        mapOf(
                            "x" to event.getX(stylusIndex).toDouble(),
                            "y" to event.getY(stylusIndex).toDouble(),
                            "pressure" to
                                event.getPressure(stylusIndex).toDouble(),
                            "time" to event.eventTime,
                            "density" to
                                resources.displayMetrics.density.toDouble()
                        )
                    )
                }

                MotionEvent.ACTION_MOVE -> {
                    penMoveEvents += 1
                    penHistoricalSamples += event.historySize

                    if (event.historySize > penMaximumHistorySize) {
                        penMaximumHistorySize = event.historySize
                    }

                    // Send the complete MotionEvent sample history as one
                    // message. Historical samples are chronological and the
                    // current sample is appended last.
                    //
                    // Coordinates intentionally remain raw Android view
                    // coordinates for this calibration pass.
                    val samples =
                        ArrayList<Map<String, Any>>(event.historySize + 1)

                    for (historyIndex in 0 until event.historySize) {
                        samples.add(
                            mapOf(
                                "x" to event.getHistoricalX(
                                    stylusIndex,
                                    historyIndex
                                ).toDouble(),
                                "y" to event.getHistoricalY(
                                    stylusIndex,
                                    historyIndex
                                ).toDouble(),
                                "pressure" to event.getHistoricalPressure(
                                    stylusIndex,
                                    historyIndex
                                ).toDouble(),
                                "time" to event.getHistoricalEventTime(
                                    historyIndex
                                )
                            )
                        )
                    }

                    samples.add(
                        mapOf(
                            "x" to event.getX(stylusIndex).toDouble(),
                            "y" to event.getY(stylusIndex).toDouble(),
                            "pressure" to
                                event.getPressure(stylusIndex).toDouble(),
                            "time" to event.eventTime
                        )
                    )

                    penChannel?.invokeMethod(
                        "samples",
                        mapOf(
                            "samples" to samples,
                            "density" to
                                resources.displayMetrics.density.toDouble()
                        )
                    )
                }

                MotionEvent.ACTION_UP,
                MotionEvent.ACTION_POINTER_UP,
                MotionEvent.ACTION_CANCEL -> {
                    val availableDrawingSamples =
                        1 + penMoveEvents + penHistoricalSamples

                    val durationMs =
                        (event.eventTime - penDownEventTime).coerceAtLeast(0L)

                    Log.i(
                        "InkdFramesPen",
                        "strokeEnd " +
                            "moveEvents=$penMoveEvents " +
                            "historicalSamples=$penHistoricalSamples " +
                            "availableDrawingSamples=$availableDrawingSamples " +
                            "maxHistoryPerMove=$penMaximumHistorySize " +
                            "durationMs=$durationMs " +
                            "pressure=${event.getPressure(stylusIndex)} " +
                            "deviceId=${event.deviceId}"
                    )

                    penChannel?.invokeMethod(
                        if (event.actionMasked == MotionEvent.ACTION_CANCEL) {
                            "cancel"
                        } else {
                            "up"
                        },
                        mapOf(
                            "x" to event.getX(stylusIndex).toDouble(),
                            "y" to event.getY(stylusIndex).toDouble(),
                            "pressure" to
                                event.getPressure(stylusIndex).toDouble(),
                            "time" to event.eventTime,
                            "density" to
                                resources.displayMetrics.density.toDouble()
                        )
                    )
                }
            }
        }

        return super.dispatchTouchEvent(event)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        penChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            penChannelName
        )

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            channelName
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "shareVideo" -> {
                    val uriString = call.argument<String>("uri")

                    if (uriString.isNullOrBlank()) {
                        result.error(
                            "INVALID_URI",
                            "No video URI was supplied.",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    try {
                        val shareIntent = Intent(Intent.ACTION_SEND).apply {
                            type = "video/mp4"
                            putExtra(
                                Intent.EXTRA_STREAM,
                                Uri.parse(uriString)
                            )
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }

                        startActivity(
                            Intent.createChooser(
                                shareIntent,
                                "Share animation"
                            )
                        )

                        result.success(null)
                    } catch (error: Exception) {
                        result.error(
                            "SHARE_FAILED",
                            error.message,
                            null
                        )
                    }
                }

                else -> result.notImplemented()
            }
        }
    }
}
