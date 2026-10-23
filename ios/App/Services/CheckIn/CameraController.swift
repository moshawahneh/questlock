import AVFoundation
import UIKit

/// Front + back capture. Uses `AVCaptureMultiCamSession` to take both photos at the same moment
/// (iPhone XS/XR and later); on older phones it takes the back photo, then switches to the front camera.
///
/// Concurrency: AVFoundation objects aren't `Sendable`. Every session and device call below happens on
/// the private serial `sessionQueue`, which is what makes `@unchecked Sendable` safe here: no mutable
/// state is touched from two threads at once. The preview layers are created once on the main thread
/// and only attached to the session (on `sessionQueue`), as Apple's AVMultiCamPiP sample does.
final class CameraController: NSObject, @unchecked Sendable {
    enum Mode: Equatable { case simultaneous, sequential }

    enum CameraError: LocalizedError {
        case notAllowed, unavailable, captureFailed

        var errorDescription: String? {
            switch self {
            case .notAllowed: "QuestLock needs the camera for check-ins. Allow it in Settings → QuestLock → Camera."
            case .unavailable: "The camera isn't available right now."
            case .captureFailed: "The photo didn't come out. Try again."
            }
        }
    }

    struct Photos: Sendable {
        let front: UIImage
        let back: UIImage
    }

    let mode: Mode = AVCaptureMultiCamSession.isMultiCamSupported ? .simultaneous : .sequential
    /// Full-screen preview: the back camera (in sequential mode, whichever camera is active).
    let backPreview: AVCaptureVideoPreviewLayer
    /// Small inset preview of the front camera (simultaneous mode only).
    let frontPreview: AVCaptureVideoPreviewLayer

    private let sessionQueue = DispatchQueue(label: "com.mohammadshaw.questlock.camera")
    private let session: AVCaptureSession
    private let backOutput = AVCapturePhotoOutput()
    private let frontOutput = AVCapturePhotoOutput()
    private var backInput: AVCaptureDeviceInput?
    private var frontInput: AVCaptureDeviceInput?
    private var configured = false
    private var inFlight: [Int64: PhotoDelegate] = [:]

    override init() {
        session = AVCaptureMultiCamSession.isMultiCamSupported ? AVCaptureMultiCamSession() : AVCaptureSession()
        backPreview = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        frontPreview = AVCaptureVideoPreviewLayer(sessionWithNoConnection: session)
        backPreview.videoGravity = .resizeAspectFill
        frontPreview.videoGravity = .resizeAspectFill
        super.init()
    }

    // MARK: - Lifecycle

    static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        default: false
        }
    }

    func start() async throws {
        guard await Self.requestAccess() else { throw CameraError.notAllowed }
        try await onSessionQueue {
            if !self.configured {
                try self.configure()
                self.configured = true
            }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    // MARK: - Capture

    func capture() async throws -> Photos {
        switch mode {
        case .simultaneous:
            async let back = takePhoto(from: .back)
            async let front = takePhoto(from: .front)
            return try await Photos(front: front, back: back)
        case .sequential:
            let back = try await takePhoto(from: .back)
            try await onSessionQueue { try self.switchSequentialCamera(to: .front) }
            try await Task.sleep(for: .milliseconds(600)) // let exposure settle on the new camera
            defer { sessionQueue.async { try? self.switchSequentialCamera(to: .back) } }
            let front = try await takePhoto(from: .back) // single session: one output, now fed by the front camera
            return Photos(front: front, back: back)
        }
    }

    private enum Output: Sendable { case back, front }

    /// Only Sendable values (which output, the photo's id) cross into the closures; the AVFoundation
    /// objects themselves are looked up on `sessionQueue`.
    private func takePhoto(from side: Output) async throws -> UIImage {
        try await withCheckedThrowingContinuation { continuation in
            sessionQueue.async {
                let output = side == .back ? self.backOutput : self.frontOutput
                let settings = AVCapturePhotoSettings()
                let id = settings.uniqueID
                // The delegate is kept in `inFlight` until it reports back, then released.
                let delegate = PhotoDelegate { result in
                    self.sessionQueue.async { self.inFlight[id] = nil }
                    continuation.resume(with: result)
                }
                self.inFlight[id] = delegate
                output.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }

    // MARK: - Session setup (sessionQueue only)

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        switch mode {
        case .simultaneous:
            try addCamera(position: .back, output: backOutput, preview: backPreview, mirrored: false)
            try addCamera(position: .front, output: frontOutput, preview: frontPreview, mirrored: true)
        case .sequential:
            session.sessionPreset = .photo
            guard let device = Self.camera(.back) else { throw CameraError.unavailable }
            let input = try AVCaptureDeviceInput(device: device)
            guard session.canAddInput(input), session.canAddOutput(backOutput) else { throw CameraError.unavailable }
            session.addInput(input)
            session.addOutput(backOutput)
            backInput = input
            backPreview.session = session // normal automatic connection in a single-camera session
            Self.portrait(backOutput.connection(with: .video))
            Self.portrait(backPreview.connection)
        }
    }

    /// Multi-cam wiring: inputs and outputs are added without automatic connections, then each camera
    /// port is connected explicitly to its own photo output and its own preview layer.
    private func addCamera(position: AVCaptureDevice.Position, output: AVCapturePhotoOutput,
                           preview: AVCaptureVideoPreviewLayer, mirrored: Bool) throws {
        guard let device = Self.camera(position) else { throw CameraError.unavailable }
        try Self.selectMultiCamFormat(device)
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw CameraError.unavailable }
        session.addInputWithNoConnections(input)
        session.addOutputWithNoConnections(output)
        guard let port = input.ports(for: .video, sourceDeviceType: device.deviceType, sourceDevicePosition: position).first
        else { throw CameraError.unavailable }

        let photoConnection = AVCaptureConnection(inputPorts: [port], output: output)
        guard session.canAddConnection(photoConnection) else { throw CameraError.unavailable }
        session.addConnection(photoConnection)
        Self.portrait(photoConnection)
        // Saved photos are never mirrored (text in the scene reads correctly); the selfie preview is.
        if photoConnection.isVideoMirroringSupported {
            photoConnection.automaticallyAdjustsVideoMirroring = false
            photoConnection.isVideoMirrored = false
        }

        let previewConnection = AVCaptureConnection(inputPort: port, videoPreviewLayer: preview)
        guard session.canAddConnection(previewConnection) else { throw CameraError.unavailable }
        session.addConnection(previewConnection)
        Self.portrait(previewConnection)
        if previewConnection.isVideoMirroringSupported {
            previewConnection.automaticallyAdjustsVideoMirroring = false
            previewConnection.isVideoMirrored = mirrored
        }

        if position == .back { backInput = input } else { frontInput = input }
    }

    private enum Side { case front, back }

    private func switchSequentialCamera(to side: Side) throws {
        guard let device = Self.camera(side == .front ? .front : .back) else { throw CameraError.unavailable }
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        if let current = backInput { session.removeInput(current) }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.unavailable }
        session.addInput(input)
        backInput = input
        Self.portrait(backOutput.connection(with: .video))
        Self.portrait(backPreview.connection)
        if let connection = backPreview.connection, connection.isVideoMirroringSupported {
            connection.automaticallyAdjustsVideoMirroring = false
            connection.isVideoMirrored = side == .front
        }
    }

    // MARK: - Helpers

    private static func camera(_ position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    /// Multi-cam needs formats that support it; pick the largest one up to 1920 px wide (we downscale anyway).
    private static func selectMultiCamFormat(_ device: AVCaptureDevice) throws {
        guard !device.activeFormat.isMultiCamSupported else { return }
        let candidates = device.formats.filter { $0.isMultiCamSupported }
        let best = candidates
            .filter { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width <= 1920 }
            .max { CMVideoFormatDescriptionGetDimensions($0.formatDescription).width < CMVideoFormatDescriptionGetDimensions($1.formatDescription).width }
            ?? candidates.first
        guard let best else { throw CameraError.unavailable }
        try device.lockForConfiguration()
        device.activeFormat = best
        device.unlockForConfiguration()
    }

    private static func portrait(_ connection: AVCaptureConnection?) {
        guard let connection, connection.isVideoRotationAngleSupported(90) else { return }
        connection.videoRotationAngle = 90
    }

    private func onSessionQueue(_ work: @escaping @Sendable () throws -> Void) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try work()
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}

/// Receives one photo and hands it back as a `UIImage`.
private final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let completion: @Sendable (Result<UIImage, Error>) -> Void

    init(completion: @escaping @Sendable (Result<UIImage, Error>) -> Void) {
        self.completion = completion
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error {
            completion(.failure(error))
        } else if let data = photo.fileDataRepresentation(), let image = UIImage(data: data) {
            completion(.success(image))
        } else {
            completion(.failure(CameraController.CameraError.captureFailed))
        }
    }
}
