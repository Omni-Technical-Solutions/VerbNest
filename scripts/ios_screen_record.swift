// Records the screen of a USB-connected iPhone or iPad to a .mov, the way
// QuickTime Player's "New Movie Recording" does (macOS only).
//
//   swiftc -O scripts/ios_screen_record.swift -o /tmp/ios_screen_record
//   /tmp/ios_screen_record out.mov            # stop with Ctrl-C or SIGTERM
//   /tmp/ios_screen_record out.mov -- cmd ...  # record while cmd runs, exit with its status
//   /tmp/ios_screen_record --list
//
// The device must be unlocked and trusted. The first run asks for camera
// access (a screen-capture device counts as a camera to macOS).
import AVFoundation
import CoreMediaIO
import Foundation

// iOS screens only show up as capture devices after this switch is on.
var prop = CMIOObjectPropertyAddress(
  mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyAllowScreenCaptureDevices),
  mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
  mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))
var allow: UInt32 = 1
CMIOObjectSetPropertyData(
  CMIOObjectID(kCMIOObjectSystemObject), &prop, 0, nil, UInt32(MemoryLayout<UInt32>.size), &allow)

func devices() -> [AVCaptureDevice] {
  AVCaptureDevice.DiscoverySession(
    deviceTypes: [.external], mediaType: .muxed, position: .unspecified
  ).devices
}

// The device list fills in a moment after the switch.
var found = devices()
// (A device that was captured a moment ago can take several seconds to
// show up again.)
for _ in 0..<160 where found.isEmpty {
  RunLoop.current.run(until: Date().addingTimeInterval(0.25))
  found = devices()
}

if CommandLine.arguments.dropFirst().first == "--list" {
  for d in found { print("\(d.localizedName)\t\(d.uniqueID)") }
  exit(found.isEmpty ? 1 : 0)
}

guard let out = CommandLine.arguments.dropFirst().first else {
  FileHandle.standardError.write(Data("usage: ios_screen_record out.mov [-- command ...] | --list\n".utf8))
  exit(2)
}
guard let device = found.first else {
  FileHandle.standardError.write(
    Data("no iPhone or iPad screen found: connect it, unlock it and tap Trust\n".utf8))
  exit(1)
}

let session = AVCaptureSession()
let videoOut = AVCaptureVideoDataOutput()
do {
  let input = try AVCaptureDeviceInput(device: device)
  guard session.canAddInput(input), session.canAddOutput(videoOut) else {
    FileHandle.standardError.write(Data("cannot capture \(device.localizedName)\n".utf8))
    exit(1)
  }
  session.addInput(input)
  session.addOutput(videoOut)
} catch {
  FileHandle.standardError.write(Data("camera access refused or failed: \(error)\n".utf8))
  exit(1)
}

/// Writes every frame the device sends to an H.264 .mov.
final class Writer: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
  let url: URL
  var writer: AVAssetWriter?
  var input: AVAssetWriterInput?
  var frames = 0
  init(_ url: URL) { self.url = url }

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard CMSampleBufferDataIsReady(sampleBuffer), let image = CMSampleBufferGetImageBuffer(sampleBuffer)
    else { return }
    if writer == nil {
      let w = CVPixelBufferGetWidth(image)
      let h = CVPixelBufferGetHeight(image)
      guard let writer = try? AVAssetWriter(outputURL: url, fileType: .mov) else { return }
      let input = AVAssetWriterInput(
        mediaType: .video,
        outputSettings: [
          AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: w, AVVideoHeightKey: h,
          AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 6_000_000],
        ])
      input.expectsMediaDataInRealTime = true
      writer.add(input)
      writer.startWriting()
      writer.startSession(atSourceTime: CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
      self.writer = writer
      self.input = input
      // Local wall-clock time, the same form Dart prints, to line the video up
      // with a log.
      let f = DateFormatter()
      f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS"
      print("first frame \(w)x\(h) at \(f.string(from: Date()))")
      fflush(stdout)
    }
    if let input, input.isReadyForMoreMediaData, input.append(sampleBuffer) { frames += 1 }
  }

  func finish(status: Int32 = 0) {
    guard let writer, let input else {
      FileHandle.standardError.write(Data("no frames arrived: unlock the device\n".utf8))
      exit(1)
    }
    input.markAsFinished()
    writer.finishWriting {
      print("saved \(self.url.path) (\(self.frames) frames)")
      exit(writer.status == .completed ? status : 1)
    }
  }
}

let url = URL(fileURLWithPath: out)
try? FileManager.default.removeItem(at: url)
let sink = Writer(url)
videoOut.setSampleBufferDelegate(sink, queue: DispatchQueue(label: "frames"))
session.startRunning()
print("recording \(device.localizedName) to \(url.path)")
fflush(stdout)

func stop(_ sig: Int32) {
  session.stopRunning()
  sink.finish()
}
signal(SIGINT, stop)
signal(SIGTERM, stop)

// With `-- command`, record for as long as the command runs: a few seconds of
// the home screen first, then the command, then a few seconds after it.
let args = Array(CommandLine.arguments.dropFirst())
if let dash = args.firstIndex(of: "--"), dash + 1 < args.count {
  for _ in 0..<80 where sink.frames == 0 {
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
  }
  guard sink.frames > 0 else {
    FileHandle.standardError.write(Data("no frames arrived: unlock the device\n".utf8))
    exit(1)
  }
  RunLoop.current.run(until: Date().addingTimeInterval(3))
  let child = Process()
  child.executableURL = URL(fileURLWithPath: "/usr/bin/env")
  child.arguments = Array(args[(dash + 1)...])
  do { try child.run() } catch {
    FileHandle.standardError.write(Data("cannot start the command: \(error)\n".utf8))
    exit(1)
  }
  // The run loop must keep turning for frames to arrive while the command runs.
  while child.isRunning { RunLoop.current.run(until: Date().addingTimeInterval(0.25)) }
  RunLoop.current.run(until: Date().addingTimeInterval(3))
  session.stopRunning()
  sink.finish(status: child.terminationStatus)
}
RunLoop.main.run()
