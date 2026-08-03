import Darwin
import Foundation

/// Renders one terminal progress step around an asynchronous operation.
public final class ProgressStep<Value> {
    /// Message displayed while the operation is running.
    private let message: String

    /// Message displayed after a successful operation.
    private let successMessage: String

    /// Message displayed after a failed operation.
    private let errorMessage: String

    /// Asynchronous operation rendered by this step.
    private let operation: () async throws -> Value

    /// Renderer that owns this step's live terminal region.
    private let renderer = TerminalRenderer.shared

    /// Creates a progress step with optional messages for its final state.
    public init(
        message: String,
        successMessage: String? = nil,
        errorMessage: String? = nil,
        operation: @escaping () async throws -> Value,
    ) {
        self.message = message.terminalSafeLine()
        self.successMessage = (successMessage ?? message).terminalSafeLine()
        self.errorMessage = (errorMessage ?? message).terminalSafeLine()
        self.operation = operation
    }

    /// Runs the operation and renders its completion state.
    @discardableResult
    public func run() async throws -> Value {
        let startedAt = ContinuousClock.now
        let isInteractive = TerminalColor.supportsLiveRendering(for: STDOUT_FILENO)
        let usesColor = TerminalColor.isEnabled(for: STDOUT_FILENO)
        let rendererIdentifier = isInteractive ? renderer.beginProgress() : nil
        if isInteractive {
            await ProgressSpinner.shared.start(
                message: message,
                usesColor: usesColor,
                rendererIdentifier: rendererIdentifier!,
            )
        } else {
            renderer.writePlain(startMessage(usesColor: usesColor) + "\n", to: .standardOutput)
        }

        do {
            let result = try await operation()
            if let rendererIdentifier {
                await ProgressSpinner.shared.stop(rendererIdentifier: rendererIdentifier)
            }
            let completion = completionMessage(
                icon: "✔︎",
                message: successMessage,
                color: .green,
                startedAt: startedAt,
                usesColor: usesColor,
            )
            let timestampedCompletion = "\(DylibForgeLogger.timestamp()) \(completion)"
            if isInteractive {
                renderer.finishProgress(
                    rendererIdentifier!,
                    content: timestampedCompletion,
                    to: .standardOutput,
                )
            } else {
                renderer.writePlain("   \(timestampedCompletion)\n", to: .standardOutput)
            }
            return result
        } catch {
            if let rendererIdentifier {
                await ProgressSpinner.shared.stop(rendererIdentifier: rendererIdentifier)
            }
            if error is CancellationError {
                if let rendererIdentifier {
                    renderer.cancelProgress(rendererIdentifier)
                }
                throw error
            }
            let completion = completionMessage(
                icon: "⨯",
                message: errorMessage,
                color: .red,
                startedAt: startedAt,
                usesColor: TerminalColor.isEnabled(for: STDERR_FILENO),
            )
            let timestampedCompletion = "\(DylibForgeLogger.timestamp()) \(completion)"
            if isInteractive {
                renderer.finishProgress(
                    rendererIdentifier!,
                    content: timestampedCompletion,
                    to: .standardError,
                )
            } else {
                renderer.writePlain("   \(timestampedCompletion)\n", to: .standardError)
            }
            throw error
        }
    }
}

private extension ProgressStep {
    /// Builds the first non-interactive status line.
    func startMessage(usesColor: Bool) -> String {
        let icon = colored("ℹ︎", with: .cyan, enabled: usesColor)
        let message = colored(message, with: .cyan, enabled: usesColor)
        return "\(icon) \(message)"
    }

    /// Builds a completion line with one status color and a muted duration.
    func completionMessage(
        icon: String,
        message: String,
        color: TerminalColor,
        startedAt: ContinuousClock.Instant,
        usesColor: Bool,
    ) -> String {
        let icon = colored(icon, with: color, enabled: usesColor)
        let message = colored(message, with: color, enabled: usesColor)
        let duration = colored("[\(elapsedTime(since: startedAt))]", with: .brightBlack, enabled: usesColor)
        return "\(icon) \(message) \(duration)"
    }

    /// Applies one foreground color when the destination stream supports it.
    func colored(_ text: String, with color: TerminalColor, enabled: Bool) -> String {
        enabled ? text.colored(color) : text
    }

    /// Formats the elapsed duration since the operation started.
    func elapsedTime(since startedAt: ContinuousClock.Instant) -> String {
        let duration = startedAt.duration(to: .now)
        let seconds = Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
        return String(format: "%.1fs", seconds)
    }
}

/// Animates the current interactive progress line.
private actor ProgressSpinner {
    /// Braille frames rendered in sequence while work is in progress.
    private static let frames = ["⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"]

    /// Interval between frames; 12.5 FPS keeps the spinner fluid without excessive terminal writes.
    private static let frameInterval = Duration.milliseconds(80)

    /// Shared scheduler for the current live spinner.
    static let shared = ProgressSpinner()

    /// Renderer that atomically redraws the spinner frame.
    private let renderer = TerminalRenderer.shared

    /// Current spinner, if a progress operation is running.
    private var spinner: Spinner?

    /// Renderer identifier associated with the current spinner.
    private var rendererIdentifier: UUID?

    /// Index of the frame to render next.
    private var frameIndex = 0

    /// Background task responsible for advancing every active spinner frame.
    private var task: Task<Void, Never>?

    /// Starts animating one progress message.
    func start(message: String, usesColor: Bool, rendererIdentifier: UUID) {
        spinner = Spinner(message: message, usesColor: usesColor)
        self.rendererIdentifier = rendererIdentifier
        render()
        guard task == nil else { return }

        task = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.frameInterval)
                guard !Task.isCancelled else { return }
                await self?.advance()
            }
        }
    }

    /// Stops animating the current progress message.
    func stop(rendererIdentifier: UUID) {
        guard self.rendererIdentifier == rendererIdentifier else { return }
        spinner = nil
        self.rendererIdentifier = nil
        task?.cancel()
        task = nil
    }

    /// Advances the shared frame index and redraws every active spinner together.
    private func advance() {
        frameIndex = (frameIndex + 1) % Self.frames.count
        render()
    }

    /// Renders the current frame for the active spinner.
    private func render() {
        guard let spinner, let rendererIdentifier else { return }
        let frame = Self.frames[frameIndex]
        let icon = spinner.usesColor ? frame.colored(.cyan) : frame
        let text = spinner.usesColor ? spinner.message.colored(.cyan) : spinner.message
        renderer.renderProgress(rendererIdentifier, content: "\(icon) \(text)")
    }

    /// Immutable description of one spinner registered with the shared scheduler.
    private struct Spinner: Sendable {
        /// Message displayed beside the spinner frame.
        let message: String

        /// Whether this spinner uses ANSI foreground colors.
        let usesColor: Bool
    }
}
