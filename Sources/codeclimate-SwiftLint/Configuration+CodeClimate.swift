//
//  Configuration+CodeClimate.swift
//  codeclimate-SwiftLint
//
//  Created by Cyril Lashkevich on 08/03/2018.
//

import Dispatch
import Foundation
import SwiftLintFramework
import SourceKittenFramework

extension SwiftLintFile {
    public static func == (lhs: SwiftLintFile, rhs: SwiftLintFile) -> Bool {
        return lhs.path == rhs.path
    }
}

extension SwiftLintFile {
    public var hashValue: Int {
        return self.path?.hashValue ?? 0
    }
}

extension Configuration {
    init(codeclimateOptions: CodeclimateOptions, configurationFiles: [String]) {
        self.init(configurationFiles: configurationFiles)
    }

    fileprivate func getUniqueFiles(codeclimateOptions: CodeclimateOptions) -> Set<SwiftLintFile> {
        let processLintable = { (path: String) -> [SwiftLintFile] in
            return self.lintableFiles(inPath: path, forceExclude: false)
        }
        let lintable:[SwiftLintFile] = codeclimateOptions.include_paths.flatMap(processLintable)
        let excludedPaths:[SwiftLintFile] = (codeclimateOptions.exclude_paths ?? []).flatMap(processLintable)
        return Set<SwiftLintFile>(lintable.lazy.filter {
            return $0.path!.bridge().isSwiftFile() && !excludedPaths.contains($0)
        })
    }

    func visitLintableFiles(codeclimateOptions: CodeclimateOptions, parallel: Bool = false,
                            visitorBlock: @escaping (Linter) -> Void) -> Void {
        let files = getUniqueFiles(codeclimateOptions: codeclimateOptions)
        if files.isEmpty {
            return
        }
        let filesAndConfigurations: [(SwiftLintFile, Configuration)] = files.map { ($0, configuration(for:$0)) }
        let visit = { (file: SwiftLintFile, config: Configuration) -> Void in
            visitorBlock(Linter(file: file, configuration: config))
        }
        if parallel {
            DispatchQueue.concurrentPerform(iterations: filesAndConfigurations.count) { index in
                let (file, config) = filesAndConfigurations[index]
                visit(file, config)
            }
        } else {
            filesAndConfigurations.forEach(visit)
        }
    }
}
