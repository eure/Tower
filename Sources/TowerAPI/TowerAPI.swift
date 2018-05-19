//
//  TowerAPI.swift
//  Tower
//
//  Created by muukii on 5/17/18.
//

import Foundation
import Tower

import Vapor

/// Register your application's routes here.
public func routes(_ router: Router) throws {
  // Basic "Hello, world!" example
  router.get("hello") { req in
    return "Hello, world!"
  }


  let controller = GraphQLController()
  router.post("query", use: controller.execute)
  router.get("query", use: controller.execute)

}

/// Called before your application initializes.
public func configure(_ env: inout Environment, _ services: inout Services) throws {
  /// Register providers first

  /// Register routes to the router
  let router = EngineRouter.default()
  try routes(router)
  services.register(router, as: Router.self)

  /// Register middleware
  var middlewares = MiddlewareConfig() // Create _empty_ middleware config
  /// middlewares.use(FileMiddleware.self) // Serves files from `Public/` directory
  middlewares.use(ErrorMiddleware.self) // Catches errors and converts to HTTP response
  services.register(middlewares)

}

/// Creates an instance of Application. This is called from main.swift in the run target.
public func app(_ env: Environment) throws -> Application {
  let config = Config.default()
  var env = env
  var services = Services.default()
  try configure(&env, &services)
  let app = try Application(config: config, environment: env, services: services)
  return app
}
