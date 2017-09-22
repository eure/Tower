
import Foundation
import RxSwift
import Bulk
import ShellOut

let Log: Logger = {

  let l = Logger()
  l.add(pipeline: Pipeline(
    plugins: [],
    targetConfiguration: Pipeline.TargetConfiguration(
      formatter: BasicFormatter(),
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
//  public let branchPattern: String = ""
  public let remote: String = "origin"
  private let workingDirName = ".tower_work"
  private let disposeBag = DisposeBag()
  private let pollingInterval: RxTimeInterval = 20

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



    createTowerWorkingDirectory()

    Observable<Int>
      .interval(pollingInterval, scheduler: MainScheduler.instance)
      .map { _ in }
      .startWith(())
      .do(onNext: {
        Log.verbose("On")
      })
      .do(onNext: { [unowned self] in
        self.fetch()
        self.checkoutTargetBranches()
      })
      .map { () -> Observable<Single<Void>> in
        Observable.from(
          self.createBranchContexts().map { c in
            Single.create { o in
              c.run()
              o(.success(()))
              return Disposables.create()
            }
          }
        )
      }
      .observeOn(ConcurrentDispatchQueueScheduler(qos: .default))
      .flatMap { a in
        a.merge(maxConcurrent: 4)
      }
      .subscribe()
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
    if fetch() {
      Log.info("[Branch : \(branchName)]", "has new commits")
      pull()
      runTowerfile()
    }
  }

  private func fetch() -> Bool {

    Log.info("[Branch : \(branchName)]", "fetch")

    do {
      let result = try shellOut(to: "git fetch", at: path)
      if result.contains("(forced update)") {
        try! shellOut(to: "git reset --hard origin/\(branchName)", at: path)
      }
      let r = try! shellOut(to: "git rev-list --count \(branchName)...origin/\(branchName)", at: path)
      let behinded = (Int(r) ?? 0) > 0
      return behinded
    } catch {
      Log.error(error)
      return false
    }
  }

  private func pull() {
    do {
      let r = try shellOut(to: "git pull", at: path)
      Log.verbose("[Branch : \(branchName)", "pull\n", r)
    } catch {
      Log.error(error)
    }
  }

  private func runTowerfile() {
    do {
      let log = try shellOut(to: "git log -n 1", at: path)
      Log.info("[Branch : \(branchName)", "\n", log, "\n", "Run towerfile")
      let r = try shellOut(to: "sh .towerfile", at: path)
      Log.verbose("\n", r)
    } catch {
      Log.error(error)
    }
  }
}
