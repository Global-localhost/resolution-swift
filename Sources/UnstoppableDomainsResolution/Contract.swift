//
//  Contract.swift
//  resolution
//
//  Created by Johnny Good on 8/12/20.
//  Copyright © 2020 Unstoppable Domains. All rights reserved.
//

struct IdentifiableResult<T> {
    var id: String
    var result: T
}

import Foundation
internal class Contract {
    let BATCH_ID_OFFSET = 128
    
    static let OWNER_KEY = "owner"
    static let RESOLVER_KEY = "resolver"
    static let VALUES_KEY = "values"

    let address: String
    let providerUrl: String
    let coder: ABICoder
    let networking: NetworkingLayer

    init(providerUrl: String, address: String, abi: ABIContract, networking: NetworkingLayer) {
        self.address = address
        self.providerUrl = providerUrl
        self.coder = ABICoder(abi)
        self.networking = networking
    }

    func callMethod(methodName: String, args: [Any]) throws -> Any {
        let encodedData = try self.coder.encode(method: methodName, args: args)
        let body = JsonRpcPayload(id: "1", data: encodedData, to: address)
        let response = try postRequest(body)!
        return try self.coder.decode(response, from: methodName)
    }
    
    func callBatchMethod(methodName: String, argsArray: [[Any]]) throws -> [IdentifiableResult<Any>] {
        let encodedDataArray = try argsArray.map { try self.coder.encode(method: methodName, args: $0) }
        let bodyArray: [JsonRpcPayload] = encodedDataArray.enumerated()
                                                            .map { JsonRpcPayload(id: String($0.offset + BATCH_ID_OFFSET),
                                                                                  data: $0.element,
                                                                                  to: address) }
        let response = try postBatchRequest(bodyArray)!
        return try response.map { IdentifiableResult<Any>(id: $0.id, result: try self.coder.decode($0.result, from: methodName)) }
}

    private func postRequest(_ body: JsonRpcPayload) throws -> String? {
        let postRequest = APIRequest(providerUrl, networking: networking)
        var resp: JsonRpcResponseArray?
        var err: Error?
        let semaphore = DispatchSemaphore(value: 0)
        try postRequest.post(body, completion: {result in
            switch result {
            case .success(let response):
                resp = response
            case .failure(let error):
                err = error
            }
            semaphore.signal()
        })
        semaphore.wait()
        guard err == nil else {
            throw err!
        }
        switch resp?[0].result {
        case .string(let result):
            return result
        default:
            return nil
        }
    }
    
    private func postBatchRequest(_ bodyArray: [JsonRpcPayload]) throws -> [IdentifiableResult<String>]? {
        let postRequest = APIRequest(providerUrl, networking: networking)
        var resp: JsonRpcResponseArray?
        var err: Error?
        let semaphore = DispatchSemaphore(value: 0)
        try postRequest.post(bodyArray, completion: {result in
            switch result {
            case .success(let response):
                resp = response
            case .failure(let error):
                err = error
            }
            semaphore.signal()
        })
        semaphore.wait()
        guard err == nil else {
            throw err!
        }
        
        guard let responseArray = resp else { return nil }
        
        let parsedResponseArray: [IdentifiableResult<String>?] = responseArray.map {
            if case let ParamElement.string ( stringResult ) = $0.result {
                return IdentifiableResult<String>(id: $0.id, result: stringResult)
            }
            return nil
        }
        guard parsedResponseArray.reduce(true, { all, element in all && (element != nil) }) else { return nil }
        return parsedResponseArray.map {$0!}
    }
}