import SwiftUI
#if os(iOS)
import AVFoundation
import UIKit

/// QR Scanner bottom sheet based on Figma design
@available(iOS 16.0, *)
struct QRScannerSheet: View {
    @Binding var isConnected: Bool
    let onResult: (Result<URL, Error>) -> Void
    
    @State private var isScanning = false
    @State private var hasCameraPermission = false
    @State private var showingPermissionAlert = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(spacing: 0) {
            // Drag Indicator
            RoundedRectangle(cornerRadius: 2)
                .fill(Colors.ink700.opacity(0.2))
                .frame(width: 36, height: 4)
                .padding(.top, Spacing.xs)
                .padding(.bottom, Spacing.md)
            
            // Header
            HStack {
                Text("Scan QR Code")
                    .font(Typography.font(.navTitle))
                    .foregroundColor(Colors.textPrimary(for: colorScheme))
                
                Spacer()
                
                Button(action: { dismiss() }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 24))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                }
            }
            .padding(.horizontal, Spacing.Layout.screenPaddingHorizontal)
            .padding(.bottom, Spacing.lg)
            
            // Camera Preview or Permission View
            if hasCameraPermission {
                QRScannerView(onCodeScanned: { code in
                    if let url = URL(string: code) {
                        onResult(.success(url))
                    } else {
                        onResult(.failure(ScanError.invalidQRCode))
                    }
                })
                .aspectRatio(1, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: CornerRadius.card))
                .padding(.horizontal, Spacing.Layout.screenPaddingHorizontal)
            } else {
                // Permission Request View
                VStack(spacing: Spacing.lg) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundColor(Colors.accentPrimaryEnd)
                    
                    Text("Camera Permission Required")
                        .font(Typography.font(.heading1))
                        .foregroundColor(Colors.textPrimary(for: colorScheme))
                    
                    Text("Allow camera access to scan QR codes from your desktop server.")
                        .font(Typography.font(.body))
                        .foregroundColor(Colors.textSecondary(for: colorScheme))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 280)
                    
                    PrimaryButton("Enable Camera") {
                        requestCameraPermission()
                    }
                    .frame(maxWidth: 200)
                }
                .padding(Spacing.xl)
            }
            
            // Instructions
            Text("Point your camera at the QR code displayed on your desktop")
                .font(Typography.font(.caption))
                .foregroundColor(Colors.textSecondary(for: colorScheme))
                .multilineTextAlignment(.center)
                .padding(.horizontal, Spacing.Layout.screenPaddingHorizontal)
                .padding(.vertical, Spacing.lg)
            
            Spacer()
        }
        .frame(maxHeight: UIScreen.main.bounds.height * 0.55)
        .background(Colors.bgBase(for: colorScheme))
        .clipShape(
            RoundedRectangle(cornerRadius: CornerRadius.sheet)
                .path(in: CGRect(x: 0, y: 20, width: UIScreen.main.bounds.width, height: UIScreen.main.bounds.height))
        )
        .onAppear {
            checkCameraPermission()
        }
        .alert("Camera Access", isPresented: $showingPermissionAlert) {
            Button("Settings") {
                if let settingsURL = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(settingsURL)
                }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Please enable camera access in Settings to scan QR codes.")
        }
    }
    
    private func checkCameraPermission() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasCameraPermission = true
        case .notDetermined:
            requestCameraPermission()
        case .denied, .restricted:
            hasCameraPermission = false
        @unknown default:
            hasCameraPermission = false
        }
    }
    
    private func requestCameraPermission() {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                hasCameraPermission = granted
                if !granted {
                    showingPermissionAlert = true
                }
            }
        }
    }
    
    enum ScanError: LocalizedError {
        case invalidQRCode
        
        var errorDescription: String? {
            switch self {
            case .invalidQRCode:
                return "Invalid QR code format"
            }
        }
    }
}

// MARK: - QR Scanner View (Camera)
@available(iOS 16.0, *)
struct QRScannerView: UIViewControllerRepresentable {
    let onCodeScanned: (String) -> Void
    
    func makeUIViewController(context: Context) -> QRScannerViewController {
        let controller = QRScannerViewController()
        controller.onCodeScanned = onCodeScanned
        return controller
    }
    
    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var onCodeScanned: ((String) -> Void)?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = UIColor.black
        captureSession = AVCaptureSession()
        
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput
        
        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }
        
        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            return
        }
        
        let metadataOutput = AVCaptureMetadataOutput()
        
        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)
            
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            return
        }
        
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        if captureSession.isRunning {
            captureSession.stopRunning()
        }
    }
    
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        captureSession.stopRunning()
        
        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            onCodeScanned?(stringValue)
        }
    }
    
    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
}
#endif
