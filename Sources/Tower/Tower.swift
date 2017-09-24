
import Foundation
import RxSwift
import Bulk
import ShellOut

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

    let string = "[\(timestamp)] \(level) \(log.body)"

    return string
  }
}

let Log: Logger = {

  let l = Logger()

  l.add(pipeline: Pipeline(
    plugins: [],
    targetConfiguration: Pipeline.TargetConfiguration(
      formatter: TowerFormatter(),
      target: ConsoleTarget()
    )
    )
  )
  return l
}()

protocol BranchType {
  var name: String { get }
}

public final class Session {

  struct LocalBranch : BranchType, Hashable {

    static func == (l: LocalBranch, r: LocalBranch) -> Bool {
      guard l.name == r.name else { return false }
      return true
    }

    let name: String

    var hashValue: Int {
      return name.hashValue
    }
  }

  struct RemoteBranch : BranchType, Hashable {

    static func == (l: RemoteBranch, r: RemoteBranch) -> Bool {
      guard l.remote == r.remote else { return false }
      guard l.name == r.name else { return false }
      return true
    }

    let remote: String
    let name: String

    var hashValue: Int {
      return remote.hashValue ^ name.hashValue
    }
  }

  public let watchPath: String
  public let branchPattern: String = "v[0-9]+.*branch"
//  public let branchPattern: String = "v15.1-branch"

  //  public let branchPattern: String = ""
  public let remote: String = "origin"
  private let workingDirName = ".tower_work"
  private let disposeBag = DisposeBag()
  private let pollingInterval: RxTimeInterval = 20
  private let queueStack = QueueStack()

  public init(watchPath: String?) {
    self.watchPath = watchPath ?? FileManager.default.currentDirectoryPath
  }

  public func start() {

    Log.info("Process Path:", CommandLine.arguments.first ?? "")
    Log.info("WatchingPath:", watchPath)
    Log.info("Session Start")

    Log.info("""

      PATH : \(try! shellOut(to: "echo $PATH"))
      
      ENV  : \(try! shellOut(to: "env"))
      """
    )

    SlackSendMessage.send(
      message: SlackMessage(
      channel: nil,
      text: "Launch Tower",
      as_user: true,
      parse: "full",
      username: "Tower",
      attachments: nil)
    )

    createTowerWorkingDirectory()

    Observable<Int>
      .interval(pollingInterval, scheduler: MainScheduler.instance)
      .map { _ in }
      .startWith(())
      .do(onNext: {
        //        Log.verbose("On")
      })
      .flatMapFirst {
        Single<Void>.create { o in
          self.fetch()
          self.checkoutTargetBranches()
          o(.success(()))
          return Disposables.create()
        }
      }
      .flatMap { () -> Single<[(String, Single<Void>)]> in

        let tasks = self.createBranchContexts()
          .map { c -> Maybe<(String, Single<Void>)> in
          Single<Bool>.create { o in
            let r = c.hasNewCommits()
            o(.success(r))
            return Disposables.create()
            }
            .filter {
              $0 == true
            }
            .map { _ in c }
            .map { c -> (String, Single<Void>) in
              (
                c.branchName,
                Single.create { o in
                  c.run()
                  o(.success(()))
                  return Disposables.create()
                }
              )
            }
            .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .default))
        }

        let _tasks = Observable.from(tasks)
          .merge(maxConcurrent: 10)
          .toArray()
          .asSingle()

        return _tasks
      }
      .subscribe(onNext: { [weak self] tasks in
        tasks.forEach {
          self?.queueStack.add($0.1, forKey: $0.0)
        }
      })
      .disposed(by: disposeBag)

  }

  private func fetch() {
    do {
      try shellOut(to: "git fetch \(remote) --prune", at: watchPath)
    } catch {

    }
  }

  private func createBranchContexts() -> [BranchContext] {
    let branchNames = checkoutedBranchDirectoryNames()
    return branchNames.map { branchName in
      BranchContext(path: "\(watchPath)/\(workingDirName)/branch/\(branchName)", branchName: branchName)
    }
  }

  private func checkoutTargetBranches() {

    let _local = checkoutedBranchDirectoryNames()
    let _remote = filterTargetBranch(branches: remoteBranches())

    for deletedBranch in _local where _remote.contains(where: { $0.name == deletedBranch }) == false {
      deleteBranchDirectory(branchName: deletedBranch)
    }

    for branch in _remote where _local.contains(where: { $0 == branch.name }) == false {
      _ = shallowCloneToWorkingDirectory(branch: branch)
    }
  }

  private func localBranches() -> [LocalBranch] {

    let remoteBranches = try! shellOut(to: "git branch --format '%(refname:short)'", at: watchPath)
    let names = remoteBranches.split(separator: "\n")
    return names.map {
      LocalBranch(name: String($0))
    }
  }

  private func remoteBranches() -> [RemoteBranch] {

    let remoteBranches = try! shellOut(to: "git branch --remote --format '%(refname:lstrip=3)'", at: watchPath)
    let names = remoteBranches.split(separator: "\n")
    return names.map {
      RemoteBranch(remote: remote, name: String($0))
    }
  }

  private func isBehind(from: String, to: String) -> Bool {
    do {
      let r = try shellOut(to: "git rev-list --count \(from)...\(to)", at: watchPath)
      return (Int(r) ?? 0) > 0
    } catch {
      return false
    }
  }

  private func remotePath() -> String {
    return try! shellOut(to: "git remote -v | grep fetch | awk '{print $2}'", at: watchPath)
  }

  private func deleteBranchDirectory(branchName: String) {

    Log.info("Delete branch", branchName)

    guard workingDirName.isEmpty == false else { return }
    guard branchName.isEmpty == false else { return }
    let command = "rm -rf \(workingDirName)/branch/\(branchName)"
    do {
      try shellOut(to: command, at: watchPath)
    } catch {
      Log.error(error)
    }
  }

  private func shallowCloneToWorkingDirectory(branch: RemoteBranch) -> String {
    let path = "\(workingDirName)/branch/\(branch.name)"
    Log.info("Clone", path)
    try! shellOut(to: "git clone --depth 1 \(remotePath()) -b \(branch.name) \(path)", at: watchPath)
    return path
  }

  private func createTowerWorkingDirectory() {
    do {
      Log.info("Create .tower_work")
      try shellOut(to: .createFolder(named: ".tower_work"), at: watchPath)
    } catch {
      Log.warn(error)
    }
    do {
      Log.info("Create .tower_work/branch")
      try shellOut(to: .createFolder(named: "branch"), at: "\(watchPath)/\(workingDirName)")
    } catch {
      Log.warn(error)
    }
  }

  private func filterTargetBranch<T: BranchType>(branches: [T]) -> [T] {

    guard branchPattern.isEmpty == false else {
      return branches
    }

    let exp = try! NSRegularExpression(pattern: branchPattern, options: [])

    return branches.filter { branch in
      exp.matches(in: branch.name, options: [], range: NSRange.init(0..<branch.name.count)).count == 1
    }
  }

  private func checkoutedBranchDirectoryNames() -> [String] {

    return try! shellOut(to: "ls -F | grep / | sed 's#/##'", at: "\(watchPath)/\(workingDirName)/branch").split(separator: "\n").map { String($0) }
  }
}

final class BranchContext {

  let path: String
  let branchName: String

  init(path: String, branchName: String) {
    self.path = path
    self.branchName = branchName
  }

  func run() {
    do {
      try pull()
      try runTowerfile()
    } catch {
      Log.error(error)
    }
  }

  func hasNewCommits() -> Bool {

    do {
      let branch = try shellOut(to: "git symbolic-ref --short HEAD", at: path)

      if branchName != branch {
        Log.warn("[Branch : \(branchName)]", "Wrong branch : \(branch)")
      }

      Log.info("[Branch : \(branchName)]", "fetch on \(Thread.current)")
      let result = try shellOut(to: "git fetch", at: path)

      if result.contains("(forced update)") {
        try shellOut(to: "git reset --hard origin/\(branchName)", at: path)
        return true
      }
      
      let r = try! shellOut(to: "git rev-list --count \(branchName)...origin/\(branchName)", at: path)
      let behinded = (Int(r) ?? 0) > 0
      return behinded
    } catch {
      Log.error(error)
      return false
    }
  }

  private func pull() throws {
    do {
      Log.verbose("[Branch : \(branchName)", "pulling")
      try shellOut(to: "git reset --hard origin/\(branchName)", at: path)

      precondition(hasNewCommits() == false, "Pull has failed")

    } catch {
      Log.error("[Branch : \(branchName)] Pull failed", (error as! ShellOutError).message)
      throw error
    }
  }

  private func runTowerfile() throws {

    do {
      Log.info("[Branch : \(branchName)]", "Run towerfile")
      let log = try shellOut(to: "git log -n 1", at: path)
      Log.info("[Branch : \(branchName)]\n\(log)", "\n")

      do {
      let p = Process()
      p.launchBash(
        with: "echo $PATH",
        output: { (s) in
          print(s, separator: "", terminator: "")
      },
        error: { (s) in
          print(s, separator: "", terminator: "")
      })
      }

      let p = Process()
      p.launchBash(
        with: "cd \"\(path)\" && sh .towerfile",
        output: { (s) in
          print(s, separator: "", terminator: "")
      },
        error: { (s) in
          print(s, separator: "", terminator: "")
      })

    } catch {
      Log.error(error)
    }
  }
}

func printError(e: Error) {
  if e is ShellOutError {
    Log.error((e as! ShellOutError).message)
  } else {
    Log.error(e)
  }
}

extension Process {

  @discardableResult func launchBash(with command: String, output: @escaping (String) -> Void, error: @escaping (String) -> Void) -> Int32 {

    launchPath = "/bin/bash"
    arguments = ["-l", "-c", "export LANG=en_US.UTF-8 && " + command]

    let outputPipe = Pipe()
    standardOutput = outputPipe

    let errorPipe = Pipe()
    standardError = errorPipe

    do {
      outputPipe.fileHandleForReading.readabilityHandler = { f in

        let d = f.availableData

        guard d.count > 0 else { return }

        output(d.shellOutput())
      }
    }

    do {
      errorPipe.fileHandleForReading.readabilityHandler = { f in
        let d = f.availableData

        guard d.count > 0 else { return }

        error(d.shellOutput())
      }
    }

    launch()

    waitUntilExit()

    #if !os(Linux)
      outputPipe.fileHandleForReading.readabilityHandler = nil
      errorPipe.fileHandleForReading.readabilityHandler = nil
    #endif

    return terminationStatus
  }
}

private extension Data {
  func shellOutput() -> String {
    guard let output = String(data: self, encoding: .utf8) else {
      return ""
    }

//    guard !output.hasSuffix("\n") else {
//      let outputLength = output.distance(from: output.startIndex, to: output.endIndex)
//      return output.substring(to: output.index(output.startIndex, offsetBy: outputLength - 1))
//    }

    return output

  }
}
