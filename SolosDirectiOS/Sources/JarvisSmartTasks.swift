import Foundation
import UserNotifications
import Combine

struct JarvisPinnedTask: Codable, Identifiable {
    var id: UUID = UUID()
    var title: String
    var kind: String
    var due: Date
    var pinned: Bool = true
    var completed: Bool = false
}

@MainActor final class JarvisSmartTasks: ObservableObject {
    @Published private(set) var tasks: [JarvisPinnedTask] = []
    private let storageKey = "jarvisSmartTasksV1"
    init() { load() }
    private func load() {
        guard let data = UserDefaults.standard.data(forKey:storageKey),
              let saved = try? JSONDecoder().decode([JarvisPinnedTask].self,from:data) else { return }
        tasks = saved
    }
    private func save() {
        if let data = try? JSONEncoder().encode(tasks) {
            UserDefaults.standard.set(data,forKey:storageKey)
        }
    }
    func add(title:String,kind:String,after seconds:TimeInterval) {
        let due = Date().addingTimeInterval(max(1,seconds))
        let item = JarvisPinnedTask(title:String(title.prefix(100)),kind:kind,due:due)
        tasks.append(item)
        save()
        let content = UNMutableNotificationContent()
        content.title = "Jarvis " + kind.capitalized
        content.body = item.title
        content.sound = .default
        UNUserNotificationCenter.current().requestAuthorization(options:[.alert,.sound,.badge]) { allowed,_ in
            guard allowed else { return }
            let request = UNNotificationRequest(identifier:item.id.uuidString,
                content:content,
                trigger:UNTimeIntervalNotificationTrigger(timeInterval:max(1,seconds),repeats:false))
            UNUserNotificationCenter.current().add(request,withCompletionHandler:{ _ in })
        }
    }
    func remove(_ id:UUID) {
        tasks.removeAll(where:{$0.id == id})
        save()
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers:[id.uuidString])
    }
    func pin(_ id:UUID,_ value:Bool) {
        guard let i = tasks.firstIndex(where:{$0.id == id}) else { return }
        tasks[i].pinned = value
        save()
    }
    func complete(_ id:UUID) {
        guard let i = tasks.firstIndex(where:{$0.id == id}) else { return }
        tasks[i].completed = true
        tasks[i].pinned = false
        save()
    }
    var pinned: [JarvisPinnedTask] {
        tasks.filter {$0.pinned && !$0.completed}.sorted {$0.due < $1.due}
    }
    static func parse(_ speech:String) -> (String,String,TimeInterval)? {
        let lower = speech.lowercased().trimmingCharacters(in:.whitespacesAndNewlines)
        guard lower.contains("jarvis") else { return nil }
        let kind:String
        if lower.contains("timer") || lower.contains("countdown") { kind = "timer" }
        else if lower.contains("alarm") { kind = "alarm" }
        else if lower.contains("remind me") || lower.contains("reminder") { kind = "reminder" }
        else { return nil }
        let pattern = #"(?:(?:in|for|after)\s+)?(\d{1,4})\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?)"#
        guard let regex = try? NSRegularExpression(pattern:pattern),
              let match = regex.firstMatch(in:lower,range:NSRange(lower.startIndex...,in:lower)),
              let numberRange = Range(match.range(at:1),in:lower),
              let unitRange = Range(match.range(at:2),in:lower),
              let value = Double(lower[numberRange]) else { return nil }
        let unit = String(lower[unitRange])
        let multiplier:Double = unit.hasPrefix("h") ? 3600 : (unit.hasPrefix("m") ? 60 : 1)
        let duration = value * multiplier
        guard duration >= 1 && duration <= 86400 * 30 else { return nil }
        let title:String
        if kind == "timer" { title = "Timer finished" }
        else if kind == "alarm" { title = "Alarm" }
        else {
            var cleaned = lower.replacingOccurrences(of:"hey jarvis",with:"")
                .replacingOccurrences(of:"jarvis",with:"")
                .replacingOccurrences(of:"remind me",with:"")
                .replacingOccurrences(of:"reminder",with:"")
            if let r = cleaned.range(of:pattern,options:.regularExpression) {
                cleaned.removeSubrange(r)
            }
            cleaned = cleaned.trimmingCharacters(in:.whitespacesAndNewlines)
            title = cleaned.isEmpty ? "Reminder" : cleaned
        }
        return (kind,title,duration)
    }
}
