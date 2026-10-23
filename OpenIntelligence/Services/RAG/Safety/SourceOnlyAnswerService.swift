#if canImport(FoundationModels)
import Foundation
import FoundationModels

@available(iOS 26.0, *)
@Generable
struct SourceOnlyClaimDraft: Sendable, Codable {
    @Guide(description: "Stable claim identifier like C1 or C2.")
    let claimId: String

    @Guide(description: "One atomic factual claim from the candidate answer. Keep numbers and units exactly as written.")
    let claimText: String

    @Guide(description: "Evidence labels chosen only from the provided E1, E2, E3 labels. Use an empty array when unsupported.", .maximumCount(3))
    let evidenceLabels: [String]

    @Guide(description: "A verbatim supporting quote copied from one cited evidence chunk. Use an empty string when unsupported.")
    let evidenceQuote: String

    @Guide(description: "True when the claim is essential to answering the user's question.")
    let isCritical: Bool
}

@available(iOS 26.0, *)
@Generable
struct SourceOnlyAnswerDraft: Sendable, Codable {
    @Guide(description: "A terse draft answer derived only from the candidate answer and evidence. Do not add new facts.")
    let draftAnswer: String

    @Guide(description: "Atomic claims extracted from the candidate answer. Prefer coverage over filtering so unsupported claims can be verified downstream.", .maximumCount(8))
    let claims: [SourceOnlyClaimDraft]

    @Guide(description: "Important facets requested by the user that appear missing or under-evidenced.", .maximumCount(4))
    let missingFacets: [String]

    @Guide(description: "True if the evidence appears too weak to answer safely.")
    let shouldAbstain: Bool

    @Guide(description: "Short abstention reason. Empty string if no abstention is needed.")
    let abstentionReason: String
}

@available(iOS 26.0, *)
@Generable
struct SourceOnlyClaimReview: Sendable, Codable {
    @Guide(description: "Claim identifier copied from the input claims.")
    let claimId: String

    @Guide(description: "One of: supported, contradicted, ambiguous, unsupported.")
    let verdict: String

    @Guide(description: "Evidence labels that best support or contradict the claim, using only the provided E1, E2, E3 labels.", .maximumCount(3))
    let evidenceLabels: [String]

    @Guide(description: "A verbatim quote from the strongest cited evidence chunk. Empty when no exact quote exists.")
    let evidenceQuote: String

    @Guide(description: "Integer fidelity score from 0 to 100.")
    let fidelity: Int

    @Guide(description: "Short explanation of why the verdict was chosen.")
    let notes: String
}

@available(iOS 26.0, *)
@Generable
struct SourceOnlyReviewBundle: Sendable, Codable {
    @Guide(description: "Per-claim verification results.", .maximumCount(8))
    let reviews: [SourceOnlyClaimReview]
}

enum SourceOnlyClaimVerdict: String, Sendable {
    case supported
    case contradicted
    case ambiguous
    case unsupported
}

struct SourceOnlyVerifiedClaim: Sendable {
    let claimId: String
    let claimText: String
    let verdict: SourceOnlyClaimVerdict
    let evidenceLabels: [String]
    let evidenceIds: [String]
    let evidenceQuote: String
    let fidelity: Float
    let notes: String?
    let isCritical: Bool

    var isSupported: Bool { verdict == .supported }
}

struct SourceOnlyAnswerOutcome: Sendable {
    let finalAnswer: String
    let structuredAnswer: StructuredAnswer
    let supportedClaims: [SourceOnlyVerifiedClaim]
    let unsupportedClaims: [SourceOnlyVerifiedClaim]
    let shouldAbstain: Bool
    let abstentionReason: String?
    let fidelityScore: Float
    let warnings: [String]

    /// Fraction of the candidate answer the drafter was actually shown, 0...1.
    ///
    /// A verification stage that cannot see its own input must decline rather
    /// than overwrite. On 2026-08-24 this stage was shown 50 of a 3,415-character
    /// answer — 1.5% — and replaced a 472-word answer that Self-RAG had already
    /// accepted at 80% confidence with a 9-word fallback. Neither
    /// `supportedClaims` nor `fidelityScore` can see that: both are computed over
    /// the fragment, so a confident verdict about 1.5% of an answer looks
    /// identical to a confident verdict about all of it. Callers gate on this.
    let candidateCoverage: Double
}

@available(iOS 26.0, *)
@MainActor
final class SourceOnlyAnswerService {
    static let shared = SourceOnlyAnswerService()

    private let model = SystemLanguageModel.default

    private struct ReviewAggregation {
        let byClaimId: [String: SourceOnlyClaimReview]
        let warnings: [String]
    }

    private init() {}

    var isAvailable: Bool {
        switch model.availability {
        case .available:
            return true
        default:
            return false
        }
    }

    func verifyAndRender(
        query: String,
        candidateAnswer: String,
        retrievedChunks: [RetrievedChunk],
        answerIntent: AnswerIntent,
        verificationResult: RAGVerificationResult?
    ) async -> SourceOnlyAnswerOutcome? {
        guard isAvailable, !retrievedChunks.isEmpty else { return nil }

        // The medical domain-isolation pre-check (in vitro / in vivo / clinical) that used to sit
        // here was removed for the legal fork. It abstained before verification and replaced the
        // drafted answer with "DOMAIN ISOLATION BREACH". Nothing replaces it: the jurisdiction
        // caveat that briefly did was removed on 2026-10-23 (Docs/Thesis/FORK_CHANGES.md, 2.10).

        // Budget the prompt before building it, because this session has no other protection.
        //
        // A device capture on 2026-08-18 recorded `Draft generation failed: The session's
        // transcript exceeded the model's context size` after a 5-session reasoning chain, 11
        // steps and 132.5 seconds. The stage that was meant to produce the answer failed at the
        // last moment, and the run continued, so it read from outside as a slow success.
        //
        // Every other input here is already bounded, and the instructions are a constant.
        // `candidateAnswer` is the one unbounded input — whatever the chain produced, 455 words in
        // that capture and able to be much longer.
        //
        // 2026-08-19, first device execution of this path: the original bound was a hardcoded
        // 6 records x 420 characters. At `onDeviceCharsPerToken` 1.4 that is 1,800 tokens against a
        // measured budget of 1,430, so the evidence could not fit *by construction* and the drop
        // loop fired on every full-evidence run rather than as an exception. The observed capture
        // dropped 4 of 6 records and cut the candidate from 4,051 to 268 characters, leaving about
        // 6% of the retrieved evidence, and the answer was 8 words after 145 seconds.
        //
        // The records are now sized against the budget rather than against a constant, so all of
        // them survive with a shorter snippet each instead of two surviving at full length. On the
        // observed numbers that is 6 x 233 characters rather than 2 x 420 — more total evidence and
        // every source still represented. Dropping from the tail remains only as a backstop.
        //
        // Guided generation reserves context for the `SourceOnlyAnswerDraft` schema on top of the
        // prompt, hence the schema allowance below. The on-device ratio is used regardless of
        // where this is allowed to run, so the budget is not loosest exactly when the device is
        // the destination.
        let instructionsText = buildExtractionInstructions()
        let contextSize = FoundationModelTokenBudget.contextSize(isAppleFMOnDevice: true)
        let reserved = FoundationModelTokenBudget.estimateTokens(for: instructionsText, isAppleFMOnDevice: true)
            + FoundationModelTokenBudget.estimateTokens(for: query, isAppleFMOnDevice: true)
            + Self.draftOutputReserve
            + Self.draftSchemaReserve
            + Self.draftSafetyReserve
        let promptBudget = max(512, contextSize - reserved)

        // Size each snippet so the whole evidence set fits its share of the budget. Bounded below
        // so a record still carries a usable quotation, and above by the original 420 so this can
        // only ever shorten a snippet relative to the previous behaviour, never lengthen it.
        let recordCount = min(Self.maxEvidenceRecords, retrievedChunks.count)
        let evidenceCharBudget = Double(promptBudget) * Self.evidenceBudgetShare
            * FoundationModelTokenBudget.onDeviceCharsPerToken

        // `renderEvidencePrompt` wraps every snippet in XML and adds the source
        // name, the page and a 36-character chunk UUID. Sizing the snippet against the budget alone
        // therefore overshoots by the entire wrapper, which is what kept the drop
        // loop firing on every full-evidence run instead of as an exception — the
        // same class of miscalculation the 2026-08-19 note above records once
        // already. Measure the wrapper rather than guessing it, so it stays correct
        // if the rendering changes.
        let probeRecords = buildEvidenceRecords(from: retrievedChunks, snippetLimit: Self.maxSnippetChars)
        let probeText = renderEvidencePrompt(probeRecords)
        let wrapperChars = max(0, probeText.count - probeRecords.reduce(0) { $0 + $1.snippet.count })
        let snippetCharBudget = max(0, Int(evidenceCharBudget) - wrapperChars)

        let snippetLimit = recordCount > 0
            ? max(Self.minSnippetChars, min(Self.maxSnippetChars, snippetCharBudget / recordCount))
            : Self.maxSnippetChars

        let evidenceRecords = buildEvidenceRecords(from: retrievedChunks, snippetLimit: snippetLimit)
        guard !evidenceRecords.isEmpty else { return nil }

        // Enforce the share the constant already declares. This loop previously
        // stopped at `promptBudget`, the *whole* budget, so evidence was free to
        // consume all of it and `candidateBudget` below collapsed to whatever was
        // left — on the 2026-08-24 capture, 50 characters of a 3,415-character
        // answer. `evidenceBudgetShare` was applied to `snippetLimit` above and
        // nowhere else, so the intent was documented and then not implemented.
        // Bounding here guarantees the candidate keeps its 30%.
        let evidenceTokenCeiling = max(1, Int(Double(promptBudget) * Self.evidenceBudgetShare))
        var budgetedRecords = evidenceRecords
        var evidencePromptText = renderEvidencePrompt(budgetedRecords)
        var droppedRecords = 0
        while budgetedRecords.count > 1,
              FoundationModelTokenBudget.estimateTokens(for: evidencePromptText, isAppleFMOnDevice: true) > evidenceTokenCeiling {
            budgetedRecords.removeLast()
            droppedRecords += 1
            evidencePromptText = renderEvidencePrompt(budgetedRecords)
        }

        let evidenceTokens = FoundationModelTokenBudget.estimateTokens(for: evidencePromptText, isAppleFMOnDevice: true)
        let candidateBudget = max(0, promptBudget - evidenceTokens)
        let candidateCharBudget = Int(Double(candidateBudget) * FoundationModelTokenBudget.onDeviceCharsPerToken)
        let budgetedCandidate = Self.trimmedAtSentenceBoundary(candidateAnswer, limit: candidateCharBudget)
        let candidateCoverage = candidateAnswer.isEmpty
            ? 1.0
            : Double(budgetedCandidate.count) / Double(candidateAnswer.count)

        if droppedRecords > 0 || budgetedCandidate.count < candidateAnswer.count {
            Log.warning(
                "[SourceOnly] Extraction prompt trimmed to fit \(promptBudget) tokens: dropped "
                    + "\(droppedRecords) evidence record(s), candidate answer "
                    + "\(budgetedCandidate.count)/\(candidateAnswer.count) chars "
                    + "(\(Int((candidateCoverage * 100).rounded()))% coverage)",
                category: .llm
            )
        }

        let extractionPrompt = buildExtractionPrompt(
            query: query,
            candidateAnswer: budgetedCandidate,
            answerIntent: answerIntent,
            evidencePrompt: evidencePromptText
        )

        // `model:` is required. Omitting it yields a session that produces no output: an Instruments
        // capture on 2026-08-15 recorded two such calls returning 0 tokens over 6.5 and 7.1
        // seconds with an empty Response, while every session built with an explicit model
        // succeeded in the same run. The bare `LanguageModelSession()` initialiser was fixed at
        // ten sites on 2026-08-14; these pass instructions but still omitted the model, so they
        // were missed by a grep for the no-argument form.
        let extractionSession = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: Instructions(sanitizeForLanguageDetection(
                buildExtractionInstructions()
            ))
        )

        // The draft gets an output limit. Without one the model may write until the context is full
        // and then throw, which is Apple's documented behaviour for an unset `maximumResponseTokens`
        // and what a 2026-09-23 macOS run did: 163.5 seconds, then "exceeded the model's context
        // size", after the answer was already on screen. A draft that reaches the limit stops early
        // and fails to parse (measured the same day: 0.9 s at a 30-token limit), and a failed draft
        // keeps the generated answer.
        //
        // The limit is `draftTokenLimit`, not `draftOutputReserve`. The reserve was tried first and
        // is too tight: on three Deep Think lookups the same day, completed drafts used 571 and 675
        // of 700 tokens and the third failed to parse, most likely at the limit. The prompt budget
        // keeps the 700 reserve; its 1.4 characters per token overestimates the prompt, which leaves
        // the real room larger.
        let draft: SourceOnlyAnswerDraft
        do {
            let response = try await extractionSession.respond(
                to: sanitizeForLanguageDetection(extractionPrompt),
                generating: SourceOnlyAnswerDraft.self,
                options: GenerationOptions(maximumResponseTokens: Self.draftTokenLimit)
            )
            draft = response.content
            // What a completed draft actually used, against the limit above, so the limit can be
            // judged from traces rather than guessed.
            #if compiler(>=6.4)
                if #available(iOS 27.0, macOS 27.0, *) {
                    Log.info(
                        "[SourceOnly] Draft used \(extractionSession.usage.output.totalTokenCount) of "
                            + "\(Self.draftTokenLimit) output tokens: \(draft.claims.count) claim(s)",
                        category: .llm
                    )
                }
            #endif
        } catch {
            Log.warning("[SourceOnly] Draft generation failed: \(error.localizedDescription)", category: .llm)
            return nil
        }

        guard !draft.claims.isEmpty else {
            Log.warning("[SourceOnly] Draft contained no claims", category: .llm)
            return nil
        }

        // The budgeted evidence, not the full set. This previously passed the untrimmed
        // `evidencePrompt` while the extraction step received the trimmed one, so the two stages
        // disagreed about what evidence existed: the reviewer could ground claims in records the
        // drafter had never seen. The caller then rejects any claim id it does not recognise, which
        // is what the 2026-08-19 capture logged seven times in a row as
        // `Source-only review returned unexpected claim id C2..C8; ignored`. Both stages now read
        // the same records.
        let reviewPrompt = buildReviewPrompt(
            query: query,
            draft: draft,
            evidencePrompt: evidencePromptText
        )
        // `model:` is required. Omitting it yields a session that produces no output: an Instruments
        // capture on 2026-08-15 recorded two such calls returning 0 tokens over 6.5 and 7.1
        // seconds with an empty Response, while every session built with an explicit model
        // succeeded in the same run. The bare `LanguageModelSession()` initialiser was fixed at
        // ten sites on 2026-08-14; these pass instructions but still omitted the model, so they
        // were missed by a grep for the no-argument form.
        let reviewSession = LanguageModelSession(
            model: SystemLanguageModel.default,
            instructions: Instructions(sanitizeForLanguageDetection(
                buildReviewInstructions()
            ))
        )

        let reviewBundle: SourceOnlyReviewBundle
        do {
            let response = try await reviewSession.respond(
                to: sanitizeForLanguageDetection(reviewPrompt),
                generating: SourceOnlyReviewBundle.self
            )
            reviewBundle = response.content
        } catch {
            Log.warning("[SourceOnly] Claim review failed: \(error.localizedDescription)", category: .llm)
            return nil
        }

        let reviewAggregation = aggregateReviews(
            reviewBundle.reviews,
            expectedClaimIds: draft.claims.map(\.claimId)
        )
        for warning in reviewAggregation.warnings {
            Log.warning("[SourceOnly] \(warning)", category: .llm)
        }
        // Amounts of money and dates the evidence contradicts, read with Apple's detector (5.7, `DetectedValueCheck`).
        let detectedEvidence = await DetectedValueCheck.evidence(
            from: evidenceRecords.map { $0.chunk.chunk.contextText })
        var verifiedClaims: [SourceOnlyVerifiedClaim] = []
        for claim in draft.claims {
            let contradiction = await DetectedValueCheck.contradictions(
                in: claim.claimText, evidence: detectedEvidence
            ).first
            verifiedClaims.append(
                mergeClaimDraft(
                    claim,
                    review: reviewAggregation.byClaimId[normalizeClaimIdentifier(claim.claimId)],
                    evidenceRecords: evidenceRecords,
                    detectedContradiction: contradiction
                ))
        }

        let supportedClaims = verifiedClaims.filter { $0.isSupported }
        let unsupportedClaims = verifiedClaims.filter { !$0.isSupported }
        // The draft's headings are not claims (5.7): they stay out of the rebuilt answer, Fact Check and the fidelity
        // checks below, where a heading copied from the passage scored high and lifted a weak claim's average over the
        // floor (second review, 2026-10-18). An unsupported heading still counts toward `criticalFailure`, and every
        // claim toward the risk profile.
        let listedClaims = Self.claimsToList(supportedClaims, candidateAnswer: candidateAnswer)
        let riskProfile = riskProfile(for: query, claims: verifiedClaims)
        let fidelityThreshold: Float = riskProfile == .high ? 0.88 : 0.78
        let criticalFailure = unsupportedClaims.contains { $0.isCritical }
        let belowThresholdCritical = listedClaims.contains { $0.isCritical && $0.fidelity < fidelityThreshold }
        let shouldAbstain = draft.shouldAbstain
            || supportedClaims.isEmpty
            || criticalFailure
            || belowThresholdCritical

        // When every supported claim is one of the draft's headings, the answer rebuilt from them was only its title,
        // which replaced the generated answer through 5.6. The check declines instead, as it does for a draft with no
        // claims, and the generated answer stands (second review, 2026-10-18).
        let draftHeadings = VerificationGateService.headingLines(in: candidateAnswer)
        if !shouldAbstain, !listedClaims.isEmpty,
            listedClaims.allSatisfy({
                draftHeadings.contains(VerificationGateService.headingKey($0.claimText))
                    && !VerificationGateService.makesStatement($0.claimText)
            })
        {
            Log.info("[SourceOnly] Every supported claim is a heading of the draft; keeping the generated answer", category: .llm)
            return nil
        }

        let fidelityScore: Float = shouldAbstain
            ? 0.0
            : (listedClaims.isEmpty ? 0.0 : listedClaims.map(\.fidelity).reduce(0, +) / Float(listedClaims.count))

        let abstentionReason: String?
        if shouldAbstain {
            if !draft.abstentionReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                abstentionReason = draft.abstentionReason
            } else if criticalFailure {
                abstentionReason = "One or more critical claims could not be verified from retrieved evidence."
            } else if belowThresholdCritical {
                abstentionReason = "Critical claims were too weakly supported for a source-only answer."
            } else {
                abstentionReason = "Retrieved evidence was insufficient for a source-only answer."
            }
        } else {
            abstentionReason = nil
        }

        let finalAnswer = shouldAbstain
            ? "⚠️ **[Needs Verification]** This answer was drafted but could not be strictly verified against the retrieved evidence:\n\n\(candidateAnswer)\n\n*(Reason: \(abstentionReason ?? "Insufficient evidence"))*"
            : renderVerifiedAnswer(
                supportedClaims: listedClaims,
                missingFacets: draft.missingFacets,
                evidenceRecords: evidenceRecords,
                answerIntent: answerIntent,
                riskProfile: riskProfile
            )

        let structuredAnswer = buildStructuredAnswer(
            finalAnswer: finalAnswer,
            answerIntent: answerIntent,
            evidenceRecords: evidenceRecords,
            supportedClaims: listedClaims,
            unsupportedClaims: unsupportedClaims,
            missingFacets: draft.missingFacets,
            verificationResult: verificationResult,
            shouldAbstain: shouldAbstain,
            topScore: retrievedChunks.first?.similarityScore ?? 0
        )

        var warnings = reviewAggregation.warnings
        warnings.append(contentsOf: unsupportedClaims.prefix(4).map { claim in
            "Source-only filter dropped claim \(claim.claimId): \(claim.claimText)"
        })

        return SourceOnlyAnswerOutcome(
            finalAnswer: finalAnswer,
            structuredAnswer: structuredAnswer,
            supportedClaims: supportedClaims,
            unsupportedClaims: unsupportedClaims,
            shouldAbstain: shouldAbstain,
            abstentionReason: abstentionReason,
            fidelityScore: fidelityScore,
            warnings: warnings,
            candidateCoverage: candidateCoverage
        )
    }

    private func buildExtractionInstructions() -> String {
        """
        You are OpenIntelligence in EVIDENCE-GROUNDED VERIFICATION MODE.
        Your top priority is factual accuracy and faithfulness to the provided evidence.
        Use ONLY the provided evidence chunks. Never use outside knowledge.
        Extract atomic claims from the candidate answer, but keep only what the evidence directly supports or what can be stated as a conservative paraphrase.
        If a fact is not directly established, leave it unsupported instead of guessing.
        Keep unsupported claims in the draft so they can be rejected later.
        Rules:
        1. Use ONLY the provided evidence chunks.
        2. Do not treat semantic similarity as proof.
        3. Do not merge nearby but different entities, mechanisms, steps, or values.
        4. Copy numbers, units, codes, dates, and names exactly.
        5. If a claim is unsupported, set evidenceLabels to [] and evidenceQuote to an empty string.
        6. Mark a claim critical when omitting it would materially fail to answer the user's question.
        """
    }

    private func buildReviewInstructions() -> String {
        """
        You are OpenIntelligence in EVIDENCE-GROUNDED VERIFICATION MODE.
        Your job is to verify claims conservatively against the provided evidence only.
        Never repair a claim with background knowledge, assumptions, or implied facts.
        If a claim is only partially supported, prefer ambiguous or unsupported over supported.
        For each claim, return one verdict: supported, contradicted, ambiguous, or unsupported.
        Rules:
        1. Use ONLY the provided evidence chunks.
        2. Supported means directly grounded in one or more chunks.
        3. Contradicted means the evidence says the opposite.
        4. Ambiguous means the evidence is partial, indirect, or too broad.
        5. Unsupported means the evidence does not establish the claim.
        6. If a number, unit, code, or date in the claim is absent from cited evidence, the claim cannot be supported.
        7. Do not repair or rewrite claims.
        8. Return exactly one review object for each input claimId. Copy each claimId exactly once and do not invent new IDs.
        9. Prefer exact evidence labels and verbatim quotes.
        """
    }

    private func buildEvidenceRecords(
        from chunks: [RetrievedChunk],
        snippetLimit: Int = SourceOnlyAnswerService.maxSnippetChars
    ) -> [EvidenceRecord] {
        Array(chunks.prefix(Self.maxEvidenceRecords)).enumerated().map { index, chunk in
            let snippet = String(chunk.chunk.contextText
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .prefix(max(1, snippetLimit)))
            return EvidenceRecord(
                label: "E\(index + 1)",
                chunk: chunk,
                snippet: snippet
            )
        }
    }

    /// Output tokens the draft response is allowed to use.
    /// Evidence-set bounds. `maxEvidenceRecords` and `maxSnippetChars` are the historical values;
    /// the effective snippet length is derived from the prompt budget at call time and can only be
    /// smaller. `evidenceBudgetShare` leaves the remainder for the candidate answer, which is the
    /// unbounded input and is trimmed against whatever the evidence did not use.
    static let maxEvidenceRecords = 6
    static let maxSnippetChars = 420
    private static let minSnippetChars = 160
    private static let evidenceBudgetShare = 0.7

    private static let draftOutputReserve = 700
    /// The draft's generation limit: about 1.5 times the largest completed draft measured on
    /// 2026-09-23 (675 tokens). It bounds a runaway draft well short of a context overflow without
    /// cutting drafts that fill the 700 reserve. See the comment at the draft call.
    private static let draftTokenLimit = 1024
    /// Guided generation reserves context for the response schema on top of the prompt.
    private static let draftSchemaReserve = 400
    /// Headroom for the chat template and tokenizer disagreement with our estimate.
    private static let draftSafetyReserve = 256

    /// Trim at a sentence end, falling back to a word break, so a truncated candidate answer
    /// never ends mid-word where the model would read it as a token it must account for.
    private static func trimmedAtSentenceBoundary(_ text: String, limit: Int) -> String {
        guard text.count > limit, limit > 0 else { return text }
        let head = String(text.prefix(limit))
        if let idx = head.lastIndex(where: { ".!?".contains($0) }) {
            return String(head[...idx])
        }
        if let idx = head.lastIndex(of: " ") {
            return String(head[..<idx])
        }
        return head
    }

    private func renderEvidencePrompt(_ evidenceRecords: [EvidenceRecord]) -> String {
        evidenceRecords.map { record in
            let pageText = record.chunk.pageNumber ?? record.chunk.chunk.metadata.pageNumber
            let page = pageText.map(String.init) ?? "nil"
            return """
            <evidence id="\(record.label)">
            <source>\(record.chunk.sourceDocument)</source>
            <page>\(page)</page>
            <chunk_id>\(record.chunk.chunk.id.uuidString)</chunk_id>
            <text>\(record.snippet)</text>
            </evidence>
            """
        }.joined(separator: "\n\n")
    }

    private func buildExtractionPrompt(
        query: String,
        candidateAnswer: String,
        answerIntent: AnswerIntent,
        evidencePrompt: String
    ) -> String {
        """
        <verification_mode>GENERAL_EVIDENCE_GROUNDED</verification_mode>
        <query>\(query)</query>
        <answer_intent>\(answerIntent.rawValue)</answer_intent>
        <candidate_answer>\(candidateAnswer)</candidate_answer>
        <evidence_set>
        \(evidencePrompt)
        </evidence_set>
        """
    }

    private func buildReviewPrompt(
        query: String,
        draft: SourceOnlyAnswerDraft,
        evidencePrompt: String
    ) -> String {
        let claimsJSON = (try? encodeJSON(draft.claims)) ?? "[]"
        return """
        <verification_mode>GENERAL_EVIDENCE_GROUNDED</verification_mode>
        <query>\(query)</query>
        <claims>\(claimsJSON)</claims>
        <evidence_set>
        \(evidencePrompt)
        </evidence_set>
        """
    }

    private func aggregateReviews(
        _ reviews: [SourceOnlyClaimReview],
        expectedClaimIds: [String]
    ) -> ReviewAggregation {
        var warnings: [String] = []
        var expectedIds: [String: String] = [:]

        for claimId in expectedClaimIds {
            let normalizedClaimId = normalizeClaimIdentifier(claimId)
            guard !normalizedClaimId.isEmpty else { continue }
            if expectedIds[normalizedClaimId] == nil {
                expectedIds[normalizedClaimId] = claimId.trimmingCharacters(in: .whitespacesAndNewlines)
            } else {
                warnings.append("Source-only draft emitted duplicate claim id \(claimId); review matching may be degraded.")
            }
        }

        var reviewMap: [String: SourceOnlyClaimReview] = [:]
        var reviewCounts: [String: Int] = [:]

        for review in reviews {
            let displayClaimId = review.claimId.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalizedClaimId = normalizeClaimIdentifier(review.claimId)

            guard !normalizedClaimId.isEmpty else {
                warnings.append("Source-only review returned a blank claim id; ignored.")
                continue
            }
            guard expectedIds[normalizedClaimId] != nil else {
                warnings.append("Source-only review returned unexpected claim id \(displayClaimId); ignored.")
                continue
            }

            reviewCounts[normalizedClaimId, default: 0] += 1

            if let existingReview = reviewMap[normalizedClaimId] {
                reviewMap[normalizedClaimId] = moreConservativeReview(existingReview, review)
            } else {
                reviewMap[normalizedClaimId] = review
            }
        }

        for claimId in expectedIds.keys.sorted() {
            if let count = reviewCounts[claimId], count > 1 {
                warnings.append("Source-only review returned \(count) entries for \(expectedIds[claimId] ?? claimId); kept the most conservative result.")
            }
            if reviewMap[claimId] == nil {
                warnings.append("Source-only review omitted \(expectedIds[claimId] ?? claimId); defaulted to unsupported.")
            }
        }

        return ReviewAggregation(byClaimId: reviewMap, warnings: warnings)
    }

    private func mergeClaimDraft(
        _ draft: SourceOnlyClaimDraft,
        review: SourceOnlyClaimReview?,
        evidenceRecords: [EvidenceRecord],
        detectedContradiction: DetectedValueCheck.Contradiction? = nil
    ) -> SourceOnlyVerifiedClaim {
        let mappedEvidence = Dictionary(uniqueKeysWithValues: evidenceRecords.map { ($0.label, $0) })
        let rawLabels = review?.evidenceLabels.isEmpty == false ? review?.evidenceLabels ?? [] : draft.evidenceLabels
        let validLabels = rawLabels.filter { mappedEvidence[$0] != nil }
        let evidenceIds = validLabels.compactMap { mappedEvidence[$0]?.chunk.chunk.id.uuidString }
        var verdict = parseVerdict(review?.verdict)
        var fidelity = Float(max(0, min(review?.fidelity ?? 0, 100))) / 100
        let quote = !(review?.evidenceQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
            ? review?.evidenceQuote ?? ""
            : draft.evidenceQuote
        var notes: [String] = []
        if let note = review?.notes.trimmingCharacters(in: .whitespacesAndNewlines), !note.isEmpty {
            notes.append(note)
        }

        let citedTexts = validLabels.compactMap { mappedEvidence[$0]?.chunk.chunk.contextText }
        let combinedEvidenceText = citedTexts.joined(separator: "\n")
        if validLabels.isEmpty {
            verdict = .unsupported
            fidelity = 0
            notes.append("No valid evidence labels were returned.")
        }

        if !quote.isEmpty && !citedTexts.contains(where: { normalize($0).contains(normalize(quote)) }) {
            verdict = .unsupported
            fidelity = min(fidelity, 0.25)
            notes.append("Returned quote did not match cited evidence.")
        }

        let numericTokens = extractNumericLikeTokens(from: draft.claimText)
        let missingNumericTokens = numericTokens.filter { token in
            !combinedEvidenceText.lowercased().contains(token.lowercased())
        }
        if !missingNumericTokens.isEmpty {
            verdict = .unsupported
            fidelity = min(fidelity, 0.2)
            notes.append("Numeric tokens missing from cited evidence: \(missingNumericTokens.joined(separator: ", ")).")
        }

        // The test above looks for the digits anywhere in the cited text, so "2.5" passes against
        // "12.5" and against a name such as "Qwen-2.5-3B". Read the claim's numbers as values too.
        // Only the numbers the numeric gate counts: digits with a letter against them ("5th",
        // "Q3", "4K") are left to the test above.
        if missingNumericTokens.isEmpty,
            let unstated = NumericValueExtractor.firstUnsupportedMention(
                in: draft.claimText,
                evidence: NumericValueExtractor.evidence(from: citedTexts),
                exempt: { !NumericValueExtractor.isCountedByGate($0) })
        {
            verdict = .unsupported
            fidelity = min(fidelity, 0.2)
            notes.append("A figure is not stated in the cited evidence as a value: \(unstated.written).")
        }

        // An amount the evidence states only in another currency, or another day of a month it gives (5.7,
        // `DetectedValueCheck`).
        if let contradiction = detectedContradiction {
            verdict = .unsupported
            fidelity = min(fidelity, 0.2)
            notes.append("The evidence states \(contradiction.stated), not \(contradiction.written).")
        }

        let exactClaimHasHardAnchor = !numericTokens.isEmpty
            || !quote.isEmpty
            || claimContainsSpecificationCue(draft.claimText)

        let anchorOverlap = lexicalOverlap(claim: draft.claimText, evidenceTexts: citedTexts)
        if anchorOverlap < 0.14 && verdict == .supported {
            if exactClaimHasHardAnchor {
                notes.append("Exact-value/spec anchors preserved despite low lexical overlap.")
            } else {
                verdict = .ambiguous
                fidelity = min(fidelity, 0.55)
                notes.append("Low lexical overlap with cited evidence.")
            }
        }

        return SourceOnlyVerifiedClaim(
            claimId: draft.claimId,
            claimText: draft.claimText.trimmingCharacters(in: .whitespacesAndNewlines),
            verdict: verdict,
            evidenceLabels: validLabels,
            evidenceIds: evidenceIds,
            evidenceQuote: quote,
            fidelity: fidelity,
            notes: notes.isEmpty ? nil : notes.joined(separator: " "),
            isCritical: draft.isCritical
        )
    }

    private func claimContainsSpecificationCue(_ text: String) -> Bool {
        text.range(
            of: #"\b(?:sae|api|ilsac|dot-4|gl-5|sp4|[0o]w-20|5w-30|75w/85|full open|user height setting|auto open|level\s*[123])\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func renderVerifiedAnswer(
        supportedClaims: [SourceOnlyVerifiedClaim],
        missingFacets: [String],
        evidenceRecords: [EvidenceRecord],
        answerIntent: AnswerIntent,
        riskProfile: RiskProfile
    ) -> String {
        let evidenceMap = Dictionary(uniqueKeysWithValues: evidenceRecords.map { ($0.label, $0) })

        let renderedClaims = supportedClaims.map { claim in
            let rankedLabels = rankedEvidenceLabels(for: claim, evidenceMap: evidenceMap)
            let citations = rankedLabels.map(compactCitationLabel(for:))
            let citationSuffix = citations.isEmpty ? "" : " " + citations.joined(separator: " ")
            return normalizedSentence(claim.claimText) + citationSuffix
        }

        var answer: String
        switch answerIntent {
        case .procedure:
            answer = renderedClaims.enumerated().map { index, claim in
                "\(index + 1). \(claim)"
            }.joined(separator: "\n")
        case .compare:
            answer = renderedClaims.joined(separator: "\n")
        default:
            answer = renderedClaims.joined(separator: " ")
        }

        if riskProfile == .normal && shouldAppendMissingFacets(
            missingFacets,
            supportedClaims: supportedClaims,
            answerIntent: answerIntent
        ) {
            let trimmedMissing = missingFacets
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if !trimmedMissing.isEmpty {
                answer += "\n\nMissing or weakly supported details: " + trimmedMissing.joined(separator: "; ")
            }
        }

        return answer.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func compactCitationLabel(for evidenceLabel: String) -> String {
        guard evidenceLabel.first?.uppercased() == "E",
              let index = Int(evidenceLabel.dropFirst()),
              index > 0 else {
            return "[\(evidenceLabel)]"
        }
        return "[S\(index)]"
    }

    private func rankedEvidenceLabels(
        for claim: SourceOnlyVerifiedClaim,
        evidenceMap: [String: EvidenceRecord]
    ) -> [String] {
        let claimText = claim.claimText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !claimText.isEmpty else { return claim.evidenceLabels }

        let scored = claim.evidenceLabels.compactMap { label -> (label: String, score: Float)? in
            guard let record = evidenceMap[label] else { return nil }
            let candidateText = record.chunk.chunk.contextText
            let overlap = lexicalOverlap(claim: claimText, evidenceTexts: [candidateText])
            let normalizedClaim = normalize(claimText)
            let normalizedEvidence = normalize(candidateText)
            let hasExactClaim = normalizedEvidence.contains(normalizedClaim)
            let numericTokens = extractNumericLikeTokens(from: claimText)
            let numericCoverage = numericTokens.isEmpty
                ? 1.0
                : Float(numericTokens.filter { normalizedEvidence.contains($0.lowercased()) }.count) / Float(numericTokens.count)
            let quoteBonus: Float = (!claim.evidenceQuote.isEmpty && normalizedEvidence.contains(normalize(claim.evidenceQuote))) ? 0.15 : 0
            let score = overlap + (hasExactClaim ? 0.75 : 0) + (numericCoverage * 0.35) + quoteBonus
            return (label: label, score: score)
        }.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.label < rhs.label
            }
            return lhs.score > rhs.score
        }

        guard let best = scored.first else { return claim.evidenceLabels }

        if scored.count == 1 {
            return [best.label]
        }

        let second = scored[1]
        let bestIsDominant = best.score >= 0.95 && (best.score - second.score) >= 0.20
        if bestIsDominant {
            return [best.label]
        }

        return Array(scored.prefix(2).map(\.label))
    }

    private func shouldAppendMissingFacets(
        _ missingFacets: [String],
        supportedClaims: [SourceOnlyVerifiedClaim],
        answerIntent: AnswerIntent
    ) -> Bool {
        let trimmedMissing = missingFacets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmedMissing.isEmpty else { return false }

        switch answerIntent {
        case .procedure, .compare:
            return true
        default:
            break
        }

        if supportedClaims.count == 1, let onlyClaim = supportedClaims.first, onlyClaim.fidelity >= 0.84 {
            return false
        }

        return true
    }

    /// The supported claims the rebuilt answer is written from and Fact Check lists (5.7): not the draft's own
    /// headings, as in `StructuredAnswer`, unless every supported claim is one. A supported heading was listed in Fact
    /// Check and written into the rebuilt answer as a sentence ("Notice to Enter. [S1]"). The headings come from the
    /// model's draft, because the rebuilt answer has none (review, 2026-10-18). A claim that states something stays even
    /// when it matches a heading (`VerificationGateService.makesStatement`): every claim here is supported, so keeping
    /// a title costs a sentence, and leaving out a statement costs what it said (fourth review, 2026-10-18).
    static func claimsToList(
        _ supportedClaims: [SourceOnlyVerifiedClaim], candidateAnswer: String
    ) -> [SourceOnlyVerifiedClaim] {
        let headings = VerificationGateService.headingLines(in: candidateAnswer)
        let kept = supportedClaims.filter {
            !headings.contains(VerificationGateService.headingKey($0.claimText))
                || VerificationGateService.makesStatement($0.claimText)
        }
        return kept.isEmpty ? supportedClaims : kept
    }

    private func buildStructuredAnswer(
        finalAnswer: String,
        answerIntent: AnswerIntent,
        evidenceRecords: [EvidenceRecord],
        supportedClaims: [SourceOnlyVerifiedClaim],
        unsupportedClaims: [SourceOnlyVerifiedClaim],
        missingFacets: [String],
        verificationResult: RAGVerificationResult?,
        shouldAbstain: Bool,
        topScore: Float
    ) -> StructuredAnswer {
        let builder = StructuredAnswer.Builder()
            .setRefuse(shouldAbstain)
            .setAnswerType(StructuredAnswer.AnswerType(rawValue: answerIntent.rawValue) ?? .lookup)
            .setAnswer(finalAnswer)
            .setTopScore(topScore)
            .setLoops(1)

        if let verificationResult {
            var gateResults: [String: Bool] = [:]
            for gate in verificationResult.gateResults {
                gateResults[gate.gate.rawValue] = gate.passed
            }
            _ = builder.setGateResults(gateResults)
        }

        let evidenceMap = Dictionary(uniqueKeysWithValues: evidenceRecords.map { ($0.label, $0) })
        var addedEvidenceIds: Set<String> = []

        for claim in supportedClaims {
            _ = builder.addClaim(
                claim.claimText,
                evidenceIds: claim.evidenceIds,
                confidence: claim.fidelity,
                isExtracted: false
            )

            for label in claim.evidenceLabels {
                guard let record = evidenceMap[label] else { continue }
                let evidenceId = record.chunk.chunk.id.uuidString
                guard !addedEvidenceIds.contains(evidenceId) else { continue }
                addedEvidenceIds.insert(evidenceId)
                _ = builder.addEvidence(
                    id: evidenceId,
                    page: record.chunk.pageNumber ?? record.chunk.chunk.metadata.pageNumber,
                    quote: claim.evidenceQuote.isEmpty ? record.snippet : claim.evidenceQuote,
                    documentName: record.chunk.sourceDocument.isEmpty ? nil : record.chunk.sourceDocument,
                    sectionPath: record.chunk.chunk.metadata.sectionPath
                )
            }
        }

        for missing in missingFacets where !missing.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            _ = builder.addMissing(missing)
        }
        return builder.build()
    }

    private func riskProfile(for query: String, claims: [SourceOnlyVerifiedClaim]) -> RiskProfile {
        let lower = query.lowercased()
        let highRiskTerms = [
            "medical", "safety", "danger", "warning", "dose", "dosage", "steril", "temperature",
            "pressure", "voltage", "medication", "drug", "legal", "financial", "compliance"
        ]
        if highRiskTerms.contains(where: { lower.contains($0) }) {
            return .high
        }
        if claims.contains(where: { !$0.isSupported && !$0.evidenceLabels.isEmpty }) {
            return .high
        }
        return .normal
    }

    private func lexicalOverlap(claim: String, evidenceTexts: [String]) -> Float {
        let claimTokens = Set(significantTokens(from: claim))
        guard !claimTokens.isEmpty else { return 1 }

        let bestOverlap = evidenceTexts.map { text -> Float in
            let evidenceTokens = Set(significantTokens(from: text))
            guard !evidenceTokens.isEmpty else { return 0 }
            let overlap = claimTokens.intersection(evidenceTokens).count
            return Float(overlap) / Float(claimTokens.count)
        }.max() ?? 0

        return bestOverlap
    }

    private func significantTokens(from text: String) -> [String] {
        let stopWords: Set<String> = [
            "the", "and", "that", "with", "from", "this", "were", "was", "have", "has", "had", "into",
            "your", "their", "about", "would", "could", "should", "there", "which", "what", "when", "where",
            "than", "then", "them", "they", "also", "only", "using", "used", "does", "each", "more", "less"
        ]

        return text.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { $0.count >= 4 && !stopWords.contains($0) }
    }

    private func extractNumericLikeTokens(from text: String) -> [String] {
        let pattern = #"(\b\d+(?:\.\d+)?\s?(?:mg/kg|mg|g/kg|g|%|days|day|weeks|week|hours|hour|min|minutes|psi|bar|°c|°f|c|f|v|volts?)\b|\b\d+(?:\.\d+)?\b)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        }
    }

    private func normalize(_ text: String) -> String {
        text.lowercased()
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func normalizedSentence(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let last = trimmed.last else { return trimmed }
        if [".", "?", "!"].contains(last) {
            return trimmed
        }
        return trimmed + "."
    }

    private func parseVerdict(_ rawValue: String?) -> SourceOnlyClaimVerdict {
        switch rawValue?.lowercased() {
        case "supported":
            return .supported
        case "contradicted":
            return .contradicted
        case "ambiguous":
            return .ambiguous
        default:
            return .unsupported
        }
    }

    private func moreConservativeReview(
        _ lhs: SourceOnlyClaimReview,
        _ rhs: SourceOnlyClaimReview
    ) -> SourceOnlyClaimReview {
        let lhsRank = verdictConservatismRank(for: lhs)
        let rhsRank = verdictConservatismRank(for: rhs)
        if lhsRank != rhsRank {
            return lhsRank < rhsRank ? lhs : rhs
        }

        if lhs.fidelity != rhs.fidelity {
            return lhs.fidelity < rhs.fidelity ? lhs : rhs
        }

        let lhsQuoteIsEmpty = lhs.evidenceQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let rhsQuoteIsEmpty = rhs.evidenceQuote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if lhsQuoteIsEmpty != rhsQuoteIsEmpty {
            return lhsQuoteIsEmpty ? lhs : rhs
        }

        return lhs
    }

    private func verdictConservatismRank(for review: SourceOnlyClaimReview) -> Int {
        switch parseVerdict(review.verdict) {
        case .contradicted:
            return 0
        case .unsupported:
            return 1
        case .ambiguous:
            return 2
        case .supported:
            return 3
        }
    }

    private func normalizeClaimIdentifier(_ claimId: String) -> String {
        claimId
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func sanitizeForLanguageDetection(_ text: String) -> String {
        var sanitized = text
        let replacements: [(String, String)] = [
            ("ł", "l"), ("Ł", "L"),
            ("ą", "a"), ("Ą", "A"),
            ("ę", "e"), ("Ę", "E"),
            ("ó", "o"), ("Ó", "O"),
            ("ś", "s"), ("Ś", "S"),
            ("ź", "z"), ("Ź", "Z"),
            ("ż", "z"), ("Ż", "Z"),
            ("ć", "c"), ("Ć", "C"),
            ("ń", "n"), ("Ń", "N"),
            ("ü", "u"), ("ö", "o"), ("ä", "a"),
            ("è", "e"), ("é", "e"), ("ê", "e"),
            ("à", "a"), ("á", "a"), ("â", "a"),
            ("ì", "i"), ("í", "i"), ("î", "i"),
            ("ù", "u"), ("ú", "u"), ("û", "u"),
            ("ñ", "n"), ("ç", "c"),
            ("—", "-"), ("–", "-")
        ]

        for (original, replacement) in replacements {
            sanitized = sanitized.replacingOccurrences(of: original, with: replacement)
        }

        return sanitized.precomposedStringWithCanonicalMapping
    }

    private func encodeJSON<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(data: try encoder.encode(value), encoding: .utf8) ?? "{}"
    }
}

@available(iOS 26.0, *)
private struct EvidenceRecord: Sendable {
    let label: String
    let chunk: RetrievedChunk
    let snippet: String
}

private enum RiskProfile {
    case normal
    case high
}
#endif
