/**
 Copyright 2018 eureka, Inc.

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

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
