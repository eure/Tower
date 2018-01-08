/**
 Copyright 2018 eureka, Inc.

 Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:

 The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.

 THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
 */

/**
 *  ShellOut
 *  Copyright (c) John Sundell 2017
 *  Licensed under the MIT license. See LICENSE file.
 */

import Foundation
import Result

// Ported from https://github.com/JohnSundell/ShellOut

@discardableResult
func shellOut(to command: String,
              arguments: [String] = [],
              at path: String = ".",
              outputHandle: FileHandle? = nil,
              errorHandle: FileHandle? = nil) throws -> String {
  let process = Process()
  let command = "cd \(path.escapingSpaces) && \(command) \(arguments.joined(separator: " "))"
  return try process.launchBash(with: command, outputHandle: outputHandle, errorHandle: errorHandle)
}

struct ShellError: Swift.Error {
  /// The termination status of the command that was run
  public let terminationStatus: Int32
  /// The error message as a UTF8 string, as returned through `STDERR`
  public var message: String { return errorData.shellOutput() }
  /// The raw error buffer data, as returned through `STDERR`
  public let errorData: Data
  /// The raw output buffer data, as retuned through `STDOUT`
  public let outputData: Data
  /// The output of the command as a UTF8 string, as returned through `STDOUT`
  public var output: String { return outputData.shellOutput() }
}

extension ShellError: CustomStringConvertible {
    public var description: String {
        return """
               ShellOut encountered an error
               Status code: \(terminationStatus)
               Message: "\(message)"
               Output: "\(output)"
               """
    }
}

extension ShellError: LocalizedError {
    public var errorDescription: String? {
        return description
    }
}

extension Process {
  @discardableResult func launchBash(with command: String, outputHandle: FileHandle? = nil, errorHandle: FileHandle? = nil) throws -> String {
    launchPath = "/bin/bash"
    arguments = ["-c", command]

    var outputData = Data()
    var errorData = Data()

    let outputPipe = Pipe()
    standardOutput = outputPipe

    let errorPipe = Pipe()
    standardError = errorPipe

    #if !os(Linux)
      outputPipe.fileHandleForReading.readabilityHandler = { handler in
        let data = handler.availableData
        outputData.append(data)
        outputHandle?.write(data)
      }

      errorPipe.fileHandleForReading.readabilityHandler = { handler in
        let data = handler.availableData
        errorData.append(data)
        errorHandle?.write(data)
      }
    #endif

    launch()

    #if os(Linux)
      outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
      errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    #endif

    waitUntilExit()

    outputHandle?.closeFile()
    errorHandle?.closeFile()

    #if !os(Linux)
      outputPipe.fileHandleForReading.readabilityHandler = nil
      errorPipe.fileHandleForReading.readabilityHandler = nil
    #endif

    if terminationStatus != 0 {
      throw ShellError(
        terminationStatus: terminationStatus,
        errorData: errorData,
        outputData: outputData
      )
    }

    return outputData.shellOutput()
  }

  func launchBashAsync(
    with command: String,
    outputHandle: FileHandle? = nil,
    errorHandle: FileHandle? = nil,
    completion: @escaping (Result<String, ShellError>) -> Void
    ) {

    launchPath = "/bin/bash"
    arguments = ["-c", command]

    var outputData = Data()
    var errorData = Data()

    let outputPipe = Pipe()
    standardOutput = outputPipe

    let errorPipe = Pipe()
    standardError = errorPipe

    #if !os(Linux)
      outputPipe.fileHandleForReading.readabilityHandler = { handler in
        let data = handler.availableData
        outputData.append(data)
        outputHandle?.write(data)
      }

      errorPipe.fileHandleForReading.readabilityHandler = { handler in
        let data = handler.availableData
        errorData.append(data)
        errorHandle?.write(data)
      }
    #endif

    terminationHandler = { process in

      outputHandle?.closeFile()
      errorHandle?.closeFile()

      #if !os(Linux)
        outputPipe.fileHandleForReading.readabilityHandler = nil
        errorPipe.fileHandleForReading.readabilityHandler = nil
      #endif

      if process.terminationStatus != 0 {
        completion(
          .failure(
            ShellError(
              terminationStatus: process.terminationStatus,
              errorData: errorData,
              outputData: outputData
            )
          )
        )
      }
      completion(.success(outputData.shellOutput()))
    }

    launch()

    #if os(Linux)
      outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
      errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    #endif

  }
}

private extension String {
  var escapingSpaces: String {
    return replacingOccurrences(of: " ", with: "\\ ")
  }

  func appending(argument: String) -> String {
    return "\(self) \"\(argument)\""
  }

  func appending(arguments: [String]) -> String {
    return appending(argument: arguments.joined(separator: "\" \""))
  }

  mutating func append(argument: String) {
    self = appending(argument: argument)
  }

  mutating func append(arguments: [String]) {
    self = appending(arguments: arguments)
  }
}

private extension Data {
  func shellOutput() -> String {
    guard let output = String(data: self, encoding: .utf8) else {
      return ""
    }

    guard !output.hasSuffix("\n") else {
      let endIndex = output.index(before: output.endIndex)
      return String(output[..<endIndex])
    }

    return output

  }
}
