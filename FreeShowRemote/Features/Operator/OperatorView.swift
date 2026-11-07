import SwiftUI
import UIKit

struct OperatorView: View {
    @ObservedObject var store: OperatorStore
    @ObservedObject var discovery: BonjourDiscovery
    @State private var showConnection = false
    @State private var confirmClear = false
    @State private var confirmProject = false
    @State private var confirmPresent = false
    @State private var confirmMedia = false
    @State private var mediaIntent: ProjectItemIntent?
    @State private var intent: PresentIntent?
    @State private var compactPane = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .body) private var previewSize = 18

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                statusBar
                if store.snapshot.projects.isEmpty && store.phase != .connected {
                    ContentUnavailableView {
                        Label("Your service, within reach", systemImage: "rectangle.on.rectangle")
                    } description: {
                        Text("Connect to FreeShow to browse the service, preview slides, and control live output.")
                    } actions: {
                        Button("Connect to FreeShow") { showConnection = true }.buttonStyle(.borderedProminent)
                        Button("Try offline demo") { store.startDemo() }.buttonStyle(.bordered)
                    }
                } else {
                    GeometryReader { geometry in
                        if geometry.size.width >= 1050 && !dynamicTypeSize.isAccessibilitySize {
                            HStack(alignment: .top, spacing: 0) {
                                playlist.frame(width: max(235, geometry.size.width * 0.23))
                                Divider()
                                slides.frame(maxWidth: .infinity)
                                Divider()
                                ScrollView { liveControls.padding() }.frame(width: max(290, geometry.size.width * 0.28))
                            }
                        } else {
                            VStack(spacing: 0) {
                                Picker("Browse", selection: $compactPane) {
                                    Text("Service").tag(0); Text("Slides").tag(1); Text("Live & preview").tag(2)
                                }.pickerStyle(.segmented).padding(.horizontal).padding(.bottom, 8)
                                if compactPane == 0 { playlist }
                                else if compactPane == 1 { slides }
                                else { ScrollView { liveControls.padding() } }
                            }
                        }
                    }
                }
                if !store.snapshot.projects.isEmpty || store.phase == .connected {
                    Divider()
                    controlDock.padding(.horizontal).padding(.vertical, 8).background(.bar)
                }
            }
            .navigationTitle(store.isDemo ? "FreeShow · Demo" : "FreeShow Remote")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showConnection = true } label: { Label("Connection", systemImage: "antenna.radiowaves.left.and.right") }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button { store.followLive(); compactPane = 1 } label: { Label("Go to live slide", systemImage: "scope") }
                        .disabled(store.currentReference == nil || store.isStale)
                    Button { store.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                        .disabled(store.phase != .connected)
                }
            }
            .sheet(isPresented: $showConnection) {
                OperatorConnectionView(store: store, discovery: discovery)
                    .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { showConnection = false } } }
            }
            .confirmationDialog("Present this slide on active outputs?", isPresented: $confirmPresent, titleVisibility: .visible) {
                Button("Present slide") { if let intent { store.present(intent) } }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(intent.map { "\($0.presentation.name) · slide \($0.slide.index + 1)" } ?? "Select a slide first.")
            }
            .confirmationDialog("Start this item on active outputs?", isPresented: $confirmMedia, titleVisibility: .visible) {
                Button("Start item") { if let mediaIntent { store.startProjectItem(mediaIntent) } }
                Button("Cancel", role: .cancel) {}
            } message: { Text(mediaIntent.map { "\($0.item.kind.capitalized) · \($0.item.name)" } ?? "Select a supported item first.") }
            .confirmationDialog("Clear all active outputs?", isPresented: $confirmClear, titleVisibility: .visible) {
                Button("Clear all outputs", role: .destructive) { store.send(.clear) }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This includes audio, backgrounds, overlays, and timers. Desktop locks still apply.") }
            .confirmationDialog("Select this project on the desktop?", isPresented: $confirmProject, titleVisibility: .visible) {
                Button("Select project") { store.activateSelectedProject() }
                Button("Cancel", role: .cancel) {}
            } message: { Text("This changes the desktop's active service project. Browsing alone does not change it.") }
            .onChange(of: store.phase) { _, phase in
                if phase != .connected { confirmPresent = false; confirmMedia = false; confirmClear = false; confirmProject = false }
            }
        }
    }

    private var statusBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                ConnectionIndicator(phase: store.phase, demo: store.isDemo)
                Spacer()
                if store.isSending { ProgressView().accessibilityLabel("Sending command") }
                if store.phase == .reconnecting || store.phase == .authenticationRequired || isFailed {
                    Button("Connection…") { showConnection = true }.font(.subheadline)
                }
            }
            if !store.snapshot.projects.isEmpty {
                Text([store.livePresentation?.name, outputLabel].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption.weight(.medium)).lineLimit(2)
            }
            if store.isStale && !store.snapshot.projects.isEmpty { Text("Last service data is stale. Live controls are disabled until synchronization completes.").font(.caption).foregroundStyle(.orange) }
            if store.commandOutcomeUnknown {
                Text("An interrupted command may have run. Check desktop output before continuing.").font(.callout).foregroundStyle(.orange)
                Button("I checked the output") { store.acknowledgeUncertainCommand() }.font(.callout)
            }
            if let error = store.errorMessage { Text(error).font(.caption).foregroundStyle(.red).lineLimit(3) }
            if let message = store.message { Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2) }
        }.padding(.horizontal).padding(.vertical, 10).frame(maxWidth: .infinity, alignment: .leading).background(.bar)
    }
    private var isFailed: Bool { if case .failed = store.phase { true } else { false } }
    private var playlist: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SERVICE").font(.caption.weight(.bold)).foregroundStyle(.secondary).padding(.horizontal).padding(.top)
            Picker("Project to browse", selection: Binding(get: { store.selectedProjectID }, set: { store.selectProject($0) })) {
                ForEach(store.snapshot.projects) { project in
                    Text(project.name + (project.id == store.snapshot.activeProjectID ? " · Desktop" : "")).tag(project.id)
                }
            }.padding(.horizontal).disabled(store.isSending)
            HStack {
                Button("Follow desktop") { store.followDesktopProject() }
                Spacer()
                Button("Select on desktop…") { confirmProject = true }.disabled(!store.canControl || store.selectedProjectID == store.snapshot.activeProjectID)
            }.font(.caption).padding(.horizontal)
            List {
                if let project = store.selectedProject, !project.items.isEmpty {
                    ForEach(project.items) { item in
                        Button { store.selectItem(item); compactPane = 1 } label: {
                            HStack(alignment: .top) {
                                Image(systemName: item.kind == "show" ? "rectangle.stack" : "doc")
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(item.name).font(.headline).foregroundStyle(.primary)
                                    HStack {
                                        Text(item.kind.capitalized).font(.caption).foregroundStyle(.secondary)
                                        if store.phase == .connected && store.outputItemID != nil && store.outputItemID == item.presentationID { badge("ON OUTPUT", color: .green) }
                                        if store.selectedItemID == item.id { badge("PREVIEW", color: .accentColor) }
                                    }
                                }
                            }.frame(minHeight: 48, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                        }.disabled(store.isSending)
                            .listRowBackground(store.selectedItemID == item.id ? Color.accentColor.opacity(0.10) : Color.clear)
                            .accessibilityLabel("\(item.name), \(item.kind)\(store.selectedItemID == item.id ? ", preview selected" : "")")
                    }
                } else { Text("This project has no service items.").foregroundStyle(.secondary) }
            }.listStyle(.plain)
            Text("Browsing leaves output unchanged. Present or Start item is explicit.").font(.caption).foregroundStyle(.secondary).padding()
        }
    }
    private var slides: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading) {
                    Text(store.presentation?.name ?? "SLIDES").font(.headline)
                    Text(store.followsLive ? "Following live output" : "Preview selection · output unchanged").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if store.isLoading { ProgressView().accessibilityLabel("Loading slides") }
            }.padding()
            if let presentation = store.presentation, !presentation.slides.isEmpty {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                            ForEach(presentation.slides) { slide in
                                Button { store.selectSlide(slide) } label: { slideCard(slide) }
                                    .buttonStyle(.plain).disabled(slide.isDisabled || store.isSending).id(slide.id)
                                    .onAppear { store.thumbnailVisible(slide.id) }
                                    .onDisappear { store.thumbnailHidden(slide.id) }
                            }
                        }.padding()
                    }
                    .onChange(of: store.currentReference) { _, ref in
                        if store.followsLive, let ref { withAnimation(.easeInOut(duration: 0.15)) { proxy.scrollTo(ref, anchor: .center) } }
                    }
                }
            } else {
                ContentUnavailableView(store.selectedItem?.canStartByName == true ? "\(store.selectedItem?.kind.capitalized ?? "Media") selected" : "Choose a presentation", systemImage: "square.grid.2x2", description: Text(store.selectedItem?.canStartByName == true ? "Use Start item in the dock after selecting this project on the desktop. FreeShow renders the media; PDF pages use Next/Previous. Native shows have the slide grid." : "Select a native show from the service to see its ordered slides. Empty shows and unsupported types have no slide navigator."))
            }
        }
    }
    private func slideCard(_ slide: Slide) -> some View {
        let selected = store.selectedSlide == slide.id
        let live = store.phase == .connected && store.currentReference == slide.id
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(slide.id.index + 1)").font(.caption.monospacedDigit().bold())
                if !slide.group.isEmpty { Text(slide.group).font(.caption).lineLimit(1) }
                Spacer()
                if live { badge("LIVE", color: .green) }
                if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(Color.accentColor) }
            }
            if let image = image(for: slide.id) { image.resizable().scaledToFit().frame(maxHeight: 140).clipShape(RoundedRectangle(cornerRadius: 6)) }
            Text(slide.text.isEmpty ? "Visual slide · text unavailable" : slide.text)
                .font(.body).lineLimit(6).frame(maxWidth: .infinity, minHeight: 105, alignment: .topLeading)
            if slide.isDisabled { Text("Disabled on desktop").font(.caption).foregroundStyle(.secondary) }
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(selected ? Color.accentColor.opacity(0.10) : Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(live ? Color.green : selected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: live || selected ? 2 : 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Slide \(slide.id.index + 1). \(slide.text). \(live ? "Live." : "") \(selected ? "Preview selected." : "") \(slide.isDisabled ? "Disabled." : "")")
    }
    private var liveControls: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("LIVE OUTPUT").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(outputLabel).font(.headline)
            if let slide = store.currentSlide {
                Text(store.livePresentation?.name ?? "").font(.caption).foregroundStyle(.secondary)
                previewBox(slide.text, caption: "CURRENT · SLIDE \(slide.id.index + 1)")
            }
            if let next = store.nextSlide { previewBox(next.text, caption: "NEXT · SLIDE \(next.id.index + 1)") }
            Text("Monitor: first active output. Commands may affect all active outputs; desktop locks apply.").font(.caption).foregroundStyle(.secondary)
            Divider()
            Text("SELECTED PREVIEW").font(.caption.weight(.bold)).foregroundStyle(.secondary)
            if let slide = store.previewSlide, let presentation = store.presentation {
                Text("\(presentation.name) · slide \(slide.id.index + 1)").font(.headline)
                if let image = image(for: slide.id) { image.resizable().scaledToFit().clipShape(RoundedRectangle(cornerRadius: 8)) }
                Text(slide.text.isEmpty ? "This visual slide has no text preview." : slide.text).font(.system(size: previewSize)).textSelection(.enabled)
                Button("Present selected slide…") {
                    intent = PresentIntent(slide: slide.id, presentation: presentation); confirmPresent = true
                }.buttonStyle(.borderedProminent).controlSize(.large).disabled(!store.canControl || slide.isDisabled)
                Button(store.thumbnailLoading ? "Loading image…" : "Load rendered preview") { store.loadSelectedThumbnail() }
                    .disabled(store.thumbnailLoading || store.phase != .connected || store.thumbnails[slide.id] != nil)
                Text("Rendering depends on desktop output availability. Text remains the fallback.").font(.caption).foregroundStyle(.secondary)
            } else if let item = store.selectedItem {
                Text(item.name).font(.headline)
                Text("\(item.kind.capitalized) · desktop-rendered item").foregroundStyle(.secondary)
                if item.canStartByName {
                    Text("A uniquely named item in the active desktop project can be started after confirmation. Its media content is rendered by FreeShow.").font(.callout)
                    if store.selectedProjectID != store.snapshot.activeProjectID { Text("Select this project on the desktop first.").font(.caption).foregroundStyle(.secondary) }
                } else { Text("This item needs desktop control or a unique supported media name.").foregroundStyle(.secondary) }
            } else { Text("Choose a slide to preview it before presenting.").foregroundStyle(.secondary) }
            if store.snapshot.receivedAt != .distantPast {
                Text("Desktop update: \(store.snapshot.receivedAt.formatted(date: .omitted, time: .standard))").font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var controlDock: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 8) { compactControls; utilityControls; presentButton }
            } else {
                HStack(spacing: 16) {
                    compactControls.frame(maxWidth: 360)
                    utilityControls
                    Spacer(minLength: 0)
                    presentButton
                }
            }
        }
    }
    private var utilityControls: some View {
        HStack(spacing: 10) {
            Button("Clear all…", role: .destructive) { confirmClear = true }.frame(minHeight: 44)
            Button("Restore") { store.send(.restore) }.frame(minHeight: 44)
        }.buttonStyle(.bordered).disabled(!store.canControl)
    }
    private var presentButton: some View {
        Button(store.selectedItem?.canStartByName == true ? "Start item…" : "Present slide…") {
            if let item = store.selectedItem, item.canStartByName {
                mediaIntent = ProjectItemIntent(projectID: store.selectedProjectID, item: item); confirmMedia = true
            } else if let slide = store.previewSlide, let presentation = store.presentation {
                intent = PresentIntent(slide: slide.id, presentation: presentation); confirmPresent = true
            }
        }
        .frame(minHeight: 44).buttonStyle(.borderedProminent)
        .disabled(store.selectedItem?.canStartByName == true ? !store.canStartSelectedItem : (!store.canControl || store.previewSlide == nil || store.previewSlide?.isDisabled == true))
    }
    private var compactControls: some View {
        HStack(spacing: 12) {
            Button { store.send(.previous) } label: { Label("Previous", systemImage: "backward.end.fill").frame(maxWidth: .infinity, minHeight: 44) }
                .keyboardShortcut("[", modifiers: .command)
            Button { store.send(.next) } label: { Label("Next", systemImage: "forward.end.fill").frame(maxWidth: .infinity, minHeight: 44) }
                .keyboardShortcut("]", modifiers: .command)
        }.buttonStyle(.borderedProminent).disabled(!store.canControl)
    }
    private func previewBox(_ text: String, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption).font(.caption.weight(.bold)).foregroundStyle(.secondary)
            Text(text.isEmpty ? "Visual slide" : text).lineLimit(8).frame(maxWidth: .infinity, minHeight: 80, alignment: .topLeading)
        }.padding(12).background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
    }
    private func badge(_ text: String, color: Color) -> some View {
        Text(text).font(.caption2.bold()).foregroundStyle(color).padding(.horizontal, 5).padding(.vertical, 3).background(color.opacity(0.12), in: Capsule())
    }
    private func image(for ref: SlideReference) -> Image? {
        guard let data = store.thumbnails[ref], let image = UIImage(data: data) else { return nil }
        return Image(uiImage: image)
    }
    private var outputLabel: String {
        if store.isStale { return "Output state unknown / stale" }
        return switch store.snapshot.output {
        case .unknown: "Output state unknown"
        case .cleared: "All output cleared at last check"
        case .live(let ref): "Live · slide \(ref.index + 1)"
        case .other(let label): label
        }
    }
}
