
import Tower
import Foundation
import Commander

command(
  Argument<String>("Work Dir"),
  Argument<String>("Git URL"),
  Option<String>("PATH", "", flag: "P", description: "Specify PATH on Process"),
  Option<String>("branch_pattern", "", flag: "b", description: "Expression for Branch")
) { path, url, PATH, branchPattern in

  Session(
    workingDirectoryPath: path,
    gitURLString: url,
    loadPathForTowerfile: PATH.isEmpty ? nil : PATH,
    branchPattern: branchPattern
    )
    .start()

  RunLoop.main.run()
  }
  .run()


