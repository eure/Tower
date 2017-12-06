
import Foundation
import RxSwift
import Bulk
import ShellOut
import PathKit
import Bulk

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
            incomingWebhookURLString: "https://hooks.slack.com/services/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",
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
  public let branchPattern: String
  public let remote: String = "origin"
  public let loadPathForTowerfile: String?
  
  private let disposeBag = DisposeBag()
  private let pollingInterval: RxTimeInterval = 10
  private var contexts: [String : BranchContext] = [:]
  private let branchDirectoryName = "me.muukii.tower.work"
  
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
    self.branchPattern = config.branchMatchingPattern
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
      
//      SlackSendMessage.send(
//        message: SlackMessage(
//          channel: nil,
//          text: "",
//          as_user: true,
//          parse: "full",
//          username: "Tower",
//          attachments: [
//            .init(
//              color: "",
//              pretext: "",
//              authorName: "Tower Status",
//              authorIcon: "",
//              title: "",
//              titleLink: "",
//              text: "Launch Tower",
//              imageURL: "",
//              thumbURL: "",
//              footer: "",
//              footerIcon: "",
//              fields: []
//            )
//          ]
//        )
//      )
      
      Observable<Int>
        .interval(pollingInterval, scheduler: MainScheduler.instance)
        .map { _ in }
        .startWith(())
        .do(onNext: {
          //        Log.verbose("On")
        })
        .flatMapFirst {
          Single<Void>.create { o in
            do {
              try self.fetch()
              try self.checkoutTargetBranches()
              o(.success(()))
            } catch {
              o(.error(error))
            }
            return Disposables.create()
            }
            .asObservable()
            .catchError { _ in .empty() }
        }
        .subscribe(onNext: { [unowned self] tasks in
          do {
            try self.createBranchContexts().forEach { $0.runIfHasNewCommit() }
          } catch {
            self.log.error(error)
          }
        })
        .disposed(by: disposeBag)
      
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
  
  private func createBranchContexts() throws -> [BranchContext] {
    
    let branchNames = try checkoutedBranchDirectoryNames()
    
    var contexts: [BranchContext] = []
    
    for branchName in branchNames {
      if let c = self.contexts[branchName] {
        contexts.append(c)
      } else {
        let c = BranchContext(
          path: branchesPath + Path(branchName) + branchDirectoryName,
          branchName: branchName,
          loadPathForTowerfile: loadPathForTowerfile,
          log: log
        )
        self.contexts[branchName] = c
        contexts.append(c)
      }
    }
    
    return contexts
  }
  
  private func checkoutTargetBranches() throws  {
    
    let _local = try checkoutedBranchDirectoryNames()
    let _remote = filterTargetBranch(branches: try remoteBranches())
    
    guard _remote.isEmpty == false else { return }
    
    for deletedBranch in _local where _remote.contains(where: { $0.name == deletedBranch }) == false {
      deleteBranchDirectory(branchName: deletedBranch)
    }

    for branch in _remote where _local.contains(where: { $0 == branch.name }) == false {
      _ = try shallowCloneToWorkingDirectory(branch: branch)
    }
  }
  
  private func localBranches() throws -> [LocalBranch] {
    
    let remoteBranches = try shellOut(to: "git branch --format '%(refname:short)'", at: basePath.string)
    let names = remoteBranches.split(separator: "\n")
    return names.map {
      LocalBranch(name: String($0))
    }
  }
  
  private func remoteBranches() throws -> [RemoteBranch] {
    
    let remoteBranches = try shellOut(to: "git branch --remote --format '%(refname:lstrip=3)'", at: basePath.string)
    let names = remoteBranches.split(separator: "\n")
    return names
      .map {
        RemoteBranch(remote: remote, name: String($0))
      }
      .filter { $0.name != "HEAD" }
  }
  
  private func deleteBranchDirectory(branchName: String) {
    
    log.info("Delete branch", branchName)
    
    guard branchName.isEmpty == false else { return }

    do {
      let path = branchesPath + branchName + branchDirectoryName
      try path.delete()
    } catch {
      log.error(error)
    }
  }
  
  private func remotePath() throws -> String {
    return try shellOut(to: "git remote -v | grep fetch | awk '{print $2}'", at: basePath.string)
  }
  
  private func shallowCloneToWorkingDirectory(branch: RemoteBranch) throws -> Path {
    let path = branchesPath + branch.name + branchDirectoryName
    log.info("Clone", path)

    do {
      try shellOut(to: "git clone --depth 1 \(remotePath()) -b \(branch.name) \(path.absolute().string)", at: basePath.string)
    } catch {
      do {
        try path.absolute().delete()
      } catch {
        throw error
      }
      throw error
    }
    return path
  }
  
  private func filterTargetBranch<T: BranchType>(branches: [T]) -> [T] {
    
    guard branchPattern.isEmpty == false else {
      return branches
    }
    
    let exp = try! NSRegularExpression(pattern: branchPattern, options: [])
    
    return branches
      .filter { branch in
      exp.matches(in: branch.name, options: [], range: NSRange.init(0..<branch.name.count)).count == 1
    }
  }
  
  ///
  ///
  /// - Returns: 
  private func checkoutedBranchDirectoryNames() throws -> [String] {
    
    return try shellOut(to: "find . -type d -name \(branchDirectoryName) | sed 's#\\./##' | xargs -n 1 dirname", at: branchesPath.absolute().string).split(separator: "\n").map { String($0) }
  }
}
