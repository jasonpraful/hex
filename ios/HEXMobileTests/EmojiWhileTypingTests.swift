import Foundation
import XCTest
@testable import HEX

/// Emoji while typing (Settings › Experiments): the emoji for the word being typed, before its
/// space, as Apple's bar offers them ("wave" → 👋 🌊), the tap that puts one and a space in the
/// word's place, and the strip's last slot split between two of them.
@MainActor
final class EmojiWhileTypingTests: XCTestCase {
    private static var libraries: [String: EmojiLibrary] = [:]

    private func library(_ language: String = "en") throws -> EmojiLibrary {
        if let cached = Self.libraries[language] { return cached }
        let loaded = try XCTUnwrap(EmojiLibrary.load(language: language, bundle: Bundle(for: FullKeyboardView.self)))
        Self.libraries[language] = loaded
        return loaded
    }

    private func typed(_ text: String?) throws -> [String] {
        let library = try library()
        return EmojiSuggester.forTypedWord(text, library: library)?.entries.map { library.entries[$0].emoji } ?? []
    }

    // MARK: - Matching

    func testTheWordBeingTypedOffersItsEmojiBeforeTheSpace() throws {
        XCTAssertEqual(try typed("wave"), ["👋", "🌊"])
        XCTAssertEqual(try typed("what is this hello"), ["👋", "😊"])
        XCTAssertEqual(try typed("Hello"), ["👋", "😊"], "case doesn't matter")
        XCTAssertEqual(try typed("the ocean"), ["🌊", "🐳"])
        XCTAssertEqual(try typed("pizza"), ["🍕"], "one emoji when the word has one")
    }

    func testTheTokenIsTheWordAsTyped() throws {
        let library = try library()
        XCTAssertEqual(EmojiSuggester.forTypedWord("what is this Hello", library: library)?.token, "Hello")
        XCTAssertEqual(EmojiSuggester.forTypedWord("wave", library: library)?.token, "wave")
    }

    func testOnlyWholeWordsBeforeTheCursor() throws {
        XCTAssertEqual(try typed("wav"), [], "a prefix is not the word, as on Apple's bar")
        XCTAssertEqual(try typed("wavw"), [])
        XCTAssertEqual(try typed("wave "), [], "after the space the finished word's emoji answers instead")
        XCTAssertEqual(try typed("wave,"), [])
        XCTAssertEqual(try typed(""), [])
        XCTAssertEqual(try typed(nil), [])
    }

    func testStopwordsAndAttachedTokensOfferNothing() throws {
        XCTAssertEqual(try typed("on the"), [])
        XCTAssertEqual(try typed("#wave"), [])
        XCTAssertEqual(try typed("@wave"), [])
        XCTAssertEqual(try typed("7wave"), [])
    }

    func testAWordOnlyLooselyLinkedToEmojiOffersNone() throws {
        XCTAssertEqual(try typed("face"), [], "a word many emoji only describe")
        XCTAssertEqual(try typed("water"), [])
    }

    // MARK: - The engine's replacement

    func testTheEmojiAndASpaceTakeTheWordsPlace() throws {
        let target = FixtureTextTarget()
        target.insertText("what is this hello")
        let engine = FullKeyboardEngine(target: target)
        XCTAssertTrue(engine.replaceTypedWord("hello", withEmoji: "🙋"))
        XCTAssertEqual(target.text, "what is this 🙋 ")
    }

    func testNothingChangesWhenTheWordIsNoLongerBeforeTheCursor() throws {
        let target = FixtureTextTarget()
        target.insertText("what is this")
        let engine = FullKeyboardEngine(target: target)
        XCTAssertFalse(engine.replaceTypedWord("hello", withEmoji: "🙋"))
        XCTAssertEqual(target.text, "what is this")
        XCTAssertFalse(engine.replaceTypedWord("", withEmoji: "🙋"))
        XCTAssertEqual(target.text, "what is this")
    }

    // MARK: - The keyboard

    func testTheKeyboardOffersAndReplacesWhileTheExperimentIsOn() throws {
        let settings = FullKeyboardSettings()
        let wasOn = settings.emojiWhileTyping
        defer { settings.emojiWhileTyping = wasOn }
        let suite = "anomaly.hex.tests.emoji-while-typing"
        let defaults = UserDefaults(suiteName: suite)
        defaults?.removePersistentDomain(forName: suite)
        defer { defaults?.removePersistentDomain(forName: suite) }

        let target = FixtureTextTarget()
        target.insertText("what is this hello")
        let view = FullKeyboardView(model: KeyboardViewModel(), target: target)
        view.emojiOverride = true
        let usage = EmojiUsageStore(defaults: defaults)
        view.makeEmojiUsage = { usage }

        settings.emojiWhileTyping = false
        view.syncSettings()
        XCTAssertNil(view.emojiForTypedWord(), "off, nothing changes")

        settings.emojiWhileTyping = true
        view.syncSettings()
        let offered = try XCTUnwrap(view.emojiForTypedWord())
        XCTAssertEqual(offered.map(\.replacement), ["👋", "😊"])
        XCTAssertTrue(offered.allSatisfy { $0.kind == .emoji })

        XCTAssertTrue(view.acceptEmojiForTypedWord(offered[0]))
        XCTAssertEqual(target.text, "what is this 👋 ")
        XCTAssertEqual(usage.ranked().first?.0, "👋", "counted like one from the panel")
        XCTAssertNil(view.emojiForTypedWord(), "nothing for the word once it is gone")
        XCTAssertFalse(view.acceptEmojiForTypedWord(offered[1]), "a chip left over is not the typed word's")
    }

    // MARK: - The strip

    func testTwoWordsAndTwoEmojiSplitTheLastSlot() {
        let words = [
            KeyboardSuggestion(displayText: "“wave”", replacement: "wave", kind: .keepLiteral),
            KeyboardSuggestion(displayText: "waves", replacement: "waves", kind: .primary(autoReplace: false)),
        ]
        let wave = KeyboardSuggestion(displayText: "👋", replacement: "👋", kind: .emoji)
        let sea = KeyboardSuggestion(displayText: "🌊", replacement: "🌊", kind: .emoji)

        let four = words + [wave, sea]
        XCTAssertTrue(KeyboardStripView.splitsLastSlot(four))
        XCTAssertEqual(KeyboardStripView.slots(for: four), [0, 1, 2, 3])

        let three = words + [wave]
        XCTAssertFalse(KeyboardStripView.splitsLastSlot(three))
        XCTAssertEqual(KeyboardStripView.slots(for: three), [0, 1, 2])

        let threeWords = words + [KeyboardSuggestion(displayText: "waved", replacement: "waved", kind: .secondary)]
        XCTAssertFalse(KeyboardStripView.splitsLastSlot(threeWords + [wave]), "only two words and two emoji split")
        XCTAssertEqual(KeyboardStripView.slots(for: threeWords + [wave]), [0, 1, 2])
        XCTAssertEqual(KeyboardStripView.slots(for: [wave]), [1], "a lone emoji keeps the centre")
    }

    // MARK: - Setting

    func testTheSettingIsOffByDefaultAndKeepsTheAppGroupKey() throws {
        let suite = "EmojiWhileTypingTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = FullKeyboardSettings(defaults: defaults)
        XCTAssertFalse(settings.emojiWhileTyping, "off, like every experiment")
        settings.emojiWhileTyping = true
        XCTAssertTrue(FullKeyboardSettings(defaults: defaults).emojiWhileTyping)
        XCTAssertTrue(defaults.bool(forKey: "experiments.emojiWhileTyping"))
    }
}
