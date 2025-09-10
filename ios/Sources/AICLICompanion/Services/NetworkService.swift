//
//  NetworkService.swift
//  AICLICompanion
//
//  Created on 2025-09-04.
//

import Foundation
import Combine

@MainActor
class NetworkService: ObservableObject {
    static let shared = NetworkService()
    
    private let urlSession = URLSession.shared
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    
    private init() {}
    
    func post(endpoint: String, body: [String: Any]) async throws -> [String: Any] {
        // Mock implementation for now
        // In real implementation, would connect to the server
        
        // Simulate network delay
        try await Task.sleep(nanoseconds: 500_000_000)
        
        // Return mock success response
        return [
            "success": true,
            "message": "Mock response"
        ]
    }
    
    func get(endpoint: String) async throws -> [String: Any] {
        // Mock implementation
        try await Task.sleep(nanoseconds: 300_000_000)
        
        return [
            "data": [],
            "success": true
        ]
    }
}
