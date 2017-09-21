
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

public final class Session {

  public let watchPath: String?

  public init(watchPath: String?) {
    self.watchPath = watchPath
  }

  public func start() {

    Log.info("Process Path:", CommandLine.arguments.first ?? "")
    let cwd = FileManager.default.currentDirectoryPath
    Log.info("WorkingDirectory:", cwd)

    Log.info("Session Start")

    let watchPath = self.watchPath ?? cwd

    Observable<Int>.interval(10, scheduler: MainScheduler.instance)
      .map { _ in }
      .do(onNext: {
        Log.verbose(try shellOut(to: "cd \(watchPath) && git status -s"))
      })
      .map {
        try shellOut(to: "cd \(watchPath) && git fetch")
      }
      .debug()
      .filter { $0.isEmpty == false }
      .subscribe()
  }
}
