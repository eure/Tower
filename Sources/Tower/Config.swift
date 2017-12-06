//
//  Config.swift
//  Tower
//
//  Created by muukii on 12/6/17.
//

import Foundation

public struct Config : Decodable {

  public let workingDirectoryPath: String
  public let gitURL: String
  public let pathForShell: String

  /// Regex
  public let branchMatchingPattern: String

  public let maxConcurrentTaskCount: Int

  public let logIncomingWebhookURL: String

  public static func load(url: URL) -> Config {

    do {
      let decoder = JSONDecoder()
      let data = try Data.init(contentsOf: url)
      return try decoder.decode(Config.self, from: data)
    } catch {
      fatalError("error")
    }
  }
}
