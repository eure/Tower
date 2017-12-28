import Foundation

public protocol CommandType {
  var commandValues: [String] { get }
}

extension CommandType {
  public var commandString: String {
    return commandValues.joined(separator: " ")
  }
}

public protocol OptionType {

  var commandValues: [String] { get }
}

public enum Git {

  public struct Init : CommandType {

    public let commandValues: [String]

    public init() {
      commandValues = ["git", "init"]
    }
  }

  public struct Commit : CommandType {

    public let commandValues: [String]

    public init() {
      commandValues = ["git", "commit"]
    }
  }

  public struct Pull : CommandType {

    public let commandValues: [String]

    public init() {
      commandValues = ["git", "pull"]
    }
  }

  public struct Push : CommandType {

    public let commandValues: [String]

    public init() {
      commandValues = ["git", "push"]
    }
  }

  public struct Remote : CommandType {

    public enum Option : OptionType {

      case verbose

      public var commandValues: [String] {
        switch self {
        case .verbose:
          return ["-v"]
        }
      }
    }

    public let commandValues: [String]

    public init(options: [Option]) {

      commandValues = ["git", "remote"] + options.joinedCommand()
    }  
  }

  public struct Fetch : CommandType {

    public enum Option : OptionType {

      case verbose
      case prune

      public var commandValues: [String] {
        switch self {
        case .prune:
          return ["--prune"]
        case .verbose:
          return ["-v"]
        }
      }
    }

    public let commandValues: [String]

    public init(group: String, options: [Option]) {

      commandValues = ["git", "fetch"] + options.joinedCommand() + [group]
    }
  }

  public struct Branch : CommandType {

    public enum Option : OptionType {

      case verbose
      case format(String)
      case remote

      public var commandValues: [String] {
        switch self {
        case .format(let format):
          return ["--format", format]
        case .remote:
          return ["--remote"]
        case .verbose:
          return ["-v"]
        }
      }
    }

    public let commandValues: [String]

    public init(options: [Option]) {

      commandValues = ["git", "branch"] + options.joinedCommand()
    }
  }

  public struct Clone : CommandType {

    public enum Option : OptionType {

      case verbose
      case depth(Int)
      case branch(String)

      public var commandValues: [String] {
        switch self {
        case .depth(let depth):
          return ["--depth", depth.description]
        case .branch(let branch):
          return ["-b", branch]
        case .verbose:
          return ["-v"]
        }
      }
    }

    public var commandValues: [String]

    public init(repo: String, dir: String, options: [Option]) {

      commandValues = ["git", "clone"] + options.joinedCommand() + [repo, dir]
    }
  }
}

extension Array where Element : OptionType {

  fileprivate func joinedCommand() -> [String] {
    return flatMap { $0.commandValues }
  }
}
