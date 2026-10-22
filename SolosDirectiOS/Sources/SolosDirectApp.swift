import SwiftUI
import MapKit
import Translation
import Contacts
import ContactsUI

@main
struct SolosDirectApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var phone = SolosPhoneController()
    var body: some Scene {
        WindowGroup {
            SolosDirectHome(phone: phone)
                .preferredColorScheme(.dark)
                .onAppear { phone.refreshSensors(); phone.accessory.refresh() }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        phone.refreshStepsOnly()
                        phone.accessory.refresh()
                        if UserDefaults.standard.bool(forKey:"jarvisLockScreenWake") {
                            phone.resumeAfterScreenUnlock()
                        }
                    } else if phase == .background &&
                                !UserDefaults.standard.bool(forKey:"jarvisLockScreenWake") {
                        phone.stopListening()
                    }
                }
        }
    }
}

struct SolosDirectHome: View {
    @ObservedObject var phone: SolosPhoneController
    @ObservedObject private var accessory: SolosClassicManager
    @StateObject private var handsFree = SolosHandsFreeEngine()
    @StateObject private var navigation = SolosNavigationEngine()
    @StateObject private var captions = OfflineCaptionService()
    init(phone: SolosPhoneController) {
        self.phone = phone
        self._accessory = ObservedObject(wrappedValue: phone.accessory)
    }
    @State private var question = "Hey Jarvis, what is a black hole?"
    @State private var customHUD = "HELLO FROM IPHONE"
    @AppStorage("solosOrientationMode") private var orientationMode = 0
    @AppStorage("solosAutoDashboard") private var autoDashboard = true
    @AppStorage("jarvisSpeakAnswers") private var jarvisSpeakAnswers = true
    @AppStorage("jarvisScreenOffHUD") private var screenOffHUD = false
    @AppStorage("jarvisLockScreenWake") private var lockScreenWake = false
    @AppStorage("jarvisWikipediaFallback") private var wikipediaFallback = false
    @AppStorage("solosTranslationSourceLocale") private var sourceLocale = "es-ES"
    private let sourceOptions: [(code:String,name:String)] = [
        ("es-ES","Spanish"),("fr-FR","French"),("de-DE","German"),
        ("it-IT","Italian"),("pt-BR","Portuguese"),("ja-JP","Japanese"),
        ("ko-KR","Korean"),("zh-CN","Mandarin Chinese"),("en-US","English")
    ]
    @State private var hudConfigured = false
    @State private var captionText = ""
    @State private var translatedText = ""
    @State private var translationPending = ""
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var messageSender = "NEW MESSAGE"
    @State private var messageBody = ""
    @State private var messagePhoto: UIImage?
    @State private var messagePages = ["NO MESSAGE YET"]
    @State private var currentMessagePage = 0
    @State private var messageRotationID = UUID()
    @State private var showContactPicker = false
    @State private var contactsStatus = ""

    @State private var lastDashboardMinute = ""
    @State private var page = 0
    @State private var lastOledMessage = ""
    @State private var answerShowingUntil = Date.distantPast
    @State private var answerDisplayID = UUID()
    @State private var lensAnswerPage = ""
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    VStack(alignment: .leading, spacing: 8) {
                        Text("VOICE JARVIS / LOCK SCREEN")
                            .font(.headline).foregroundStyle(.mint)
                        Text("With Siri enabled, say: “Hey Siri, ask Solos Jarvis a question.” Siri can speak the answer without opening this app.")
                            .font(.subheadline)
                        Text("Or say: “Hey Siri, my steps with Solos Jarvis” to hear your step count since midnight.")
                            .font(.subheadline)
                        Toggle("Speak Jarvis answers through phone or Bluetooth audio", isOn: $jarvisSpeakAnswers)
                            .tint(.mint)
                        Toggle("HEY JARVIS • CONTINUOUS MIC (EXPERIMENTAL)", isOn:$lockScreenWake)
                            .tint(.mint)
                            .onChange(of: lockScreenWake) { _, armed in
                                if armed { phone.startListening() }
                                else { phone.stopListening() }
                            }
                        Text("Turn this on once while the app is open. The microphone will attempt to keep listening when locked, then re-arm after Jarvis speaks. Continuous recording uses more battery; iOS may suspend recognition, and it cannot run after force-quit. Siri voice shortcuts are the reliable locked-screen fallback.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(14)
                        .background(Color(red:0.045,green:0.095,blue:0.12),in:RoundedRectangle(cornerRadius:14))
                    handsFreeCard
                    captionCard
                    translationCard
                    messageCard
                    navigationCard
                    SolosAccessoryCard(manager: phone.accessory)
                    VStack(alignment: .leading, spacing: 9) {
                        Text("JARVIS • AI + OPTIONAL FACT LOOKUP").font(.headline).foregroundStyle(.mint)
                        Toggle("ALLOW ONLINE WIKIPEDIA FACTUAL FALLBACK",isOn:$wikipediaFallback)
                            .tint(.mint)
                        Text("Optional: If Apple's offline model fails, factual questions can be sent to Wikipedia over HTTPS. Requires internet; not a general AI service. Off by default for privacy.")
                            .font(.caption2).foregroundStyle(.secondary)
                        Text(phone.aiStatus).font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $question)
                            .frame(minHeight: 90)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 14))
                        Button("ASK ON-DEVICE AI + SHOW ON GLASSES") { phone.ask(question) }
                            .buttonStyle(.borderedProminent).tint(.mint)
                        Button("TEST JARVIS TEXT ON REAL GLASSES") {
                            showAnswerOnGlasses("JARVIS DISPLAY TEST. THIS ANSWER SHOULD APPEAR ON YOUR SOLOS HUD.")
                            phone.accessory.speak("Jarvis display test")
                        }
                        .buttonStyle(.bordered)
                        Text(accessory.connectedProtocol.isEmpty
                             ? "No active glasses HUD connection. Phone preview cannot prove lens output. Open DIRECT GLASSES CONNECTION below."
                             : "CONNECTED HUD: " + accessory.connectedName + " • " + accessory.connectedProtocol)
                            .font(.caption.bold())
                            .foregroundStyle(accessory.connectedProtocol.isEmpty ? .orange : .mint)
                        Text("HUD packets transmitted: \(accessory.hudFramesSent)")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                        HStack {
                            Button(phone.listening ? "STOP LISTENING" : "START HEY JARVIS") {
                                phone.listening ? phone.stopListening() : phone.startListening()
                            }.buttonStyle(.bordered)
                            Image(systemName: "mic.fill").foregroundStyle(.mint)
                        }
                        Text(phone.voiceStatus).font(.caption).foregroundStyle(.secondary)
                        if !phone.transcribed.isEmpty {
                            Text("Heard: \(phone.transcribed)").font(.caption)
                        }
                        Text("JARVIS:").font(.caption.bold()).foregroundStyle(.mint)
                        Text(phone.aiAnswer)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                    }.card()
                    VStack(alignment: .leading, spacing: 10) {
                        Text("LIVE IPHONE DASHBOARD").font(.headline).foregroundStyle(.mint)
                        HStack(alignment: .firstTextBaseline) {
                            Text(phone.clock).font(.system(size: 37, weight: .bold, design: .rounded))
                            Spacer()
                            Text("OFFLINE").foregroundStyle(.mint).font(.caption.bold())
                        }
                        Text(phone.dateLine).foregroundStyle(.secondary)
                        HStack {
                            Label("\(phone.steps) steps", systemImage: "figure.walk")
                            Spacer()
                            Label(phone.distance, systemImage: "map")
                        }.font(.subheadline)
                        HStack {
                            Label(phone.battery, systemImage: "battery.100percent")
                            Spacer()
                            Label(phone.speed, systemImage: "location")
                        }.font(.subheadline)
                        Text(phone.coordinates).font(.caption).foregroundStyle(.mint)
                        Text(phone.motionStatus).font(.caption2).foregroundStyle(.secondary)
                        Text(phone.locationStatus).font(.caption2).foregroundStyle(.secondary)
                        Toggle("LIVE OLED DASHBOARD: refresh on lens each minute", isOn: $autoDashboard)
                            .tint(.mint)
                            .onChange(of: autoDashboard) { _, enabled in
                                if enabled { sendDashboard() }
                            }
                        Toggle("KEEP HUD UPDATING WITH SCREEN LOCKED", isOn: $screenOffHUD)
                            .tint(.mint)
                            .onChange(of: screenOffHUD) { _, enabled in
                                navigation.enableBackgroundDashboard(enabled)
                            }
                        Text("Screen-off dashboard uses background GPS and more battery. It can continue while the app is backgrounded, but not after force-quit. Turn it off when not needed.")
                            .font(.caption2).foregroundStyle(.secondary)
                         HStack {
                            Button("SEND OLED DASHBOARD") { sendDashboard() }
                                .buttonStyle(.borderedProminent).tint(.mint)
                            Button("REFRESH SENSORS") { phone.refreshSensors() }
                                .buttonStyle(.bordered)
                        }
                        Text("Daily steps are re-read after reopening. During navigation, location callbacks also refresh them with the screen locked. A force-quit stops live HUD updates.")

                            .font(.caption).foregroundStyle(.secondary)
                    }.card()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("TEST CUSTOM HUD — ORIGINAL V4 CONNECTION").font(.headline).foregroundStyle(.mint)
                        Text("Correct upside-down AND mirrored letters independently. Start with V4 Original, then try each correction.")
                            .font(.caption).foregroundStyle(.secondary)
                        Picker("Lens image orientation", selection: $orientationMode) {
                            Text("0 • V4 ORIGINAL").tag(0)
                            Text("1 • ROTATE 180°").tag(1)
                            Text("2 • MIRROR LEFT/RIGHT").tag(2)
                            Text("3 • FLIP TOP/BOTTOM").tag(3)
                        }
                        .pickerStyle(.menu)
                        .tint(.mint)
                        Button("SEND ORIENTATION TEST — ABC 123 →") {
                            phone.accessory.sendHUD("TOP ABC 123 >\nLEFT > RIGHT\nBOTTOM 789")
                        }
                        .buttonStyle(.borderedProminent).tint(.mint)
                        TextField("Text for Solos display", text: $customHUD, axis: .vertical)
                            .textFieldStyle(.roundedBorder)
                        Button("SEND 428 × 240 RLE565 IMAGE") { phone.accessory.sendHUD(customHUD) }
                            .buttonStyle(.bordered)
                        if let image = SolosDisplayPacket.imagePacket(message: customHUD) {
                            Text("Encoded Solos frame: \(image.count) bytes").font(.caption).foregroundStyle(.secondary)
                        }
                        Image(uiImage: SolosDisplayPacket.render(message: customHUD))
                            .resizable().aspectRatio(contentMode: .fit)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text("This preview appears on iPhone regardless of Bluetooth. It appears in your glasses only if an Apple-authorized display connection succeeds.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.card()
                    VStack(alignment: .leading, spacing: 8) {
                        Text("BLUETOOTH DIAGNOSTICS").font(.headline).foregroundStyle(.mint)
                        Text(phone.bleState).font(.caption).foregroundStyle(.secondary)
                        Button("SCAN BLUETOOTH LE") { phone.scanBLE() }.buttonStyle(.bordered)
                        ForEach(phone.discoveredBLE.prefix(15), id: \.self) { device in
                            Text(device).font(.caption.monospaced())
                        }
                        Text("Bluetooth LE scan does not expose the glasses' Bluetooth Classic RFCOMM channel. The official accessory protocol is still needed for direct HUD communication.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.card()
                }
                .padding()
            }
            .background(Color(red: 0.02, green: 0.055, blue: 0.075))
            .navigationTitle("SOLOS DIRECT")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented:$showContactPicker) {
                SolosMessageContactPicker { name, photo in
                    messageSender = name
                    messagePhoto = photo
                }
            }
            .onOpenURL { url in acceptIncomingMessageURL(url) }
            .translationTask(translationConfiguration) { session in
                let original = translationPending
                guard handsFree.mode == 3, !original.isEmpty else { return }
                do {
                    try await session.prepareTranslation()
                    let result = try await session.translate(original)
                    await MainActor.run {
                        guard handsFree.mode == 3, translationPending == original else { return }
                        translatedText = result.targetText
                        sendModeHUD(3)
                    }
                } catch {
                    await MainActor.run {
                        guard handsFree.mode == 3, translationPending == original else { return }
                        translatedText = "Translation unavailable: " + error.localizedDescription
                        sendModeHUD(3)
                    }
                }
            }
            .onChange(of: sourceLocale) { _, _ in
                if handsFree.mode == 3 { beginCaptions(mode:3) }
            }
            .onAppear {
                configureHandsFree()
                if lockScreenWake && handsFree.mode != 2 && handsFree.mode != 3 && !phone.listening { phone.startListening() }
            }
            .onChange(of: accessory.connectedProtocol) { _, proto in
                if !proto.isEmpty {
                    navigation.enableBackgroundDashboard(screenOffHUD)
                    sendModeHUD(handsFree.mode)
                }
            }
            .onChange(of: phone.aiStatus) { _, status in
                guard status.hasPrefix("Answered "), !phone.aiAnswer.isEmpty, handsFree.mode != 4 else { return }
                showAnswerOnGlasses(phone.aiAnswer)
            }
            .onChange(of: phone.now) { _, time in
                guard autoDashboard, handsFree.mode == 0, Date() >= answerShowingUntil, !accessory.connectedProtocol.isEmpty else { return }
                let stamp = String(Calendar.current.component(.year, from: time)) + "-" +
                            String(Calendar.current.component(.month, from: time)) + "-" +
                            String(Calendar.current.component(.day, from: time)) + "-" +
                            String(Calendar.current.component(.hour, from: time)) + ":" +
                            String(Calendar.current.component(.minute, from: time))
                if stamp != lastDashboardMinute {
                    lastDashboardMinute = stamp
                    sendModeHUD(0)
                }
            }
        }
    }
    private func showAnswerOnGlasses(_ answer: String) {
        // Real lens images are sent via EASession and the unchanged V4 RLE565
        // packet format. The phone preview is not the lens display.
        let pages = SolosProHUD.answerPages(answer)
        let generation = UUID()
        answerDisplayID = generation
        answerShowingUntil = Date().addingTimeInterval(Double(pages.count * 7 + 5))
        for (index, page) in pages.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index * 7)) {
                guard answerDisplayID == generation else { return }
                lensAnswerPage = page
                sendModeHUD(5, message:page, detail:"JARVIS • PAGE \(index + 1)/\(pages.count)")
            }
        }
        DispatchQueue.main.asyncAfter(deadline:.now()+Double(pages.count * 7 + 5)) {
            guard answerDisplayID == generation else { return }
            answerShowingUntil = .distantPast
            lensAnswerPage = ""
            sendModeHUD(handsFree.mode)
        }
    }

    private func sendDashboard() {
        phone.refreshSensors()
        lastDashboardMinute = String(Calendar.current.component(.year, from: Date())) + "-" +
                              String(Calendar.current.component(.month, from: Date())) + "-" +
                              String(Calendar.current.component(.day, from: Date())) + "-" +
                              String(Calendar.current.component(.hour, from: Date())) + ":" +
                              String(Calendar.current.component(.minute, from: Date()))
        sendModeHUD(0)
    }
    private func configureHandsFree() {
        guard !hudConfigured else { return }
        hudConfigured = true
        handsFree.enableMediaButtons()
        navigation.enableBackgroundDashboard(screenOffHUD)
        accessory.onAccessoryPacket = { packet in
            handsFree.input(packet)
        }
        handsFree.onModeChange = { selected in
            enterHUDMode(selected)
        }
        handsFree.onLanguageButton = {
            nextTranslationLanguage()
        }
        captions.onSubtitle = { words in
            captionText = words
            if handsFree.mode == 2 {
                sendModeHUD(2)
            } else if handsFree.mode == 3 {
                requestTranslation(words)
            }
        }
        captions.onFinal = { words in
            captionText = words
            if handsFree.mode == 2 { sendModeHUD(2) }
            if handsFree.mode == 3 { requestTranslation(words) }
        }
        navigation.onUpdate = { if handsFree.mode == 1 && Date() >= answerShowingUntil { sendModeHUD(1) } }
        navigation.onBackgroundTick = {
            phone.refreshStepsOnly()
            if autoDashboard && handsFree.mode == 0 && Date() >= answerShowingUntil {
                sendModeHUD(0)
            }
        }
        if handsFree.mode == 2 || handsFree.mode == 3 {
            beginCaptions(mode:handsFree.mode)
        }
        if !accessory.connectedProtocol.isEmpty {
            sendModeHUD(handsFree.mode)
        }
    }
    private func sendModeHUD(_ mode: Int, message: String = "", detail: String = "") {
        guard !accessory.connectedProtocol.isEmpty else { return }
        let navMessage = navigation.nextTurn + "|" + navigation.instruction + "|" + navigation.eta + "|" + navigation.remaining
        let body: String
        switch mode {
        case 1: body = navMessage
        case 2: body = captionText
        case 3: body = translatedText
        case 4: body = messagePages[min(currentMessagePage,messagePages.count - 1)]
        default: body = message
        }
        let sourceName = sourceOptions.first(where:{$0.code == sourceLocale})?.name ?? sourceLocale
        let footer: String
        switch mode {
        case 2: footer = "SPEECH • ENGLISH • LIVE"
        case 3: footer = sourceName.uppercased() + " TO ENGLISH • LIVE"
        case 4: footer = "MESSAGE FROM SHORTCUT / PASTE"
        default: footer = "SOLOS • \(mode + 1)/5"
        }
        let view = SolosProHUD.image(mode:mode,
            clock:phone.clock,date:phone.dateLine,
            steps:Int(phone.steps) ?? 0,distance:phone.distance,
            speed:phone.speed,battery:phone.battery,gps:phone.coordinates,
            message:body,detail:detail.isEmpty ? footer : detail,
            sender:messageSender,senderPhoto:messagePhoto,
            messagePage:currentMessagePage + 1,pageCount:messagePages.count)
        accessory.sendHUDImage(view,priority:mode == 4 || mode == 5)
        lastOledMessage = body
    }

    private func enterHUDMode(_ selected: Int) {
        // Stop any timed Jarvis answer pages whenever a glasses control
        // changes screens. Messages are pinned until NEXT or BACK is pressed.
        answerDisplayID = UUID()
        lensAnswerPage = ""
        answerShowingUntil = .distantPast
        messageRotationID = UUID()
        if selected == 2 || selected == 3 {
            beginCaptions(mode:selected)
        } else {
            captions.stop()
            translationConfiguration = nil
            translationPending = ""
            if lockScreenWake && !phone.listening { phone.startListening() }
            if selected == 0 { phone.refreshSensors() }
        }
        if selected == 4 {
            messagePages = SolosProHUD.messagePages(messageBody)
            currentMessagePage = 0
            let token = messageRotationID
            rotateMessagePages(token)
        }
        sendModeHUD(selected)
    }

    private func beginCaptions(mode:Int) {
        guard mode == 2 || mode == 3 else { return }
        // Only one service can own the mic tap reliably at a time.
        // Re-arm the Hey Jarvis service when captions/translation is exited.
        phone.stopListening()
        captions.stop()
        captionText = ""
        translatedText = ""
        translationPending = ""
        let locale = mode == 2 ? "en-US" : sourceLocale
        let label = mode == 2 ? "English" :
            (sourceOptions.first(where:{$0.code == sourceLocale})?.name ?? sourceLocale)
        if mode == 3 && !locale.hasPrefix("en") {
            let source = String(locale.split(separator:"-").first ?? "es")
            translationConfiguration = TranslationSession.Configuration(
                source:Locale.Language(identifier:source),
                target:Locale.Language(identifier:"en")
            )
        } else {
            translationConfiguration = nil
        }
        captions.start(locale:locale,name:label)
        sendModeHUD(mode)
    }

    private func requestTranslation(_ spoken:String) {
        guard handsFree.mode == 3, !spoken.isEmpty else { return }
        if sourceLocale.hasPrefix("en") {
            translatedText = spoken
            sendModeHUD(3)
            return
        }
        guard spoken != translationPending else { return }
        translationPending = spoken
        if translatedText.isEmpty { translatedText = "TRANSLATING..." }
        // The system task requests models with consent when needed.
        // Reusing the configuration's invalidation ensures the next spoken
        // phrase runs in the right source-to-English session.
        translationConfiguration?.invalidate()
    }

    private func nextTranslationLanguage() {
        guard handsFree.mode == 3 else { return }
        let current = sourceOptions.firstIndex(where:{$0.code == sourceLocale}) ?? 0
        sourceLocale = sourceOptions[(current + 1) % sourceOptions.count].code
        // Changing this @AppStorage triggers onChange -> reinitializes captions.
    }

    private func rotateMessagePages(_ token:UUID) {
        DispatchQueue.main.asyncAfter(deadline:.now()+8) {
            guard handsFree.mode == 4, messageRotationID == token else { return }
            if messagePages.count > 1 {
                currentMessagePage = (currentMessagePage + 1) % messagePages.count
                sendModeHUD(4)
            }
            rotateMessagePages(token)
        }
    }

    private func pinCurrentMessage() {
        guard !messageBody.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else {
            contactsStatus = "Paste or type the message first."
            return
        }
        messagePages = SolosProHUD.messagePages(messageBody)
        currentMessagePage = 0
        handsFree.setMode(4,force:true)
    }

    private func acceptIncomingMessageURL(_ url:URL) {
        guard url.scheme?.lowercased() == "solosjarvis",
              url.host?.lowercased() == "message",
              let items = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems,
              let text = items.first(where:{$0.name == "body"})?.value,
              !text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        messageSender = String((items.first(where:{$0.name == "from"})?.value ?? "NEW MESSAGE").prefix(80))
        messageBody = String(text.prefix(12_000))
        messagePhoto = nil
        loadExistingContactPhoto(for:messageSender)
        pinCurrentMessage()
    }

    private func loadExistingContactPhoto(for sender:String) {
        let permission = CNContactStore.authorizationStatus(for:.contacts)
        guard permission == .authorized || permission == .limited else { return }
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey,CNContactFamilyNameKey,
                    CNContactThumbnailImageDataKey] as [CNKeyDescriptor]
        do {
            let matches: [CNContact]
            if sender.contains(where:{$0.isNumber}) {
                matches = try store.unifiedContacts(
                    matching:CNContact.predicateForContacts(matching:CNPhoneNumber(stringValue:sender)),
                    keysToFetch:keys)
            } else {
                matches = try store.unifiedContacts(
                    matching:CNContact.predicateForContacts(matchingName:sender),
                    keysToFetch:keys)
            }
            guard let contact = matches.first else { return }
            if let name = CNContactFormatter.string(from:contact,style:.fullName),
               !name.isEmpty { messageSender = name }
            if let data = contact.thumbnailImageData {
                messagePhoto = UIImage(data:data)
            }
        } catch {
            contactsStatus = "Contact photo unavailable: " + error.localizedDescription
        }
    }

    private func requestContactsPermission() {
        CNContactStore().requestAccess(for:.contacts) { granted, _ in
            DispatchQueue.main.async {
                contactsStatus = granted ? "Contacts permitted for sender photos" :
                    "Contacts access not granted. Select a contact manually."
                if granted { loadExistingContactPhoto(for:messageSender) }
            }
        }
    }

    private var navigationCard: some View {
        VStack(alignment:.leading,spacing:12) {
            Label("APPLE MAPS • SPOKEN DIRECTIONS",systemImage:"map.fill")
                .font(.headline).foregroundStyle(.mint)
            TextField("Enter address, place, or ZIP",text:$navigation.address)
                .textContentType(.fullStreetAddress)
                .textInputAutocapitalization(.words)
                .padding(12)
                .background(.black,in:RoundedRectangle(cornerRadius:10))
            HStack {
                Button("START NAVIGATION") {
                    Task {
                        await navigation.start()
                        if navigation.active { sendModeHUD(1) }
                    }
                }.buttonStyle(.borderedProminent).tint(.mint)
                Button("STOP") { navigation.stop(); sendModeHUD(1) }
                    .buttonStyle(.bordered)
            }
            Toggle("Speak turn-by-turn directions",isOn:$navigation.voiceEnabled)
                .tint(.mint)
            Text(navigation.status).font(.caption).foregroundStyle(.secondary)
            Text(navigation.instruction)
                .font(.system(size:19,weight:.black,design:.rounded))
            HStack {
                Label(navigation.nextTurn,systemImage:"arrow.turn.up.right")
                Spacer()
                Label(navigation.remaining,systemImage:"point.topleft.down.to.point.bottomright.curvepath")
            }.font(.subheadline)
            if let route = navigation.route {
                Map(initialPosition:.region(MKCoordinateRegion(
                    center:navigation.position ?? route.polyline.coordinate,
                    latitudinalMeters:5000,longitudinalMeters:5000))) {
                    MapPolyline(route.polyline).stroke(.mint,lineWidth:5)
                    if let target = navigation.target {
                        Marker("Destination",coordinate:target)
                    }
                    if let position = navigation.position {
                        Marker("You",coordinate:position)
                    }
                }
                .frame(height:210)
                .clipShape(RoundedRectangle(cornerRadius:14))
            }
            Text("Apple Maps routing needs internet. Once you START NAVIGATION, GPS and spoken turns can continue with the screen locked or another app visible. Do not swipe-force-close Jarvis. Audio follows your iPhone Bluetooth output.")

                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(15)
        .background(Color(red:0.035,green:0.08,blue:0.10),in:RoundedRectangle(cornerRadius:18))
    }
    private var handsFreeCard: some View {
        VStack(alignment:.leading,spacing:12) {
            HStack {
                Text("SOLOS • HUD CONTROLS").font(.system(size:19,weight:.black,design:.monospaced))
                    .foregroundStyle(.mint)
                Spacer()
                Circle().fill(accessory.connectedProtocol.isEmpty ? Color.orange : Color.mint)
                    .frame(width:11,height:11)
            }
            Text("MODE \(handsFree.mode + 1) / 5  •  \(SolosHandsFreeEngine.modeNames[handsFree.mode])")
                .font(.system(size:14,weight:.heavy,design:.monospaced))
            let previewMode = Date() < answerShowingUntil && handsFree.mode != 4 ? 5 : handsFree.mode
            let previewMessage: String = {
                switch previewMode {
                case 1:
                    return navigation.nextTurn + "|" + navigation.instruction + "|" + navigation.eta + "|" + navigation.remaining
                case 2: return captionText
                case 3: return translatedText
                case 4: return messagePages[min(currentMessagePage,messagePages.count - 1)]
                case 5: return lensAnswerPage
                default: return lastOledMessage
                }
            }()
            Image(uiImage:SolosProHUD.image(
                mode:previewMode,clock:phone.clock,date:phone.dateLine,
                steps:Int(phone.steps) ?? 0,distance:phone.distance,
                speed:phone.speed,battery:phone.battery,gps:phone.coordinates,
                message:previewMessage,sender:messageSender,
                senderPhoto:messagePhoto,messagePage:currentMessagePage + 1,
                pageCount:messagePages.count))
                .resizable().interpolation(.none)
                .aspectRatio(428.0 / 240.0,contentMode:.fit)
                .clipShape(RoundedRectangle(cornerRadius:11))
                .overlay(RoundedRectangle(cornerRadius:11).stroke(.mint.opacity(0.5),lineWidth:1))
            Text(handsFree.status).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("◀ BACK HUD") { handsFree.previousMode() }
                    .buttonStyle(.borderedProminent).tint(.cyan)
                Button("NEXT HUD ▶") { handsFree.nextMode() }
                    .buttonStyle(.borderedProminent).tint(.mint)
            }
            HStack {
                Button("LEARN NEXT") { handsFree.learn(.next) }.buttonStyle(.bordered)
                Button("LEARN BACK") { handsFree.learn(.back) }.buttonStyle(.bordered)
                Button("LEARN LANG") { handsFree.learn(.language) }.buttonStyle(.bordered)
            }.font(.caption)
            if handsFree.learning {
                Text("LEARNING \(handsFree.learningAction): press that physical button 3 times, about 1 second apart.")
                    .font(.caption.bold()).foregroundStyle(.orange)
            }
            Text("Accessory input: " + accessory.incomingSample)
                .font(.system(size:10,design:.monospaced)).foregroundStyle(.mint.opacity(0.8))
                .textSelection(.enabled)
            Text("NEXT: " + handsFree.learnedDescription(.next))
                .font(.caption2.monospaced()).textSelection(.enabled)
            Text("BACK: " + handsFree.learnedDescription(.back))
                .font(.caption2.monospaced()).textSelection(.enabled)
            Text("LANGUAGE: " + handsFree.learnedDescription(.language))
                .font(.caption2.monospaced()).textSelection(.enabled)
            HStack {
                Text("?? means a changing byte. Different buttons need distinct incoming packets.")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button("RESET HEX") { handsFree.clearLearnedButton() }
                    .font(.caption2.bold()).foregroundStyle(.orange)
            }
            Text("iOS may not expose volume-only presses. The phone BACK/NEXT controls always work.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .padding(16)
        .background(Color(red:0.035,green:0.08,blue:0.10),in:RoundedRectangle(cornerRadius:18))
        .overlay(RoundedRectangle(cornerRadius:18).stroke(.mint.opacity(0.35),lineWidth:1))
    }

    private var captionCard: some View {
        VStack(alignment:.leading,spacing:10) {
            Label("AUTO-START LIVE CAPTIONS",systemImage:"captions.bubble.fill")
                .font(.headline).foregroundStyle(.mint)
            Text("Switch to HUD 3. English captions start listening immediately. Moving away stops the caption mic and restores Hey Jarvis.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("GO TO CAPTIONS HUD") {
                    handsFree.setMode(2,force:true)
                }.buttonStyle(.borderedProminent).tint(.mint)
                if handsFree.mode == 2 {
                    Button("RESTART CAPTIONS") { beginCaptions(mode:2) }.buttonStyle(.bordered)
                }
            }
            Text(captions.status).font(.caption).foregroundStyle(.secondary)
            Text(captionText.isEmpty ? "Listening for speech..." : captionText)
                .font(.title3.weight(.bold))
                .frame(maxWidth:.infinity,alignment:.leading)
                .padding(12)
                .background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
        }.card()
    }

    private var translationCard: some View {
        VStack(alignment:.leading,spacing:11) {
            Label("LIVE SPEECH → ENGLISH",systemImage:"character.book.closed.fill")
                .font(.headline).foregroundStyle(.mint)
            Picker("Spoken language",selection:$sourceLocale) {
                ForEach(sourceOptions.indices,id:\.self) { index in
                    Text(sourceOptions[index].name).tag(sourceOptions[index].code)
                }
            }.pickerStyle(.menu)
            HStack {
                Button("NEXT LANGUAGE") { nextTranslationLanguage() }
                    .buttonStyle(.bordered)
                    .disabled(handsFree.mode != 3)
                Button("GO TO TRANSLATION HUD") {
                    handsFree.setMode(3,force:true)
                }.buttonStyle(.borderedProminent).tint(.mint)
            }
            Text("Source: \(sourceOptions.first(where:{$0.code == sourceLocale})?.name ?? sourceLocale) → English. Apple may ask to download on-device language packs.")
                .font(.caption).foregroundStyle(.secondary)
            Text(translatedText.isEmpty ? "Translated English appears here..." : translatedText)
                .font(.title3.weight(.bold))
                .frame(maxWidth:.infinity,alignment:.leading)
                .padding(12)
                .background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:10))
            if !captionText.isEmpty {
                Text("HEARD: " + captionText).font(.caption).foregroundStyle(.secondary)
            }
        }.card()
    }

    private var messageCard: some View {
        VStack(alignment:.leading,spacing:10) {
            Label("PINNED MESSAGES • CONTACT + PHOTO",systemImage:"message.fill")
                .font(.headline).foregroundStyle(.mint)
            Text("Shows a full message on the actual 428×240 lens, cycling long messages across pages until you press NEXT or BACK HUD. It cannot read iMessage notifications by itself.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                if let image = messagePhoto {
                    Image(uiImage:image).resizable().scaledToFill()
                        .frame(width:52,height:52).clipShape(RoundedRectangle(cornerRadius:11))
                } else {
                    Image(systemName:"person.crop.circle.fill")
                        .resizable().frame(width:47,height:47).foregroundStyle(.mint)
                }
                TextField("Sender contact name",text:$messageSender)
                    .textInputAutocapitalization(.words)
                Button("CHOOSE CONTACT") { showContactPicker = true }
                    .buttonStyle(.bordered)
            }
            TextEditor(text:$messageBody)
                .frame(height:85)
                .scrollContentBackground(.hidden).padding(6)
                .background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:10))
            HStack {
                Button("PASTE MESSAGE") {
                    messageBody = UIPasteboard.general.string ?? ""
                }.buttonStyle(.bordered)
                Button("PIN TO GLASSES") { pinCurrentMessage() }
                    .buttonStyle(.borderedProminent).tint(.mint)
            }
            HStack {
                Button("NEXT MESSAGE PAGE") {
                    guard handsFree.mode == 4 else { return }
                    currentMessagePage = (currentMessagePage + 1) % messagePages.count
                    sendModeHUD(4)
                }.buttonStyle(.bordered)
                Button("ALLOW CONTACT PHOTOS") { requestContactsPermission() }
                    .buttonStyle(.bordered)
            }.font(.caption)
            if !contactsStatus.isEmpty {
                Text(contactsStatus).font(.caption).foregroundStyle(.secondary)
            }
            Text("Shortcuts bridge: Open URLs with solosjarvis://message?from=CONTACT&body=MESSAGE, URL-encoding both values. A Message automation can supply sender and message variables. Automation/locked-screen behavior depends on iOS.")
                .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }.card()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("SOLOS  /  iPHONE")
                .font(.system(.title2, design: .monospaced).bold())
                .foregroundStyle(.mint)
            Text("V21: Back button • Instant captions • English translations • Pinned messages")
                .font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.vertical, 10)
    }
}

struct SolosAccessoryCard: View {
    @ObservedObject var manager: SolosClassicManager
    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("DIRECT GLASSES CONNECTION")
                .font(.headline).foregroundStyle(.mint)
            Text(manager.status).font(.caption)
            HStack {
                Button("PAIR / FIND ACCESSORY") { manager.openPicker() }.buttonStyle(.bordered)
                Button("REFRESH") { manager.refresh() }.buttonStyle(.bordered)
            }
            if manager.accessories.isEmpty {
                Text("No Apple External Accessory detected. If glasses connect only by RFCOMM, stock iOS cannot use that display channel.")
                    .font(.caption).foregroundStyle(.orange)
            }
            ForEach(manager.accessories) { item in
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.name).font(.subheadline.bold())
                    Text("Maker: \(item.manufacturer)").font(.caption)
                    Text("Protocols: " + (item.protocols.isEmpty ? "none" : item.protocols.joined(separator: ", ")))
                        .font(.caption.monospaced()).textSelection(.enabled)
                    ForEach(item.protocols, id: \.self) { proto in
                        Button("CONNECT: \(proto)") {
                            manager.connect(accessoryID: item.id, protocolString: proto)
                        }
                        .buttonStyle(.borderedProminent).tint(.mint)
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
            }
            Text("Declared experimental protocols: \(manager.declaredProtocols.joined(separator: ", ")). Matching values alone do not bypass manufacturer authorization.")
                .font(.caption2).foregroundStyle(.secondary).textSelection(.enabled)
        }.card()
    }
}

private struct CardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(red: 0.065, green: 0.12, blue: 0.15), in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).stroke(.mint.opacity(0.15), lineWidth: 1))
    }
}
extension View {
    fileprivate func card() -> some View { modifier(CardModifier()) }
}
