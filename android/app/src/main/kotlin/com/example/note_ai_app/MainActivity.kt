package com.example.note_ai_app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private val attachmentExports by lazy { AttachmentExports(applicationContext) }
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        attachmentExports.install(flutterEngine.dartExecutor.binaryMessenger)
    }
    override fun onDestroy() {
        attachmentExports.close()
        super.onDestroy()
    }
}
