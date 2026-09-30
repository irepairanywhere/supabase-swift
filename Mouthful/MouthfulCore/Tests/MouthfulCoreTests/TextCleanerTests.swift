import XCTest
@testable import MouthfulCore

final class TextCleanerTests: XCTestCase {
  func testRemovesFillerWordsAndKeepsPunctuation() {
    XCTAssertEqual(TextCleaner.clean("Um, I think we should, uh, ship it."), "I think we should ship it.")
    XCTAssertEqual(TextCleaner.clean("So I, um, think that works."), "So I think that works.")
    XCTAssertEqual(TextCleaner.clean("that is the plan um."), "That is the plan.")
  }

  func testDoesNotTouchWordsContainingFillers() {
    XCTAssertEqual(TextCleaner.clean("Bring an umbrella and a hummus wrap."), "Bring an umbrella and a hummus wrap.")
    XCTAssertEqual(TextCleaner.clean("She said uh-huh."), "She said uh-huh.")
  }

  func testCollapsesRepeatedWords() {
    XCTAssertEqual(TextCleaner.clean("I I think the the plan is is good."), "I think the plan is good.")
  }

  func testLineCommands() {
    XCTAssertEqual(TextCleaner.clean("Hi Sam. New line. Thanks for today. New paragraph. Best, Alex"),
                   "Hi Sam.\nThanks for today.\n\nBest, Alex")
  }

  func testPunctuationCommandsAreOptIn() {
    let raw = "hello comma how are you question mark"
    XCTAssertEqual(TextCleaner.clean(raw), "Hello comma how are you question mark")
    var options = CleanupOptions()
    options.processPunctuationCommands = true
    XCTAssertEqual(TextCleaner.clean(raw, options: options), "Hello, how are you?")
  }

  func testCapitalization() {
    XCTAssertEqual(TextCleaner.clean("this is one. this is two! is this three? yes"),
                   "This is one. This is two! Is this three? Yes")
    XCTAssertEqual(TextCleaner.clean("i think i will go"), "I think I will go")
    XCTAssertEqual(TextCleaner.clean("visit example.com today"), "Visit example.com today")
  }

  func testDictionaryReplacementsRunBeforeCleanup() {
    let dictionary = [DictionaryEntry(spoken: "super base", written: "Supabase"),
                      DictionaryEntry(spoken: "wisper flow", written: "Wispr Flow")]
    XCTAssertEqual(TextCleaner.clean("we moved the app to Super Base last week", dictionary: dictionary),
                   "We moved the app to Supabase last week")
  }

  func testStripsWhisperArtifacts() {
    XCTAssertEqual(TextCleaner.clean("[BLANK_AUDIO] Hello there (music)"), "Hello there")
    XCTAssertEqual(TextCleaner.clean("<|startoftranscript|> okay <|endoftext|>"), "Okay")
  }

  func testWhitespaceNormalization() {
    XCTAssertEqual(TextCleaner.clean("Hello ,  world .   How   are you ?"), "Hello, world. How are you?")
  }

  func testEmptyAndWhitespaceInput() {
    XCTAssertEqual(TextCleaner.clean(""), "")
    XCTAssertEqual(TextCleaner.clean("   \n  "), "")
  }
}
