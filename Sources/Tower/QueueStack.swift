//
//  QueueStack.swift
//  Tower
//
//  Created by muukii on 9/24/17.
//

import Foundation
import RxSwift

final class QueueStack {

  private var queues: [String : PublishSubject<Single<Void>>] = [:]

  private let disposeBag = DisposeBag()

  func add(_ o: Single<Void>, forKey key: String) {

    let q: PublishSubject<Single<Void>>

    if let _q = queues[key] {
      q = _q
    } else {
      q = createQueue()
      queues[key] = q
    }

    q.onNext(o)
  }

  func createQueue() -> PublishSubject<Single<Void>> {
    let q = PublishSubject<Single<Void>>()
    q
      .do(onNext: { _ in
        Log.info("Add Task")
      })
      .observeOn(ConcurrentDispatchQueueScheduler(qos: .default))      
      .concat()
      .subscribe()
      .disposed(by: disposeBag)
    return q
  }
}
