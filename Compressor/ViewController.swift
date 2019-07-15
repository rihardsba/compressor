//
//  ViewController.swift
//  Compressor
//
//  Created by Rihards Baumanis on 15/07/2019.
//  Copyright © 2019 Rich. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import CoreServices
import AVKit
import Photos

final class ViewController: UIViewController {
    @IBOutlet weak var recordButton: UIButton!
    @IBOutlet weak var compressButton: UIButton!
    @IBOutlet weak var playButton: UIButton!
    @IBOutlet weak var resetButton: UIButton!

    @IBOutlet weak var recordedSizeLabel: UILabel!
    @IBOutlet weak var progressLabel: UILabel!
    @IBOutlet weak var compressedSizeLabel: UILabel!

    @IBOutlet weak var downloadOriginalButton: UIButton!
    @IBOutlet weak var downloadCompressedButton: UIButton!

    let compressor = Compressor()

    let recordedURL = BehaviorRelay<URL?>(value: nil)
    let hasCompressed = BehaviorRelay<Bool>(value: false)

    private let bag = DisposeBag()

    override func viewDidLoad() {
        super.viewDidLoad()
        addHandlers()
    }

    private func addHandlers() {
        recordedURL.map { $0 == nil }.bind(to: recordButton.rx.isEnabled).disposed(by: bag)

        let hasRecorded = recordedURL.map { $0 != nil }.share(replay: 1)
        hasRecorded.bind(to: compressButton.rx.isEnabled).disposed(by: bag)
        hasRecorded.bind(to: downloadOriginalButton.rx.isEnabled).disposed(by: bag)
        hasCompressed.bind(to: playButton.rx.isEnabled).disposed(by: bag)
        hasCompressed.bind(to: downloadCompressedButton.rx.isEnabled).disposed(by: bag)



        compressButton.rx.tap.withLatestFrom(recordedURL).filter { $0 != nil }.map { $0! }.subscribe(onNext: { [unowned self] url in
            self.startCompress(from: url)
        }).disposed(by: bag)

        playButton.rx.tap.subscribe(onNext: { [unowned self] in
            self.playCompressed()
        }).disposed(by: bag)

        downloadOriginalButton.rx.tap.withLatestFrom(recordedURL).filter { $0 != nil }.map { $0! }.subscribe(onNext: { [unowned self] url in
            self.saveVideo(with: url)
        }).disposed(by: bag)

        downloadCompressedButton.rx.tap.subscribe(onNext: { [unowned self] in
            self.saveVideo(with: RecordingConfig.compressedRecordingURL)
        }).disposed(by: bag)

        resetButton.rx.tap.subscribe(onNext: { [unowned self] in
            self.resetAll()
        }).disposed(by: bag)
        
        recordButton.rx.tap.subscribe(onNext: { [unowned self] in
            self.showPicker()
        }).disposed(by: bag)

        compressor.compressionProgress.map { "\($0)%" }.bind(to: progressLabel.rx.text).disposed(by: bag)
    }

    private func saveVideo(with url: URL) {
        guard PHPhotoLibrary.authorizationStatus() == .authorized else {
            PHPhotoLibrary.requestAuthorization { [weak self] (status) in
                if status == .authorized {
                    self?.saveVideo(with: url)
                } else {
                    print("just allow access, will you..")
                }
            }

            return
        }

        PHPhotoLibrary.shared().performChanges({
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
        }, completionHandler: { success, err in
            print("saving error: \(String(describing: err))")
            print("saving success: \(success)")
        })
    }

    private func resetAll() {
        recordedURL.accept(nil)
        RecordingConfig.clearCompressed()
        hasCompressed.accept(false)
        recordedSizeLabel.text = "0"
        compressedSizeLabel.text = "0"
        progressLabel.text = "-"
    }

    private func startCompress(from url: URL) {
        compressor.compressFile(urlToCompress: url, outputURL: RecordingConfig.compressedRecordingURL) { [weak self] result in
            DispatchQueue.main.async {
                switch result {
                case .failed:
                    self?.hasCompressed.accept(false)
                    self?.compressedSizeLabel.text = "Err"
                case .success:
                    self?.hasCompressed.accept(true)
                    self?.compressedSizeLabel.text = RecordingConfig.compressedRecordingURL.fileSize(for: .compressed)
                }
            }
        }
    }

    private func playCompressed() {
        let ctr = AVPlayerViewController()
        ctr.player = AVPlayer(url: RecordingConfig.compressedRecordingURL)
        present(ctr, animated: true, completion: {
            ctr.player?.play()
        })
    }

    private func showPicker() {
        resetAll()

        let ctr = UIImagePickerController()
        ctr.delegate = self
        ctr.sourceType = .camera
        ctr.videoQuality = .typeHigh
        ctr.mediaTypes = [kUTTypeMovie as String]
        ctr.cameraCaptureMode = .video
        present(ctr, animated: true)
    }
}

extension ViewController: UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let url = info[.mediaURL] as? URL {
            self.recordedSizeLabel.text = url.fileSize(for: .original)
            self.recordedURL.accept(url)
        }

        picker.dismiss(animated: true)
    }
}

private extension URL {
    enum FileType: String {
        case original
        case compressed
    }

    func fileSize(for type: FileType) -> String {
        guard let data = try? Data(contentsOf: self) else {
            return "Err"
        }

        let countBytes = ByteCountFormatter()
        countBytes.allowedUnits = [.useMB]
        countBytes.countStyle = .file
        let fileSize = countBytes.string(fromByteCount: Int64(data.count))
        return fileSize
    }
}
