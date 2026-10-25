package app.flowshare.flowshare

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.StatFs
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private lateinit var channel: MethodChannel
    private var hotspot: WifiManager.LocalOnlyHotspotReservation? = null
    private var pendingHotspot: MethodChannel.Result? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "app.flowshare/platform")
        channel.setMethodCallHandler { call, result ->
            try {
                when (call.method) {
                    "freeBytes" -> result.success(StatFs(call.argument<String>("path") ?: filesDir.path).availableBytes)
                    "wifiSettings" -> { startActivity(Intent(Settings.ACTION_WIFI_SETTINGS)); result.success(null) }
                    "createHotspot" -> {
                        if (Build.VERSION.SDK_INT < 26) result.error("hotspotUnavailable", "Requires Android 8 or later", null)
                        else if (pendingHotspot != null || hotspot != null) result.error("hotspotUnavailable", "Hotspot already active or pending", null)
                        else {
                            pendingHotspot = result
                            val permission = if (Build.VERSION.SDK_INT >= 33) Manifest.permission.NEARBY_WIFI_DEVICES else Manifest.permission.ACCESS_FINE_LOCATION
                            if (checkSelfPermission(permission) != PackageManager.PERMISSION_GRANTED) requestPermissions(arrayOf(permission), 51)
                            else startHotspot()
                        }
                    }
                    "stopHotspot" -> { hotspot?.close(); hotspot = null; result.success(null) }
                    "transferActive" -> {
                        if (call.argument<Boolean>("active") == true) {
                            if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 52)
                            val intent = Intent(this, TransferService::class.java).putExtra("language", call.argument<String>("language"))
                            if (Build.VERSION.SDK_INT >= 26) startForegroundService(intent) else startService(intent)
                        } else stopService(Intent(this, TransferService::class.java))
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            } catch (error: Exception) { result.error("operationFailed", error.javaClass.simpleName, null) }
        }
    }
    @Suppress("DEPRECATION")
    private fun startHotspot() {
        if (Build.VERSION.SDK_INT < 26) return
        try {
            val wifi = applicationContext.getSystemService(WIFI_SERVICE) as WifiManager
            wifi.startLocalOnlyHotspot(object : WifiManager.LocalOnlyHotspotCallback() {
                override fun onStarted(reservation: WifiManager.LocalOnlyHotspotReservation) {
                    hotspot = reservation
                    val ssid: String?
                    val password: String?
                    if (Build.VERSION.SDK_INT >= 30) {
                        ssid = reservation.softApConfiguration.ssid
                        password = reservation.softApConfiguration.passphrase
                    } else {
                        ssid = reservation.wifiConfiguration?.SSID
                        password = reservation.wifiConfiguration?.preSharedKey
                    }
                    pendingHotspot?.success(mapOf("ssid" to ssid, "password" to password)); pendingHotspot = null
                }
                override fun onStopped() { hotspot = null; channel.invokeMethod("hotspotStopped", null) }
                override fun onFailed(reason: Int) { pendingHotspot?.error("hotspotUnavailable", "Android could not start hotspot: $reason", null); pendingHotspot = null }
            }, Handler(Looper.getMainLooper()))
        } catch (error: Exception) { pendingHotspot?.error("hotspotUnavailable", error.javaClass.simpleName, null); pendingHotspot = null }
    }
    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 51) {
            if (grantResults.isNotEmpty() && grantResults[0] == PackageManager.PERMISSION_GRANTED) startHotspot()
            else { pendingHotspot?.error("permissionDenied", "Hotspot permission denied", null); pendingHotspot = null }
        }
    }
    override fun onDestroy() { hotspot?.close(); stopService(Intent(this, TransferService::class.java)); super.onDestroy() }
}
