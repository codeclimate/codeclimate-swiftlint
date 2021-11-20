import Dispatch
import Foundation
import SwiftLintFramework

#if os(Linux)
    import Glibc
#endif

var debugMode = false

struct CodeclimateOptions : Decodable {
    let include_paths: [String]
    let exclude_paths: [String]?
}

private func violationToDict(violation: StyleViolation) -> [String: Any] {
    let category: String = {
        if let rule = primaryRuleList.list[violation.ruleIdentifier] {
            switch rule.description.kind {
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
        }

        return ""
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

    return [
        "type": "issue",
        "check_name": violation.ruleDescription,
        "description": violation.reason,
        "categories": [category],
        "location": location,
        "severity": severity,
    ]
}

// Exit fast when just version is required
if CommandLine.argc == 2 && CommandLine.arguments[1] == "--version" {
    print(SwiftLintFramework.Version.current.value)
    exit(0)
}

DispatchQueue.global().async {
    do {
        var rootPath: String? = nil
        var configUrl = URL(fileURLWithPath:"/config.json")
        var args = CommandLine.arguments[1...]

        if let opt = args.first, opt == "--debug" {
                debugMode = true
                args = args.dropFirst()
        }
        if let opt = args.first {
            rootPath = opt
            configUrl = URL(fileURLWithPath:rootPath!.bridge().appendingPathComponent("config.json"))
        }

        let configFileData = try Data(contentsOf:configUrl)
        let fileURL = URL(fileURLWithPath:"/code/.swiftlint.yml")
        var configurationFiles: [String] = []
        if let _ = try? fileURL.checkResourceIsReachable() {
            configurationFiles = ["/code/.swiftlint.yml"]
        }
        let codeclimateOptions = try JSONDecoder().decode(CodeclimateOptions.self, from: configFileData)
        let configuration = Configuration(codeclimateOptions: codeclimateOptions, configurationFiles: configurationFiles)
        let storage = RuleStorage()
        if !debugMode {
            let outputQueue = DispatchQueue(label: "com.codeclimate.swiftlint.outputQueue")
            configuration.visitLintableFiles(codeclimateOptions: codeclimateOptions, parallel: true) { linter in
                let violations = linter.collect(into: storage).styleViolations(using: storage)
                linter.file.invalidateCache()
                outputQueue.async {
                    for v in violations {
                        let jsonData = try! JSONSerialization.data(withJSONObject: violationToDict(violation: v))
                        jsonData.withUnsafeBytes { p -> Void in
                            fwrite(
                                p.load(as: UnsafeRawPointer.self),
                                jsonData.count, 1,
                                stdout
                            )
                        }
                        fputc(0, stdout)
                    }
                }
            }
            outputQueue.sync(flags: .barrier) {}
        }
        else {
            var violationsCount = 0
            let violationsCountLock = NSLock()
            let storage = RuleStorage()
            configuration.visitLintableFiles(codeclimateOptions: codeclimateOptions, parallel: false) { linter in
                violationsCountLock.lock()
                violationsCount += linter.collect(into: storage).styleViolations(using: storage).count
                violationsCountLock.unlock()
                queuedPrint(XcodeReporter.generateReport(linter.collect(into: storage).styleViolations(using: storage)))
                linter.file.invalidateCache()
            }
            queuedPrintError("Done linting! Found \(violationsCount) violations")
        }
    }
    catch {
        exit(1)
    }
    exit(0)
}

dispatchMain()
