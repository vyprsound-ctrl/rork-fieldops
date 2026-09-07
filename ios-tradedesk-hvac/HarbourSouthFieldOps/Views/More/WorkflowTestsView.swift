import SwiftUI

/// Runs the phase-two acceptance scenarios live, against a real gateway with a
/// fresh seed, and shows what came back. This is a development tool: it proves
/// the rules rather than describing them.
struct WorkflowTestsView: View {
    @State private var results: [TestScenarioResult] = []
    @State private var isRunning: Bool = false
    @State private var hasRun: Bool = false

    private var passCount: Int { results.filter(\.passed).count }
    private var failCount: Int { results.filter { !$0.passed }.count }
    private var allPassed: Bool { failCount == 0 && !results.isEmpty }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if isRunning {
                    LoadingStateView(message: "Running scenarios")
                        .frame(height: 200)
                } else if results.isEmpty {
                    EmptyStateView(
                        symbolName: "checklist",
                        title: "Nothing run yet",
                        message: "Runs the full acceptance suite: tenancy, role permissions, field worker restrictions, jobs, quotes, invoicing, payments, receivables, dispatch, scheduling conflicts, location capture, ETA and trade neutrality.",
                        actionTitle: "Run scenarios",
                        action: run
                    )
                    .cardSurface()
                } else {
                    ForEach(results) { result in
                        card(result)
                    }

                    Button(action: run) {
                        Text("Run all \(results.count) scenarios again")
                            .font(.headline)
                            .foregroundStyle(Theme.primary)
                            .frame(maxWidth: .infinity, minHeight: Theme.minTap)
                            .cardSurface()
                    }
                    .buttonStyle(PressableTileStyle())
                }
            }
            .padding(.horizontal, Theme.margin)
            .padding(.bottom, 28)
        }
        .background(Theme.canvas)
        .navigationTitle("Development tests")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .task {
            if !hasRun { run() }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            if hasRun, !results.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 10) {
                        Image(systemName: allPassed ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                            .font(.system(size: 20, weight: .semibold))
                            .foregroundStyle(allPassed ? Theme.green : Theme.amber)
                            .frame(width: 44, height: 44)
                            .background((allPassed ? Theme.green : Theme.amber).opacity(0.12))
                            .clipShape(.circle)

                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(passCount) of \(results.count) passed")
                                .font(.title3.weight(.bold))
                                .foregroundStyle(Theme.ink)
                            Text("Run against a freshly seeded store")
                                .font(.caption)
                                .foregroundStyle(Theme.secondary)
                        }
                        Spacer(minLength: 0)
                    }

                    Divider()

                    HStack(spacing: 10) {
                        tally("Passed", count: passCount, tone: Theme.green, symbolName: "checkmark.circle.fill")
                        tally("Failed", count: failCount, tone: failCount == 0 ? Theme.meta : Theme.red, symbolName: "xmark.octagon.fill")
                        tally("Total", count: results.count, tone: Theme.primary, symbolName: "number.circle.fill")
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .cardSurface()
            }

            Text("Each scenario calls the same data gateway the app uses. Nothing here is stubbed, and none of it touches the data you're browsing in the app.")
                .font(.footnote)
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    /// One headline counter: passed, failed and total are each stated outright
    /// rather than left to be inferred from the list.
    private func tally(_ caption: String, count: Int, tone: Color, symbolName: String) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 5) {
                Image(systemName: symbolName)
                    .font(.caption)
                    .foregroundStyle(tone)
                Text("\(count)")
                    .font(.title3.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(tone)
            }
            Text(caption)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(Theme.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(tone.opacity(0.08))
        .clipShape(.rect(cornerRadius: 8))
    }

    private func card(_ result: TestScenarioResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: result.passed ? "checkmark.circle.fill" : "xmark.octagon.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(result.passed ? Theme.green : Theme.red)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(result.number). \(result.title)")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(result.expectation)
                        .font(.caption)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }

            Text(result.evidence)
                .font(.caption)
                .monospaced()
                .foregroundStyle(result.passed ? Theme.secondary : Theme.red)
                .fixedSize(horizontal: false, vertical: true)
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.canvas)
                .clipShape(.rect(cornerRadius: 8))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func run() {
        isRunning = true
        Task {
            let outcome = await DevelopmentTestSuite.run()
            results = outcome
            isRunning = false
            hasRun = true
        }
    }
}

#Preview {
    NavigationStack {
        WorkflowTestsView()
    }
}
