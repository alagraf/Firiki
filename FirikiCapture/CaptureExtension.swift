//
//  CaptureExtension.swift
//  FirikiCapture
//
//  Scan a page into a library from the Lock Screen (5.7).
//

import ExtensionKit
import Foundation
import LockedCameraCapture
import SwiftUI

/// Firiki's camera for a locked iPhone or iPad (5.7), opened by the "Scan into Library" control
/// (`ScanIntoLibraryIntent`). The system runs it without the network and without the app group; what it keeps goes
/// in the session's folder, which is in the app's own data container, and the app takes it from there
/// (`LockedCaptureImport`).
@main
struct FirikiCaptureExtension: LockedCameraCaptureExtension {
    var body: some LockedCameraCaptureExtensionScene {
        LockedCameraCaptureUIScene { session in
            CaptureScreen(session: session)
        }
    }
}
