import AVFoundation
import SwiftUI

/// BeReal-style capture: back camera full screen, front camera in a small inset, today's target on top.
/// Camera only: there is deliberately no photo-library picker anywhere in the app.
struct CaptureView: View {
    @Environment(CheckInModel.self) private var checkIn
    @Environment(SessionModel.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var camera = CameraController()
    @State private var photos: CameraController.Photos?
    @State private var working = false
    @State private var message: String?
    @State private var cameraError: String?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if let photos {
                review(photos)
            } else {
                live
            }
        }
        .overlay(alignment: .top) { header }
        .task {
            do {
                try await camera.start()
            } catch {
                cameraError = error.localizedDescription
            }
        }
        .onDisappear { camera.stop() }
        .statusBarHidden()
    }

    // MARK: - Live camera

    private var live: some View {
        ZStack(alignment: .topLeading) {
            CameraPreview(layer: camera.backPreview)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .ignoresSafeArea(edges: .bottom)
            if camera.mode == .simultaneous {
                CameraPreview(layer: camera.frontPreview)
                    .frame(width: 110, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black, lineWidth: 2))
                    .padding(.top, 96)
                    .padding(.leading, 16)
            }
            if let cameraError {
                ContentUnavailableView("Camera unavailable", systemImage: "camera.fill", description: Text(cameraError))
                    .foregroundStyle(.white)
            }
        }
        .overlay(alignment: .bottom) {
            Button {
                Task { await shoot() }
            } label: {
                Circle().strokeBorder(.white, lineWidth: 5)
                    .background(Circle().fill(.white.opacity(working ? 0.2 : 0.9)).padding(9))
                    .frame(width: 82, height: 82)
            }
            .disabled(working || cameraError != nil)
            .padding(.bottom, 36)
            .accessibilityLabel("Take photos")
        }
    }

    // MARK: - Review and submit

    private func review(_ photos: CameraController.Photos) -> some View {
        VStack(spacing: 16) {
            ZStack(alignment: .topLeading) {
                Image(uiImage: photos.back).resizable().scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                Image(uiImage: photos.front).resizable().scaledToFill()
                    .frame(width: 110, height: 150)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(.black, lineWidth: 2))
                    .padding(.top, 96).padding(.leading, 16)
            }
            if let message {
                Text(message)
                    .font(.callout).multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .padding(.horizontal)
            }
            HStack(spacing: 16) {
                Button("Retake") {
                    self.photos = nil
                    message = nil
                }
                .buttonStyle(.bordered).tint(.white)
                .disabled(working)
                Button {
                    Task { await post(photos) }
                } label: {
                    if working { ProgressView().tint(.white) } else { Text("Post check-in").bold() }
                }
                .buttonStyle(.borderedProminent).tint(.indigo)
                .disabled(working)
            }
            .controlSize(.large)
            .padding(.bottom, 24)
        }
    }

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark").font(.headline).padding(10).background(.ultraThinMaterial, in: Circle())
            }
            Spacer()
            VStack(spacing: 2) {
                Text("Find \(checkIn.challenge?.target_label ?? "today's target")").font(.headline)
                if let hint = checkIn.challenge?.hint {
                    Text(hint).font(.caption).foregroundStyle(.secondary)
                }
            }
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14).padding(.vertical, 8)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
            Spacer()
            Color.clear.frame(width: 40, height: 40)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Actions

    private func shoot() async {
        working = true
        defer { working = false }
        do {
            photos = try await camera.capture()
            message = nil
        } catch {
            cameraError = error.localizedDescription
        }
    }

    private func post(_ photos: CameraController.Photos) async {
        guard let userID = session.userID else { return }
        working = true
        let outcome = await checkIn.submit(photos, userID: userID)
        working = false
        switch outcome {
        case .verified:
            dismiss()
        case .late:
            message = "Posted, but after the deadline: it counts as late. Your friends can still see it."
            try? await Task.sleep(for: .seconds(2))
            dismiss()
        case .retake(let text), .rejected(let text), .failed(let text):
            message = text
        }
    }
}

/// Hosts an `AVCaptureVideoPreviewLayer` owned by `CameraController`.
private struct CameraPreview: UIViewRepresentable {
    let layer: AVCaptureVideoPreviewLayer

    func makeUIView(context: Context) -> PreviewHostView {
        let view = PreviewHostView()
        view.backgroundColor = .black
        view.layer.addSublayer(layer)
        view.previewLayer = layer
        return view
    }

    func updateUIView(_ uiView: PreviewHostView, context: Context) {}

    final class PreviewHostView: UIView {
        var previewLayer: CALayer?
        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}
