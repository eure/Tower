//
//  BranchController.swift
//  Tower
//
//  Created by muukii on 9/29/17.
//

import Foundation
import RxSwift
import PathKit
import Bulk
import BulkSlackTarget

enum CommitAttribute {
  static let skip = "[skip tower]"
}

final class BranchController : Equatable {

  static func == (l: BranchController, r: BranchController) -> Bool {
    guard l.branch == r.branch else { return false }
    return true
  }

  let branch: LocalBranch
  let loadPathForTowerfile: String?
  var isRunning: Bool = false

  private let queue = PublishSubject<Single<Void>>()
  private let disposeBag = DisposeBag()
  private let logger: ContextLogger
  private let remote: String = "origin"
  private let taskScheduler = ConcurrentDispatchQueueScheduler(qos: .default)
  private let centralQueue: OperationQueue
  private let config: Config

  init(
    config: Config,
    branch: LocalBranch,
    loadPathForTowerfile: String?,
    logger: Logger,
    centralQueue: OperationQueue
    ) {

    self.config = config
    self.centralQueue = centralQueue
    self.branch = branch
    self.loadPathForTowerfile = loadPathForTowerfile
    self.logger = logger.context(["[\(branch.name)]"])

    queue
      .map { [weak self] in
        $0
          .timeout((60 * 60), scheduler: MainScheduler.instance)
          .do(
            onError: { _ in

          },
            onSubscribe: {
              self?.isRunning = true
          },
            onSubscribed: {
              self?.isRunning = false
          },
            onDispose: {
              self?.isRunning = false
          })
      }
      .flatMap {
        $0.asObservable()
          .materialize()
      }
      .subscribe()
      .disposed(by: disposeBag)

    self.logger.info("Init \(self)")
  }

  deinit {
    logger.info("Deinit \(self)")
  }

  func prepareDestroy(completion: @escaping () -> Void) {
    queue.dispose()
    completion()
  }

  func runImmediately() {

    guard isRunning == false else {
      logger.verbose("[Skip running towerfile now")
      return
    }

    logger.info("Run Immediately")

    let task = Single<Void>
      .create { (o) -> Disposable in

        var subscription: Disposable?

        DispatchQueue.global(qos: .default).async {
          do {
            try self.fetchAndPull()
            subscription = self.runTowerfile().subscribe(o)
          } catch {
            o(.error(error))
          }
        }

        return Disposables.create {
          subscription?.dispose()
        }
    }

    queue.onNext(task)
  }

  func runIfHasDifferences() {

    guard isRunning == false else {
      logger.verbose("[Skip running towerfile now")
      return
    }

    let task = Single<Void>
      .create { (o) -> Disposable in

        var subscription: Disposable?

        DispatchQueue.global(qos: .default).async {
          do {
            guard try self.hasNewCommitsShouldRun() else {
              o(.success(()))
              return
            }

            subscription = self.runTowerfile().subscribe(o)

          } catch {
            o(.error(error))
          }
        }

        return Disposables.create {
          subscription?.dispose()
        }
    }

    queue.onNext(task)
  }

  private func fetchAndPull() throws {
    try fetch()
    try pullForced()
  }

  private func hasNewCommitsShouldRun() throws -> Bool {

    try fetch()

    guard try obtainHasDifferences() else { return false }

    let oldestCommitHash = obtainCurrentCommitHash()
    try pullForced()
    let latestCommitHash = obtainCurrentCommitHash()

    if oldestCommitHash == latestCommitHash {
      logger.warn("Pull failed")
    }

    let commitMessages = try obtainCommitMessages(latestHash: latestCommitHash, oldestHash: oldestCommitHash)

    guard checkShouldRun(commitMessages: commitMessages) else { return false }

    return true
  }

  private func obtainCurrentCommitHash() -> CommitHash {
    let r = try! runShellInDirectory("git rev-parse HEAD")
    return CommitHash(sha: r)
  }

  private func obtainCommitMessages(latestHash: CommitHash, oldestHash: CommitHash) throws -> [String] {

    let r = try runShellInDirectory("git log --format='%s' \(latestHash.sha)...\(oldestHash.sha)")

    return r.split(separator: "\n").map(String.init)
  }

  private func checkShouldRun(commitMessages: [String]) -> Bool {

    return commitMessages
      .lazy
      .filter { $0.hasPrefix(CommitAttribute.skip) == false }
      .isEmpty == false
  }

  private func fetch() throws {
    try runShellInDirectory("git fetch")
  }

  private func obtainHasDifferences() throws -> Bool {
    let r = try runShellInDirectory("git rev-list --count \(branch.name)...\(remote)/\(branch.name)")
    let behinded = (Int(r) ?? 0) > 0
    return behinded
  }

  private func pullForced() throws {
    logger.info("\(branch.name) => pulling")
    try runShellInDirectory("git reset --hard \(remote)/\(branch.name)")
    if try obtainHasDifferences() == true {
      logger.error("Pull has failed")
    }
  }

  private func lastCommit() throws -> String {
    return try runShellInDirectory("git log -n 1")
  }

  private func runTowerfile() -> Single<Void> {

    return Single<Void>.create { (o) -> Disposable in

      let p = Process()

      self.centralQueue.addOperation {
        do {

          let p = Process()

          processRef = p

          let _log = try self.lastCommit()
          self.sendStarted(commitLog: _log)

          self.logger.info("Task did run")
          let commitLog = try self.lastCommit()
          self.logger.info("\n\(commitLog)", "\n")

          let command = "cd \"\(self.branch.path.absolute().string)\" && sh .towerfile"
          let resolvedCommand: String
          if let loadPATH = self.loadPathForTowerfile {
            resolvedCommand = "export LANG=en_US.UTF-8 && export PATH=\(loadPATH) && " + command
          } else {
            resolvedCommand = "export LANG=en_US.UTF-8 && " + command
          }

          let now = Date().timeIntervalSince1970

          let outputPath = self.branch.path.parent() + "\(self.branch.name)-\(now).log"
          let errorPath = self.branch.path.parent() + "\(self.branch.name)-\(now)-error.log"

          self.logger.info("LogFiles:\nOutput => \(outputPath.string)\nError => \(errorPath.string)")

          FileManager.default.createFile(
            atPath: outputPath.string,
            contents: nil,
            attributes: nil
          )

          FileManager.default.createFile(
            atPath: errorPath.string,
            contents: nil,
            attributes: nil
          )

          let outputHandle = try FileHandle.init(forWritingTo: outputPath.url)
          let errorHandle = try FileHandle.init(forWritingTo: errorPath.url)

          try p.launchBash(
            with: resolvedCommand,
            outputHandle: outputHandle,
            errorHandle: errorHandle
          )

          self.logger.info("Task did finish")

          self.sendEnded(commitLog: _log)

        } catch {
          self.logger.error("Task did fail :", error)
          self.sendError(error: error)
        }
      }

      return Disposables.create {
        p.terminate()
      }
    }
  }

  @discardableResult
  private func runShellInDirectory(_ c: String) throws -> String {
    return try shellOut(to: c, at: branch.path.absolute().string)
  }

  private func sendStarted(commitLog: String) {
    SlackTarget.send(
      message: SlackTarget.SlackMessage(
        channel: config.slack.channelIdentifierForNotification,
        text: "Task added",
        as_user: true,
        parse: "full",
        username: "Tower",
        attachments: [
          .init(
            authorName: "Tower Status",
            title: "Task added",
            text: "",
            fields: [
              .init(
                title: "Branch",
                value: branch.name,
                short: true
              ),
              .init(
                title: "Commit",
                value: commitLog,
                short: false
              )
            ]
          )
        ]
      ),
      to: config.slack.incomingWebhookURL,
      completion: {}
    )
  }

  private func sendEnded(commitLog: String) {

    SlackTarget.send(
      message: SlackTarget.SlackMessage(
        channel: config.slack.channelIdentifierForNotification,
        text: "Task Ended",
        as_user: true,
        parse: "full",
        username: "Tower",
        attachments: [
          .init(
            authorName: "Tower Status",
            title: "Task Ended",
            text: "",
            fields: [
              .init(
                title: "Branch",
                value: branch.name,
                short: false
              ),
              .init(
                title: "Commit",
                value: commitLog,
                short: false
              )
            ]
          )
        ]
      ),
      to: config.slack.incomingWebhookURL,
      completion: {}
    )
  }

  private func sendError(error: Error) {

    SlackTarget.send(
      message: SlackTarget.SlackMessage(
        channel: config.slack.channelIdentifierForNotification,
        text: "Task Failed",
        as_user: true,
        parse: "full",
        username: "Tower",
        attachments: [
          .init(
            authorName: "Tower Status",
            title: "Task Failed",
            text: "",
            fields: [
              .init(
                title: "Branch",
                value: branch.name,
                short: false
              ),
              .init(
                title: "Error",
                value: error.localizedDescription,
                short: false
              )
            ]
          )
        ]
      ),
      to: config.slack.incomingWebhookURL,
      completion: {}
    )
  }
  
}
