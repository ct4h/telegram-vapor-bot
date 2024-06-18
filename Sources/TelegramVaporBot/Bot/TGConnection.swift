//
//  File.swift
//  
//
//  Created by Oleh Hudeichuk on 29.05.2021.
//

import Foundation
import Vapor


public protocol TGConnectionPrtcl {
    
    var bot: TGBot { get }
    var dispatcher: TGDispatcherPrtcl { get }
    
    @discardableResult
    func start() async throws -> Bool
}


public final class TGLongPollingConnection: TGConnectionPrtcl {
    
    public let bot: TGBot
    public let dispatcher: TGDispatcherPrtcl
    public var limit: Int?
    public var timeout: Int? = 10
    public var allowedUpdates: [TGUpdate.CodingKeys]?
    
    private var currentTask: Task<(), any Error>?
    private var offsetUpdates: Int = 0
    private var newOffsetUpdates: Int { offsetUpdates + 1 }
    
    public init(bot: TGBot,
                dispatcher: TGDispatcherPrtcl.Type = TGDefaultDispatcher.self,
                limit: Int? = nil,
                timeout: Int? = nil,
                allowedUpdates: [TGUpdate.CodingKeys]? = nil
    ) async throws {
        self.bot = bot
        self.dispatcher = try await dispatcher.init(bot: bot)
        self.limit = limit
        self.timeout = timeout ?? self.timeout
        self.allowedUpdates = allowedUpdates
    }
    
    @discardableResult
    public func start() async throws -> Bool {
        /// delete webhook because: You will not be able to receive updates using getUpdates for as long as an outgoing webhook is set up.
        let deleteWebHookParams: TGDeleteWebhookParams = .init(dropPendingUpdates: true)
        try await bot.deleteWebhook(params: deleteWebHookParams)
        
        currentTask = Task.detached { [weak self] in
            guard let self = self, let task = self.currentTask else {
                return
            }
            
            while !task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: 100)
                    try await self.getUpdates()
                } catch {
                    try await self.start()
                    task.cancel()
                }
            }
        }
        
        return true
    }
    
    private func getUpdates() async throws {
        let allowedUpdates: [String] = (allowedUpdates ?? []).map { $0.rawValue }
        let params: TGGetUpdatesParams = .init(offset: newOffsetUpdates,
                                               limit: limit,
                                               timeout: timeout,
                                               allowedUpdates: allowedUpdates)
        let response = try await bot.getUpdates(params: params)
        if let lastUpdate: TGUpdate = response.last {
            offsetUpdates = lastUpdate.updateId
        }
        try await dispatcher.process(response)
    }
}


public final class TGWebHookConnection: TGConnectionPrtcl {
    
    public let bot: TGBot
    public let dispatcher: TGDispatcherPrtcl
    public let webHookURL: URI
    
    public init(bot: TGBot, webHookURL: URI, dispatcher: TGDispatcherPrtcl.Type = TGDefaultDispatcher.self) async throws {
        self.bot = bot
        self.webHookURL = webHookURL
        self.dispatcher = try await dispatcher.init(bot: bot)
    }
    
    @discardableResult
    public func start() async throws -> Bool {
        let webHookParams: TGSetWebhookParams = .init(url: webHookURL.description)
        return try await bot.setWebhook(params: webHookParams)
    }
}
