import SwiftUI
import Translation
import FoundationModels

private enum V5Tab: String, CaseIterable, Identifiable {
    case dashboard = "HUD"
    case captions = "CAPTIONS"
    case translate = "TRANSLATE"
    case jarvis = "JARVIS"
    case vision = "VISION"
    case connection = "CONNECT"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dashboard: return "speedometer"
        case .captions: return "captions.bubble.fill"
        case .translate: return "character.book.closed"
        case .jarvis: return "brain.head.profile"
        case .vision: return "eye"
        case .connection: return "antenna.radiowaves.left.and.right"
        }
    }
}

private struct SpeechLanguage: Identifiable, Hashable {
    let id: String
    let name: String
}
// Fifty common spoken languages offered for selection; iOS checks actual device/model
// availability before captions and translations begin. NOT all 50 are supported by Apple.
private let languages: [SpeechLanguage] = [
    .init(id:"en-US",name:"English"), .init(id:"es-ES",name:"Spanish"),
    .init(id:"fr-FR",name:"French"), .init(id:"de-DE",name:"German"),
    .init(id:"it-IT",name:"Italian"), .init(id:"pt-BR",name:"Portuguese"),
    .init(id:"zh-CN",name:"Mandarin Chinese"), .init(id:"ja-JP",name:"Japanese"),
    .init(id:"ko-KR",name:"Korean"), .init(id:"ar-SA",name:"Arabic"),
    .init(id:"hi-IN",name:"Hindi"), .init(id:"ru-RU",name:"Russian"),
    .init(id:"nl-NL",name:"Dutch"), .init(id:"pl-PL",name:"Polish"),
    .init(id:"tr-TR",name:"Turkish"), .init(id:"uk-UA",name:"Ukrainian"),
    .init(id:"vi-VN",name:"Vietnamese"), .init(id:"th-TH",name:"Thai"),
    .init(id:"id-ID",name:"Indonesian"), .init(id:"sv-SE",name:"Swedish"),
    .init(id:"da-DK",name:"Danish"), .init(id:"fi-FI",name:"Finnish"),
    .init(id:"he-IL",name:"Hebrew"), .init(id:"ms-MY",name:"Malay"),
    .init(id:"nb-NO",name:"Norwegian"), .init(id:"el-GR",name:"Greek"),
    .init(id:"ro-RO",name:"Romanian"), .init(id:"cs-CZ",name:"Czech"),
    .init(id:"hu-HU",name:"Hungarian"), .init(id:"sk-SK",name:"Slovak"),
    .init(id:"bg-BG",name:"Bulgarian"), .init(id:"hr-HR",name:"Croatian"),
    .init(id:"sr-RS",name:"Serbian"), .init(id:"sl-SI",name:"Slovenian"),
    .init(id:"et-EE",name:"Estonian"), .init(id:"lv-LV",name:"Latvian"),
    .init(id:"lt-LT",name:"Lithuanian"), .init(id:"is-IS",name:"Icelandic"),
    .init(id:"fa-IR",name:"Persian"), .init(id:"ur-PK",name:"Urdu"),
    .init(id:"bn-BD",name:"Bengali"), .init(id:"ta-IN",name:"Tamil"),
    .init(id:"te-IN",name:"Telugu"), .init(id:"ml-IN",name:"Malayalam"),
    .init(id:"mr-IN",name:"Marathi"), .init(id:"gu-IN",name:"Gujarati"),
    .init(id:"sw-KE",name:"Swahili"), .init(id:"fil-PH",name:"Filipino"),
    .init(id:"ca-ES",name:"Catalan"), .init(id:"af-ZA",name:"Afrikaans")
]

private let neon = Color(red: 0.24, green: 1.0, blue: 0.73)
private let cyan = Color(red: 0.36, green: 0.88, blue: 1.0)
private let darkPanel = Color(red: 0.044, green: 0.075, blue: 0.095)
private let deepBlack = Color(red: 0.007, green: 0.015, blue: 0.020)

struct SolosV5Home: View {
    @ObservedObject var phone: SolosPhoneController
    @StateObject private var captions = OfflineCaptionService()
    @AppStorage("hudRotation") private var rotateDisplay = true
    @AppStorage("hudHighContrast") private var contrast = true
    @AppStorage("hudGiantText") private var giantText = false

    @State private var mode: V5Tab = .dashboard
    @State private var question = ""
    @State private var customText = "JARVIS ONLINE"
    @State private var fromID = "es-ES"
    @State private var toID = "en-US"
    @State private var captionID = "en-US"
    @State private var config: TranslationSession.Configuration?
    @State private var sourceText = ""
    @State private var translationText = ""
    @State private var translationStatus = "Choose a language pair. Models download once, then work offline."
    @State private var displayingText = "JARVIS / SOLOS\nREADY"
    @State private var lastCaptionSent = Date.distantPast

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 17) {
                    hero
                    connectionStrip
                    modePicker
                    displayPreview
                    switch mode {
                    case .dashboard: dashboardPanel
                    case .captions: captionPanel
                    case .translate: translationPanel
                    case .jarvis: jarvisPanel
                    case .vision: visionPanel
                    case .connection: connectionPanel
                    }
                    footer
                }
                .padding(.horizontal, 15)
                .padding(.top, 10)
                .padding(.bottom, 42)
            }
            .background(deepBlack.ignoresSafeArea())
            .navigationBarHidden(true)
            .translationTask(config) { session in
                do {
                    translationStatus = "Preparing Apple on-device translation; first use may request a model download..."
                    try await session.prepareTranslation()
                    let current = sourceText.trimmingCharacters(in: .whitespacesAndNewlines)
                    if current.isEmpty {
                        translationStatus = "Offline language pair ready. Speak or type to translate."
                        return
                    }
                    let response = try await session.translate(current)
                    guard !Task.isCancelled else { return }
                    translationText = response.targetText
                    translationStatus = "Translated on iPhone using installed language model"
                    if mode == .translate {
                        showing(response.targetText)
                    }
                } catch {
                    translationStatus = "Not available offline yet: \(error.localizedDescription). Use Wi-Fi once to install supported languages."
                }
            }
            .onChange(of: captions.partial) { _, text in
                guard !text.isEmpty else { return }
                if mode == .captions {
                    displayingText = text
                    if Date().timeIntervalSince(lastCaptionSent) > 1.25 {
                        lastCaptionSent = Date()
                        phone.accessory.sendHUD(text)
                    }
                }
            }
            .onChange(of: captions.latestFinal) { _, text in
                guard !text.isEmpty else { return }
                if mode == .translate {
                    sourceText = text
                    requestTranslation()
                } else if mode == .captions {
                    showing(text)
                }
            }
            .onChange(of: phone.aiAnswer) { _, text in
                if mode == .jarvis, !text.isEmpty { displayingText = text }
            }
            .onChange(of: mode) { _, next in
                if next == .jarvis { captions.stop() }
                else { phone.stopListening() }
            }
            .onDisappear {
                captions.stop()
                phone.stopListening()
            }
            .onAppear {
                phone.refreshSensors()
            }
        }
        .preferredColorScheme(.dark)
    }
    private func showing(_ text: String) {
        displayingText = text
        phone.accessory.sendHUD(text)
    }
    private func requestTranslation() {
        guard !sourceText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if config == nil {
            config = TranslationSession.Configuration(
                source: Locale.Language(identifier: fromID),
                target: Locale.Language(identifier: toID))
        } else {
            config?.invalidate()
        }
    }
    private func prepareLanguagePair() {
        captions.stop()
        config = nil
        translationText = ""
        let from = Locale.Language(identifier: fromID)
        let to = Locale.Language(identifier: toID)
        Task {
            let pair = await LanguageAvailability().status(from: from, to: to)
            switch pair {
            case .unsupported:
                translationStatus = "This pair is NOT supported by Apple's offline Translation system. Select a different pair."
            case .installed:
                translationStatus = "Language pair installed and available offline."
                config = TranslationSession.Configuration(source: from, target: to)
            case .supported:
                translationStatus = "Language pair supported. Approve the one-time download when prompted."
                config = TranslationSession.Configuration(source: from, target: to)
            @unknown default:
                translationStatus = "Language support could not be determined."
            }
        }
    }
    private func label(_ id: String) -> String {
        languages.first(where: { $0.id == id })?.name ?? id
    }
    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "eye.fill")
                    .font(.title3.weight(.black))
                    .foregroundStyle(neon)
                Text("S O L O S")
                    .font(.system(size: 21, weight: .black, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.white)
                Spacer()
                Text("V5  /  OLED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(neon)
            }
            HStack(alignment: .lastTextBaseline) {
                Text("JARVIS HUD")
                    .font(.system(size: 34, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Text("ON DEVICE")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(cyan)
            }
            Text("A brighter lens. A smarter iPhone. No cloud AI.")
                .foregroundStyle(.white.opacity(0.58))
                .font(.footnote)
        }
    }
    private var connectionStrip: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(phone.accessory.connectedProtocol.isEmpty ? .orange : neon)
                .frame(width: 8, height: 8)
            Text(phone.accessory.connectedProtocol.isEmpty ? "GLASSES LINK: NOT AUTHORIZED" : "DIRECT LINK CONNECTED")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .lineLimit(2)
            Spacer()
            Button("REFRESH") { phone.accessory.refresh() }
                .font(.system(size: 10, weight: .black, design: .monospaced))
                .foregroundStyle(neon)
        }
        .padding(13)
        .background(darkPanel, in: RoundedRectangle(cornerRadius: 13))
    }
    private var modePicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(V5Tab.allCases) { tab in
                    Button {
                        if mode == .captions || mode == .translate { captions.stop() }
                        mode = tab
                    } label: {
                        VStack(spacing: 5) {
                            Image(systemName: tab.icon).font(.system(size: 17, weight: .semibold))
                            Text(tab.rawValue).font(.system(size: 9, weight: .black, design: .monospaced))
                        }
                        .foregroundStyle(mode == tab ? deepBlack : .white.opacity(0.75))
                        .frame(width: 74, height: 58)
                        .background(mode == tab ? neon : darkPanel, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
    private var displayPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("LENS OUTPUT")
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .foregroundStyle(neon)
                Spacer()
                Text("428 × 240 • RGB565")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.5))
            }
            Image(uiImage: SolosDisplayPacket.render(message: displayingText))
                .resizable()
                .interpolation(.none)
                .aspectRatio(428.0 / 240.0, contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(neon.opacity(0.5), lineWidth: 1))
                .shadow(color: neon.opacity(0.10), radius: 14)
            HStack {
                Label(rotateDisplay ? "ROTATED 180° FOR LENS" : "NORMAL ORIENTATION", systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(neon)
                Spacer()
                Button("TEST LENS") { showing("SOLOS V5\nSHARP AND CLEAR") }
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(neon)
            }
        }.panel()
    }
    private var dashboardPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("LIVE HUD", symbol:"waveform.path.ecg")
            Text(phone.clock).font(.system(size: 47, weight: .black, design: .rounded)).foregroundStyle(.white)
            Text(phone.dateLine).foregroundStyle(.white.opacity(0.60))
            HStack(spacing: 10) {
                metric("STEPS", value:phone.steps, icon:"figure.walk")
                metric("SPEED", value:phone.speed, icon:"location.north.fill")
            }
            Text(phone.coordinates)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(neon)
            heroButton("DISPLAY LIVE DATA",symbol:"eye.fill") { showing(phone.dashboard) }
            Text("Clock, motion and satellite GPS work without data or API keys. Keep the app open for refresh.")
                .font(.caption).foregroundStyle(.secondary)
        }.panel()
    }
    private var captionPanel: some View {
        VStack(alignment: .leading, spacing: 14) {
            sectionTitle("OFFLINE LIVE CAPTIONS",symbol:"captions.bubble")
            Text("PHONE MIC • NO CLOUD AUDIO")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(neon)
            Picker("SPEECH LANGUAGE", selection:$captionID) {
                ForEach(languages) { lang in Text(lang.name).tag(lang.id) }
            }
            .tint(neon)
            Text(captions.status).font(.caption).foregroundStyle(.secondary)
            Text(captions.partial.isEmpty ? "Words appear here as people speak..." : captions.partial)
                .font(.system(size: 26, weight: .black, design: .rounded))
                .frame(maxWidth:.infinity,minHeight:110,alignment:.topLeading)
                .padding(14)
                .background(Color.black,in:RoundedRectangle(cornerRadius:12))
                .foregroundStyle(.white)
            heroButton(captions.isListening ? "STOP CAPTIONS" : "START LIVE CAPTIONS",symbol:captions.isListening ? "stop.fill" : "mic.fill") {
                if captions.isListening {
                    captions.stop()
                } else {
                    phone.stopListening()
                    captions.start(locale:captionID,name:label(captionID))
                }
            }
            HStack {
                Button("CLEAR TEXT") { captions.clear() }.tint(.white)
                Spacer()
                Button("SHOW LAST CAPTION") { showing(captions.partial) }.tint(neon)
            }.font(.caption.bold())
            Text("Only languages with iPhone on-device speech support work offline. Continuous listening works while the app remains active.")
                .font(.caption).foregroundStyle(.secondary)
        }.panel()
    }
    private var translationPanel: some View {
        VStack(alignment: .leading, spacing: 13) {
            sectionTitle("OFFLINE TRANSLATOR",symbol:"character.book.closed.fill")
            Text("SELECT FROM 50 • DEVICE SUPPORT VARIES")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.orange)
            HStack {
                VStack(alignment:.leading) {
                    Text("HEAR").font(.caption2).foregroundStyle(.secondary)
                    Picker("From",selection:$fromID) {
                        ForEach(languages) { lang in Text(lang.name).tag(lang.id) }
                    }
                }
                Image(systemName:"arrow.right").foregroundStyle(neon)
                VStack(alignment:.leading) {
                    Text("DISPLAY").font(.caption2).foregroundStyle(.secondary)
                    Picker("To",selection:$toID) {
                        ForEach(languages) { lang in Text(lang.name).tag(lang.id) }
                    }
                }
            }
            .tint(neon)
            .onChange(of: fromID) { _, _ in config = nil; translationText = "" }
            .onChange(of: toID) { _, _ in config = nil; translationText = "" }
            Text(translationStatus).font(.caption).foregroundStyle(.secondary)
            HStack(spacing:10) {
                Button("PREPARE LANGUAGE PACKS") { prepareLanguagePair() }
                    .buttonStyle(.bordered).tint(neon)
                Button(captions.isListening ? "STOP MIC" : "START MIC") {
                    if captions.isListening {
                        captions.stop()
                    } else {
                        phone.stopListening()
                        prepareLanguagePair()
                        captions.start(locale:fromID,name:label(fromID))
                    }
                }
                .buttonStyle(.bordered).tint(neon)
            }
            Text(captions.partial.isEmpty ? "Spoken words appear here..." : captions.partial)
                .foregroundStyle(.white.opacity(0.75))
                .font(.subheadline)
            TextField("Or type text to translate",text:$sourceText,axis:.vertical)
                .padding(12)
                .background(.black,in:RoundedRectangle(cornerRadius:11))
                .lineLimit(2...5)
            heroButton("TRANSLATE OFFLINE",symbol:"character.bubble") {
                if config == nil { prepareLanguagePair() }
                else { requestTranslation() }
            }
            Text(translationText.isEmpty ? "Translated words will appear here and in the glasses." : translationText)
                .font(.system(size: 25, weight: .bold))
                .frame(maxWidth:.infinity,minHeight:90,alignment:.topLeading)
                .padding(12)
                .background(.black,in:RoundedRectangle(cornerRadius:12))
            Text("Model downloads need internet once. Translations then run on-device for supported language pairs. Speech recognition also needs a local language model. Translation updates after complete phrases.")
                .font(.caption).foregroundStyle(.secondary)
        }.panel()
    }
    private var jarvisPanel: some View {
        VStack(alignment:.leading,spacing:14) {
            sectionTitle("JARVIS • ON-DEVICE AI",symbol:"brain.head.profile")
            Text("APPLE FOUNDATION MODEL • NO SERVER")
                .font(.system(size:10,weight:.bold,design:.monospaced))
                .foregroundStyle(neon)
            Text(phone.aiStatus).font(.caption).foregroundStyle(.secondary)
            TextField("Ask anything...",text:$question,axis:.vertical)
                .lineLimit(2...5)
                .padding(12)
                .background(.black,in:RoundedRectangle(cornerRadius:12))
            heroButton("ASK JARVIS OFFLINE",symbol:"sparkles") { phone.ask(question) }
            heroButton(phone.listening ? "STOP HEY JARVIS" : "LISTEN FOR HEY JARVIS",symbol:phone.listening ? "stop.fill" : "waveform") {
                captions.stop()
                phone.listening ? phone.stopListening() : phone.startListening()
            }
            Text(phone.voiceStatus).font(.caption).foregroundStyle(.secondary)
            if !phone.transcribed.isEmpty {
                Text("HEARD: \(phone.transcribed)").font(.caption).foregroundStyle(cyan)
            }
            Text(phone.aiAnswer).font(.system(size:22,weight:.bold))
                .frame(maxWidth:.infinity,alignment:.leading)
                .padding(14)
                .background(.black,in:RoundedRectangle(cornerRadius:12))
            Text("This runs Apple's local AI model, not the desktop Ollama application. Requires Apple Intelligence enabled and its model downloaded. Wake recognition works with the app active; iOS may suspend listening in the background.")
                .font(.caption).foregroundStyle(.secondary)
        }.panel()
    }
    private var visionPanel: some View {
        VStack(alignment:.leading,spacing:17) {
            sectionTitle("ACCESSIBLE OLED VISION",symbol:"eye.fill")
            Text("BUILT FOR MAXIMUM LEGIBILITY")
                .font(.system(size:12,weight:.black,design:.monospaced))
                .foregroundStyle(neon)
            toggle("ROTATE LENS 180°",desc:"Fix the upside-down Solos image",value:$rotateDisplay)
            toggle("ULTRA-HIGH CONTRAST",desc:"Near-black pixels, white letters and solid outlines",value:$contrast)
            toggle("GIANT BOLD LETTERS",desc:"Fewer words, larger text on the 428×240 lens",value:$giantText)
            TextField("Test high-contrast text",text:$customText,axis:.vertical)
                .padding(10)
                .background(.black,in:RoundedRectangle(cornerRadius:10))
            heroButton("APPLY AND TEST LENS",symbol:"eye.fill") { showing(customText) }
            Text("Digital sharpening cannot correct optical focus or replace prescription glasses. These settings make pixel edges and letters easier to distinguish.")
                .font(.caption).foregroundStyle(.secondary)
        }.panel()
    }
    private var connectionPanel: some View {
        VStack(alignment:.leading,spacing:12) {
            sectionTitle("DIRECT SOLOS LINK",symbol:"antenna.radiowaves.left.and.right")
            Text(phone.accessory.status).foregroundStyle(.white.opacity(0.8)).font(.caption)
            HStack {
                Button("PAIR ACCESSORY") { phone.accessory.openPicker() }.buttonStyle(.borderedProminent).tint(neon)
                Button("REFRESH") { phone.accessory.refresh() }.buttonStyle(.bordered).tint(neon)
            }
            if phone.accessory.accessories.isEmpty {
                Text("No External Accessory protocol exposed right now. Your previous working connection is required to send images to the lens.")
                    .font(.caption).foregroundStyle(.orange)
            }
            ForEach(phone.accessory.accessories) { device in
                VStack(alignment:.leading,spacing:8) {
                    Text(device.name).font(.headline)
                    Text("Maker: \(device.manufacturer)")
                    Text(device.protocols.joined(separator:", "))
                        .font(.caption.monospaced()).textSelection(.enabled)
                    ForEach(device.protocols,id:\.self) { proto in
                        Button("CONNECT \(proto)") {
                            phone.accessory.connect(accessoryID:device.id,protocolString:proto)
                        }
                        .buttonStyle(.bordered).tint(neon)
                    }
                }
                .padding(12).background(.black,in:RoundedRectangle(cornerRadius:11))
            }
            Text(phone.bleState).font(.caption).foregroundStyle(.secondary)
            Button("SCAN BLE DIAGNOSTICS") { phone.scanBLE() }.buttonStyle(.bordered).tint(neon)
            ForEach(phone.discoveredBLE.prefix(12),id:\.self) { dev in
                Text(dev).font(.caption2.monospaced())
            }
            Text("iOS accessory authorization is still required; the app can't bypass Apple's RFCOMM restrictions.")
                .font(.caption).foregroundStyle(.secondary)
        }.panel()
    }
    private func toggle(_ title:String,desc:String,value:Binding<Bool>) -> some View {
        Toggle(isOn:value) {
            VStack(alignment:.leading,spacing:3) {
                Text(title).font(.system(size:12,weight:.heavy,design:.monospaced))
                Text(desc).font(.caption).foregroundStyle(.secondary)
            }
        }.tint(neon)
    }
    private func sectionTitle(_ name:String,symbol:String) -> some View {
        HStack {
            Image(systemName:symbol).foregroundStyle(neon)
            Text(name).font(.system(size:15,weight:.black,design:.monospaced))
            Spacer()
            Rectangle().fill(neon.opacity(0.38)).frame(width:28,height:2)
        }
    }
    private func metric(_ label:String,value:String,icon:String) -> some View {
        VStack(alignment:.leading,spacing:5) {
            Label(label,systemImage:icon)
                .font(.system(size:11,weight:.bold,design:.monospaced))
                .foregroundStyle(neon)
            Text(value).font(.system(size:21,weight:.heavy,design:.rounded))
        }
        .frame(maxWidth:.infinity,alignment:.leading)
        .padding(13)
        .background(.black,in:RoundedRectangle(cornerRadius:11))
    }
    private func heroButton(_ title:String,symbol:String,action:@escaping () -> Void) -> some View {
        Button(action:action) {
            HStack {
                Image(systemName:symbol)
                Text(title).font(.system(size:14,weight:.black,design:.monospaced))
                Spacer()
                Image(systemName:"arrow.up.right")
            }
            .foregroundStyle(deepBlack)
            .padding(15)
            .background(neon,in:RoundedRectangle(cornerRadius:12))
        }
        .buttonStyle(.plain)
    }
    private var footer: some View {
        HStack {
            Image(systemName:"cpu")
            Text("SOLOS IPHONE V5")
            Spacer()
            Text("LOCAL • PRIVATE")
        }
        .font(.system(size:10,weight:.heavy,design:.monospaced))
        .foregroundStyle(.white.opacity(0.38))
        .padding(10)
    }
}

private struct V5Panel: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth:.infinity,alignment:.leading)
            .background(darkPanel,in:RoundedRectangle(cornerRadius:18))
            .overlay(RoundedRectangle(cornerRadius:18).stroke(neon.opacity(0.20),lineWidth:1))
    }
}
private extension View { func panel() -> some View { modifier(V5Panel()) } }
