
import Foundation
import RxSwift
import Bulk

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

  public init() {

  }

  public func start() {

    Log.info("Session Start")

    Observable<Int>.interval(2, scheduler: MainScheduler.instance)
//          Observable<Int>.interval(1, scheduler: SerialDispatchQueueScheduler(qos: .default))
      .debug()
      .subscribe()
  }
}
