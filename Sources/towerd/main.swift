
import Tower
import Foundation
import Commander

command(
  Argument<String>("Work Dir"),
  Argument<String>("Git URL"),
  Option<String>("PATH", "", flag: "P", description: "Specify PATH on Process")
) { path, url, PATH in

  Session(
    workingDirectoryPath: path,
    gitURLString: url,
    loadPathForTowerfile: PATH.isEmpty ? nil : PATH
    )
    .start()

  RunLoop.main.run()
  }
  .run()


