import AVFoundation
import CoreGraphics
import Foundation
import UIKit

enum CoppedVideoCompositor {
    private static let targetPortraitRenderSize = CGSize(width: 720, height: 1280)
    private static let targetLandscapeRenderSize = CGSize(width: 1280, height: 720)
    private static let targetFrameRate: Int32 = 30

    static func addText(
        to sourceURL: URL,
        text: String,
        position: CoppedTextPosition
    ) async -> URL? {
        await renderForUpload(
            to: sourceURL,
            text: text,
            position: position,
            effectConfig: CoppedVideoEffectConfig(look: .none, sticker: .none)
        )
    }

    static func renderForUpload(
        to sourceURL: URL,
        text: String,
        position: CoppedTextPosition,
        effectConfig: CoppedVideoEffectConfig
    ) async -> URL? {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let shouldBypass = trimmedText.isEmpty && effectConfig.isNeutral
        if shouldBypass {
            return sourceURL
        }

        return await withCheckedContinuation { continuation in
            let asset = AVAsset(url: sourceURL)
            guard let videoTrack = asset.tracks(withMediaType: .video).first else {
                continuation.resume(returning: nil)
                return
            }

            let composition = AVMutableComposition()
            guard let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
            ) else {
                continuation.resume(returning: nil)
                return
            }

            let fullRange = CMTimeRange(start: .zero, duration: asset.duration)

            do {
                try compositionVideoTrack.insertTimeRange(fullRange, of: videoTrack, at: .zero)
                if let audioTrack = asset.tracks(withMediaType: .audio).first,
                   let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                   ) {
                    try compositionAudioTrack.insertTimeRange(fullRange, of: audioTrack, at: .zero)
                }
            } catch {
                continuation.resume(returning: nil)
                return
            }

            let sourceRect = CGRect(origin: .zero, size: videoTrack.naturalSize)
                .applying(videoTrack.preferredTransform)
            let orientedSize = CGSize(
                width: abs(sourceRect.width),
                height: abs(sourceRect.height)
            )

            let renderSize = normalizedRenderSize(for: orientedSize)

            let instruction = AVMutableVideoCompositionInstruction()
            instruction.timeRange = fullRange

            let layerInstruction = AVMutableVideoCompositionLayerInstruction(assetTrack: compositionVideoTrack)
            let normalizedTransform = normalizedTransform(
                preferredTransform: videoTrack.preferredTransform,
                sourceRect: sourceRect,
                orientedSize: orientedSize,
                renderSize: renderSize
            )
            layerInstruction.setTransform(normalizedTransform, at: .zero)
            instruction.layerInstructions = [layerInstruction]

            let videoComposition = AVMutableVideoComposition()
            videoComposition.instructions = [instruction]
            videoComposition.renderSize = renderSize
            videoComposition.frameDuration = CMTime(value: 1, timescale: targetFrameRate)

            let parentLayer = CALayer()
            parentLayer.frame = CGRect(origin: .zero, size: renderSize)

            let videoLayer = CALayer()
            videoLayer.frame = CGRect(origin: .zero, size: renderSize)
            parentLayer.addSublayer(videoLayer)

            addLookOverlayLayer(effectConfig.look, renderSize: renderSize, parentLayer: parentLayer)
            let rawDuration = CMTimeGetSeconds(asset.duration)
            let animationDuration = rawDuration.isFinite && rawDuration > 0 ? rawDuration : 8

            addStickerLayer(
                effectConfig.sticker,
                renderSize: renderSize,
                durationSeconds: animationDuration,
                parentLayer: parentLayer
            )

            if !trimmedText.isEmpty {
                addTextLayer(
                    text: trimmedText,
                    position: position,
                    renderSize: renderSize,
                    parentLayer: parentLayer
                )
            }

            videoComposition.animationTool = AVVideoCompositionCoreAnimationTool(
                postProcessingAsVideoLayer: videoLayer,
                in: parentLayer
            )

            guard let exportSession = AVAssetExportSession(
                asset: composition,
                presetName: AVAssetExportPresetHighestQuality
            ) else {
                continuation.resume(returning: nil)
                return
            }

            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("copped-composited-\(UUID().uuidString).mp4")

            try? FileManager.default.removeItem(at: outputURL)

            exportSession.videoComposition = videoComposition
            exportSession.outputURL = outputURL
            exportSession.outputFileType = .mp4
            exportSession.shouldOptimizeForNetworkUse = true

            exportSession.exportAsynchronously {
                if exportSession.status == .completed {
                    continuation.resume(returning: outputURL)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }

    private static func normalizedRenderSize(for sourceSize: CGSize) -> CGSize {
        sourceSize.height >= sourceSize.width ? targetPortraitRenderSize : targetLandscapeRenderSize
    }

    private static func normalizedTransform(
        preferredTransform: CGAffineTransform,
        sourceRect: CGRect,
        orientedSize: CGSize,
        renderSize: CGSize
    ) -> CGAffineTransform {
        let translated = preferredTransform.concatenating(
            CGAffineTransform(translationX: -sourceRect.minX, y: -sourceRect.minY)
        )

        let scale = max(
            renderSize.width / max(orientedSize.width, 1),
            renderSize.height / max(orientedSize.height, 1)
        )
        let scaledWidth = orientedSize.width * scale
        let scaledHeight = orientedSize.height * scale

        let centerTranslation = CGAffineTransform(
            translationX: (renderSize.width - scaledWidth) / 2,
            y: (renderSize.height - scaledHeight) / 2
        )

        return translated
            .concatenating(CGAffineTransform(scaleX: scale, y: scale))
            .concatenating(centerTranslation)
    }

    private static func addLookOverlayLayer(
        _ look: CoppedVideoLook,
        renderSize: CGSize,
        parentLayer: CALayer
    ) {
        guard look != .none else { return }

        switch look {
        case .none:
            return
        case .rioHeat:
            let tint = CALayer()
            tint.frame = CGRect(origin: .zero, size: renderSize)
            tint.backgroundColor = UIColor(red: 1.0, green: 0.35, blue: 0.06, alpha: 0.14).cgColor
            parentLayer.addSublayer(tint)

            let glow = CAGradientLayer()
            glow.frame = CGRect(origin: .zero, size: renderSize)
            glow.colors = [
                UIColor(red: 1.0, green: 0.6, blue: 0.14, alpha: 0.25).cgColor,
                UIColor.clear.cgColor,
                UIColor(red: 1.0, green: 0.22, blue: 0.08, alpha: 0.28).cgColor,
            ]
            glow.locations = [0.0, 0.48, 1.0]
            parentLayer.addSublayer(glow)

        case .goldenHour:
            let tint = CALayer()
            tint.frame = CGRect(origin: .zero, size: renderSize)
            tint.backgroundColor = UIColor(red: 1.0, green: 0.72, blue: 0.28, alpha: 0.13).cgColor
            parentLayer.addSublayer(tint)

            let warmFade = CAGradientLayer()
            warmFade.frame = CGRect(origin: .zero, size: renderSize)
            warmFade.colors = [
                UIColor(red: 1.0, green: 0.84, blue: 0.45, alpha: 0.22).cgColor,
                UIColor.clear.cgColor,
            ]
            warmFade.startPoint = CGPoint(x: 0.2, y: 0.0)
            warmFade.endPoint = CGPoint(x: 0.8, y: 1.0)
            parentLayer.addSublayer(warmFade)

        case .coolTeal:
            let tint = CALayer()
            tint.frame = CGRect(origin: .zero, size: renderSize)
            tint.backgroundColor = UIColor(red: 0.02, green: 0.55, blue: 0.62, alpha: 0.12).cgColor
            parentLayer.addSublayer(tint)

            let coolGradient = CAGradientLayer()
            coolGradient.frame = CGRect(origin: .zero, size: renderSize)
            coolGradient.colors = [
                UIColor(red: 0.05, green: 0.35, blue: 0.58, alpha: 0.25).cgColor,
                UIColor.clear.cgColor,
                UIColor(red: 0.12, green: 0.78, blue: 0.72, alpha: 0.2).cgColor,
            ]
            coolGradient.locations = [0.0, 0.45, 1.0]
            parentLayer.addSublayer(coolGradient)
        }
    }

    private static func addTextLayer(
        text: String,
        position: CoppedTextPosition,
        renderSize: CGSize,
        parentLayer: CALayer
    ) {
        let horizontalPadding = renderSize.width * 0.08
        let textHeight = renderSize.height * 0.2
        let width = renderSize.width - (horizontalPadding * 2)

        let yOrigin: CGFloat
        switch position {
        case .top:
            yOrigin = renderSize.height * 0.1
        case .center:
            yOrigin = (renderSize.height - textHeight) / 2
        case .bottom:
            yOrigin = renderSize.height * 0.68
        }

        let containerLayer = CALayer()
        containerLayer.frame = CGRect(
            x: horizontalPadding,
            y: yOrigin,
            width: width,
            height: textHeight
        )

        let backgroundLayer = CAShapeLayer()
        backgroundLayer.frame = containerLayer.bounds
        backgroundLayer.path = UIBezierPath(
            roundedRect: backgroundLayer.bounds.insetBy(dx: 2, dy: 2),
            cornerRadius: 12
        ).cgPath
        backgroundLayer.fillColor = UIColor.black.withAlphaComponent(0.22).cgColor
        containerLayer.addSublayer(backgroundLayer)

        let textLayer = CATextLayer()
        let fontSize = max(24, renderSize.width * 0.06)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        paragraph.lineBreakMode = .byWordWrapping
        let attributed = NSAttributedString(
            string: text.uppercased(),
            attributes: [
                .font: UIFont.systemFont(ofSize: fontSize, weight: .heavy),
                .foregroundColor: UIColor.white,
                .paragraphStyle: paragraph,
                .kern: 0.5,
            ]
        )
        textLayer.string = attributed
        textLayer.alignmentMode = .center
        textLayer.shadowColor = UIColor.black.withAlphaComponent(0.6).cgColor
        textLayer.shadowOpacity = 1
        textLayer.shadowRadius = 4
        textLayer.shadowOffset = CGSize(width: 0, height: 2)
        textLayer.isWrapped = true
        textLayer.truncationMode = .end
        textLayer.contentsScale = UIScreen.main.scale
        textLayer.frame = CGRect(
            x: 10,
            y: 6,
            width: width - 20,
            height: textHeight - 12
        )

        containerLayer.addSublayer(textLayer)
        parentLayer.addSublayer(containerLayer)
    }

    private static func addStickerLayer(
        _ sticker: CoppedVideoSticker,
        renderSize: CGSize,
        durationSeconds: Double,
        parentLayer: CALayer
    ) {
        guard sticker != .none else { return }

        switch sticker {
        case .none:
            return
        case .shootingStar:
            let starLayer = CAShapeLayer()
            starLayer.path = shootingStarGlyphPath(in: CGRect(x: 0, y: 0, width: 84, height: 84)).cgPath
            starLayer.bounds = CGRect(x: 0, y: 0, width: 84, height: 84)
            starLayer.fillColor = UIColor.white.withAlphaComponent(0.95).cgColor
            starLayer.shadowColor = UIColor.white.withAlphaComponent(0.6).cgColor
            starLayer.shadowOpacity = 1
            starLayer.shadowRadius = 4
            starLayer.opacity = 0
            parentLayer.addSublayer(starLayer)

            let trailLayer = CAShapeLayer()
            trailLayer.path = UIBezierPath(roundedRect: CGRect(x: 0, y: 0, width: 120, height: 8), cornerRadius: 4).cgPath
            trailLayer.bounds = CGRect(x: 0, y: 0, width: 120, height: 8)
            trailLayer.fillColor = UIColor.white.withAlphaComponent(0.22).cgColor
            trailLayer.opacity = 0
            parentLayer.addSublayer(trailLayer)

            let path = UIBezierPath()
            path.move(to: CGPoint(x: -120, y: renderSize.height * 0.36))
            path.addCurve(
                to: CGPoint(x: renderSize.width + 120, y: renderSize.height * 0.34),
                controlPoint1: CGPoint(x: renderSize.width * 0.2, y: renderSize.height * 0.26),
                controlPoint2: CGPoint(x: renderSize.width * 0.75, y: renderSize.height * 0.4)
            )

            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path.cgPath
            move.duration = 1.6
            move.repeatCount = Float(max(1, Int(durationSeconds / 1.6) + 1))
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            move.beginTime = AVCoreAnimationBeginTimeAtZero + 0.1

            let fade = CAKeyframeAnimation(keyPath: "opacity")
            fade.values = [0.0, 1.0, 1.0, 0.0]
            fade.keyTimes = [0.0, 0.12, 0.78, 1.0]
            fade.duration = 1.6
            fade.repeatCount = move.repeatCount
            fade.beginTime = move.beginTime

            let scale = CAKeyframeAnimation(keyPath: "transform.scale")
            scale.values = [0.55, 1.0, 0.9]
            scale.keyTimes = [0.0, 0.4, 1.0]
            scale.duration = 1.6
            scale.repeatCount = move.repeatCount
            scale.beginTime = move.beginTime

            starLayer.add(move, forKey: "shootingStarMove")
            starLayer.add(fade, forKey: "shootingStarFade")
            starLayer.add(scale, forKey: "shootingStarScale")

            let trailMove = move.copy() as! CAKeyframeAnimation
            let trailFade = fade.copy() as! CAKeyframeAnimation
            trailFade.values = [0.0, 0.45, 0.22, 0.0]
            let trailScale = CABasicAnimation(keyPath: "transform.scaleX")
            trailScale.fromValue = 0.65
            trailScale.toValue = 1.05
            trailScale.duration = 1.6
            trailScale.repeatCount = move.repeatCount
            trailScale.beginTime = move.beginTime

            trailLayer.add(trailMove, forKey: "shootingStarTrailMove")
            trailLayer.add(trailFade, forKey: "shootingStarTrailFade")
            trailLayer.add(trailScale, forKey: "shootingStarTrailScale")

        case .dolphinSplash:
            let dolphinLayer = CAShapeLayer()
            dolphinLayer.path = dolphinGlyphPath(in: CGRect(x: 0, y: 0, width: 96, height: 64)).cgPath
            dolphinLayer.bounds = CGRect(x: 0, y: 0, width: 96, height: 64)
            dolphinLayer.fillColor = UIColor.white.withAlphaComponent(0.94).cgColor
            dolphinLayer.shadowColor = UIColor.black.withAlphaComponent(0.3).cgColor
            dolphinLayer.shadowRadius = 3
            dolphinLayer.shadowOpacity = 1
            dolphinLayer.opacity = 0.95
            parentLayer.addSublayer(dolphinLayer)

            let path = UIBezierPath()
            let baseline = renderSize.height * 0.7
            path.move(to: CGPoint(x: -80, y: baseline + 8))
            path.addCurve(
                to: CGPoint(x: renderSize.width + 80, y: baseline - 6),
                controlPoint1: CGPoint(x: renderSize.width * 0.25, y: baseline - 85),
                controlPoint2: CGPoint(x: renderSize.width * 0.75, y: baseline + 55)
            )

            let move = CAKeyframeAnimation(keyPath: "position")
            move.path = path.cgPath
            move.duration = 2.8
            move.repeatCount = Float(max(1, Int(durationSeconds / 2.8) + 1))
            move.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            move.beginTime = AVCoreAnimationBeginTimeAtZero + 0.2

            let roll = CAKeyframeAnimation(keyPath: "transform.rotation.z")
            roll.values = [-0.18, 0.15, -0.08]
            roll.keyTimes = [0.0, 0.5, 1.0]
            roll.duration = 2.8
            roll.repeatCount = move.repeatCount
            roll.beginTime = move.beginTime

            dolphinLayer.add(move, forKey: "dolphinMove")
            dolphinLayer.add(roll, forKey: "dolphinRoll")

            for index in 0..<4 {
                let splash = CAShapeLayer()
                let radius = CGFloat(8 + (index * 4))
                splash.path = UIBezierPath(ovalIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)).cgPath
                splash.fillColor = UIColor.white.withAlphaComponent(0.35).cgColor
                splash.position = CGPoint(x: renderSize.width * 0.5, y: baseline + 20)
                splash.opacity = 0
                parentLayer.addSublayer(splash)

                let burst = CABasicAnimation(keyPath: "transform.scale")
                burst.fromValue = 0.3
                burst.toValue = 1.8
                burst.duration = 0.8
                burst.repeatCount = move.repeatCount * Float(1.8)
                burst.beginTime = AVCoreAnimationBeginTimeAtZero + 0.35 + (Double(index) * 0.15)

                let splashFade = CAKeyframeAnimation(keyPath: "opacity")
                splashFade.values = [0.0, 0.55, 0.0]
                splashFade.keyTimes = [0.0, 0.2, 1.0]
                splashFade.duration = 0.8
                splashFade.repeatCount = burst.repeatCount
                splashFade.beginTime = burst.beginTime

                splash.add(burst, forKey: "splashScale")
                splash.add(splashFade, forKey: "splashFade")
            }
        }
    }

    private static func dolphinGlyphPath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let bodyRect = CGRect(
            x: rect.minX + rect.width * 0.2,
            y: rect.minY + rect.height * 0.25,
            width: rect.width * 0.62,
            height: rect.height * 0.5
        )
        path.append(UIBezierPath(ovalIn: bodyRect))

        let tail = UIBezierPath()
        tail.move(to: CGPoint(x: bodyRect.maxX - 2, y: bodyRect.midY))
        tail.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.2))
        tail.addLine(to: CGPoint(x: rect.maxX - 2, y: rect.maxY - rect.height * 0.2))
        tail.close()
        path.append(tail)

        let fin = UIBezierPath()
        fin.move(to: CGPoint(x: bodyRect.midX - 4, y: bodyRect.minY + 2))
        fin.addLine(to: CGPoint(x: bodyRect.midX + 8, y: rect.minY))
        fin.addLine(to: CGPoint(x: bodyRect.midX + 14, y: bodyRect.minY + 9))
        fin.close()
        path.append(fin)

        return path
    }

    private static func shootingStarGlyphPath(in rect: CGRect) -> UIBezierPath {
        let path = UIBezierPath()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let outerRadius = min(rect.width, rect.height) * 0.5
        let innerRadius = outerRadius * 0.44

        for index in 0..<10 {
            let angle = (CGFloat(index) * (.pi / 5)) - (.pi / 2)
            let radius = index.isMultiple(of: 2) ? outerRadius : innerRadius
            let point = CGPoint(
                x: center.x + (cos(angle) * radius),
                y: center.y + (sin(angle) * radius)
            )

            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.close()
        return path
    }
}
