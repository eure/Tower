//
//  Config.swift
//  Tower
//
//  Created by muukii on 12/6/17.
//

import Foundation

public struct Config : Decodable {

  public struct SlackIntegration : Decodable {

    public let incomingWebhookURL: String

    public let channelIdentifierForLog: String

    public let channelIdentifierForNotification: String
  }

  public struct Target : Decodable {
    public let gitURL: String
    /// Regex
    public let branchMatchingPattern: String?

    public let pathForShell: String?

    public let maxConcurrentTaskCount: Int

    public let pollingInterval: Int
  }

  public let workingDirectoryPath: String

  public let target: Target

  public let slack: SlackIntegration

  public static func load(url: URL) -> Config {

    do {
      let decoder = JSONDecoder()
      let data = try Data.init(contentsOf: url)
      return try decoder.decode(Config.self, from: data)
    } catch {
      fatalError("Failed to load Config : \(error)")
    }
  }
}
