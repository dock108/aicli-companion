import XCTest
@testable import AICLICompanion

@available(iOS 17.0, macOS 14.0, *)
final class MarkdownParserFilePathTests: XCTestCase {
    func testFilePathDetection() {
        // Test various file path formats
        let testCases = [
            // Backtick wrapped files
            ("Check `README.md` for details", ["README.md"]),
            ("Files: `package.json` and `tsconfig.json`", ["package.json", "tsconfig.json"]),
            
            // Bullet points with files
            ("• lottery_bot.py", ["lottery_bot.py"]),
            ("- README_LOTTERY.md", ["README_LOTTERY.md"]),
            ("* config.yaml", ["config.yaml"]),
            
            // Files with paths
            ("Edit src/index.js", ["src/index.js"]),
            ("The file ./components/Button.tsx needs fixing", ["./components/Button.tsx"]),
            
            // Files with line numbers
            ("Error in main.swift:42", ["main.swift"]),
            ("Check utils/helper.js:123", ["utils/helper.js"]),
            
            // Mixed content
            ("Fixed bugs in `server.js`, utils/config.json and • README.md",
             ["server.js", "utils/config.json", "README.md"])
        ]
        
        for (input, expectedFiles) in testCases {
            let attributedString = MarkdownParser.parseMarkdown(input)
            
            // Extract all file paths from the attributed string
            var foundFiles: [String] = []
            for run in attributedString.runs {
                if let metadata = attributedString[run.range][FilePathAttributeKey.self] {
                    foundFiles.append(metadata.path)
                }
            }
            
            XCTAssertEqual(Set(foundFiles), Set(expectedFiles),
                          "Failed to detect all files in: \(input)")
            
            // Also verify that file paths have links
            for run in attributedString.runs {
                if let metadata = attributedString[run.range][FilePathAttributeKey.self] {
                    let link = attributedString[run.range].link
                    XCTAssertNotNil(link,
                                   "File path \(metadata.path) should have a link attribute")
                    if let link = link {
                        XCTAssertTrue(link.absoluteString.starts(with: "file://"),
                                     "File path link should use file:// scheme")
                    }
                }
            }
        }
    }
    
    func testFilePathWithLineNumbers() {
        let input = "Error in main.swift:42 and helper.js:123"
        let attributedString = MarkdownParser.parseMarkdown(input)
        
        var filePathsWithLines: [(String, Int?)] = []
        for run in attributedString.runs {
            if let metadata = attributedString[run.range][FilePathAttributeKey.self] {
                filePathsWithLines.append((metadata.path, metadata.lineNumber))
            }
        }
        
        XCTAssertEqual(filePathsWithLines.count, 2)
        XCTAssertTrue(filePathsWithLines.contains(where: { $0.0 == "main.swift" && $0.1 == 42 }))
        XCTAssertTrue(filePathsWithLines.contains(where: { $0.0 == "helper.js" && $0.1 == 123 }))
    }
    
    func testFilePathValidation() {
        // Test that invalid patterns are not detected as files
        let invalidCases = [
            "Version 1.0.0", // Version numbers
            "Time is 3.14", // Decimal numbers
            "IP: 192.168.1.1", // IP addresses
            "Just text.", // Sentence ending with period
            "www.example.com" // Domain names without protocol
        ]
        
        for input in invalidCases {
            let attributedString = MarkdownParser.parseMarkdown(input)
            
            var foundFiles: [String] = []
            for run in attributedString.runs {
                if let metadata = attributedString[run.range][FilePathAttributeKey.self] {
                    foundFiles.append(metadata.path)
                }
            }
            
            XCTAssertEqual(foundFiles.count, 0,
                          "Should not detect files in: \(input)")
        }
    }
}
