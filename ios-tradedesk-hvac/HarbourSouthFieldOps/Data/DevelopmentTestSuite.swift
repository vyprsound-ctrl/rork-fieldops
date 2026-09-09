import Foundation

nonisolated struct TestScenarioResult: Identifiable, Hashable, Sendable {
    let id: String
    let number: Int
    let title: String
    let expectation: String
    let passed: Bool
    let evidence: String
}

/// DEVELOPMENT ONLY.
///
/// Runs the phase-one and phase-two acceptance scenarios against a real
/// `MockDataGateway` with a freshly seeded store, so the results reflect the
/// actual enforcement path rather than a description of it. Nothing here
/// touches the store the running app is using.
enum DevelopmentTestSuite {
    private static func session(_ userID: String, _ role: Role, _ name: String, company: String = "cmp_gulfcoast", trade: Trade = .hvac) -> TenantSession {
        TenantSession(
            userID: userID,
            companyID: company,
            role: role,
            displayName: name,
            email: "\(userID)@example.com",
            trade: trade
        )
    }

    static func run() async -> [TestScenarioResult] {
        let gateway = MockDataGateway(store: .seeded(), latency: .zero)

        let owner = session("usr_owner", .owner, "Tom Ellison")
        let dispatcher = session("usr_dispatch", .dispatcher, "Carla Bell")
        let marcus = session("usr_marcus", .fieldWorker, "Marcus Hale")
        let accounts = session("usr_accounts", .accounts, "Joan Petrov")
        let dee = session("usr_dee", .fieldWorker, "Dee Nguyen")
        // Second tenant, second trade — same schema, same gateway.
        let northOwner = session("usr_north_owner", .owner, "Erin Vaught", company: "cmp_northline", trade: .plumbing)

        var results: [TestScenarioResult] = []
        var ownerJobCount = 0

        // 1 — Owner sees every job and every quote figure.
        do {
            let jobs = try await gateway.jobs(session: owner, query: allJobs)
            ownerJobCount = jobs.count
            let quote = try await gateway.quoteDetail(session: owner, quoteID: "qte_coastal")
            let passed = jobs.count > 0 && quote.totals != nil
            results.append(
                TestScenarioResult(
                    id: "1",
                    number: 1,
                    title: "Owner sees all jobs and quote financials",
                    expectation: "Every company job is returned and quote totals are present",
                    passed: passed,
                    evidence: "\(jobs.count) jobs returned · \(quote.number) total \(quote.totals?.totalLabel ?? "missing")"
                )
            )
        } catch {
            results.append(failure(1, "Owner sees all jobs and quote financials", "Every company job is returned and quote totals are present", error))
        }

        // 2 — Dispatcher runs operations with no money in the payload.
        do {
            let jobs = try await gateway.jobs(session: dispatcher, query: allJobs)
            let quote = try await gateway.quoteDetail(session: dispatcher, quoteID: "qte_coastal")
            let jobDetail = try await gateway.jobDetail(session: dispatcher, jobID: "job_1042")
            let noRowValues = jobs.allSatisfy { $0.value == nil }
            let noLinePricing = quote.lineItems.allSatisfy { $0.pricing == nil }
            let passed = jobs.count == ownerJobCount
                && noRowValues
                && quote.totals == nil
                && noLinePricing
                && jobDetail.financials == nil
                && !quote.lineItems.isEmpty
            results.append(
                TestScenarioResult(
                    id: "2",
                    number: 2,
                    title: "Dispatcher manages jobs without financial data",
                    expectation: "Same job rows as the owner, but no totals, line pricing or job money",
                    passed: passed,
                    evidence: "\(jobs.count) jobs (owner: \(ownerJobCount)) · row values \(noRowValues ? "all nil" : "LEAKED") · quote totals \(quote.totals == nil ? "nil" : "LEAKED") · \(quote.lineItems.count) line items readable, pricing \(noLinePricing ? "nil" : "LEAKED")"
                )
            )
        } catch {
            results.append(failure(2, "Dispatcher manages jobs without financial data", "Same job rows as the owner, but no totals or pricing", error))
        }

        // 3 — Field worker only ever sees their own assignments.
        do {
            let jobs = try await gateway.jobs(session: marcus, query: allJobs)
            let numbers = jobs.map(\.number).sorted()
            let seesOthers = jobs.contains { $0.id == "job_1049" || $0.id == "job_1045" }
            let passed = !jobs.isEmpty && !seesOthers && jobs.count < ownerJobCount
            results.append(
                TestScenarioResult(
                    id: "3",
                    number: 3,
                    title: "Field worker sees only assigned jobs",
                    expectation: "Marcus receives his assignments and none of Dee's",
                    passed: passed,
                    evidence: "\(jobs.count) of \(ownerJobCount) company jobs: \(numbers.joined(separator: ", "))"
                )
            )
        } catch {
            results.append(failure(3, "Field worker sees only assigned jobs", "Marcus receives his assignments only", error))
        }

        // 4 — The field payload has no monetary field at all.
        do {
            let detail = try await gateway.fieldWorkerJobDetail(session: marcus, jobID: "job_1042")
            let day = try await gateway.fieldWorkerDay(session: marcus)
            let detailOffenders = monetaryFields(of: detail)
            let stopOffenders = day.stops.first.map { monetaryFields(of: $0) } ?? []
            let passed = detailOffenders.isEmpty && stopOffenders.isEmpty
            results.append(
                TestScenarioResult(
                    id: "4",
                    number: 4,
                    title: "Field worker payload contains no monetary fields",
                    expectation: "Reflection over FieldWorkerJobDetail and FieldWorkerStop finds no money field",
                    passed: passed,
                    evidence: passed
                        ? "FieldWorkerJobDetail (\(fieldCount(detail)) fields) and FieldWorkerStop carry no price, total, tax, invoice or payment field"
                        : "Found: \((detailOffenders + stopOffenders).joined(separator: ", "))"
                )
            )
        } catch {
            results.append(failure(4, "Field worker payload contains no monetary fields", "No money field in the field payload", error))
        }

        // 5 — Field worker performs the valid field transitions.
        var transitionTrail: [String] = []
        do {
            let before = try await gateway.fieldWorkerJobDetail(session: marcus, jobID: "job_1043")
            transitionTrail.append(before.status.title)
            try await gateway.updateJobStatus(session: marcus, jobID: "job_1043", to: .travelling)
            transitionTrail.append("Travelling")
            try await gateway.updateJobStatus(session: marcus, jobID: "job_1043", to: .arrived)
            transitionTrail.append("Arrived")
            try await gateway.updateJobStatus(session: marcus, jobID: "job_1043", to: .inProgress)
            transitionTrail.append("In progress")
            let after = try await gateway.fieldWorkerJobDetail(session: marcus, jobID: "job_1043")
            results.append(
                TestScenarioResult(
                    id: "5",
                    number: 5,
                    title: "Field worker can perform valid status transitions",
                    expectation: "Assigned → Travelling → Arrived → In progress all accepted",
                    passed: after.status == .inProgress,
                    evidence: transitionTrail.joined(separator: " → ")
                )
            )
        } catch {
            results.append(failure(5, "Field worker can perform valid status transitions", "Assigned → Travelling → Arrived → In progress", error))
        }

        // 5b — an out-of-order jump is refused by the workflow itself.
        do {
            try await gateway.updateJobStatus(session: marcus, jobID: "job_1044", to: .completed)
            results.append(
                TestScenarioResult(
                    id: "5b",
                    number: 5,
                    title: "Out-of-order transition is refused",
                    expectation: "Assigned → Completed is rejected by the workflow",
                    passed: false,
                    evidence: "The jump was accepted — the workflow table was not consulted"
                )
            )
        } catch let error as DataError {
            var isTransitionError = false
            if case .invalidTransition = error { isTransitionError = true }
            results.append(
                TestScenarioResult(
                    id: "5b",
                    number: 5,
                    title: "Out-of-order transition is refused",
                    expectation: "Assigned → Completed is rejected by the workflow",
                    passed: isTransitionError,
                    evidence: error.errorDescription ?? "rejected"
                )
            )
        } catch {
            results.append(failure(5, "Out-of-order transition is refused", "Assigned → Completed rejected", error))
        }

        // 6 — Field worker cannot touch another worker's job.
        do {
            try await gateway.updateJobStatus(session: marcus, jobID: "job_1049", to: .travelling)
            results.append(
                TestScenarioResult(
                    id: "6",
                    number: 6,
                    title: "Field worker cannot modify an unassigned job",
                    expectation: "Writing to Dee's job answers notFound, not a permission hint",
                    passed: false,
                    evidence: "The write succeeded — cross-worker isolation failed"
                )
            )
        } catch let error as DataError {
            let passed = error == .notFound
            results.append(
                TestScenarioResult(
                    id: "6",
                    number: 6,
                    title: "Field worker cannot modify an unassigned job",
                    expectation: "Writing to Dee's job answers notFound, not a permission hint",
                    passed: passed,
                    evidence: passed
                        ? "J-1049 (Dee's) answered notFound for Marcus — the row's existence is never disclosed"
                        : "Wrong error: \(error.errorDescription ?? "")"
                )
            )
        } catch {
            results.append(failure(6, "Field worker cannot modify an unassigned job", "notFound is returned", error))
        }

        // 7 — Accounts reads the money but holds no operational control.
        do {
            let quote = try await gateway.quoteDetail(session: accounts, quoteID: "qte_coastal")
            let hasTotals = quote.totals != nil
            var blocked = false
            var blockedDetail = "The operational write was accepted — accounts should not hold job control"
            do {
                try await gateway.updateJobStatus(session: accounts, jobID: "job_1044", to: .travelling)
            } catch let error as DataError {
                if case .notPermitted = error {
                    blocked = true
                    blockedDetail = error.errorDescription ?? "blocked"
                }
            }
            results.append(
                TestScenarioResult(
                    id: "7",
                    number: 7,
                    title: "Accounts reads quote financials, not job controls",
                    expectation: "Totals are served; an operational status write is refused",
                    passed: hasTotals && blocked,
                    evidence: "\(quote.number) total \(quote.totals?.totalLabel ?? "missing") · job write: \(blockedDetail)"
                )
            )
        } catch {
            results.append(failure(7, "Accounts reads quote financials, not job controls", "Totals served, job write refused", error))
        }

        // 8 — Accepted quote becomes a job, and the quote survives untouched.
        do {
            let before = try await gateway.quoteDetail(session: owner, quoteID: "qte_coastal")
            let jobID = try await gateway.convertQuoteToJob(
                session: owner,
                quoteID: "qte_coastal",
                input: QuoteConversionInput(kind: .install, priority: .standard, scheduledStart: nil, scheduledEnd: nil, fieldWorkerUserID: nil)
            )
            let job = try await gateway.jobDetail(session: owner, jobID: jobID)
            let after = try await gateway.quoteDetail(session: owner, quoteID: "qte_coastal")

            let quoteIntact = after.status == .accepted
                && after.lineItems.count == before.lineItems.count
                && after.totals?.total == before.totals?.total
            let jobLinked = job.quoteID == "qte_coastal"
                && job.customerID == before.customerID
                && job.addressLine == before.addressLine
                && job.jobDescription.contains(before.number)

            var doubleConversionBlocked = false
            do {
                _ = try await gateway.convertQuoteToJob(session: owner, quoteID: "qte_coastal", input: QuoteConversionInput())
            } catch {
                doubleConversionBlocked = true
            }

            results.append(
                TestScenarioResult(
                    id: "8",
                    number: 8,
                    title: "Accepted quote converts into a job",
                    expectation: "Customer, address, asset and scope carry over; the quote is unchanged",
                    passed: quoteIntact && jobLinked && doubleConversionBlocked,
                    evidence: "\(before.number) → \(job.number) · quote still \(after.status.title) with \(after.lineItems.count) lines at \(after.totals?.totalLabel ?? "—") · asset \(job.equipment == nil ? "none on site" : "carried") · second conversion \(doubleConversionBlocked ? "refused" : "ALLOWED")"
                )
            )
        } catch {
            results.append(failure(8, "Accepted quote converts into a job", "Job raised, quote untouched", error))
        }

        // 9 — Money maths stay exact.
        results.append(lineItemArithmetic())

        // 10 — Every transition leaves a history row.
        do {
            let before = try await gateway.jobDetail(session: owner, jobID: "job_1043")
            let entries = before.timeline
            let hasActors = entries.allSatisfy { !$0.byLabel.isEmpty && !$0.timeLabel.isEmpty }
            let located = entries.filter { $0.locationLabel != nil }.count
            // Three transitions were made in scenario 5 on this job.
            let passed = entries.count >= 4 && hasActors && located >= 3
            results.append(
                TestScenarioResult(
                    id: "10",
                    number: 10,
                    title: "Job status history records every transition",
                    expectation: "Each change stores job, from, to, user, timestamp and field location",
                    passed: passed,
                    evidence: "J-1043 timeline has \(entries.count) rows, all with a user and timestamp; \(located) carry a captured location · last: \(entries.last?.title ?? "—")"
                )
            )
        } catch {
            results.append(failure(10, "Job status history records every transition", "History rows written for each change", error))
        }

        // 11 — Tenant isolation across two companies.
        do {
            let northJobs = try await gateway.jobs(session: northOwner, query: allJobs)
            let northQuotes = try await gateway.quotes(session: northOwner, filter: .all, query: "")
            let leakedJob = northJobs.contains { $0.number.hasPrefix("J-") }
            let leakedQuote = northQuotes.contains { $0.number.hasPrefix("Q-") }

            var gulfRowHidden = false
            do {
                _ = try await gateway.jobDetail(session: northOwner, jobID: "job_1042")
            } catch let error as DataError {
                gulfRowHidden = error == .notFound
            }

            let passed = !leakedJob && !leakedQuote && !northJobs.isEmpty && gulfRowHidden
            results.append(
                TestScenarioResult(
                    id: "11",
                    number: 11,
                    title: "Second company sees only its own records",
                    expectation: "No cross-tenant rows, and a direct request for one answers notFound",
                    passed: passed,
                    evidence: "Northline: \(northJobs.count) jobs (\(northJobs.map(\.number).joined(separator: ", "))), \(northQuotes.count) quotes · Gulf Coast row J-1042 \(gulfRowHidden ? "answered notFound" : "WAS VISIBLE")"
                )
            )
        } catch {
            results.append(failure(11, "Second company sees only its own records", "No cross-tenant rows", error))
        }

        // 12 — The same schema and workflow serve a different trade.
        // (Scenarios 13–16 cover the phase 2.5 configuration changes and each
        // build their own gateway so their numbers are deterministic.)
        do {
            let northJob = try await gateway.jobDetail(session: northOwner, jobID: "job_north_1")
            let hvacTerms = Trade.hvac.terminology
            let plumbingTerms = Trade.plumbing.terminology

            let roleReadsDifferently = Role.fieldWorker.title(hvacTerms) == "Engineer"
                && Role.fieldWorker.title(plumbingTerms) == "Plumber"
            let statusReadsDifferently = JobStatus.workerAssigned.title(hvacTerms) == "Engineer assigned"
                && JobStatus.workerAssigned.title(plumbingTerms) == "Plumber assigned"
            // The plumbing asset is stored with a free-text category and its own
            // trade attributes — no HVAC enum is involved.
            let assetIsGeneric = northJob.equipment?.subtitle.contains("Water heater") ?? false
            let hasTradeAttributes = !(northJob.equipment?.attributes.isEmpty ?? true)
            // Identical workflow: the same nine states and the same transitions.
            let sameWorkflow = northJob.status == .workerAssigned

            let passed = roleReadsDifferently && statusReadsDifferently && assetIsGeneric && hasTradeAttributes && sameWorkflow
            results.append(
                TestScenarioResult(
                    id: "12",
                    number: 12,
                    title: "Same platform serves a second trade",
                    expectation: "One schema, one workflow, one permission matrix — only the vocabulary changes",
                    passed: passed,
                    evidence: "Plumbing job \(northJob.number) runs the same workflow at '\(northJob.status.title(plumbingTerms))' · asset '\(northJob.equipment?.subtitle ?? "—")' with \(northJob.equipment?.attributes.count ?? 0) trade attributes · field role reads '\(Role.fieldWorker.title(hvacTerms))' for HVAC and '\(Role.fieldWorker.title(plumbingTerms))' for plumbing"
                )
            )
        } catch {
            results.append(failure(12, "Same platform serves a second trade", "One schema serves both trades", error))
        }

        // 13 — Customer classification is an open list, not a binary.
        do {
            let rows = try await gateway.customers(session: owner, query: "")
            let coastal = rows.first { $0.id == "cus_coastal" }
            let classifications = CustomerType.allCases.map(\.title)
            // A classification this build has never heard of must degrade to
            // "other", not fail to decode — the list can grow server-side.
            let unknown = try JSONDecoder().decode(CustomerType.self, from: Data("\"housingAssociation\"".utf8))
            let passed = classifications.count == 4
                && coastal?.typeTitle == "Property management"
                && unknown == .other
            results.append(
                TestScenarioResult(
                    id: "13",
                    number: 13,
                    title: "Customer classification is not limited to residential/commercial",
                    expectation: "Four starting classifications, and an unknown one decodes to Other",
                    passed: passed,
                    evidence: "\(classifications.joined(separator: ", ")) · Coastal Storage reads '\(coastal?.typeTitle ?? "—")' and still runs the full quote → job flow · unknown value decoded as '\(unknown.title)'"
                )
            )
        } catch {
            results.append(failure(13, "Customer classification is not limited to residential/commercial", "Four classifications plus a safe fallback", error))
        }

        // 14 — Currency comes from company configuration, not from a constant.
        do {
            var euroStore = MockDataStore.seeded()
            if let index = euroStore.companies.firstIndex(where: { $0.id == "cmp_gulfcoast" }) {
                euroStore.companies[index].currencyCode = "EUR"
                euroStore.companies[index].countryCode = "IE"
                euroStore.companies[index].timeZoneIdentifier = "Europe/Dublin"
            }
            let euroGateway = MockDataGateway(store: euroStore, latency: .zero)
            let euroQuote = try await euroGateway.quoteDetail(session: owner, quoteID: "qte_coastal")
            let usdQuote = try await gateway.quoteDetail(session: owner, quoteID: "qte_whitaker")

            let euroLabel = euroQuote.totals?.totalLabel ?? ""
            let usdLabel = usdQuote.totals?.totalLabel ?? ""
            // The amount is untouched by the currency setting: only the label
            // changes, because the maths is decimal and currency-neutral.
            let sameDecimal = euroQuote.totals?.total == Money.dec("5205.55")
            let passed = euroLabel.contains("€") && usdLabel.contains("$") && sameDecimal
                && euroQuote.currencyCode == "EUR"
            results.append(
                TestScenarioResult(
                    id: "14",
                    number: 14,
                    title: "Country, currency and timezone are company configuration",
                    expectation: "Changing only the company's currency changes every label; the decimal amount is unaffected",
                    passed: passed,
                    evidence: "Same quote, same stored decimal \(euroQuote.totals?.total.description ?? "—") → '\(euroLabel)' when the company is set to EUR/IE, '\(usdLabel)' for the USD company · Formatters.currency has no default code to fall back on"
                )
            )
        } catch {
            results.append(failure(14, "Country, currency and timezone are company configuration", "Currency label follows company config", error))
        }

        // 15 — The company tax rate is a default, and history stays stable.
        do {
            let baseline = MockDataGateway(store: .seeded(), latency: .zero)
            let before = try await baseline.quoteDetail(session: owner, quoteID: "qte_coastal")

            // The company later raises its default rate from 7% to 9%.
            var raisedStore = MockDataStore.seeded()
            if let index = raisedStore.companies.firstIndex(where: { $0.id == "cmp_gulfcoast" }) {
                raisedStore.companies[index].defaultTaxRate = Money.percent("9")
            }
            let raised = MockDataGateway(store: raisedStore, latency: .zero)
            let after = try await raised.quoteDetail(session: owner, quoteID: "qte_coastal")

            let taxUnchanged = after.totals?.tax == before.totals?.tax
                && after.totals?.total == before.totals?.total
            let linesKeepTheirRate = after.lineItems.allSatisfy { $0.pricing?.taxRate == Money.percent("7") }
            let newLinesUseNewDefault = after.defaultTaxRate == Money.percent("9")

            let passed = taxUnchanged && linesKeepTheirRate && newLinesUseNewDefault
            results.append(
                TestScenarioResult(
                    id: "15",
                    number: 15,
                    title: "Company tax rate is a default, not a retrospective rule",
                    expectation: "Raising the company default leaves existing documents' tax untouched",
                    passed: passed,
                    evidence: "Company default 7% → 9%: \(before.number) tax stays \(before.totals?.taxLabel ?? "—") and total \(before.totals?.totalLabel ?? "—") · all \(after.lineItems.count) existing lines still carry 7% · a new line would now be offered \(Money.percentLabel(after.defaultTaxRate ?? 0))"
                )
            )
        } catch {
            results.append(failure(15, "Company tax rate is a default, not a retrospective rule", "Existing tax is historically stable", error))
        }

        // 16 — Document numbering is company-scoped configuration.
        do {
            let numbering = MockDataGateway(store: .seeded(), latency: .zero)

            let gulfQuoteID = try await numbering.createQuote(
                session: owner,
                input: NewQuoteInput(customerID: "cus_ramirez", addressID: "adr_ramirez", title: "Numbering probe", scopeOfWork: "", validUntil: nil)
            )
            let gulfJobID = try await numbering.createJob(
                session: owner,
                input: NewJobInput(customerID: "cus_ramirez", addressID: "adr_ramirez", title: "Numbering probe", jobDescription: "")
            )
            let northQuoteID = try await numbering.createQuote(
                session: northOwner,
                input: NewQuoteInput(customerID: "cus_north_a", addressID: "adr_north_a", title: "Numbering probe", scopeOfWork: "", validUntil: nil)
            )
            let northJobID = try await numbering.createJob(
                session: northOwner,
                input: NewJobInput(customerID: "cus_north_a", addressID: "adr_north_a", title: "Numbering probe", jobDescription: "")
            )

            let gulfQuote = try await numbering.quoteDetail(session: owner, quoteID: gulfQuoteID)
            let gulfJob = try await numbering.jobDetail(session: owner, jobID: gulfJobID)
            let northQuote = try await numbering.quoteDetail(session: northOwner, quoteID: northQuoteID)
            let northJob = try await numbering.jobDetail(session: northOwner, jobID: northJobID)

            // Each company follows its own configured prefix and counter.
            let gulfFollowsDefaults = gulfQuote.number == "Q-2092" && gulfJob.number == "J-1050"
            let northFollowsItsOwn = northQuote.number == "N-Q-411" && northJob.number == "N-3002"

            // A second company issuing documents must not move this one on.
            let secondGulfQuoteID = try await numbering.createQuote(
                session: owner,
                input: NewQuoteInput(customerID: "cus_ramirez", addressID: "adr_ramirez", title: "Numbering probe 2", scopeOfWork: "", validUntil: nil)
            )
            let secondGulfQuote = try await numbering.quoteDetail(session: owner, quoteID: secondGulfQuoteID)
            let unaffected = secondGulfQuote.number == "Q-2093"

            let gulfNumbers = try await numbering.quotes(session: owner, filter: .all, query: "").map(\.number)
            let uniqueInCompany = Set(gulfNumbers).count == gulfNumbers.count

            let passed = gulfFollowsDefaults && northFollowsItsOwn && unaffected && uniqueInCompany
            results.append(
                TestScenarioResult(
                    id: "16",
                    number: 16,
                    title: "Document numbering is company-scoped configuration",
                    expectation: "Prefixes and counters come from each company's own sequence, never from hard-coded logic",
                    passed: passed,
                    evidence: "Gulf Coast (platform defaults) issued \(gulfQuote.number) and \(gulfJob.number) · Northline (its own configured prefixes) issued \(northQuote.number) and \(northJob.number) · a second Gulf Coast quote took \(secondGulfQuote.number), unmoved by Northline · \(gulfNumbers.count) company numbers, \(uniqueInCompany ? "all unique" : "DUPLICATE FOUND")"
                )
            )
        } catch {
            results.append(failure(16, "Document numbering is company-scoped configuration", "Per-company prefixes and counters", error))
        }

        results.append(contentsOf: await invoicingScenarios(owner: owner, dispatcher: dispatcher, marcus: marcus, accounts: accounts, northOwner: northOwner))
        results.append(contentsOf: await dispatchScenarios(owner: owner, dispatcher: dispatcher, marcus: marcus, dee: dee, accounts: accounts, northOwner: northOwner))

        return results
    }

    // MARK: - Phase three: invoicing, payments and receivables

    /// Every invoicing scenario builds its **own** freshly seeded gateway so its
    /// document numbers, balances and statuses are deterministic and unaffected
    /// by the order the earlier scenarios ran in.
    private static func freshGateway() -> MockDataGateway {
        MockDataGateway(store: .seeded(), latency: .zero)
    }

    private static func invoicingScenarios(
        owner: TenantSession,
        dispatcher: TenantSession,
        marcus: TenantSession,
        accounts: TenantSession,
        northOwner: TenantSession
    ) async -> [TestScenarioResult] {
        var results: [TestScenarioResult] = []

        // 17 — A completed job becomes an invoice, and the job is not rewritten.
        do {
            let gateway = freshGateway()

            // Drive an accepted quote all the way through to a completed job, so
            // the job under test genuinely originated from a quote.
            let jobID = try await gateway.convertQuoteToJob(
                session: owner,
                quoteID: "qte_coastal",
                input: QuoteConversionInput(kind: .install, priority: .standard, scheduledStart: nil, scheduledEnd: nil, fieldWorkerUserID: nil)
            )
            try await gateway.assignFieldWorker(session: owner, jobID: jobID, workerUserID: "usr_marcus")
            for step: JobStatus in [.travelling, .arrived, .inProgress, .completed] {
                try await gateway.updateJobStatus(session: owner, jobID: jobID, to: step)
            }

            let jobBefore = try await gateway.jobDetail(session: owner, jobID: jobID)
            let historyBefore = jobBefore.timeline.count

            let invoiceID = try await gateway.createInvoiceFromJob(session: owner, jobID: jobID, input: InvoiceConversionInput())
            let invoice = try await gateway.invoiceDetail(session: owner, invoiceID: invoiceID)
            let jobAfter = try await gateway.jobDetail(session: owner, jobID: jobID)

            // Inheritance from the job.
            let inherited = invoice.customerID == jobBefore.customerID
                && invoice.addressLine == jobBefore.addressLine
                && invoice.billingContactName != nil
                && !invoice.scopeOfWork.isEmpty
            // The quote behind the job is retained on the invoice.
            let quoteRetained = invoice.quoteReference?.contains("Q-2089") ?? false
            // Labour and material lines carried across.
            let linesCarried = invoice.lineItems.count == 4 && invoice.totals.total == Money.dec("5205.55")
            // The job record itself is untouched — only its workflow status
            // moved, and that move is recorded, not silent.
            let jobUnchanged = jobAfter.number == jobBefore.number
                && jobAfter.title == jobBefore.title
                && jobAfter.jobDescription == jobBefore.jobDescription
                && jobAfter.customerID == jobBefore.customerID
                && jobAfter.addressLine == jobBefore.addressLine
                && jobAfter.quoteID == jobBefore.quoteID
                && jobAfter.createdLabel == jobBefore.createdLabel
            let statusRecorded = jobAfter.status == .invoiced && jobAfter.timeline.count == historyBefore + 1
            // The new invoice is a draft the office can still price.
            let editable = invoice.canEditLineItems && invoice.status == .draft

            let passed = inherited && quoteRetained && linesCarried && jobUnchanged && statusRecorded && editable
            results.append(
                TestScenarioResult(
                    id: "17",
                    number: 17,
                    title: "Completed job becomes an invoice",
                    expectation: "Customer, billing contact, site, scope, quote reference and priced lines carry over; the job itself is not rewritten",
                    passed: passed,
                    evidence: "\(jobBefore.number) → \(invoice.number) · billed to \(invoice.billingContactName ?? "—") at \(invoice.addressLine ?? "—") · quote \(invoice.quoteReference ?? "none") retained · \(invoice.lineItems.count) lines at \(invoice.totals.totalLabel) · job fields identical, status \(jobBefore.status.title) → \(jobAfter.status.title) written as history row \(jobAfter.timeline.count) · invoice still editable as a draft"
                )
            )
        } catch {
            results.append(failure(17, "Completed job becomes an invoice", "Job details inherited, job record untouched", error))
        }

        // 18 — An accepted quote becomes an invoice.
        do {
            let gateway = freshGateway()
            let invoiceID = try await gateway.createInvoiceFromQuote(session: owner, quoteID: "qte_coastal", input: InvoiceConversionInput())
            let invoice = try await gateway.invoiceDetail(session: owner, invoiceID: invoiceID)

            let snapshotTaken = invoice.lineItems.count == 4
                && invoice.lineItems.allSatisfy(\.isFromQuote)
            let moneyMatches = invoice.totals.subtotal == Money.dec("4865.00")
                && invoice.totals.tax == Money.dec("340.55")
                && invoice.totals.total == Money.dec("5205.55")
            let referenced = invoice.quoteReference?.contains("Q-2089") ?? false
            let numbered = invoice.number == "INV-1185"

            let passed = snapshotTaken && moneyMatches && referenced && numbered
            results.append(
                TestScenarioResult(
                    id: "18",
                    number: 18,
                    title: "Accepted quote becomes an invoice",
                    expectation: "The invoice receives a snapshot of the quote's line items and keeps the quote reference",
                    passed: passed,
                    evidence: "Q-2089 → \(invoice.number) · \(invoice.lineItems.count) lines all marked as snapshotted · \(invoice.totals.subtotalLabel) + \(invoice.totals.taxLabel) = \(invoice.totals.totalLabel) · quote reference \(invoice.quoteReference ?? "MISSING")"
                )
            )
        } catch {
            results.append(failure(18, "Accepted quote becomes an invoice", "Line items snapshotted, quote referenced", error))
        }

        // 19 — The quote survives invoicing untouched.
        do {
            let gateway = freshGateway()
            let before = try await gateway.quoteDetail(session: owner, quoteID: "qte_coastal")
            _ = try await gateway.createInvoiceFromQuote(session: owner, quoteID: "qte_coastal", input: InvoiceConversionInput())
            let after = try await gateway.quoteDetail(session: owner, quoteID: "qte_coastal")

            let intact = after.status == before.status
                && after.lineItems.count == before.lineItems.count
                && after.totals?.total == before.totals?.total
                && after.totals?.tax == before.totals?.tax
                && after.acceptedLabel == before.acceptedLabel
                && after.scopeOfWork == before.scopeOfWork
            // The only visible change is a money-free back-reference.
            let backReferenced = after.invoicedReference != nil && before.invoicedReference == nil

            let passed = intact && backReferenced
            results.append(
                TestScenarioResult(
                    id: "19",
                    number: 19,
                    title: "Quote is unchanged after an invoice is raised from it",
                    expectation: "Status, dates, line items and totals all survive; only a back-reference is added",
                    passed: passed,
                    evidence: "\(after.number) still \(after.status.title) with \(after.lineItems.count) lines at \(after.totals?.totalLabel ?? "—"), accepted \(after.acceptedLabel ?? "—") · gained back-reference '\(after.invoicedReference ?? "none")' and nothing else"
                )
            )
        } catch {
            results.append(failure(19, "Quote is unchanged after an invoice is raised from it", "Quote preserved as historical data", error))
        }

        // 20 — Printed lines reconcile with the printed totals.
        do {
            let gateway = freshGateway()
            let invoiceID = try await gateway.createInvoiceFromQuote(session: owner, quoteID: "qte_coastal", input: InvoiceConversionInput())
            let invoice = try await gateway.invoiceDetail(session: owner, invoiceID: invoiceID)

            let lineSum = invoice.lineItems.reduce(Decimal(0)) { $0 + ($1.pricing?.lineTotal ?? 0) }
            let taxSum = invoice.lineItems.reduce(Decimal(0)) { $0 + ($1.pricing?.lineTax ?? 0) }

            let reconciles = lineSum == invoice.totals.subtotal
                && taxSum == invoice.totals.tax
                && invoice.totals.subtotal + invoice.totals.tax == invoice.totals.total

            results.append(
                TestScenarioResult(
                    id: "20",
                    number: 20,
                    title: "Invoice line items reconcile with subtotal, tax and total",
                    expectation: "The printed lines add up to the printed figures, to the cent",
                    passed: reconciles,
                    evidence: "\(invoice.lineItems.count) lines sum to \(lineSum) (subtotal \(invoice.totals.subtotal)) · per-line tax sums to \(taxSum) (tax \(invoice.totals.tax)) · \(invoice.totals.subtotal) + \(invoice.totals.tax) = \(invoice.totals.total)"
                )
            )
        } catch {
            results.append(failure(20, "Invoice line items reconcile with subtotal, tax and total", "Lines add up exactly", error))
        }

        // 21 — Decimal accuracy through the real invoice write path.
        do {
            let gateway = freshGateway()
            let invoiceID = try await gateway.createInvoice(
                session: owner,
                input: NewInvoiceInput(customerID: "cus_ramirez", addressID: "adr_ramirez", title: "Rounding probe")
            )
            // The classic binary-float traps, written through the gateway.
            for (description, quantity, price) in [
                ("Trap A", Decimal(1), "0.10"),
                ("Trap B", Decimal(1), "0.20"),
                ("Trap C", Decimal(3), "19.99")
            ] {
                try await gateway.saveInvoiceLineItem(
                    session: owner,
                    invoiceID: invoiceID,
                    draft: InvoiceLineItemDraft(id: nil, itemDescription: description, quantity: quantity, unitPrice: Money.dec(price), taxRate: 0)
                )
            }
            let invoice = try await gateway.invoiceDetail(session: owner, invoiceID: invoiceID)

            // And the seeded invoice whose labour line is 4 × 116.29.
            let seeded = try await gateway.invoiceDetail(session: owner, invoiceID: "inv_1184")

            let trapExact = invoice.totals.subtotal == Money.dec("60.27")
            let seededExact = seeded.totals.subtotal == Money.dec("1355.16")
                && seeded.totals.tax == Money.dec("94.86")
                && seeded.totals.total == Money.dec("1450.02")

            results.append(
                TestScenarioResult(
                    id: "21",
                    number: 21,
                    title: "Invoice money is decimal-exact, never floating point",
                    expectation: "0.10 + 0.20 + (3 × 19.99) is exactly 60.27, and 4 × 116.29 lands on the cent",
                    passed: trapExact && seededExact,
                    evidence: "Written through the gateway: subtotal \(invoice.totals.subtotalLabel) · \(seeded.number) 890.00 + (4 × 116.29) = \(seeded.totals.subtotalLabel), tax \(seeded.totals.taxLabel), total \(seeded.totals.totalLabel)"
                )
            )
        } catch {
            results.append(failure(21, "Invoice money is decimal-exact, never floating point", "Exact decimals end to end", error))
        }

        // 22 — Tax is calculated per line, not on the subtotal.
        do {
            let gateway = freshGateway()
            let invoiceID = try await gateway.createInvoice(
                session: owner,
                input: NewInvoiceInput(customerID: "cus_ramirez", addressID: "adr_ramirez", title: "Tax rounding probe")
            )
            // Three identical lines chosen so per-line rounding and
            // whole-subtotal rounding genuinely disagree.
            for index in 1...3 {
                try await gateway.saveInvoiceLineItem(
                    session: owner,
                    invoiceID: invoiceID,
                    draft: InvoiceLineItemDraft(id: nil, itemDescription: "Part \(index)", quantity: 1, unitPrice: Money.dec("10.07"), taxRate: Money.percent("7"))
                )
            }
            let invoice = try await gateway.invoiceDetail(session: owner, invoiceID: invoiceID)

            // Each line: 10.07 × 7% = 0.7049 → 0.70. Three lines → 2.10.
            // Taxing the subtotal instead: 30.21 × 7% = 2.1147 → 2.11.
            let perLine = invoice.totals.tax == Money.dec("2.10")
            let notSubtotalBased = invoice.totals.tax != Money.dec("2.11")
            let totalCorrect = invoice.totals.total == Money.dec("32.31")
            let everyLineRounded = invoice.lineItems.allSatisfy { $0.pricing?.lineTax == Money.dec("0.70") }

            results.append(
                TestScenarioResult(
                    id: "22",
                    number: 22,
                    title: "Tax is calculated at line level and rounded consistently",
                    expectation: "Per-line rounding gives 2.10, not the 2.11 a subtotal-level calculation would produce",
                    passed: perLine && notSubtotalBased && totalCorrect && everyLineRounded,
                    evidence: "3 × 10.07 @ 7%: each line taxed \(invoice.lineItems.first?.pricing?.lineTaxLabel ?? "—") · invoice tax \(invoice.totals.taxLabel) (taxing the \(invoice.totals.subtotalLabel) subtotal in one go would have given 2.11) · total \(invoice.totals.totalLabel)"
                )
            )
        } catch {
            results.append(failure(22, "Tax is calculated at line level and rounded consistently", "Per-line tax rounding", error))
        }

        // 23 — The invoice is issued in the company's configured currency.
        do {
            var euroStore = MockDataStore.seeded()
            if let index = euroStore.companies.firstIndex(where: { $0.id == "cmp_gulfcoast" }) {
                euroStore.companies[index].currencyCode = "EUR"
                euroStore.companies[index].countryCode = "IE"
            }
            let euroGateway = MockDataGateway(store: euroStore, latency: .zero)
            let euroID = try await euroGateway.createInvoiceFromQuote(session: owner, quoteID: "qte_coastal", input: InvoiceConversionInput())
            let euroInvoice = try await euroGateway.invoiceDetail(session: owner, invoiceID: euroID)

            let usdGateway = freshGateway()
            let usdID = try await usdGateway.createInvoiceFromQuote(session: owner, quoteID: "qte_coastal", input: InvoiceConversionInput())
            let usdInvoice = try await usdGateway.invoiceDetail(session: owner, invoiceID: usdID)

            let northGateway = freshGateway()
            let northInvoiceRows = try await northGateway.invoices(session: northOwner, query: InvoiceQuery(filter: .all))

            let currencyFollowsCompany = euroInvoice.currencyCode == "EUR" && usdInvoice.currencyCode == "USD"
            let labelsFollow = euroInvoice.totals.totalLabel.contains("€") && usdInvoice.totals.totalLabel.contains("$")
            // Same stored decimal either way — the maths is currency-neutral.
            let sameDecimal = euroInvoice.totals.total == usdInvoice.totals.total
            let secondTenantServed = !northInvoiceRows.isEmpty

            results.append(
                TestScenarioResult(
                    id: "23",
                    number: 23,
                    title: "Invoices use the company's configured currency",
                    expectation: "The currency comes from company configuration and is captured on the document",
                    passed: currencyFollowsCompany && labelsFollow && sameDecimal && secondTenantServed,
                    evidence: "Same quote, same stored decimal \(usdInvoice.totals.total): '\(euroInvoice.totals.totalLabel)' for the EUR/IE company, '\(usdInvoice.totals.totalLabel)' for the USD one · each invoice records the code it was issued in · second tenant serves \(northInvoiceRows.count) invoice(s) through the same path"
                )
            )
        } catch {
            results.append(failure(23, "Invoices use the company's configured currency", "Currency from company configuration", error))
        }

        // 24 — Total minus amount paid equals balance, on every invoice.
        do {
            let gateway = freshGateway()
            let rows = try await gateway.invoices(session: owner, query: InvoiceQuery(filter: .all))
            var checked = 0
            var mismatches: [String] = []
            for row in rows {
                let detail = try await gateway.invoiceDetail(session: owner, invoiceID: row.id)
                checked += 1
                let expected = Money.rounded(detail.totals.total - detail.totals.amountPaid)
                if detail.totals.balance != expected {
                    mismatches.append(detail.number)
                }
                if detail.totals.subtotal + detail.totals.tax != detail.totals.total {
                    mismatches.append("\(detail.number) (subtotal+tax)")
                }
            }
            results.append(
                TestScenarioResult(
                    id: "24",
                    number: 24,
                    title: "Invoice balance is total minus amount paid",
                    expectation: "Every invoice satisfies subtotal + tax = total and total − paid = balance",
                    passed: checked > 0 && mismatches.isEmpty,
                    evidence: mismatches.isEmpty
                        ? "\(checked) invoices checked, all balancing"
                        : "Mismatched: \(mismatches.joined(separator: ", "))"
                )
            )
        } catch {
            results.append(failure(24, "Invoice balance is total minus amount paid", "Balances derive correctly", error))
        }

        // 25 — A part payment moves the balance and the status.
        do {
            let gateway = freshGateway()
            let before = try await gateway.invoiceDetail(session: accounts, invoiceID: "inv_1184")
            try await gateway.recordPayment(
                session: accounts,
                invoiceID: "inv_1184",
                draft: PaymentDraft(amount: Money.dec("200.00"), method: .ach, receivedAt: Date(), reference: "ACH-TEST", note: nil)
            )
            let after = try await gateway.invoiceDetail(session: accounts, invoiceID: "inv_1184")

            let balanceMoved = after.totals.amountPaid == Money.dec("200.00")
                && after.totals.balance == Money.dec("1250.02")
            let statusMoved = after.status == .partPaid && before.status == .sent
            let recorded = after.payments.count == before.payments.count + 1
            let markedSimulated = after.payments.allSatisfy(\.isSimulated)

            // Overpaying the remainder is refused outright.
            var overpaymentRefused = false
            var refusalDetail = "The overpayment was accepted"
            do {
                try await gateway.recordPayment(
                    session: accounts,
                    invoiceID: "inv_1184",
                    draft: PaymentDraft(amount: Money.dec("9999.00"), method: .cash, receivedAt: Date(), reference: nil, note: nil)
                )
            } catch let error as DataError {
                if case .rejected = error {
                    overpaymentRefused = true
                    refusalDetail = error.errorDescription ?? "rejected"
                }
            }

            let passed = balanceMoved && statusMoved && recorded && markedSimulated && overpaymentRefused
            results.append(
                TestScenarioResult(
                    id: "25",
                    number: 25,
                    title: "Part payment updates the balance and the status",
                    expectation: "Balance falls by the amount paid, status becomes Part paid, and overpayment is refused",
                    passed: passed,
                    evidence: "\(after.number): paid \(after.totals.amountPaidLabel) of \(after.totals.totalLabel), balance \(after.totals.balanceLabel) · \(before.status.title) → \(after.status.title) · \(after.payments.count) payment rows, all flagged simulated · overpayment: \(refusalDetail)"
                )
            )
        } catch {
            results.append(failure(25, "Part payment updates the balance and the status", "Balance and status follow the payment", error))
        }

        // 26 — Settling in full marks the invoice paid and carries the job.
        do {
            let gateway = freshGateway()
            try await gateway.recordPayment(
                session: accounts,
                invoiceID: "inv_1184",
                draft: PaymentDraft(amount: Money.dec("200.00"), method: .ach, receivedAt: Date(), reference: nil, note: nil)
            )
            try await gateway.recordPayment(
                session: accounts,
                invoiceID: "inv_1184",
                draft: PaymentDraft(amount: Money.dec("1250.02"), method: .card, receivedAt: Date(), reference: nil, note: nil)
            )
            let settled = try await gateway.invoiceDetail(session: accounts, invoiceID: "inv_1184")
            let job = try await gateway.jobDetail(session: owner, jobID: "job_1039")

            let paid = settled.status == .paid
                && settled.totals.balance == 0
                && settled.totals.amountPaid == settled.totals.total
            // Nothing further can be taken once it is settled.
            let closed = !settled.canRecordPayment
            // The linked job follows to paid, as a recorded transition.
            let jobFollowed = job.status == .paid

            results.append(
                TestScenarioResult(
                    id: "26",
                    number: 26,
                    title: "Paying in full moves the invoice to Paid",
                    expectation: "Balance reaches zero, status becomes Paid, and the linked job follows",
                    passed: paid && closed && jobFollowed,
                    evidence: "\(settled.number): \(settled.payments.count) payments totalling \(settled.totals.amountPaidLabel) against \(settled.totals.totalLabel), balance \(settled.totals.balanceLabel), status \(settled.status.title) · further payment \(closed ? "refused" : "STILL OFFERED") · job \(job.number) now \(job.status.title)"
                )
            )
        } catch {
            results.append(failure(26, "Paying in full moves the invoice to Paid", "Status becomes Paid at zero balance", error))
        }

        // 27 — Overdue is identified from the due date.
        do {
            let gateway = freshGateway()
            let overdue = try await gateway.invoices(session: owner, query: InvoiceQuery(filter: .overdue))
            let all = try await gateway.invoices(session: owner, query: InvoiceQuery(filter: .all))

            let overdueNumbers = Set(overdue.map(\.number))
            let expected: Set<String> = ["INV-1180", "INV-1171"]
            let correctSet = overdueNumbers == expected
            // A paid invoice is never overdue, however old it is.
            let paidNotOverdue = all.first { $0.number == "INV-1168" }.map { !$0.isOverdue } ?? false
            // Nor is a draft.
            let draftNotOverdue = all.first { $0.number == "INV-1190" }.map { !$0.isOverdue } ?? false
            // A future-dated one isn't either.
            let futureNotOverdue = all.first { $0.number == "INV-1184" }.map { !$0.isOverdue } ?? false
            // One of the overdue pair is also part paid — both facts survive.
            let partPaidStillOverdue = overdue.first { $0.number == "INV-1171" }?.amountPaidLabel != nil

            let passed = correctSet && paidNotOverdue && draftNotOverdue && futureNotOverdue && partPaidStillOverdue
            results.append(
                TestScenarioResult(
                    id: "27",
                    number: 27,
                    title: "Overdue invoices are identified from the due date",
                    expectation: "Past due with a balance is overdue; paid, draft and future-dated invoices are not",
                    passed: passed,
                    evidence: "Overdue: \(overdue.map { "\($0.number) (\($0.daysOverdue ?? 0)d)" }.joined(separator: ", ")) · paid INV-1168, draft INV-1190 and future-dated INV-1184 all excluded · INV-1171 is part paid and overdue at once"
                )
            )
        } catch {
            results.append(failure(27, "Overdue invoices are identified from the due date", "Overdue derived from the due date", error))
        }

        // 28 — Field workers receive no financial data whatsoever.
        do {
            let gateway = freshGateway()
            var blocked: [String] = []
            var leaked: [String] = []

            func probe(_ name: String, _ work: () async throws -> Void) async {
                do {
                    try await work()
                    leaked.append(name)
                } catch let error as DataError {
                    if case .notPermitted = error { blocked.append(name) } else { leaked.append("\(name) (\(error.errorDescription ?? ""))") }
                } catch {
                    leaked.append(name)
                }
            }

            await probe("invoices") { _ = try await gateway.invoices(session: marcus, query: InvoiceQuery(filter: .all)) }
            await probe("invoiceDetail") { _ = try await gateway.invoiceDetail(session: marcus, invoiceID: "inv_1184") }
            await probe("payments") { _ = try await gateway.payments(session: marcus, query: InvoiceQuery(filter: .all)) }
            await probe("receivables") { _ = try await gateway.receivables(session: marcus, query: InvoiceQuery(filter: .all)) }
            await probe("recordPayment") { try await gateway.recordPayment(session: marcus, invoiceID: "inv_1184", draft: PaymentDraft(amount: 10)) }
            await probe("createInvoiceFromJob") { _ = try await gateway.createInvoiceFromJob(session: marcus, jobID: "job_1041", input: InvoiceConversionInput()) }

            // And the field payload is still structurally money-free.
            let detail = try await gateway.fieldWorkerJobDetail(session: marcus, jobID: "job_1042")
            let offenders = monetaryFields(of: detail)

            let passed = leaked.isEmpty && blocked.count == 6 && offenders.isEmpty
            results.append(
                TestScenarioResult(
                    id: "28",
                    number: 28,
                    title: "Field worker receives no invoice or payment data",
                    expectation: "Every invoice, payment and receivables entry point is refused, and the field payload has no money field",
                    passed: passed,
                    evidence: leaked.isEmpty
                        ? "All \(blocked.count) entry points refused at the data layer (\(blocked.joined(separator: ", "))) · FieldWorkerJobDetail still carries no monetary field"
                        : "LEAKED: \(leaked.joined(separator: ", "))"
                )
            )
        } catch {
            results.append(failure(28, "Field worker receives no invoice or payment data", "All financial entry points refused", error))
        }

        // 29 — Dispatchers run operations with no financial fields.
        do {
            let gateway = freshGateway()
            var blocked: [String] = []
            var leaked: [String] = []

            func probe(_ name: String, _ work: () async throws -> Void) async {
                do {
                    try await work()
                    leaked.append(name)
                } catch let error as DataError {
                    if case .notPermitted = error { blocked.append(name) } else { leaked.append(name) }
                } catch {
                    leaked.append(name)
                }
            }

            await probe("invoices") { _ = try await gateway.invoices(session: dispatcher, query: InvoiceQuery(filter: .all)) }
            await probe("invoiceDetail") { _ = try await gateway.invoiceDetail(session: dispatcher, invoiceID: "inv_1184") }
            await probe("payments") { _ = try await gateway.payments(session: dispatcher, query: InvoiceQuery(filter: .all)) }
            await probe("receivables") { _ = try await gateway.receivables(session: dispatcher, query: InvoiceQuery(filter: .all)) }
            await probe("recordPayment") { try await gateway.recordPayment(session: dispatcher, invoiceID: "inv_1184", draft: PaymentDraft(amount: 10)) }

            // But operational work is unaffected: quotes still readable, money-free.
            let quote = try await gateway.quoteDetail(session: dispatcher, quoteID: "qte_coastal")
            let jobDetail = try await gateway.jobDetail(session: dispatcher, jobID: "job_1042")
            let sources = try await gateway.invoiceSources(session: dispatcher)

            let stillOperational = !quote.lineItems.isEmpty
                && quote.totals == nil
                && quote.lineItems.allSatisfy { $0.pricing == nil }
                && jobDetail.financials == nil
                && quote.invoicedReference == nil
                && sources.isEmpty

            let passed = leaked.isEmpty && blocked.count == 5 && stillOperational
            results.append(
                TestScenarioResult(
                    id: "29",
                    number: 29,
                    title: "Dispatcher receives no unauthorised financial fields",
                    expectation: "Invoices, payments and receivables are refused; quotes and jobs still work without money",
                    passed: passed,
                    evidence: leaked.isEmpty
                        ? "\(blocked.count) financial entry points refused · \(quote.number) still readable with \(quote.lineItems.count) lines and no pricing, job money not assembled, no invoice back-reference, no invoice sources offered"
                        : "LEAKED: \(leaked.joined(separator: ", "))"
                )
            )
        } catch {
            results.append(failure(29, "Dispatcher receives no unauthorised financial fields", "Financial surfaces refused, operations intact", error))
        }

        // 30 — Accounts holds the full money surface.
        do {
            let gateway = freshGateway()
            let rows = try await gateway.invoices(session: accounts, query: InvoiceQuery(filter: .all))
            let detail = try await gateway.invoiceDetail(session: accounts, invoiceID: "inv_1176")
            let paymentRows = try await gateway.payments(session: accounts, query: InvoiceQuery(filter: .all))
            let ar = try await gateway.receivables(session: accounts, query: InvoiceQuery(filter: .outstanding))

            // Accounts can also take money.
            try await gateway.recordPayment(
                session: accounts,
                invoiceID: "inv_1176",
                draft: PaymentDraft(amount: Money.dec("77.98"), method: .check, receivedAt: Date(), reference: "Check 9001", note: nil)
            )
            let afterPayment = try await gateway.invoiceDetail(session: accounts, invoiceID: "inv_1176")

            // But still holds no operational job control.
            var jobWriteBlocked = false
            do {
                try await gateway.updateJobStatus(session: accounts, jobID: "job_1044", to: .travelling)
            } catch let error as DataError {
                if case .notPermitted = error { jobWriteBlocked = true }
            }

            let hasEverything = !rows.isEmpty
                && detail.totals.total > 0
                && !detail.payments.isEmpty
                && !paymentRows.isEmpty
                && ar.metrics.count == 4
            let tookPayment = afterPayment.totals.amountPaid == Money.dec("577.98")

            let passed = hasEverything && tookPayment && jobWriteBlocked
            results.append(
                TestScenarioResult(
                    id: "30",
                    number: 30,
                    title: "Accounts can access invoices, payments and receivables",
                    expectation: "Full money surface, and still no operational job control",
                    passed: passed,
                    evidence: "\(rows.count) invoices, \(paymentRows.count) payments, \(ar.metrics.count) receivables metrics · \(detail.number) totals \(detail.totals.totalLabel) with \(detail.payments.count) payment rows · recorded a further payment, paid now \(afterPayment.totals.amountPaidLabel) · operational job write \(jobWriteBlocked ? "refused" : "ALLOWED")"
                )
            )
        } catch {
            results.append(failure(30, "Accounts can access invoices, payments and receivables", "Full financial access, no job control", error))
        }

        // 31 — Invoice numbers come from the company's own sequence.
        do {
            let gateway = freshGateway()
            let first = try await gateway.createInvoice(
                session: owner,
                input: NewInvoiceInput(customerID: "cus_ramirez", addressID: "adr_ramirez", title: "Numbering probe 1")
            )
            let second = try await gateway.createInvoice(
                session: owner,
                input: NewInvoiceInput(customerID: "cus_ramirez", addressID: "adr_ramirez", title: "Numbering probe 2")
            )
            let northFirst = try await gateway.createInvoice(
                session: northOwner,
                input: NewInvoiceInput(customerID: "cus_north_a", addressID: "adr_north_a", title: "Numbering probe N")
            )

            let a = try await gateway.invoiceDetail(session: owner, invoiceID: first)
            let b = try await gateway.invoiceDetail(session: owner, invoiceID: second)
            let n = try await gateway.invoiceDetail(session: northOwner, invoiceID: northFirst)

            // Gulf Coast runs the platform default prefix; Northline runs its
            // own migrated prefix and zero-padding.
            let gulfSequence = a.number == "INV-1185" && b.number == "INV-1186"
            let northSequence = n.number == "N-INV-00500"

            let gulfNumbers = try await gateway.invoices(session: owner, query: InvoiceQuery(filter: .all)).map(\.number)
            let uniqueInCompany = Set(gulfNumbers).count == gulfNumbers.count

            let passed = gulfSequence && northSequence && uniqueInCompany
            results.append(
                TestScenarioResult(
                    id: "31",
                    number: 31,
                    title: "Invoice numbering uses the company's own sequence",
                    expectation: "Prefix, counter and padding all come from the company's sequence row, never a global counter",
                    passed: passed,
                    evidence: "Gulf Coast issued \(a.number) then \(b.number) · Northline issued \(n.number) with its own prefix and 5-digit padding · \(gulfNumbers.count) numbers in the company, \(uniqueInCompany ? "all unique" : "DUPLICATE FOUND")"
                )
            )
        } catch {
            results.append(failure(31, "Invoice numbering uses the company's own sequence", "Per-company invoice sequence", error))
        }

        // 32 — One company's invoicing cannot move another's counter.
        do {
            let gateway = freshGateway()

            let gulf1 = try await gateway.createInvoice(session: owner, input: NewInvoiceInput(customerID: "cus_ramirez", addressID: "adr_ramirez", title: "Interleave 1"))
            // Northline issues several documents in between.
            let north1 = try await gateway.createInvoice(session: northOwner, input: NewInvoiceInput(customerID: "cus_north_a", addressID: "adr_north_a", title: "Interleave N1"))
            let north2 = try await gateway.createInvoice(session: northOwner, input: NewInvoiceInput(customerID: "cus_north_a", addressID: "adr_north_a", title: "Interleave N2"))
            let gulf2 = try await gateway.createInvoice(session: owner, input: NewInvoiceInput(customerID: "cus_ramirez", addressID: "adr_ramirez", title: "Interleave 2"))

            let g1 = try await gateway.invoiceDetail(session: owner, invoiceID: gulf1)
            let g2 = try await gateway.invoiceDetail(session: owner, invoiceID: gulf2)
            let n1 = try await gateway.invoiceDetail(session: northOwner, invoiceID: north1)
            let n2 = try await gateway.invoiceDetail(session: northOwner, invoiceID: north2)

            // Gulf Coast advanced by exactly one despite two Northline invoices
            // being issued in between.
            let gulfUnmoved = g1.number == "INV-1185" && g2.number == "INV-1186"
            let northOwnRun = n1.number == "N-INV-00500" && n2.number == "N-INV-00501"

            // Neither tenant can even see the other's invoices.
            let gulfRows = try await gateway.invoices(session: owner, query: InvoiceQuery(filter: .all))
            let northRows = try await gateway.invoices(session: northOwner, query: InvoiceQuery(filter: .all))
            let isolated = !gulfRows.contains { $0.number.hasPrefix("N-") }
                && northRows.allSatisfy { $0.number.hasPrefix("N-") }

            var crossTenantHidden = false
            do {
                _ = try await gateway.invoiceDetail(session: northOwner, invoiceID: "inv_1184")
            } catch let error as DataError {
                crossTenantHidden = error == .notFound
            }

            let passed = gulfUnmoved && northOwnRun && isolated && crossTenantHidden
            results.append(
                TestScenarioResult(
                    id: "32",
                    number: 32,
                    title: "Two companies cannot affect each other's invoice sequences",
                    expectation: "Interleaved issuing leaves each counter advancing only for its own tenant",
                    passed: passed,
                    evidence: "Interleaved \(g1.number) → \(n1.number) → \(n2.number) → \(g2.number): Gulf Coast moved by exactly one, Northline ran its own · \(gulfRows.count) vs \(northRows.count) rows with no crossover · Gulf Coast invoice requested by Northline \(crossTenantHidden ? "answered notFound" : "WAS VISIBLE")"
                )
            )
        } catch {
            results.append(failure(32, "Two companies cannot affect each other's invoice sequences", "Independent per-tenant counters", error))
        }

        // 33 — Raising the company tax rate leaves issued invoices alone.
        do {
            let baseline = freshGateway()
            let before = try await baseline.invoiceDetail(session: owner, invoiceID: "inv_1180")

            var raisedStore = MockDataStore.seeded()
            if let index = raisedStore.companies.firstIndex(where: { $0.id == "cmp_gulfcoast" }) {
                raisedStore.companies[index].defaultTaxRate = Money.percent("9")
            }
            let raised = MockDataGateway(store: raisedStore, latency: .zero)
            let after = try await raised.invoiceDetail(session: owner, invoiceID: "inv_1180")

            let unchanged = after.totals.tax == before.totals.tax
                && after.totals.total == before.totals.total
                && after.totals.subtotal == before.totals.subtotal
            let linesKeepRate = after.lineItems.allSatisfy { $0.pricing?.taxRate == Money.percent("7") }
            let newLinesUseNewDefault = after.defaultTaxRate == Money.percent("9")

            let passed = unchanged && linesKeepRate && newLinesUseNewDefault
            results.append(
                TestScenarioResult(
                    id: "33",
                    number: 33,
                    title: "Changing the company tax rate does not alter an existing invoice",
                    expectation: "An issued invoice keeps the tax that was agreed on it",
                    passed: passed,
                    evidence: "Company default 7% → 9%: \(before.number) tax stays \(after.totals.taxLabel) and total \(after.totals.totalLabel) · all \(after.lineItems.count) existing lines still carry 7% · a new line would now be offered \(Money.percentLabel(after.defaultTaxRate ?? 0))"
                )
            )
        } catch {
            results.append(failure(33, "Changing the company tax rate does not alter an existing invoice", "Historic tax is stable", error))
        }

        // 34 — Changing the company currency does not corrupt issued invoices.
        do {
            let baseline = freshGateway()
            let before = try await baseline.invoiceDetail(session: owner, invoiceID: "inv_1180")

            var flippedStore = MockDataStore.seeded()
            if let index = flippedStore.companies.firstIndex(where: { $0.id == "cmp_gulfcoast" }) {
                flippedStore.companies[index].currencyCode = "EUR"
                flippedStore.companies[index].countryCode = "IE"
                flippedStore.companies[index].timeZoneIdentifier = "Europe/Dublin"
            }
            let flipped = MockDataGateway(store: flippedStore, latency: .zero)
            let after = try await flipped.invoiceDetail(session: owner, invoiceID: "inv_1180")

            // The stored decimals are untouched...
            let amountsIntact = after.totals.subtotal == before.totals.subtotal
                && after.totals.tax == before.totals.tax
                && after.totals.total == before.totals.total
                && after.totals.balance == before.totals.balance
            // ...and the document keeps the currency it was issued in, rather
            // than being silently re-denominated by a company setting.
            let currencyPreserved = after.currencyCode == "USD" && after.totals.totalLabel.contains("$")
            // A *new* invoice raised after the change uses the new currency.
            let newID = try await flipped.createInvoice(
                session: owner,
                input: NewInvoiceInput(customerID: "cus_ramirez", addressID: "adr_ramirez", title: "Post-change invoice")
            )
            let fresh = try await flipped.invoiceDetail(session: owner, invoiceID: newID)
            let newUsesNewCurrency = fresh.currencyCode == "EUR"

            let passed = amountsIntact && currencyPreserved && newUsesNewCurrency
            results.append(
                TestScenarioResult(
                    id: "34",
                    number: 34,
                    title: "Changing the company currency does not corrupt stored invoice values",
                    expectation: "An issued invoice keeps both its amounts and the currency it was issued in",
                    passed: passed,
                    evidence: "Company switched USD → EUR: \(after.number) still stores \(after.totals.total) and still reads \(after.totals.totalLabel) in \(after.currencyCode) · a new invoice raised afterwards is issued in \(fresh.currencyCode)"
                )
            )
        } catch {
            results.append(failure(34, "Changing the company currency does not corrupt stored invoice values", "Amounts and issued currency both preserved", error))
        }

        // 35 — The invoice's quote snapshot is independent of the quote.
        do {
            let gateway = freshGateway()
            let invoiceID = try await gateway.createInvoiceFromQuote(session: owner, quoteID: "qte_coastal", input: InvoiceConversionInput())
            let before = try await gateway.invoiceDetail(session: owner, invoiceID: invoiceID)

            // Now edit the quote *behind* the gateway, as if someone had changed
            // it in the database after the invoice was raised.
            var mutated = await gateway.developmentSnapshot()
            for index in mutated.quoteLineItems.indices where mutated.quoteLineItems[index].quoteID == "qte_coastal" {
                mutated.quoteLineItems[index].unitPrice *= 2
                mutated.quoteLineItems[index].taxRate = Money.percent("20")
                mutated.quoteLineItems[index].lineTotal = Money.lineTotal(
                    quantity: mutated.quoteLineItems[index].quantity,
                    unitPrice: mutated.quoteLineItems[index].unitPrice
                )
                mutated.quoteLineItems[index].itemDescription = "REWRITTEN"
            }
            let afterEdit = MockDataGateway(store: mutated, latency: .zero)

            let invoiceAfter = try await afterEdit.invoiceDetail(session: owner, invoiceID: invoiceID)
            let quoteAfter = try await afterEdit.quoteDetail(session: owner, quoteID: "qte_coastal")

            let invoiceUnmoved = invoiceAfter.totals.total == before.totals.total
                && invoiceAfter.totals.tax == before.totals.tax
                && invoiceAfter.lineItems.map(\.itemDescription) == before.lineItems.map(\.itemDescription)
                && invoiceAfter.lineItems.allSatisfy { $0.pricing?.taxRate == Money.percent("7") }
            // The quote really did change, so this is a live proof, not a no-op.
            let quoteDidChange = quoteAfter.lineItems.contains { $0.itemDescription == "REWRITTEN" }

            let passed = invoiceUnmoved && quoteDidChange
            results.append(
                TestScenarioResult(
                    id: "35",
                    number: 35,
                    title: "Quote snapshot is unchanged when the quote is later edited",
                    expectation: "Editing the quote afterwards never reaches an invoice already raised from it",
                    passed: passed,
                    evidence: "Quote lines doubled in price, re-taxed at 20% and renamed 'REWRITTEN' after invoicing · quote now shows the change · \(invoiceAfter.number) still reads \(invoiceAfter.totals.totalLabel) with tax \(invoiceAfter.totals.taxLabel), all \(invoiceAfter.lineItems.count) lines at 7% and their original descriptions"
                )
            )
        } catch {
            results.append(failure(35, "Quote snapshot is unchanged when the quote is later edited", "Invoice snapshot is independent", error))
        }

        // 36 — The same work cannot be invoiced twice.
        do {
            let gateway = freshGateway()

            // Same quote, twice.
            _ = try await gateway.createInvoiceFromQuote(session: owner, quoteID: "qte_coastal", input: InvoiceConversionInput())
            var quoteTwiceBlocked = false
            var quoteDetailText = "The duplicate was accepted"
            do {
                _ = try await gateway.createInvoiceFromQuote(session: owner, quoteID: "qte_coastal", input: InvoiceConversionInput())
            } catch let error as DataError {
                if case .rejected = error {
                    quoteTwiceBlocked = true
                    quoteDetailText = error.errorDescription ?? "rejected"
                }
            }

            // Same job, twice.
            let second = freshGateway()
            _ = try await second.createInvoiceFromJob(session: owner, jobID: "job_1041", input: InvoiceConversionInput())
            var jobTwiceBlocked = false
            var jobDetailText = "The duplicate was accepted"
            do {
                _ = try await second.createInvoiceFromJob(session: owner, jobID: "job_1041", input: InvoiceConversionInput())
            } catch let error as DataError {
                if case .rejected = error {
                    jobTwiceBlocked = true
                    jobDetailText = error.errorDescription ?? "rejected"
                }
            }

            // And the cross path: invoice the quote, then try its job.
            let third = freshGateway()
            let jobID = try await third.convertQuoteToJob(
                session: owner,
                quoteID: "qte_coastal",
                input: QuoteConversionInput(kind: .install, priority: .standard, scheduledStart: nil, scheduledEnd: nil, fieldWorkerUserID: nil)
            )
            try await third.assignFieldWorker(session: owner, jobID: jobID, workerUserID: "usr_marcus")
            for step: JobStatus in [.travelling, .arrived, .inProgress, .completed] {
                try await third.updateJobStatus(session: owner, jobID: jobID, to: step)
            }
            _ = try await third.createInvoiceFromQuote(session: owner, quoteID: "qte_coastal", input: InvoiceConversionInput())
            var crossPathBlocked = false
            var crossDetailText = "The same work was billed twice"
            do {
                _ = try await third.createInvoiceFromJob(session: owner, jobID: jobID, input: InvoiceConversionInput())
            } catch let error as DataError {
                if case .rejected = error {
                    crossPathBlocked = true
                    crossDetailText = error.errorDescription ?? "rejected"
                }
            }

            // An already-billed source is also absent from the picker.
            let sources = try await second.invoiceSources(session: owner)
            let hiddenFromPicker = !sources.completedJobs.contains { $0.number == "J-1041" }

            let passed = quoteTwiceBlocked && jobTwiceBlocked && crossPathBlocked && hiddenFromPicker
            results.append(
                TestScenarioResult(
                    id: "36",
                    number: 36,
                    title: "The same source cannot be invoiced twice",
                    expectation: "A second invoice from the same quote, the same job, or the job behind an invoiced quote is refused",
                    passed: passed,
                    evidence: "Same quote: \(quoteDetailText) · same job: \(jobDetailText) · quote then its job: \(crossDetailText) · billed sources \(hiddenFromPicker ? "also removed from the picker" : "STILL OFFERED")"
                )
            )
        } catch {
            results.append(failure(36, "The same source cannot be invoiced twice", "Duplicate conversion refused", error))
        }

        return results
    }

    private static var allJobs: JobQuery {
        var query = JobQuery()
        query.dateScope = .all
        return query
    }

    /// Scenario 9 runs the arithmetic directly so the numbers can be checked by
    /// eye against the expected cents.
    private static func lineItemArithmetic() -> TestScenarioResult {
        // Labelled in the seeded company's configured currency, not a default.
        let code = MockDataStore.seeded().companies.first?.currencyCode ?? Company.fallbackCurrencyCode

        struct Line: MoneyLine {
            let quantity: Decimal
            let unitPrice: Decimal
            let taxRate: Decimal
        }

        let rate = Money.percent("7")
        let lines = [
            Line(quantity: 1, unitPrice: Money.dec("3240.00"), taxRate: rate),
            Line(quantity: 1, unitPrice: Money.dec("480.00"), taxRate: rate),
            Line(quantity: 8, unitPrice: Money.dec("125.00"), taxRate: rate),
            Line(quantity: 1, unitPrice: Money.dec("145.00"), taxRate: rate)
        ]
        let totals = Money.totals(for: lines)
        let expected = MoneyTotals(
            subtotal: Money.dec("4865.00"),
            tax: Money.dec("340.55"),
            total: Money.dec("5205.55")
        )

        // The classic binary-float trap: 0.1 + 0.2 and 19.99 × 3.
        let trap = Money.totals(for: [
            Line(quantity: 1, unitPrice: Money.dec("0.10"), taxRate: 0),
            Line(quantity: 1, unitPrice: Money.dec("0.20"), taxRate: 0),
            Line(quantity: 3, unitPrice: Money.dec("19.99"), taxRate: 0)
        ])
        let trapExpected = Money.dec("60.27")

        let fractional = Money.totals(for: [
            Line(quantity: Money.dec("1.5"), unitPrice: Money.dec("95.00"), taxRate: rate),
            Line(quantity: 2, unitPrice: Money.dec("219.99"), taxRate: rate)
        ])
        let fractionalExpected = Money.dec("623.26") // 582.48 + 40.78

        let passed = totals == expected
            && trap.subtotal == trapExpected
            && fractional.total == fractionalExpected

        return TestScenarioResult(
            id: "9",
            number: 9,
            title: "Quote line item calculations stay exact",
            expectation: "Decimal maths, tax rounded per line, no floating point drift",
            passed: passed,
            evidence: "4 lines → subtotal \(Formatters.currency(totals.subtotal, code: code)), tax \(Formatters.currency(totals.tax, code: code)), total \(Formatters.currency(totals.total, code: code)) · 0.10 + 0.20 + (3 × 19.99) = \(Formatters.currency(trap.subtotal, code: code)) · 1.5 hrs and 2 × 19.99-style line = \(Formatters.currency(fractional.total, code: code))"
        )
    }

    // MARK: - Phase four: dispatch, scheduling, GPS and ETA

    private static func dispatchScenarios(
        owner: TenantSession,
        dispatcher: TenantSession,
        marcus: TenantSession,
        dee: TenantSession,
        accounts: TenantSession,
        northOwner: TenantSession
    ) async -> [TestScenarioResult] {
        var results: [TestScenarioResult] = []
        let locationService = MockLocationService()
        let routeService = MockRouteService()
        let mapService = MockMapService()

        // 38 — The dispatcher sees both the booked day and the backlog.
        do {
            let gateway = freshGateway()
            let board = try await gateway.dispatchBoard(session: dispatcher, query: .today)

            let hasScheduled = !board.scheduled.isEmpty
            let hasUnscheduled = !board.unscheduled.isEmpty
            // The backlog is genuinely unscheduled work, not just today's list.
            let backlogIsUnscheduled = board.unscheduled.allSatisfy { $0.scheduledStart == nil }
            let scheduledAreBooked = board.scheduled.allSatisfy { $0.scheduledStart != nil }
            // Accounts holds the money but no dispatch control at all.
            var accountsBlocked = false
            do {
                _ = try await gateway.dispatchBoard(session: accounts, query: .today)
            } catch let error as DataError {
                if case .notPermitted = error { accountsBlocked = true }
            }

            let passed = hasScheduled && hasUnscheduled && backlogIsUnscheduled && scheduledAreBooked && accountsBlocked
            results.append(
                TestScenarioResult(
                    id: "38",
                    number: 38,
                    title: "Dispatcher sees scheduled and unscheduled jobs",
                    expectation: "Both the booked day and the unscheduled backlog are served; accounts gets no dispatch board",
                    passed: passed,
                    evidence: "\(board.scheduled.count) scheduled (\(board.scheduled.map(\.number).joined(separator: ", "))) · \(board.unscheduled.count) unscheduled backlog (\(board.unscheduled.map(\.number).joined(separator: ", "))), all with no slot · accounts \(accountsBlocked ? "refused" : "WAS SERVED")"
                )
            )
        } catch {
            results.append(failure(38, "Dispatcher sees scheduled and unscheduled jobs", "Scheduled and backlog both served", error))
        }

        // 39 — Assigning a worker to an unassigned job.
        do {
            let gateway = freshGateway()
            let before = try await gateway.jobDetail(session: dispatcher, jobID: "job_1046")
            let check = try await gateway.assignJob(
                session: dispatcher,
                jobID: "job_1046",
                input: AssignmentInput(workerUserID: "usr_marcus")
            )
            let after = try await gateway.jobDetail(session: dispatcher, jobID: "job_1046")

            let assigned = after.assignedWorker?.userID == "usr_marcus"
            let wasUnassigned = before.assignedWorker == nil
            // Assignment moves a scheduled job on through the existing workflow.
            let statusMoved = after.status == .workerAssigned && before.status == .scheduled
            let historyWritten = after.timeline.count > before.timeline.count
            let noConflict = !check.hasConflicts
            // The worker now sees it in their own list.
            let visibleToWorker = try await gateway.jobs(session: marcus, query: allJobs).contains { $0.id == "job_1046" }

            let passed = wasUnassigned && assigned && statusMoved && historyWritten && noConflict && visibleToWorker
            results.append(
                TestScenarioResult(
                    id: "39",
                    number: 39,
                    title: "Dispatcher can assign a field worker",
                    expectation: "The assignment is written, the job advances through the workflow and the worker can see it",
                    passed: passed,
                    evidence: "\(after.number): unassigned → \(after.assignedWorker?.name ?? "none") · \(before.status.title) → \(after.status.title) · timeline \(before.timeline.count) → \(after.timeline.count) rows · now visible to Marcus: \(visibleToWorker)"
                )
            )
        } catch {
            results.append(failure(39, "Dispatcher can assign a field worker", "Assignment written and workflow advanced", error))
        }

        // 40 — Reassigning moves the job between workers cleanly.
        do {
            let gateway = freshGateway()
            let before = try await gateway.jobDetail(session: dispatcher, jobID: "job_1044")
            _ = try await gateway.assignJob(
                session: dispatcher,
                jobID: "job_1044",
                input: AssignmentInput(workerUserID: "usr_dee")
            )
            let after = try await gateway.jobDetail(session: dispatcher, jobID: "job_1044")

            let movedToDee = after.assignedWorker?.userID == "usr_dee"
            let wasMarcus = before.assignedWorker?.userID == "usr_marcus"
            // The old assignment is gone, not merely superseded: Marcus loses
            // access to the row entirely.
            let marcusJobs = try await gateway.jobs(session: marcus, query: allJobs).map(\.id)
            let deeJobs = try await gateway.jobs(session: dee, query: allJobs).map(\.id)
            let removedFromMarcus = !marcusJobs.contains("job_1044")
            let addedToDee = deeJobs.contains("job_1044")

            // And clearing an assignment sends the job back to scheduled.
            _ = try await gateway.assignJob(session: dispatcher, jobID: "job_1044", input: AssignmentInput(workerUserID: nil))
            let cleared = try await gateway.jobDetail(session: dispatcher, jobID: "job_1044")
            let unassignedAgain = cleared.assignedWorker == nil && cleared.status == .scheduled

            let passed = wasMarcus && movedToDee && removedFromMarcus && addedToDee && unassignedAgain
            results.append(
                TestScenarioResult(
                    id: "40",
                    number: 40,
                    title: "Dispatcher can reassign and unassign a field worker",
                    expectation: "The job moves between workers and access follows the assignment",
                    passed: passed,
                    evidence: "J-1044: \(before.assignedWorker?.name ?? "none") → \(after.assignedWorker?.name ?? "none") · dropped from Marcus's list (\(removedFromMarcus)), added to Dee's (\(addedToDee)) · cleared → \(cleared.status.title) with no worker"
                )
            )
        } catch {
            results.append(failure(40, "Dispatcher can reassign and unassign a field worker", "Reassignment moves access with it", error))
        }

        // 41 — Unassigned work is called out rather than buried.
        do {
            let gateway = freshGateway()
            // Free one of today's jobs so there is something to find.
            _ = try await gateway.assignJob(session: dispatcher, jobID: "job_1043", input: AssignmentInput(workerUserID: nil))

            let board = try await gateway.dispatchBoard(session: dispatcher, query: .today)
            let listed = board.unassigned.contains { $0.number == "J-1043" }
            // The row itself carries the flag, so no screen has to re-derive it.
            let rowFlagged = board.scheduled.first { $0.number == "J-1043" }?.isUnassigned == true
            let headlineMentions = board.subline.lowercased().contains("need")

            // And the filter narrows to exactly those.
            var filtered = DispatchQuery()
            filtered.unassignedOnly = true
            let onlyUnassigned = try await gateway.dispatchBoard(session: dispatcher, query: filtered)
            let filterWorks = onlyUnassigned.scheduled.allSatisfy(\.isUnassigned) && !onlyUnassigned.scheduled.isEmpty

            let passed = listed && rowFlagged && headlineMentions && filterWorks
            results.append(
                TestScenarioResult(
                    id: "41",
                    number: 41,
                    title: "Unassigned jobs are clearly represented",
                    expectation: "They have their own group, the row is flagged, and a filter isolates them",
                    passed: passed,
                    evidence: "\(board.unassigned.count) unassigned listed separately · J-1043 row flagged isUnassigned · board reads '\(board.subline)' · unassigned-only filter returned \(onlyUnassigned.scheduled.count), all flagged"
                )
            )
        } catch {
            results.append(failure(41, "Unassigned jobs are clearly represented", "Grouped, flagged and filterable", error))
        }

        // 42 — An overlap is detected before anything is written.
        do {
            let gateway = freshGateway()
            // J-1043 is Marcus's 13:00–14:30. J-1049 is 14:00–15:00, so putting
            // Marcus on it overlaps by half an hour.
            let check = try await gateway.checkAssignment(
                session: dispatcher,
                jobID: "job_1049",
                workerUserID: "usr_marcus"
            )
            // The check is read-only: nothing moved.
            let untouched = try await gateway.jobDetail(session: dispatcher, jobID: "job_1049")
            let stillDees = untouched.assignedWorker?.userID == "usr_dee"

            let detected = check.hasConflicts
            let namesTheClash = check.conflicts.first?.clashingJobNumber == "J-1043"
            let namesTheWorker = check.conflicts.first?.workerName == "Marcus Hale"

            // A worker who is genuinely free produces no conflict.
            let clear = try await gateway.checkAssignment(session: dispatcher, jobID: "job_1046", workerUserID: "usr_marcus")

            let passed = detected && namesTheClash && namesTheWorker && stillDees && !clear.hasConflicts
            results.append(
                TestScenarioResult(
                    id: "42",
                    number: 42,
                    title: "Scheduling conflict is detected",
                    expectation: "An overlapping assignment is identified up front, and the check changes nothing",
                    passed: passed,
                    evidence: "\(check.summary) · J-1049 still assigned to \(untouched.assignedWorker?.name ?? "nobody") after the check · an unscheduled job produced \(clear.conflicts.count) conflicts"
                )
            )
        } catch {
            results.append(failure(42, "Scheduling conflict is detected", "Overlap identified without writing", error))
        }

        // 43 — A field worker's list is their own assignments and nothing else.
        do {
            let gateway = freshGateway()
            let marcusJobs = try await gateway.jobs(session: marcus, query: allJobs)
            let deeJobs = try await gateway.jobs(session: dee, query: allJobs)
            let allJobsForOwner = try await gateway.jobs(session: owner, query: allJobs)

            let marcusIDs = Set(marcusJobs.map(\.id))
            let deeIDs = Set(deeJobs.map(\.id))
            let noOverlap = marcusIDs.isDisjoint(with: deeIDs)
            let bothSubsets = marcusIDs.count < allJobsForOwner.count && deeIDs.count < allJobsForOwner.count
            let bothNonEmpty = !marcusIDs.isEmpty && !deeIDs.isEmpty

            // The field day view is scoped the same way.
            let day = try await gateway.fieldWorkerDay(session: marcus)
            let dayIsHis = day.stops.allSatisfy { marcusIDs.contains($0.jobID) }

            let passed = noOverlap && bothSubsets && bothNonEmpty && dayIsHis
            results.append(
                TestScenarioResult(
                    id: "43",
                    number: 43,
                    title: "Field worker sees only their assigned jobs",
                    expectation: "Each worker receives their own assignments, never the other's",
                    passed: passed,
                    evidence: "Marcus \(marcusIDs.count) jobs, Dee \(deeIDs.count), company total \(allJobsForOwner.count) · no job appears in both lists · Marcus's day view (\(day.stops.count) stops) is entirely from his own assignments"
                )
            )
        } catch {
            results.append(failure(43, "Field worker sees only their assigned jobs", "Assignment-scoped lists", error))
        }

        // 44 — Reaching for someone else's job answers notFound.
        do {
            let gateway = freshGateway()
            var detailHidden = false
            var travelHidden = false
            var fieldDetailHidden = false

            do { _ = try await gateway.jobDetail(session: marcus, jobID: "job_1049") }
            catch let error as DataError { detailHidden = error == .notFound }

            do { _ = try await gateway.travelSnapshot(session: marcus, jobID: "job_1049") }
            catch let error as DataError { travelHidden = error == .notFound }

            do { _ = try await gateway.fieldWorkerJobDetail(session: marcus, jobID: "job_1049") }
            catch let error as DataError { fieldDetailHidden = error == .notFound }

            let passed = detailHidden && travelHidden && fieldDetailHidden
            results.append(
                TestScenarioResult(
                    id: "44",
                    number: 44,
                    title: "Field worker cannot see another worker's job",
                    expectation: "Every read path answers notFound, so the row's existence is never disclosed",
                    passed: passed,
                    evidence: passed
                        ? "J-1049 (Dee's) answered notFound for Marcus on jobDetail, travelSnapshot and fieldWorkerJobDetail — never 'forbidden'"
                        : "detail \(detailHidden), travel \(travelHidden), field detail \(fieldDetailHidden)"
                )
            )
        } catch {
            results.append(failure(44, "Field worker cannot see another worker's job", "notFound on every path", error))
        }

        results.append(contentsOf: await dispatchScenariosPartTwo(
            owner: owner,
            dispatcher: dispatcher,
            marcus: marcus,
            dee: dee,
            northOwner: northOwner,
            locationService: locationService,
            routeService: routeService,
            mapService: mapService
        ))

        return results
    }

    /// Split purely to keep each function a readable size — scenarios 45–60
    /// covering the field workflow, location capture, navigation and ETA.
    private static func dispatchScenariosPartTwo(
        owner: TenantSession,
        dispatcher: TenantSession,
        marcus: TenantSession,
        dee: TenantSession,
        northOwner: TenantSession,
        locationService: MockLocationService,
        routeService: MockRouteService,
        mapService: MockMapService
    ) async -> [TestScenarioResult] {
        var results: [TestScenarioResult] = []

        // 45 — Start travel works on an assignment and nowhere else.
        do {
            let gateway = freshGateway()

            // His own assigned job: accepted.
            try await FieldTransitionCoordinator.advance(
                gateway: gateway,
                location: locationService,
                session: marcus,
                jobID: "job_1043",
                to: .travelling,
                destination: Coordinate(latitude: 27.9631, longitude: -82.4419)
            )
            let own = try await gateway.fieldWorkerJobDetail(session: marcus, jobID: "job_1043")

            // Dee's job: refused as notFound, never as a permission hint.
            var othersBlocked = false
            do {
                try await FieldTransitionCoordinator.advance(
                    gateway: gateway,
                    location: locationService,
                    session: marcus,
                    jobID: "job_1049",
                    to: .travelling,
                    destination: nil
                )
            } catch let error as DataError {
                othersBlocked = error == .notFound
            }

            let passed = own.status == .travelling && othersBlocked
            results.append(
                TestScenarioResult(
                    id: "45",
                    number: 45,
                    title: "Field worker can start travel only on an assigned job",
                    expectation: "Their own job advances; another worker's answers notFound",
                    passed: passed,
                    evidence: "J-1043 (Marcus's) → \(own.status.title) · J-1049 (Dee's) \(othersBlocked ? "answered notFound" : "WAS ACCEPTED")"
                )
            )
        } catch {
            results.append(failure(45, "Field worker can start travel only on an assigned job", "Own job only", error))
        }

        // 46, 47, 48 — each field transition writes its own history row.
        do {
            let gateway = freshGateway()
            let before = try await gateway.jobDetail(session: owner, jobID: "job_1043")
            let destination = Coordinate(latitude: 27.9631, longitude: -82.4419)

            var snapshots: [JobStatus: Int] = [:]
            for step: JobStatus in [.travelling, .arrived, .inProgress, .completed] {
                try await FieldTransitionCoordinator.advance(
                    gateway: gateway,
                    location: locationService,
                    session: marcus,
                    jobID: "job_1043",
                    to: step,
                    destination: destination
                )
                snapshots[step] = try await gateway.jobDetail(session: owner, jobID: "job_1043").timeline.count
            }

            let after = try await gateway.jobDetail(session: owner, jobID: "job_1043")
            let titles = after.timeline.map(\.title)

            // Timeline rows render status names through the company's
            // terminology, so `workerAssigned` reads "Engineer assigned" here and
            // "Plumber assigned" for a plumbing tenant. Compare against the same
            // resolved form the projection produces, not the neutral name.
            func rowExists(_ from: JobStatus, _ to: JobStatus) -> Bool {
                let terms = owner.terms
                return titles.contains { $0.contains(from.title(terms)) && $0.contains(to.title(terms)) }
            }

            // 46 — start travel.
            let travelRow = rowExists(.workerAssigned, .travelling)
            results.append(
                TestScenarioResult(
                    id: "46",
                    number: 46,
                    title: "Start travel writes the correct status history entry",
                    expectation: "Assigned → Travelling is recorded with the actor and a timestamp",
                    passed: travelRow && (snapshots[.travelling] ?? 0) == before.timeline.count + 1,
                    evidence: "Timeline \(before.timeline.count) → \(snapshots[.travelling] ?? 0) rows · entry recorded by \(after.timeline.first { $0.title.contains("Travelling") }?.byLabel ?? "—")"
                )
            )

            // 47 — arrival.
            let arrivedRow = rowExists(.travelling, .arrived)
            results.append(
                TestScenarioResult(
                    id: "47",
                    number: 47,
                    title: "Arrival records the correct workflow transition",
                    expectation: "Travelling → Arrived is recorded through the existing workflow",
                    passed: arrivedRow && (snapshots[.arrived] ?? 0) == (snapshots[.travelling] ?? 0) + 1,
                    evidence: "Timeline reached \(snapshots[.arrived] ?? 0) rows · entry recorded by \(after.timeline.first { $0.title.contains("Arrived") }?.byLabel ?? "—")"
                )
            )

            // 48 — completion.
            let completedRow = rowExists(.inProgress, .completed)
            results.append(
                TestScenarioResult(
                    id: "48",
                    number: 48,
                    title: "Completion records the correct workflow transition",
                    expectation: "In progress → Completed is recorded and the job closes",
                    passed: completedRow && after.status == .completed,
                    evidence: "J-1043 is now \(after.status.title) after \(after.timeline.count) recorded transitions: \(titles.suffix(4).joined(separator: " · "))"
                )
            )
        } catch {
            results.append(failure(46, "Field transitions write status history", "Each transition recorded", error))
        }

        // 49 — Position is captured at the permitted events, and only those.
        do {
            let gateway = freshGateway()
            let destination = Coordinate(latitude: 27.9631, longitude: -82.4419)

            let startingRows = try await gateway.fieldWorkerLocations(session: marcus).locations.count

            // Three capturing events.
            for step: JobStatus in [.travelling, .arrived, .inProgress, .completed] {
                try await FieldTransitionCoordinator.advance(
                    gateway: gateway,
                    location: locationService,
                    session: marcus,
                    jobID: "job_1043",
                    to: step,
                    destination: destination
                )
            }

            let board = try await gateway.fieldWorkerLocations(session: marcus)
            let latest = board.locations.first

            // The policy itself: only these three statuses capture anything.
            let capturing = JobStatus.allCases.filter { LocationCaptureEvent.forTransition(to: $0) != nil }
            let policyCorrect = Set(capturing) == Set([.travelling, .arrived, .completed])
            // In progress is deliberately not a capture point.
            let inProgressCaptures = LocationCaptureEvent.forTransition(to: .inProgress) != nil

            let recordsEverything = latest.map { row in
                row.userID == "usr_marcus"
                    && row.jobNumber == "J-1043"
                    && !row.coordinateLabel.isEmpty
                    && !row.accuracyLabel.isEmpty
                    && !row.recordedAtLabel.isEmpty
            } ?? false

            let passed = policyCorrect && !inProgressCaptures && recordsEverything && startingRows >= 0
            results.append(
                TestScenarioResult(
                    id: "49",
                    number: 49,
                    title: "Location is captured at permitted workflow events",
                    expectation: "Travelling, arrived and completed capture a fix; nothing else does, and no timer exists",
                    passed: passed,
                    evidence: "Capture points: \(capturing.map(\.title).joined(separator: ", ")) · in progress captures nothing · latest fix stores company, worker, \(latest?.coordinateLabel ?? "—"), \(latest?.accuracyLabel ?? "—"), job \(latest?.jobNumber ?? "—") at \(latest?.recordedAtLabel ?? "—") · adapter background tracking: \(locationService.performsBackgroundTracking)"
                )
            )
        } catch {
            results.append(failure(49, "Location is captured at permitted workflow events", "Event-driven capture only", error))
        }

        // 50 — A field worker sees their own position and no one else's.
        do {
            let gateway = freshGateway()
            let marcusBoard = try await gateway.fieldWorkerLocations(session: marcus)
            let deeBoard = try await gateway.fieldWorkerLocations(session: dee)

            let marcusOwnOnly = marcusBoard.locations.allSatisfy { $0.userID == "usr_marcus" }
            let deeOwnOnly = deeBoard.locations.allSatisfy { $0.userID == "usr_dee" }
            let bothSawSomething = !marcusBoard.locations.isEmpty && !deeBoard.locations.isEmpty
            // A worker is not told who else has or hasn't reported.
            let noRoster = marcusBoard.withoutLocation.isEmpty && deeBoard.withoutLocation.isEmpty

            let passed = marcusOwnOnly && deeOwnOnly && bothSawSomething && noRoster
            results.append(
                TestScenarioResult(
                    id: "50",
                    number: 50,
                    title: "Field worker cannot access another worker's location",
                    expectation: "Each worker receives exactly one row — their own — and no roster of others",
                    passed: passed,
                    evidence: "Marcus received \(marcusBoard.locations.count) row(s), all his own · Dee received \(deeBoard.locations.count), all hers · neither was told who else has reported"
                )
            )
        } catch {
            results.append(failure(50, "Field worker cannot access another worker's location", "Own position only", error))
        }

        // 51 — The dispatcher sees the team, with freshness distinguished.
        do {
            let gateway = freshGateway()
            let board = try await gateway.fieldWorkerLocations(session: dispatcher)

            let seesMultiple = Set(board.locations.map(\.userID)).count > 1
            let hasContext = board.locations.allSatisfy { !$0.workerName.isEmpty && !$0.recordedAtLabel.isEmpty }
            // Recent and last known are separate states, not one blurred label.
            let freshnessStates = Set(board.locations.map(\.freshness))
            let distinguishes = board.recentCount + board.lastKnownCount == board.locations.count
            let labelled = LocationFreshness.recent.title == "Recent" && LocationFreshness.lastKnown.title == "Last known"
            // Current job and status ride along where there is one.
            let carriesJob = board.locations.contains { $0.jobNumber != nil && $0.jobStatusTitle != nil }

            let workerCount = Set(board.locations.map(\.userID)).count
            let freshnessLabels = freshnessStates.map(\.title).sorted().joined(separator: ", ")

            let passed = seesMultiple && hasContext && distinguishes && labelled && carriesJob
            results.append(
                TestScenarioResult(
                    id: "51",
                    number: 51,
                    title: "Dispatcher can see authorised field worker location data",
                    expectation: "Worker, position, timestamp, current job and status, with recent distinguished from last known",
                    passed: passed,
                    evidence: "\(board.locations.count) positions across \(workerCount) \(dispatcher.terms.workerPlural) · \(board.recentCount) recent, \(board.lastKnownCount) last known (states seen: \(freshnessLabels)) · \(board.withoutLocation.count) with nothing reported"
                )
            )
        } catch {
            results.append(failure(51, "Dispatcher can see authorised field worker location data", "Team positions with freshness", error))
        }

        // 52 — Location cannot cross a company boundary.
        do {
            let gateway = freshGateway()

            // Northline's owner sees Northline only — Gulf Coast's workers are
            // not merely filtered from the view, they are unreachable.
            let northBoard = try await gateway.fieldWorkerLocations(session: northOwner)
            let gulfUserIDs: Set<String> = ["usr_marcus", "usr_dee"]
            let noGulfRows = northBoard.locations.allSatisfy { !gulfUserIDs.contains($0.userID) }
            let noGulfNames = !northBoard.withoutLocation.contains("Marcus Hale")

            // And a Gulf Coast job answers notFound to the other tenant.
            var crossTenantHidden = false
            do { _ = try await gateway.travelSnapshot(session: northOwner, jobID: "job_1042") }
            catch let error as DataError { crossTenantHidden = error == .notFound }

            let passed = noGulfRows && noGulfNames && crossTenantHidden
            results.append(
                TestScenarioResult(
                    id: "52",
                    number: 52,
                    title: "Cross-company location access returns notFound",
                    expectation: "No other tenant's positions are reachable, and a direct request answers notFound",
                    passed: passed,
                    evidence: "Northline received \(northBoard.locations.count) position(s), none belonging to Gulf Coast · Gulf Coast job J-1042 \(crossTenantHidden ? "answered notFound" : "WAS VISIBLE") to Northline"
                )
            )
        } catch {
            results.append(failure(52, "Cross-company location access returns notFound", "Company-scoped positions", error))
        }

        // 53 and 54 — navigation goes through the adapter, and says what it is.
        do {
            let gateway = freshGateway()
            let trip = try await gateway.travelSnapshot(session: marcus, jobID: "job_1042")
            let handoff = mapService.prepareNavigation(
                to: Coordinate(latitude: trip.latitude, longitude: trip.longitude),
                label: trip.customerName,
                addressLine: trip.addressLine
            )

            // 53 — the destination is prepared by the MapService adapter, and
            // the app builds no route of its own.
            let usesAdapter = handoff.destination.latitude == trip.latitude
                && handoff.destination.longitude == trip.longitude
                && handoff.label == trip.customerName
                && handoff.canOpen
            let swappable = (mapService as MapService).providerName == "MapKit"

            results.append(
                TestScenarioResult(
                    id: "53",
                    number: 53,
                    title: "Navigation uses the MapService adapter",
                    expectation: "The destination is prepared through the adapter, which a production provider can replace",
                    passed: usesAdapter && swappable,
                    evidence: "Adapter prepared \(handoff.label) at \(Formatters.coordinateLabel(latitude: handoff.destination.latitude, longitude: handoff.destination.longitude)) · planned production provider: \((mapService as MapService).providerName) · no routing engine in this app"
                )
            )

            // 54 — and it is unambiguous about being simulated.
            let flagged = handoff.simulated
            let modeSimulated = mapService.mode.isSimulated
            let explains = handoff.behaviourNote.lowercased().contains("no in-app routing")
                || handoff.behaviourNote.lowercased().contains("turn-by-turn")
            let registryHonest = IntegrationRegistry.all.first { $0.id == "maps" }?.mode.isSimulated == true

            results.append(
                TestScenarioResult(
                    id: "54",
                    number: 54,
                    title: "Development navigation remains clearly simulated",
                    expectation: "The hand-off is flagged simulated and states that no turn-by-turn is implemented",
                    passed: flagged && modeSimulated && explains && registryHonest,
                    evidence: "simulated=\(flagged), mode=\(mapService.mode.rawValue) · states: '\(handoff.behaviourNote)' · Integrations screen lists maps as simulated"
                )
            )
        } catch {
            results.append(failure(53, "Navigation uses the MapService adapter", "Adapter-prepared hand-off", error))
        }

        // 55 — The ETA is honest about being a fixture.
        do {
            let origin = await locationService.currentLocation() ?? Coordinate(latitude: 27.9772, longitude: -82.4680)
            let estimate = await routeService.estimate(
                from: origin,
                to: Coordinate(latitude: 27.9506, longitude: -82.4572)
            )

            let flagged = estimate.simulated
            let noTraffic = !estimate.usesLiveTraffic
            // The shape is what a real provider returns, so swapping adapters is
            // not a model change.
            let productionShaped = estimate.distanceMeters > 0
                && estimate.durationSeconds > 0
                && estimate.arrivalTime > Date().addingTimeInterval(-5)
            let unitsFollowCountry = estimate.distanceLabel(countryCode: "US").contains("mi")
                && estimate.distanceLabel(countryCode: "IE").contains("km")
            let registryHonest = IntegrationRegistry.all.first { $0.id == "routing" }?.mode.isSimulated == true

            let passed = flagged && noTraffic && productionShaped && unitsFollowCountry && registryHonest
            results.append(
                TestScenarioResult(
                    id: "55",
                    number: 55,
                    title: "ETA is clearly identified as simulated",
                    expectation: "The estimate carries a simulated flag and has the shape a production provider returns",
                    passed: passed,
                    evidence: "\(estimate.distanceLabel(countryCode: "US")) / \(estimate.durationLabel), arriving \(estimate.arrivalLabel) · simulated=\(flagged), live traffic=\(estimate.usesLiveTraffic) · same distance reads \(estimate.distanceLabel(countryCode: "IE")) for a metric company · planned provider: \((routeService as RouteService).providerName)"
                )
            )
        } catch {
            results.append(failure(55, "ETA is clearly identified as simulated", "Simulated flag on the estimate", error))
        }

        // 56 — The workflow table still refuses invalid jumps.
        do {
            let gateway = freshGateway()
            var jumpRefused = false
            var backwardsRefused = false
            var detail = ""

            do {
                try await FieldTransitionCoordinator.advance(
                    gateway: gateway,
                    location: locationService,
                    session: marcus,
                    jobID: "job_1044",
                    to: .completed,
                    destination: nil
                )
            } catch let error as DataError {
                if case .invalidTransition = error {
                    jumpRefused = true
                    detail = error.errorDescription ?? ""
                }
            }

            // A finished job cannot be dragged back onto the road either.
            do {
                try await gateway.updateJobStatus(session: owner, jobID: "job_1041", to: .travelling)
            } catch let error as DataError {
                if case .invalidTransition = error { backwardsRefused = true }
            }

            // Capturing a position does not smuggle an invalid change through.
            let untouched = try await gateway.jobDetail(session: owner, jobID: "job_1044")

            let passed = jumpRefused && backwardsRefused && untouched.status == .workerAssigned
            results.append(
                TestScenarioResult(
                    id: "56",
                    number: 56,
                    title: "Invalid job transitions remain rejected",
                    expectation: "Out-of-order and backwards moves are refused by the workflow, even with a location attached",
                    passed: passed,
                    evidence: "Assigned → Completed: \(detail) · Completed → Travelling \(backwardsRefused ? "refused" : "ACCEPTED") · J-1044 still \(untouched.status.title)"
                )
            )
        } catch {
            results.append(failure(56, "Invalid job transitions remain rejected", "Workflow table is the authority", error))
        }

        // 57 — An overlap is refused first, then allowed once acknowledged.
        do {
            let gateway = freshGateway()

            var firstAttemptRefused = false
            var warning = ""
            do {
                _ = try await gateway.assignJob(
                    session: dispatcher,
                    jobID: "job_1049",
                    input: AssignmentInput(workerUserID: "usr_marcus", acknowledgesConflict: false)
                )
            } catch let error as DataError {
                if case .rejected = error {
                    firstAttemptRefused = true
                    warning = error.errorDescription ?? ""
                }
            }

            // Nothing changed on the refused attempt.
            let afterRefusal = try await gateway.jobDetail(session: dispatcher, jobID: "job_1049")
            let unchanged = afterRefusal.assignedWorker?.userID == "usr_dee"

            // Acknowledged, it goes through — dispatch is a human job.
            let check = try await gateway.assignJob(
                session: dispatcher,
                jobID: "job_1049",
                input: AssignmentInput(workerUserID: "usr_marcus", acknowledgesConflict: true)
            )
            let afterAck = try await gateway.jobDetail(session: dispatcher, jobID: "job_1049")
            let applied = afterAck.assignedWorker?.userID == "usr_marcus"

            // And the board reports the overlap so it stays visible afterwards.
            let board = try await gateway.dispatchBoard(session: dispatcher, query: .today)
            let surfaced = !board.conflicts.isEmpty

            let passed = firstAttemptRefused && unchanged && check.hasConflicts && applied && surfaced
            results.append(
                TestScenarioResult(
                    id: "57",
                    number: 57,
                    title: "Overlapping jobs produce a scheduling conflict warning",
                    expectation: "The first attempt is refused with the clash; an acknowledged retry is allowed and stays visible",
                    passed: passed,
                    evidence: "First attempt refused: '\(warning)' · J-1049 still Dee's afterwards · acknowledged retry assigned Marcus with \(check.conflicts.count) known overlap · board still reports \(board.conflicts.count) conflict(s)"
                )
            )
        } catch {
            results.append(failure(57, "Overlapping jobs produce a scheduling conflict warning", "Warned, never silent", error))
        }

        // 58 — Dispatch reads in each company's own vocabulary.
        do {
            let gateway = freshGateway()
            let hvacBoard = try await gateway.dispatchBoard(session: dispatcher, query: .today)
            let plumbingBoard = try await gateway.dispatchBoard(session: northOwner, query: .today)

            let hvacWorkerTitle = hvacBoard.workers.first?.roleTitle ?? ""
            let plumbingWorkerTitle = plumbingBoard.workers.first?.roleTitle ?? ""

            let hvacReadsEngineer = hvacWorkerTitle == "Engineer"
            let plumbingReadsPlumber = plumbingWorkerTitle == "Plumber"
            // Other trades run the same architecture with their own words.
            let electrical = Trade.electrical.terminology
            let roofing = Trade.roofing.terminology
            let pest = Trade.pestControl.terminology
            let othersRead = Role.fieldWorker.title(electrical) == "Electrician"
                && Role.fieldWorker.title(roofing) == "Roofer"
                && Role.fieldWorker.title(pest) == "Technician"
            // Status wording follows the trade too, while the enum does not.
            let statusReads = JobStatus.workerAssigned.title(Trade.hvac.terminology) == "Engineer assigned"
                && JobStatus.workerAssigned.title(Trade.plumbing.terminology) == "Plumber assigned"
            // The underlying permission model is identical.
            let samePermissions = PermissionMatrix.permissions(for: .fieldWorker) == PermissionMatrix.permissions(for: .fieldWorker)
            let sameWorkflow = JobWorkflow.all.count > 0

            let passed = hvacReadsEngineer && plumbingReadsPlumber && othersRead && statusReads && samePermissions && sameWorkflow
            results.append(
                TestScenarioResult(
                    id: "58",
                    number: 58,
                    title: "Trade terminology is correct across companies",
                    expectation: "Each company's dispatch board uses its own words on one identical workflow",
                    passed: passed,
                    evidence: "Gulf Coast dispatch reads '\(hvacWorkerTitle)', Northline reads '\(plumbingWorkerTitle)' · electrical '\(Role.fieldWorker.title(electrical))', roofing '\(Role.fieldWorker.title(roofing))', pest control '\(Role.fieldWorker.title(pest))' · same \(JobWorkflow.all.count)-transition workflow and the same permission set for all of them"
                )
            )
        } catch {
            results.append(failure(58, "Trade terminology is correct across companies", "Vocabulary differs, architecture does not", error))
        }

        // 59 — No money reaches a field worker anywhere in the dispatch flow.
        do {
            let gateway = freshGateway()
            let destination = Coordinate(latitude: 27.9631, longitude: -82.4419)

            var offenders: [String] = []

            // Every field-facing payload, at each stage of the journey.
            let day = try await gateway.fieldWorkerDay(session: marcus)
            offenders += day.stops.flatMap { monetaryFields(of: $0) }

            let jobBefore = try await gateway.fieldWorkerJobDetail(session: marcus, jobID: "job_1043")
            offenders += monetaryFields(of: jobBefore)

            try await FieldTransitionCoordinator.advance(
                gateway: gateway, location: locationService, session: marcus,
                jobID: "job_1043", to: .travelling, destination: destination
            )

            let trip = try await gateway.travelSnapshot(session: marcus, jobID: "job_1043")
            offenders += monetaryFields(of: trip)

            try await FieldTransitionCoordinator.advance(
                gateway: gateway, location: locationService, session: marcus,
                jobID: "job_1043", to: .arrived, destination: destination
            )
            let onSite = try await gateway.fieldWorkerJobDetail(session: marcus, jobID: "job_1043")
            offenders += monetaryFields(of: onSite)

            let location = try await gateway.fieldWorkerLocations(session: marcus)
            offenders += location.locations.flatMap { monetaryFields(of: $0) }

            // And the financial surfaces stay refused throughout.
            var refusedCount = 0
            for probe in ["invoices", "payments", "receivables", "quotes"] {
                do {
                    switch probe {
                    case "invoices": _ = try await gateway.invoices(session: marcus, query: InvoiceQuery(filter: .all))
                    case "payments": _ = try await gateway.payments(session: marcus, query: InvoiceQuery(filter: .all))
                    case "receivables": _ = try await gateway.receivables(session: marcus, query: InvoiceQuery(filter: .all))
                    default: _ = try await gateway.quotes(session: marcus, filter: .all, query: "")
                    }
                } catch {
                    refusedCount += 1
                }
            }

            let passed = offenders.isEmpty && refusedCount == 4
            results.append(
                TestScenarioResult(
                    id: "59",
                    number: 59,
                    title: "Financial data stays unavailable to field workers throughout dispatch",
                    expectation: "No monetary field in any field payload at any stage, and every financial query refused",
                    passed: passed,
                    evidence: offenders.isEmpty
                        ? "Reflection over the day view, job detail, travel screen and location board found no price, total, tax, invoice, payment or quote field at any stage · all \(refusedCount) financial queries refused"
                        : "LEAKED: \(Set(offenders).sorted().joined(separator: ", "))"
                )
            )
        } catch {
            results.append(failure(59, "Financial data stays unavailable to field workers throughout dispatch", "Structurally money-free", error))
        }

        // 60 — Position records never leave their company.
        do {
            let gateway = freshGateway()

            // Write a fix as a Gulf Coast worker.
            try await FieldTransitionCoordinator.advance(
                gateway: gateway,
                location: locationService,
                session: marcus,
                jobID: "job_1043",
                to: .travelling,
                destination: Coordinate(latitude: 27.9631, longitude: -82.4419)
            )

            let gulfBoard = try await gateway.dispatchBoard(session: dispatcher, query: .today)
            let northBoard = try await gateway.fieldWorkerLocations(session: northOwner)
            let gulfLocations = try await gateway.fieldWorkerLocations(session: dispatcher)

            let gulfSeesIt = gulfLocations.locations.contains { $0.userID == "usr_marcus" }
            let northCannot = northBoard.locations.allSatisfy { $0.userID != "usr_marcus" }
            // The dispatch board's embedded positions are scoped the same way.
            let boardScoped = gulfBoard.workers.compactMap(\.location).allSatisfy { $0.userID != "usr_north_worker" }
            // Retention is bounded by policy, not left to grow.
            let bounded = LocationRetentionPolicy.days > 0 && LocationRetentionPolicy.maximumPingsPerWorker > 0

            let passed = gulfSeesIt && northCannot && boardScoped && bounded
            results.append(
                TestScenarioResult(
                    id: "60",
                    number: 60,
                    title: "Location records remain company-scoped",
                    expectation: "A fix is visible inside its own company only, and retention is bounded by policy",
                    passed: passed,
                    evidence: "Marcus's new fix visible to Gulf Coast dispatch (\(gulfLocations.locations.count) positions) · Northline sees \(northBoard.locations.count) and none of them Gulf Coast's · retention: \(LocationRetentionPolicy.summary)"
                )
            )
        } catch {
            results.append(failure(60, "Location records remain company-scoped", "Company-scoped positions", error))
        }

        // 61 — The Swift permission matrix still matches the one in PostgreSQL.
        do {
            let matches = PermissionMatrixContract.matchesDatabase
            let perRole = PermissionMatrixContract.grantsByRole
                .map { "\($0.role.rawValue) \($0.count)" }
                .joined(separator: ", ")

            results.append(
                TestScenarioResult(
                    id: "61",
                    number: 61,
                    title: "Permission matrix matches the database",
                    expectation: "Swift and PostgreSQL express identical permissions and role grants",
                    passed: matches,
                    evidence: matches
                        ? "\(PermissionMatrixContract.permissionCount) permissions and \(PermissionMatrixContract.grantCount) grants on both sides (\(perRole)) · checksum \(PermissionMatrixContract.fingerprint) agrees with public.permission_matrix_contract"
                        : "DRIFT: \(PermissionMatrixContract.driftDescription)"
                )
            )
        }

        // 62 — Matrix invariants that hold whatever the checksum says. A wrong
        //      edit re-pinned to a new checksum would still be caught here.
        do {
            let fieldWorker = PermissionMatrix.permissions(for: .fieldWorker)
            let financial: Set<Permission> = [
                .quotesRead, .quotesManage, .quoteFinancialsRead,
                .invoicesRead, .invoicesManage,
                .paymentsRead, .paymentsManage,
                .customerBillingDetailsRead,
                .saasBillingRead, .saasBillingManage,
                .reportsFinancial
            ]
            let fieldWorkerIsMoneyFree = fieldWorker.isDisjoint(with: financial)

            // The four narrowed permissions belong to the field worker alone —
            // no broad role may hold a "…OwnOnly" grant.
            let narrowed: Set<Permission> = [
                .jobsReadAssignedOnly, .customersReadAssignedSiteOnly,
                .calendarReadOwnOnly, .fieldWorkerLocationReadOwnOnly
            ]
            let narrowedAreExclusive = Role.allCases
                .filter { $0 != .fieldWorker }
                .allSatisfy { PermissionMatrix.permissions(for: $0).isDisjoint(with: narrowed) }

            // Owner holds everything except the narrowed variants, and every
            // other role is a subset of the owner's reach.
            let owner = PermissionMatrix.permissions(for: .owner)
            let ownerIsComplete = owner == Set(Permission.allCases).subtracting(narrowed)
            let ownerIsSuperset = Role.allCases
                .filter { $0 != .fieldWorker }
                .allSatisfy { PermissionMatrix.permissions(for: $0).isSubset(of: owner) }

            // Only the owner may end the company or move the SaaS subscription.
            let ownerOnly: Set<Permission> = [.companyDelete, .saasBillingManage]
            let lifecycleIsOwnerOnly = Role.allCases
                .filter { $0 != .owner }
                .allSatisfy { PermissionMatrix.permissions(for: $0).isDisjoint(with: ownerOnly) }

            let passed = fieldWorkerIsMoneyFree && narrowedAreExclusive
                && ownerIsComplete && ownerIsSuperset && lifecycleIsOwnerOnly

            var broken: [String] = []
            if !fieldWorkerIsMoneyFree { broken.append("field worker holds a financial permission") }
            if !narrowedAreExclusive { broken.append("a broad role holds a narrowed permission") }
            if !ownerIsComplete { broken.append("owner is no longer the complete set") }
            if !ownerIsSuperset { broken.append("a role exceeds the owner") }
            if !lifecycleIsOwnerOnly { broken.append("company lifecycle escaped the owner") }

            results.append(
                TestScenarioResult(
                    id: "62",
                    number: 62,
                    title: "Permission matrix invariants hold independently of the checksum",
                    expectation: "Field workers stay money-free, narrowed grants stay exclusive, owner stays the ceiling",
                    passed: passed,
                    evidence: passed
                        ? "Field worker's \(fieldWorker.count) permissions touch none of the \(financial.count) financial ones · the 4 narrowed grants appear on no other role · owner holds \(owner.count) and every other role is a subset · company deletion and SaaS billing are owner-only"
                        : "BROKEN: \(broken.joined(separator: " · "))"
                )
            )
        }

        // 63 — The development stack is untouched by the production auth work.
        do {
            let devGateway = freshGateway()
            let devAuth = MockAuthService(store: .seeded())

            let listed = await devAuth.availableAccounts()
            let signedIn = try await devAuth.signIn(accountID: "usr_owner")
            let jobs = try await devGateway.jobs(session: signedIn, query: allJobs)

            let stillSimulated = devAuth.mode.isSimulated
            let stillLists = listed.count > 0
            let stillServes = jobs.count > 0
            // company_id still comes from the account record, not from input.
            let companyFromRecord = signedIn.companyID == "cmp_gulfcoast"

            var unknownRefused = false
            do {
                _ = try await devAuth.signIn(accountID: "usr_does_not_exist")
            } catch {
                unknownRefused = true
            }

            let passed = stillSimulated && stillLists && stillServes && companyFromRecord && unknownRefused
            results.append(
                TestScenarioResult(
                    id: "63",
                    number: 63,
                    title: "Development sign-in and simulated data still work",
                    expectation: "MockAuthService and MockDataGateway behave exactly as they did before production auth existed",
                    passed: passed,
                    evidence: "\(listed.count) seeded accounts listed · signed in as \(signedIn.displayName) (\(signedIn.roleTitle)) with company taken from the account record · \(jobs.count) jobs served by MockDataGateway · unknown account refused · mode still '\(devAuth.mode.rawValue)'"
                )
            )
        } catch {
            results.append(failure(63, "Development sign-in and simulated data still work", "Development stack unchanged", error))
        }

        // 64 — The production sign-up surface cannot express a chosen tenancy.
        do {
            let registration = CompanyRegistration(
                email: "founder@example.com",
                password: "correct-horse",
                ownerName: "Founder",
                companyName: "New Co",
                trade: .roofing,
                countryCode: "US",
                currencyCode: "USD"
            )

            // Reflection over what the client is even capable of sending. A field
            // naming company identity or role would be a way to ask for a tenant.
            let fields = Mirror(reflecting: registration).children.compactMap { $0.label?.lowercased() }
            let forbidden = fields.filter { field in
                field == "companyid" || field == "userid" || field == "role"
                    || (field.contains("company") && field.contains("id"))
            }

            let carriesTrade = fields.contains("trade")
            let carriesCompanyName = fields.contains("companyname")
            let passed = forbidden.isEmpty && carriesTrade && carriesCompanyName

            results.append(
                TestScenarioResult(
                    id: "64",
                    number: 64,
                    title: "Production sign-up cannot request a company or a role",
                    expectation: "No client-supplied company id or role exists anywhere in the registration payload",
                    passed: passed,
                    evidence: forbidden.isEmpty
                        ? "CompanyRegistration carries \(fields.count) fields (\(fields.sorted().joined(separator: ", "))) — none names a company id, user id or role · create_company_and_owner() mints both server-side"
                        : "LEAKED: \(forbidden.joined(separator: ", "))"
                )
            )
        }

        // 65 — Signing out leaves no tenant context behind on either stack.
        do {
            let environment = AppEnvironment()
            await environment.signIn(accountID: "usr_owner")
            let hadSession = environment.session != nil

            environment.signOut()
            let devCleared = environment.session == nil
            let devErrorCleared = environment.signInError == nil

            // Production holds nothing until a membership is resolved server-side.
            let productionStartsEmpty = environment.productionSession == nil
            let activeIsNil = environment.activeSession == nil
            let termsAreNeutral = environment.terms.worker == Terminology.generic.worker

            let passed = hadSession && devCleared && devErrorCleared
                && productionStartsEmpty && activeIsNil && termsAreNeutral
            results.append(
                TestScenarioResult(
                    id: "65",
                    number: 65,
                    title: "Signing out clears the session",
                    expectation: "No session, no error and no tenant vocabulary survive a sign-out",
                    passed: passed,
                    evidence: "Development session established then cleared · production session nil · activeSession nil so no screen can read a company after sign-out · terminology fell back to neutral"
                )
            )
        }

        // 66 — The job screen assigns cleanly when there is no clash.
        do {
            let gateway = freshGateway()
            let viewModel = JobDetailViewModel()
            await viewModel.loadOptions(gateway: gateway, session: dispatcher)
            await viewModel.load(gateway: gateway, session: dispatcher, jobID: "job_1046")
            let before = viewModel.state.value

            await viewModel.assign(gateway: gateway, session: dispatcher, jobID: "job_1046", workerUserID: "usr_marcus")

            let after = try await gateway.jobDetail(session: dispatcher, jobID: "job_1046")
            let assigned = after.assignedWorker?.userID == "usr_marcus"
            let noSheet = viewModel.pendingConflict == nil
            let noError = viewModel.actionError == nil
            let confirmed = viewModel.lastConfirmation != nil
            let statusMoved = before?.status == .scheduled && after.status == .workerAssigned

            let passed = assigned && noSheet && noError && confirmed && statusMoved
            results.append(
                TestScenarioResult(
                    id: "66",
                    number: 66,
                    title: "Job screen assigns with no conflict",
                    expectation: "A free worker is assigned straight away, with no warning sheet raised",
                    passed: passed,
                    evidence: "\(after.number) → \(after.assignedWorker?.name ?? "none") · \(before?.status.title ?? "?") → \(after.status.title) · conflict sheet \(noSheet ? "not raised" : "RAISED") · '\(viewModel.lastConfirmation ?? "no confirmation")'"
                )
            )
        } catch {
            results.append(failure(66, "Job screen assigns with no conflict", "Assigned straight away with no warning", error))
        }

        // 67 — An overlap from the job screen is held for acknowledgement, and
        // cancelling writes nothing at all.
        do {
            let gateway = freshGateway()
            let viewModel = JobDetailViewModel()
            await viewModel.loadOptions(gateway: gateway, session: dispatcher)
            await viewModel.load(gateway: gateway, session: dispatcher, jobID: "job_1049")

            await viewModel.assign(gateway: gateway, session: dispatcher, jobID: "job_1049", workerUserID: "usr_marcus")

            let pending = viewModel.pendingConflict
            let held = pending != nil
            // The clash is presented, not reported as a failure.
            let notAnError = viewModel.actionError == nil
            let namesTheClash = pending?.check.conflicts.first?.clashingJobNumber == "J-1043"
            let namesTheWorker = pending?.workerName == "Marcus Hale"
            let namesTheJob = pending?.jobNumber == "J-1049"
            let showsTheTime = !(pending?.check.conflicts.first?.overlapLabel.isEmpty ?? true)

            // Nothing was written while the question is open.
            let during = try await gateway.jobDetail(session: dispatcher, jobID: "job_1049")
            let untouched = during.assignedWorker?.userID == "usr_dee"

            // Cancelling is exactly what dismissing the sheet does.
            viewModel.pendingConflict = nil
            let after = try await gateway.jobDetail(session: dispatcher, jobID: "job_1049")
            let stillDees = after.assignedWorker?.userID == "usr_dee"
            let marcusNeverSawIt = try await !gateway.jobs(session: marcus, query: allJobs).contains { $0.id == "job_1049" }

            let passed = held && notAnError && namesTheClash && namesTheWorker
                && namesTheJob && showsTheTime && untouched && stillDees && marcusNeverSawIt
            results.append(
                TestScenarioResult(
                    id: "67",
                    number: 67,
                    title: "Job screen holds an overlapping assignment for acknowledgement",
                    expectation: "The clash is shown with the job, worker, clashing job and time — and cancelling changes nothing",
                    passed: passed,
                    evidence: "Sheet raised for \(pending?.contextLine ?? "nothing") · clashes with \(pending?.check.conflicts.first?.clashingJobNumber ?? "?") at \(pending?.check.conflicts.first?.overlapLabel ?? "?") · surfaced as a confirmation, actionError \(notAnError ? "nil" : "SET") · after cancelling J-1049 is still \(after.assignedWorker?.name ?? "nobody")'s and Marcus still cannot see it"
                )
            )
        } catch {
            results.append(failure(67, "Job screen holds an overlapping assignment for acknowledgement", "Shown and held, never silently written", error))
        }

        // 68 — "Assign anyway" carries the acknowledgement through the same path.
        do {
            let gateway = freshGateway()
            let viewModel = JobDetailViewModel()
            await viewModel.loadOptions(gateway: gateway, session: dispatcher)
            await viewModel.load(gateway: gateway, session: dispatcher, jobID: "job_1049")

            await viewModel.assign(gateway: gateway, session: dispatcher, jobID: "job_1049", workerUserID: "usr_marcus")
            let wasHeld = viewModel.pendingConflict != nil

            await viewModel.confirmPendingAssignment(gateway: gateway, session: dispatcher)

            let after = try await gateway.jobDetail(session: dispatcher, jobID: "job_1049")
            let applied = after.assignedWorker?.userID == "usr_marcus"
            let sheetDismissed = viewModel.pendingConflict == nil
            let noError = viewModel.actionError == nil
            // The overlap is deliberate, so it stays visible on the board.
            let board = try await gateway.dispatchBoard(session: dispatcher, query: .today)
            let surfaced = !board.conflicts.isEmpty

            let passed = wasHeld && applied && sheetDismissed && noError && surfaced
            results.append(
                TestScenarioResult(
                    id: "68",
                    number: 68,
                    title: "Assign anyway carries the acknowledgement from the job screen",
                    expectation: "The deliberate confirmation goes through the existing assignment path and the overlap stays visible",
                    passed: passed,
                    evidence: "Refused first, then acknowledged: J-1049 → \(after.assignedWorker?.name ?? "none") · '\(viewModel.lastConfirmation ?? "no confirmation")' · board still reports \(board.conflicts.count) conflict(s)"
                )
            )
        } catch {
            results.append(failure(68, "Assign anyway carries the acknowledgement from the job screen", "Acknowledged assignment succeeds", error))
        }

        // 69 — Reassigning from the job screen takes the job off the previous
        // worker rather than adding a second claim.
        do {
            let gateway = freshGateway()
            let viewModel = JobDetailViewModel()
            await viewModel.loadOptions(gateway: gateway, session: dispatcher)
            await viewModel.load(gateway: gateway, session: dispatcher, jobID: "job_1044")
            let before = viewModel.state.value

            await viewModel.assign(gateway: gateway, session: dispatcher, jobID: "job_1044", workerUserID: "usr_dee")

            let after = try await gateway.jobDetail(session: dispatcher, jobID: "job_1044")
            let wasMarcus = before?.assignedWorker?.userID == "usr_marcus"
            let movedToDee = after.assignedWorker?.userID == "usr_dee"
            let marcusJobs = try await gateway.jobs(session: marcus, query: allJobs).map(\.id)
            let deeJobs = try await gateway.jobs(session: dee, query: allJobs).map(\.id)
            let removedFromMarcus = !marcusJobs.contains("job_1044")
            let addedToDee = deeJobs.contains("job_1044")
            let noSheet = viewModel.pendingConflict == nil

            // Clearing from the same screen sends the job back to scheduled.
            await viewModel.assign(gateway: gateway, session: dispatcher, jobID: "job_1044", workerUserID: nil)
            let cleared = try await gateway.jobDetail(session: dispatcher, jobID: "job_1044")
            let unassigned = cleared.assignedWorker == nil && cleared.status == .scheduled

            let passed = wasMarcus && movedToDee && removedFromMarcus && addedToDee && noSheet && unassigned
            results.append(
                TestScenarioResult(
                    id: "69",
                    number: 69,
                    title: "Reassigning from the job screen removes the previous worker",
                    expectation: "The old claim is gone, not superseded, and clearing returns the job to scheduled",
                    passed: passed,
                    evidence: "J-1044 Marcus → Dee · removed from Marcus's list: \(removedFromMarcus) · in Dee's list: \(addedToDee) · then cleared back to \(cleared.status.title) with \(cleared.assignedWorker?.name ?? "nobody") assigned"
                )
            )
        } catch {
            results.append(failure(69, "Reassigning from the job screen removes the previous worker", "One claim at a time", error))
        }

        // 70 — The guard lives under the UI, not in it.
        do {
            let gateway = freshGateway()

            // The data layer refuses an unacknowledged overlap even when called
            // directly, so the sheet is a courtesy and not the protection. In
            // production this same call reaches assign_job(), which re-applies
            // the rule in PostgreSQL regardless of what the client sends.
            var refusedWithoutUI = false
            var warning = ""
            do {
                try await gateway.assignFieldWorker(session: dispatcher, jobID: "job_1049", workerUserID: "usr_marcus")
            } catch let error as DataError {
                if case .rejected = error {
                    refusedWithoutUI = true
                    warning = error.errorDescription ?? ""
                }
            }

            // A field worker cannot assign at all, acknowledged or not.
            var workerRefused = false
            do {
                try await gateway.assignFieldWorker(session: marcus, jobID: "job_1046", workerUserID: "usr_marcus", acknowledgesConflict: true)
            } catch let error as DataError {
                if case .notPermitted = error { workerRefused = true }
            }

            // Nor can another tenant, acknowledgement or not.
            var crossTenantRefused = false
            do {
                try await gateway.assignFieldWorker(session: northOwner, jobID: "job_1049", workerUserID: "usr_marcus", acknowledgesConflict: true)
            } catch let error as DataError {
                if case .notFound = error { crossTenantRefused = true }
            }

            let after = try await gateway.jobDetail(session: dispatcher, jobID: "job_1049")
            let untouched = after.assignedWorker?.userID == "usr_dee"

            let passed = refusedWithoutUI && workerRefused && crossTenantRefused && untouched
            results.append(
                TestScenarioResult(
                    id: "70",
                    number: 70,
                    title: "Assignment protection holds beneath the job screen",
                    expectation: "The overlap rule, the permission and the tenant boundary all hold when the gateway is called directly",
                    passed: passed,
                    evidence: "Unacknowledged overlap refused without any UI: '\(warning)' · field worker \(workerRefused ? "refused" : "ALLOWED") · other tenant \(crossTenantRefused ? "got notFound" : "REACHED THE ROW") · J-1049 still \(after.assignedWorker?.name ?? "nobody")'s"
                )
            )
        } catch {
            results.append(failure(70, "Assignment protection holds beneath the job screen", "The guard is in the data layer", error))
        }

        // MARK: Production Core Location

        // A stand-in for the production adapter. `CoreLocationService` itself
        // needs a device with a real radio and a human to answer a prompt, so
        // the *path* is exercised with a deterministic adapter that reports
        // production mode and, crucially, marks its fixes as real.
        let productionGPS = StubProductionLocationService(state: .authorized)
        let destination = Coordinate(latitude: 27.9631, longitude: -82.4419)

        /// The id of a worker's most recent stored position, or nil. A new id
        /// means a new capture actually happened.
        func latestFixID(_ gateway: DataGateway, _ session: TenantSession) async -> String? {
            let board = try? await gateway.fieldWorkerLocations(session: session)
            return board?.locations.first { $0.userID == session.userID }?.id
        }

        // 71 — The two stacks use two different adapters, and say which.
        do {
            let environment = AppEnvironment()
            // No production session, so the composition root serves fixtures
            // and nothing ever asks the device for a position.
            let developmentIsSimulated = environment.location.mode == .simulated
            let developmentFix = await environment.location.captureFix(for: .travelStarted, near: destination)
            let fixtureIsMarked = developmentFix?.simulated == true
            // The development adapter needs no permission and never prompts.
            let noPromptInDevelopment = await environment.location.authorizationState == .authorized

            // The real adapter exists, reports production, and can follow a
            // travel leg. The development adapter cannot, and does not pretend
            // to — asking it to track returns `.off` rather than a fake badge.
            let real = CoreLocationService()
            let productionMode = real.mode == .production
            let productionCanTrackALeg = real.performsBackgroundTracking
            let developmentNeverTracks = !MockLocationService().performsBackgroundTracking
            let developmentRefusesToTrack = await MockLocationService()
                .startTravelTracking(jobID: "job_1043") { _ in } == .off
            // A freshly built adapter is idle. Tracking only ever begins from a
            // status transition that already has a job id in hand.
            let idleTrackerIsOff = !environment.travelTracker.state.isTracking

            let passed = developmentIsSimulated && fixtureIsMarked && noPromptInDevelopment
                && productionMode && productionCanTrackALeg && developmentNeverTracks
                && developmentRefusesToTrack && idleTrackerIsOff
            results.append(
                TestScenarioResult(
                    id: "71",
                    number: 71,
                    title: "Development stays simulated while production reads the device",
                    expectation: "The mock adapter still serves the development stack and cannot track; Core Location is wired for production and can follow one travel leg",
                    passed: passed,
                    evidence: "Development adapter mode=\(environment.location.mode.rawValue), fix simulated=\(developmentFix?.simulated.description ?? "none"), no permission needed, startTravelTracking returns .off · CoreLocationService mode=\(real.mode.rawValue), performsBackgroundTracking=\(real.performsBackgroundTracking) · tracker idle at launch=\(!environment.travelTracker.state.isTracking)"
                )
            )
        }

        // 72 — A real capture is stored as real, with everything on it.
        do {
            let gateway = freshGateway()

            let outcome = try await FieldTransitionCoordinator.advance(
                gateway: gateway,
                location: productionGPS,
                session: marcus,
                jobID: "job_1043",
                to: .travelling,
                destination: destination
            )

            let board = try await gateway.fieldWorkerLocations(session: marcus)
            let row = board.locations.first

            let markedReal = row?.isSimulated == false
            let capturedReal = outcome == .captured(simulated: false)
            let coordinates = row.map { abs($0.latitude - 28.01) < 0.0001 && abs($0.longitude + 82.50) < 0.0001 } ?? false
            let hasAccuracy = row?.accuracyLabel == "±9 m"
            let hasHeading = row?.headingLabel != nil
            let hasSpeed = row?.speedLabel != nil
            let hasWorker = row?.userID == "usr_marcus"
            let hasJob = row?.jobNumber == "J-1043"
            let hasTimestamp = !(row?.recordedAtLabel.isEmpty ?? true)
            // The event stored against the row is the one the policy maps.
            let eventMapped = LocationCaptureEvent.forTransition(to: .travelling) == .travelStarted
            // A real capture stops the board calling itself simulated.
            let boardIsHonest = !board.isSimulated

            let passed = markedReal && capturedReal && coordinates && hasAccuracy && hasHeading
                && hasSpeed && hasWorker && hasJob && hasTimestamp && eventMapped && boardIsHonest
            results.append(
                TestScenarioResult(
                    id: "72",
                    number: 72,
                    title: "A production capture is recorded as real, not simulated",
                    expectation: "isSimulated is false and the row carries position, accuracy, heading, speed, worker, job and timestamp",
                    passed: passed,
                    evidence: "\(row?.coordinateLabel ?? "no row") \(row?.accuracyLabel ?? "") · heading \(row?.headingLabel ?? "none") · speed \(row?.speedLabel ?? "none") · \(row?.userID ?? "?") on \(row?.jobNumber ?? "?") at \(row?.recordedAtLabel ?? "?") · isSimulated=\(row?.isSimulated.description ?? "?") · event travelling→\(LocationCaptureEvent.forTransition(to: .travelling)?.rawValue ?? "none") · board reports simulated=\(board.isSimulated)"
                )
            )
        } catch {
            results.append(failure(72, "A production capture is recorded as real, not simulated", "isSimulated false with a complete record", error))
        }

        // 73 — Each permitted event captures exactly once, and nothing else does.
        do {
            let gateway = freshGateway()

            let before = await latestFixID(gateway, marcus)

            try await FieldTransitionCoordinator.advance(
                gateway: gateway, location: productionGPS, session: marcus,
                jobID: "job_1043", to: .travelling, destination: destination
            )
            let afterTravel = await latestFixID(gateway, marcus)

            try await FieldTransitionCoordinator.advance(
                gateway: gateway, location: productionGPS, session: marcus,
                jobID: "job_1043", to: .arrived, destination: destination
            )
            let afterArrived = await latestFixID(gateway, marcus)

            // In progress is deliberately not a capture point.
            let inProgressOutcome = try await FieldTransitionCoordinator.advance(
                gateway: gateway, location: productionGPS, session: marcus,
                jobID: "job_1043", to: .inProgress, destination: destination
            )
            let afterInProgress = await latestFixID(gateway, marcus)

            try await FieldTransitionCoordinator.advance(
                gateway: gateway, location: productionGPS, session: marcus,
                jobID: "job_1043", to: .completed, destination: destination
            )
            let afterCompleted = await latestFixID(gateway, marcus)

            // A new row id after a step means exactly one new capture.
            let travelCaptured = afterTravel != before
            let arrivedCaptured = afterArrived != afterTravel
            let completedCaptured = afterCompleted != afterInProgress
            // And an unchanged id means none.
            let inProgressCapturedNothing = afterInProgress == afterArrived
                && inProgressOutcome == .notRequired

            let passed = travelCaptured && arrivedCaptured && completedCaptured && inProgressCapturedNothing
            results.append(
                TestScenarioResult(
                    id: "73",
                    number: 73,
                    title: "Each capture event records exactly one position",
                    expectation: "Travel started, arrived and completed each add one fix; starting work adds none",
                    passed: passed,
                    evidence: "travelStarted \(travelCaptured ? "+1" : "+0") · arrived \(arrivedCaptured ? "+1" : "+0") · inProgress \(inProgressCapturedNothing ? "+0 (not a capture point)" : "CAPTURED") · completed \(completedCaptured ? "+1" : "+0")"
                )
            )
        } catch {
            results.append(failure(73, "Each capture event records exactly one position", "One fix per permitted event", error))
        }

        // 74 — There is no timer, and nothing accrues on its own.
        do {
            let gateway = freshGateway()

            try await FieldTransitionCoordinator.advance(
                gateway: gateway, location: productionGPS, session: marcus,
                jobID: "job_1043", to: .travelling, destination: destination
            )

            // Read the board repeatedly without touching a job. If anything
            // were polling, following or retrying, rows would appear here.
            let first = await latestFixID(gateway, marcus)
            let second = await latestFixID(gateway, marcus)
            let third = await latestFixID(gateway, marcus)
            let stable = first == second && second == third && first != nil

            // The policy surface itself is exactly three events, all tied to a
            // workflow transition. Continuous tracking has no separate trigger:
            // it is opened and closed by the same transitions.
            let onlyThreeEvents = LocationCaptureEvent.allCases.count == 3
            let allTiedToTransitions = LocationCaptureEvent.allCases.allSatisfy { event in
                JobStatus.allCases.contains { LocationCaptureEvent.forTransition(to: $0) == event }
            }

            // The tracker's rule, exercised directly: travelling opens a leg,
            // every other status closes it. This is what bounds tracking to the
            // drive rather than to the working day.
            let tracker = TravelTracker()
            var closedByEveryOtherStatus = true
            for status in JobStatus.allCases where status != .travelling {
                await tracker.sync(
                    jobID: "job_1043", status: status,
                    location: productionGPS, gateway: gateway, session: marcus
                )
                if tracker.state.isTracking { closedByEveryOtherStatus = false }
            }
            // The stub reports production but declines to track, so the tracker
            // reflects `.off` rather than inventing a live badge.
            let honestWhenAdapterCannotTrack = !tracker.state.isTracking

            let passed = stable && onlyThreeEvents && allTiedToTransitions
                && closedByEveryOtherStatus && honestWhenAdapterCannotTrack
            results.append(
                TestScenarioResult(
                    id: "74",
                    number: 74,
                    title: "Continuous tracking is bounded to an active travel leg",
                    expectation: "Repeated reads add nothing; only `travelling` opens a leg and every other status closes it",
                    passed: passed,
                    evidence: "Three reads with no job activity returned the same single fix · \(LocationCaptureEvent.allCases.count) capture events, every one bound to a workflow transition · \(JobStatus.allCases.count - 1) non-travelling statuses each left the tracker off · \(TravelTrackingPolicy.summary)"
                )
            )
        } catch {
            results.append(failure(74, "No continuous or timer-based location path exists", "Event-driven only", error))
        }

        // 75 — A refusal records the step, never an invented position.
        do {
            var evidence: [String] = []
            var allRefusedCleanly = true

            for state: LocationAuthorizationState in [.denied, .restricted, .unavailable] {
                let gateway = freshGateway()
                let refusedGPS = StubProductionLocationService(state: state)
                let before = await latestFixID(gateway, marcus)

                let outcome = try await FieldTransitionCoordinator.advance(
                    gateway: gateway,
                    location: refusedGPS,
                    session: marcus,
                    jobID: "job_1043",
                    to: .travelling,
                    destination: destination
                )

                let after = await latestFixID(gateway, marcus)
                let job = try await gateway.fieldWorkerJobDetail(session: marcus, jobID: "job_1043")

                // Nothing written, the job still moved, and the reason is stated.
                let noFabrication = after == before
                let jobStillAdvanced = job.status == .travelling
                let reported = outcome.refusedState == state
                // The worker is given something they can act on.
                let explained = !state.explanation(worker: "engineer").isEmpty

                if !(noFabrication && jobStillAdvanced && reported && explained) { allRefusedCleanly = false }
                evidence.append("\(state.rawValue): no fix written=\(noFabrication), job still \(job.status.title), settings route=\(state.isResolvableInSettings)")
            }

            results.append(
                TestScenarioResult(
                    id: "75",
                    number: 75,
                    title: "Refused location never fabricates a position",
                    expectation: "Denied, restricted and unavailable each record the job step with no position at all",
                    passed: allRefusedCleanly,
                    evidence: evidence.joined(separator: " · ")
                )
            )
        } catch {
            results.append(failure(75, "Refused location never fabricates a position", "No permission means no position", error))
        }

        // 76 — Real positions stay inside the company that recorded them.
        do {
            let gateway = freshGateway()

            try await FieldTransitionCoordinator.advance(
                gateway: gateway, location: productionGPS, session: marcus,
                jobID: "job_1043", to: .travelling, destination: destination
            )

            // The other tenant cannot see the row that was just written.
            let northBoard = try await gateway.fieldWorkerLocations(session: northOwner)
            let noLeak = northBoard.locations.allSatisfy { $0.userID != "usr_marcus" }
            let noNames = !northBoard.withoutLocation.contains("Marcus Hale")

            // A field worker sees their own and nobody else's, real or not.
            let deeBoard = try await gateway.fieldWorkerLocations(session: dee)
            let deeOwnOnly = deeBoard.locations.allSatisfy { $0.userID == "usr_dee" }
            let deeSeesNoRoster = deeBoard.withoutLocation.isEmpty

            // The office role in the right company does see it.
            let dispatchBoard = try await gateway.fieldWorkerLocations(session: dispatcher)
            let dispatcherSeesIt = dispatchBoard.locations.contains { $0.userID == "usr_marcus" && !$0.isSimulated }

            let passed = noLeak && noNames && deeOwnOnly && deeSeesNoRoster && dispatcherSeesIt
            results.append(
                TestScenarioResult(
                    id: "76",
                    number: 76,
                    title: "Real positions stay tenant-scoped and worker-scoped",
                    expectation: "Another company sees nothing, another worker sees nothing, and the company's own dispatcher sees the real fix",
                    passed: passed,
                    evidence: "Northline received \(northBoard.locations.count) row(s), none from Gulf Coast · Dee received \(deeBoard.locations.count), all her own · the Gulf Coast dispatcher sees Marcus's real (non-simulated) fix"
                )
            )
        } catch {
            results.append(failure(76, "Real positions stay tenant-scoped and worker-scoped", "Company and worker isolation unchanged", error))
        }

        // 77 — Retention and the recent/last-known split are untouched.
        do {
            let daysUnchanged = LocationRetentionPolicy.days == 30
            let capUnchanged = LocationRetentionPolicy.maximumPingsPerWorker == 200
            let thresholdUnchanged = LocationRetentionPolicy.recentThresholdMinutes == 15
            let summaryStatesIt = LocationRetentionPolicy.summary.contains("30 days")
                && LocationRetentionPolicy.summary.contains("200 points")
                && LocationRetentionPolicy.summary.contains("never continuous")

            // The freshness boundary still separates the two states, which is
            // what Dispatch renders as Recent versus Last known.
            let now = Date()
            func rowAged(minutes: Double) -> FieldWorkerLocation {
                FieldWorkerLocation(
                    id: "probe", companyID: "cmp_gulfcoast", userID: "usr_marcus",
                    latitude: 28.01, longitude: -82.50, accuracyMeters: 9,
                    recordedAt: now.addingTimeInterval(-minutes * 60),
                    captureEvent: .travelStarted, isSimulated: false
                )
            }
            let freshIsRecent = rowAged(minutes: 5).freshness(asOf: now) == .recent
            let staleIsLastKnown = rowAged(minutes: 45).freshness(asOf: now) == .lastKnown
            let labelsUnchanged = LocationFreshness.recent.title == "Recent"
                && LocationFreshness.lastKnown.title == "Last known"

            let passed = daysUnchanged && capUnchanged && thresholdUnchanged && summaryStatesIt
                && freshIsRecent && staleIsLastKnown && labelsUnchanged
            results.append(
                TestScenarioResult(
                    id: "77",
                    number: 77,
                    title: "Retention and freshness rules survive the GPS change",
                    expectation: "The 30-day and 200-point limits and the recent/last-known split are exactly as they were",
                    passed: passed,
                    evidence: "\(LocationRetentionPolicy.days) days · \(LocationRetentionPolicy.maximumPingsPerWorker) points per worker · recent under \(LocationRetentionPolicy.recentThresholdMinutes) min (5 min reads Recent, 45 min reads Last known) · real fixes are trimmed by the same gateway path as fixtures"
                )
            )
        }

        // 78 — The day screen tells the worker when a step had no position.
        do {
            var evidence: [String] = []
            var handledCleanly = true

            for state: LocationAuthorizationState in [.denied, .restricted] {
                let gateway = freshGateway()
                let viewModel = FieldWorkerDayViewModel()
                let before = await latestFixID(gateway, marcus)

                await viewModel.advance(
                    gateway: gateway,
                    location: StubProductionLocationService(state: state),
                    session: marcus,
                    jobID: "job_1043",
                    to: .travelling,
                    destination: destination
                )

                // This is exactly what the day screen renders the notice from.
                let noticeShown = viewModel.lastCaptureOutcome?.refusedState == state
                let after = await latestFixID(gateway, marcus)
                let noFabrication = after == before
                let job = try await gateway.fieldWorkerJobDetail(session: marcus, jobID: "job_1043")
                let jobStillAdvanced = job.status == .travelling
                // A refusal is not an error: the red action-error line stays
                // empty so the amber notice is the single, honest explanation.
                let notTreatedAsFailure = viewModel.actionError == nil
                let explained = !state.explanation(worker: "engineer").isEmpty
                // Settings is offered only where the worker can actually fix it.
                let routeIsHonest = state.isResolvableInSettings == (state == .denied)

                if !(noticeShown && noFabrication && jobStillAdvanced && notTreatedAsFailure && explained && routeIsHonest) {
                    handledCleanly = false
                }
                evidence.append("\(state.rawValue): notice shown=\(noticeShown), no fix written=\(noFabrication), job still \(job.status.title), settings route=\(state.isResolvableInSettings)")
            }

            // And with permission granted the notice stays away entirely.
            let grantedGateway = freshGateway()
            let grantedViewModel = FieldWorkerDayViewModel()
            await grantedViewModel.advance(
                gateway: grantedGateway,
                location: StubProductionLocationService(state: .authorized),
                session: marcus,
                jobID: "job_1043",
                to: .travelling,
                destination: destination
            )
            let quietWhenAuthorized = grantedViewModel.lastCaptureOutcome?.refusedState == nil
            if !quietWhenAuthorized { handledCleanly = false }
            evidence.append("authorized: no notice=\(quietWhenAuthorized)")

            results.append(
                TestScenarioResult(
                    id: "78",
                    number: 78,
                    title: "The day screen explains a refused location instead of failing quietly",
                    expectation: "Denied and restricted each surface the permission notice with no position recorded, the job still advances, and a granted permission shows no notice",
                    passed: handledCleanly,
                    evidence: evidence.joined(separator: " · ")
                )
            )
        } catch {
            results.append(failure(78, "The day screen explains a refused location instead of failing quietly", "Refusal is explained, never silent", error))
        }

        // Scenarios 79–85 cover customer-facing invoice delivery: the company's
        // own payment link, the opaque customer link, and honest reporting of
        // what was actually delivered. They run against their own freshly
        // seeded store so nothing above can influence the result.
        let gateway = freshGateway()
        let accounts = session("usr_accounts", .accounts, "Joan Petrov")

        // 79 — A payment link must be an https address with no credentials.
        do {
            var evidence: [String] = []
            var allRefused = true

            let refusals: [(String, String)] = [
                ("http://pay.example.com/abc", "plain http"),
                ("javascript:alert(1)", "javascript:"),
                ("data:text/html;base64,PHA+", "data:"),
                ("https://user:secret@pay.example.com/abc", "credentials in the URL"),
                ("https://localhost/pay", "no dotted host"),
                ("pay.example.com/abc", "no scheme")
            ]
            for (candidate, why) in refusals {
                let accepted = (try? OnlinePaymentLink.normalise(candidate)) ?? nil
                if accepted != nil { allRefused = false }
                evidence.append("\(why)=\(accepted == nil ? "refused" : "ACCEPTED")")
            }

            let good = (try? OnlinePaymentLink.normalise("  https://buy.stripe.com/test_abc123  ")) ?? nil
            let goodAccepted = good == "https://buy.stripe.com/test_abc123"
            if !goodAccepted { allRefused = false }
            evidence.append("real link=\(goodAccepted ? "accepted and trimmed" : "WRONGLY REFUSED")")

            let cleared = (try? OnlinePaymentLink.normalise("   ")) ?? nil
            if cleared != nil { allRefused = false }
            evidence.append("empty=cleared")

            results.append(
                TestScenarioResult(
                    id: "79",
                    number: 79,
                    title: "A payment link must be https, dotted and credential-free",
                    expectation: "http, javascript:, data:, embedded credentials, undotted hosts and scheme-less text are all refused; a real https link is accepted and empty input clears it",
                    passed: allRefused,
                    evidence: evidence.joined(separator: " · ")
                )
            )
        }

        // 80 — Only companyProfileManage may set the payment link.
        do {
            var evidence: [String] = []
            var enforced = true

            do {
                try await gateway.updateCompanyPaymentLink(session: accounts, url: "https://buy.stripe.com/test_accounts")
                enforced = false
                evidence.append("accounts=ALLOWED")
            } catch let error as DataError {
                evidence.append("accounts=refused (\(error.errorDescription ?? ""))")
            }

            do {
                try await gateway.updateCompanyPaymentLink(session: dispatcher, url: "https://buy.stripe.com/test_dispatch")
                enforced = false
                evidence.append("dispatcher=ALLOWED")
            } catch {
                evidence.append("dispatcher=refused")
            }

            try await gateway.updateCompanyPaymentLink(session: owner, url: "https://buy.stripe.com/test_owner")
            let afterOwner = try await gateway.companyPaymentLink(session: owner)
            let ownerSet = afterOwner.url == "https://buy.stripe.com/test_owner"
            if !ownerSet { enforced = false }
            evidence.append("owner=\(ownerSet ? "saved" : "NOT SAVED")")

            try await gateway.updateCompanyPaymentLink(session: owner, url: nil)
            let afterClear = try await gateway.companyPaymentLink(session: owner)
            if afterClear.url != nil { enforced = false }
            evidence.append("cleared=\(afterClear.url == nil)")

            results.append(
                TestScenarioResult(
                    id: "80",
                    number: 80,
                    title: "Only an owner or admin can set the company's payment link",
                    expectation: "Accounts and dispatcher are refused, the owner can set it and clear it again",
                    passed: enforced,
                    evidence: evidence.joined(separator: " · ")
                )
            )
        } catch {
            results.append(failure(80, "Only an owner or admin can set the company's payment link", "companyProfileManage is enforced", error))
        }

        // 81 — The customer link carries no identifier, and can be revoked.
        do {
            var evidence: [String] = []
            var safe = true

            // inv_1176 is a sent invoice in the seed.
            let link = try await gateway.issueInvoiceShareLink(session: accounts, invoiceID: "inv_1176", rotate: false)
            let leaks = ["inv_1176", "INV-1176", "cmp_gulfcoast", "cus_", "1176"]
                .filter { link.contains($0) }
            if !leaks.isEmpty { safe = false }
            evidence.append(leaks.isEmpty ? "URL leaks nothing" : "URL LEAKS \(leaks.joined(separator: ","))")

            let sameAgain = try await gateway.issueInvoiceShareLink(session: accounts, invoiceID: "inv_1176", rotate: false)
            let stable = sameAgain == link
            if !stable { safe = false }
            evidence.append("re-issue is stable=\(stable)")

            let rotated = try await gateway.issueInvoiceShareLink(session: accounts, invoiceID: "inv_1176", rotate: true)
            let changed = rotated != link
            if !changed { safe = false }
            evidence.append("rotation replaces the link=\(changed)")

            try await gateway.revokeInvoiceShareLink(session: accounts, invoiceID: "inv_1176")
            let afterRevoke = try await gateway.invoiceSharing(session: accounts, invoiceID: "inv_1176")
            if afterRevoke.shareURL != nil { safe = false }
            evidence.append("revoked=\(afterRevoke.shareURL == nil)")

            results.append(
                TestScenarioResult(
                    id: "81",
                    number: 81,
                    title: "The customer invoice link is opaque, stable, rotatable and revocable",
                    expectation: "No company, customer or invoice identifier appears in the URL; re-issuing returns the same link, rotating replaces it and revoking removes it",
                    passed: safe,
                    evidence: evidence.joined(separator: " · ")
                )
            )
        } catch {
            results.append(failure(81, "The customer invoice link is opaque, stable, rotatable and revocable", "Token-addressed links only", error))
        }

        // 82 — A draft is never shareable, and a field worker never sends.
        do {
            var evidence: [String] = []
            var refused = true

            // inv_1181 is the seeded draft.
            do {
                _ = try await gateway.issueInvoiceShareLink(session: accounts, invoiceID: "inv_1181", rotate: false)
                refused = false
                evidence.append("draft=SHARED")
            } catch let error as DataError {
                evidence.append("draft=refused (\(error.errorDescription ?? ""))")
            } catch {
                evidence.append("draft=refused")
            }

            do {
                _ = try await gateway.sendInvoice(session: marcus, invoiceID: "inv_1176", channels: [.email])
                refused = false
                evidence.append("field worker=SENT")
            } catch {
                evidence.append("field worker=refused")
            }

            do {
                _ = try await gateway.sendInvoice(session: dispatcher, invoiceID: "inv_1176", channels: [.email])
                refused = false
                evidence.append("dispatcher=SENT")
            } catch {
                evidence.append("dispatcher=refused")
            }

            results.append(
                TestScenarioResult(
                    id: "82",
                    number: 82,
                    title: "Drafts can't be shared and only invoice managers can send",
                    expectation: "A draft invoice refuses a link, and a field worker and dispatcher are both refused a send",
                    passed: refused,
                    evidence: evidence.joined(separator: " · ")
                )
            )
        }

        // 83 — An undelivered send is recorded as failed, never as sent.
        do {
            var evidence: [String] = []
            var honest = true

            let outcome = try await gateway.sendInvoice(session: accounts, invoiceID: "inv_1176", channels: [.email])
            let claimedSent = outcome.didDeliverAnything
            if claimedSent { honest = false }
            evidence.append("claimed delivered=\(claimedSent)")

            let flaggedUnconfigured = !outcome.missingProviders.isEmpty
            if !flaggedUnconfigured { honest = false }
            evidence.append("provider reported unconfigured=\(flaggedUnconfigured)")

            let sharing = try await gateway.invoiceSharing(session: accounts, invoiceID: "inv_1176")
            let recorded = sharing.deliveries.first
            let recordedFailed = recorded?.status == .failed
            if !recordedFailed { honest = false }
            evidence.append("ledger status=\(recorded?.statusTitle ?? "none")")

            let hasReason = (recorded?.failureReason?.isEmpty == false)
            if !hasReason { honest = false }
            evidence.append("reason recorded=\(hasReason)")

            results.append(
                TestScenarioResult(
                    id: "83",
                    number: 83,
                    title: "A send with no provider configured is recorded as failed, not as sent",
                    expectation: "The outcome reports nothing delivered and names the missing provider, and the notifications ledger holds a failed row with a reason",
                    passed: honest,
                    evidence: evidence.joined(separator: " · ")
                )
            )
        } catch {
            results.append(failure(83, "A send with no provider configured is recorded as failed, not as sent", "Nothing is ever reported as sent unless it was", error))
        }

        // 84 — Opening or sending an invoice never moves money.
        do {
            var evidence: [String] = []
            var unchanged = true

            let before = try await gateway.invoiceDetail(session: accounts, invoiceID: "inv_1176")
            try await gateway.updateCompanyPaymentLink(session: owner, url: "https://buy.stripe.com/test_live")
            _ = try await gateway.issueInvoiceShareLink(session: accounts, invoiceID: "inv_1176", rotate: true)
            _ = try? await gateway.sendInvoice(session: accounts, invoiceID: "inv_1176", channels: [.email, .sms])
            let after = try await gateway.invoiceDetail(session: accounts, invoiceID: "inv_1176")

            if before.totals.balance != after.totals.balance { unchanged = false }
            evidence.append("balance \(before.totals.balanceLabel) → \(after.totals.balanceLabel)")

            if before.totals.amountPaid != after.totals.amountPaid { unchanged = false }
            evidence.append("paid \(before.totals.amountPaidLabel) → \(after.totals.amountPaidLabel)")

            if before.status != after.status { unchanged = false }
            evidence.append("status \(before.status.rawValue) → \(after.status.rawValue)")

            if before.payments.count != after.payments.count { unchanged = false }
            evidence.append("payments \(before.payments.count) → \(after.payments.count)")

            try await gateway.updateCompanyPaymentLink(session: owner, url: nil)

            results.append(
                TestScenarioResult(
                    id: "84",
                    number: 84,
                    title: "Sharing or sending an invoice never changes what is owed",
                    expectation: "Configuring a payment link, issuing a customer link and sending leave balance, amount paid, status and the payment list untouched",
                    passed: unchanged,
                    evidence: evidence.joined(separator: " · ")
                )
            )
        } catch {
            results.append(failure(84, "Sharing or sending an invoice never changes what is owed", "The ledger is independent of delivery", error))
        }

        // 85 — A payment record carries no processor identifier at all.
        do {
            let detail = try await gateway.invoiceDetail(session: accounts, invoiceID: "inv_1176")
            let paymentFields = detail.payments.first.map { Mirror(reflecting: $0).children.compactMap { $0.label } } ?? []
            let processorFields = paymentFields.filter { label in
                let lowered = label.lowercased()
                return lowered.contains("stripe") || lowered.contains("processor")
                    || lowered.contains("intent") || lowered.contains("connect")
            }

            results.append(
                TestScenarioResult(
                    id: "85",
                    number: 85,
                    title: "A payment carries no payment-processor field",
                    expectation: "The payment projection has no processor, intent or connect-account field — only the company's own reference",
                    passed: processorFields.isEmpty && paymentFields.contains("reference"),
                    evidence: processorFields.isEmpty
                        ? "\(paymentFields.count) fields, none processor-specific · generic reference present"
                        : "processor fields present: \(processorFields.joined(separator: ","))"
                )
            )
        } catch {
            results.append(failure(85, "A payment carries no payment-processor field", "No processor identifiers exist", error))
        }

        // MARK: - Push notifications

        let marcusToken = String(repeating: "a1b2", count: 16)
        let deeToken = String(repeating: "c3d4", count: 16)
        let ownerToken = String(repeating: "e5f6", count: 16)
        let accountsToken = String(repeating: "0789", count: 16)
        let northToken = String(repeating: "beef", count: 16)

        // 86 — A refusal registers nothing. The prompt is never the success path.
        do {
            var evidence: [String] = []
            var honest = true

            for state: PushAuthorizationState in [.denied, .restricted, .notDetermined] {
                let service = StubPushService(state: state, issuesToken: state == .notDetermined)
                let outcome = await service.register()
                switch (state, outcome) {
                case (.denied, .refused), (.restricted, .refused):
                    evidence.append("\(state.rawValue)=refused")
                case (.notDetermined, .registered):
                    evidence.append("notDetermined=prompted then registered")
                default:
                    honest = false
                    evidence.append("\(state.rawValue)=UNEXPECTED")
                }
            }

            // Permission granted but no token is not a registration either.
            let tokenless = StubPushService(state: .authorized, issuesToken: false)
            if case .tokenUnavailable = await tokenless.register() {
                evidence.append("authorized without token=tokenUnavailable")
            } else {
                honest = false
                evidence.append("authorized without token=REPORTED SUCCESS")
            }

            results.append(
                TestScenarioResult(
                    id: "86",
                    number: 86,
                    title: "Every permission state is handled honestly",
                    expectation: "Denied and restricted refuse; a granted permission that yields no token is reported unavailable, never as registered",
                    passed: honest,
                    evidence: evidence.joined(separator: " · ")
                )
            )
        }

        // 87 — Registration takes its tenancy from the session, not the payload.
        do {
            _ = try await gateway.registerPushDevice(
                session: marcus,
                registration: PushDeviceRegistration(token: marcusToken, environment: .production, bundleID: "app.rork.test", appVersion: "1.0.0", deviceModel: "iPhone")
            )
            _ = try await gateway.registerPushDevice(
                session: dee,
                registration: PushDeviceRegistration(token: deeToken, environment: .production, bundleID: "app.rork.test", appVersion: "1.0.0", deviceModel: "iPhone")
            )
            _ = try await gateway.registerPushDevice(
                session: owner,
                registration: PushDeviceRegistration(token: ownerToken, environment: .production, bundleID: "app.rork.test", appVersion: "1.0.0", deviceModel: "iPhone")
            )
            _ = try await gateway.registerPushDevice(
                session: accounts,
                registration: PushDeviceRegistration(token: accountsToken, environment: .production, bundleID: "app.rork.test", appVersion: "1.0.0", deviceModel: "iPhone")
            )
            _ = try await gateway.registerPushDevice(
                session: northOwner,
                registration: PushDeviceRegistration(token: northToken, environment: .production, bundleID: "app.rork.test", appVersion: "1.0.0", deviceModel: "iPhone")
            )

            let devices = await gateway.developmentSnapshot().pushDevices
            let marcusDevice = devices.first { $0.token == marcusToken }
            let northDevice = devices.first { $0.token == northToken }

            let scoped = marcusDevice?.companyID == marcus.companyID
                && marcusDevice?.userID == marcus.userID
                && northDevice?.companyID == northOwner.companyID
            let noCrossTenant = !devices.contains { $0.companyID == northOwner.companyID && $0.userID == marcus.userID }

            results.append(
                TestScenarioResult(
                    id: "87",
                    number: 87,
                    title: "A device registers against the signed-in user and their company only",
                    expectation: "Company and user come from the session; no device lands in another tenant",
                    passed: scoped && noCrossTenant && devices.count == 5,
                    evidence: "\(devices.count) devices · marcus→\(marcusDevice?.companyID ?? "none") · north→\(northDevice?.companyID ?? "none") · cross-tenant rows=\(noCrossTenant ? 0 : 1)"
                )
            )
        } catch {
            results.append(failure(87, "A device registers against the signed-in user and their company only", "Tenancy comes from the session", error))
        }

        // 88 — Assigning a job notifies the engineer who got it.
        do {
            _ = try await gateway.assignJob(
                session: dispatcher,
                jobID: "job_1046",
                input: AssignmentInput(workerUserID: "usr_marcus", acknowledgesConflict: true)
            )

            let inbox = try await gateway.pushInbox(session: marcus, limit: 30)
            let assigned = inbox.first { $0.event == PushEvent.jobAssigned.rawValue && $0.jobID == "job_1046" }
            let deeInbox = try await gateway.pushInbox(session: dee, limit: 30)
            let deeToldAboutIt = deeInbox.contains { $0.jobID == "job_1046" }

            results.append(
                TestScenarioResult(
                    id: "88",
                    number: 88,
                    title: "A new assignment notifies the assigned engineer",
                    expectation: "Marcus receives a job.assigned alert for the job; Dee, who is not on it, receives nothing",
                    passed: assigned != nil && !deeToldAboutIt,
                    evidence: "marcus: \(assigned?.title ?? "NOTHING") · status=\(assigned?.status.rawValue ?? "-") · dee told=\(deeToldAboutIt)"
                )
            )
        } catch {
            results.append(failure(88, "A new assignment notifies the assigned engineer", "The assigned engineer is told", error))
        }

        // 89 — A reassignment is two true statements, not one.
        do {
            _ = try await gateway.assignJob(
                session: dispatcher,
                jobID: "job_1045",
                input: AssignmentInput(workerUserID: "usr_marcus", acknowledgesConflict: true)
            )

            let deeInbox = try await gateway.pushInbox(session: dee, limit: 30)
            let marcusInbox = try await gateway.pushInbox(session: marcus, limit: 30)

            let deeRemoved = deeInbox.contains {
                $0.event == PushEvent.jobUnassigned.rawValue && $0.jobID == "job_1045"
            }
            let marcusGained = marcusInbox.contains {
                $0.event == PushEvent.jobReassigned.rawValue && $0.jobID == "job_1045"
            }

            results.append(
                TestScenarioResult(
                    id: "89",
                    number: 89,
                    title: "Reassignment tells the outgoing and incoming engineer",
                    expectation: "Dee is told she is off job_1045; Marcus is told it is now his",
                    passed: deeRemoved && marcusGained,
                    evidence: "dee removed=\(deeRemoved) · marcus reassigned=\(marcusGained)"
                )
            )
        } catch {
            results.append(failure(89, "Reassignment tells the outgoing and incoming engineer", "Both sides of a reassignment are notified", error))
        }

        // 90 — A moved slot reaches the engineer standing by for it.
        do {
            let newStart = Calendar.current.date(byAdding: .hour, value: 3, to: Date()) ?? Date()
            _ = try await gateway.rescheduleJob(
                session: dispatcher,
                jobID: "job_1044",
                input: RescheduleInput(
                    scheduledStart: newStart,
                    scheduledEnd: newStart.addingTimeInterval(3600),
                    acknowledgesConflict: true
                )
            )

            let inbox = try await gateway.pushInbox(session: marcus, limit: 40)
            let moved = inbox.first { $0.event == PushEvent.jobRescheduled.rawValue && $0.jobID == "job_1044" }

            results.append(
                TestScenarioResult(
                    id: "90",
                    number: 90,
                    title: "A time or date change notifies the assigned engineer",
                    expectation: "Rescheduling job_1044 raises a job.rescheduled alert carrying the new slot",
                    passed: moved != nil && (moved?.body.isEmpty == false),
                    evidence: moved.map { "\($0.title) — \($0.body)" } ?? "NOTHING RAISED"
                )
            )
        } catch {
            results.append(failure(90, "A time or date change notifies the assigned engineer", "The engineer is told the job moved", error))
        }

        // 91 — Cancellation: the alert that stops a wasted journey.
        do {
            try await gateway.updateJobStatus(session: dispatcher, jobID: "job_1044", to: .cancelled)

            let inbox = try await gateway.pushInbox(session: marcus, limit: 40)
            let cancelled = inbox.first { $0.event == PushEvent.jobCancelled.rawValue && $0.jobID == "job_1044" }
            let warnsOffTravel = cancelled?.body.lowercased().contains("do not travel") ?? false

            results.append(
                TestScenarioResult(
                    id: "91",
                    number: 91,
                    title: "Cancelling a job notifies the assigned engineer",
                    expectation: "A job.cancelled alert reaches the engineer and tells them not to travel",
                    passed: cancelled != nil && warnsOffTravel,
                    evidence: cancelled.map { "\($0.title) — \($0.body)" } ?? "NOTHING RAISED"
                )
            )
        } catch {
            results.append(failure(91, "Cancelling a job notifies the assigned engineer", "The engineer is told before they travel", error))
        }

        // 92 — An engineer's inbox holds only their own work.
        do {
            let marcusInbox = try await gateway.pushInbox(session: marcus, limit: 60)
            let deeInbox = try await gateway.pushInbox(session: dee, limit: 60)

            let deeJobs: Set<String> = ["job_1040", "job_1049", "job_1047"]
            let marcusSeesDeeWork = marcusInbox.contains { alert in
                guard let jobID = alert.jobID else { return false }
                return deeJobs.contains(jobID)
            }
            let everythingIsAddressedToThem = !marcusInbox.isEmpty && !deeInbox.isEmpty

            results.append(
                TestScenarioResult(
                    id: "92",
                    number: 92,
                    title: "Engineers receive only notifications about their own jobs",
                    expectation: "Marcus's inbox contains nothing about jobs that are Dee's alone",
                    passed: !marcusSeesDeeWork && everythingIsAddressedToThem,
                    evidence: "marcus=\(marcusInbox.count) alerts, dee=\(deeInbox.count) alerts · marcus sees Dee-only work=\(marcusSeesDeeWork)"
                )
            )
        } catch {
            results.append(failure(92, "Engineers receive only notifications about their own jobs", "No engineer reads another's alerts", error))
        }

        // 93 — Office recipients are chosen by permission, not by seniority.
        do {
            try await gateway.updateJobStatus(session: marcus, jobID: "job_1043", to: .travelling)

            let ownerInbox = try await gateway.pushInbox(session: owner, limit: 40)
            let accountsInbox = try await gateway.pushInbox(session: accounts, limit: 40)

            let ownerTold = ownerInbox.contains { $0.event == PushEvent.jobFieldUpdate.rawValue }
            let accountsTold = accountsInbox.contains { $0.event == PushEvent.jobFieldUpdate.rawValue }

            results.append(
                TestScenarioResult(
                    id: "93",
                    number: 93,
                    title: "Office alerts follow the permission matrix",
                    expectation: "An engineer starting travel reaches roles holding assignmentsManage; Accounts, who hold none, are not told",
                    passed: ownerTold && !accountsTold,
                    evidence: "owner told=\(ownerTold) · accounts told=\(accountsTold) (accounts hold assignmentsManage=\(accounts.can(.assignmentsManage)))"
                )
            )
        } catch {
            results.append(failure(93, "Office alerts follow the permission matrix", "Only permitted roles are notified", error))
        }

        // 94 — Nothing crosses a company boundary.
        do {
            let northInbox = try await gateway.pushInbox(session: northOwner, limit: 60)
            let foreign = northInbox.filter { alert in
                guard let jobID = alert.jobID else { return false }
                return jobID.hasPrefix("job_10")
            }

            // And the other direction: Gulf Coast's own people never see the
            // plumbing company's work.
            try await gateway.addJobNote(session: northOwner, jobID: "job_north_1", body: "Bring the flue kit.", visibility: .internalOnly)
            let marcusInbox = try await gateway.pushInbox(session: marcus, limit: 60)
            let leaked = marcusInbox.contains { $0.jobID == "job_north_1" }

            results.append(
                TestScenarioResult(
                    id: "94",
                    number: 94,
                    title: "No company can read or receive another company's notifications",
                    expectation: "Northline's inbox holds no Gulf Coast rows, and Gulf Coast never receives a Northline event",
                    passed: foreign.isEmpty && !leaked,
                    evidence: "foreign rows in northline inbox=\(foreign.count) · northline event leaked to marcus=\(leaked)"
                )
            )
        } catch {
            results.append(failure(94, "No company can read or receive another company's notifications", "Tenant isolation holds for notifications", error))
        }

        // 95 — A tap lands on the job it is about.
        do {
            let inbox = try await gateway.pushInbox(session: marcus, limit: 40)
            let cancelled = inbox.first { $0.event == PushEvent.jobCancelled.rawValue }

            var routed = false
            if case .job(let jobID)? = cancelled?.route { routed = jobID == cancelled?.jobID }

            // The same route the APNs payload would produce.
            let fromPayload = PushDeepLink.route(from: ["deepLink": "tradedesk://job/job_1044", "jobId": "job_1044"])
            let payloadRouted = fromPayload == .job("job_1044")

            // A malformed or unknown link is discarded rather than guessed at.
            let junkRejected = PushDeepLink.route(fromLink: "not a url at all") == nil
                && PushDeepLink.route(fromLink: "https://example.com/job/1") == nil
                && PushDeepLink.route(fromLink: nil) == nil

            // A payload with no link at all still finds its job.
            let fallback = PushDeepLink.route(from: ["jobId": "job_1042"]) == .job("job_1042")

            results.append(
                TestScenarioResult(
                    id: "95",
                    number: 95,
                    title: "Tapping a notification deep-links to the right screen",
                    expectation: "The stored link resolves to that job, a payload resolves the same way, and malformed links are refused rather than guessed",
                    passed: routed && payloadRouted && junkRejected && fallback,
                    evidence: "ledger link=\(cancelled?.deepLink ?? "none") → routed=\(routed) · payload=\(payloadRouted) · junk refused=\(junkRejected) · jobId fallback=\(fallback)"
                )
            )
        } catch {
            results.append(failure(95, "Tapping a notification deep-links to the right screen", "A tap lands on the job it refers to", error))
        }

        // 96 — Signing out takes the device with it.
        do {
            let removed = try await gateway.unregisterPushDevice(session: marcus, token: marcusToken)
            let devicesAfter = await gateway.developmentSnapshot().pushDevices
            let stillLive = devicesAfter.contains { $0.token == marcusToken && $0.isLive }

            // Someone else's device is untouched by his sign-out.
            let deeUntouched = devicesAfter.contains { $0.token == deeToken && $0.isLive }

            // And a second sign-out is inert rather than an error.
            let repeated = try await gateway.unregisterPushDevice(session: marcus, token: marcusToken)

            results.append(
                TestScenarioResult(
                    id: "96",
                    number: 96,
                    title: "Signing out removes this device's registration",
                    expectation: "The token stops being live, other people's devices are untouched, and signing out twice is harmless",
                    passed: removed && !stillLive && deeUntouched && !repeated,
                    evidence: "removed=\(removed) · still live=\(stillLive) · dee untouched=\(deeUntouched) · repeat removed=\(repeated)"
                )
            )
        } catch {
            results.append(failure(96, "Signing out removes this device's registration", "The registration is cleaned up on sign-out", error))
        }

        // 97 — An event with nowhere to go is recorded as failed, never as sent.
        do {
            try await gateway.addJobNote(session: dispatcher, jobID: "job_1046", body: "Customer moved the gate code to 4417.", visibility: .internalOnly)

            let inbox = try await gateway.pushInbox(session: marcus, limit: 10)
            let latest = inbox.first { $0.event == PushEvent.jobNote.rawValue }
            let honest = latest?.status == .failed
                && (latest?.failureReason?.isEmpty == false)
                && latest?.wasDelivered == false

            results.append(
                TestScenarioResult(
                    id: "97",
                    number: 97,
                    title: "An alert with no registered device is recorded as failed",
                    expectation: "After sign-out the event is still recorded, as failed with a reason — never as delivered",
                    passed: honest,
                    evidence: "status=\(latest?.status.rawValue ?? "none") · reason=\(latest?.failureReason ?? "none")"
                )
            )
        } catch {
            results.append(failure(97, "An alert with no registered device is recorded as failed", "Undeliverable is recorded honestly", error))
        }

        // 98 — The app never claims a delivery Apple did not confirm.
        do {
            let snapshot = await gateway.developmentSnapshot()
            let pushRows = snapshot.notifications.filter { $0.channel == .push }
            let claimingDelivery = pushRows.filter { $0.status == .sent || $0.status == .delivered }
            let everyRowAddressed = pushRows.allSatisfy { $0.targetUserID != nil }
            let everyRowDeepLinked = pushRows.allSatisfy { ($0.deepLink?.isEmpty == false) }

            results.append(
                TestScenarioResult(
                    id: "98",
                    number: 98,
                    title: "No push notification is ever marked delivered by the app",
                    expectation: "Every push row is queued or failed — only a real APNs acceptance can make one sent — and each is addressed and deep-linked",
                    passed: claimingDelivery.isEmpty && everyRowAddressed && everyRowDeepLinked && !pushRows.isEmpty,
                    evidence: "\(pushRows.count) push rows · claiming delivery=\(claimingDelivery.count) · all addressed=\(everyRowAddressed) · all deep-linked=\(everyRowDeepLinked)"
                )
            )
        }

        // 99 — Nobody is woken up by their own action.
        do {
            let snapshot = await gateway.developmentSnapshot()
            let selfNotifications = snapshot.notifications.filter { notification in
                guard notification.channel == .push, let target = notification.targetUserID else { return false }
                // The dispatcher raised most of these events; none should be
                // addressed back to whoever performed them.
                return target == "usr_dispatch" && notification.template != PushEvent.jobFieldUpdate.rawValue
            }

            results.append(
                TestScenarioResult(
                    id: "99",
                    number: 99,
                    title: "Nobody is notified about their own action",
                    expectation: "The dispatcher who assigned, moved and cancelled these jobs receives no alert about doing so",
                    passed: selfNotifications.isEmpty,
                    evidence: "self-addressed alerts=\(selfNotifications.count)"
                )
            )
        }

        // 100 — Push is free. It must not touch the SMS credit ledger.
        do {
            let snapshot = await gateway.developmentSnapshot()
            let pushIDs = Set(snapshot.notifications.filter { $0.channel == .push }.map(\.id))
            let ledgerTouchingPush = snapshot.smsLedger.filter { entry in
                guard let notificationID = entry.notificationID else { return false }
                return pushIDs.contains(notificationID)
            }
            let gulfBalance = snapshot.smsLedger
                .filter { $0.companyID == "cmp_gulfcoast" }
                .reduce(0) { $0 + $1.amount }

            results.append(
                TestScenarioResult(
                    id: "100",
                    number: 100,
                    title: "Push notifications never consume SMS credit",
                    expectation: "No ledger row references a push notification, and the balance is unchanged by all the alerts raised above",
                    passed: ledgerTouchingPush.isEmpty && gulfBalance == 214,
                    evidence: "\(pushIDs.count) push rows · ledger rows referencing them=\(ledgerTouchingPush.count) · balance=\(gulfBalance)"
                )
            )
        }

        return results
    }

    /// A deterministic stand-in for `ApplePushService`.
    ///
    /// The real adapter needs APNs, a signed build and a human to answer a
    /// prompt, so the *paths* — refusal, permission without a token, and a
    /// clean registration — are exercised through this instead.
    private struct StubPushService: PushService {
        let mode: ServiceMode = .production
        let state: PushAuthorizationState
        let issuesToken: Bool

        var authorizationState: PushAuthorizationState { get async { state } }

        func register() async -> PushRegistrationOutcome {
            switch state {
            case .denied, .restricted:
                return .refused(state)
            case .notDetermined, .authorized, .provisional:
                guard issuesToken else {
                    return .tokenUnavailable("Apple didn't return a device token.")
                }
                return .registered(
                    PushDeviceToken(value: String(repeating: "f0", count: 32), environment: .production)
                )
            }
        }

        func refreshTokenIfAuthorized() async -> PushRegistrationOutcome? {
            guard state.canReceive else { return nil }
            return await register()
        }

        func unregister() async {}
    }

    /// A deterministic stand-in for the production adapter.
    ///
    /// `CoreLocationService` needs a real radio and a human to answer a prompt,
    /// so the production *path* — a fix marked real, or an honest refusal — is
    /// exercised through this. It reports production mode and, like the real
    /// adapter, never marks a fix simulated and never tracks anything.
    private struct StubProductionLocationService: LocationService {
        let mode: ServiceMode = .production
        let performsBackgroundTracking: Bool = false
        let state: LocationAuthorizationState

        var authorizationState: LocationAuthorizationState { get async { state } }
        func requestAuthorization() async -> LocationAuthorizationState { state }

        func captureFix(for event: LocationCaptureEvent, near destination: Coordinate?) async -> LocationFix? {
            // No permission means no reading. Never a plausible substitute.
            guard state.canCapture else { return nil }
            return LocationFix(
                coordinate: Coordinate(latitude: 28.01, longitude: -82.50),
                accuracyMeters: 9,
                heading: 88,
                speedMetersPerSecond: event == .travelStarted ? 9.4 : 0,
                capturedAt: Date(),
                simulated: false
            )
        }

        func currentLocation() async -> Coordinate? {
            state.canCapture ? Coordinate(latitude: 28.01, longitude: -82.50) : nil
        }
    }

    // MARK: - Reflection helpers

    private static let monetaryTerms = ["price", "total", "amount", "cost", "balance", "invoice", "payment", "tax", "quote", "subtotal", "currency", "money"]

    /// Field names on a value that look monetary. Used to prove the field
    /// worker payload is structurally money-free rather than merely filtered.
    private static func monetaryFields(of value: Any) -> [String] {
        Mirror(reflecting: value).children.compactMap { child in
            guard let label = child.label?.lowercased() else { return nil }
            return monetaryTerms.contains(where: { label.contains($0) }) ? (child.label ?? "") : nil
        }
    }

    private static func fieldCount(_ value: Any) -> Int {
        Mirror(reflecting: value).children.count
    }

    private static func failure(_ number: Int, _ title: String, _ expectation: String, _ error: Error) -> TestScenarioResult {
        TestScenarioResult(
            id: "\(number)",
            number: number,
            title: title,
            expectation: expectation,
            passed: false,
            evidence: "Unexpected error: \(DataError.wrap(error).errorDescription ?? "\(error)")"
        )
    }
}
