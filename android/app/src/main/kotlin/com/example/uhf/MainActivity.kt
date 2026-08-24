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
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.reflect.InvocationHandler
import java.lang.reflect.Method
import java.lang.reflect.Proxy
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val METHOD_CHANNEL = "com.example.uhf/methods"
    private val EVENT_CHANNEL = "com.example.uhf/events"
    private val TAG = "UHF_MainActivity"

    // SEUIC UHF via reflection (system framework class)
    private var mUhfService: Any? = null
    private var mUhfServiceClass: Class<*>? = null
    private var mEpcClass: Class<*>? = null
    private var mListenerProxy: Any? = null

    private var eventSink: EventChannel.EventSink? = null
    private var mMethodChannel: MethodChannel? = null
    private val mainHandler = Handler(Looper.getMainLooper())

    private lateinit var bgThread: HandlerThread
    private lateinit var bgHandler: Handler

    private val isScanning = AtomicBoolean(false)
    private val isTriggerActive = AtomicBoolean(false)

    private var filterDuplicates = false
    private val scannedEpcs = ConcurrentHashMap.newKeySet<String>()

    private var toneGenerator: ToneGenerator? = null
    private var vibrator: Vibrator? = null
    private var lastBeepTime = 0L
    private val BEEP_MIN_INTERVAL_MS = 60L

    private var currentScanMode = "auto"

    private var lastTriggerDown = 0L
    private val TRIGGER_DEBOUNCE_MS = 80L

    // Create IReadTagsListener proxy via java.lang.reflect.Proxy
    private fun createReadTagsListenerProxy(): Any? {
        return try {
            val listenerClass = Class.forName("com.seuic.uhf.IReadTagsListener")
            Proxy.newProxyInstance(
                listenerClass.classLoader,
                arrayOf(listenerClass),
                InvocationHandler { _, method, args ->
                    if (method.name == "tagsRead" && args != null && args.isNotEmpty()) {
                        val tags = args[0] as? List<*>
                        if (tags != null && tags.isNotEmpty()) {
                            bgHandler.post {
                                processTagList(tags)
                            }
                        }
                    }
                    null
                }
            )
        } catch (e: Throwable) {
            Log.e(TAG, "Failed to create IReadTagsListener proxy: ${e.message}")
            null
        }
    }

    private fun processTagList(tags: List<*>) {
        val tagMaps = ArrayList<HashMap<String, Any?>>()
        val now = System.currentTimeMillis()

        for (item in tags) {
            if (item == null) continue
            try {
                val epcStr = callMethod(item, "getId") as? String ?: continue
                val subEpcs = epcStr.split(Regex("[\\r\\n;,]+"))
                    .map { it.trim().replace(" ", "").uppercase() }
                    .filter { it.isNotBlank() && it.length >= 4 }

                val rssi = try { item.javaClass.getField("rssi").getInt(item) } catch (_: Throwable) { -50 }
                val count = try { item.javaClass.getField("count").getInt(item) } catch (_: Throwable) { 1 }

                for (epc in subEpcs) {
                    if (filterDuplicates && scannedEpcs.contains(epc)) continue
                    scannedEpcs.add(epc)

                    val map = HashMap<String, Any?>()
                    map["epc"] = epc
                    map["tid"] = ""
                    map["user"] = ""
                    map["rssi"] = rssi.toString()
                    map["ant"] = "1"
                    map["count"] = count
                    map["pc"] = ""
                    map["timestamp"] = now
                    tagMaps.add(map)
                }
            } catch (e: Throwable) {
                Log.w(TAG, "Error processing tag: ${e.message}")
            }
        }

        if (tagMaps.isNotEmpty()) {
            mainHandler.post {
                eventSink?.success(tagMaps)
            }
            playBeepThrottled()
        }
    }

    private fun playBeepThrottled() {
        val now = System.currentTimeMillis()
        if (now - lastBeepTime >= BEEP_MIN_INTERVAL_MS) {
            lastBeepTime = now
            bgHandler.post {
                try {
                    toneGenerator?.startTone(ToneGenerator.TONE_PROP_BEEP, 20)
                } catch (_: Exception) {}
            }
        }
    }

    private fun processRawBroadcastData(rawText: String) {
        val lines = rawText.split(Regex("[\\r\\n;,]+"))
            .map { it.trim().replace(" ", "").uppercase() }
            .filter { it.isNotBlank() && it.length >= 4 }

        if (lines.isEmpty()) return

        val tagMaps = ArrayList<HashMap<String, Any?>>()
        val now = System.currentTimeMillis()

        for (epc in lines) {
            if (filterDuplicates && scannedEpcs.contains(epc)) continue
            scannedEpcs.add(epc)

            val map = HashMap<String, Any?>()
            map["epc"] = epc
            map["tid"] = ""
            map["user"] = ""
            map["rssi"] = "-45"
            map["ant"] = "1"
            map["count"] = 1
            map["pc"] = ""
            map["timestamp"] = now
            tagMaps.add(map)
        }

        if (tagMaps.isNotEmpty()) {
            mainHandler.post {
                eventSink?.success(tagMaps)
            }
            playBeepThrottled()
        }
    }

    private val keyReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val action = intent?.action ?: return
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
                    "com.ubx.datawedge.RECORD_DATA",
                    "com.seuic.uhf.action.TAG_READ",
                    "com.seuic.uhf.action.INVENTORY_TAG",
                    "com.seuic.uhf.action.ACTION_TAG",
                    "com.seuic.uhftool.action.TAG",
                    "com.seuic.uhf.action.TAG" -> {
                        handleBarcodeBroadcastData(intent)
                    }
                }
            }
        }
    }

    private fun handleBarcodeBroadcastData(intent: Intent) {
        var rawData: String? = null
        val stringKeys = listOf(
            "scannerdata", "barcode", "data", "value", "extra_barcode_broadcast_data",
            "com.symbol.datawedge.data_string", "data_string", "SCAN_BARCODE1",
            "barcode_string", "decode_data", "barcode_data",
            "text", "code", "content", "com.seuic.extra.SCAN_RESULT",
            "se_barcode_data", "scanner_data", "epc", "tag_epc", "tag"
        )
        for (key in stringKeys) {
            val s = intent.getStringExtra(key)
            if (!s.isNullOrEmpty()) { rawData = s.trim(); break }
        }
        if (rawData.isNullOrEmpty()) {
            val byteData = intent.getByteArrayExtra("data")
                ?: intent.getByteArrayExtra("scannerdata")
                ?: intent.getByteArrayExtra("barcode")
            if (byteData != null && byteData.isNotEmpty()) {
                rawData = String(byteData).trim()
            }
        }
        if (rawData.isNullOrEmpty()) return

        // Nếu app đang ở chế độ RFID (mặc định): Tách từng dòng và đưa vào danh sách thẻ RFID riêng biệt!
        if (currentScanMode.lowercase() != "barcode") {
            processRawBroadcastData(rawData)
            return
        }

        Log.d(TAG, "Barcode Broadcast Data: $rawData")
        mainHandler.post {
            try {
                mMethodChannel?.invokeMethod("onBarcodeRead", mapOf("barcode" to rawData))
            } catch (e: Exception) {
                Log.w(TAG, "Error invoking onBarcodeRead: ${e.message}")
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        bgThread = HandlerThread("UHF_BG").apply { start() }
        bgHandler = Handler(bgThread.looper)

        try {
            toneGenerator = ToneGenerator(AudioManager.STREAM_MUSIC, 85)
            vibrator = getSystemService(Context.VIBRATOR_SERVICE) as? Vibrator
        } catch (e: Exception) {
            Log.w(TAG, "Could not initialize ToneGenerator/Vibrator: ${e.message}")
        }

        try {
            val filter = IntentFilter().apply {
                addAction("com.rscja.android.KEY_DOWN"); addAction("com.rscja.android.KEY_UP")
                addAction("android.rfid.FUN_KEY")
                addAction("com.rscja.action.KEY_DOWN"); addAction("com.rscja.action.KEY_UP")
                addAction("com.seuic.android.action.KEY_DOWN"); addAction("com.seuic.android.action.KEY_UP")
                addAction("com.rfid.KEY_DOWN"); addAction("com.rfid.KEY_UP")
                addAction("com.android.server.scannerservice.broadcast")
                addAction("android.intent.action.SCANNER_BARCODE_DATA")
                addAction("android.intent.ACTION_DECODE_DATA")
                addAction("com.seuic.scanner.action.RESULT_DATA")
                addAction("com.symbol.datawedge.api.RESULT_ACTION")
                addAction("com.honeywell.decode.intent.action.SCAN_RESULT")
                addAction("nlscan.action.SCANNER_RESULT")
                addAction("urovo.rcv.message")
                addAction("com.ubx.datawedge.RECORD_DATA")
                addAction("com.seuic.uhf.action.TAG_READ")
                addAction("com.seuic.uhf.action.INVENTORY_TAG")
                addAction("com.seuic.uhf.action.ACTION_TAG")
                addAction("com.seuic.uhftool.action.TAG")
                addAction("com.seuic.uhf.action.TAG")
            }
            registerReceiver(keyReceiver, filter)
        } catch (e: Exception) {
            Log.e(TAG, "Error registering key receiver: ${e.message}")
        }
    }

    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        EventChannel(flutterEngine.dartExecutor.binaryMessenger, EVENT_CHANNEL).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events; Log.d(TAG, "EventChannel listening")
                }
                override fun onCancel(arguments: Any?) {
                    eventSink = null; Log.d(TAG, "EventChannel canceled")
                }
            }
        )
        mMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
        mMethodChannel?.setMethodCallHandler { call, result -> handleMethodCall(call, result) }
    }

    private fun handleMethodCall(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "init" -> {
                    bgHandler.post {
                        val res = try { initUHF() } catch (t: Throwable) {
                            Log.e(TAG, "Hardware init error: ${t.message}"); false
                        }
                        mainHandler.post { result.success(res) }
                    }
                }
                "free" -> {
                    bgHandler.post {
                        val res = freeUHF()
                        mainHandler.post { result.success(res) }
                    }
                }
                "isPowerOn" -> result.success(isUhfOpen())
                "startInventory" -> {
                    bgHandler.post {
                        val res = startInventory()
                        mainHandler.post { result.success(res) }
                    }
                }
                "stopInventory" -> {
                    bgHandler.post {
                        val res = stopInventory()
                        mainHandler.post { result.success(res) }
                    }
                }
                "setScanMode" -> {
                    currentScanMode = call.argument<String>("mode") ?: "auto"
                    Log.d(TAG, "Scan mode: $currentScanMode")
                    if (currentScanMode.lowercase() == "barcode") {
                        enableBarcodeScannerHardware()
                    } else {
                        disableBarcodeScannerHardware()
                    }
                    result.success(true)
                }
                "getScanMode" -> result.success(currentScanMode)
                "triggerBarcodeScan", "scanBarcode" -> { triggerBarcodeBroadcast(); result.success(true) }
                "setFilterDuplicates" -> {
                    filterDuplicates = call.argument<Boolean>("filter") ?: false; result.success(true)
                }
                "clearScannedSession" -> { scannedEpcs.clear(); result.success(true) }
                "inventorySingleTag" -> {
                    bgHandler.post {
                        val tag = inventorySingleTag()
                        mainHandler.post { result.success(tag) }
                    }
                }
                "readData" -> {
                    val bank = call.argument<Int>("bank") ?: 1
                    val ptr = call.argument<Int>("ptr") ?: 2
                    val cnt = call.argument<Int>("cnt") ?: 6
                    val pwd = call.argument<String>("accessPassword") ?: "00000000"
                    val filter = call.argument<String>("filterData")
                    bgHandler.post {
                        val data = readTagData(pwd, bank, ptr, cnt, filter)
                        mainHandler.post { result.success(data) }
                    }
                }
                "writeData" -> {
                    val bank = call.argument<Int>("bank") ?: 1
                    val ptr = call.argument<Int>("ptr") ?: 2
                    val cnt = call.argument<Int>("cnt") ?: 6
                    val pwd = call.argument<String>("accessPassword") ?: "00000000"
                    val writeData = call.argument<String>("data") ?: ""
                    val filter = call.argument<String>("filterData")
                    bgHandler.post {
                        val success = writeTagData(pwd, bank, ptr, cnt, writeData, filter)
                        mainHandler.post { result.success(success) }
                    }
                }
                "writeDataToEpc" -> {
                    val pwd = call.argument<String>("accessPassword") ?: "00000000"
                    val epc = call.argument<String>("epc") ?: ""
                    bgHandler.post {
                        val success = writeTagData(pwd, 1, 2, epc.length / 4, epc, null)
                        mainHandler.post { result.success(success) }
                    }
                }
                "getPower" -> {
                    val p = callMethod(mUhfService, "getPower") as? Int ?: 30
                    result.success(p)
                }
                "setPower" -> {
                    val power = call.argument<Int>("power") ?: 30
                    bgHandler.post {
                        val ok = callMethod(mUhfService, "setPower", arrayOf(Int::class.javaPrimitiveType!!), arrayOf(power)) as? Boolean ?: false
                        mainHandler.post { result.success(ok) }
                    }
                }
                "getTemperature" -> {
                    val t = callMethod(mUhfService, "getTemperature") as? String
                    result.success(t?.toIntOrNull() ?: 28)
                }
                "setFrequencyMode" -> result.success(true)
                "getFrequencyMode" -> result.success(1)
                "getHardwareVersion" -> result.success("SEUIC CRUISE2 UHF")
                "getFirmwareVersion" -> {
                    val v = callMethod(mUhfService, "getFirmwareVersion") as? String ?: "Unknown"
                    result.success(v)
                }
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            Log.e(TAG, "Error executing ${call.method}: ${e.message}", e)
            result.error("ERROR", e.message, null)
        }
    }

    // ──── Reflection helpers ────

    private fun callMethod(obj: Any?, methodName: String): Any? {
        if (obj == null) return null
        return try {
            val m = obj.javaClass.getMethod(methodName)
            m.invoke(obj)
        } catch (e: Throwable) {
            Log.w(TAG, "callMethod($methodName) failed: ${e.message}")
            null
        }
    }

    private fun callMethod(obj: Any?, methodName: String, paramTypes: Array<Class<*>>, args: Array<Any?>): Any? {
        if (obj == null) return null
        return try {
            val m = obj.javaClass.getMethod(methodName, *paramTypes)
            m.invoke(obj, *args)
        } catch (e: Throwable) {
            Log.w(TAG, "callMethod($methodName) failed: ${e.message}")
            null
        }
    }

    // ──── UHF Operations via Reflection ────

    private fun isUhfOpen(): Boolean {
        return try {
            callMethod(mUhfService, "isOpen") as? Boolean ?: false
        } catch (_: Throwable) { false }
    }

    private fun initUHF(): Boolean {
        return try {
            if (mUhfService != null && isUhfOpen()) {
                Log.d(TAG, "UHF already initialized")
                return true
            }

            Log.d(TAG, "Initializing SEUIC UHFService via reflection...")

            val clazz = Class.forName("com.seuic.uhf.UHFService")
            mUhfServiceClass = clazz
            mEpcClass = Class.forName("com.seuic.uhf.EPC")

            var service: Any? = null
            try {
                val m = clazz.getMethod("getInstance", Context::class.java)
                service = m.invoke(null, applicationContext)
                Log.d(TAG, "getInstance(Context) returned: ${service != null}")
            } catch (e: Throwable) {
                Log.d(TAG, "getInstance(Context) failed: ${e.message}")
            }
            if (service == null) {
                try {
                    val m = clazz.getMethod("getInstance")
                    service = m.invoke(null)
                    Log.d(TAG, "getInstance() returned: ${service != null}")
                } catch (e: Throwable) {
                    Log.d(TAG, "getInstance() failed: ${e.message}")
                }
            }

            if (service == null) {
                Log.e(TAG, "UHFService.getInstance() returned null")
                return false
            }

            mUhfService = service

            val opened = callMethod(service, "open") as? Boolean ?: false
            Log.d(TAG, "UHFService.open() = $opened")

            if (!opened) {
                Log.e(TAG, "UHFService.open() failed")
                return false
            }

            // Register tag read listener
            mListenerProxy = createReadTagsListenerProxy()
            if (mListenerProxy != null) {
                val listenerClass = Class.forName("com.seuic.uhf.IReadTagsListener")
                val regMethod = service.javaClass.getMethod("registerReadTags", listenerClass)
                regMethod.invoke(service, mListenerProxy)
                Log.d(TAG, "Registered IReadTagsListener")
            }

            // Log all available methods on SEUIC UHFService to discover performance tuning APIs
            for (m in clazz.methods) {
                if (m.declaringClass == Object::class.java) continue
                val params = m.parameterTypes.joinToString(",") { it.simpleName }
                Log.d(TAG, "UHFService Method: ${m.name}($params): ${m.returnType.simpleName}")
            }

            // Set Max Output Power (Try 33 dBm first, fallback to 30 dBm)
            try {
                val ok33 = callMethod(service, "setPower", arrayOf(Int::class.javaPrimitiveType!!), arrayOf(33)) as? Boolean ?: false
                if (!ok33) {
                    callMethod(service, "setPower", arrayOf(Int::class.javaPrimitiveType!!), arrayOf(30))
                }
                Log.d(TAG, "SEUIC RF Power set (33 attempt: $ok33, current=${callMethod(service, "getPower")})")
            } catch (_: Throwable) {}

            // Try setting high-speed inventory parameters if supported by SEUIC
            try {
                // Session S0 (0) or S1 (1) - S0 scans at maximum rate without tag silencing
                clazz.getMethod("setGen2Session", Int::class.javaPrimitiveType).invoke(service, 0)
                Log.d(TAG, "Configured setGen2Session(0)")
            } catch (_: Throwable) {}

            try {
                clazz.getMethod("setSession", Int::class.javaPrimitiveType).invoke(service, 0)
                Log.d(TAG, "Configured setSession(0)")
            } catch (_: Throwable) {}

            try {
                clazz.getMethod("setQ", Int::class.javaPrimitiveType).invoke(service, 4)
                Log.d(TAG, "Configured setQ(4)")
            } catch (_: Throwable) {}

            try {
                clazz.getMethod("setGen2Q", Int::class.javaPrimitiveType).invoke(service, 4)
                Log.d(TAG, "Configured setGen2Q(4)")
            } catch (_: Throwable) {}

            try {
                clazz.getMethod("setGen2Target", Int::class.javaPrimitiveType).invoke(service, 0)
                Log.d(TAG, "Configured setGen2Target(0)")
            } catch (_: Throwable) {}

            try {
                clazz.getMethod("setTarget", Int::class.javaPrimitiveType).invoke(service, 0)
                Log.d(TAG, "Configured setTarget(0)")
            } catch (_: Throwable) {}

            Log.d(TAG, "SEUIC UHF initialized successfully with max RF power and optimized parameters")
            true
        } catch (t: Throwable) {
            Log.e(TAG, "UHF init error: ${t.message}", t)
            false
        }
    }

    private fun freeUHF(): Boolean {
        return try {
            stopInventory()
            if (mListenerProxy != null && mUhfService != null) {
                try {
                    val listenerClass = Class.forName("com.seuic.uhf.IReadTagsListener")
                    val m = mUhfService!!.javaClass.getMethod("unregisterReadTags", listenerClass)
                    m.invoke(mUhfService, mListenerProxy)
                } catch (_: Throwable) {}
            }
            callMethod(mUhfService, "close")
            mUhfService = null
            mListenerProxy = null
            Log.d(TAG, "UHF free completed")
            true
        } catch (t: Throwable) {
            Log.w(TAG, "Exception during free: ${t.message}")
            false
        }
    }

    private fun startInventory(): Boolean {
        if (isScanning.get()) return true

        if (mUhfService == null || !isUhfOpen()) {
            try { initUHF() } catch (_: Throwable) {}
        }
        if (mUhfService == null || !isUhfOpen()) {
            Log.w(TAG, "UHF not available")
            return false
        }

        return try {
            val started = callMethod(mUhfService, "inventoryStart") as? Boolean ?: false
            Log.d(TAG, "inventoryStart() = $started")
            if (started) isScanning.set(true)
            started
        } catch (e: Exception) {
            Log.e(TAG, "inventoryStart error: ${e.message}")
            false
        }
    }

    private fun stopInventory(): Boolean {
        Log.d(TAG, "stopInventory called")
        isScanning.set(false)
        return try {
            callMethod(mUhfService, "inventoryStop") as? Boolean ?: true
        } catch (_: Throwable) { true }
    }

    private fun inventorySingleTag(): Map<String, Any?>? {
        if (mUhfService == null || !isUhfOpen()) initUHF()
        if (mUhfService == null) return null

        return try {
            val epcClass = mEpcClass ?: return null
            val epc = epcClass.getDeclaredConstructor().newInstance()
            val m = mUhfService!!.javaClass.getMethod("inventoryOnce", epcClass, Int::class.javaPrimitiveType!!)
            val found = m.invoke(mUhfService, epc, 300) as? Boolean ?: false
            if (found) {
                val epcStr = (callMethod(epc, "getId") as? String)?.uppercase()?.trim() ?: return null
                if (epcStr.isBlank()) return null
                val rssi = try { epcClass.getField("rssi").getInt(epc) } catch (_: Throwable) { -50 }

                hashMapOf<String, Any?>(
                    "epc" to epcStr, "tid" to "", "user" to "",
                    "rssi" to rssi.toString(), "ant" to "1", "count" to 1,
                    "pc" to "", "timestamp" to System.currentTimeMillis()
                )
            } else null
        } catch (e: Exception) {
            Log.e(TAG, "inventorySingleTag error: ${e.message}")
            null
        }
    }

    private fun readTagData(accessPassword: String, bank: Int, ptr: Int, cnt: Int, filterEpc: String?): String? {
        if (mUhfService == null || !isUhfOpen()) return null
        return try {
            val pwd = hexToBytes(accessPassword)
            val filter = if (!filterEpc.isNullOrEmpty()) hexToBytes(filterEpc) else ByteArray(0)
            val dataOut = ByteArray(cnt * 2)
            val m = mUhfService!!.javaClass.getMethod("readTagData",
                ByteArray::class.java, ByteArray::class.java,
                Int::class.javaPrimitiveType!!, Int::class.javaPrimitiveType!!,
                Int::class.javaPrimitiveType!!, ByteArray::class.java)
            val ok = m.invoke(mUhfService, pwd, filter, bank, ptr, cnt, dataOut) as? Boolean ?: false
            if (ok) bytesToHex(dataOut) else null
        } catch (e: Exception) {
            Log.e(TAG, "readTagData error: ${e.message}"); null
        }
    }

    private fun writeTagData(accessPassword: String, bank: Int, ptr: Int, cnt: Int, data: String, filterEpc: String?): Boolean {
        if (mUhfService == null || !isUhfOpen()) return false
        return try {
            val pwd = hexToBytes(accessPassword)
            val filter = if (!filterEpc.isNullOrEmpty()) hexToBytes(filterEpc) else ByteArray(0)
            val writeBytes = hexToBytes(data)
            val m = mUhfService!!.javaClass.getMethod("writeTagData",
                ByteArray::class.java, ByteArray::class.java,
                Int::class.javaPrimitiveType!!, Int::class.javaPrimitiveType!!,
                Int::class.javaPrimitiveType!!, ByteArray::class.java)
            m.invoke(mUhfService, pwd, filter, bank, ptr, cnt, writeBytes) as? Boolean ?: false
        } catch (e: Exception) {
            Log.e(TAG, "writeTagData error: ${e.message}"); false
        }
    }

    private fun hexToBytes(hex: String): ByteArray {
        val h = hex.replace(" ", "")
        return ByteArray(h.length / 2) { ((Character.digit(h[it * 2], 16) shl 4) + Character.digit(h[it * 2 + 1], 16)).toByte() }
    }

    private fun bytesToHex(bytes: ByteArray): String = bytes.joinToString("") { "%02X".format(it) }

    // ──── Trigger Handling ────

    private fun isTriggerKey(keyCode: Int): Boolean {
        return keyCode == 142 || keyCode == 293 || keyCode == 294 || keyCode == 280 || keyCode == 281 ||
               keyCode == 248 || keyCode == 249 || keyCode == 250 || keyCode == 251 || keyCode == 252 ||
               keyCode == 131 || keyCode == 132 || keyCode == 133 || keyCode == 134 ||
               keyCode == 135 || keyCode == 136 || keyCode == 137 || keyCode == 138 ||
               keyCode == 139 || keyCode == 140 || keyCode == 141 ||
               keyCode == KeyEvent.KEYCODE_F4 || keyCode == KeyEvent.KEYCODE_F1 ||
               keyCode == KeyEvent.KEYCODE_F2 || keyCode == KeyEvent.KEYCODE_F3 ||
               keyCode == KeyEvent.KEYCODE_F5 ||
               keyCode == KeyEvent.KEYCODE_BUTTON_L1 || keyCode == KeyEvent.KEYCODE_BUTTON_R1 ||
               keyCode == KeyEvent.KEYCODE_PROG_RED || keyCode == KeyEvent.KEYCODE_PROG_GREEN ||
               keyCode == KeyEvent.KEYCODE_STEM_1 || keyCode == KeyEvent.KEYCODE_STEM_2 ||
               keyCode == KeyEvent.KEYCODE_STEM_3
    }

    private fun disableBarcodeScannerHardware() {
        try {
            sendBroadcast(Intent("com.android.server.scannerservice.broadcast").apply {
                putExtra("action", "SCANNER_STOP")
                putExtra("action_stop", "STOP_SCAN")
                putExtra("scanner_enabled", false)
                putExtra("key_enabled", false)
            })
            sendBroadcast(Intent("com.seuic.scanner.action.STOP_SCAN"))
            sendBroadcast(Intent("com.seuic.scanner.action.SCANNER_ENABLED").apply {
                putExtra("enabled", false)
            })
            sendBroadcast(Intent("com.seuic.scanner.action.KEY_CONTROL").apply {
                putExtra("enabled", false)
            })
            sendBroadcast(Intent("com.android.server.scannerservice.broadcast").apply {
                putExtra("action", "ACTION_STOP_SCAN")
            })
            sendBroadcast(Intent("com.android.server.scannerservice.broadcast").apply {
                putExtra("action", "KEY_CONTROL_DISABLED")
            })
            try {
                val scannerClass = Class.forName("com.seuic.scanner.ScannerFactory")
                val getScanner = scannerClass.getMethod("getScanner", Context::class.java)
                val scanner = getScanner.invoke(null, this)
                if (scanner != null) {
                    val closeMethod = scanner.javaClass.getMethod("close")
                    closeMethod.invoke(scanner)
                }
            } catch (_: Throwable) {}
            Log.d(TAG, "Barcode Scanner Hardware disabled for RFID mode")
        } catch (e: Exception) {
            Log.w(TAG, "disableBarcodeScannerHardware error: ${e.message}")
        }
    }

    private fun enableBarcodeScannerHardware() {
        try {
            sendBroadcast(Intent("com.android.server.scannerservice.broadcast").apply {
                putExtra("action", "SCANNER_START")
                putExtra("scanner_enabled", true)
                putExtra("key_enabled", true)
            })
            sendBroadcast(Intent("com.seuic.scanner.action.SCANNER_ENABLED").apply {
                putExtra("enabled", true)
            })
            sendBroadcast(Intent("com.seuic.scanner.action.KEY_CONTROL").apply {
                putExtra("enabled", true)
            })
            try {
                val scannerClass = Class.forName("com.seuic.scanner.ScannerFactory")
                val getScanner = scannerClass.getMethod("getScanner", Context::class.java)
                val scanner = getScanner.invoke(null, this)
                if (scanner != null) {
                    val openMethod = scanner.javaClass.getMethod("open")
                    openMethod.invoke(scanner)
                }
            } catch (_: Throwable) {}
            Log.d(TAG, "Barcode Scanner Hardware enabled for Barcode mode")
        } catch (e: Exception) {
            Log.w(TAG, "enableBarcodeScannerHardware error: ${e.message}")
        }
    }

    private fun triggerBarcodeBroadcast() {
        try {
            enableBarcodeScannerHardware()
            sendBroadcast(Intent("com.android.server.scannerservice.broadcast").apply { putExtra("action", "ACTION_SCAN") })
            sendBroadcast(Intent("android.intent.action.SCAN_TRIGGER"))
            sendBroadcast(Intent("com.seuic.scanner.action.SCAN"))
        } catch (e: Exception) {
            Log.w(TAG, "triggerBarcodeBroadcast error: ${e.message}")
        }
    }

    private fun sendTriggerEvent(pressed: Boolean, keyCode: Int) {
        if (pressed) {
            if (!isTriggerActive.compareAndSet(false, true)) return
            val now = System.currentTimeMillis()
            if (now - lastTriggerDown < TRIGGER_DEBOUNCE_MS) return
            lastTriggerDown = now

            val mode = currentScanMode.lowercase()
            bgHandler.post {
                if (mode == "barcode") {
                    triggerBarcodeBroadcast()
                } else {
                    // Chế độ RFID (mặc định): Tuyệt đối chỉ quét RFID, không bắn barcode
                    startInventory()
                }
            }

            notifyFlutterTrigger(true, keyCode, mode)
        } else {
            if (!isTriggerActive.compareAndSet(true, false)) return
            val mode = currentScanMode.lowercase()
            bgHandler.post {
                if (mode != "barcode") stopInventory()
            }
            notifyFlutterTrigger(false, keyCode, mode)
        }
    }

    private fun notifyFlutterTrigger(pressed: Boolean, keyCode: Int, mode: String) {
        val runnable = Runnable {
            flutterEngine?.dartExecutor?.binaryMessenger?.let { messenger ->
                MethodChannel(messenger, METHOD_CHANNEL).invokeMethod(
                    "onHardwareTrigger",
                    mapOf("pressed" to pressed, "keyCode" to keyCode, "mode" to mode)
                )
            }
        }
        if (Looper.myLooper() == Looper.getMainLooper()) runnable.run() else mainHandler.post(runnable)
    }

    override fun dispatchKeyEvent(event: KeyEvent?): Boolean {
        if (event != null && isTriggerKey(event.keyCode)) {
            if (event.action == KeyEvent.ACTION_DOWN && event.repeatCount == 0) {
                sendTriggerEvent(true, event.keyCode)
            } else if (event.action == KeyEvent.ACTION_UP) {
                sendTriggerEvent(false, event.keyCode)
            }
            return true
        }
        return super.dispatchKeyEvent(event)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        if (isTriggerKey(keyCode) && event?.repeatCount == 0) {
            sendTriggerEvent(true, keyCode); return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onKeyUp(keyCode: Int, event: KeyEvent?): Boolean {
        if (isTriggerKey(keyCode)) {
            sendTriggerEvent(false, keyCode); return true
        }
        return super.onKeyUp(keyCode, event)
    }

    override fun onResume() {
        super.onResume()
        if (currentScanMode.lowercase() != "barcode") {
            disableBarcodeScannerHardware()
        }
    }

    override fun onDestroy() {
        try { unregisterReceiver(keyReceiver) } catch (_: Exception) {}
        toneGenerator?.release(); toneGenerator = null
        bgThread.quitSafely()
        freeUHF()
        super.onDestroy()
    }
}
