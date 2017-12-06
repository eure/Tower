//
//  BranchContext.swift
//  Tower
//
//  Created by muukii on 9/29/17.
//

import Foundation
import ShellOut
import RxSwift
import PathKit
import Bulk

final class BranchContext : Equatable {

  static func == (l: BranchContext, r: BranchContext) -> Bool {
    guard l.path == r.path else { return false }
    guard l.branchName == r.branchName else { return false }
    return true
  }

  let path: Path
  let branchName: String
  let loadPathForTowerfile: String?
  var isRunning: Bool = false

  private let lock = NSRecursiveLock()
  private let queue = PublishSubject<Single<Void>>()
  private let disposeBag = DisposeBag()
  private let log: Logger

  init(
    path: Path,
    branchName: String,
    loadPathForTowerfile: String?,
    log: Logger
    ) {
    
    self.path = path
    self.branchName = branchName
    self.loadPathForTowerfile = loadPathForTowerfile
    self.log = log

    queue
      .mapWithIndex { task, i in
        task.do(
          onSubscribed: {

        },
          onDispose: {

        }
          )
          .asObservable()
          .materialize()
      }
      .concat()
      .subscribe()
      .disposed(by: disposeBag)
  }

  func runIfHasNewCommit() {

    lock.lock(); defer { lock.unlock() }

    guard isRunning == false else {
      log.verbose("[\(branchName)] is running, skip polling")
      return
    }

    let task = Single<Void>.create { (o) -> Disposable in

      do {
        if try self.hasNewCommitsShouldRun() {
          try self.run()
        }
        o(.success(()))
      } catch {
        o(.error(error))
      }

      return Disposables.create()
      }
      .do(
        onError: { _ in
          
      },
        onSubscribe: {
          self.isRunning = true
      },
        onSubscribed: {
          self.isRunning = false
      },
        onDispose: {
          self.isRunning = false
      })
      .timeout((60 * 60), scheduler: SerialDispatchQueueScheduler(qos: .default))
      .subscribeOn(ConcurrentDispatchQueueScheduler(qos: .default))

    queue.onNext(task)
  }

  private func run() throws {

    do {

      let log = try lastCommit()
      sendStarted(commitLog: log)
      try runTowerfile()
      sendEnded(commitLog: log)
    } catch {
      log.error(error)
      sendError(error: error)
    }
  }

  private func lastCommitHash() -> CommitHash {
    let r = try! runShellInDirectory("git rev-parse HEAD")
    return CommitHash(sha: r)
  }

  private func hasNewCommitsShouldRun() throws -> Bool {

    guard try hasNewCommits() else {
      return false
    }

    let oldestCommitHash = lastCommitHash()
    try pull()
    let latestCommitHash = lastCommitHash()

    if oldestCommitHash == latestCommitHash {
      log.error("You said 'we have new commits!'")
    }

    guard try hasShouldRunCommits(latestHash: latestCommitHash, oldestHash: oldestCommitHash) else {
      return false
    }

    return true
  }

  private func hasShouldRunCommits(latestHash: CommitHash, oldestHash: CommitHash) throws -> Bool {

    let r = try runShellInDirectory("git log --format='%s' \(latestHash.sha)...\(oldestHash.sha)")

    let line = r.split(separator: "\n")

    let skipCount = line
      .filter { String($0).hasPrefix("[skip tower]") }
      .count

    return line.count > skipCount
  }

  private func hasNewCommits() throws -> Bool {

    let branch = try runShellInDirectory("git rev-parse --abbrev-ref HEAD")

    if branchName != branch {
      log.warn("[Branch : \(branchName)]", "Wrong branch : \(branch)")
    }

    log.info("[Branch : \(branchName)]")
    let result = try runShellInDirectory("git fetch")

    if result.contains("(forced update)") {
      try runShellInDirectory("git reset --hard origin/\(branchName)")
      return true
    }

    let r = try runShellInDirectory("git rev-list --count \(branchName)...origin/\(branchName)")
    let behinded = (Int(r) ?? 0) > 0
    return behinded
  }

  private func pull() throws {
    log.verbose("[Branch : \(branchName)", "pulling")
    try runShellInDirectory("git reset --hard origin/\(branchName)")
    let hasNewCommits = try self.hasNewCommits()
    if hasNewCommits == false {
      log.error("Pull has failed")
    }
  }

  private func lastCommit() throws -> String {
    return try runShellInDirectory("git log -n 1")
  }

  private func runTowerfile() throws {

    do {
      log.info("[Branch : \(branchName)]", "Run towerfile")
      let commitLog = try lastCommit()
      log.info("[Branch : \(branchName)]\n\(commitLog)", "\n")

      do {
        let p = Process()
        p.launchBash(
          with: "echo $PATH",
          loadPATH: loadPathForTowerfile,
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
        loadPATH: loadPathForTowerfile,
        output: { (s) in
          print("[\(self.branchName)]", s, separator: "", terminator: "")
      },
        error: { (s) in
          print("[\(self.branchName)]", s, separator: "", terminator: "")
      })

    } catch {
      log.error(error)
    }
  }

  @discardableResult
  private func runShellInDirectory(_ c: String) throws -> String {
    return try shellOut(to: c, at: path.string)
  }

  private func sendStarted(commitLog: String) {
    SlackSendMessage.send(
      message: SlackMessage(
        channel: "C2K76LQ8Z",
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
            text: "Task added",
            imageURL: "",
            thumbURL: "",
            footer: "",
            footerIcon: "",
            fields: [
              .init(
                title: "Branch",
                value: branchName,
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
      )
    )
  }

  private func sendEnded(commitLog: String) {

    SlackSendMessage.send(
      message: SlackMessage(
        channel: "C2K76LQ8Z",
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
            text: "Task Ended",
            imageURL: "",
            thumbURL: "",
            footer: "",
            footerIcon: "",
            fields: [
              .init(
                title: "Branch",
                value: branchName,
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
      )
    )
  }

  private func sendError(error: Error) {

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
            text: "Task Failed",
            imageURL: "",
            thumbURL: "",
            footer: "",
            footerIcon: "",
            fields: [
              .init(
                title: "Branch",
                value: branchName,
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
      )
    )
  }
  
}
