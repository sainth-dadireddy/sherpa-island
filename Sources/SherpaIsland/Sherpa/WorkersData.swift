import SwiftUI

// MARK: - Category color tokens

enum WorkerCategory: String, CaseIterable, Identifiable {
    case pm        // Project Manager / orchestration
    case eng       // Engineering / code
    case reviewer  // Code review / adversarial
    case security  // Security audit
    case research  // Research / long context / multimodal
    case docs      // Docs / classify / bulk
    case cli       // CLI agents (subscription-funded)

    var id: String { rawValue }

    var label: String {
        switch self {
        case .pm: return "PM"
        case .eng: return "Engineering"
        case .reviewer: return "Reviewer"
        case .security: return "Security"
        case .research: return "Research"
        case .docs: return "Docs"
        case .cli: return "CLI Crew"
        }
    }

    var emoji: String {
        switch self {
        case .pm: return "👔"
        case .eng: return "⚙️"
        case .reviewer: return "🔍"
        case .security: return "🛡️"
        case .research: return "📚"
        case .docs: return "📝"
        case .cli: return "🖥️"
        }
    }

    // SwiftUI Color from hex
    var color: (red: Double, green: Double, blue: Double) {
        switch self {
        case .pm:       return (0.51, 0.31, 0.85)  // violet  #8250D8
        case .eng:      return (0.13, 0.83, 0.93)  // cyan    #22D3EE
        case .reviewer: return (0.99, 0.88, 0.28)  // yellow  #FDE047
        case .security: return (0.96, 0.40, 0.40)  // red     #F87171
        case .research: return (0.38, 0.65, 0.98)  // blue    #60A5FA
        case .docs:     return (0.16, 0.72, 0.65)  // teal    #14B8A6
        case .cli:      return (0.98, 0.57, 0.20)  // orange  #FB923C
        }
    }

    var swiftUIColor: Color {
        let (r, g, b) = color
        return Color(red: r, green: g, blue: b)
    }
}

// MARK: - Per-model pricing table

struct ModelPricing {
    let input_per_M: Double    // USD per million input tokens
    let output_per_M: Double
    let billing: String        // "bedrock" | "subscription" | "free-tier" | "local"
}

let MODEL_PRICING: [String: ModelPricing] = [
    // === Claude family (Bedrock) ===
    "claude-opus-4.7":   ModelPricing(input_per_M: 5.00,  output_per_M: 25.00, billing: "bedrock"),
    "claude-sonnet-4.6": ModelPricing(input_per_M: 3.00,  output_per_M: 15.00, billing: "bedrock"),
    "claude-haiku-4.5":  ModelPricing(input_per_M: 1.00,  output_per_M:  5.00, billing: "bedrock"),

    // === Non-Claude Bedrock ===
    "qwen3-coder":       ModelPricing(input_per_M: 0.13,  output_per_M: 0.13,  billing: "bedrock"),
    "deepseek-r1":       ModelPricing(input_per_M: 0.55,  output_per_M: 2.19,  billing: "bedrock"),
    "kimi-k2.5":         ModelPricing(input_per_M: 0.50,  output_per_M: 0.50,  billing: "bedrock"),
    "devstral":          ModelPricing(input_per_M: 0.50,  output_per_M: 0.50,  billing: "bedrock"),
    "nova-pro":          ModelPricing(input_per_M: 0.80,  output_per_M: 3.20,  billing: "bedrock"),
    "nova-lite":         ModelPricing(input_per_M: 0.06,  output_per_M: 0.24,  billing: "bedrock"),
    "nova-micro":        ModelPricing(input_per_M: 0.04,  output_per_M: 0.14,  billing: "bedrock"),
    "gemma-3-4b":        ModelPricing(input_per_M: 0.02,  output_per_M: 0.02,  billing: "bedrock"),
    "gemma-3-12b":       ModelPricing(input_per_M: 0.07,  output_per_M: 0.07,  billing: "bedrock"),
    "gpt-oss-20b":       ModelPricing(input_per_M: 0.03,  output_per_M: 0.03,  billing: "bedrock"),
    "gpt-oss-120b":      ModelPricing(input_per_M: 0.15,  output_per_M: 0.30,  billing: "bedrock"),
    "llama-4-scout":     ModelPricing(input_per_M: 0.16,  output_per_M: 0.16,  billing: "bedrock"),

    // === Direct APIs ===
    "gpt-5":             ModelPricing(input_per_M: 1.25,  output_per_M: 10.00, billing: "subscription"),
    "gpt-5.2-codex":     ModelPricing(input_per_M: 0.00,  output_per_M: 0.00,  billing: "subscription"),
    "gpt-4.1":           ModelPricing(input_per_M: 2.00,  output_per_M: 8.00,  billing: "subscription"),
    "gpt-4.1-nano":      ModelPricing(input_per_M: 0.10,  output_per_M: 0.40,  billing: "subscription"),
    "o4-mini":           ModelPricing(input_per_M: 1.10,  output_per_M: 4.40,  billing: "subscription"),

    // === Free-tier ===
    "gemini-3-pro":      ModelPricing(input_per_M: 0.00,  output_per_M: 0.00,  billing: "free-tier"),
    "gemini-2.5-pro":    ModelPricing(input_per_M: 1.25,  output_per_M: 5.00,  billing: "free-tier"),
    "gemini-2.5-flash":  ModelPricing(input_per_M: 0.15,  output_per_M: 0.60,  billing: "free-tier"),
    "gemini-2.5-flash-lite": ModelPricing(input_per_M: 0.075, output_per_M: 0.30, billing: "free-tier"),
    "gem-async":         ModelPricing(input_per_M: 0.00,  output_per_M: 0.00,  billing: "free-tier"),
    "nano-banana":       ModelPricing(input_per_M: 0.00,  output_per_M: 0.00,  billing: "free-tier"),

    // === Sherpa composite workflows ===
    "sherpa-3-model":            ModelPricing(input_per_M: 0.15, output_per_M: 0.00, billing: "bedrock"),
    "sherpa-researcher":         ModelPricing(input_per_M: 0.25, output_per_M: 0.00, billing: "bedrock"),
    "sherpa-security-analyst":   ModelPricing(input_per_M: 0.50, output_per_M: 0.50, billing: "bedrock"),
    "sherpa-aws-specialist":     ModelPricing(input_per_M: 0.80, output_per_M: 3.20, billing: "bedrock"),
    "sherpa-web-researcher":     ModelPricing(input_per_M: 0.15, output_per_M: 0.15, billing: "bedrock"),
    "sherpa-scraper":            ModelPricing(input_per_M: 0.00, output_per_M: 0.00, billing: "subscription"),

    // === Local (ollama) ===
    "qwen2.5-coder:14b": ModelPricing(input_per_M: 0.00, output_per_M: 0.00, billing: "local"),
    "llama3.2:3b":       ModelPricing(input_per_M: 0.00, output_per_M: 0.00, billing: "local"),
    "deepseek-r1:14b":   ModelPricing(input_per_M: 0.00, output_per_M: 0.00, billing: "local"),
    "gemma:7b":          ModelPricing(input_per_M: 0.00, output_per_M: 0.00, billing: "local"),
]

func priceLabel(for model: String) -> String {
    guard let p = MODEL_PRICING[model] else { return "?" }
    switch p.billing {
    case "free-tier":
        return "free tier"
    case "subscription":
        return p.input_per_M == 0 ? "sub" : String(format: "sub · $%.2f/M", p.output_per_M)
    case "local":
        return "local · $0"
    default:
        if p.input_per_M == p.output_per_M {
            return String(format: "$%.2f/M", p.output_per_M)
        }
        return String(format: "$%.2f in · $%.2f out", p.input_per_M, p.output_per_M)
    }
}

// MARK: - CLI agent specs

let CLI_AGENT_SPECS: [(id: String, name: String, displayName: String, category: WorkerCategory, description: String, llmOptions: [String], defaultLLM: String)] = [
    (id: "cli-codex",
     name: "codex",
     displayName: "Codex (GPT-5)",
     category: .cli,
     description: "Adversarial review, web-grounded answers, OpenAI ecosystem.",
     llmOptions: ["gpt-5", "gpt-5.2-codex", "gpt-4.1", "o4-mini"],
     defaultLLM: "gpt-5"),

    (id: "cli-agy",
     name: "agy",
     displayName: "Agy (Gemini)",
     category: .cli,
     description: "Long context 1M+, multimodal/OCR, CJK, batch classify.",
     llmOptions: ["gemini-3-pro", "gemini-2.5-pro", "gemini-2.5-flash", "nano-banana"],
     defaultLLM: "gemini-3-pro"),

    (id: "cli-ollama",
     name: "ollama",
     displayName: "Ollama (local)",
     category: .cli,
     description: "Local-only, offline classify, sensitive content, $0.",
     llmOptions: ["qwen2.5-coder:14b", "llama3.2:3b", "deepseek-r1:14b", "gemma:7b"],
     defaultLLM: "qwen2.5-coder:14b"),

    (id: "cli-jules",
     name: "jules",
     displayName: "Jules (async)",
     category: .cli,
     description: "Async cloud-VM coding agent. GitHub-PR based hours-long work.",
     llmOptions: ["gem-async", "gem-async", "gem-async", "gem-async"],
     defaultLLM: "gem-async"),

    (id: "cli-claude",
     name: "claude",
     displayName: "Claude (Max sub)",
     category: .cli,
     description: "Orchestrator + reasoning. Free via Max subscription.",
     llmOptions: ["claude-opus-4.7", "claude-sonnet-4.6", "claude-haiku-4.5", "gpt-5"],
     defaultLLM: "claude-opus-4.7"),
]

// MARK: - Live updating selected LLM persistence helper

struct WorkerLLMSelection {
    static let key = { (agentId: String) in "worker.\(agentId).llm" }

    static func get(_ agentId: String, default defaultModel: String) -> String {
        UserDefaults.standard.string(forKey: key(agentId)) ?? defaultModel
    }

    static func set(_ agentId: String, model: String) {
        UserDefaults.standard.set(model, forKey: key(agentId))
        // Post notification so observers can react live
        NotificationCenter.default.post(
            name: .workerLLMChanged,
            object: nil,
            userInfo: ["agentId": agentId, "model": model]
        )
    }
}

extension Notification.Name {
    static let workerLLMChanged = Notification.Name("workerLLMChanged")
}
