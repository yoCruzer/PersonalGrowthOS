import AVFoundation
import ImageIO
import SwiftUI
import UniformTypeIdentifiers
import UIKit

enum CameraCaptureError: Error {
    case permissionDenied
    case unavailable
    case configurationFailed
    case noFileRepresentation
    case unsupportedRepresentation
}

struct CameraCaptureView: UIViewControllerRepresentable {
    let completion: (Result<MediaSource, Error>) -> Void
    let cancellation: () -> Void

    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    func makeUIViewController(context: Context) -> CameraViewController {
        CameraViewController(completion: completion, cancellation: cancellation)
    }

    func updateUIViewController(_ uiViewController: CameraViewController, context: Context) {}
}

final class CameraViewController: UIViewController, AVCapturePhotoCaptureDelegate {
    private let completion: (Result<MediaSource, Error>) -> Void
    private let cancellation: () -> Void
    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let sessionQueue = DispatchQueue(label: "com.yocruzer.PersonalGrowthOS.camera")
    private var previewLayer: AVCaptureVideoPreviewLayer?

    init(
        completion: @escaping (Result<MediaSource, Error>) -> Void,
        cancellation: @escaping () -> Void
    ) {
        self.completion = completion
        self.cancellation = cancellation
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is unavailable")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        installControls()
        authorizeAndConfigure()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sessionQueue.async { [session] in
            if session.isRunning { session.stopRunning() }
        }
    }

    private func installControls() {
        let captureButton = UIButton(type: .system)
        captureButton.setImage(UIImage(systemName: "circle.inset.filled"), for: .normal)
        captureButton.tintColor = .white
        captureButton.contentVerticalAlignment = .fill
        captureButton.contentHorizontalAlignment = .fill
        captureButton.addTarget(self, action: #selector(capturePhoto), for: .touchUpInside)
        captureButton.translatesAutoresizingMaskIntoConstraints = false

        let cancelButton = UIButton(type: .system)
        cancelButton.setTitle("Cancel", for: .normal)
        cancelButton.tintColor = .white
        cancelButton.addTarget(self, action: #selector(cancel), for: .touchUpInside)
        cancelButton.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(captureButton)
        view.addSubview(cancelButton)
        NSLayoutConstraint.activate([
            captureButton.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            captureButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            captureButton.widthAnchor.constraint(equalToConstant: 72),
            captureButton.heightAnchor.constraint(equalToConstant: 72),
            cancelButton.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor, constant: 24),
            cancelButton.centerYAnchor.constraint(equalTo: captureButton.centerYAnchor)
        ])
    }

    private func authorizeAndConfigure() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSession()
                    } else {
                        self?.completion(.failure(CameraCaptureError.permissionDenied))
                    }
                }
            }
        default:
            completion(.failure(CameraCaptureError.permissionDenied))
        }
    }

    private func configureSession() {
        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: .back
        ), let input = try? AVCaptureDeviceInput(device: device) else {
            completion(.failure(CameraCaptureError.unavailable))
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .photo
        guard session.canAddInput(input), session.canAddOutput(photoOutput) else {
            session.commitConfiguration()
            completion(.failure(CameraCaptureError.configurationFailed))
            return
        }
        session.addInput(input)
        session.addOutput(photoOutput)
        session.commitConfiguration()

        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        previewLayer.frame = view.bounds
        view.layer.insertSublayer(previewLayer, at: 0)
        self.previewLayer = previewLayer
        sessionQueue.async { [session] in session.startRunning() }
    }

    @objc private func capturePhoto() {
        let codec: AVVideoCodecType = photoOutput.availablePhotoCodecTypes.contains(.hevc) ? .hevc : .jpeg
        photoOutput.capturePhoto(
            with: AVCapturePhotoSettings(format: [AVVideoCodecKey: codec]),
            delegate: self
        )
    }

    @objc private func cancel() {
        cancellation()
    }

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        do {
            if let error { throw error }
            guard let data = photo.fileDataRepresentation() else {
                throw CameraCaptureError.noFileRepresentation
            }
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let identifier = CGImageSourceGetType(source) as String?,
                  let type = UTType(identifier),
                  let fileExtension = type.preferredFilenameExtension,
                  let mimeType = type.preferredMIMEType else {
                throw CameraCaptureError.unsupportedRepresentation
            }
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("PGOS-Camera-\(UUID().uuidString).\(fileExtension)")
            try data.write(to: url, options: .atomic)
            completion(.success(MediaSource(
                url: url,
                originalFilename: "Camera Photo.\(fileExtension)",
                contentType: mimeType
            )))
        } catch {
            completion(.failure(error))
        }
    }
}
