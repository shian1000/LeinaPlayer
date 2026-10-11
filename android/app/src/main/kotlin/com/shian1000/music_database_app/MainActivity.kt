package com.shian1000.music_database_app

import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

// AudioServiceActivity (a FlutterActivity) lets the media notification/background service and
// the app share one Flutter engine.
class MainActivity : AudioServiceActivity() {
    private var newPipe: NewPipeBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        newPipe = NewPipeBridge(flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        newPipe?.dispose()
        newPipe = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
