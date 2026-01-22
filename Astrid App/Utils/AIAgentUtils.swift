import SwiftUI
import Foundation

/**
 * Utility functions for AI agent type checking
 * Matches web implementation in lib/ai-agent-utils.ts
 */
enum AIAgentUtils {
    /// Valid coding agent types that can perform GitHub operations
    private static let CODING_AGENT_TYPES = ["coding_agent", "claude_agent", "openai_agent", "gemini_agent"]

    /**
     * Check if an AI agent type is a valid coding agent
     * - Parameter aiAgentType: The AI agent type to check
     * - Returns: true if the agent type is a coding agent
     */
    static func isCodingAgentType(_ aiAgentType: String?) -> Bool {
        guard let type = aiAgentType else { return false }
        return CODING_AGENT_TYPES.contains(type)
    }

    /**
     * Check if a user is a coding agent
     * - Parameter user: User object with isAIAgent and aiAgentType properties
     * - Returns: true if the user is a coding agent
     */
    static func isCodingAgent(_ user: User) -> Bool {
        return user.isAIAgent == true && isCodingAgentType(user.aiAgentType)
    }
}