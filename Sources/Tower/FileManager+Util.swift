//
//  FileManager+Util.swift
//  Tower
//
//  Created by muukii on 12/29/17.
//

import Foundation

extension FileManager {

  func findDirectoryPaths(directoryName: String, from rootPath: String) -> [String] {
    let fileSystem = self

    let standardizedRootPath = NSString(string: rootPath).standardizingPath

    guard let directoryEnumrator = fileSystem.enumerator(
      at: URL.init(fileURLWithPath: standardizedRootPath),
      includingPropertiesForKeys: [
        .isDirectoryKey,
        .nameKey,
        ],
      options: [
        .skipsHiddenFiles,
        .skipsPackageDescendants,
        ],
      errorHandler: nil
      ) else {
        return []
    }

    // https://medium.com/folded-plane/swift-array-appending-and-avoiding-o-n-6082619cdf7b
    var paths: [[String]] = [[]]

    while let path = directoryEnumrator.nextObject() as? URL {

      let r = try! path.resourceValues(forKeys: [.isDirectoryKey, .nameKey])

      if r.isDirectory!, r.name == directoryName {
        paths[0].append(path.path)
        directoryEnumrator.skipDescendants()
      }
    }

    return paths[0]
  }
}
