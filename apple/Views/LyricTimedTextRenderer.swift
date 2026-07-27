import SwiftUI

@available(iOS 18, *)
struct LyricTimingTextAttribute: TextAttribute, Hashable, Sendable {
    let startTime: TimeInterval
    let endTime: TimeInterval
    let syllableStartTime: TimeInterval
    let syllableEndTime: TimeInterval
    let characterIndex: Int
    let characterCount: Int
}

/// Renders timed lyric runs in the coordinates supplied by SwiftUI.
/// Each glyph fades uniformly from its unplayed style to white, lifts slightly
/// as it is sung, and long syllables get a short expansion envelope. All of it
/// is derived analytically from `playbackTime`, so the sweep stays continuous
@available(iOS 18, *)
struct LyricTimedTextRenderer: TextRenderer {
    struct Style: Equatable, Sendable {
        let unplayedOpacity: Double
        let maximumUnplayedBlurRadius: CGFloat
        let playedRise: CGFloat
        let maximumLongSyllableScale: CGFloat
    }

    struct LayoutConfiguration: Equatable, Sendable {
        let width: CGFloat?
        let centersLines: Bool

        fileprivate var constrainedWidth: CGFloat? {
            guard let width, width.isFinite, width > 0 else { return nil }
            return width
        }
    }

    var playbackTime: TimeInterval
    let style: Style
    let layoutConfiguration: LayoutConfiguration

    var animatableData: Double {
        get { playbackTime }
        set { playbackTime = newValue }
    }

    func sizeThatFits(
        proposal: ProposedViewSize,
        text: TextProxy
    ) -> CGSize {
        guard let width = layoutConfiguration.constrainedWidth else {
            return text.sizeThatFits(proposal)
        }

        let measuredSize = text.sizeThatFits(
            ProposedViewSize(width: width, height: proposal.height)
        )
        return CGSize(width: width, height: measuredSize.height)
    }

    func draw(layout: Text.Layout, in context: inout GraphicsContext) {
        for line in layout {
            var lineContext = context
            let offset = horizontalOffset(for: line)
            if offset != 0 {
                lineContext.translateBy(x: offset, y: 0)
            }

            for run in line {
                draw(run, in: &lineContext)
            }
        }
    }

    private func horizontalOffset(for line: Text.Layout.Line) -> CGFloat {
        guard layoutConfiguration.centersLines,
              let width = layoutConfiguration.constrainedWidth else {
            return 0
        }

        let lineBounds = line.typographicBounds.rect
        guard lineBounds.width.isFinite,
              lineBounds.midX.isFinite else {
            return 0
        }
        return width * 0.5 - lineBounds.midX
    }

    private func draw(
        _ run: Text.Layout.Run,
        in context: inout GraphicsContext
    ) {
        guard let timing = run[LyricTimingTextAttribute.self] else {
            context.draw(run)
            return
        }

        let state = visualState(for: timing)
        if state.revealProgress < 1 {
            drawUnplayed(
                run,
                revealProgress: state.revealProgress,
                blurRadius: state.unplayedBlurRadius,
                in: &context
            )
        }
        guard state.revealProgress > 0 else { return }

        drawPlayed(
            run,
            revealProgress: state.revealProgress,
            liftProgress: state.liftProgress,
            expansionScale: state.expansionScale,
            in: &context
        )
    }

    private func visualState(
        for timing: LyricTimingTextAttribute
    ) -> RunVisualState {
        let rawProgress = playedProgress(for: timing)
        return RunVisualState(
            revealProgress: smootherStep(rawProgress),
            liftProgress: liftProgress(for: timing),
            expansionScale: expansionScale(for: timing),
            unplayedBlurRadius: unplayedBlurRadius(for: timing)
        )
    }

    private func liftProgress(
        for timing: LyricTimingTextAttribute
    ) -> Double {
        guard playbackTime > timing.startTime else { return 0 }

        let transitionEndTime = timing.endTime
            + Metrics.liftContinuationDuration
        let transitionDuration = transitionEndTime - timing.startTime
        guard transitionDuration > 0 else { return 1 }
        return smootherStep(
            (playbackTime - timing.startTime) / transitionDuration
        )
    }

    private func expansionScale(
        for timing: LyricTimingTextAttribute
    ) -> CGFloat {
        let maximumScale = max(style.maximumLongSyllableScale, 1)
        let syllableDuration = timing.syllableEndTime
            - timing.syllableStartTime
        guard maximumScale > 1,
              syllableDuration >= Metrics.longSyllableDurationThreshold,
              timing.characterCount > 0 else {
            return 1
        }

        let characterDuration = syllableDuration
            / Double(timing.characterCount)
        let overlapDuration = min(
            characterDuration * Metrics.expansionOverlapFraction,
            Metrics.maximumExpansionOverlapDuration
        )
        let windowStart = timing.startTime
            - (timing.characterIndex > 0 ? overlapDuration : 0)
        let windowEnd = timing.endTime
            + (timing.characterIndex < timing.characterCount - 1
                ? overlapDuration
                : 0)
        let windowDuration = windowEnd - windowStart
        guard windowDuration > 0,
              playbackTime > windowStart,
              playbackTime < windowEnd else {
            return 1
        }

        let rawProgress = unitProgress(
            (playbackTime - windowStart) / windowDuration
        )
        let envelope = sin(.pi * smootherStep(rawProgress))
        return 1 + (maximumScale - 1) * CGFloat(envelope)
    }

    private func drawUnplayed(
        _ run: Text.Layout.Run,
        revealProgress: Double,
        blurRadius: CGFloat,
        in context: inout GraphicsContext
    ) {
        var unplayedContext = context
        unplayedContext.opacity = style.unplayedOpacity
            * (1 - unitProgress(revealProgress))
        if blurRadius > 0 {
            unplayedContext.addFilter(.blur(radius: blurRadius))
        }
        unplayedContext.draw(run)
    }

    private func drawPlayed(
        _ run: Text.Layout.Run,
        revealProgress: Double,
        liftProgress: Double,
        expansionScale: CGFloat,
        in context: inout GraphicsContext
    ) {
        let verticalOffset = -max(style.playedRise, 0)
            * CGFloat(unitProgress(liftProgress))
        let scale = max(expansionScale, 1)
        var playedContext = context
        playedContext.opacity = unitProgress(revealProgress)

        if verticalOffset != 0 || scale != 1 {
            let bounds = run.typographicBounds.rect
            let transform = CGAffineTransform(
                a: scale,
                b: 0,
                c: 0,
                d: scale,
                tx: bounds.midX * (1 - scale),
                ty: bounds.midY * (1 - scale) + verticalOffset
            )
            playedContext.addFilter(
                .projectionTransform(ProjectionTransform(transform))
            )
        }
        playedContext.draw(run)
    }

    private func unplayedBlurRadius(
        for timing: LyricTimingTextAttribute
    ) -> CGFloat {
        guard style.maximumUnplayedBlurRadius > 0,
              playbackTime < timing.startTime else {
            return 0
        }

        let leadTime = timing.startTime - playbackTime
        let distance = smootherStep(
            leadTime / Metrics.unplayedBlurLeadDuration
        )
        let blurFraction = Metrics.minimumUnplayedBlurFraction
            + (1 - Metrics.minimumUnplayedBlurFraction) * distance
        let radius = style.maximumUnplayedBlurRadius * CGFloat(blurFraction)
        // Quantize so a barely changing radius does not invalidate the blur
        // every single frame, and drop sub-pixel blurs entirely.
        let quantized = (radius / Metrics.blurQuantum).rounded()
            * Metrics.blurQuantum
        return quantized < Metrics.minimumEffectiveBlurRadius ? 0 : quantized
    }

    private func playedProgress(
        for timing: LyricTimingTextAttribute
    ) -> Double {
        guard playbackTime >= timing.startTime else { return 0 }
        guard playbackTime < timing.endTime else { return 1 }

        let duration = timing.endTime - timing.startTime
        guard duration > 0 else { return 1 }
        return unitProgress((playbackTime - timing.startTime) / duration)
    }

    private func smootherStep(_ value: Double) -> Double {
        let progress = unitProgress(value)
        return progress * progress * progress
            * (progress * (progress * 6 - 15) + 10)
    }

    private func unitProgress(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

@available(iOS 18, *)
private extension LyricTimedTextRenderer {
    struct RunVisualState {
        let revealProgress: Double
        let liftProgress: Double
        let expansionScale: CGFloat
        let unplayedBlurRadius: CGFloat
    }

    enum Metrics {
        static let unplayedBlurLeadDuration: TimeInterval = 2.4
        static let minimumUnplayedBlurFraction = 0.12
        static let liftContinuationDuration: TimeInterval = 0.32
        static let longSyllableDurationThreshold: TimeInterval = 0.7
        static let expansionOverlapFraction = 0.32
        static let maximumExpansionOverlapDuration: TimeInterval = 0.14
        static let blurQuantum: CGFloat = 0.25
        static let minimumEffectiveBlurRadius: CGFloat = 0.3
    }
}
