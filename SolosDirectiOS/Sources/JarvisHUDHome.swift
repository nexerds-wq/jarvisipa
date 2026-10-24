import SwiftUI
import Translation
import UserNotifications
import HealthKit
import Combine
import Contacts

/// HUD-first controller. The iPhone is a remote and a live preview; the
/// glasses receive identical 428x240 image frames only if iOS exposes an
/// authorized ExternalAccessory stream for the display.
struct JarvisHUDHome: View {
    @ObservedObject var phone: SolosPhoneController
    @ObservedObject private var accessory: SolosClassicManager
    @StateObject private var handsFree = SolosHandsFreeEngine()
    @StateObject private var captions = OfflineCaptionService()
    @StateObject private var navigation = SolosNavigationEngine()
    @StateObject private var music = JarvisAppleMusic()
    @StateObject private var weatherGuardian = JarvisWeatherGuardian()
    @StateObject private var smartTasks = JarvisSmartTasks()
    @State private var smartTaskTitle = ""
    @State private var smartTaskMinutes = 10
    @State private var smartTaskKind = "reminder"
    private let health = HKHealthStore()

    @Environment(\.scenePhase) private var scenePhase
    @State private var mode = 0
    @State private var image: UIImage?
    @State private var lastFrameAt = Date.distantPast
    @State private var captionFlushWork: DispatchWorkItem?
    @State private var translationDebounceWork: DispatchWorkItem?
    @State private var translationSessionReady = false
    @State private var lastVoiceHUDCommand = ""
    @State private var hudSleeping = false
    @State private var hudQuitRequested = false
    @State private var lifecycleStatus = ""
    @AppStorage("jarvisListenWhileMusic") private var listenWhileMusic = true
    @AppStorage("jarvisMediaButtonsForHUD") private var mediaButtonsForHUD = false
    @State private var captionWakeWork: DispatchWorkItem?
    @State private var lastCaptionWakeCommand = ""
    @State private var lastCaptionWakeAt = Date.distantPast
    @State private var heard = ""
    @State private var translated = ""
    @State private var translationConfiguration: TranslationSession.Configuration?
    @State private var translationContinuation: AsyncStream<String>.Continuation?
    @State private var translationPending = ""
    @State private var translationStatus = "Choose TRANSLATE HUD"
    @State private var language = "es-ES"
    @State private var answer = "Say Hey Jarvis or ask a question."
    @State private var question = ""
    @State private var musicQuery = ""
    @State private var musicOnHUD = false
    @State private var sender = "MESSAGE"
    @State private var message = ""
    @State private var senderPhoto: UIImage?
    @State private var messagePages = ["NO MESSAGE YET"]
    @State private var currentMessagePage = 0
    @State private var lastMessagePageAt = Date.distantPast
    @State private var messageRelayStatus = "Use Shortcuts → Show Jarvis Message for incoming texts"
    @State private var lastMessageID = ""
    @State private var showContactPicker = false
    @State private var heartRate = "—"
    @State private var reminderText = ""
    @State private var remindAt = Date().addingTimeInterval(3600)
    @State private var reminderStatus = ""
    @State private var timerMinutes = 5
    @State private var timerEnd: Date?
    @State private var timerStatus = ""
    @State private var online = false
    @State private var ollamaServer = "http://192.168.1.10:11434"
    @State private var ollamaModel = "llama3.2"
    @State private var ollamaKey = ""
    @State private var serperKey = ""
    @State private var aiBusy = false
    @AppStorage("jarvisCompanionEnabled") private var companionEnabled = true
    @AppStorage("jarvisCompanionAutoSupport") private var companionAutoSupport = false
    @AppStorage("jarvisCompanionSpeak") private var companionSpeak = true
    @AppStorage("jarvisCompanionStyle") private var companionStyle = "FRIDAY"
    @AppStorage("jarvisCompanionSoundCues") private var companionSoundCues = false
    @StateObject private var emotionCues = JarvisEmotionCues()
    @AppStorage("jarvisCompanionMemoryEnabled") private var companionMemoryEnabled = true
    @AppStorage("jarvisCompanionNotes") private var companionNotes = ""
    @AppStorage("jarvisCompanionTurnTaking") private var companionTurnTaking = true
    @AppStorage("jarvisCompanionFollowUpSeconds") private var companionFollowUpSeconds = 35.0
    @State private var companionConversationUntil = Date.distantPast
    @State private var companionLastTranscript = ""
    @State private var companionQuiet = false
    @State private var companionHistory = [[String:String]]()
    @State private var companionNoteDraft = ""
    @State private var companionInput = ""
    @State private var companionReply = "I'm here when you want to talk."
    @State private var companionStatus = "Off until enabled"
    @State private var companionBusy = false
    @State private var companionLastResponse = Date.distantPast
    @State private var showConnection = false
    @State private var showSettings = false
    @State private var showHUDTools = false
    @State private var showMemoryControls = false
    @State private var jarvisSpeaking = false
    @AppStorage("hudVisionBrightness") private var hudBrightness = 1.0
    @AppStorage("hudVisionContrast") private var hudContrast = 1.3
    @AppStorage("hudVisionSharpness") private var hudSharpness = 0.25
    @AppStorage("hudVisionTextScale") private var hudTextScale = 1.12
    @AppStorage("hudVisionBold") private var hudBold = true
    @AppStorage("hudVisionHighVisibility") private var hudHighVisibility = false
    @AppStorage("hudVisionDirectional") private var hudDirectional = 0
    @AppStorage("hudVisionRxAxisStrength") private var hudRxAxisStrength = 0.0
    @State private var visionWizardPresented = false
    @AppStorage("hudHardwareBrightnessPreference") private var hardwareBrightnessPreference = 2
    @AppStorage("hudVisionActiveEye") private var hudActiveEye = "OD"
    @State private var rightPrescriptionActivated = false
    @State private var visionDiagnosticActive = false
    @AppStorage("jarvisAllowOnlineSpeech") private var allowOnlineRecognition = false
    @AppStorage("jarvisPreferPhoneMicrophone") private var preferPhoneMicrophone = false
    @AppStorage("jarvisMicrophoneSource") private var microphoneSource = "bluetooth"
    @State private var speakReplies = true
    @AppStorage("jarvisLockScreenWake") private var keepJarvisListening = true
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    private let names = ["DASHBOARD","NAVIGATION","CAPTIONS","TRANSLATE","MESSAGES","JARVIS","TIMERS"]
    private let availableHUDModes = [0,5]
    private let locales: [(String,String)] = [
        ("es-ES","Spanish"),("fr-FR","French"),("de-DE","German"),
        ("it-IT","Italian"),("pt-BR","Portuguese"),("ja-JP","Japanese"),
        ("ko-KR","Korean"),("zh-CN","Chinese"),("en-US","English")
    ]

    init(phone: SolosPhoneController) {
        self.phone = phone
        self._accessory = ObservedObject(wrappedValue: phone.accessory)
    }

    private var mainLayout: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading, spacing:14) {
                    header
                    weatherAlertStrip
                    jarvisPanel
                    preview
                    hudNavigationButtons
                    hudToolDisclosure
                    advancedPanels
                }
                .padding(15)
            }
            .background(Color.black)
            .navigationTitle("JARVIS")
            .toolbar {
                ToolbarItem(placement:.topBarTrailing) {
                    Button(showSettings ? "Done" : "Advanced") { showSettings.toggle() }
                }
            }
        }
        .overlay {
            JarvisVoiceBorder(level:phone.microphoneLevel,
                              speaking:phone.jarvisVoiceActive,
                              listening:phone.listening)
                .ignoresSafeArea()
                .allowsHitTesting(false)
                .accessibilityHidden(true)
        }
    }

    @ViewBuilder private var weatherAlertStrip: some View {
        if !weatherGuardian.banner.isEmpty {
            Text(weatherGuardian.banner).font(.caption.bold())
                .foregroundStyle(.red)
        }
    }

    private var hudNavigationButtons: some View {
        HStack(spacing:12) {
            Button("◀ BACK") { handsFree.setMode(mode == 0 ? 5 : 0,force:true) }
            Spacer()
            Text(mode == 0 ? "DASHBOARD" : "JARVIS AI").font(.caption.monospaced()).foregroundStyle(.secondary)
            Spacer()
            Button("NEXT ▶") { handsFree.setMode(mode == 0 ? 5 : 0,force:true) }
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
    }

    private var hudToolDisclosure: some View {
        DisclosureGroup("HUD TOOLS · " + names[mode],isExpanded:$showHUDTools) {
            hudModePicker
            if hudSleeping {
                Text(lifecycleStatus).font(.caption)
                Button("WAKE JARVIS") { wakeJarvis() }
            } else {
                modeControls
            }
        }
        .font(.subheadline)
        .padding(11)
        .background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:12))
    }

    private var hudModePicker: some View {
        ScrollView(.horizontal,showsIndicators:false) {
            HStack(spacing:8) {
                ForEach(availableHUDModes,id:\.self) { index in
                    Button(names[index]) { handsFree.setMode(index,force:true) }
                        .font(.caption.bold())
                        .padding(.horizontal,11).padding(.vertical,9)
                        .background(mode == index ? Color.green.opacity(0.28) : Color.white.opacity(0.08),
                                    in:RoundedRectangle(cornerRadius:9))
                        .foregroundStyle(.white)
                }
            }
        }
    }

    @ViewBuilder private var advancedPanels: some View {
        if showConnection { connectionPanel }
        if showSettings {
            section("CONNECTION") {
                Text(accessory.status).font(.caption)
                Button("CONNECT / DIAGNOSE") { showConnection = true; accessory.refresh() }
            }
            visionPanel
            visionCalibrationPanel
            settingsPanel
        }
        Text("Glasses display requires an authorized accessory connection; Bluetooth audio pairing alone does not provide HUD access.")
            .font(.caption2).foregroundStyle(.orange)
    }

    private var hudWithLifecycle: some View {
        mainLayout
        .preferredColorScheme(.dark)
        .onAppear {
            handsFree.onModeChange = { newMode in selectMode(newMode) }
            phone.onHUDVoiceCommand = { spoken in routeVoiceHUDCommand(spoken,wakeAlreadyVerified:true) }
            accessory.onAccessoryPacket = { data in handsFree.input(data) }
            accessory.onSpeechCompleted = {
                DispatchQueue.main.async {
                    guard jarvisSpeaking else { return }
                    jarvisSpeaking = false
                    if mode == 2 && !companionQuiet {
                        DispatchQueue.main.asyncAfter(deadline:.now() + 0.35) {
                            if mode == 2 && !jarvisSpeaking && !companionQuiet { startCaptioning() }
                        }
                    }
                }
            }
            if mediaButtonsForHUD { handsFree.enableMediaButtons() }
            accessory.refresh()
            phone.refreshSensors()
            weatherGuardian.start()
            if companionEnabled && companionSoundCues { emotionCues.start() }
            requestHeartRate()
            if keepJarvisListening { phone.startListening() }
            selectMode(0)
            restorePinnedMessageIfNeeded()
            consumeShortcutMessage()
        }
        .onOpenURL { url in acceptIncomingMessageURL(url) }
        .onChange(of:keepJarvisListening) { _, enabled in
            if enabled && !hudQuitRequested { phone.startListening() }
            else { phone.stopListening() }
        }
        .onChange(of:scenePhase) { _, phase in
            if phase == .active {
                if (mode == 2 || mode == 3) && !captions.isListening {
                    startCaptioning()
                } else if keepJarvisListening && mode != 2 && mode != 3 {
                    phone.resumeAfterScreenUnlock()
                }
            }
        }
        .onChange(of:mediaButtonsForHUD) { _, enabled in
            if enabled { handsFree.enableMediaButtons() }
            else { handsFree.stop() }
        }
        .onChange(of:listenWhileMusic) { _, enabled in
            if enabled && keepJarvisListening { phone.startListening() }
            else if !enabled && musicOnHUD { phone.setMusicPlaybackActive(true) }
        }
        .onReceive(NotificationCenter.default.publisher(for: Notification.Name("SolosJarvisIncomingMessage"))) { _ in
            consumeShortcutMessage()
        }
        .sheet(isPresented: $showContactPicker) {
            SolosMessageContactPicker { name, photo in
                sender = name
                senderPhoto = photo
            }
        }
        .sheet(isPresented:$visionWizardPresented,onDismiss:{ drawHUD() }) {
            JarvisVisionCalibrationWizard(accessory:accessory)
        }
        .onDisappear {
            // A lock/background transition must not dismantle active caption
            // capture or the HUD connection. iOS owns final suspension policy.
            guard UIApplication.shared.applicationState == .active else { return }
            phone.onHUDVoiceCommand = nil
            accessory.onSpeechCompleted = nil
            handsFree.stop()
            captionWakeWork?.cancel()
            captionFlushWork?.cancel()
            translationDebounceWork?.cancel()
            captions.stop()
            weatherGuardian.stop()
            emotionCues.stop()
            translationContinuation?.finish()
            translationContinuation = nil
            phone.setHUDCaptionsActive(false)
        }
    }

    private var hudWithObservedState: some View {
        hudWithLifecycle
        .onChange(of: captions.partial) { _, text in
            guard mode == 2 || mode == 3, !text.isEmpty else { return }
            if handleCaptionWakePhrase(text,isFinal:false) { return }
            if routeVoiceHUDCommand(text,allowMusic:false,allowSystem:false) { return }
            heard = text
            if mode == 2 {
                // The first partial is quick; a trailing frame MUST still
                // deliver "hey how are you" after "hey" was sent earlier.
                drawHUD(throttled:true)
                scheduleCaptionFlush(text)
            } else {
                queueTranslation(text)
            }
        }
        .onChange(of: captions.latestFinal) { _, text in
            guard mode == 2 || mode == 3, !text.isEmpty else { return }
            if handleCaptionWakePhrase(text,isFinal:true) { return }
            considerCompanionTranscript(text)
            if routeVoiceHUDCommand(text) { return }
            heard = text
            if mode == 2 {
                captionFlushWork?.cancel()
                drawHUD()
            } else {
                queueTranslation(text, final:true)
            }
        }
        .onChange(of: allowOnlineRecognition) { _, _ in
            if mode == 2 || mode == 3 { startCaptioning() }
        }
        .onChange(of: preferPhoneMicrophone) { _, _ in
            if mode == 2 || mode == 3 { startCaptioning() }
        }
        .onChange(of: navigation.instruction) { _, _ in
            if mode == 1 { drawHUD(throttled:true) }
        }
        .onChange(of: phone.aiAnswer) { _, text in
            guard !online else { return }
            musicOnHUD = false
            answer = text
            if mode != 5 { handsFree.setMode(5,force:true) }
            drawHUD(throttled:true)
        }
        .onChange(of: music.status) { _, status in
            if musicOnHUD {
                answer = status
                if mode == 5 { drawHUD() }
            }
            let failed = ["didn't start","No saved copy","Couldn't play",
                          "Music library access unavailable","Allow Media",
                          "No matching song","catalog playback isn't enabled"]
            if failed.contains(where:status.contains) {
                phone.setMusicPlaybackActive(false)
            }
        }
        .onChange(of:weatherGuardian.banner) { _,_ in drawHUD() }
        .onChange(of:companionEnabled) { _,_ in syncEmotionCues() }
        .onChange(of:companionSoundCues) { _,_ in syncEmotionCues() }
        .onReceive(ticker) { now in
            if hudSleeping { return }
            if mode == 0 || !smartTasks.pinned.isEmpty { drawHUD(throttled:true) }
            if mode == 4 && messagePages.count > 1 && now.timeIntervalSince(lastMessagePageAt) >= 7 {
                currentMessagePage = (currentMessagePage + 1) % messagePages.count
                lastMessagePageAt = now
                drawHUD()
            }
            if false && mode == 6 {
                if let end = timerEnd, now >= end {
                    timerEnd = nil
                    timerStatus = "Timer finished!"
                    notify(title:"Jarvis Timer", body:"Your timer has finished", after:1)
                }
                drawHUD(throttled:true)
            }
        }
    }

    var body: some View {
        hudWithObservedState
        .translationTask(translationConfiguration) { session in
            let channel = AsyncStream<String>.makeStream(bufferingPolicy:.bufferingNewest(1))
            await MainActor.run {
                translationContinuation?.finish()
                translationContinuation = channel.continuation
                translationSessionReady = false
                translationStatus = "Preparing Apple Spanish → English translation models..."
            }
            do {
                try await session.prepareTranslation()
                await MainActor.run {
                    guard mode == 3 else { return }
                    translationSessionReady = true
                    translationStatus = "Translator ready • listening for full Spanish phrases"
                    // If Speech heard someone while the language pack loaded,
                    // immediately translate the most recent sentence.
                    if !translationPending.isEmpty {
                        channel.continuation.yield(translationPending)
                    }
                }
                for await original in channel.stream {
                    guard !Task.isCancelled else { break }
                    do {
                        let result = try await session.translate(original)
                        await MainActor.run {
                            guard mode == 3, original == translationPending else { return }
                            let english = result.targetText.trimmingCharacters(in:.whitespacesAndNewlines)
                            guard !english.isEmpty else { return }
                            translated = english
                            translationStatus = "Translated • \(language) → English"
                            drawHUD()
                        }
                    } catch {
                        await MainActor.run {
                            guard mode == 3 else { return }
                            translationStatus = "Translation failed: " + error.localizedDescription
                        }
                    }
                }
            } catch {
                await MainActor.run {
                    guard mode == 3 else { return }
                    translationSessionReady = false
                    translationStatus = "Download Spanish and English in Apple Translate, then tap Retry: " + error.localizedDescription
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing:9) {
            Image(systemName:"eyeglasses").font(.title2)
            VStack(alignment:.leading,spacing:2) {
                Text("SOLOS  /  JARVIS").font(.headline.monospaced()).foregroundStyle(.green)
                Text(lastVoiceHUDCommand.isEmpty ? "HUD FIRST • NO EFFECTS" : lastVoiceHUDCommand)
                    .font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Circle().fill(accessory.connectedProtocol.isEmpty ? .orange : .green).frame(width:11,height:11)
        }
    }

    private var preview: some View {
        VStack(alignment:.leading,spacing:8) {
            HStack {
                Text("GLASSES DISPLAY 428 × 240").font(.caption.bold()).foregroundStyle(.green)
                Spacer()
                Text(names[mode]).font(.caption.monospaced())
            }
            Group {
                if let image {
                    Image(uiImage:image).resizable().aspectRatio(contentMode:.fit)
                } else {
                    Rectangle().fill(.black).overlay(Text("HUD PREVIEW").foregroundStyle(.green))
                }
            }
            .aspectRatio(428.0/240.0,contentMode:.fit)
            .clipShape(RoundedRectangle(cornerRadius:6))
            .overlay(RoundedRectangle(cornerRadius:6).stroke(.green.opacity(0.4)))
            HStack {
                Text(accessory.connectedProtocol.isEmpty ? "PREVIEW ONLY • NO DISPLAY CONNECTION" : "ACCESSORY SESSION ACTIVE")
                    .font(.caption2.bold())
                    .foregroundStyle(accessory.connectedProtocol.isEmpty ? .orange : .green)
                Spacer()
                Button("SEND NOW") { drawHUD() }.font(.caption.bold())
            }
        }.padding(12).background(.white.opacity(0.06),in:RoundedRectangle(cornerRadius:12))
    }

    @ViewBuilder
    private var modeControls: some View {
        switch mode {
        case 0:
            section("TIME • STEPS • DISTANCE") {
                Text(phone.clock + "  •  " + phone.dateLine).font(.title3.bold())
                Text("Steps: " + phone.steps + "   Distance: " + phone.distance)
                Text("Heart rate: " + heartRate + " bpm (Apple Health, if available)")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Refresh activity + heart rate") {
                    phone.refreshSensors()
                    requestHeartRate()
                    drawHUD()
                }.buttonStyle(.bordered)
            }
        case 1:
            section("NAVIGATION") {
                TextField("Where to?",text:$navigation.address).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Start route") {
                        Task { await navigation.start(); drawHUD() }
                    }
                    Button("Stop route") { navigation.stop(); drawHUD() }
                }.buttonStyle(.borderedProminent)
                Text(navigation.instruction).font(.headline)
                Text(navigation.status).font(.caption).foregroundStyle(.secondary)
                Text(phone.coordinates).font(.caption.monospaced()).foregroundStyle(.secondary)
            }
        case 2:
            section("LIVE CAPTIONS") {
                Text(captions.status).font(.caption).foregroundStyle(.secondary)
                Text("Mic: " + captions.microphoneRoute).font(.caption2).foregroundStyle(.secondary)
                Text(heard.isEmpty ? "Listening..." : heard).font(.title3)
                HStack {
                    Button("Restart captions") { startCaptioning() }
                    Button("Stop") { captions.stop() }
                }.buttonStyle(.bordered)
            }
        case 3:
            section("TRANSLATE TO ENGLISH") {
                Picker("Spoken language",selection:$language) {
                    ForEach(locales.indices,id:\.self) { index in Text(locales[index].1).tag(locales[index].0) }
                }.onChange(of:language) { _, _ in startCaptioning() }
                Text(captions.status).font(.caption2).foregroundStyle(.secondary)
                Text("Mic: " + captions.microphoneRoute).font(.caption2).foregroundStyle(.secondary)
                Text(translationStatus).font(.caption).foregroundStyle(.orange)
                Text("Spanish heard: " + (heard.isEmpty ? "Waiting for speech..." : heard)).font(.caption)
                Text(translated.isEmpty ? "English translation will appear here" : translated).font(.title3.bold())
                Toggle("Improve Spanish speech using online recognition",isOn:$allowOnlineRecognition)
                    .font(.caption)
                Toggle("Use iPhone microphone for people farther away",isOn:$preferPhoneMicrophone)
                    .font(.caption)
                Button("Retry / download translation models") {
                    startCaptioning()
                    translationConfiguration?.invalidate()
                }.buttonStyle(.bordered)
            }
        case 4:
            section("PIN A MESSAGE TO HUD") {
                HStack {
                    if let photo = senderPhoto {
                        Image(uiImage: photo).resizable().scaledToFill()
                            .frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 9))
                    }
                    TextField("Sender name",text:$sender).textFieldStyle(.roundedBorder)
                    Button("Contact") { showContactPicker = true }.buttonStyle(.bordered)
                }
                TextField("Message",text:$message,axis:.vertical).lineLimit(2...5).textFieldStyle(.roundedBorder)
                HStack {
                    Button("Paste") { message = UIPasteboard.general.string ?? "" }
                    Button("Pin to HUD") { pinMessage(sender: sender, body: message) }
                }.buttonStyle(.borderedProminent)
                if messagePages.count > 1 {
                    Button("NEXT MESSAGE PAGE  \(currentMessagePage + 1)/\(messagePages.count)") {
                        currentMessagePage = (currentMessagePage + 1) % messagePages.count
                        lastMessagePageAt = Date()
                        drawHUD()
                    }.buttonStyle(.bordered)
                }
                Text(messageRelayStatus).font(.caption2).foregroundStyle(.green)
                Text("For incoming iMessages, create a Shortcuts → Automation → Message trigger, then use the Show Jarvis Message action with Sender and Message. iOS does not allow automatic reading of all Messages.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        case 5:
            section("JARVIS • HUD CHAT") {
                Text("Talk to the same Jarvis at the top of the app. Its reply appears here and on your glasses when connected.")
                    .font(.caption).foregroundStyle(.secondary)
                Text(aiBusy ? "Thinking..." : answer).font(.body)
                Text("Say Hey Jarvis, then ask a question. The answer appears on your glasses and is spoken aloud.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            section("APPLE MUSIC • VOICE PLAYBACK") {
                Text("Say: Hey Jarvis, play Blinding Lights by The Weeknd")
                    .font(.caption).foregroundStyle(.secondary)
                TextField("Song title and artist",text:$musicQuery)
                    .textFieldStyle(.roundedBorder)
                Button("Play requested song") {
                    handleMusicCommand(.play(musicQuery))
                }.buttonStyle(.borderedProminent).disabled(music.isBusy)
                HStack(spacing:12) {
                    Button("Pause") { handleMusicCommand(.pause) }
                    Button("Resume") { handleMusicCommand(.resume) }
                    Button("Next") { handleMusicCommand(.next) }
                    Button("Back") { handleMusicCommand(.previous) }
                }.buttonStyle(.bordered)
                Text(music.status).font(.caption).foregroundStyle(.green)
                if music.searchURL != nil {
                    Button("OPEN IN APPLE MUSIC • SEARCH FULL CATALOG") {
                        music.openSearchInMusic()
                    }
                    .buttonStyle(.borderedProminent)
                }
                Text("Searches the full Apple Music catalog by song name using public song IDs. Attempts direct playback with your Apple Music subscription — without MusicKit developer tokens. If unavailable, tries your library and offers Open in Apple Music.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        default:
            section("TIMERS • REMINDERS") {
                Stepper("Timer: \(timerMinutes) minutes",value:$timerMinutes,in:1...180)
                HStack {
                    Button("Start timer") {
                        timerEnd = Date().addingTimeInterval(TimeInterval(timerMinutes * 60))
                        timerStatus = "Timer started"
                        drawHUD()
                    }
                    Button("Cancel timer") { timerEnd = nil; timerStatus = "Timer canceled"; drawHUD() }
                }.buttonStyle(.bordered)
                Text(timerEnd.map { "Remaining: " + formatRemaining($0) } ?? timerStatus)
                Divider()
                TextField("Reminder",text:$reminderText).textFieldStyle(.roundedBorder)
                DatePicker("Remind me",selection:$remindAt,in:Date()...,displayedComponents:[.date,.hourAndMinute])
                Button("Schedule reminder") { scheduleReminder() }.buttonStyle(.borderedProminent)
                Text(reminderStatus).font(.caption).foregroundStyle(.secondary)
                Text("Alarms use local notifications, not the built-in Clock app. Delivery depends on iOS notification settings.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var connectionSummary: some View {
        section("GLASSES CONNECTION") {
            Text(accessory.status).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("PAIR / CONNECT") { showConnection.toggle(); accessory.refresh() }
                Button("SCAN BLE") { phone.scanBLE(); showConnection = true }
            }.buttonStyle(.bordered)
            if !phone.discoveredBLE.isEmpty {
                Text("Nearby BLE: " + phone.discoveredBLE.prefix(5).joined(separator:", "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private var connectionPanel: some View {
        section("AUTHORIZED ACCESSORIES") {
            Text("A detected device is not proof that iOS can transmit HUD image packets.")
                .font(.caption).foregroundStyle(.orange)
            Button("Open iOS accessory pairing") { accessory.openPicker() }.buttonStyle(.bordered)
            Button("Refresh") { accessory.refresh() }.buttonStyle(.bordered)
            ForEach(accessory.accessories) { item in
                Text(item.name).font(.headline)
                Text(item.protocols.joined(separator:", ")).font(.caption).textSelection(.enabled)
                ForEach(item.protocols,id:\.self) { proto in
                    Button("Connect " + proto) {
                        accessory.connect(accessoryID:item.id,protocolString:proto)
                    }.buttonStyle(.borderedProminent)
                }
            }
            if accessory.accessories.isEmpty {
                Text("No supported Apple External Accessory is exposed. Glasses audio pairing alone won't enable the display.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("Learn NEXT") { handsFree.learn(.next) }
                Button("Learn BACK") { handsFree.learn(.back) }
                Button("Learn LANG") { handsFree.learn(.language) }
            }.font(.caption).buttonStyle(.bordered)
            Text(handsFree.status).font(.caption2)
            Text("Accessory packets: \(handsFree.accessoryPacketCount). " + handsFree.lastMatchedControl)
                .font(.caption2)
        }
    }

    private var visionPanel: some View {
        section("HUD DISPLAY TUNING • 428 × 240") {
            Button("MATCH MY IPHONE • CLEAR TEXT PRESET") {
                // Match the phone's high-legibility rendering style, not its
                // physical luminance: the Widescreen OLED has different optics.
                hudBrightness = 1.0
                hudContrast = 1.55
                hudSharpness = 0.0
                hudTextScale = 1.45
                hudBold = true
                hudHighVisibility = false
                hudDirectional = 0
                drawHUD()
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            Text("iPhone-style: bright white, large bold type on pure black, without sharpening halos. Solos cannot match the iPhone's actual nits, pixel density, or autofocus.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("SOLOS WIDESCREEN • REAL DISPLAY BRIGHTNESS")
                .font(.caption.bold()).foregroundStyle(.green)
            Picker("Hardware brightness preference",selection:$hardwareBrightnessPreference) {
                Text("Low").tag(0)
                Text("Medium").tag(1)
                Text("High").tag(2)
                Text("Auto").tag(3)
            }.pickerStyle(.segmented)
            Text("Saved preference only: this app does NOT transmit a hardware brightness command until the original Widescreen command is verified. Set the actual level in the official Solos app under Settings → Devices → Headset Brightness.")
                .font(.caption2).foregroundStyle(.orange)
            Text("Adjust the actual glasses frame. The preview updates as you move each slider.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Pixel brightness (not hardware OLED power): \(Int(hudBrightness * 100))%")
            Slider(value:$hudBrightness,in:0.35...1.7,step:0.05)
            Text("Contrast: \(Int(hudContrast * 100))%")
            Slider(value:$hudContrast,in:0.7...2.3,step:0.05)
            Text("Sharpening: \(Int(hudSharpness * 100))%")
            Slider(value:$hudSharpness,in:0...1.4,step:0.05)
            Text("Text size: \(Int(hudTextScale * 100))%")
            Slider(value:$hudTextScale,in:0.85...1.55,step:0.05)
            Toggle("Extra bold letters",isOn:$hudBold)
            Toggle("Maximum visibility • yellow/white on black",isOn:$hudHighVisibility)
            HStack {
                Button("MAX READABILITY") {
                    hudBrightness = 1.0
                    hudContrast = 1.65
                    hudSharpness = 0.08
                    hudTextScale = 1.42
                    hudBold = true
                    hudHighVisibility = false
                    hudDirectional = 0
                }.buttonStyle(.borderedProminent)
                Button("RESET") {
                    hudBrightness = 1
                    hudContrast = 1.3
                    hudSharpness = 0.25
                    hudTextScale = 1.12
                    hudBold = true
                    hudHighVisibility = false
                    hudDirectional = 0
                }.buttonStyle(.bordered)
            }
            Text("Bigger text shows fewer words per page. HUD brightness cannot exceed the optical hardware limit.")
                .font(.caption2).foregroundStyle(.secondary)
        }
        .onChange(of:hudBrightness) { _,_ in drawHUD() }
        .onChange(of:hudContrast) { _,_ in drawHUD() }
        .onChange(of:hudSharpness) { _,_ in drawHUD() }
        .onChange(of:hudTextScale) { _,_ in drawHUD() }
        .onChange(of:hudBold) { _,_ in drawHUD() }
        .onChange(of:hudHighVisibility) { _,_ in drawHUD() }
    }

    private var visionCalibrationPanel: some View {
        section("VISION CALIBRATION • THROUGH THE GLASSES") {
            Text("Scientific A/B comparison: sample letters, glare/contrast, and horizontal/vertical edge clarity. The app sends real 428×240 test frames to the accessory session.")
                .font(.caption)
            Text("Active eye preset: \(hudActiveEye). Only the eye viewing the monocular HUD uses this preset.")
            Text("YOUR RIGHT-EYE RX: −2.00 SPH / −4.50 CYL × 15°")
                .font(.caption.bold()).foregroundStyle(.yellow)
            Button("APPLY MY RIGHT-EYE READABILITY PROFILE") {
                let profile = JarvisVisionProfileStorage.read(.right) ??
                    JarvisVisionProfile.prescriptionStartingPoint(.right)
                JarvisVisionProfileStorage.activate(profile,eye:.right)
                hudActiveEye = "OD"
                hudRxAxisStrength = 0.35
                rightPrescriptionActivated = true
                drawHUD()
            }.buttonStyle(.borderedProminent)
            if rightPrescriptionActivated {
                Text("Right-eye readability settings applied. This changes pixels and text, not optical prescription power.")
                    .font(.caption2).foregroundStyle(.green)
            }
            Text("RX-AXIS IMAGE FILTER • \(hudActiveEye == "OD" ? "15° RIGHT EYE" : "160° LEFT EYE")")
                .font(.caption.bold()).foregroundStyle(.yellow)
            Text("Experimental axis-aligned letter-edge filter strength: \(Int(hudRxAxisStrength * 100))%")
                .font(.caption)
            Slider(value:$hudRxAxisStrength,in:0...1,step:0.05)
                .onChange(of:hudRxAxisStrength) { _,_ in drawHUD() }
            HStack {
                Button("RX FILTER OFF") {
                    hudRxAxisStrength = 0
                    drawHUD()
                }.buttonStyle(.bordered)
                Button("TRY RIGHT-EYE 15°") {
                    hudActiveEye = "OD"
                    hudRxAxisStrength = 0.35
                    drawHUD()
                }.buttonStyle(.borderedProminent)
            }
            Text("The filter samples pixels along your actual prescription axis. It is experimental, not optical sphere/cylinder correction; compare OFF versus ON through your glasses.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("VERIFY THE GLASSES REALLY RECEIVE A NEW FRAME")
                .font(.caption.bold()).foregroundStyle(.green)
            HStack {
                Button("SHOW HUGE HUD TEST") {
                    visionDiagnosticActive = true
                    sendVisionDiagnostic()
                }.buttonStyle(.borderedProminent)
                Button("RESTORE NORMAL HUD") {
                    visionDiagnosticActive = false
                    drawHUD()
                }.buttonStyle(.bordered)
            }
            Text("The HUD should show giant 'RX TEST' letters instead of the normal dashboard. If only the iPhone preview changes, this is a display transmission problem, not an eyesight filter problem.")
                .font(.caption2).foregroundStyle(.secondary)
            Button("START VISION CALIBRATION WIZARD") {
                visionWizardPresented = true
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            Picker("Manual directional edge enhancement",selection:$hudDirectional) {
                Text("Off").tag(0)
                Text("Horizontal").tag(1)
                Text("Vertical").tag(2)
                Text("Both").tag(3)
            }
            .pickerStyle(.menu)
            .onChange(of:hudDirectional) { _,_ in drawHUD() }
            Text("A test result is saved only when you tap Save. No software can change optical focus, correct astigmatism, or provide additional hardware display pixels.")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var jarvisPanel: some View {
        section("JARVIS • YOUR AI") {
            HStack(spacing:8) {
                Circle().fill(companionBusy ? .orange : .green)
                    .frame(width:9,height:9)
                Text(companionBusy ? "Thinking..." : (jarvisSpeaking ? "Speaking..." : "Ready to talk"))
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("VOICE TEST") {
                    accessory.speakCompanion("Hey. I'm Jarvis. Tell me what you're working on, and we'll figure it out together.",style:"JARVIS")
                }.font(.caption)
            }
            TextField("Ask Jarvis anything...",text:$companionInput,axis:.vertical)
                .lineLimit(1...4).textFieldStyle(.roundedBorder)
            HStack {
                Button("SEND") {
                    let message = companionInput.trimmingCharacters(in:.whitespacesAndNewlines)
                    guard !message.isEmpty else { return }
                    companionInput = ""
                    talkToCompanion(message)
                }
                .disabled(companionBusy || companionInput.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                Button("TALK") {
                    companionEnabled = true
                    companionTurnTaking = true
                    companionSpeak = true
                    companionQuiet = false
                    companionConversationUntil = Date().addingTimeInterval(companionFollowUpSeconds)
                    selectMode(2)
                    companionStatus = "Listening for Jarvis voice commands"
                }
                Button("QUIET") {
                    companionQuiet = true
                    companionConversationUntil = .distantPast
                    accessory.stopSpeaking()
                    jarvisSpeaking = false
                    companionStatus = "Quiet"
                }
            }.buttonStyle(.borderedProminent)
            Text(companionReply).font(.body)
            if companionStatus.hasPrefix("Companion unavailable") {
                Text(companionStatus).font(.caption).foregroundStyle(.orange)
            }
            if !smartTasks.pinned.isEmpty {
                ForEach(smartTasks.pinned.prefix(3)) { task in
                    HStack {
                        Image(systemName:task.kind == "timer" ? "timer" : "bell")
                        Text(task.title).lineLimit(1)
                        Spacer()
                        Text(task.due,style:.relative).font(.caption.monospaced())
                        Button {
                            smartTasks.complete(task.id); drawHUD()
                        } label: { Image(systemName:"checkmark.circle") }
                    }.font(.caption)
                }
            }
            DisclosureGroup("Tasks & memory",isExpanded:$showMemoryControls) {
                HStack {
                    TextField("Task name",text:$smartTaskTitle)
                        .textFieldStyle(.roundedBorder)
                    Stepper("\(smartTaskMinutes)m",value:$smartTaskMinutes,in:1...1440)
                        .fixedSize()
                }
                Picker("Task",selection:$smartTaskKind) {
                    Text("Reminder").tag("reminder")
                    Text("Timer").tag("timer")
                    Text("Alarm").tag("alarm")
                }.pickerStyle(.segmented)
                Button("PIN TASK") {
                    let name = smartTaskTitle.trimmingCharacters(in:.whitespacesAndNewlines)
                    smartTasks.add(title:name.isEmpty ? smartTaskKind.capitalized : name,
                                   kind:smartTaskKind,after:TimeInterval(smartTaskMinutes * 60))
                    smartTaskTitle = ""
                    drawHUD()
                }
                TextField("Remember this about me...",text:$companionNoteDraft)
                    .textFieldStyle(.roundedBorder)
                Button("SAVE MEMORY") {
                    let note = companionNoteDraft.trimmingCharacters(in:.whitespacesAndNewlines)
                    guard !note.isEmpty else { return }
                    companionNotes = String((companionNotes + "\n" + note).suffix(1800))
                    companionNoteDraft = ""
                }
                .disabled(companionNoteDraft.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty)
                HStack {
                    Button("Forget chat") { companionHistory.removeAll() }
                    Button("Delete memories") { companionNotes = "" }
                }.font(.caption).buttonStyle(.bordered)
                Text("Saved notes are included with requests to your configured Ollama server. Conversation history stays in memory for this app session.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func syncEmotionCues() {
        if companionEnabled && companionSoundCues && mode != 2 && mode != 3 && !musicOnHUD {
            emotionCues.start()
        } else {
            emotionCues.stop()
        }
    }

    private func considerCompanionTranscript(_ transcript:String) {
        guard companionEnabled, !companionBusy, !musicOnHUD, mode == 2 else { return }
        let phrase = transcript.trimmingCharacters(in:.whitespacesAndNewlines)
        guard phrase.count >= 3, phrase != companionLastTranscript else { return }
        let lower = phrase.lowercased()
        if ["jarvis quiet","jarvis stop talking","jarvis be quiet","jarvis silence"].contains(where:lower.contains) {
            companionQuiet = true
            companionConversationUntil = .distantPast
            companionStatus = "Companion quiet"
            companionLastTranscript = phrase
            return
        }
        if lower.contains("jarvis let's talk") || lower.contains("jarvis lets talk") {
            companionQuiet = false
            companionConversationUntil = Date().addingTimeInterval(companionFollowUpSeconds)
            companionStatus = "Conversation window open"
            companionLastTranscript = phrase
            return
        }
        guard !companionQuiet else { return }
        if companionTurnTaking {
            let addressed = lower.hasPrefix("jarvis ") || lower.hasPrefix("hey jarvis ")
            let withinWindow = Date() < companionConversationUntil
            if addressed || withinWindow {
                let message:String
                if lower.hasPrefix("hey jarvis ") { message = String(phrase.dropFirst(11)) }
                else if lower.hasPrefix("jarvis ") { message = String(phrase.dropFirst(7)) }
                else { message = phrase }
                guard message.count >= 4 else { return }
                companionLastTranscript = phrase
                companionConversationUntil = Date().addingTimeInterval(companionFollowUpSeconds)
                talkToCompanion(message)
                return
            }
        }
        guard companionAutoSupport, Date().timeIntervalSince(companionLastResponse) > 180 else { return }
        let signals = ["i'm frustrated","i am frustrated","i'm sad","i am sad",
                       "i feel alone","i'm overwhelmed","i am overwhelmed",
                       "i need someone to talk to","i'm upset","i am upset"]
        guard signals.contains(where:lower.contains) else { return }
        companionLastTranscript = phrase
        talkToCompanion("I said: " + String(phrase.prefix(350)) +
                        ". Offer one brief, gentle, non-assumptive response.")
    }

    private func smartTasksOverlay(_ original:UIImage) -> UIImage {
        guard let task = smartTasks.pinned.first else { return original }
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size:CGSize(width:428,height:240),format:format).image { ctx in
            original.draw(in:CGRect(x:0,y:0,width:428,height:240))
            UIColor(red:0.02,green:0.10,blue:0.18,alpha:0.98).setFill()
            ctx.fill(CGRect(x:6,y:190,width:416,height:46))
            let remaining = max(0,Int(task.due.timeIntervalSinceNow))
            let countdown = remaining >= 3600 ? "\\(remaining / 3600)h \\((remaining % 3600) / 60)m" :
                remaining >= 60 ? "\\(remaining / 60)m \\(remaining % 60)s" : "\\(remaining)s"
            let label = task.kind.uppercased() + " • " + task.title + " • " + countdown
            (label as NSString).draw(in:CGRect(x:12,y:198,width:404,height:34),
                withAttributes:[.font:UIFont.systemFont(ofSize:17,weight:.bold),
                                .foregroundColor:UIColor.white])
        }
    }

    private func companionOverlay(_ original:UIImage) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size:CGSize(width:428,height:240),format:format).image { ctx in
            original.draw(in:CGRect(x:0,y:0,width:428,height:240))
            UIColor(red:0.02,green:0.14,blue:0.18,alpha:0.98).setFill()
            ctx.fill(CGRect(x:0,y:90,width:428,height:150))
            ("JARVIS COMPANION" as NSString).draw(
                in:CGRect(x:12,y:96,width:405,height:27),
                withAttributes:[.font:UIFont.systemFont(ofSize:18,weight:.heavy),
                                .foregroundColor:UIColor.cyan])
            (companionReply as NSString).draw(
                in:CGRect(x:12,y:128,width:405,height:107),
                withAttributes:[.font:UIFont.systemFont(ofSize:22,weight:.bold),
                                .foregroundColor:UIColor.white])
        }
    }

    private func talkToCompanion(_ text:String) {
        guard !companionBusy else { return }
        companionBusy = true
        companionLastResponse = Date()
        companionStatus = "Contacting Ollama companion..."
        let server = ollamaServer, model = ollamaModel, key = ollamaKey
        let previous = companionMemoryEnabled ? companionHistory : []
        let notes = companionMemoryEnabled ? companionNotes : ""
        Task {
            do {
                let reply = try await JarvisOllama.companionReply(text,baseURL:server,model:model,apiKey:key,history:previous,memory:notes)
                await MainActor.run {
                    companionReply = reply
                    if companionMemoryEnabled {
                        companionHistory.append(["role":"user","content":String(text.prefix(900))])
                        companionHistory.append(["role":"assistant","content":String(reply.prefix(900))])
                        if companionHistory.count > 12 {
                            companionHistory.removeFirst(companionHistory.count - 12)
                        }
                    }
                    companionStatus = "Companion replied"
                    companionBusy = false
                    if companionSpeak && mode != 3 {
                        emotionCues.stop()
                        if mode == 2 { captions.stop() }
                        jarvisSpeaking = true
                        accessory.speakCompanion(reply,style:"JARVIS")
                    }
                    drawHUD()
                }
            } catch {
                await MainActor.run {
                    companionBusy = false
                    companionStatus = "Companion unavailable: " + error.localizedDescription
                }
            }
        }
    }

    private var settingsPanel: some View {
        section("AI • PRIVACY • SPEECH") {
            Text("One Jarvis AI, powered by Ollama for conversation. Without a reachable Ollama model, the iPhone's separate built-in answer feature remains available.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Use Ollama for legacy Ask screen",isOn:$online)
            TextField("Ollama address",text:$ollamaServer).textInputAutocapitalization(.never)
                .keyboardType(.URL).textFieldStyle(.roundedBorder)
            TextField("Model name",text:$ollamaModel).textInputAutocapitalization(.never)
                .textFieldStyle(.roundedBorder)
            SecureField("Ollama Cloud API key (optional)",text:$ollamaKey).textFieldStyle(.roundedBorder)
            SecureField("Serper Google Search API key (optional)",text:$serperKey).textFieldStyle(.roundedBorder)
            Toggle("Speak Jarvis answers",isOn:$speakReplies)
            Toggle("Listen for Hey Jarvis when possible",isOn:$keepJarvisListening)
            Toggle("Keep Jarvis microphone active during music (may disrupt playback)",
                   isOn:$listenWhileMusic)
            Toggle("Use Bluetooth headset track controls for HUD navigation (interferes with music)",
                   isOn:$mediaButtonsForHUD)
            Text("Default: headset Play/Pause/Skip are left to Apple Music. During songs, Jarvis stops its mic to avoid interruptions. For Hey Jarvis while music plays, enable the simultaneous microphone option only if your audio route supports it.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Voice: stop, quit, power off, shut down, sleep, wake up, stop everything, stop navigation, stop captions, stop translation, stop music, cancel timer, stop listening.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Keeps the microphone active when iOS permits. iOS may pause speech in the background, and a force-close stops it. Siri Shortcuts remains the lock-screen fallback.")
                .font(.caption2).foregroundStyle(.secondary)
            Toggle("Allow online speech recognition",isOn:$allowOnlineRecognition)
            Picker("Jarvis microphone",selection:$microphoneSource) {
                Text("Any Bluetooth headset").tag("bluetooth")
                Text("Solos only").tag("solos")
                Text("iPhone").tag("iphone")
            }
            .onChange(of:microphoneSource) { _, _ in
                phone.stopListening()
                if keepJarvisListening { phone.startListening() }
            }
            Text("No Solos HUD required: AI voice replies play through the current iOS audio output. Choose your music headset in Control Center. iOS may move audio to the mic headset during listening.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("For a speaker 8–10 feet away, point the iPhone microphone toward them and reduce room noise. No software setting guarantees speech recognition at that distance.")
                .font(.caption2).foregroundStyle(.secondary)
            Text("Ollama must run on your computer or reachable server. A local Wi-Fi model works without outside internet, but iPhone-only offline answers use Apple's supported on-device model.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func section<Content: View>(_ title:String, @ViewBuilder content:()->Content) -> some View {
        VStack(alignment:.leading,spacing:12) {
            Text(title).font(.subheadline.bold()).foregroundStyle(.green)
            content()
        }.frame(maxWidth:.infinity,alignment:.leading)
            .padding(14)
            .background(.white.opacity(0.07),in:RoundedRectangle(cornerRadius:12))
    }

    private func selectMode(_ value:Int) {
        guard availableHUDModes.contains(value) else { return }
        if hudSleeping {
            hudSleeping = false
            hudQuitRequested = false
            lifecycleStatus = "Display restored"
        }
        if mode == 4 && value != 4 {
            UserDefaults.standard.set(false, forKey:"jarvisMessagePinned")
        }
        if mode == value {
            if (value == 2 || value == 3) && !captions.isListening { startCaptioning() }
            drawHUD()
            return
        }
        let previousMode = mode
        mode = value
        captionWakeWork?.cancel()
        captionFlushWork?.cancel()
        translationDebounceWork?.cancel()
        translationSessionReady = false
        if !(previousMode == 2 && value == 3 && language == "en-US") &&
           !(previousMode == 3 && value == 2 && language == "en-US") {
            captions.stop()
        }
        translationContinuation?.finish()
        translationContinuation = nil
        translationConfiguration = nil
        phone.setHUDCaptionsActive(value == 2 || value == 3)
        if value == 2 || value == 3 {
            if !captions.isListening { startCaptioning() }
            else if value == 3 { translationStatus = "Live speech capture continuing" }
        }
        if value == 0 { phone.refreshSensors() }
        syncEmotionCues()
        drawHUD()
    }

    private func startCaptioning() {
        guard mode == 2 || mode == 3 else { return }
        if captions.isListening { captions.stop() }
        captionFlushWork?.cancel()
        translationDebounceWork?.cancel()
        heard = ""
        translated = ""
        translationPending = ""
        translationSessionReady = false
        if mode == 3 { translationStatus = "Starting speech recognition and translation..." }
        let locale = mode == 2 ? "en-US" : language
        if mode == 3 && !language.hasPrefix("en") {
            let source = language.components(separatedBy:"-").first ?? "es"
            translationConfiguration = TranslationSession.Configuration(
                source:Locale.Language(identifier:source),
                target:Locale.Language(identifier:"en")
            )
        } else {
            translationConfiguration = nil
        }
        captions.start(locale:locale,
                       name:locales.first(where:{$0.0 == locale})?.1 ?? "English",
                       allowOnlineRecognition:allowOnlineRecognition,
                       preferPhoneMicrophone:preferPhoneMicrophone)
    }

    private func scheduleCaptionFlush(_ text:String) {
        captionFlushWork?.cancel()
        let job = DispatchWorkItem {
            guard mode == 2, heard == text else { return }
            drawHUD() // Forced trailing frame after streaming speech settles.
        }
        captionFlushWork = job
        DispatchQueue.main.asyncAfter(deadline:.now()+0.18,execute:job)
    }

    private func queueTranslation(_ text:String, final:Bool = false) {
        guard mode == 3 else { return }
        let phrase = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !phrase.isEmpty else { return }
        if language.hasPrefix("en") {
            translated = phrase
            drawHUD()
            return
        }
        translationDebounceWork?.cancel()
        // Stabilize fluent speech first; translating every 100-ms partial
        // kept invalidating the result before it could ever reach the HUD.
        let job = DispatchWorkItem {
            guard mode == 3 else { return }
            guard translationPending != phrase else { return }
            translationPending = phrase
            translationStatus = translationSessionReady ? "Translating speech..." :
                "Heard Spanish; preparing language models..."
            translationContinuation?.yield(phrase)
            if translated.isEmpty { drawHUD() }
        }
        translationDebounceWork = job
        DispatchQueue.main.asyncAfter(deadline:.now()+(final ? 0.03 : 0.18),execute:job)
    }

    // Caption/translation recognizer owns the microphone. Detect wake phrases
    // in its transcript rather than starting a competing audio engine.
    private func handleCaptionWakePhrase(_ transcript:String,isFinal:Bool) -> Bool {
        let lower = transcript.lowercased()
        guard let range = lower.range(of:"hey jarvis") ?? lower.range(of:"oye jarvis") else { return false }
        let question = String(transcript[range.upperBound...]).trimmingCharacters(in:.whitespacesAndNewlines)
        guard !question.isEmpty else { return true }
        // Respond after brief silence even if iOS never returns isFinal.
        // Reset on each changed partial so the actual question is preserved.
        captionWakeWork?.cancel()
        if !isFinal {
            let pending = transcript
            let job = DispatchWorkItem { _ = handleCaptionWakePhrase(pending,isFinal:true) }
            captionWakeWork = job
            DispatchQueue.main.asyncAfter(deadline:.now()+0.85,execute:job)
            return true
        }
        captionWakeWork = nil
        guard question != lastCaptionWakeCommand ||
              Date().timeIntervalSince(lastCaptionWakeAt) > 8 else { return true }
        lastCaptionWakeCommand = question
        lastCaptionWakeAt = Date()
        if routeVoiceHUDCommand(transcript,wakeAlreadyVerified:true) { return true }
        if companionEnabled { talkToCompanion(question) }
        else { phone.ask(question) }
        return true
    }

    @discardableResult
    private func routeVoiceHUDCommand(_ speech:String,
                                      wakeAlreadyVerified:Bool = false,
                                      allowMusic:Bool = true,
                                      allowSystem:Bool = true) -> Bool {
        if false, let (kind,title,seconds) = JarvisSmartTasks.parse(speech) {
            smartTasks.add(title:title,kind:kind,after:seconds)
            lastVoiceHUDCommand = "PINNED " + kind.uppercased()
            drawHUD()
            return true
        }
        if allowSystem, let action = JarvisSystemVoice.parse(
            speech,wakeAlreadyVerified:wakeAlreadyVerified) {
            // Only explicit music requests can stop music.
            if case .stopMusic = action {
                let words = speech.lowercased()
                guard ["stop music","pause music","stop the song","pause the song"].contains(where:words.contains) else { return false }
            }
            handleSystemCommand(action)
            return true
        }
        if allowMusic, let command = JarvisMusicCommand.parse(
            speech,wakeAlreadyVerified:wakeAlreadyVerified) {
            if case .pause = command { return false } // Never pause a song from ambient or wake-word speech.
            handleMusicCommand(command)
            return true
        }
        let normalized = speech.folding(options:[.caseInsensitive,.diacriticInsensitive],
                                        locale:Locale(identifier:"en_US")).lowercased()
        guard wakeAlreadyVerified || normalized.contains("hey jarvis") ||
              normalized.contains("oye jarvis") else { return false }
        let targets: [(Int,[String])] = [
            (0,["dashboard","home","inicio","default display"]),
            (5,["assistant","jarvis mode","ai","answer"])
        ]
        guard let chosen = targets.first(where:{ item in
            item.1.contains(where:{ target in
                normalized.range(of:target,options:.caseInsensitive) != nil
            })
        }) else { return false }
        // Avoid extra audio-engine restarts when an existing recognizer
        // sends the same intermediate phrase more than once.
        if mode != chosen.0 { handsFree.setMode(chosen.0,force:true) }
        lastVoiceHUDCommand = "VOICE → " + names[chosen.0]
        return true
    }

    private func pauseCaptionsAndTranslation() {
        captionFlushWork?.cancel()
        translationDebounceWork?.cancel()
        captions.stop()
        translationContinuation?.finish()
        translationContinuation = nil
        translationConfiguration = nil
        translationSessionReady = false
        phone.setHUDCaptionsActive(false)
        if mode == 2 { heard = "CAPTIONS STOPPED" }
        if mode == 3 {
            translated = "TRANSLATION STOPPED"
            translationStatus = "Translation paused"
        }
    }

    private func pauseAllFeatures(cancelTimer:Bool) {
        pauseCaptionsAndTranslation()
        navigation.stop()
        // Stop Jarvis features without changing Apple Music playback.
        accessory.interruptSpeech()
        if cancelTimer {
            timerEnd = nil
            timerStatus = "Timer canceled by voice"
        }
    }

    private func sleepJarvis(quit:Bool) {
        pauseAllFeatures(cancelTimer:false)
        hudSleeping = true
        hudQuitRequested = quit
        musicOnHUD = false
        if quit {
            keepJarvisListening = false
            phone.stopListening()
            lifecycleStatus = "Jarvis idle. Microphone off. Tap Wake to restore."
            lastVoiceHUDCommand = "JARVIS EXITED • SOFTWARE IDLE"
        } else {
            lifecycleStatus = "Display blanked. Say Hey Jarvis wake up if the microphone is active."
            lastVoiceHUDCommand = "JARVIS STANDBY • HUD OFF"
        }
        renderBlackHUD()
    }

    private func wakeJarvis() {
        hudSleeping = false
        hudQuitRequested = false
        lifecycleStatus = "Jarvis awake"
        lastVoiceHUDCommand = "JARVIS ONLINE • HUD RESTORED"
        handsFree.setMode(0,force:true)
        if keepJarvisListening { phone.startListening() }
        drawHUD()
    }

    private func renderBlackHUD() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let black = UIGraphicsImageRenderer(
            size:CGSize(width:428,height:240),format:format).image { _ in
                UIColor.black.setFill()
                UIRectFill(CGRect(x:0,y:0,width:428,height:240))
            }
        image = black
        if !accessory.connectedProtocol.isEmpty {
            accessory.sendHUDImage(black,priority:true)
        }
    }

    private func setCommandStatus(_ status:String) {
        lastVoiceHUDCommand = "VOICE • " + status
        lifecycleStatus = status
        if !hudSleeping { drawHUD() }
    }

    private func handleSystemCommand(_ action:JarvisSystemCommand) {
        switch action {
        case .sleepDisplay:
            sleepJarvis(quit:false)
        case .quitJarvis:
            sleepJarvis(quit:true)
        case .wakeDisplay:
            wakeJarvis()
        case .stopAll:
            pauseAllFeatures(cancelTimer:true)
            phone.stopListening()
            keepJarvisListening = false
            if hudSleeping { wakeJarvis() }
            else { handsFree.setMode(0,force:true) }
            setCommandStatus("ALL JARVIS ACTIVITIES STOPPED")
        case .stopListening:
            if mode == 2 || mode == 3 { pauseCaptionsAndTranslation() }
            keepJarvisListening = false
            phone.stopListening()
            setCommandStatus("MIC OFF • TAP LISTEN TO RESTART")
        case .startListening:
            if hudSleeping { wakeJarvis() }
            keepJarvisListening = true
            if mode == 2 || mode == 3 {
                phone.setHUDCaptionsActive(true)
                startCaptioning()
            } else {
                phone.startListening()
            }
            setCommandStatus("MICROPHONE LISTENING WHEN iOS PERMITS")
        case .stopTalking:
            accessory.interruptSpeech()
            setCommandStatus("JARVIS VOICE STOPPED")
        case .stopMusic:
            // Deliberately leave Apple Music alone, including voice false positives.
            setCommandStatus("MUSIC PROTECTED • USE MUSIC APP TO PAUSE")
        case .stopNavigation:
            navigation.stop()
            setCommandStatus("NAVIGATION STOPPED")
        case .stopCaptions:
            if mode == 2 { pauseCaptionsAndTranslation() }
            setCommandStatus("CAPTIONS STOPPED")
        case .stopTranslation:
            if mode == 3 { pauseCaptionsAndTranslation() }
            setCommandStatus("TRANSLATION STOPPED")
        case .cancelTimer:
            timerEnd = nil
            timerStatus = "Timer canceled by voice"
            setCommandStatus("TIMER CANCELED")
        case .stopCurrent:
            if hudSleeping {
                setCommandStatus("HUD ALREADY IN STANDBY")
            } else {
                switch mode {
                case 1:
                    navigation.stop()
                    setCommandStatus("NAVIGATION STOPPED")
                case 2,3:
                    pauseCaptionsAndTranslation()
                    setCommandStatus(mode == 2 ? "CAPTIONS STOPPED" : "TRANSLATION STOPPED")
                case 5:
                    accessory.interruptSpeech()
                    setCommandStatus("JARVIS SPEECH STOPPED • MUSIC CONTINUES")
                case 6:
                    timerEnd = nil
                    timerStatus = "Timer canceled by voice"
                    setCommandStatus("TIMER CANCELED")
                case 4:
                    UserDefaults.standard.set(false,forKey:"jarvisMessagePinned")
                    handsFree.setMode(0,force:true)
                    setCommandStatus("PINNED MESSAGE CLEARED")
                default:
                    accessory.interruptSpeech()
                    setCommandStatus("JARVIS STOPPED")
                }
            }
        case .unsupportedPhonePower:
            if hudSleeping { wakeJarvis() }
            handsFree.setMode(5,force:true)
            musicOnHUD = false
            answer = "iOS does not allow an app to power off an iPhone. Say Hey Jarvis power off to blank your HUD instead."
            setCommandStatus("IPHONE POWER OFF NOT AVAILABLE")
        }
    }

    private func handleMusicCommand(_ command:JarvisMusicCommand) {
        musicOnHUD = true
        if mode != 5 { handsFree.setMode(5,force:true) }
        switch command {
        case .play(let query):
            musicQuery = query
            phone.setMusicPlaybackActive(true)
            if !listenWhileMusic { captions.stop() }
            music.playSong(query)
        case .pause:
            // Music playback stays under the user's control in Apple Music.
            lastVoiceHUDCommand = "MUSIC PROTECTED"
        case .resume:
            phone.setMusicPlaybackActive(true)
            music.resume()
        case .next:
            phone.setMusicPlaybackActive(true)
            music.next()
        case .previous:
            phone.setMusicPlaybackActive(true)
            music.previous()
        }
        answer = music.status
        lastVoiceHUDCommand = "APPLE MUSIC • " + music.status
        drawHUD()
    }

    private func sendVisionDiagnostic() {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let test = UIGraphicsImageRenderer(
            size:CGSize(width:428,height:240),format:format).image { context in
            UIColor.black.setFill()
            context.cgContext.fill(CGRect(x:0,y:0,width:428,height:240))
            UIColor.white.setStroke()
            context.cgContext.setLineWidth(5)
            context.cgContext.stroke(CGRect(x:7,y:7,width:414,height:226))
            ("RX TEST" as NSString).draw(
                in:CGRect(x:25,y:42,width:382,height:110),
                withAttributes:[.font:UIFont.systemFont(ofSize:71,weight:.black),
                                .foregroundColor:UIColor.white])
            ("RIGHT EYE   15 DEGREES" as NSString).draw(
                in:CGRect(x:22,y:166,width:400,height:44),
                withAttributes:[.font:UIFont.systemFont(ofSize:24,weight:.black),
                                .foregroundColor:UIColor.white])
        }
        image = test
        if !accessory.connectedProtocol.isEmpty {
            accessory.sendHUDImage(test,priority:true)
        }
    }

    private func drawHUD(throttled:Bool = false) {
        if visionDiagnosticActive { return }
        if hudSleeping || visionWizardPresented { return }
        if throttled && Date().timeIntervalSince(lastFrameAt) < (mode == 2 ? 0.25 : 0.6) { return }
        lastFrameAt = Date()
        let detail = mode == 0 ? "HEART " + heartRate + " BPM" :
            (mode == 3 && translated.isEmpty ? "SPANISH HEARD • TRANSLATING" :
            (mode == 5 && musicOnHUD ? "APPLE MUSIC • NOW PLAYING" : "JARVIS • " + names[mode]))
        let text: String
        let renderMode: Int
        switch mode {
        case 1:
            text = navigation.nextTurn + "|" + navigation.instruction + "|" + navigation.eta + "|" + navigation.remaining
            renderMode = 1
        case 2: text = heard; renderMode = 2
        case 3: text = translated.isEmpty ? heard : translated; renderMode = 3
        case 4: text = messagePages[min(currentMessagePage, messagePages.count - 1)]; renderMode = 4
        case 5: text = answer; renderMode = 5
        case 6:
            text = timerEnd.map { "TIMER\n" + formatRemaining($0) } ?? "TIMER READY"
            renderMode = 5
        default: text = ""; renderMode = 0
        }
        let output = SolosProHUD.image(
            mode:renderMode,clock:phone.clock,date:phone.dateLine,
            steps:Int(phone.steps) ?? 0,distance:phone.distance,
            speed:phone.speed,battery:phone.battery,gps:phone.coordinates,
            message:text,detail:detail,sender:sender,
            senderPhoto:senderPhoto,messagePage:currentMessagePage + 1,pageCount:messagePages.count)
        let companionFrame = Date().timeIntervalSince(companionLastResponse) < 35 &&
            companionStatus == "Companion replied" ? companionOverlay(output) : output
        let tuned = weatherGuardian.overlay(JarvisHUDVision.apply(to:companionFrame))
        image = tuned
        // sendHUDImage drops obsolete ordinary frames while busy. No new BLE
        // transport is fabricated if iOS does not expose an accessory session.
        if !accessory.connectedProtocol.isEmpty {
            accessory.sendHUDImage(tuned,priority:mode == 4 || mode == 5)
        }
    }

    private func askJarvis() {
        let query = question.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        aiBusy = true
        musicOnHUD = false
        if mode != 5 { handsFree.setMode(5,force:true) }
        if online {
            let server = ollamaServer, model = ollamaModel, key = ollamaKey, searchKey = serperKey
            Task {
                do {
                    let response = try await JarvisOllama.answer(query,baseURL:server,
                        model:model,apiKey:key,googleKey:searchKey)
                    await MainActor.run {
                        answer = response
                        aiBusy = false
                        drawHUD()
                        if speakReplies { accessory.speak(response) }
                    }
                } catch {
                    await MainActor.run {
                        answer = "Ollama error: " + error.localizedDescription
                        aiBusy = false
                        drawHUD()
                    }
                }
            }
        } else {
            phone.ask(query)
            aiBusy = false
        }
    }

    private func requestHeartRate() {
        guard HKHealthStore.isHealthDataAvailable(),
              let type = HKObjectType.quantityType(forIdentifier:.heartRate) else {
            heartRate = "—"; return
        }
        health.requestAuthorization(toShare:[],read:[type]) { granted,_ in
            guard granted else { return }
            let sort = NSSortDescriptor(key:HKSampleSortIdentifierEndDate,ascending:false)
            let query = HKSampleQuery(sampleType:type,predicate:nil,limit:1,sortDescriptors:[sort]) { _,samples,_ in
                guard let sample = samples?.first as? HKQuantitySample else { return }
                let bpm = Int(sample.quantity.doubleValue(for:HKUnit.count().unitDivided(by:HKUnit.minute())))
                DispatchQueue.main.async { heartRate = String(bpm); if mode == 0 { drawHUD() } }
            }
            health.execute(query)
        }
    }


    private func pinMessage(sender newSender:String, body newBody:String) {
        let clean = newBody.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !clean.isEmpty else {
            messageRelayStatus = "Add message text first."
            return
        }
        sender = String(newSender.prefix(80))
        message = String(clean.prefix(12_000))
        messagePages = SolosProHUD.messagePages(message)
        currentMessagePage = 0
        lastMessagePageAt = Date()
        let defaults = UserDefaults.standard
        defaults.set(sender,forKey:"jarvisPinnedSender")
        defaults.set(message,forKey:"jarvisPinnedBody")
        defaults.set(true,forKey:"jarvisMessagePinned")
        messageRelayStatus = "PINNED · \(messagePages.count) page(s) · \(sender)"
        handsFree.setMode(4,force:true)
    }

    private func restorePinnedMessageIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey:"jarvisMessagePinned"),
              let text = defaults.string(forKey:"jarvisPinnedBody"), !text.isEmpty else { return }
        sender = defaults.string(forKey:"jarvisPinnedSender") ?? "NEW MESSAGE"
        message = text
        messagePages = SolosProHUD.messagePages(text)
        currentMessagePage = 0
        lastMessagePageAt = Date()
        loadContactPhoto(for:sender)
        handsFree.setMode(4,force:true)
    }

    private func consumeShortcutMessage() {
        let defaults = UserDefaults.standard
        guard let id = defaults.string(forKey:"jarvisIncomingMessageID"),
              id != lastMessageID,
              let text = defaults.string(forKey:"jarvisIncomingMessageBody"),
              !text.isEmpty else { return }
        lastMessageID = id
        let incomingSender = defaults.string(forKey:"jarvisIncomingMessageSender") ?? "NEW MESSAGE"
        defaults.removeObject(forKey:"jarvisIncomingMessageID")
        defaults.removeObject(forKey:"jarvisIncomingMessageSender")
        defaults.removeObject(forKey:"jarvisIncomingMessageBody")
        senderPhoto = nil
        loadContactPhoto(for: incomingSender)
        pinMessage(sender:incomingSender,body:text)
    }

    private func acceptIncomingMessageURL(_ url:URL) {
        guard url.scheme?.lowercased() == "solosjarvis",
              url.host?.lowercased() == "message",
              let items = URLComponents(url:url,resolvingAgainstBaseURL:false)?.queryItems,
              let body = items.first(where:{$0.name == "body"})?.value,
              !body.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else { return }
        let from = items.first(where:{$0.name == "from"})?.value ?? "NEW MESSAGE"
        senderPhoto = nil
        loadContactPhoto(for:from)
        pinMessage(sender:from,body:body)
    }

    private func loadContactPhoto(for name:String) {
        let auth = CNContactStore.authorizationStatus(for:.contacts)
        guard auth == .authorized || auth == .limited else { return }
        let store = CNContactStore()
        let keys = [CNContactGivenNameKey,CNContactFamilyNameKey,CNContactThumbnailImageDataKey] as [CNKeyDescriptor]
        do {
            let found: [CNContact]
            if name.contains(where:{$0.isNumber}) {
                found = try store.unifiedContacts(matching:CNContact.predicateForContacts(
                    matching:CNPhoneNumber(stringValue:name)),keysToFetch:keys)
            } else {
                found = try store.unifiedContacts(matching:CNContact.predicateForContacts(
                    matchingName:name),keysToFetch:keys)
            }
            if let contact = found.first {
                senderPhoto = contact.thumbnailImageData.flatMap(UIImage.init(data:))
            }
        } catch {
            messageRelayStatus = "Contact photo not available"
        }
    }

    private func scheduleReminder() {
        let body = reminderText.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !body.isEmpty else { reminderStatus = "Enter a reminder"; return }
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge]) { allowed,_ in
            guard allowed else {
                DispatchQueue.main.async { reminderStatus = "Allow notifications in iPhone Settings" }
                return
            }
            let content = UNMutableNotificationContent()
            content.title = "Jarvis Reminder"
            content.body = body
            content.sound = .default
            let components = Calendar.current.dateComponents([.year,.month,.day,.hour,.minute],from:remindAt)
            let request = UNNotificationRequest(identifier:UUID().uuidString,content:content,
                                                trigger:UNCalendarNotificationTrigger(dateMatching:components,repeats:false))
            UNUserNotificationCenter.current().add(request) { error in
                DispatchQueue.main.async { reminderStatus = error?.localizedDescription ?? "Reminder scheduled" }
            }
        }
    }

    private func notify(title:String,body:String,after:TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = title; content.body = body; content.sound = .default
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound]) { granted,_ in
            guard granted else { return }
            UNUserNotificationCenter.current().add(
                UNNotificationRequest(identifier:UUID().uuidString,content:content,
                    trigger:UNTimeIntervalNotificationTrigger(timeInterval:after,repeats:false))
            )
        }
    }

    private func formatRemaining(_ end:Date) -> String {
        let seconds = max(0,Int(end.timeIntervalSinceNow))
        return String(format:"%02d:%02d",seconds / 60,seconds % 60)
    }
}


// The border belongs to the Jarvis app window. iOS does not allow a
// persistent third-party overlay above the Home Screen or other apps.
private struct JarvisVoiceBorder: View {
    let level: Double
    let speaking: Bool
    let listening: Bool
    @State private var breathing = false

    private var tint: Color {
        speaking ? Color(red:1.0,green:0.43,blue:0.08) :
        Color(red:0.06,green:0.53,blue:1.0)
    }

    var body: some View {
        GeometryReader { geometry in
            let strength = speaking ? (breathing ? 0.95 : 0.55) :
                           (listening ? min(1.0,0.18 + level * 0.82) : 0.06)
            let corner = min(55.0,geometry.size.width * 0.12)
            RoundedRectangle(cornerRadius:corner,style:.continuous)
                .stroke(tint.opacity(0.35 + strength * 0.65),
                        lineWidth:2.5 + strength * 2.0)
                .shadow(color:tint.opacity(strength * 0.9),
                        radius:5 + strength * 15)
                .padding(3)
                .animation(.easeOut(duration:0.12),value:level)
                .animation(.easeInOut(duration:0.35),value:speaking)
        }
        .onAppear { breathing = true }
        .animation(.easeInOut(duration:0.45).repeatForever(autoreverses:true),
                   value:breathing)
    }
}
