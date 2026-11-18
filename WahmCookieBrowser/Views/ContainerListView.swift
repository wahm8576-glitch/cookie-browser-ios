import SwiftUI

struct ContainerListView: View {
    @EnvironmentObject private var store: ContainerStore
    @State private var renaming: BrowserContainer?
    @State private var renameText: String = ""
    @State private var pendingDelete: BrowserContainer?

    var body: some View {
        NavigationStack {
            Group {
                if store.containers.isEmpty {
                    emptyState
                } else {
                    containerList
                }
            }
            .navigationTitle("الأقسام")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("متصفح وهم  v3")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.addContainer()
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.title2)
                    }
                    .accessibilityLabel("إضافة قسم")
                }
            }
            .alert("إعادة تسمية القسم", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("اسم القسم", text: $renameText)
                Button("حفظ") {
                    if let renaming {
                        store.rename(renaming, to: renameText)
                    }
                    self.renaming = nil
                }
                Button("إلغاء", role: .cancel) {
                    renaming = nil
                }
            }
            .confirmationDialog(
                "حذف القسم؟",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("حذف القسم وكوكيزه", role: .destructive) {
                    if let pendingDelete {
                        store.delete(pendingDelete)
                    }
                    self.pendingDelete = nil
                }
                Button("إلغاء", role: .cancel) {
                    pendingDelete = nil
                }
            } message: {
                Text("سيتم حذف جلسة هذا القسم والكوكيز المحفوظة فيه. الأقسام الأخرى لن تتأثر.")
            }
        }
    }

    private var containerList: some View {
        List {
            Section {
                ForEach(store.containers) { container in
                    NavigationLink {
                        BrowserView(container: container)
                    } label: {
                        ContainerRow(container: container)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            pendingDelete = container
                        } label: {
                            Label("حذف", systemImage: "trash")
                        }
                        Button {
                            renameText = container.name
                            renaming = container
                        } label: {
                            Label("إعادة تسمية", systemImage: "pencil")
                        }
                        .tint(.indigo)
                    }
                    .contextMenu {
                        Button {
                            renameText = container.name
                            renaming = container
                        } label: {
                            Label("إعادة تسمية", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            pendingDelete = container
                        } label: {
                            Label("حذف", systemImage: "trash")
                        }
                    }
                }
            } header: {
                Text("كل قسم جلسة مستقلة تماماً عن الباقي، وتنحفظ بعد إغلاق التطبيق.")
                    .textCase(nil)
                    .font(.footnote)
            }
        }
        .listStyle(.insetGrouped)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "square.grid.2x2")
                .font(.system(size: 56))
                .foregroundStyle(.tertiary)
            Text("لا توجد أقسام بعد")
                .font(.title2.weight(.bold))
            Text("أضف قسماً لبدء التصفح. كل قسم يحتفظ بجلسته وكوكيزه بشكل مستقل.")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Button {
                store.addContainer()
            } label: {
                Label("إضافة قسم", systemImage: "plus")
                    .font(.headline)
                    .padding(.horizontal, 8)
            }
            .buttonStyle(.borderedProminent)
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ContainerRow: View {
    let container: BrowserContainer

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "globe")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(container.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(container.lastHost ?? "لا يوجد موقع مفتوح بعد")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
    }
}
