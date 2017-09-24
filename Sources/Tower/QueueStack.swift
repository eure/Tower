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
            text: "",
            as_user: true,
            parse: "full",
            username: "Tower",
            attachments: [
              .init(
                color: "",
                pretext: "",
                authorName: "Tower Status",
                authorIcon: "",
                title: "",
                titleLink: "",
                text: "Add Task",
                imageURL: "",
                thumbURL: "",
                footer: "",
                footerIcon: "",
                fields: [
                  .init(
                    title: "Branch",
                    value: key,
                    short: false
                  )
                ]
              )
            ]
          )
        )

      })
      .observeOn(ConcurrentDispatchQueueScheduler(qos: .default))
      .mapWithIndex { task, i in
        task.do(
          onSubscribed: {
           
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
