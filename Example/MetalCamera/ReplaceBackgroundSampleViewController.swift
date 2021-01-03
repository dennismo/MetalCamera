//
//  SegmentationSampleViewController.swift
//  MetalCamera_Example
//
//  Created by Dennis on 2020/06/11.
//  Copyright © 2020 CocoaPods. All rights reserved.
//

import UIKit
import MetalCamera
import CoreML
import Vision
import AVKit
import AVFoundation


class ReplaceBackgroundSampleViewController: BaseCameraViewController {
    @IBOutlet weak var recordButton: UIButton!
//    var video: MetalVideoLoader?
    var recorder: MetalVideoWriter?
    var recordingURL: URL {
        let documentsDir = try? FileManager.default.url(for:. documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let fileURL = URL(string: "recording.mov", relativeTo: documentsDir)!
        return fileURL
    }
    
    let modelURL = URL(string: "https://ml-assets.apple.com/coreml/models/Image/ImageSegmentation/DeepLabV3/DeepLabV3Int8LUT.mlmodel")!

    override func viewDidLoad() {
        setupAudioSession()
        super.viewDidLoad()
        loadCoreML()
//        setupBackgroundImage()
    }
    
//    override func viewWillAppear(_ animated: Bool) {
//        super.viewWillAppear(animated)
//    }
}
// MARK: Setup Functions
extension ReplaceBackgroundSampleViewController {
    func loadCoreML() {
        do {
            let loader = try CoreMLLoader(url: modelURL)
            loader.load { [weak self](model, error) in
                if let model = model {
                    self?.setupModelHandler(model)
                } else if let error = error {
                    debugPrint(error)
                }
            }
        } catch {
            debugPrint(error)
        }
    }
    
    func setupAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setActive(false)
            try audioSession.setCategory(.playAndRecord, options: [.mixWithOthers, .allowBluetoothA2DP, .defaultToSpeaker])
            try audioSession.setMode(.videoChat)
            try audioSession.setActive(true)
        } catch {
            debugPrint(error)
        }
    }

    func setupModelHandler(_ model: MLModel) {
        let imageCompositor = BackgroundImageCompositor(baseTextureKey: camera.sourceKey)
        guard let testImage = UIImage(named: "sampleImage") else {
            fatalError("Check image resource")
        }
        let compositeFrame = CGRect(x: 0, y: 0, width: 620, height: 620)
        imageCompositor.addCompositeImage(testImage)
        imageCompositor.sourceFrame = compositeFrame
        
        let imageCompositor2 = ImageCompositor(baseTextureKey: camera.sourceKey)
        imageCompositor2.addCompositeImage(testImage)
        imageCompositor2.sourceFrame = compositeFrame
        do {
            let modelHandler = try CoreMLBackgroundReplacementHandler(model)
            camera.removeTarget(preview)
//            camera-->modelHandler-->preview
//            camera-->imageCompositor-->preview
            camera-->modelHandler-->imageCompositor-->preview
//            camera-->preview
        } catch{
            debugPrint(error)
        }
    }
    
    
    // MARK: tap record
    @IBAction func didTapRecordButton(_ sender: Any) {
        if let recorder = recorder {
            preview.removeTarget(recorder)

            camera.removeAudioTarget(recorder)

            recorder.finishRecording { [weak self] in
                guard let self = self else { return }

                DispatchQueue.main.async {
                    let player = AVPlayer(url: self.recordingURL)

                    let vc = AVPlayerViewController()
                    vc.player = player

                    self.present(vc, animated: true) { vc.player?.play() }

                    self.recorder = nil

                    self.recordButton.setTitle("Start", for: .normal)
                }
            }
        } else {
            do {
                if FileManager.default.fileExists(atPath: recordingURL.path) {
                    try FileManager.default.removeItem(at: recordingURL)
                }

                recorder = try MetalVideoWriter(url: recordingURL, videoSize: CGSize(width: 480, height: 480), recordAudio: true)
                if let recorder = recorder {
                    preview-->recorder
                    camera==>recorder

                    recorder.startRecording()
                }

                recordButton.setTitle("Stop", for: .normal)
            } catch {
                debugPrint(error)
            }
        }
    }
}
