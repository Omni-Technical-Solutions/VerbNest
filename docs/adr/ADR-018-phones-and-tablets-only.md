# ADR-018: Phones and tablets only on Android and iOS

Status: accepted (v0.59.3)

## Context
The mobile builds are designed and tested for phone and tablet screens (device matrix, goldens, store screenshots). Other device types that can run or list an Android or iOS app (TV, watch, car, XR, Chromebook, iPhone/iPad apps on Mac or Vision) are untested and have no layout work.

## Decision
- iOS: `TARGETED_DEVICE_FAMILY = 1,2` (iPhone, iPad); `SUPPORTS_MACCATALYST`, `SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD` and `SUPPORTS_XR_DESIGNED_FOR_IPHONE_IPAD` are `NO`. macOS users get the native macOS app.
- Android: `uses-feature android.hardware.touchscreen` is required; no leanback, watch, automotive or XR declarations or launcher entries.
- Store consoles (Owner): no extra form factors in Play; Chromebooks excluded in the device catalog; Mac and Vision availability of the iPhone/iPad app off in App Store Connect.

## Consequences
Foldables and large tablets stay supported (they are phones and tablets). Chromebooks cannot be excluded from the manifest alone, so that step is a console setting. Supporting another device type later needs layout work, tests and store setup first.
