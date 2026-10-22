import SwiftUI
import Contacts
import ContactsUI
import UIKit

/// Apple's person picker shares only the contact that the user selects.
struct SolosMessageContactPicker: UIViewControllerRepresentable {
    var onSelect: (String, UIImage?) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onSelect:onSelect) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        var onSelect: (String, UIImage?) -> Void
        init(onSelect: @escaping (String, UIImage?) -> Void) {
            self.onSelect = onSelect
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let fullName = CNContactFormatter.string(from:contact,style:.fullName)
                ?? ([contact.givenName,contact.familyName].joined(separator:" "))
            let image = contact.thumbnailImageData.flatMap(UIImage.init(data:))
            onSelect(fullName.isEmpty ? "CONTACT" : fullName,image)
        }
    }
}
