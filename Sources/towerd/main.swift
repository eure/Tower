
import Tower
import Foundation

let path: String? = CommandLine.arguments.indices.contains(1) ? CommandLine.arguments[1] : nil

Session(watchPath: path).start()

RunLoop.main.run()
