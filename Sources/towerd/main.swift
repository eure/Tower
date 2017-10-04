
import Tower
import Foundation

let path: String = CommandLine.arguments[1]
let url: String = CommandLine.arguments[2]

Session(workingDirectoryPath: path, gitURLString: url).start()


RunLoop.main.run()
