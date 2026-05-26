import SwiftUI
import AVFoundation
import UIKit

/// SwiftUI wrapper around an AVCaptureSession that calls `onCode` once the
/// first 1D/2D code is recognized. Camera preview fills the underlying view.
///
/// Won't run in the iOS Simulator (no real camera). Use `#if targetEnvironment`
/// at the call site if you need a fake-trigger fallback for demos.
struct BarcodeScannerView: UIViewControllerRepresentable {
    let onCode: (String) -> Void
    let onError: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerVC {
        let vc = ScannerVC()
        vc.onCode = onCode
        vc.onError = onError
        return vc
    }

    func updateUIViewController(_ uiViewController: ScannerVC, context: Context) {}
}

final class ScannerVC: UIViewController {
    var onCode: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private let session = AVCaptureSession()
    private var preview: AVCaptureVideoPreviewLayer?
    private var hasReported = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        configure()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                self?.session.startRunning()
            }
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if session.isRunning {
            session.stopRunning()
        }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        preview?.frame = view.bounds
    }

    private func configure() {
        guard let device = AVCaptureDevice.default(for: .video) else {
            onError?("No camera available on this device.")
            return
        }
        guard let input = try? AVCaptureDeviceInput(device: device) else {
            onError?("Could not open the camera.")
            return
        }

        if session.canAddInput(input) {
            session.addInput(input)
        }

        let output = AVCaptureMetadataOutput()
        if session.canAddOutput(output) {
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [
                .ean8, .ean13, .upce,
                .code39, .code39Mod43, .code93, .code128,
                .interleaved2of5, .itf14,
                .qr,
            ]
        }

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.insertSublayer(preview, at: 0)
        self.preview = preview
    }
}

extension ScannerVC: AVCaptureMetadataOutputObjectsDelegate {
    func metadataOutput(_ output: AVCaptureMetadataOutput,
                        didOutput metadataObjects: [AVMetadataObject],
                        from connection: AVCaptureConnection) {
        guard !hasReported,
              let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let str = obj.stringValue, !str.isEmpty
        else { return }
        hasReported = true
        // Light haptic on capture.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Stop scanning to prevent duplicate fires.
        session.stopRunning()
        onCode?(str)
    }
}
