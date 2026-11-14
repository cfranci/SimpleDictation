import SwiftUI
import AppKit

/// Settings > License: shows where the user stands and takes a license code.
struct LicensePage: View {
    @ObservedObject private var license = LicenseManager.shared
    @State private var code = ""
    @State private var busy = false
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundStyle(tint)
            Text(detail)
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !license.isLicensed {
                HStack {
                    TextField("SD42-XXXX-XXXX-XXXX", text: $code)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(.body, design: .monospaced))
                        .onSubmit(activate)
                    Button(busy ? "Activating…" : "Activate", action: activate)
                        .disabled(busy || code.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let message {
                    Text(message).font(.caption).foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Button("Buy a license for $4.20") { NSWorkspace.shared.open(LicenseManager.buyURL) }
                Text("Activating contacts the license server once. After that the app checks your license on this Mac and never goes online for it again.")
                    .font(.caption2).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 440, alignment: .leading)
    }

    private var title: String {
        switch license.state {
        case .licensed:            return "Licensed"
        case .trial(let daysLeft): return daysLeft == 1 ? "Trial: 1 day left" : "Trial: \(daysLeft) days left"
        case .expired:             return "Trial ended"
        }
    }

    private var icon: String {
        switch license.state {
        case .licensed: return "checkmark.seal.fill"
        case .trial:    return "clock.fill"
        case .expired:  return "lock.fill"
        }
    }

    private var tint: Color {
        switch license.state {
        case .licensed: return .green
        case .trial:    return .primary
        case .expired:  return .orange
        }
    }

    private var detail: String {
        switch license.state {
        case .licensed(let email):
            if email == "early supporter" {
                return "You used SimpleDictation while it was free, so every engine stays unlocked for you. Thank you."
            }
            return email.isEmpty ? "Every engine is unlocked. Thank you for buying SimpleDictation."
                                 : "Every engine is unlocked. Licensed to \(email)."
        case .trial:
            return "Every engine is unlocked during the trial. When it ends, Apple Speech stays free and a license unlocks the rest for good."
        case .expired:
            return "Apple Speech still works. A license unlocks the Whisper, Moonshine and Whistle engines for good."
        }
    }

    private func activate() {
        guard !busy else { return }
        busy = true
        message = nil
        let entered = code
        Task {
            let result = await LicenseManager.shared.activate(code: entered)
            await MainActor.run {
                busy = false
                if case .failure(let error) = result { message = error.localizedDescription } else { code = "" }
            }
        }
    }
}
