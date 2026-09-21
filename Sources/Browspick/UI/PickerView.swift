import AppKit
import BrowspickCore
import SwiftUI

final class PickerSelection: NSObject, ObservableObject {
    @Published var entries: [PickerEntry] = []
    @Published var selectedIndex = 0
    /// Brief "URL copied" confirmation shown in the footer.
    @Published var copied = false
    var onPick: ((PickerEntry) -> Void)?

    var selected: PickerEntry? {
        entries.indices.contains(selectedIndex) ? entries[selectedIndex] : nil
    }

    func move(by delta: Int) {
        guard !entries.isEmpty else { return }
        selectedIndex = (selectedIndex + delta + entries.count) % entries.count
    }

    private var copiedResetTimer: Timer?

    func copyURL(_ url: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        copied = true
        // Target-action Timer — no @Sendable capture of self.
        copiedResetTimer?.invalidate()
        copiedResetTimer = Timer.scheduledTimer(
            timeInterval: 1.2, target: self,
            selector: #selector(resetCopied), userInfo: nil, repeats: false)
    }

    @objc private func resetCopied() { copied = false }
}

struct PickerView: View {
    let url: String
    @ObservedObject var selection: PickerSelection
    let onPick: (PickerEntry) -> Void

    init(url: String, selection: PickerSelection) {
        self.url = url
        self.selection = selection
        self.onPick = { entry in selection.onPick?(entry) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                // ZWSP between every char → breaks anywhere, so line 1 fills fully.
                // (SwiftUI only breaks at UAX#14 boundaries; long path segments are
                // unbreakable tokens that would jump whole to line 2.)
                Text(url.map { "\($0)\u{200B}" }.joined())
                    .font(.system(.callout, design: .monospaced))
                    .lineLimit(2)
                    .truncationMode(.tail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {
                        Button("Copy URL") { selection.copyURL(url) }
                    }
                Button {
                    selection.copyURL(url)
                } label: {
                    Group {
                        if selection.copied {
                            Image(systemName: "checkmark")
                        } else {
                            Text("c")
                        }
                    }
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(selection.copied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                    .frame(width: 18, height: 18)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Copy URL (c)")
            }

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 2) {
                        ForEach(Array(selection.entries.enumerated()), id: \.element.id) { index, entry in
                            Button {
                                onPick(entry)
                            } label: {
                                HStack(spacing: 10) {
                                    if let icon = entry.icon {
                                        Image(nsImage: icon)
                                            .resizable()
                                            .frame(width: 20, height: 20)
                                            .clipShape(entry.isAvatar ? AnyShape(Circle()) : AnyShape(RoundedRectangle(cornerRadius: 4)))
                                    }
                                    Text(entry.title)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                    if entry.isSuggested {
                                        Image(systemName: "clock.arrow.circlepath")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .help("Last used for this host")
                                    }
                                    Spacer()
                                    if index < 9 {
                                        Text("\(index + 1)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .padding(.horizontal, 4)
                                            .padding(.vertical, 1)
                                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 3))
                                    }
                                }
                                .padding(.horizontal, 10)
                                .padding(.vertical, 7)
                                .contentShape(Rectangle())
                                .background(
                                    index == selection.selectedIndex
                                        ? Color.accentColor.opacity(0.25)
                                        : Color.clear,
                                    in: RoundedRectangle(cornerRadius: 6)
                                )
                            }
                            .buttonStyle(.plain)
                            .id(entry.id)
                        }
                    }
                }
                .onAppear {
                    if let entry = selection.selected {
                        proxy.scrollTo(entry.id, anchor: .center)
                    }
                }
            }
            .frame(maxHeight: 380)

            Text(selection.copied
                 ? "URL copied"
                 : "1–9 / arrows / Return: open  ·  c: copy URL  ·  ⌘: save rule  ·  ⌃: background  ·  Esc: cancel")
                .font(.caption2)
                .foregroundStyle(selection.copied ? AnyShapeStyle(.green) : AnyShapeStyle(.tertiary))
        }
        .padding(14)
        .frame(width: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.separator))
    }
}
