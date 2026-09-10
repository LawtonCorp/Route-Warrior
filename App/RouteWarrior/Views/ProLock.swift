import SwiftUI

/// A Pro gate that shows the shape of what is locked (D-050): the real
/// content, blurred and untouchable, with one button over it. People
/// pay to open a gate they can see through.
struct ProLock<Content: View>: View {
    let locked: Bool
    let title: String
    let onUnlock: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        if locked {
            ZStack {
                content()
                    .blur(radius: 6)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                Button(action: onUnlock) {
                    Label(title, systemImage: "lock.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.pro)
            }
        } else {
            content()
        }
    }
}

/// A locked list row: what is there, and that Pro opens it.
struct ProLockRow: View {
    let title: String
    var detail: String? = nil
    let onUnlock: () -> Void

    var body: some View {
        Button(action: onUnlock) {
            HStack(spacing: 12) {
                IconTile(symbol: "lock.fill", color: Theme.pro)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                    if let detail {
                        Text(detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
        }
        .tint(.primary)
    }
}
