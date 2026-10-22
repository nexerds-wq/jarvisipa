import Foundation
import AppIntents
import CoreMotion
import FoundationModels

// Siri owns the wake phrase and speech output. iOS does not allow a third-party
// app to register "Hey Jarvis" as an always-on system hotword.
// These actions can be invoked through Siri and Shortcuts without opening the UI.
@available(iOS 26.0, *)
struct AskJarvisIntent: AppIntent {
    static var title: LocalizedStringResource = "Ask Jarvis"
    static var description = IntentDescription("Ask the iPhone's private on-device Jarvis assistant a question. Siri speaks its response.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Question", requestValueDialog: IntentDialog("What would you like to ask Jarvis?"))
    var question: String

    static var parameterSummary: some ParameterSummary {
        Summary("Ask Jarvis \(\.$question)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let prompt = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else {
            return .result(dialog: IntentDialog("What would you like to know?"))
        }
        if let liveAnswer = JarvisLiveClock.answer(for: prompt) {
            return .result(dialog: IntentDialog("\(liveAnswer)"))
        }
        guard SystemLanguageModel.default.isAvailable else {
            return .result(dialog: IntentDialog("The offline Jarvis model isn't available. Enable Apple Intelligence in iPhone Settings and download its model."))
        }
        do {
            let session = LanguageModelSession(instructions: "You are Jarvis, a concise and helpful private iPhone smart glasses assistant. Respond in one or two spoken sentences. Do not invent live information. Be clear and accurate. " + JarvisLiveClock.modelTimeContext())
            let result = try await session.respond(to: prompt)
            return .result(dialog: IntentDialog("\(String(result.content.prefix(600)))"))
        } catch {
            return .result(dialog: IntentDialog("Jarvis couldn't answer just now. Please try again."))
        }
    }
}

@available(iOS 26.0, *)
struct JarvisStepsIntent: AppIntent {
    static var title: LocalizedStringResource = "My Steps with Jarvis"
    static var description = IntentDescription("Ask Jarvis how many steps you have taken today, even when its app isn't open.")
    static var openAppWhenRun: Bool = false

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard CMPedometer.isStepCountingAvailable() else {
            return .result(dialog: IntentDialog("This iPhone doesn't provide pedometer steps."))
        }
        let pedometer = CMPedometer()
        let today = Calendar.current.startOfDay(for: Date())
        let result: (CMPedometerData?, Error?) = await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: today, to: Date()) { data, error in
                continuation.resume(returning: (data, error))
            }
        }
        guard let data = result.0 else {
            return .result(dialog: IntentDialog("I couldn't read today's steps. Please allow Motion and Fitness access."))
        }
        let count = data.numberOfSteps.intValue
        let distance = data.distance.map { String(format: "%.2f miles", $0.doubleValue / 1609.344) } ?? "an unknown distance"
        return .result(dialog: IntentDialog(stringLiteral: "You've walked \(count) steps and \(distance) today, since midnight."))
    }
}

@available(iOS 26.0, *)
struct ShowJarvisMessageIntent: AppIntent {
    static var title: LocalizedStringResource = "Show Jarvis Message"
    static var description = IntentDescription("Show a message sender and full text on the Solos HUD; connect this to an incoming Message automation.")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Sender")
    var sender: String

    @Parameter(title: "Message")
    var message: String

    static var parameterSummary: some ParameterSummary {
        Summary("Show message from \\(.$sender): \\(.$message)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let body = message.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !body.isEmpty else {
            return .result(dialog:IntentDialog("No message text was provided."))
        }
        UserDefaults.standard.set(String(sender.prefix(80)),forKey:"jarvisIncomingMessageSender")
        UserDefaults.standard.set(String(body.prefix(12_000)),forKey:"jarvisIncomingMessageBody")
        UserDefaults.standard.set(UUID().uuidString,forKey:"jarvisIncomingMessageID")
        return .result(dialog:IntentDialog("Message ready for the Solos Jarvis HUD."))
    }
}

@available(iOS 26.0, *)
struct JarvisAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: AskJarvisIntent(),
                    phrases: ["Ask \(.applicationName) a question", "Talk to \(.applicationName)"],
                    shortTitle: "Ask Jarvis",
                    systemImageName: "waveform")
        AppShortcut(intent: JarvisStepsIntent(),
                    phrases: ["My steps with \(.applicationName)", "Ask \(.applicationName) for my steps"],
                    shortTitle: "Today's Steps",
                    systemImageName: "figure.walk")
    }
}
