//
//  PlanningValidationModels.swift
//  AICLICompanion
//
//  Models for planning validation API responses
//

import Foundation

// MARK: - Request Models

public struct PlanningValidationRequest: Encodable {
    let content: String
    let projectType: String?
    let projectPath: String?
}

public struct DirectoryAnalysisRequest: Encodable {
    let projectPath: String
}

public struct PlanSaveRequest: Encodable {
    let projectPath: String
    let content: String
}

// MARK: - Response Models

public struct PlanningValidationResponse: Decodable {
    public let success: Bool
    public let validation: ValidationResult
    public let metadata: ValidationMetadata
}

public struct ValidationResult: Decodable {
    public let overallScore: Int
    public let readinessLevel: ReadinessLevelResponse
    public let confidence: Int
    public let domains: [PlanningDomainScoreResponse]
    public let blockers: [BlockerResponse]
    public let suggestions: [SuggestionResponse]
    public let actionItems: [ActionItemResponse]
    public let feedback: [String]
}

public struct ReadinessLevelResponse: Decodable {
    public let level: String
    public let label: String
    public let description: String
    public let icon: String
}

public struct PlanningDomainScoreResponse: Decodable {
    public let name: String
    public let icon: String
    public let score: Int
    public let keywordMatches: Int
    public let foundRequirements: [String]
    public let missingRequirements: [String]
}

public struct BlockerResponse: Decodable {
    public let severity: String
    public let domain: String
    public let message: String
    public let resolution: String?
}

public struct SuggestionResponse: Decodable {
    public let priority: String
    public let message: String
    public let action: String?
}

public struct ActionItemResponse: Decodable {
    public let priority: Int
    public let category: String
    public let icon: String
    public let action: String
    public let impact: String?
    public let effort: String?
}

public struct ValidationMetadata: Decodable {
    public let analyzedAt: String
    public let contentLength: Int
    public let projectType: String
}

// MARK: - Directory Analysis Response

public struct DirectoryAnalysisResponse: Decodable {
    public let success: Bool
    public let analysis: DirectoryAnalysis
}

public struct DirectoryAnalysis: Decodable {
    public let projectPath: String
    public let structure: ProjectStructure
    public let validation: ValidationSummary?
    public let recommendations: [Recommendation]
}

public struct ProjectStructure: Decodable {
    public let directories: [String]
    public let files: [String]
    public let hasPlan: Bool
    public let hasReadme: Bool
    public let hasClaude: Bool
    public let hasIssues: Bool
}

public struct ValidationSummary: Decodable {
    public let overallScore: Int
    public let readinessLevel: ReadinessLevelResponse
    public let domains: [PlanningDomainScoreResponse]
}

public struct Recommendation: Decodable {
    public let priority: String
    public let message: String
    public let action: String
}

// MARK: - Plan Save Response

public struct PlanSaveResponse: Decodable {
    public let success: Bool
    public let result: PlanSaveResult
}

public struct PlanSaveResult: Decodable {
    public let filePath: String
    public let saved: Bool
    public let validation: ValidationSummary
}
