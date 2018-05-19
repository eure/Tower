//
//  GraphQLController.swift
//  TowerAPI
//
//  Created by muukii on 5/19/18.
//

import Foundation

import Graphiti
import Vapor

// https://github.com/GraphQLSwift/Graphiti/blob/master/Tests/GraphitiTests/StarWarsTests/StarWarsSchema.swift

struct QueryContainer : Content {

  let query: String
  let variable: String?
}

struct Session : OutputType {
  let name: String
  let remote: String
}

final class GraphQLController {

  enum Error : Swift.Error {
    case something
  }

  private let schema: Schema<Void, NoContext>

  init() {

    do {
      self.schema = try Schema<Void, NoContext> { schema in

        try schema.object(
          type: Session.self,
          build: { (builder) in
            try builder.exportFields()
        })

        try schema.query { query in

          try query.field(name: "allSessions", type: [Session].self) { _, _, _, _ in
            return [
              Session(name: "a", remote: "a"),
              Session(name: "b", remote: "a"),
              Session(name: "c", remote: "a"),
            ]
          }

          try query.field(name: "hello", type: String.self) { _, _, _, _ in
            return "world"
          }
          try query.field(name: "hoge", type: String.self) { a, b, c, d in
            return "fuga"
          }
        }
      }
    } catch {
      fatalError("\(error)")
    }

    print(schema)
  }

  func execute(request: Request) throws -> Future<String> {

    print(request.http.body)

    return try request.content
      .decode(QueryContainer.self)
      .map({ (queryContainer) -> (String) in
        let r = try self.schema.execute(request: queryContainer.query)
        return r.description
      })

  }
}
