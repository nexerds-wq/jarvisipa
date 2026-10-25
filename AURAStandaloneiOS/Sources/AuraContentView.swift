import SwiftUI

struct AuraContentView: View {
    @EnvironmentObject private var voice: AuraVoiceController
    @State private var typedMessage = ""

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.025, green: 0.038, blue: 0.088),
                         Color(red: 0.010, green: 0.015, blue: 0.037)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 22) {
                    header
                    orb
                    statusCard
                    conversation
                    controls
                    options
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.top, 18)
                .padding(.bottom, 35)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("JARVIS")
                    .font(.system(size: 34, weight: .thin, design: .rounded))
                    .tracking(8)
                Text("AURA  /  ON-DEVICE AI")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .tracking(3)
                    .foregroundStyle(.cyan.opacity(0.85))
            }
            Spacer()
            Image(systemName: "iphone.gen3.radiowaves.left.and.right")
                .font(.system(size: 27))
                .foregroundStyle(.cyan)
                .accessibilityHidden(true)
        }
    }

    private var orb: some View {
        ZStack {
            Circle()
                .stroke(.cyan.opacity(0.12), lineWidth: 1)
                .frame(width: 244, height: 244)
            Circle()
                .stroke(.cyan.opacity(0.27), lineWidth: 2)
                .frame(width: 205, height: 205)
            Circle()
                .fill(
                    RadialGradient(colors: [
                        (voice.isListening ? Color.orange : Color.cyan).opacity(0.43),
                        Color(red: 0.04, green: 0.16, blue: 0.29).opacity(0.35),
                        .clear
                    ], center: .center, startRadius: 0, endRadius: 93)
                )
                .frame(width: 190, height: 190)
            Circle()
                .stroke(
                    AngularGradient(colors: [.cyan.opacity(0.1), .cyan, .blue, .cyan.opacity(0.15)], center: .center),
                    lineWidth: 7
                )
                .frame(width: 146, height: 146)
            Image(systemName: voice.isListening ? "waveform" : "sparkle")
                .font(.system(size: 41, weight: .ultraLight))
                .foregroundStyle(voice.isListening ? .orange : .cyan)
                .contentTransition(.symbolEffect(.replace))
        }
        .frame(height: 250)
        .accessibilityLabel(voice.isListening ? "Microphone listening" : "JARVIS AI ready")
    }

    private var statusCard: some View {
        VStack(spacing: 9) {
            HStack(spacing: 8) {
                Circle()
                    .fill(voice.modelReady ? Color.green : Color.orange)
                    .frame(width: 8, height: 8)
                Text(voice.modelReady ? "AI READY ON THIS IPHONE" : "AI SETUP NEEDED")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1)
                Spacer()
                Button("Check") { voice.checkAvailability() }
                    .font(.caption)
                    .foregroundStyle(.cyan)
            }
            Text(voice.status)
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(.white.opacity(0.10)))
    }

    private var conversation: some View {
        VStack(alignment: .leading, spacing: 14) {
            message(label: "YOU", text: voice.heardText.isEmpty ? "Tap the microphone or type to begin." : voice.heardText,
                    tint: .orange)
            message(label: "JARVIS", text: voice.reply.isEmpty ? "I'm here. What's on your mind?" : voice.reply,
                    tint: .cyan)
        }
    }

    private func message(label: String, text: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(tint)
            Text(text)
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(.white.opacity(0.94))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
    }

    private var controls: some View {
        VStack(spacing: 12) {
            Button {
                voice.microphoneTapped()
            } label: {
                Label(voice.isListening ? "FINISH TALKING" : "TALK TO JARVIS",
                      systemImage: voice.isListening ? "stop.fill" : "mic.fill")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .tracking(1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.black)
            .background(voice.isListening ? Color.orange : Color.cyan, in: RoundedRectangle(cornerRadius: 19))
            .disabled(!voice.modelReady || voice.isGenerating)

            HStack(spacing: 12) {
                Button("Interrupt") { voice.interrupt() }
                    .buttonStyle(.bordered)
                    .tint(.orange)
                    .frame(maxWidth: .infinity)
                Button("New conversation") { voice.newConversation() }
                    .buttonStyle(.bordered)
                    .tint(.cyan)
                    .frame(maxWidth: .infinity)
            }

            HStack {
                TextField("Or type anything...", text: $typedMessage, axis: .vertical)
                    .lineLimit(1...3)
                    .textInputAutocapitalization(.sentences)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.075), in: RoundedRectangle(cornerRadius: 12))
                Button {
                    let message = typedMessage
                    typedMessage = ""
                    voice.send(message)
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 30))
                }
                .disabled(!voice.modelReady || voice.isGenerating || typedMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private var options: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("PERSONALITY & VOICE")
                .font(.system(size: 11, weight: .semibold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(.cyan)
            Picker("Personality", selection: $voice.personality) {
                ForEach(AuraPersonality.allCases) { personality in
                    Text(personality.rawValue).tag(personality)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: voice.personality) { _, _ in voice.newConversation() }

            Toggle("Speak responses aloud", isOn: $voice.speakReplies)
                .tint(.cyan)
                .font(.subheadline)
        }
        .padding(16)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 17))
    }

    private var footer: some View {
        Text("No PC • No IP address • No API subscription\nUses Apple's on-device language model and system voices.\nTap to talk; tap again to send. Requires iOS 26+ and Apple Intelligence.")
            .font(.system(size: 11))
            .multilineTextAlignment(.center)
            .foregroundStyle(.white.opacity(0.5))
            .lineSpacing(4)
    }
}
