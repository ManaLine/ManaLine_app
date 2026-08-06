package com.example.mana_line

import io.flutter.embedding.android.FlutterFragmentActivity

// FlutterFragmentActivity, NOT FlutterActivity.
//
// local_auth shows the system biometric prompt through AndroidX BiometricPrompt,
// which requires a FragmentActivity host. With a plain FlutterActivity it
// compiles and installs perfectly and then throws `no_fragment_activity` the
// first time a fingerprint is requested — a failure that only ever appears on a
// real device, never in analyze, tests or the build.
class MainActivity : FlutterFragmentActivity()
