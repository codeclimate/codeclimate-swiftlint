import Dispatch
import Foundation
import SwiftLintFramework
import SourceKittenFramework
#if os(Linux)
    import Glibc
#endif

struct CodeclimateOptions : Decodable {
    let include_paths: [String]
}

struct JSONCodeclimateReporter: Reporter {
    static let identifier = "json_codeclimate"
    static let isRealtime = true

    var description: String {
        return "Reports violations as a JSON objects separated by NUL"
    }

    static func generateReport(_ violations: [StyleViolation]) -> String {
        return toJSON(violations.map(dictionary(for:)))
    }

    fileprivate static func dictionary(for violation: StyleViolation) -> [String: Any] {
        return [
            "file": violation.location.file ?? NSNull() as Any,
            "line": violation.location.line ?? NSNull() as Any,
            "character": violation.location.character ?? NSNull() as Any,
            "severity": violation.severity.rawValue.capitalized,
            "type": violation.ruleDescription.name,
            "rule_id": violation.ruleDescription.identifier,
            "reason": violation.reason
        ]
    }
}

extension Configuration {
    init(codeclimateOptions: CodeclimateOptions, rootPath: String) {
        self.init(rootPath: rootPath,
                  optional: true, quiet: true, cachePath: nil)
    }

    fileprivate func getFiles(codeclimateOptions: CodeclimateOptions) -> [File] {
        return codeclimateOptions.include_paths.flatMap { path -> [File] in
            if let root = rootPath {
                return lintableFiles(inPath: root.bridge().appendingPathComponent(path))
            }
            else {
                return lintableFiles(inPath: path)
            }
        }
    }

    func visitLintableFiles(codeclimateOptions: CodeclimateOptions, parallel: Bool = false,
                            visitorBlock: @escaping (Linter) -> Void) -> [File] {
        let files = getFiles(codeclimateOptions: codeclimateOptions).filter {
            return $0.path?.hasSuffix(".swift") ?? false
        }
        if (files.isEmpty) {
            return []
        }
        let filesPerConfiguration: [Configuration: [File]] = Dictionary(grouping: files, by: configuration(for:))
        let fileCount = filesPerConfiguration.reduce(0) { $0 + $1.value.count }
        let visit = { (file: File, config: Configuration) -> Void in
            visitorBlock(Linter(file: file, configuration: config))
        }
        var filesAndConfigurations = [(File, Configuration)]()
        filesAndConfigurations.reserveCapacity(fileCount)
        for (config, files) in filesPerConfiguration {
            filesAndConfigurations += files.map { ($0, config) }
        }
        if parallel {
            DispatchQueue.concurrentPerform(iterations: fileCount) { index in
                let (file, config) = filesAndConfigurations[index]
                visit(file, config)
            }
        } else {
            filesAndConfigurations.forEach(visit)
        }
        return files
    }
}

private func violationToString(violation: StyleViolation) -> String {
    let category: String = {
        switch violation.ruleDescription.kind {
        case .idiomatic:
            return "Clarity"
        case .lint:
            return "Bug Risk"
        case .metrics:
            return "Complexity"
        case .performance:
            return "Performance"
        case .style:
            return "Style"
        }
    }()

    let severity: String = {
        switch violation.severity {
        case .error:
            return "critical"
        case .warning:
            return "minor"
        }
    }()

    let location: [String: Any] = [
        "path": violation.location.relativeFile ?? NSNull() as Any,
        "lines": [
            "begin": violation.location.line ?? NSNull() as Any,
            "end": violation.location.line ?? NSNull() as Any
        ]
    ]

    let d: [String: Any] = [
        "type": "issue",
        "check_name": violation.ruleDescription.name,
        "description": violation.ruleDescription.description,
        "categories": [category],
        "location": location,
        "severity": severity,
    ]
    return toJSON(d)
}

if CommandLine.argc == 2 && CommandLine.arguments[1] == "--version" {
    print(SwiftLintFramework.Version.current.value)
    exit(0)
}

DispatchQueue.global().async {
    do {
        let rootPath: String?
        let configUrl: URL
        if CommandLine.argc == 2 {
            rootPath = CommandLine.arguments[1]
            configUrl = URL(fileURLWithPath:rootPath!.bridge().appendingPathComponent("config.json"))
        }
        else {
            rootPath = nil
            configUrl = URL(fileURLWithPath:"/config.json")
        }

        let configFileData = try Data(contentsOf:configUrl)
        let codeclimateOptions = try JSONDecoder().decode(CodeclimateOptions.self, from: configFileData)
        let configuration = Configuration(codeclimateOptions: codeclimateOptions, rootPath: rootPath ?? "/code")
        configuration.visitLintableFiles(codeclimateOptions: codeclimateOptions, parallel: false) { linter in
            for v: StyleViolation in linter.styleViolations {
                var jsonString = violationToString(violation: v)
                jsonString.append("\n\0")
                queuedPrint(jsonString)
            }
            linter.file.invalidateCache()
        }
    }
    catch {
        exit(1)
    }
    exit(0)
}

dispatchMain()
