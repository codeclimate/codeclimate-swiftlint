import Dispatch
import Foundation
import SwiftLintFramework
import SourceKittenFramework
#if os(Linux)
    import Glibc
#endif

var debugMode = false

private let outputQueue: DispatchQueue = {
    let queue = DispatchQueue(label: "com.codeclimate.swiftlint.outputQueue")

    #if !os(Linux)
        atexit_b {
            queue.sync(flags: .barrier) {}
        }
    #endif

    return queue
}()

struct CodeclimateOptions : Decodable {
    let include_paths: [String]
    let exclude_paths: [String]?
}

extension File : Equatable {
    public static func == (lhs: File, rhs: File) -> Bool {
        return lhs.path == rhs.path
    }
}

extension File : Hashable {
    public var hashValue: Int {
        return self.path?.hashValue ?? 0
    }
}

extension Configuration {
    init(codeclimateOptions: CodeclimateOptions, rootPath: String) {
        self.init(rootPath: rootPath,
                  optional: true, quiet: true, cachePath: nil)
    }

    fileprivate func getUniqueFiles(codeclimateOptions: CodeclimateOptions) -> Set<File> {
        let processLintable = { (path: String) -> [File] in
            if let root = self.rootPath {
                return self.lintableFiles(inPath: root.bridge().appendingPathComponent(path))
            }
            else {
                return self.lintableFiles(inPath: path)
            }
        }
        let lintable:[File] = codeclimateOptions.include_paths.flatMap(processLintable)
        let excludedPaths:[File] = (codeclimateOptions.exclude_paths ?? []).flatMap(processLintable)
        return Set<File>(lintable.lazy.filter {
            return $0.path!.bridge().isSwiftFile() && !excludedPaths.contains($0)
        })
    }

    func visitLintableFiles(codeclimateOptions: CodeclimateOptions, parallel: Bool = false,
                            visitorBlock: @escaping (Linter) -> Void) -> Void {
        let uniqueFiles = getUniqueFiles(codeclimateOptions: codeclimateOptions)
        if (uniqueFiles.isEmpty) {
            return
        }

        let filesPerConfiguration: [Configuration: [File]] = Dictionary(grouping: uniqueFiles, by: configuration(for:))
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
    }
}

private func violationToDict(violation: StyleViolation) -> [String: Any] {
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

    return [
        "type": "issue",
        "check_name": violation.ruleDescription.name,
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
        let codeclimateOptions = try JSONDecoder().decode(CodeclimateOptions.self, from: configFileData)
        let configuration = Configuration(codeclimateOptions: codeclimateOptions, rootPath: rootPath ?? "/code")
        if !debugMode {
            configuration.visitLintableFiles(codeclimateOptions: codeclimateOptions, parallel: true) { linter in
                let violations = linter.styleViolations.map(violationToDict)
                linter.file.invalidateCache()
                outputQueue.async {
                    for v in violations {
                        let jsonData = try! JSONSerialization.data(withJSONObject: v)
                        jsonData.withUnsafeBytes { p -> Void in
                            fwrite(p, jsonData.count, 1, stdout)
                        }
                        fputc(0, stdout)
                    }
                }
            }
        }
        else {
            var violationsCount = 0
            let violationsCountLock = NSLock()
            configuration.visitLintableFiles(codeclimateOptions: codeclimateOptions, parallel: false) { linter in
                violationsCountLock.lock()
                violationsCount += linter.styleViolations.count
                violationsCountLock.unlock()
                queuedPrint(XcodeReporter.generateReport(linter.styleViolations))
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
