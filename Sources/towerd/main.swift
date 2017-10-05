
import Tower
import Foundation
import Commander

command(
  Argument<String>("Work Dir"),
  Argument<String>("Git URL")
) { path, url in

  Session(workingDirectoryPath: path, gitURLString: url).start()

  RunLoop.main.run()
  }
  .run()


