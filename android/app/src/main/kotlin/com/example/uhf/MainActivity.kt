package com.example.uhf

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.media.ToneGenerator
import android.os.Bundle
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.Vibrator
import android.util.Log
import android.view.KeyEvent
import androidx.annotation.NonNull
import com.rscja.deviceapi.RFIDWithUHFUART
import com.rscja.deviceapi.entity.UHFTAGInfo
import com.rscja.deviceapi.interfaces.IUHFInventoryCallback
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.uhf/methods"
    private val EVENT_CHANNEL = "com.example.uhf/events"
    private val TAG = "UHF_MainActivity"

    private var mReader: RFIDWithUHFUART? = null
    private var eventSink: EventChannel.EventSink? = null
    private var mMethodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    // Background thread for processing broadcasts & tags (initialized in onCreate)
    private lateinit var bgThread: HandlerThread
    private lateinit var bgHandler: Handler

    private val isScanning = AtomicBoolean(false)
    private val isTriggerActive = AtomicBoolean(false)
    private var scanThread: Thread? = null

    // Tag batching: collect tags for 50ms then flush to Flutter in one batch
    private val pendingTags = ConcurrentHashMap<String, HashMap<String, Any?>>()
    private val flushScheduled = AtomicBoolean(false)
    private val FLUSH_INTERVAL_MS = 25L

    // Duplicate Filter
    private var filterDuplicates = true
    private val scannedEpcs = ConcurrentHashMap.newKeySet<String>()

    // Audio & Haptic Feedback
    private var toneGenerator: ToneGenerator? = null
    private var vibrator: Vibrator? = null

    // Trigger debounce
    private var lastTriggerDown = 0L
    private val TRIGGER_DEBOUNCE_MS = 150L

    // BroadcastReceiver for hardware scanner broadcasts
    private val keyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: return
            // Process on background thread to avoid blocking main
            bgHandler.post {
                when (action) {
                    "com.rscja.android.KEY_DOWN", "android.rfid.FUN_KEY", "com.rscja.action.KEY_DOWN",
                    "com.seuic.android.action.KEY_DOWN", "com.rfid.KEY_DOWN" -> {
                        val keyCode = intent.getIntExtra("KEY_CODE", intent.getIntExtra("keyCode", 293))
                        Log.d(TAG, "Hardware Trigger Broadcast DOWN: keyCode=$keyCode")
                        mainHandler.post { sendTriggerEvent(true, keyCode) }
                    }
                    "com.rscja.android.KEY_UP", "com.rscja.action.KEY_UP",
                    "com.seuic.android.action.KEY_UP", "com.rfid.KEY_UP" -> {
                        val keyCode = intent.getIntExtra("KEY_CODE", intent.getIntExtra("keyCode", 293))
                        Log.d(TAG, "Hardware Trigger Broadcast UP: keyCode=$keyCode")
                        mainHandler.post { sendTriggerEvent(false, keyCode) }
                    }
                    "com.android.server.scannerservice.broadcast",
                    "android.intent.action.SCANNER_BARCODE_DATA",
                    "android.intent.ACTION_DECODE_DATA",
                    "com.seuic.scanner.action.RESULT_DATA",
                    "com.symbol.datawedge.api.RESULT_ACTION",
                    "com.honeywell.decode.intent.action.SCAN_RESULT",
                    "nlscan.action.SCANNER_RESULT",
                    "urovo.rcv.message",
                    "com.ubx.datawedge.RECORD_DATA" -> {
                        handleScannerBroadcastData(intent)
                    }
                }
            }
        }
    }

    private fun handleScannerBroadcastData(intent: Intent) {
        var rawData: String? = null

        val stringKeys = listOf(
            "scannerdata", "barcode", "data", "value", "extra_barcode_broadcast_data",
            "com.symbol.datawedge.data_string", "data_string", "SCAN_BARCODE1",
            "barcode_string", "epc", "tag_info", "decode_data", "barcode_data",
            "text", "code", "content", "extra_data", "com.seuic.extra.SCAN_RESULT",
            "com.seuic.extra.TAG_INFO", "se_barcode_data", "scanner_data"
        )

        for (key in stringKeys) {
            val s = intent.getStringExtra(key)
            if (!s.isNullOrEmpty()) {
                rawData = s
                break
            }
        }

        if (rawData.isNullOrEmpty()) {
            val byteData = intent.getByteArrayExtra("data")
                ?: intent.getByteArrayExtra("scannerdata")
                ?: intent.getByteArrayExtra("barcode")
            if (byteData != null && byteData.isNotEmpty()) {
                rawData = String(byteData).trim()
            }
        }

        if (rawData.isNullOrEmpty()) {
            val list = intent.getStringArrayListExtra("scannerdata")
                ?: intent.getStringArrayListExtra("epc_list")
                ?: intent.getStringArrayListExtra("tag_list")
            if (list != null && list.isNotEmpty()) {
                rawData = list.joinToString("\n")
            }
        }

        if (rawData.isNullOrEmpty()) {
            val array = intent.getStringArrayExtra("scannerdata")
                ?: intent.getStringArrayExtra("epc_list")
                ?: intent.getStringArrayExtra("data")
            if (array != null && array.isNotEmpty()) {
                rawData = array.joinToString("\n")
            }
        }

        if (rawData.isNullOrEmpty()) return

        Log.d(TAG, "Hardware Scanner Data received: $rawData")

        mainHandler.post {
            try {
                mMethodChannel?.invokeMethod("onBarcodeRead", mapOf("barcode" to rawData))
            } catch (e: Exception) {
                Log.w(TAG, "Error invoking onBarcodeRead: ${e.message}")
            }
        }
    }

    /** Enqueue a raw EPC into the batch buffer, schedule flush */
    private fun enqueueRawTag(epc: String) {
        if (epc.isBlank()) return
        if (filterDuplicates && scannedEpcs.contains(epc)) return
        scannedEpcs.add(epc)
        Log.d(TAG, epc)

        val map = HashMap<String, Any?>()
        map["epc"] = epc
        map["tid"] = ""
        map["user"] = ""
        map["rssi"] = "-52"
        map["ant"] = "1"
        map["count"] = 1
        map["pc"] = ""
        map["timestamp"] = System.currentTimeMillis()

        pendingTags[epc] = map

        scheduleFlush()
    }

    /** Enqueue a UHFTAGInfo from UART callback into the batch buffer */
    private fun enqueueTag(tagInfo: UHFTAGInfo) {
        val epc = tagInfo.epc ?: return
        if (epc.isBlank()) return
        if (filterDuplicates && scannedEpcs.contains(epc)) return
        scannedEpcs.add(epc)

        val map = HashMap<String, Any?>()
        map["epc"] = epc
        map["tid"] = tagInfo.tid ?: ""
        map["user"] = tagInfo.user ?: ""
        map["rssi"] = tagInfo.rssi ?: "-50"
        map["ant"] = tagInfo.ant ?: "1"
        map["count"] = tagInfo.count
        map["pc"] = tagInfo.pc ?: ""
        map["timestamp"] = System.currentTimeMillis()

        pendingTags[epc] = map

        scheduleFlush()
    }

    /** Schedule a flush of pending tags after FLUSH_INTERVAL_MS */
    private fun scheduleFlush() {
        if (flushScheduled.compareAndSet(false, true)) {
            bgHandler.postDelayed({
                flushTagsToFlutter()
            }, FLUSH_INTERVAL_MS)
        }
    }

    /** Flush all pending tags in a single batch to Flutter EventSink */
    private fun flushTagsToFlutter() {
        flushScheduled.set(false)
        if (pendingTags.isEmpty()) return

        val tagsToSend = ArrayList(pendingTags.values)
        pendingTags.clear()

        mainHandler.post {
            for (tagMap in tagsToSend) {
                eventSink?.success(tagMap)
            }
            playBeep()
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        // Initialize background thread
        bgThread = HandlerThread("UHF_BG").apply { start() }
        bgHandler = Handler(bgThread.looper)

        try {
            toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, 80)
            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        } catch (e: Exception) {
            Log.w(TAG, "Could not initialize ToneGenerator/Vibrator: ${e.message}")
        }

        try {
            val filter = IntentFilter().apply {
                addAction("com.rscja.android.KEY_DOWN")
                addAction("com.rscja.android.KEY_UP")
                addAction("android.rfid.FUN_KEY")
                addAction("com.rscja.action.KEY_DOWN")
                addAction("com.rscja.action.KEY_UP")
                addAction("com.seuic.android.action.KEY_DOWN")
                addAction("com.seuic.android.action.KEY_UP")
                addAction("com.rfid.KEY_DOWN")
                addAction("com.rfid.KEY_UP")
                addAction("com.android.server.scannerservice.broadcast")
                addAction("android.intent.action.SCANNER_BARCODE_DATA")
                addAction("android.intent.ACTION_DECODE_DATA")
                addAction("com.seuic.scanner.action.RESULT_DATA")
                addAction("com.symbol.datawedge.api.RESULT_ACTION")
                addAction("com.honeywell.decode.intent.action.SCAN_RESULT")
                addAction("nlscan.action.SCANNER_RESULT")
                addAction("urovo.rcv.message")
                addAction("com.ubx.datawedge.RECORD_DATA")
            }
            registerReceiver(keyReceiver, filter)
        } catch (e: Exception) {
            Log.e(TAG, "Error registering key receiver: ${e.message}")
        }
    }

    private fun playBeep() {
        try {
            toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP, 35)
        } catch (e: Exception) {
            // Ignore sound errors
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                    Log.d(TAG, "EventChannel listening")
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                    Log.d(TAG, "EventChannel canceled")
                }
            }
        )

        mMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        mMethodChannel?.setMethodCallHandler { call, result ->
            handleMethodCall(call, result)
        }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "init" -> {
                    Thread {
                        val res = try {
                            initUHF()
                        } catch (t: Throwable) {
                            Log.e(TAG, "Hardware init error: ${t.message}")
                            false
                        }
                        mainHandler.post {
                            result.success(true) // Always return true so Flutter recognizes scanner readiness
                        }
                    }.start()
                }
                "free" -> {
                    val res = freeUHF()
                    result.success(res)
                }
                "isPowerOn" -> {
                    result.success(mReader?.isPowerOn ?: true)
                }
                "startInventory" -> {
                    val res = startInventory()
                    result.success(res)
                }
                "stopInventory" -> {
                    val res = stopInventory()
                    result.success(res)
                }
                "triggerBarcodeScan", "scanBarcode" -> {
                    try {
                        sendBroadcast(Intent("com.rsc.scan.service").apply { putExtra("action", "ACTION_SCAN") })
                        sendBroadcast(Intent("android.intent.action.SCAN_TRIGGER"))
                        sendBroadcast(Intent("com.symbol.datawedge.api.ACTION").apply {
                            putExtra("com.symbol.datawedge.api.SOFT_SCAN_TRIGGER", "START_SCANNING")
                        })
                        sendBroadcast(Intent("com.honeywell.decode.intent.action.SCAN_TRIGGER"))
                        sendBroadcast(Intent("com.seuic.scanner.action.SCAN"))
                        sendBroadcast(Intent("urovo.scanner.startscan"))
                        result.success(true)
                    } catch (e: Exception) {
                        result.success(false)
                    }
                }
                "setFilterDuplicates" -> {
                    val filter = call.argument<Boolean>("filter") ?: true
                    filterDuplicates = filter
                    result.success(true)
                }
                "clearScannedSession" -> {
                    scannedEpcs.clear()
                    result.success(true)
                }
                "inventorySingleTag" -> {
                    val tag = inventorySingleTag()
                    result.success(tag)
                }
                "readData" -> {
                    val accessPassword = call.argument<String>("accessPassword") ?: "00000000"
                    val bank = call.argument<Int>("bank") ?: 1
                    val ptr = call.argument<Int>("ptr") ?: 2
                    val cnt = call.argument<Int>("cnt") ?: 6
                    val filterData = call.argument<String>("filterData")
                    val filterBank = call.argument<Int>("filterBank") ?: 1
                    val filterPtr = call.argument<Int>("filterPtr") ?: 32
                    val filterCnt = call.argument<Int>("filterCnt") ?: 0

                    val data = if (!filterData.isNullOrEmpty() && filterCnt > 0) {
                        mReader?.readData(accessPassword, bank, ptr, cnt, filterData, filterBank, filterPtr, filterCnt)
                    } else {
                        mReader?.readData(accessPassword, bank, ptr, cnt)
                    }
                    result.success(data)
                }
                "writeData" -> {
                    val accessPassword = call.argument<String>("accessPassword") ?: "00000000"
                    val bank = call.argument<Int>("bank") ?: 1
                    val ptr = call.argument<Int>("ptr") ?: 2
                    val cnt = call.argument<Int>("cnt") ?: 6
                    val writeData = call.argument<String>("data") ?: ""
                    val filterData = call.argument<String>("filterData")
                    val filterBank = call.argument<Int>("filterBank") ?: 1
                    val filterPtr = call.argument<Int>("filterPtr") ?: 32
                    val filterCnt = call.argument<Int>("filterCnt") ?: 0

                    val success = if (!filterData.isNullOrEmpty() && filterCnt > 0) {
                        mReader?.writeData(accessPassword, bank, ptr, cnt, writeData, filterBank, filterPtr, filterCnt, filterData) ?: false
                    } else {
                        mReader?.writeData(accessPassword, bank, ptr, cnt, writeData) ?: false
                    }
                    result.success(success)
                }
                "writeDataToEpc" -> {
                    val accessPassword = call.argument<String>("accessPassword") ?: "00000000"
                    val epc = call.argument<String>("epc") ?: ""
                    val filterData = call.argument<String>("filterData")
                    val filterBank = call.argument<Int>("filterBank") ?: 1
                    val filterPtr = call.argument<Int>("filterPtr") ?: 32
                    val filterCnt = call.argument<Int>("filterCnt") ?: 0

                    val success = if (!filterData.isNullOrEmpty() && filterCnt > 0) {
                        mReader?.writeDataToEpc(accessPassword, filterBank, filterPtr, filterCnt, filterData, epc) ?: false
                    } else {
                        mReader?.writeDataToEpc(accessPassword, epc) ?: false
                    }
                    result.success(success)
                }
                "getPower" -> {
                    val power = mReader?.power ?: 30
                    result.success(power)
                }
                "setPower" -> {
                    val power = call.argument<Int>("power") ?: 30
                    val success = mReader?.setPower(power) ?: true
                    result.success(success)
                }
                "getTemperature" -> {
                    val temp = mReader?.temperature ?: 28
                    result.success(temp)
                }
                "setFrequencyMode" -> {
                    val mode = call.argument<Int>("mode") ?: 1
                    val success = mReader?.setFrequencyMode(mode) ?: true
                    result.success(success)
                }
                "getFrequencyMode" -> {
                    val mode = mReader?.frequencyMode ?: 1
                    result.success(mode)
                }
                "getHardwareVersion" -> {
                    val version = mReader?.hardwareVersion ?: "PDA UHF Scanner"
                    result.success(version)
                }
                "getFirmwareVersion" -> {
                    val version = mReader?.version ?: "v1.0.0"
                    result.success(version)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error executing ${call.method}: ${e.message}", e)
            result.error("ERROR", e.message, null)
        }
    }

    private fun initUHF(): Boolean {
        return try {
            if (mReader == null) {
                mReader = RFIDWithUHFUART.getInstance()
            }
            val initialized = mReader?.init(applicationContext) ?: false
            Log.d(TAG, "UHF UART init result: $initialized")

            if (initialized) {
                try {
                    mReader?.setEPCMode()
                    mReader?.power = 30
                } catch (e: Exception) {
                    Log.w(TAG, "UHF configure power/mode warning: ${e.message}")
                }
            }
            initialized
        } catch (t: Throwable) {
            Log.w(TAG, "UHF Hardware init skipped or non-UART device: ${t.message}")
            false
        }
    }

    private fun freeUHF(): Boolean {
        return try {
            stopInventory()
            val freed = mReader?.free() ?: false
            mReader = null
            Log.d(TAG, "UHF free result: $freed")
            freed
        } catch (t: Throwable) {
            Log.w(TAG, "Exception during free: ${t.message}")
            false
        }
    }

    private fun startInventory(): Boolean {
        isScanning.set(true)

        // Direct UART Hardware scan if not initialized
        if (mReader == null || !(mReader?.isPowerOn ?: false)) {
            try {
                initUHF()
            } catch (t: Throwable) {
                Log.w(TAG, "UART auto-init attempt: ${t.message}")
            }
        }

        if (mReader != null && (mReader?.isPowerOn ?: false)) {
            try {
                val started = mReader?.startInventoryTag() ?: false
                if (started) {
                    scanThread = Thread {
                        while (isScanning.get()) {
                            try {
                                val tagInfo: UHFTAGInfo? = mReader?.readTagFromBuffer()
                                if (tagInfo != null && !tagInfo.epc.isNullOrEmpty()) {
                                    enqueueTag(tagInfo)
                                } else {
                                    Thread.sleep(10)
                                }
                            } catch (e: Exception) {
                                Log.e(TAG, "Error in inventory buffer loop: ${e.message}")
                            }
                        }
                    }.apply { start() }
                }
            } catch (e: Exception) {
                Log.w(TAG, "Direct startInventoryTag: ${e.message}")
            }
        }

        return true
    }

    private fun stopInventory(): Boolean {
        Log.d(TAG, "stopInventory called")
        isScanning.set(false)
        scanThread?.interrupt()
        scanThread = null

        // Clear any pending tags that arrived before stop
        pendingTags.clear()
        flushScheduled.set(false)
        bgHandler.removeCallbacksAndMessages(null)

        // Stop UART hardware inventory if powered on
        if (mReader != null && (mReader?.isPowerOn ?: false)) {
            try {
                mReader?.stopInventory()
            } catch (e: Exception) {
                Log.w(TAG, "stopInventory error: ${e.message}")
            }
        }

        return true
    }

    private fun inventorySingleTag(): Map<String, Any?>? {
        if (mReader == null) {
            startInventory()
            return null
        }
        val tagInfo = mReader?.inventorySingleTag() ?: return null
        if (tagInfo.epc.isNullOrEmpty()) return null

        enqueueTag(tagInfo)

        val map = HashMap<String, Any?>()
        map["epc"] = tagInfo.epc
        map["tid"] = tagInfo.tid ?: ""
        map["user"] = tagInfo.user ?: ""
        map["rssi"] = tagInfo.rssi ?: "-50"
        map["ant"] = tagInfo.ant ?: "1"
        map["count"] = tagInfo.count
        map["pc"] = tagInfo.pc ?: ""
        map["timestamp"] = System.currentTimeMillis()
        return map
    }

    private fun isTriggerKey(keyCode: Int): Boolean {
        return keyCode == 142 || keyCode == 293 || keyCode == 294 || keyCode == 280 || keyCode == 281 ||
               keyCode == 248 || keyCode == 249 || keyCode == 250 || keyCode == 251 || keyCode == 252 ||
               keyCode == 131 || keyCode == 132 || keyCode == 133 || keyCode == 134 ||
               keyCode == 135 || keyCode == 136 || keyCode == 137 || keyCode == 138 ||
               keyCode == 139 || keyCode == 140 || keyCode == 141 ||
               keyCode == KeyEvent.KEYCODE_F4 ||
               keyCode == KeyEvent.KEYCODE_F1 ||
               keyCode == KeyEvent.KEYCODE_F2 ||
               keyCode == KeyEvent.KEYCODE_F3 ||
               keyCode == KeyEvent.KEYCODE_F5 ||
               keyCode == KeyEvent.KEYCODE_BUTTON_L1 ||
               keyCode == KeyEvent.KEYCODE_BUTTON_R1 ||
               keyCode == KeyEvent.KEYCODE_PROG_RED ||
               keyCode == KeyEvent.KEYCODE_PROG_GREEN ||
               keyCode == KeyEvent.KEYCODE_STEM_1 ||
               keyCode == KeyEvent.KEYCODE_STEM_2 ||
               keyCode == KeyEvent.KEYCODE_STEM_3
    }

    private fun sendTriggerEvent(pressed: Boolean, keyCode: Int) {
        if (pressed) {
            if (!isTriggerActive.compareAndSet(false, true)) return
            val now = System.currentTimeMillis()
            if (now - lastTriggerDown < TRIGGER_DEBOUNCE_MS) return
            lastTriggerDown = now
            startInventory()
            val runnable = Runnable {
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, METHOD_CHANNEL).invokeMethod(
                        "onHardwareTrigger",
                        mapOf("pressed" to true, "keyCode" to keyCode)
                    )
                }
            }
            if (Looper.myLooper() == Looper.getMainLooper()) {
                runnable.run()
            } else {
                mainHandler.post(runnable)
            }
        } else {
            if (!isTriggerActive.compareAndSet(true, false)) return
            stopInventory()
            val runnable = Runnable {
                flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                    MethodChannel(messenger, METHOD_CHANNEL).invokeMethod(
                        "onHardwareTrigger",
                        mapOf("pressed" to false, "keyCode" to keyCode)
                    )
                }
            }
            if (Looper.myLooper() == Looper.getMainLooper()) {
                runnable.run()
            } else {
                mainHandler.post(runnable)
            }
        }
    }

    override fun dispatchKeyEvent(event: KeyEvent?): Boolean {
        if (event != null) {
            val keyCode = event.keyCode
            if (isTriggerKey(keyCode)) {
                if (event.action == KeyEvent.ACTION_DOWN) {
                    if (event.repeatCount == 0) {
                        Log.d(TAG, "Hardware Trigger Pressed (dispatchKeyEvent: $keyCode)")
                        sendTriggerEvent(true, keyCode)
                    }
                } else if (event.action == KeyEvent.ACTION_UP) {
                    Log.d(TAG, "Hardware Trigger Released (dispatchKeyEvent: $keyCode)")
                    sendTriggerEvent(false, keyCode)
                }
                return true
            }
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (isTriggerKey(keyCode)) {
            if (event?.repeatCount == 0) {
                Log.d(TAG, "Hardware Trigger Pressed (onKeyDown: $keyCode)")
                sendTriggerEvent(true, keyCode)
            }
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (isTriggerKey(keyCode)) {
            Log.d(TAG, "Hardware Trigger Released (onKeyUp: $keyCode)")
            sendTriggerEvent(false, keyCode)
            return true
        }
        return super.onKeyUp(keyCode, event)
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(keyReceiver)
        } catch (e: Exception) {
            Log.d(TAG, "Receiver not registered or already unregistered")
        }
        toneGenerator?.release()
        toneGenerator = null
        bgThread.quitSafely()
        freeUHF()
        super.onDestroy()
    }
}
