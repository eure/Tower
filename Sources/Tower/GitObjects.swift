//
//  GitObjects.swift
//  Tower
//
//  Created by muukii on 9/29/17.
//

import Foundation

import Require

struct CommitHash : Hashable {

  static func == (l: CommitHash, r: CommitHash) -> Bool {
    return l.sha == r.sha
  }

  let sha: String

  var hashValue: Int {
    return sha.hashValue
  }
}
