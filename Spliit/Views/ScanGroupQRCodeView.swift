import AVFoundation
import SpliitAPI
import SpliitCore
import SwiftUI
import VisionKit

/// Adds a group by pointing the camera at the QR code the web app's share dialog draws.
///
/// The same act as pasting the link — a group URL is the whole invitation, since Spliit has no
/// accounts — with the camera doing the typing. What the code carries is
/// `<instance>/groups/<id>/expenses?ref=share`, and only the ID in it is used: the group is then
/// looked up on the instance this app is pointed at, which is what says whether it is really
/// there.
///
/// The lookup happens here rather than after dismissal so that a code naming a group the server
/// has never heard of can be answered while the camera is still up, with the next code one
/// movement away.
struct ScanGroupQRCodeView: View {

    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    let onAdded: (RecentGroup) -> Void

    @State private var access: CameraAccess?
    @State private var phase = Phase.scanning
    /// The last code that was read and turned out to name nothing here. Held so that a code
    /// still sitting in frame is not looked up again and again while the message about it is
    /// on screen.
    @State private var refusedPayload: String?

    private enum Phase: Equatable {
        case scanning
        case adding
        case problem(String)
    }

    enum CameraAccess {
        case allowed
        /// Asked and refused, or refused on this device's behalf by a restriction.
        case denied
        /// No scanner on this hardware — and every simulator.
        case unsupported
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottom) {
                content
                statusPanel
            }
            .navigationTitle("Scan QR code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier(AccessibilityID.ScanQRCode.cancelButton)
                }
            }
            .trackScreen(.addGroupByQRCode)
        }
        .task {
            #if DEBUG
            // A simulator has no camera, so the suite hands over a payload as if one had just
            // been read. Everything past this point — parsing it, looking the group up, adding
            // it — is the code that runs in the field. The camera is still asked about
            // afterwards rather than skipped, so a run that stays on this screen shows what a
            // device with no scanner really shows, instead of a spinner that never resolves.
            if let sample = UITestSupport.sampleQRCode() {
                found(sample)
            }
            #endif
            access = await Self.cameraAccess()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch access {
        case .allowed:
            QRCodeCamera(isScanning: phase != .adding, onFound: found)
                .ignoresSafeArea(edges: .bottom)

        case .denied:
            EmptyState(
                art: .icon("video.slash"),
                title: Text("Camera access is off"),
                description: Text("Spliit reads the QR code with the camera. You can turn access back on in Settings, or add the group by its link instead.")
            ) {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else {
                        return
                    }
                    UIApplication.shared.open(url)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier(AccessibilityID.ScanQRCode.settingsButton)
            }

        case .unsupported:
            EmptyState(
                art: .icon("qrcode.viewfinder"),
                title: Text("No camera to scan with"),
                description: Text("This device can’t read a QR code. Add the group by its link instead.")
            ) {
                EmptyView()
            }

        case nil:
            // Between asking for the camera and being answered, and — under UI test — for as
            // long as the handed-over code takes to look up.
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// What the screen is saying, over the camera when there is one.
    ///
    /// Always the bottom of the screen, whichever state it is in, so a message about the code
    /// just read never has to be looked for somewhere new.
    @ViewBuilder
    private var statusPanel: some View {
        if let status {
            status
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity)
                .background(.bar)
                .accessibilityIdentifier(AccessibilityID.ScanQRCode.status)
        }
    }

    private var status: Text? {
        switch phase {
        case .scanning:
            // Nothing to say beside an empty state that has already said it.
            access == .allowed
                ? Text("Point the camera at the QR code from a group’s share screen.")
                : nil
        case .adding:
            Text("Adding the group…")
        case .problem(let message):
            Text(message)
        }
    }

    // MARK: - Reading a code

    /// A code has been read. Anything at all can be printed on one, so the payload is only ever
    /// a string until the parser says otherwise.
    private func found(_ payload: String) {
        guard phase != .adding, payload != refusedPayload else { return }

        guard let link = GroupLink(url: payload) else {
            refuse(payload, saying: String(localized: "That QR code isn’t a Spliit group link."))
            return
        }
        // The code names its server as well as its group, which is what lets somebody hold up a
        // group on an instance this phone has never talked to. A URL always names one.
        let instanceURL = link.instanceURL ?? app.settings.defaultInstanceURL

        phase = .adding
        Task {
            do {
                let client = app.client(on: instanceURL)
                guard let group = try await client.call(Spliit.group(id: link.groupID)).group
                else {
                    refuse(
                        payload,
                        saying: String(
                            localized: "No group with that link exists on \(SettingsStore.displayName(for: instanceURL))."
                        )
                    )
                    return
                }
                onAdded(
                    RecentGroup(
                        groupId: group.id, groupName: group.name, instanceURL: instanceURL
                    )
                )
                dismiss()
            } catch {
                // Nothing wrong with the code — the server was unreachable — so this one is
                // deliberately not held against it, and holding it up again retries.
                refusedPayload = nil
                phase = .problem(error.localizedDescription)
            }
        }
    }

    /// Says what was wrong with a code and goes back to scanning, without looking at that same
    /// code again — it is very likely still in frame.
    private func refuse(_ payload: String, saying message: String) {
        refusedPayload = payload
        phase = .problem(message)
    }

    private static func cameraAccess() async -> CameraAccess {
        guard DataScannerViewController.isSupported else { return .unsupported }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .allowed
        case .notDetermined:
            // The first scan is what asks. Asking here rather than letting VisionKit ask means
            // a refusal arrives as a state this screen can explain, instead of as a camera that
            // silently never starts.
            return await AVCaptureDevice.requestAccess(for: .video) ? .allowed : .denied
        default:
            return .denied
        }
    }
}

/// The system's live barcode scanner, narrowed to QR codes.
///
/// Worth the wrapper over `AVCaptureMetadataOutput`: the viewfinder, the highlight drawn round a
/// code and the guidance when nothing is in frame all come with it, and none of it is code this
/// app would want to own.
private struct QRCodeCamera: UIViewControllerRepresentable {

    /// False while a code is being looked up, so the camera stops rather than going on offering
    /// codes nothing is ready to read.
    let isScanning: Bool
    let onFound: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let controller = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            // One code at a time, and no fast tracking: a share screen holds up a single QR and
            // holds it still.
            recognizesMultipleItems: false,
            isHighFrameRateTrackingEnabled: false,
            isPinchToZoomEnabled: true,
            isGuidanceEnabled: true,
            isHighlightingEnabled: true
        )
        controller.delegate = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {
        context.coordinator.onFound = onFound

        if isScanning, !controller.isScanning {
            try? controller.startScanning()
        } else if !isScanning, controller.isScanning {
            controller.stopScanning()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onFound: onFound) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        var onFound: (String) -> Void

        init(onFound: @escaping (String) -> Void) {
            self.onFound = onFound
        }

        func dataScanner(
            _ scanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            for case .barcode(let barcode) in addedItems {
                guard let payload = barcode.payloadStringValue else { continue }
                onFound(payload)
                return
            }
        }
    }
}
