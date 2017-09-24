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
      q = createQueue(key: key)
      queues[key] = q
    }

    q.onNext(o)
  }

  func createQueue(key: String) -> PublishSubject<Single<Void>> {
    let q = PublishSubject<Single<Void>>()
    q
      .do(onNext: { _ in
        Log.info("Add Task on \(key)")

        SlackSendMessage.send(
          message: SlackMessage(
            channel: nil,
            text: "Add Task on \(key)",
            as_user: true,
            parse: "full",
            username: "Tower",
            attachments: nil)
        )

      })
      .observeOn(ConcurrentDispatchQueueScheduler(qos: .default))
      .mapWithIndex { task, i in
        task.do(
          onSubscribed: {
            SlackSendMessage.send(
              message: SlackMessage(
                channel: nil,
                text: "Start Task \(i) on \(key)",
                as_user: true,
                parse: "full",
                username: "Tower",
                attachments: nil)
            )
        },
          onDispose: {

        }
        )
      }
      .concat()
      .subscribe()
      .disposed(by: disposeBag)
    return q
  }
}
