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
