//
//  CategorySettingsView.swift
//  AlarmDM
//
//  The category list, as something to arrange rather than something handed
//  down: rename what is yours, throw it away, and drag any of them - the
//  app's own included - into the order you actually use.
//

import SwiftUI

struct CategorySettingsView: View {

    @ObservedObject private var catalog = BookmarkCategories.shared

    @State private var isNaming = false
    @State private var newName = ""
    @State private var newIcon = BookmarkCatalog.customIcons[0]

    /// The one being renamed. A sheet rather than an inline field: the row is
    /// already a drag handle and a delete target, and a third thing to hit by
    /// accident is one too many.
    @State private var renaming: BookmarkCategoryItem?
    @State private var renamedTo = ""

    var body: some View {
        List {
            Section {
                ForEach(catalog.items) { item in
                    row(item)
                }
                .onMove(perform: move)
                .onDelete(perform: delete)
            } footer: {
                Text("Kategorije koje aplikacija donosi ne mogu se obrisati, ali mogu se preurediti. Redosled i tvoje kategorije se sinhronizuju sa ostalim uređajima.")
            }

            Section {
                Button {
                    newName = ""
                    newIcon = BookmarkCatalog.customIcons[0]
                    isNaming = true
                } label: {
                    Label("Nova kategorija", systemImage: "plus")
                }
            }
        }
        .navigationTitle("Kategorije")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { EditButton() }
        .sheet(isPresented: $isNaming) {
            CategoryEditorView(title: "Nova kategorija",
                               name: $newName,
                               icon: $newIcon,
                               showsIcons: true) {
                catalog.add(name: newName, iconName: newIcon)
                isNaming = false
            } onCancel: {
                isNaming = false
            }
        }
        .sheet(item: $renaming) { item in
            CategoryEditorView(title: "Preimenuj",
                               name: $renamedTo,
                               icon: .constant(item.customIcon ?? BookmarkCatalog.customIcons[0]),
                               showsIcons: false) {
                catalog.rename(item.id, to: renamedTo)
                renaming = nil
            } onCancel: {
                renaming = nil
            }
        }
    }

    private func row(_ item: BookmarkCategoryItem) -> some View {
        HStack(spacing: 12) {
            BookmarkCategoryIcon(item, size: 26)
            Text(item.title)
            Spacer(minLength: 0)
            if item.isBuiltIn {
                // Said rather than shown as a disabled control: the row is not
                // broken, it is simply not yours to rename.
                Text("Ugrađena")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard !item.isBuiltIn else { return }
            renamedTo = item.title
            renaming = item
        }
        // Built-ins refuse the swipe rather than offering it and then doing
        // nothing, which is the shape of a bug even when it is a rule.
        .deleteDisabled(item.isBuiltIn)
    }

    private func move(from offsets: IndexSet, to destination: Int) {
        var ids = catalog.items.map(\.id)
        ids.move(fromOffsets: offsets, toOffset: destination)
        catalog.rearrange(toOrder: ids)
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let item = catalog.items[index]
            guard !item.isBuiltIn else { continue }
            catalog.delete(item.id)
        }
    }
}

/// Naming one, and choosing its drawing when it is new. Renaming does not
/// offer the drawing again - that is a second decision, and the row it is
/// reached from already shows which one it wears.
private struct CategoryEditorView: View {

    let title: LocalizedStringKey
    @Binding var name: String
    @Binding var icon: String
    let showsIcons: Bool
    let onSave: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Ime kategorije", text: $name)
                }

                if showsIcons {
                    Section("Znak") {
                        HStack(spacing: 14) {
                            ForEach(BookmarkCatalog.customIcons, id: \.self) { candidate in
                                Button { icon = candidate } label: {
                                    BookmarkCategoryIcon(
                                        BookmarkCategoryItem(id: candidate, builtIn: nil,
                                                             customName: "", customIcon: candidate,
                                                             sortOrder: 0),
                                        size: 40
                                    )
                                    .overlay(
                                        Circle().strokeBorder(Color("primaryLink"),
                                                              lineWidth: icon == candidate ? 3 : 0)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityAddTraits(icon == candidate ? [.isSelected] : [])
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Otkaži", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Sačuvaj", action: onSave)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}
