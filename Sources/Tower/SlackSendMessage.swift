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

      init(
        title: String,
        value: String,
        short: Bool
        ) {
        self.title = title
        self.value = value
        self.short = short
      }
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

    init(
      color: String,
      pretext: String,
      authorName: String,
      authorIcon: String,
      title: String,
      titleLink: String,
      text: String,
      imageURL: String,
      thumbURL: String,
      footer: String,
      footerIcon: String,
      fields: [Field]
      ) {

      self.color = color
      self.pretext = pretext
      self.author_name = authorName
      self.author_icon = authorIcon
      self.title = title
      self.title_link = titleLink
      self.text = text
      self.image_url = imageURL
      self.thumb_url = thumbURL
      self.footer = footer
      self.footer_icon = footerIcon
      self.fields = fields

    }
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
