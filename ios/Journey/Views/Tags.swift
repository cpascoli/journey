import SwiftData
import SwiftUI

extension TagColor {
    var color: Color {
        switch self {
        case .red: .red
        case .orange: .orange
        case .yellow: .yellow
        case .green: .green
        case .mint: .mint
        case .teal: .teal
        case .blue: .blue
        case .indigo: .indigo
        case .purple: .purple
        case .pink: .pink
        case .brown: .brown
        case .gray: .gray
        }
    }
}

extension Entry {
    var sortedTags: [Tag] {
        (tags ?? []).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

struct TagChip: View {
    let name: String
    let color: TagColor
    var isSelected = true

    init(name: String, color: TagColor, isSelected: Bool = true) {
        self.name = name
        self.color = color
        self.isSelected = isSelected
    }

    init(tag: Tag, isSelected: Bool = true) {
        self.init(name: tag.name, color: tag.color, isSelected: isSelected)
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color.color)
                .frame(width: 7, height: 7)
            Text(name)
        }
        .font(.caption.weight(.medium))
        .padding(.horizontal, 9)
        .padding(.vertical, 4)
        .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        .background(isSelected ? color.color.opacity(0.16) : Color.clear, in: Capsule())
        .overlay(Capsule().strokeBorder(isSelected ? Color.clear : Color.secondary.opacity(0.35), lineWidth: 1))
    }
}

/// Lays subviews out left to right, wrapping onto new rows.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var width: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > maxWidth {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
            width = max(width, x - spacing)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX && x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

struct TagEditorView: View {
    let tag: Tag?
    /// Names of the other tags, to keep names unique.
    let otherNames: [String]

    @State private var name: String
    @State private var color: TagColor
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    init(tag: Tag?, otherNames: [String]) {
        self.tag = tag
        self.otherNames = otherNames
        _name = State(initialValue: tag?.name ?? "")
        _color = State(initialValue: tag?.color ?? .blue)
    }

    private var trimmed: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        otherNames.contains { $0.caseInsensitiveCompare(trimmed) == .orderedSame }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $name)
                } footer: {
                    if isDuplicate {
                        Text("There's already a tag called “\(trimmed)”.").foregroundStyle(.red)
                    }
                }

                Section("Color") {
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 6), spacing: 14) {
                        ForEach(TagColor.allCases) { option in
                            Button { color = option } label: {
                                Circle()
                                    .fill(option.color)
                                    .frame(width: 32, height: 32)
                                    .overlay {
                                        if option == color {
                                            Image(systemName: "checkmark")
                                                .font(.caption.weight(.bold))
                                                .foregroundStyle(.white)
                                        }
                                    }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(option.rawValue.capitalized)
                            .accessibilityAddTraits(option == color ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 6)
                }

                if !trimmed.isEmpty {
                    Section("Preview") {
                        TagChip(name: trimmed, color: color)
                    }
                }
            }
            .navigationTitle(tag == nil ? "New Tag" : "Edit Tag")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        save()
                        dismiss()
                    }
                    .disabled(trimmed.isEmpty || isDuplicate)
                }
            }
        }
    }

    private func save() {
        if let tag {
            tag.name = trimmed
            tag.color = color
        } else {
            context.insert(Tag(name: trimmed, color: color))
        }
    }
}
