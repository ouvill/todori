package com.taskveil.app

import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        AndroidCapsuleStore.install(this)
        super.onCreate(savedInstanceState)
    }
}
