import XCTest
@testable import SwiftTerm

final class HangulInputTests: XCTestCase {
    func testComposesTrailingFinalConsonant() {
        XCTAssertEqual(
            HangulInput.composeSyllable(base: "하", finalIndex: HangulInput.finalIndexByJamo["ㅅ"]!),
            "핫")
    }

    func testComposesAllCompoundVowels() {
        let cases: [(Character, Character, Character)] = [
            ("고", "ㅏ", "과"), ("고", "ㅐ", "괘"), ("고", "ㅣ", "괴"),
            ("구", "ㅓ", "궈"), ("구", "ㅔ", "궤"), ("구", "ㅣ", "귀"),
            ("으", "ㅣ", "의"),
        ]

        for (base, vowel, expected) in cases {
            XCTAssertEqual(HangulInput.composeCompoundVowel(base: base, followingVowel: vowel), expected)
        }
    }

    func testComposesAllCompoundFinals() {
        let cases: [(Character, Character, Character)] = [
            ("각", "ㅅ", "갃"), ("간", "ㅈ", "갅"), ("간", "ㅎ", "갆"),
            ("갈", "ㄱ", "갉"), ("갈", "ㅁ", "갊"), ("갈", "ㅂ", "갋"),
            ("갈", "ㅅ", "갌"), ("갈", "ㅌ", "갍"), ("갈", "ㅍ", "갎"),
            ("갈", "ㅎ", "갏"), ("갑", "ㅅ", "값"),
        ]

        for (base, finalJamo, expected) in cases {
            XCTAssertEqual(
                HangulInput.composeSyllable(base: base, finalIndex: HangulInput.finalIndexByJamo[finalJamo]!),
                expected)
        }
    }

    func testComposesReportedSplitWords() {
        let gwa = HangulInput.composeCompoundVowel(base: "고", followingVowel: "ㅏ")!
        XCTAssertEqual(HangulInput.composeSyllable(base: gwa, finalIndex: HangulInput.finalIndexByJamo["ㄴ"]!), "관")
        XCTAssertEqual(HangulInput.composeSyllable(base: "일", finalIndex: HangulInput.finalIndexByJamo["ㄱ"]!), "읽")
        XCTAssertEqual(HangulInput.composeCompoundVowel(base: "으", followingVowel: "ㅣ"), "의")
        XCTAssertEqual(HangulInput.composeSyllable(base: "달", finalIndex: HangulInput.finalIndexByJamo["ㄱ"]!), "닭")
        XCTAssertEqual(HangulInput.composeSyllable(base: "갑", finalIndex: HangulInput.finalIndexByJamo["ㅅ"]!), "값")
    }

    func testResyllabifiesFinalConsonantBeforeFollowingVowel() {
        XCTAssertEqual(
            HangulInput.resyllabifyFinalConsonant(base: "핫", followingVowel: "ㅔ"),
            "하세")
    }

    func testResyllabificationPreservesPreviousSyllableInBuffer() {
        var text = "안녕핫"
        let last = text.removeLast()
        let edit = HangulInput.resyllabificationEdit(base: last, followingVowel: "ㅔ")

        XCTAssertEqual(edit?.charactersToDelete, 1)
        XCTAssertEqual(edit?.textToInsert, "하세")
        text.append(contentsOf: edit!.textToInsert)
        XCTAssertEqual(text, "안녕하세")
    }

    func testResyllabifiesFinalIeungBeforeFollowingVowel() {
        XCTAssertEqual(
            HangulInput.resyllabifyFinalConsonant(base: "셍", followingVowel: "ㅛ"),
            "세요")
    }

    func testResyllabifiesCompoundFinalConsonantBeforeFollowingVowel() {
        XCTAssertEqual(
            HangulInput.resyllabifyFinalConsonant(base: "값", followingVowel: "ㅏ"),
            "갑사")
    }

    func testResyllabifiesAllCompoundFinals() {
        let cases: [(Character, Character, String)] = [
            ("넋", "ㅏ", "넉사"), ("앉", "ㅏ", "안자"), ("않", "ㅏ", "안하"),
            ("닭", "ㅏ", "달가"), ("옮", "ㅏ", "올마"), ("짧", "ㅏ", "짤바"),
            ("곬", "ㅏ", "골사"),
            ("핥", "ㅏ", "할타"), ("읊", "ㅓ", "을퍼"), ("싫", "ㅓ", "실허"),
            ("값", "ㅣ", "갑시"),
        ]

        for (base, vowel, expected) in cases {
            let edit = HangulInput.resyllabificationEdit(base: base, followingVowel: vowel)
            XCTAssertEqual(edit?.textToInsert, expected, "\(base)+\(vowel)")
            XCTAssertEqual(edit?.charactersToDelete, 1)
        }
    }

    func testResyllabificationTransactionHandlesUIKitDeleteAndReinsertSequence() {
        var transaction = HangulInput.ResyllabificationTransaction()
        transaction.begin(deletedText: " 핫")

        XCTAssertEqual(transaction.consumeInsertion(" "), .prefixReinserted)
        XCTAssertEqual(transaction.consumeInsertion("세"), .replacement(" 하세"))
    }

    func testResyllabificationTransactionHandlesLineStart() {
        var transaction = HangulInput.ResyllabificationTransaction()
        transaction.begin(deletedText: "간")

        XCTAssertEqual(transaction.consumeInsertion("나"), .replacement("가나"))
    }

    func testResyllabificationTransactionHandlesCompoundFinals() {
        var transaction = HangulInput.ResyllabificationTransaction()
        transaction.begin(deletedText: " 값")

        XCTAssertEqual(transaction.consumeInsertion(" "), .prefixReinserted)
        XCTAssertEqual(transaction.consumeInsertion("사"), .replacement(" 갑사"))
    }

    func testResyllabificationTransactionExpiresOnUnexpectedInsertion() {
        var transaction = HangulInput.ResyllabificationTransaction()
        transaction.begin(deletedText: " 핫")

        XCTAssertEqual(transaction.consumeInsertion("x"), .noMatch)
        XCTAssertEqual(transaction.consumeInsertion("세"), .noMatch)
    }

    func testResyllabificationTransactionIgnoresSyllablesWithoutFinals() {
        var transaction = HangulInput.ResyllabificationTransaction()
        transaction.begin(deletedText: " 하")

        XCTAssertEqual(transaction.consumeInsertion(" "), .noMatch)
    }

    func testComposedFollowingSyllableMustStartWithMovedFinalConsonant() {
        XCTAssertNil(
            HangulInput.resyllabificationEdit(base: "핫", followingSyllable: "아"))
    }

    func testDoesNotResyllabifySyllableWithoutFinalConsonant() {
        XCTAssertNil(HangulInput.resyllabifyFinalConsonant(base: "하", followingVowel: "ㅔ"))
    }
}
