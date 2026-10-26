import Foundation
import Combine
import EventKit
import AlarmKit
import SwiftUI

struct JarvisNote: Codable, Identifiable {
    let id: UUID
    let text: String
    let createdAt: Date
}

struct JarvisAlarmMetadata: AlarmMetadata {}

/// Personal notes remain local; Reminders and alarms use Apple's supported APIs.
@MainActor final class JarvisProductivity: ObservableObject {
    @Published private(set) var notes: [JarvisNote] = []
    @Published var status = "Ready for notes, reminders and alarms"
    private let eventStore = EKEventStore()
    private let notesKey = "jarvisLocalNotesV1"

    init() {
        if let data = UserDefaults.standard.data(forKey:notesKey),
           let restored = try? JSONDecoder().decode([JarvisNote].self,from:data) {
            notes = restored
        }
    }

    func addNote(_ text:String) {
        let trimmed = text.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { status = "Write something to save"; return }
        notes.insert(JarvisNote(id:UUID(),text:String(trimmed.prefix(3000)),createdAt:Date()),at:0)
        persistNotes()
        status = "Note saved privately on this iPhone"
    }

    func deleteNote(_ id:UUID) {
        notes.removeAll(where:{$0.id == id})
        persistNotes()
        status = "Note deleted"
    }

    private func persistNotes() {
        if let encoded = try? JSONEncoder().encode(notes) {
            UserDefaults.standard.set(encoded,forKey:notesKey)
        }
    }

    func createAppleReminder(title:String,at date:Date) async {
        let trimmed = title.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !trimmed.isEmpty else { status = "Enter a reminder title"; return }
        guard date > Date() else { status = "Choose a future reminder time"; return }
        do {
            let granted = try await eventStore.requestFullAccessToReminders()
            guard granted else { status = "Allow Reminders access in iPhone Settings"; return }
            guard let calendar = eventStore.defaultCalendarForNewReminders() else {
                status = "No writable Apple Reminders list is available"
                return
            }
            let reminder = EKReminder(eventStore:eventStore)
            reminder.title = String(trimmed.prefix(240))
            reminder.calendar = calendar
            reminder.dueDateComponents = Calendar.current.dateComponents(
                [.year,.month,.day,.hour,.minute],from:date)
            reminder.addAlarm(EKAlarm(absoluteDate:date))
            try eventStore.save(reminder,commit:true)
            status = "Saved to Apple Reminders for \(date.formatted(date:.abbreviated,time:.shortened))"
        } catch {
            status = "Reminder not saved: \(error.localizedDescription)"
        }
    }

    func createSystemAlarm(title:String,at date:Date) async {
        guard date > Date() else { status = "Choose a future alarm time"; return }
        do {
            let permission = try await AlarmManager.shared.requestAuthorization()
            guard permission == .authorized else {
                status = "Alarm permission denied. Check iPhone Settings."
                return
            }
            typealias Configuration = AlarmManager.AlarmConfiguration<JarvisAlarmMetadata>
            let stop = AlarmButton(text:"Dismiss",textColor:.white,systemImageName:"stop.circle")
            let displayTitle = title.isEmpty ? "Jarvis Alarm" : String(title.prefix(80))
            let localizedTitle: LocalizedStringResource = "\(displayTitle)"
            let alert = AlarmPresentation.Alert(
                title:localizedTitle,stopButton:stop)
            let attributes = AlarmAttributes<JarvisAlarmMetadata>(
                presentation:AlarmPresentation(alert:alert),metadata:nil,tintColor:.orange)
            let config: Configuration = Configuration(schedule:.fixed(date),attributes:attributes)
            let _: Alarm = try await AlarmManager.shared.schedule(id:UUID(),configuration:config)
            status = "iOS system alarm scheduled for \(date.formatted(date:.abbreviated,time:.shortened))"
        } catch {
            status = "Alarm not scheduled: \(error.localizedDescription)"
        }
    }
}
