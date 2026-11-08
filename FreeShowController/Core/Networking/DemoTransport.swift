import Foundation

@MainActor
final class SwitchableRemoteTransport: RemoteTransport {
    var receive: ((RemoteEvent) -> Void)?
    private let live: any RemoteTransport
    private let demo: any RemoteTransport
    private(set) var isDemo = false
    private var token = UUID()
    private var selected: any RemoteTransport { isDemo ? demo : live }
    init(live: any RemoteTransport, demo: any RemoteTransport = DemoTransport()) { self.live = live; self.demo = demo }
    func useDemo(_ value: Bool) { disconnect(); isDemo = value }
    func connect(to url: URL) {
        let current = token
        selected.receive = { [weak self] event in
            guard let self, self.token == current else { return }
            self.receive?(event)
        }
        selected.connect(to: url)
    }
    func emit(_ message: RemoteMessage) throws { try selected.emit(message) }
    func disconnect() {
        token = UUID(); live.receive = nil; demo.receive = nil
        live.disconnect(); demo.disconnect()
    }
}

/// Explicit offline rehearsal. These original sample sentences are not Bible content.
@MainActor
final class DemoTransport: RemoteTransport {
    var receive: ((RemoteEvent) -> Void)?
    private var output: JSONValue = .object(["slide": .object(["id": .string("welcome"), "layout": .string("main"), "index": .number(0)])])
    private var restored: JSONValue = .object(["slide": .null])
    private var activeProject = "service"
    private let projects: JSONValue = .object([
        "service": .object(["name": .string("Sunday service · Demo"), "shows": .array([
            .object(["id": .string("welcome"), "name": .string("Welcome"), "type": .string("show")]),
            .object(["id": .string("song"), "name": .string("Opening song"), "type": .string("show")]),
            .object(["id": .string("notes"), "name": .string("Message notes"), "type": .string("show")]),
            .object(["id": .string("song"), "name": .string("Closing reprise"), "type": .string("show")]),
            .object(["id": .string("demo-document"), "name": .string("Announcements document"), "type": .string("pdf")])
        ])]),
        "rehearsal": .object(["name": .string("Rehearsal · Demo"), "shows": .array([])])
    ])
    private var library: JSONValue {
        .object([
            "welcome": Self.show("Welcome", texts: ["Welcome\nWe’re glad you’re here.", "This week\nCommunity meal · Wednesday, 6 pm", "Take a moment\nPrepare for worship."]),
            "song": Self.show("Opening song", texts: ["Opening verse\nA sample song for rehearsal.", "Chorus\nPractice moving confidently between slides.", "Final verse\nThese are original demo words."]),
            "notes": Self.show("Message notes", texts: ["Today’s message\nA place for your service notes.", "Reflect\nListen. Consider. Respond.", "Closing\nThank you for joining us."])
        ])
    }
    private static func show(_ name: String, texts: [String]) -> JSONValue {
        let ids = texts.indices.map { "slide\($0)" }
        return .object(["name": .string(name), "settings": .object(["activeLayout": .string("main")]),
            "layouts": .object(["main": .object(["slides": .array(ids.map { .object(["id": .string($0)]) })])]),
            "slides": .object(Dictionary(uniqueKeysWithValues: zip(ids, texts).map { id, text in
                (id, .object(["group": .string(""), "items": .array([.object(["lines": .array(text.split(separator: "\n").map {
                    .object(["text": .array([.object(["value": .string(String($0))])])])
                })])])]))
            }))])
    }
    func connect(to url: URL) { receive?(.connected) }
    func disconnect() {}
    private func reply(_ channel: String, _ data: JSONValue) { receive?(.message(RemoteMessage(channel: channel, data: data))) }
    func emit(_ message: RemoteMessage) throws {
        let data = message.data
        if message.channel == "PASSWORD" {
            reply("ACCESS", .null)
            reply("PROJECTS", projects); reply("PROJECT", .string(activeProject)); reply("SHOWS", library)
            reply("OUT_DATA", output)
            reply("SCRIPTURE", .object(["demo": .object(["name": .string("Demo text — not a Bible translation")])]))
            return
        }
        if message.channel == "GET_SCRIPTURE" {
            reply(message.channel, .object(["id": .string("demo"), "bible": .object([
                "copyright": .string("Original demonstration text. Connect to FreeShow to use real translations."),
                "books": .array([.object(["number": .number(1), "name": .string("Sample"), "chapters": .array([
                    .object(["number": .number(1), "verses": .array((1...3).map { .object(["number": .number(Double($0)),
                        "text": .string("Demo passage, sample verse \($0). This is demonstration text, not scripture.")]) })])
                ])])])])]))
            return
        }
        guard message.channel.hasPrefix("API:") else { return }
        let action = String(message.channel.dropFirst(4))
        var result: JSONValue = .null
        switch action {
        case "get_projects": result = projects
        case "get_shows": result = library
        case "get_show": result = library[data["id"].string ?? ""]
        case "get_output": result = output
        case "get_slide_thumbnail": result = .string("")
        case "get_pdf_thumbnails":
            // Tiny original fixture image; real PDF pages are rendered by the desktop.
            let image = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX1sAAAAASUVORK5CYII="
            result = .object(["path": data["path"], "pages": .array([.string(image), .string(image)])])
        case "get_cleared":
            let cleared = output["slide"] == .null
            result = .object(Dictionary(uniqueKeysWithValues: ["all", "background", "slide", "overlays", "audio", "slideTimers"].map { ($0, .bool(cleared)) }))
        case "id_select_project":
            activeProject = data["id"].string ?? activeProject; reply("PROJECT", .string(activeProject))
        case "index_select_slide":
            output = .object(["slide": .object(["id": data["showId"], "layout": data["layoutId"], "index": data["index"]])])
        case "next_slide", "previous_slide":
            if output["slide"]["type"].string == "pdf" {
                let page = min(max(0, (output["slide"]["page"].nonnegativeInt ?? 0) + (action == "next_slide" ? 1 : -1)), 1)
                output = .object(["slide": .object(["type": .string("pdf"), "id": .string("demo-document"), "name": .string("Announcements document"), "page": .number(Double(page)), "pages": .number(2)])])
            } else if let id = output["slide"]["id"].string, id != "temp", let current = output["slide"]["index"].nonnegativeInt {
                let presentation = try PresentationDecoder.presentation(library[id], id: id)
                let index = min(max(0, current + (action == "next_slide" ? 1 : -1)), max(0, presentation.slides.count - 1))
                output = .object(["slide": .object(["id": .string(id), "layout": .string("main"), "index": .number(Double(index))])])
            }
        case "name_start_project_item":
            if data["value"].string == "Announcements document" {
                output = .object(["slide": .object(["type": .string("pdf"), "id": .string("demo-document"), "name": .string("Announcements document"), "page": .number(0), "pages": .number(2)])])
            }
        case "play_media":
            output = .object(["slide": .object(["type": .string("pdf"), "id": data["path"], "page": data["index"], "pages": data["data"]["pageCount"], "name": .string("Announcements document")])])
        case "clear_all": restored = output; output = .object(["slide": .null])
        case "restore_output": output = restored
        case "start_scripture": output = .object(["slide": .object(["id": .string("temp")])])
        default: break
        }
        if !action.hasPrefix("get_") { reply("OUT_DATA", output) }
        reply(message.channel, result)
    }
}
