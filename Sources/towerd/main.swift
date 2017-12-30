
import Tower
import Foundation
import Commander

command(
  Argument<String>("path to config.json")
) { path in

  let configURL = URL(fileURLWithPath: (path as NSString).standardizingPath)

  Session(config: Config.load(url: configURL)).start()

  RunLoop.main.run()
  }
  .run()


