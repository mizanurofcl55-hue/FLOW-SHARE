package app.flowshare.flowshare

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder

class TransferService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null
    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = "flowshare.transfers"
        if (Build.VERSION.SDK_INT >= 26) manager.createNotificationChannel(NotificationChannel(channel,"FlowShare transfers",NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this,0,Intent(this,MainActivity::class.java),PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26) Notification.Builder(this,channel) else Notification.Builder(this)
        val bengali = intent?.getStringExtra("language") == "bn"
        val notification = builder.setSmallIcon(android.R.drawable.stat_sys_upload).setContentTitle("FlowShare")
            .setContentText(if (bengali) "স্থানীয় ট্রান্সফার চলছে। দেখতে বা বাতিল করতে খুলুন।" else "Local transfer active. Open to view or cancel.")
            .setContentIntent(open).setOngoing(true).setOnlyAlertOnce(true).build()
        startForeground(17,notification)
        return START_NOT_STICKY
    }
}
