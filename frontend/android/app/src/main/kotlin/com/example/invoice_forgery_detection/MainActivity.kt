package com.example.invoice_forgery_detection

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import android.util.Log

class MainActivity : FlutterActivity() {
    
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // ✅ Add native crash logging
        Thread.setDefaultUncaughtExceptionHandler { thread, throwable ->
            Log.e("InvoiceGuard", "Native crash in thread $thread", throwable)
        }
        
        Log.d("InvoiceGuard", "MainActivity initialized")
    }
    
    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        try {
            Log.d("InvoiceGuard", "onCreate starting")
            super.onCreate(savedInstanceState)
            Log.d("InvoiceGuard", "onCreate completed")
        } catch (e: Exception) {
            Log.e("InvoiceGuard", "onCreate failed", e)
            // Don't rethrow - let Flutter handle
        }
    }
}

