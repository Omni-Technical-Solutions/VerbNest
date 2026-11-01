# App Store review recording

A screen recording of VerbNest running on a real iPhone, from launch to the
last check, to attach for App Review (for example in the review notes or as a
reply in Resolution Center). Nothing in it leaves the phone: the test sends its
request to a small server inside the app's own process.

## What it shows

`apps/verbnest_app/integration_test/app_review_device_test.dart` runs only on a
physical iPhone or iPad (it skips itself on a simulator, Android and
desktops). On a fresh, throwaway workspace it:

1. launches the app,
2. creates a collection,
3. adds a request,
4. types the address with the on-screen keyboard,
5. adds a header (the check that the keyboard stays open for every letter),
6. sends the request and reads the answer (status 200, and the header it sent
   is echoed back),
7. opens the response headers,
8. goes back to the collections,
9. visits History, Environments and Settings,
10. finishes.

Each step is logged as `APP-REVIEW <time> <step>`.

## Make the recording

1. Connect the iPhone by cable, unlock it, tap Trust, and set Settings >
   Display & Brightness > Auto-Lock to Never until the recording is done.
2. Leave it on the home screen and do not touch it while the app runs.
3. Run `scripts/app_review_recording.sh` (add `WARMUP=0` when the app was
   already built on this phone; the first run on a phone needs the warm-up).

Result: `~/Downloads/VerbNest-<version>+<build>-app-review.mp4` (H.264, the
phone's own resolution, about 80 s) and a `.log` with the step times. The video
starts a few seconds before the app opens.

How it works: macOS only lists an iPhone screen as a capture device after a
CoreMediaIO switch is on, so `scripts/ios_screen_record.swift` turns it on and
writes the frames with AVAssetWriter. QuickTime Player's New Movie Recording
does the same by hand. The Mac asks once for camera access.

## Notes for App Review

- The app is a local-first API client. It needs no account and no sign-in.
- The recording was made on an iPhone XR, iOS 18.7, with a profile build of the
  same code as the submitted build.
