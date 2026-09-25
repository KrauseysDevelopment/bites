// BarcodeScannerView.swift
import SwiftUI
import VisionKit
import AVFoundation

/// Camera barcode scanner built on VisionKit's DataScannerViewController.
///
/// Every device that runs iOS 18 is A12 or newer, so `isSupported` is
/// effectively always true on real hardware. It is false in the Simulator,
/// which has no camera, so the unsupported branch is what you see there.
struct BarcodeScannerView: View {
    @Environment(\.dismiss) private var dismiss

    let onScan: (String) -> Void

    @State private var cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
    @State private var scannerFailed = false
    @State private var hasScanned = false

    private var isAvailable: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    var body: some View {
        NavigationStack {
            Group {
                switch cameraAuthorization {
                case .authorized:
                    if isAvailable && !scannerFailed {
                        scanner
                    } else {
                        unavailableState
                    }
                case .notDetermined:
                    permissionPrompt
                case .denied, .restricted:
                    deniedState
                @unknown default:
                    unavailableState
                }
            }
            .navigationTitle("Scan Barcode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    // MARK: - Scanner

    private var scanner: some View {
        ZStack(alignment: .bottom) {
            DataScannerRepresentable(
                onScan: { code in
                    guard !hasScanned else { return }
                    hasScanned = true
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    onScan(code)
                    dismiss()
                },
                onFailure: { scannerFailed = true }
            )
            .ignoresSafeArea(edges: .bottom)

            VStack(spacing: 6) {
                Image(systemName: "barcode.viewfinder")
                    .font(.title2)
                Text("Point at the barcode on the package")
                    .font(.subheadline.weight(.medium))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(.black.opacity(0.55), in: Capsule())
            .padding(.bottom, 40)
        }
    }

    // MARK: - States

    private var permissionPrompt: some View {
        infoState(
            icon: "camera.fill",
            title: "Camera Access",
            message: "Bites needs the camera to read barcodes. Nothing is recorded or uploaded."
        ) {
            Button("Allow Camera") {
                AVCaptureDevice.requestAccess(for: .video) { _ in
                    DispatchQueue.main.async {
                        cameraAuthorization = AVCaptureDevice.authorizationStatus(for: .video)
                    }
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    private var deniedState: some View {
        infoState(
            icon: "camera.badge.ellipsis",
            title: "Camera Is Off",
            message: "Turn the camera on for Bites in Settings to scan barcodes."
        ) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            .tint(.orange)
        }
    }

    private var unavailableState: some View {
        infoState(
            icon: "iphone.slash",
            title: "Scanning Unavailable",
            message: "Barcode scanning needs a real device with a camera. Search for the food by name instead."
        ) {
            EmptyView()
        }
    }

    private func infoState<Action: View>(
        icon: String,
        title: String,
        message: String,
        @ViewBuilder action: () -> Action
    ) -> some View {
        VStack(spacing: 14) {
            ZStack {
                Circle().fill(Color.orange.opacity(0.1)).frame(width: 78, height: 78)
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(.orange.opacity(0.75))
            }
            Text(title).font(.title3.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 36)
            action()
                .padding(.top, 6)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - VisionKit bridge

private struct DataScannerRepresentable: UIViewControllerRepresentable {
    let onScan: (String) -> Void
    let onFailure: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            // UPC-A arrives as EAN-13 with a leading zero, so .ean13 covers it.
            recognizedDataTypes: [.barcode(symbologies: [.ean13, .ean8, .upce, .code128, .itf14, .code39])],
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        guard !context.coordinator.isRunning else { return }
        do {
            try controller.startScanning()
            context.coordinator.isRunning = true
        } catch {
            onFailure()
        }
    }

    static func dismantleUIViewController(_ controller: DataScannerViewController, coordinator: Coordinator) {
        controller.stopScanning()
        coordinator.isRunning = false
    }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        var isRunning = false

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ scanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            handle(addedItems)
        }

        func dataScanner(_ scanner: DataScannerViewController, didTapOn item: RecognizedItem) {
            handle([item])
        }

        private func handle(_ items: [RecognizedItem]) {
            for item in items {
                if case let .barcode(barcode) = item,
                   let value = barcode.payloadStringValue,
                   Barcode.isPlausible(value) {
                    onScan(value)
                    return
                }
            }
        }
    }
}
