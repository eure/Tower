//
//  ShellOutError+Debug.swift
//  Tower
//
//  Created by muukii on 9/29/17.
//

import Foundation

import ShellOut

extension ShellOutError : CustomDebugStringConvertible {
  public var debugDescription: String {
    return
      [
        "ShellOutError",
        "status  : \(terminationStatus)",
        "message : \(message)",
        ]
        .joined(separator: "\n")
  }
}
