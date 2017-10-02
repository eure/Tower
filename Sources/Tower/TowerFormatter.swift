//
//  TowerFormatter.swift
//  Tower
//
//  Created by muukii on 9/29/17.
//

import Foundation

import Bulk

struct TowerFormatter: Bulk.Formatter {

  public typealias FormatType = String

  public struct LevelString {
    public var verbose = "📜"
    public var debug = "📃"
    public var info = "💡"
    public var warn = "⚠️"
    public var error = "❌"
  }

  public let dateFormatter: DateFormatter

  public var levelString = LevelString()

  public init() {

    let formatter = DateFormatter()
    formatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
    self.dateFormatter = formatter

  }

  public func format(log: Log) -> FormatType {

    let level: String = {
      switch log.level {
      case .verbose: return levelString.verbose
      case .debug: return levelString.debug
      case .info: return levelString.info
      case .warn: return levelString.warn
      case .error: return levelString.error
      }
    }()

    let timestamp = dateFormatter.string(from: log.date)
    let string: String
    
    switch log.level {
    case .warn, .error:
      let file = URL(string: log.file.description)?.deletingPathExtension()
      string = "[\(timestamp)] \(level) \(file?.lastPathComponent ?? "???").\(log.function):\(log.line) \(log.body)"
    default:
      string = "[\(timestamp)] \(level) \(log.body)"
    }

    return string
  }
}
