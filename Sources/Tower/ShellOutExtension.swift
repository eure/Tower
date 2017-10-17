//
//  ShellOutExtension.swift
//  Tower
//
//  Created by muukii on 9/29/17.
//

import Foundation

extension Process {
  
  @discardableResult func launchBash(
    with command: String,
    loadPATH: String? = nil,
    output: @escaping (String) -> Void,
    error: @escaping (String) -> Void
    ) -> Int32 {
    
    launchPath = "/bin/bash"
    if let loadPATH = loadPATH {
      print("💄 Set Path", loadPATH)
      arguments = ["-c", "export LANG=en_US.UTF-8 export PATH=\(loadPATH) && " + command]
    } else {
      arguments = ["-c", "export LANG=en_US.UTF-8 && " + command]
    }
    
    let outputPipe = Pipe()
    standardOutput = outputPipe
    
    let errorPipe = Pipe()
    standardError = errorPipe
    
    do {
      outputPipe.fileHandleForReading.readabilityHandler = { f in
        
        let d = f.availableData
        
        guard d.count > 0 else { return }
        
        output(d.shellOutput())
      }
    }
    
    do {
      errorPipe.fileHandleForReading.readabilityHandler = { f in
        let d = f.availableData
        
        guard d.count > 0 else { return }
        
        error(d.shellOutput())
      }
    }
    
    launch()
    
    waitUntilExit()
    
    #if !os(Linux)
      outputPipe.fileHandleForReading.readabilityHandler = nil
      errorPipe.fileHandleForReading.readabilityHandler = nil
    #endif
    
    return terminationStatus
  }
}

private extension Data {
  func shellOutput() -> String {
    guard let output = String(data: self, encoding: .utf8) else {
      return ""
    }
    
    //    guard !output.hasSuffix("\n") else {
    //      let outputLength = output.distance(from: output.startIndex, to: output.endIndex)
    //      return output.substring(to: output.index(output.startIndex, offsetBy: outputLength - 1))
    //    }
    
    return output
    
  }
}
