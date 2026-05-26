import SwiftUI

// SDK persona specs (sherpa-platform's pm/eng/reviewer/qa pool).
// These live alongside CLI_AGENT_SPECS in WorkersData.swift.
struct SDKPersonaSpec: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let category: WorkerCategory
    let description: String
    let llmOptions: [String]
    let defaultLLM: String
}

let SDK_AGENT_SPECS: [SDKPersonaSpec] = [
    .init(id: "pm",        name: "pm",        displayName: "PM Lead",
          category: .pm,        description: "Architecture, deep reasoning, orchestration.",
          llmOptions: ["claude-opus-4.7", "claude-sonnet-4.6", "gpt-5", "gemini-2.5-pro"],
          defaultLLM: "claude-opus-4.7"),
    .init(id: "eng",       name: "eng",       displayName: "Engineer",
          category: .eng,       description: "Code generation, refactoring, scaffolding.",
          llmOptions: ["qwen3-coder", "claude-sonnet-4.6", "gpt-5", "devstral"],
          defaultLLM: "qwen3-coder"),
    .init(id: "reviewer",  name: "reviewer",  displayName: "Reviewer",
          category: .reviewer,  description: "3-model consensus catches 40% more bugs.",
          llmOptions: ["sherpa-3-model", "deepseek-r1", "claude-opus-4.7", "kimi-k2.5"],
          defaultLLM: "sherpa-3-model"),
    .init(id: "architect", name: "architect", displayName: "Architect",
          category: .pm,        description: "System design, trade-off analysis, RCA.",
          llmOptions: ["claude-opus-4.7", "deepseek-r1", "gpt-5", "gemini-2.5-pro"],
          defaultLLM: "claude-opus-4.7"),
    .init(id: "security",  name: "security",  displayName: "Security",
          category: .security,  description: "OWASP scans, IAM review, secret hunting.",
          llmOptions: ["kimi-k2.5", "sherpa-security-analyst", "claude-opus-4.7", "deepseek-r1"],
          defaultLLM: "kimi-k2.5"),
    .init(id: "research",  name: "research",  displayName: "Researcher",
          category: .research,  description: "Long context + 4-model research pipeline.",
          llmOptions: ["sherpa-researcher", "gemini-2.5-pro", "claude-opus-4.7", "llama-4-scout"],
          defaultLLM: "sherpa-researcher"),
    .init(id: "ocr",       name: "ocr",       displayName: "OCR/Multimodal",
          category: .research,  description: "Native multimodal: PDFs, images, screenshots.",
          llmOptions: ["gemini-2.5-pro", "nova-pro", "claude-opus-4.7"],
          defaultLLM: "gemini-2.5-pro"),
    .init(id: "docs",      name: "docs",      displayName: "Doc Writer",
          category: .docs,      description: "READMEs, changelogs, summaries.",
          llmOptions: ["nova-lite", "claude-haiku-4.5", "gpt-oss-120b", "gpt-4.1-nano"],
          defaultLLM: "nova-lite"),
    .init(id: "qa",        name: "qa",        displayName: "QA Tester",
          category: .docs,      description: "Test plans, edge cases, regression.",
          llmOptions: ["claude-haiku-4.5", "qwen3-coder", "gemini-2.5-flash", "gpt-4.1-nano"],
          defaultLLM: "claude-haiku-4.5"),
    .init(id: "classify",  name: "classify",  displayName: "Classifier",
          category: .docs,      description: "Bulk labeling. nova-micro = 75x cheaper.",
          llmOptions: ["nova-micro", "gemma-3-4b", "gpt-oss-20b", "claude-haiku-4.5"],
          defaultLLM: "nova-micro"),
    .init(id: "aws",       name: "aws",       displayName: "AWS Specialist",
          category: .research,  description: "Lambda, IAM, Terraform; deep AWS knowledge.",
          llmOptions: ["sherpa-aws-specialist", "claude-opus-4.7", "gpt-5", "gemini-2.5-pro"],
          defaultLLM: "sherpa-aws-specialist"),
    .init(id: "scraper",   name: "scraper",   displayName: "Web Researcher",
          category: .research,  description: "Anti-bot scraping, extraction.",
          llmOptions: ["sherpa-web-researcher", "gpt-5"],
          defaultLLM: "sherpa-web-researcher"),
]

// Unified card model spanning both SDK personas and CLI agents.
struct WorkerCardData: Identifiable, Hashable {
    let id: String
    let name: String
    let displayName: String
    let category: WorkerCategory
    let description: String
    let llmOptions: [String]
    let defaultLLM: String
    let isCLI: Bool
}

func allWorkerCards() -> [WorkerCardData] {
    let sdk = SDK_AGENT_SPECS.map {
        WorkerCardData(
            id: $0.id, name: $0.name, displayName: $0.displayName,
            category: $0.category, description: $0.description,
            llmOptions: $0.llmOptions, defaultLLM: $0.defaultLLM,
            isCLI: false
        )
    }
    let cli = CLI_AGENT_SPECS.map { spec in
        WorkerCardData(
            id: spec.id, name: spec.name, displayName: spec.displayName,
            category: spec.category, description: spec.description,
            llmOptions: spec.llmOptions, defaultLLM: spec.defaultLLM,
            isCLI: true
        )
    }
    return sdk + cli
}


struct WorkersBoardView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let cards = allWorkerCards()
        let byCat = Dictionary(grouping: cards, by: { $0.category })

        VStack(spacing: 0) {
            HStack {
                Text("AI Workers")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(red: 0.20, green: 0.235, blue: 0.302))

            Divider()

            ScrollView(.horizontal, showsIndicators: true) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(WorkerCategory.allCases) { cat in
                        let items = byCat[cat] ?? []
                        if !items.isEmpty {
                            CategoryColumn(category: cat, cards: items)
                        }
                    }
                }
                .padding(12)
            }
            .background(Color(red: 0.165, green: 0.192, blue: 0.255))
        }
        .frame(minWidth: 1100, idealWidth: 1300, minHeight: 600, idealHeight: 700)
    }
}


private struct CategoryColumn: View {
    let category: WorkerCategory
    let cards: [WorkerCardData]

    var body: some View {
        let c = category.color
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(category.emoji).font(.system(size: 14))
                Text(category.label.uppercased())
                    .font(.system(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundColor(Color(red: c.red, green: c.green, blue: c.blue))
                Spacer()
                Text("\(cards.count)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 4)

            ForEach(cards) { card in
                WorkerCardView(card: card)
            }
        }
        .frame(width: 250, alignment: .topLeading)
    }
}


private struct WorkerCardView: View {
    let card: WorkerCardData
    @State private var selectedLLM: String = ""

    var body: some View {
        let c = card.category.color
        let catColor = Color(red: c.red, green: c.green, blue: c.blue)
        let activeLLM = selectedLLM.isEmpty ? WorkerLLMSelection.get(card.id, default: card.defaultLLM) : selectedLLM

        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                // Avatar circle with initial
                ZStack {
                    Circle().fill(catColor.opacity(0.25))
                    Text(String(card.displayName.prefix(1)))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(catColor)
                }
                .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 1) {
                    Text(card.displayName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    Text(activeLLM)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                if card.isCLI {
                    Text("CLI")
                        .font(.system(size: 8, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 4).padding(.vertical, 1)
                        .background(Capsule().fill(catColor.opacity(0.25)))
                        .foregroundColor(catColor)
                }
            }

            Text(card.description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 4) {
                Text("LLM:")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
                Picker("", selection: Binding(
                    get: { activeLLM },
                    set: { newVal in
                        selectedLLM = newVal
                        WorkerLLMSelection.set(card.id, model: newVal)
                    })
                ) {
                    ForEach(card.llmOptions, id: \.self) { opt in
                        Text(opt).tag(opt)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 4) {
                Text("Price:")
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(priceLabel(for: activeLLM))
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(.primary)
                    .lineLimit(1)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.20, green: 0.235, blue: 0.302))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(catColor.opacity(0.30), lineWidth: 0.5)
        )
        .onAppear {
            if selectedLLM.isEmpty {
                selectedLLM = WorkerLLMSelection.get(card.id, default: card.defaultLLM)
            }
        }
    }
}
