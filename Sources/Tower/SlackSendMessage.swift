//
//  SlackSendMessage.swift
//  Tower
//
//  Created by muukii on 9/24/17.
//

import Foundation

struct SlackMessage : Codable {

  struct Attachment : Codable {

    struct Field : Codable {
      let title: String
      let value: String
      let short: Bool
    }

    let color: String
    let pretext: String
    let author_name: String
    let author_icon: String
    let title: String
    let title_link: String
    let text: String
    let fields: [Field]
    let image_url: String
    let thumb_url: String
    let footer: String
    let footer_icon: String
  }

  var channel: String?
  let text: String?
  let as_user: Bool
  let parse: String
  let username: String
  let attachments: [Attachment]?
}

enum SlackSendMessage {

  static func send(message: SlackMessage) {

    send(message: message, to: "https://hooks.slack.com/services/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")
  }

  static func send(message: SlackMessage, to urlString: String) {

    let sessionConfig = URLSessionConfiguration.default
    let session = URLSession(configuration: sessionConfig, delegate: nil, delegateQueue: nil)
    guard let url = URL(string: urlString) else {return}
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.addValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")

    let encoder = JSONEncoder()
    let data = try! encoder.encode(message)
    request.httpBody = data

    let task = session.dataTask(with: request, completionHandler: { (data: Data?, response: URLResponse?, error: Error?) -> Void in
      if (error == nil) {
        // Success
        let statusCode = (response as! HTTPURLResponse).statusCode
        print("URL Session Task Succeeded: HTTP \(statusCode)")
      }
      else {
        // Failure
        print("URL Session Task Failed: %@", error!.localizedDescription);
      }
    })
    task.resume()
    session.finishTasksAndInvalidate()
  }
}
