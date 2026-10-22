import SwiftUI
import Translation
import Speech
import FoundationModels

private let accent = Color(red: 0.35, green: 1, blue: 0.73)
private let glassBlack = Color(red: 0.016, green: 0.028, blue: 0.038)
private let glassPanel = Color(red: 0.048, green: 0.080, blue: 0.104)

/// These optional features sit UNDER the unchanged, proven V4.1 connection and test screens.
/// Everything sends text through the SAME SolosClassicManager.sendHUD(_:).
struct StableExtrasView: View {
    @ObservedObject var phone: SolosPhoneController
    @ObservedObject private var accessory: SolosClassicManager
    @StateObject private var captions = OfflineCaptionService()

    @AppStorage("solosFlip180") private var flip180 = false
    @AppStorage("solosVisionBold") private var sharpText = false
    @AppStorage("solosVisionGiant") private var giantText = false
    @State private var panel = 0
    @State private var captionLocale = "en-US"
    @State private var source = "es-ES"
    @State private var target = "en-US"
    @State private var originalText = ""
    @State private var translatedText = ""
    @State private var translationStatus = "Install supported Apple language packs once over Wi-Fi."
    @State private var translationConfig: TranslationSession.Configuration?
    @State private var pendingTranslation = ""
    @State private var lastDisplaySent = Date.distantPast
    @State private var question = "Hey Jarvis, explain black holes briefly."
    @State private var testMessage = "JARVIS / SHARP VISION"

    init(phone: SolosPhoneController) {
        self.phone = phone
        _accessory = ObservedObject(wrappedValue: phone.accessory)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "eye.fill").foregroundStyle(accent)
                    Text("SOLOS  /  V6  OLED").font(.system(size: 19, weight: .black, design: .monospaced))
                    Spacer()
                    Circle().fill(accessory.connectedProtocol.isEmpty ? Color.orange : accent)
                        .frame(width: 10, height: 10)
                }
                Text("New features. Original V4.1 Bluetooth path.")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text("The V4.1 pair, connect, and SEND IMAGE controls ABOVE remain unchanged.")
                    .font(.caption).foregroundStyle(.green)
            }

            HStack(spacing: 3) {
                tab(0, "VISION", "eye")
                tab(1, "CAPTIONS", "captions.bubble")
                tab(2, "TRANSLATE", "character.book.closed")
                tab(3, "JARVIS", "brain.head.profile")
            }
            .padding(5)
            .background(.black, in: RoundedRectangle(cornerRadius: 15))

            Group {
                switch panel {
                case 0: visionPanel
                case 1: captionsPanel
                case 2: translationPanel
                default: jarvisPanel
                }
            }

            Text("Only features supported by installed iPhone language models can work fully offline. No API keys or computer are required for Apple's local AI and speech models.")
                .font(.caption2).foregroundStyle(.white.opacity(0.52))
        }
        .padding(15)
        .background(glassBlack, in: RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(accent.opacity(0.5), lineWidth: 1.2))
        .translationTask(translationConfig) { session in
            do {
                translationStatus = "Checking and preparing offline language models..."
                try await session.prepareTranslation()
                let input = pendingTranslation.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !input.isEmpty else {
                    translationStatus = "Pair ready. Speech or typed text can be translated offline."
                    return
                }
                let result = try await session.translate(input)
                if Task.isCancelled { return }
                translatedText = result.targetText
                translationStatus = "Translated locally; displaying in glasses."
                accessory.sendHUD(result.targetText)
            } catch {
                translationStatus = "Unavailable: \(error.localizedDescription). Try supported languages or connect to Wi-Fi once for a model download."
            }
        }
        .onChange(of: captions.partial) { _, newValue in
            if panel == 1 && !newValue.isEmpty && Date().timeIntervalSince(lastDisplaySent) > 1.8 {
                lastDisplaySent = Date()
                accessory.sendHUD(newValue)
            }
        }
        .onChange(of: captions.latestFinal) { _, newValue in
            if newValue.isEmpty { return }
            if panel == 1 {
                accessory.sendHUD(newValue)
            } else if panel == 2 {
                originalText = newValue
                translate(newValue)
            }
        }
        .onChange(of: panel) { _, _ in
            captions.stop()
        }
        .onDisappear { captions.stop() }
    }

    private func tab(_ id: Int, _ title: String, _ icon: String) -> some View {
        Button {
            captions.stop()
            panel = id
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 16, weight: .bold))
                Text(title).font(.system(size: 9, weight: .black, design: .monospaced))
            }
            .foregroundStyle(panel == id ? Color.black : Color.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(panel == id ? accent : glassPanel, in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }
    private func heading(_ text: String, _ icon: String) -> some View {
        Label(text, systemImage: icon)
            .font(.system(size: 16, weight: .black, design: .monospaced))
            .foregroundStyle(accent)
    }
    private func action(_ text: String, icon: String, onClick: @escaping () -> Void) -> some View {
        Button(action: onClick) {
            HStack {
                Image(systemName: icon)
                Text(text)
                Spacer()
                Image(systemName: "arrow.up.right")
            }
            .font(.system(size: 13, weight: .black, design: .monospaced))
            .padding(14)
            .foregroundStyle(Color.black)
            .background(accent, in: RoundedRectangle(cornerRadius: 11))
        }
        .buttonStyle(.plain)
    }

    private var visionPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            heading("MAX-CLARITY OLED LENS", "eye.fill")
            Toggle("Rotate glasses image 180°", isOn: $flip180).tint(accent)
            Toggle("Sharper, heavier white lettering", isOn: $sharpText).tint(accent)
            Toggle("Giant text / fewer words", isOn: $giantText).tint(accent)
            Text("These settings change only pixels sent to the lens. Your V4.1 Bluetooth connection and frame format are preserved.")
                .font(.caption).foregroundStyle(.secondary)
            TextField("Lens test text", text: $testMessage, axis: .vertical)
                .padding(12).background(.black, in: RoundedRectangle(cornerRadius: 10))
            action("TEST SHARPENED IMAGE", icon: "eye") {
                accessory.sendHUD(testMessage)
            }
            Image(uiImage: SolosDisplayPacket.render(message: testMessage))
                .resizable()
                .interpolation(.none)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 9))
            Text("Pixel sharpening cannot adjust physical focus. Large bold fonts generally improve readability more than artificial glow.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var captionsPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("LIVE OFFLINE CAPTIONS", "captions.bubble.fill")
            Text("All speech processing stays on-device when an offline recognition pack is available.")
                .font(.caption).foregroundStyle(.secondary)
            Picker("Speech language", selection: $captionLocale) {
                ForEach(speechLanguages) { language in
                    Text(language.name).tag(language.id)
                }
            }.tint(accent)
            Text(captions.status).font(.caption).foregroundStyle(.secondary)
            Text(captions.partial.isEmpty ? "What someone says will appear here..." : captions.partial)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .frame(maxWidth: .infinity, minHeight: 115, alignment: .topLeading)
                .padding(13)
                .background(.black, in: RoundedRectangle(cornerRadius: 12))
            action(captions.isListening ? "STOP CAPTIONS" : "START CAPTIONS", icon: captions.isListening ? "stop.fill" : "mic.fill") {
                if captions.isListening { captions.stop() }
                else {
                    phone.stopListening()
                    captions.start(locale: captionLocale, name: name(captionLocale))
                }
            }
            Button("Send last line to glasses") {
                accessory.sendHUD(captions.partial)
            }.font(.footnote.bold()).foregroundStyle(accent)
            Text("Keep the app open. Some languages cannot be captioned fully offline on all iPhone configurations.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var translationPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            heading("ON-DEVICE SPEECH TRANSLATION", "character.book.closed.fill")
            Text("50 language choices; Apple supports only a subset for offline speech and translation. Unsupported pairs are reported, not faked.")
                .font(.caption).foregroundStyle(.orange)
            HStack {
                VStack(alignment: .leading) {
                    Text("INPUT").font(.caption2.bold()).foregroundStyle(.secondary)
                    Picker("Input", selection: $source) {
                        ForEach(speechLanguages) { language in Text(language.name).tag(language.id) }
                    }.tint(accent)
                }
                Spacer()
                Image(systemName: "arrow.right").foregroundStyle(accent)
                Spacer()
                VStack(alignment: .leading) {
                    Text("OUTPUT").font(.caption2.bold()).foregroundStyle(.secondary)
                    Picker("Output", selection: $target) {
                        ForEach(speechLanguages) { language in Text(language.name).tag(language.id) }
                    }.tint(accent)
                }
            }
            .onChange(of: source) { _, _ in translationConfig = nil; captions.stop() }
            .onChange(of: target) { _, _ in translationConfig = nil; captions.stop() }
            Text(translationStatus).font(.caption).foregroundStyle(.secondary)
            action("CHECK / PREPARE LANGUAGE PACKS", icon: "square.and.arrow.down") {
                prepareTranslation()
            }
            Button(captions.isListening ? "Stop source microphone" : "Start source microphone") {
                if captions.isListening { captions.stop() }
                else {
                    phone.stopListening()
                    prepareTranslation()
                    captions.start(locale: source, name: name(source))
                }
            }.buttonStyle(.bordered).tint(accent)
            Text(captions.partial.isEmpty ? "Speech appears here..." : captions.partial)
                .font(.subheadline).foregroundStyle(.white.opacity(0.75))
            TextField("Or type text to translate", text: $originalText, axis: .vertical)
                .lineLimit(2...5)
                .padding(12)
                .background(.black, in: RoundedRectangle(cornerRadius: 11))
            action("TRANSLATE TEXT", icon: "arrow.left.arrow.right") {
                translate(originalText)
            }
            Text(translatedText.isEmpty ? "Translated words appear here and on the lens." : translatedText)
                .font(.system(size: 23, weight: .bold))
                .frame(maxWidth: .infinity, minHeight: 85, alignment: .topLeading)
                .padding(13)
                .background(.black, in: RoundedRectangle(cornerRadius: 11))
            Text("A language pack may need downloading with internet once. After installation, supported translations work offline.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var jarvisPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("JARVIS — PRIVATE ON-DEVICE AI", "brain.head.profile")
            Text("Runs Apple's offline Foundation Model (Ollama-style local AI). Requires Apple Intelligence enabled and its model present.")
                .font(.caption).foregroundStyle(.secondary)
            Text(phone.aiStatus).font(.caption).foregroundStyle(accent)
            TextField("What do you want to know?", text: $question, axis: .vertical)
                .lineLimit(2...5)
                .padding(12)
                .background(.black, in: RoundedRectangle(cornerRadius: 10))
            action("ASK JARVIS", icon: "sparkles") {
                captions.stop()
                phone.ask(question)
            }
            action(phone.listening ? "STOP HEY JARVIS" : "LISTEN FOR HEY JARVIS", icon: "waveform") {
                captions.stop()
                phone.listening ? phone.stopListening() : phone.startListening()
            }
            Text(phone.voiceStatus).font(.caption).foregroundStyle(.secondary)
            if !phone.transcribed.isEmpty { Text("Heard: \(phone.transcribed)").font(.caption).foregroundStyle(accent) }
            Text(phone.aiAnswer)
                .font(.system(size: 21, weight: .bold))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(12)
                .background(.black, in: RoundedRectangle(cornerRadius: 12))
            Text("Say 'Hey Jarvis' followed by a question. This uses on-device speech recognition while the app is open. It is not a dedicated always-on background hotword engine.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func name(_ locale: String) -> String { speechLanguages.first(where: {$0.id == locale})?.name ?? locale }

    private func prepareTranslation() {
        captions.stop()
        let sourceLanguage = Locale.Language(identifier: source)
        let targetLanguage = Locale.Language(identifier: target)
        Task { @MainActor in
            let availability = await LanguageAvailability().status(from: sourceLanguage, to: targetLanguage)
            switch availability {
            case .unsupported:
                translationConfig = nil
                translationStatus = "Unsupported language pair by Apple on this iPhone."
            case .installed:
                translationStatus = "Installed. This language pair is ready offline."
                translationConfig = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
            case .supported:
                translationStatus = "Supported, but a one-time language download is required. Accept iOS prompt on Wi-Fi."
                translationConfig = TranslationSession.Configuration(source: sourceLanguage, target: targetLanguage)
            @unknown default:
                translationStatus = "Unknown language support."
            }
        }
    }
    private func translate(_ words: String) {
        guard !words.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        pendingTranslation = words
        if translationConfig == nil {
            prepareTranslation()
        } else {
            translationConfig?.invalidate()
        }
    }
}

private struct SpeechOption: Identifiable {
    let id: String
    let name: String
}
// Choice list, not a claim that Apple supplies offline speech/translation for every locale.
private let speechLanguages: [SpeechOption] = [
    .init(id:"en-US",name:"English"),.init(id:"es-ES",name:"Spanish"),
    .init(id:"fr-FR",name:"French"),.init(id:"de-DE",name:"German"),
    .init(id:"it-IT",name:"Italian"),.init(id:"pt-BR",name:"Portuguese"),
    .init(id:"zh-CN",name:"Chinese"),.init(id:"ja-JP",name:"Japanese"),
    .init(id:"ko-KR",name:"Korean"),.init(id:"ar-SA",name:"Arabic"),
    .init(id:"hi-IN",name:"Hindi"),.init(id:"ru-RU",name:"Russian"),
    .init(id:"nl-NL",name:"Dutch"),.init(id:"pl-PL",name:"Polish"),
    .init(id:"tr-TR",name:"Turkish"),.init(id:"uk-UA",name:"Ukrainian"),
    .init(id:"vi-VN",name:"Vietnamese"),.init(id:"th-TH",name:"Thai"),
    .init(id:"id-ID",name:"Indonesian"),.init(id:"sv-SE",name:"Swedish"),
    .init(id:"da-DK",name:"Danish"),.init(id:"fi-FI",name:"Finnish"),
    .init(id:"he-IL",name:"Hebrew"),.init(id:"ms-MY",name:"Malay"),
    .init(id:"nb-NO",name:"Norwegian"),.init(id:"el-GR",name:"Greek"),
    .init(id:"ro-RO",name:"Romanian"),.init(id:"cs-CZ",name:"Czech"),
    .init(id:"hu-HU",name:"Hungarian"),.init(id:"sk-SK",name:"Slovak"),
    .init(id:"bg-BG",name:"Bulgarian"),.init(id:"hr-HR",name:"Croatian"),
    .init(id:"sr-RS",name:"Serbian"),.init(id:"sl-SI",name:"Slovenian"),
    .init(id:"et-EE",name:"Estonian"),.init(id:"lv-LV",name:"Latvian"),
    .init(id:"lt-LT",name:"Lithuanian"),.init(id:"is-IS",name:"Icelandic"),
    .init(id:"fa-IR",name:"Persian"),.init(id:"ur-PK",name:"Urdu"),
    .init(id:"bn-BD",name:"Bengali"),.init(id:"ta-IN",name:"Tamil"),
    .init(id:"te-IN",name:"Telugu"),.init(id:"ml-IN",name:"Malayalam"),
    .init(id:"mr-IN",name:"Marathi"),.init(id:"gu-IN",name:"Gujarati"),
    .init(id:"sw-KE",name:"Swahili"),.init(id:"fil-PH",name:"Filipino"),
    .init(id:"ca-ES",name:"Catalan"),.init(id:"af-ZA",name:"Afrikaans")
]
