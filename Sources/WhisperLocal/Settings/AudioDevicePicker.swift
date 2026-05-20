import SwiftUI

struct AudioDevicePicker: View {
    @State private var devices: [AudioInputDevice] = []
    @State private var selection: String  // empty string = system default
    var onChange: (String?) -> Void

    init(initial: String?, onChange: @escaping (String?) -> Void) {
        _selection = State(initialValue: initial ?? "")
        self.onChange = onChange
    }

    var body: some View {
        HStack {
            Picker("", selection: $selection) {
                Text("System default").tag("")
                ForEach(devices, id: \.uid) { device in
                    Text(device.name).tag(device.uid)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)

            Button {
                refresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .help("Refresh device list")
            .buttonStyle(.borderless)
        }
        .onAppear { refresh() }
        .onChange(of: selection) { _, new in
            let uid: String? = new.isEmpty ? nil : new
            onChange(uid)
        }
    }

    private func refresh() {
        devices = AudioDeviceManager.inputDevices()
        // If selection refers to a missing device, fall back to default.
        if !selection.isEmpty, !devices.contains(where: { $0.uid == selection }) {
            selection = ""
        }
    }
}
