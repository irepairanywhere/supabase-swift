import XCTest
@testable import DictumCore

final class PersonalDictionaryTests: XCTestCase {
  func testReplacesWholeWordsCaseInsensitively() {
    let entries = [DictionaryEntry(spoken: "john smith", written: "Jon Smyth")]
    XCTAssertEqual(PersonalDictionary.apply(entries, to: "Ask John Smith. JOHN SMITH knows."), "Ask Jon Smyth. Jon Smyth knows.")
  }

  func testDoesNotReplaceInsideWords() {
    let entries = [DictionaryEntry(spoken: "cat", written: "Cat")]
    XCTAssertEqual(PersonalDictionary.apply(entries, to: "concatenate the cat"), "concatenate the Cat")
  }

  func testSkipsIncompleteEntries() {
    let entries = [DictionaryEntry(spoken: "", written: "Kubernetes"), DictionaryEntry(spoken: "x", written: "")]
    XCTAssertEqual(PersonalDictionary.apply(entries, to: "x marks the spot"), "x marks the spot")
  }

  func testVocabularyDeduplicates() {
    let entries = [DictionaryEntry(spoken: "", written: "Kubernetes"),
                   DictionaryEntry(spoken: "cube", written: "kubernetes"),
                   DictionaryEntry(spoken: "", written: "  ")]
    XCTAssertEqual(PersonalDictionary.vocabulary(from: entries), ["Kubernetes"])
  }

  func testTemplateCharactersInWrittenFormAreLiteral() {
    let entries = [DictionaryEntry(spoken: "price", written: "$100")]
    XCTAssertEqual(PersonalDictionary.apply(entries, to: "the price is fixed"), "the $100 is fixed")
  }
}
