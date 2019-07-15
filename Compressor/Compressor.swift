//
//  Compressor.swift
//  Compressor
//
//  Created by Rihards Baumanis on 15/07/2019.
//  Copyright © 2019 Rich. All rights reserved.
//

import UIKit
import RxSwift
import RxCocoa
import AVFoundation

final class Compressor {
    private let bag = DisposeBag()

    let videoCompressionProgress = BehaviorRelay<Double>(value: 0)
    let audioCompressionProgress = BehaviorRelay<Double>(value: 0)

    let compressionProgress = BehaviorRelay<Double>(value: 0)

    var assetWriter: AVAssetWriter?
    var assetReader: AVAssetReader?

    private static let videoQueue = "videoQueue"
    private static let audioQueue = "audioQueue"

    init() {
        addHandlers()
    }

    private func addHandlers() {
        Observable
            .combineLatest(videoCompressionProgress, audioCompressionProgress)
            .map { ($0 + $1) / 2 }
            .bind(to: compressionProgress)
            .disposed(by: bag)
    }

    enum CompressionResult {
        case failed
        case success
    }

    private func getVideoSettings(for track: AVAssetTrack) -> [String: Any] {
        let bitrate = min(track.estimatedDataRate, 3500000)

        let horizontalSize = CGSize(width: 1280, height: 720)
        let verticalSize = CGSize(width: 720, height: 1280)
        let squareSize = CGSize(width: 720, height: 720)

        let newSize: CGSize
        let expectedLargest: CGFloat = 1280
        let size = track.naturalSize.applying(track.preferredTransform)

        if expectedLargest < (max(abs(size.width), abs(size.height))) {
            if size.height > size.width {
                newSize = size.width < 0 ? horizontalSize : verticalSize
            } else if size.width > size.height {
                newSize = size.height < 0 ? verticalSize : horizontalSize
            } else {
                newSize = squareSize
            }
        } else {
            newSize = track.naturalSize
        }

        return [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: bitrate],
            AVVideoHeightKey: newSize.height,
            AVVideoWidthKey: newSize.width
        ]
    }

    private var getVideoReaderSettings: [String: Any] {
        return [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB ]
    }

    private func setupReader(for asset: AVAsset) -> AVAssetReader? {
        assetReader = try? AVAssetReader(asset: asset)
        return assetReader
    }

    private func setupWriter(to url: URL, with videoInput: AVAssetWriterInput, and audioInput: AVAssetWriterInput) -> AVAssetWriter? {
        assetWriter = try? AVAssetWriter(outputURL: url, fileType: AVFileType.mov)
        assetWriter?.shouldOptimizeForNetworkUse = true
        assetWriter?.add(videoInput)
        assetWriter?.add(audioInput)
        return assetWriter
    }

    func compressFile(urlToCompress: URL, outputURL: URL, completion: @escaping ((CompressionResult) -> Void)) {
        var audioFinished = false
        var videoFinished = false

        let asset = AVAsset(url: urlToCompress)
        let duration = asset.duration
        let durationTime = CMTimeGetSeconds(duration)

        guard
            let reader = setupReader(for: asset),
            let videoTrack = asset.tracks(withMediaType: .video).first,
            let audioTrack = asset.tracks(withMediaType: .audio).first else {
                completion(.failed)
                return
        }

        let assetReaderVideoOutput = AVAssetReaderTrackOutput(track: videoTrack, outputSettings: getVideoReaderSettings)
        let assetReaderAudioOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: nil)
        assetReaderVideoOutput.alwaysCopiesSampleData = false
        assetReaderAudioOutput.alwaysCopiesSampleData = false

        for output in [assetReaderVideoOutput, assetReaderAudioOutput] {
            guard reader.canAdd(output) else {
                completion(.failed)
                return
            }
            reader.add(output)
        }

        let audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: nil)
        let videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: getVideoSettings(for: videoTrack))
        videoInput.transform = videoTrack.preferredTransform

        let videoInputQueue = DispatchQueue(label: Compressor.videoQueue)
        let audioInputQueue = DispatchQueue(label: Compressor.audioQueue)

        guard let writer = setupWriter(to: outputURL, with: videoInput, and: audioInput) else {
            completion(.failed)
            return
        }

        writer.startWriting()
        reader.startReading()
        writer.startSession(atSourceTime: CMTime.zero)

        let closeWriter: () -> Void = { [weak self] in
            guard audioFinished && videoFinished else { return }

            self?.assetWriter?.finishWriting(completionHandler: { [weak self] in
                self?.assetReader?.cancelReading()
                self?.assetReader = nil
                self?.assetWriter = nil
                completion(.success)
            })
        }

        audioInput.requestMediaDataWhenReady(on: audioInputQueue) { [weak self] in
            while audioInput.isReadyForMoreMediaData {
                guard let sample = assetReaderAudioOutput.copyNextSampleBuffer() else {
                    guard self?.assetWriter != nil, self?.assetWriter?.inputs.contains(audioInput) == true else { return }
                    audioInput.markAsFinished()
                    audioFinished = true
                    closeWriter()
                    break
                }

                let timeStamp = CMSampleBufferGetPresentationTimeStamp(sample)
                let timeSecond = CMTimeGetSeconds(timeStamp)
                let per = timeSecond / durationTime
                self?.audioCompressionProgress.accept(per)
                debugPrint("audio progress --- \(per)")
                audioInput.append(sample)
            }
        }

        videoInput.requestMediaDataWhenReady(on: videoInputQueue) { [weak self] in
            while videoInput.isReadyForMoreMediaData {
                guard let sample = assetReaderVideoOutput.copyNextSampleBuffer() else {
                    guard self?.assetWriter != nil, self?.assetWriter?.inputs.contains(audioInput) == true else { return }
                    videoInput.markAsFinished()
                    videoFinished = true
                    closeWriter()
                    break
                }

                let timeStamp = CMSampleBufferGetPresentationTimeStamp(sample)
                let timeSecond = CMTimeGetSeconds(timeStamp)
                let per = timeSecond / durationTime
                self?.videoCompressionProgress.accept(per)
                debugPrint("video progress --- \(per)")

                videoInput.append(sample)
            }
        }
    }
}
