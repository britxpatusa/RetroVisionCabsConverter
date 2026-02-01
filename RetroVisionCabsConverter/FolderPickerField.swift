import SwiftUI
import AppKit

struct FolderPickerField: View {
    let title: String
    @Binding var path: String

    var body: some View {
        HStack(spacing: 12) {
            Text(title)
                .frame(width: 170, alignment: .leading)

            TextField("", text: $path)
                .textFieldStyle(.roundedBorder)

            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = false
                panel.prompt = "Choose"

                if panel.runModal() == .OK, let url = panel.url {
                    path = url.path
                }
            }
        }
    }
}
