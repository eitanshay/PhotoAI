import SwiftUI
import SwiftData

struct LibraryView: View {
    @Environment(EnhanceSession.self) private var session
    @Query(sort: \LibraryItem.createdAt, order: .reverse) private var items: [LibraryItem]

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Library").font(ESFont.h2).tracking(-0.9).foregroundStyle(ES.ink)
                    Spacer()
                    if !items.isEmpty { MonoLabel("\(items.count) saved") }
                }
                if items.isEmpty {
                    VStack(spacing: 8) {
                        MonoLabel("nothing here yet")
                        Text("Every enhanced photo is kept here on this iPhone.")
                            .font(ESFont.small).foregroundStyle(ES.ink2).multilineTextAlignment(.center)
                    }
                    .padding(.vertical, 44)
                    .frame(maxWidth: .infinity)
                    .background(StripeFill().clipShape(RoundedRectangle(cornerRadius: ES.radiusXl, style: .continuous)))
                } else {
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(items) { item in
                            LibraryTile(item: item)
                                .onTapGesture { session.open(item) }
                                .contextMenu {
                                    Button("Open") { session.open(item) }
                                    Button("Delete", role: .destructive) { session.delete(item) }
                                }
                        }
                    }
                }
            }
            .panelSurface(padding: 18)
            .padding(.horizontal, ES.gutter)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
    }
}

struct LibraryTile: View {
    let item: LibraryItem
    @State private var image: UIImage?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                StripeFill()
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .frame(height: 150)
            .frame(maxWidth: .infinity)
            .clipped()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Badge(text: item.category, tone: .signal)
                    if let s = item.faceScore {
                        Badge(text: "\(s)/10", tone: s >= FaceVerdict.passScore ? .ok : .warn)
                    }
                }
                Text("\(item.subject) · \(item.createdAt.formatted(.dateTime.month(.abbreviated).day()))")
                    .font(ESFont.mono(11, .regular))
                    .foregroundStyle(ES.ink2)
                    .lineLimit(1)
            }
            .padding(12)
        }
        .background(ES.paper)
        .clipShape(RoundedRectangle(cornerRadius: ES.radiusLg, style: .continuous))
        .contentShape(RoundedRectangle(cornerRadius: ES.radiusLg, style: .continuous))
        .task(id: item.resultFile) {
            let name = item.resultFile
            image = await Task.detached(priority: .utility) { LibraryFiles.image(name, maxSide: 600) }.value
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
