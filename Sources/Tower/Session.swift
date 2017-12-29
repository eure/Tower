
import Foundation
import RxSwift
import Bulk
import ShellOut
import PathKit
import Bulk

#if !os(Linux)
  import RxCocoa
#endif

protocol BranchType : Hashable {
  var name: String { get }
}

struct LocalBranch : BranchType {

  static func == (l: LocalBranch, r: LocalBranch) -> Bool {
    guard l.name == r.name else { return false }
    return true
  }

  let name: String
  let path: Path

  var hashValue: Int {
    return name.hashValue
  }
}

struct RemoteBranch : BranchType {

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

public final class Session {

  private lazy var log: Logger = {

    let l = Logger()

    l.add(pipeline: Pipeline(
      plugins: [
        LevelFilterPlugin.init(ignoreLevels: [.verbose, .debug, .info])
      ],
      targetConfiguration: Pipeline.TargetConfiguration(
        formatter: TowerFormatter(),
        target: ConsoleTarget()
      )
      )
    )

    l.add(pipeline:
      AsyncPipeline(
        plugins: [],
        bulkConfiguration: Pipeline.BulkConfiguration.init(buffer: MemoryBuffer(size: 10), timeout: .seconds(20)),
        targetConfiguration: Pipeline.TargetConfiguration.init(
          formatter: RawFormatter(),
          target: SlackTarget.init(
            incomingWebhookURLString: config.logIncomingWebhookURL,
            username: "Tower"
          )
        ),
        queue: DispatchQueue.global(qos: .utility)
      )
    )

    return l
  }()

  public let config: Config
  
  public let workingDirectoryPath: Path
  public let gitURLString: String
  public let remote: String = "origin"
  public let loadPathForTowerfile: String?
  
  private let disposeBag = DisposeBag()
  private let pollingInterval: RxTimeInterval = 10
  private var contexts: [LocalBranch : BranchController] = [:]
  private let branchDirectoryName = "me.muukii.tower.work"

  private let taskQueue: OperationQueue = .init()
  
  public var basePath: Path {
    return workingDirectoryPath + "base"
  }
  
  public var branchesPath: Path {
    return workingDirectoryPath + "branches"
  }
  
  public init(config: Config) {

    self.config = config
    
    self.workingDirectoryPath = Path(config.workingDirectoryPath).absolute()
    self.gitURLString = config.gitURL
    self.loadPathForTowerfile = config.pathForShell
    self.taskQueue.maxConcurrentOperationCount = config.maxConcurrentTaskCount
  }
  
  public func start() {
    
    do {

      let logFilePath = (workingDirectoryPath + "log.txt").absolute().description

      print("LogFilePath => \(logFilePath)")

      log.add(pipeline:
        AsyncPipeline(
          plugins: [],
          bulkConfiguration: nil,
          targetConfiguration: Pipeline.TargetConfiguration.init(
            formatter: TowerFormatter(),
            target: FileTarget(filePath: logFilePath)
          ),
          queue: DispatchQueue.global(qos: .background)
        )
      )
      
      log.info("Process Path:", CommandLine.arguments.first ?? "")
      log.info("WorkingDirectory:", workingDirectoryPath)
      log.info("Git-URL:", gitURLString)
      log.info("Specified PATH:", loadPathForTowerfile ?? "NONE")
      log.info("Session Start")
      
      log.info("""
        
        PATH : \(try shellOut(to: "echo $PATH"))
        ENV  : \(try shellOut(to: "env"))
        """
      )
      
      if self.workingDirectoryPath.exists == false {
        try shellOut(to: .createFolder(named: self.workingDirectoryPath.string))
      }
      
      if branchesPath.exists == false {
        try shellOut(to: .createFolder(named: branchesPath.string))
      }
      
      if basePath.exists == false {
        try clone()
      }

      let scheduler = SerialDispatchQueueScheduler.init(qos: .default)

      Observable<Int>
        .interval(pollingInterval, scheduler: MainScheduler.instance)
        .map { _ in }
        .startWith(())       
        .flatMapFirst {
          Single.deferred {
            Single<Void>
              .create { o in
                do {
                  try self.fetch()
                  let (shouldRunBranchControllers, controllersElse) = try self.update()

                  shouldRunBranchControllers.forEach {
                    $0.runImmediately()
                  }

                  controllersElse.forEach {
                    $0.runIfHasDifferences()
                  }

                  o(.success(()))
                } catch {
                  o(.error(error))
                }
                return Disposables.create()
            }
            }
            .asObservable()
            .catchError { _ in .empty() }
            .subscribeOn(scheduler)
        }
        .subscribe()
        .disposed(by: disposeBag)

      #if !os(Linux)

        taskQueue.rx.observe(Int.self, #keyPath(OperationQueue.operationCount))
          .flatMap {
            $0 != nil ? Observable.just($0!) : Observable.empty()
          }
          .bind { [weak self] count in
            self?.log.info("Task count => \(count)")
          }
          .disposed(by: disposeBag)

      #endif
      
    } catch {
      fatalError("\(error)")
    }
  }
  
  private func clone() throws {
    log.info("Start Clone BaseRipogitory")
    try shellOut(to: "git clone --depth 1 \(gitURLString) \(basePath.string)", at: workingDirectoryPath.string)
    try shellOut(to: "git remote set-branches origin '*'", at: basePath.string)
    try shellOut(to: "git fetch", at: basePath.string)
    log.info("Complete Clone BaseRipogitory")
  }
  
  private func fetch() throws {
    try shellOut(to: "git fetch \(remote) --prune", at: basePath.string)
  }

  private func update() throws -> (shouldRunBranchControllers: [BranchController], controllersElse: [BranchController]) {

    let localBranches = try obtainLocalBranches()
    let remoteBranches = filterTargetBranch(branches: try obtainRemoteBranches())

    let localBranchNames = Set(localBranches.map { $0.name })
    let remoteBranchNames = Set(remoteBranches.map { $0.name })

    let shouldCheckoutBranchNames = remoteBranchNames.subtracting(localBranchNames)
    let shouldDeleteBranchNames = localBranchNames.subtracting(remoteBranchNames)

    let shouldCheckoutBranches = shouldCheckoutBranchNames.map { name in remoteBranches[remoteBranches.index(where: { $0.name == name })!] }
    let shouldDeleteBranches = shouldDeleteBranchNames.map { name in localBranches[localBranches.index(where: { $0.name == name })!] }

    shouldDeleteBranches
      .forEach { branch in

        guard let controller = contexts[branch] else { return }

        self.contexts.removeValue(forKey: branch)

        controller.prepareDestroy { [weak self] in
          self?.delete(branch: branch)
        }
        
    }

    let shouldRunBranches = try shouldCheckoutBranches.map {
      try shallowCloneToWorkingDirectory(branch: $0)
    }

    let newLocalBranches = try obtainLocalBranches()

    newLocalBranches
      .filter { branch in
        contexts.contains(where: { $0.key == branch }) == false
      }
      .map { branch in
        BranchController(
          branch: branch,
          loadPathForTowerfile: loadPathForTowerfile,
          logger: log,
          centralQueue: taskQueue
        )
      }
      .forEach { controller in
        contexts[controller.branch] = controller
    }

    var source = contexts
    shouldRunBranches.forEach {
      source.removeValue(forKey: $0)
    }

    return (
      shouldRunBranches.flatMap { contexts[$0] },
      source.map { $0.value }
    )
  }

  private func obtainLocalBranches() throws -> Set<LocalBranch> {

    let targetDir = branchesPath.absolute().string
    let branchPaths = FileManager.default.findDirectoryPaths(
      directoryName: branchDirectoryName,
      from: branchesPath.absolute().string
    )

    let localBranches = Set(
      branchPaths.map { absolutePath -> LocalBranch in
        let path = Path(absolutePath)
        let branchName = absolutePath
          .replacingOccurrences(of: targetDir + "/", with: "")
          .replacingOccurrences(of: "/" + branchDirectoryName, with: "")
        let branch = LocalBranch(name: branchName, path: path)
        return branch
      }
    )

    return localBranches
  }

  private func obtainRemoteBranches() throws -> Set<RemoteBranch> {
    
    let remoteBranches = try shellOut(to: "git branch --remote --format '%(refname:lstrip=3)'", at: basePath.string)
    let names = remoteBranches.split(separator: "\n")
    return Set(
      names
        .map {
          RemoteBranch(remote: remote, name: String($0))
        }
        .filter { $0.name != "HEAD" }
    )
  }
  
  private func delete(branch: LocalBranch) {
    
    log.info("Delete branch", branch.name)

    do {
      try branch.path.parent().delete()
    } catch {
      log.error(error)
    }
  }
  
  private func remotePath() throws -> String {
    return try shellOut(to: "git remote -v | grep fetch | awk '{print $2}'", at: basePath.string)
  }
  
  private func shallowCloneToWorkingDirectory(branch: RemoteBranch) throws -> LocalBranch {
    let path = branchesPath + branch.name + branchDirectoryName
    log.info("Clone", path)

    do {
      try shellOut(to: "git clone --depth 1 \(remotePath()) -b \(branch.name) \(path.absolute().string)", at: basePath.string)
      log.info("Clone done : \(branch.name)")
    } catch {
      do {
        log.error("Clone failed :", error)
        try path.absolute().delete()
      } catch {
        throw error
      }
      throw error
    }
    return LocalBranch(name: branch.name, path: path)
  }
  
  private func filterTargetBranch<T: BranchType>(branches: Set<T>) -> Set<T> {

    guard let pattern = config.branchMatchingPattern, pattern.isEmpty == false else {
      return branches
    }

    do {
      let exp = try NSRegularExpression(pattern: pattern, options: [])
      return branches
        .filter { branch in
          exp.matches(in: branch.name, options: [], range: NSRange.init(0..<branch.name.count)).count == 1
      }
    } catch {
      log.error("Unsupported value for branchMatchingPattern. error =>", error)
      return branches
    }
  }
}

