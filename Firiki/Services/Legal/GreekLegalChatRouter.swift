//
//  GreekLegalChatRouter.swift
//  Firiki
//
//  Thesis fork: recognizes capability requests straight from the chat prompt
//  (statute summary, legal opinion, contract template routing) and executes them directly.
//

import Foundation
import FoundationModels

enum GreekLegalChatIntent: Equatable, Sendable {
    case statuteSummary(documentQuery: String?)
    case legalOpinion(question: String)
    /// An explicit request for a contract template: the template router's answer is always shown.
    case contractRouting(terms: String)
    /// A described hiring or work arrangement: the template router runs, and when no template fits
    /// the prompt goes on to ordinary Q&A.
    case possibleContractRouting(terms: String)
    case standardQA(query: String)

    var isCapability: Bool {
        if case .standardQA = self { return false }
        return true
    }
}

struct ChatCapabilityResult: Sendable {
    let content: String
    let metadata: ResponseMetadata?
    let retrievedChunks: [RetrievedChunk]?
    let structuredAnswer: StructuredAnswer?

    init(
        content: String,
        metadata: ResponseMetadata? = nil,
        retrievedChunks: [RetrievedChunk]? = nil,
        structuredAnswer: StructuredAnswer? = nil
    ) {
        self.content = content
        self.metadata = metadata
        self.retrievedChunks = retrievedChunks
        self.structuredAnswer = structuredAnswer
    }
}

enum GreekLegalChatRouter {
    // MARK: - Recognition Rules
    //
    // Every pattern runs on the prompt folded like the Greek keyword index
    // (`SQLiteFullTextService.greekSearchFold`: no accents, lower case, final sigma as σ), so
    // «ΣΥΝΟΨΗ», «συνοψη» and «Σύνοψη» are the same word. Designed on the dev splits of the
    // template routing, Labour Code, library and opinion sets only.

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        try? NSRegularExpression(pattern: pattern)
    }

    private static let templateNoun = #"(?:υποδειγμα\w*|προτυπ\w*|templates?)"#
    private static let contractNoun = #"(?:συμβασ\w*|συμφωνητικ\w*|contracts?|agreements?)"#

    /// Explicit template requests: they name a template, or ask which contract form to sign.
    private static let explicitTemplateRules: [NSRegularExpression?] = [
        regex(#"\b\#(templateNoun)\b(?:\W+\w+){0,3}?\W+\#(contractNoun)"#),
        regex(#"\b\#(contractNoun)(?:\W+\w+){0,3}?\W+\#(templateNoun)\b"#),
        regex(#"\bποιο\s+(?:υποδειγμα|προτυπο)\b"#),
        regex(#"\b(?:which|what)\s+(?:\w+\s+)?(?:contract|template)\b.*\b(?:use|fit|suit)"#),
        regex(#"^(?:contract|agreement|συμβαση|συμφωνητικο)\s+(?:for|για)\b"#),
        regex(#"\b(?:τι|ποια|ποιο)\s+(?:συμβαση|συμφωνητικο)\s+(?:χρειαζομαι|κανουμε|να\s+κανω|υπογραφουμε|να\s+υπογραψω)"#),
    ]
    private static let templateNounRule = regex(#"\b\#(templateNoun)\b"#)
    private static let contractNounRule = regex(#"\b\#(contractNoun)\b"#)

    /// A contract noun with a request verb ("χρειάζομαι", "να χρησιμοποιήσω", "draft"…).
    private static let requestVerbRule = regex(
        #"(?:υπογραφουμε|υπογραψουμε|να\s+υπογραψω|κανουμε|να\s+κανω|sign\b|covers?\b|χρειαζομαι|χρειαζομαστε|θελω|να\s+χρησιμοποιησ\w*|να\s+υπογραψ\w*|ταιριαζ\w*|ετοιμασ\w*|συνταξ\w*|φτιαξ\w*|καταρτισ\w*|should\s+(?:i|we)\s+use|draft\w*|prepare\w*|\bfits?\b|suits?\b)"#)
    /// A yes/no question about the law ("Χρειάζεται γραπτή σύμβαση…;", "Do I need a written contract…?").
    private static let yesNoQuestionRule = regex(
        #"^(?:do|does|is|are|can|must|χρειαζεται|πρεπει|μπορει)\b"#)
    private static let whichContractRule = regex(#"\b(?:which|what)\s+contract\b"#)

    /// A hiring or work arrangement described as a request ("Θέλω να πάρω μια φοιτήτρια…",
    /// "I need someone for six months…").
    private static let arrangementRule = regex(
        #"\b(?:προσλαμβ\w*|προσλαβ\w*|να\s+παρω|να\s+παρουμε|θελω\s+(?:\w+\s+){1,2}(?:που|να)\b|θελω\s+να\s+(?:παρω|συμφωνησ\w*|προσλαβ\w*)|χρειαζομαι\s+(?!να\b)\w+|χρειαζομαστε\s+\w+|hir(?:e|ing)\b|take\s+on\b|i\s+need\s+(?:someone|an?\s+\w+|staff|people)|we\s+need\s+(?:someone|an?\s+\w+|staff)|i\s+want\s+(?:staff|someone|people|an?\s+\w+)|staff(?:ing)?\b|temp\b|placement|arrangement|θα\s+δουλευει|θα\s+κανει\s+(?:την\s+)?πρακτικ\w*|στελνει\s+\w+\s+\w+\s+για\s+πρακτικ\w*|μας\s+δανεισει|ετοιμασε|employment\s+agreement)"#)
    /// A prompt that opens as a question about the law, not a request.
    private static let questionStartRule = regex(
        #"^(?:ποσ\w*|ποι\w*|τι\b|πωσ|ποτε|μεχρι|γιατι|σε\s+ποια|υπαρχει|ισχυει|επιτρεπεται|δικαιουται|how|what|when|which|why|is|are|do|does|can|must|may|should|χρειαζεται|πρεπει|μπορει)\b"#)

    private static let opinionRule = regex(
        #"\b(?:γνωμοδοτ\w*|νομικη\s+(?:συμβουλη|αποψη|γνωμη)|legal\s+opinion|formal\s+memo\w*)\b"#)

    private static let summaryRule = regex(
        #"\b(?:συνοψ\w*|περιληψ\w*|περιληπτ\w*|summar\w*|digest)\b"#)
    /// A summary must be of a document: «περίληψη των δικαιωμάτων της εγκύου» is a question.
    private static let documentWordRule = regex(
        #"\b(?:εγγραφ\w*|νομο\w*|νομου|διαταγμ\w*|αποφασ\w*|κειμεν\w*|διαταξ\w*|laws?|decree|decision|document|statute|act)\b|\bπ\.?\s*δ\.?|\bν\.|\d{2,5}/\d{4}"#)

    private static func matches(_ regex: NSRegularExpression?, _ text: String) -> Bool {
        guard let regex else { return false }
        return regex.firstMatch(in: text, range: NSRange(location: 0, length: (text as NSString).length)) != nil
    }

    static func folded(_ text: String) -> String {
        SQLiteFullTextService.greekSearchFold(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Decides the capability intent of a chat prompt using program rules.
    static func detectIntent(_ query: String) -> GreekLegalChatIntent {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = folded(trimmed)

        // 1. An explicit template request.
        if explicitTemplateRules.contains(where: { matches($0, text) })
            || (matches(templateNounRule, text) && matches(contractNounRule, text)) {
            return .contractRouting(terms: trimmed)
        }

        // 2. Legal opinion.
        if matches(opinionRule, text) {
            return .legalOpinion(question: trimmed)
        }

        // 3. Statute summary: a summary word and a document or a named statute.
        if matches(summaryRule, text) {
            let target = extractDocumentTarget(from: trimmed)
            if target != nil || matches(documentWordRule, text) {
                return .statuteSummary(documentQuery: target)
            }
        }

        // 4. A described hiring or work arrangement: try the templates, else answer as a question.
        let requestsContract = matches(contractNounRule, text) && matches(requestVerbRule, text)
            && !matches(yesNoQuestionRule, text)
        let describesArrangement = matches(arrangementRule, text) && !matches(questionStartRule, text)
        if requestsContract || describesArrangement || matches(whichContractRule, text) {
            return .possibleContractRouting(terms: trimmed)
        }

        return .standardQA(query: trimmed)
    }

    /// Extracts named statute numbers or filenames from a summary prompt (e.g. «σύνοψη του ν. 5278/2026»).
    static func extractDocumentTarget(from query: String) -> String? {
        let text = folded(query)
        let patterns = [
            #"\b(?:ν\.|νομ(?:οσ|ου))\s*(\d{1,5}(?:/\d{4})?)\b"#,
            #"(?:\bπ\.?\s*δ\.?|\bδιαταγμ(?:α|ατοσ))\s*(\d{1,4}(?:/\d{4})?)\b"#,
            #"(?:\bυ\.?\s*α\.?|\bαποφασ(?:η|ησ))\s*(\d{1,5}(?:/\d{4})?)\b"#,
            #"\b(?:law|decree|decision)\s*(\d{1,5}(?:/\d{4})?)\b"#,
            #"\b(\d{4}/\d{4})\b"#,
            #"\b(?:συνοψη|συνοψε|περιληψη|summarize|summary)\s+(?:του\s+|τησ\s+|το\s+|the\s+)?(?:ν\.\s*|νομου\s+)?(\d{4,5})\b"#,
        ]
        let ns = text as NSString
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) {
                return ns.substring(with: match.range(at: 1))
            }
        }
        return nil
    }

    /// The document a summary request asks for.
    enum SummaryTarget: Equatable {
        /// The library document the request names.
        case document(Document)
        /// The request names a statute that no library document is: its key ("LAW:5278/2026")
        /// when the request names its kind, else the number as written ("5278/2026").
        case notInLibrary(key: String?, number: String?)
        /// The request names no statute ("summarise the document").
        case unnamed
    }

    /// Finds the document a summary request names. `statuteKeys` holds each document's own statute
    /// (`documentStatuteKey`, read from its title page at import). In order:
    /// 1. a statute named with its kind (`requestedStatutes`) that is a document's statute;
    /// 2. the number, and the year when given, against the documents' statutes, any kind
    ///    («νόμου 5239», or «ν. 62/2025» for the Labour Code, which is a decree);
    /// 3. for documents without a statute (imported before it was recorded), the number and year as
    ///    whole numbers in the filename.
    static func matchDocument(
        query: String,
        target: String?,
        in documents: [Document],
        statuteKeys: [UUID: String]
    ) -> SummaryTarget {
        let requested = GreekLegalAnswerFinalizer.requestedStatutes(query)
        if let named = documents.first(where: { document in
            guard let key = statuteKeys[document.id] else { return false }
            return requested.contains { LegalVerificationPolicy.sameStatute(key, $0) }
        }) {
            return .document(named)
        }

        let parts = target?.split(separator: "/").map(String.init) ?? []
        let number = parts.first.flatMap { Int($0) }.map(String.init)
        let year = parts.count > 1 ? parts[1] : nil
        if let number {
            if let byKey = documents.first(where: { document in
                guard let key = statuteKeys[document.id] else { return false }
                let keyParts = key.split(separator: ":", maxSplits: 1).last?.split(separator: "/").map(String.init) ?? []
                guard keyParts.first.flatMap({ Int($0) }).map(String.init) == number else { return false }
                return year == nil || keyParts.count < 2 || keyParts[1] == year
            }) {
                return .document(byKey)
            }
            if let byName = documents.first(where: { document in
                guard statuteKeys[document.id] == nil else { return false }
                let numbers = document.filename.split(whereSeparator: { !$0.isNumber }).compactMap { Int($0) }.map(String.init)
                return numbers.contains(number) && (year.map(numbers.contains) ?? true)
            }) {
                return .document(byName)
            }
        }

        if number != nil || !requested.isEmpty {
            return .notInLibrary(key: requested.sorted().first, number: target)
        }
        return .unnamed
    }

    /// A statute key as a Greek reader writes it: «ν. 5278/2026», «π.δ. 62/2025», «Υ.Α. 8934»,
    /// «Σύνταγμα».
    static func greekStatuteName(_ key: String) -> String {
        if key == "CONST" { return "Σύνταγμα" }
        let names = [("LAW:", "ν. "), ("PD:", "π.δ. "), ("MD:", "Υ.Α. ")]
        for (prefix, name) in names where key.hasPrefix(prefix) { return name + key.dropFirst(prefix.count) }
        return key
    }

    /// A statute key in the request's language.
    static func statuteName(_ key: String, greek: Bool) -> String {
        greek ? greekStatuteName(key) : GreekLegalAnswerFinalizer.statuteName(key)
    }

    /// One line per library document for "which document?": its statute when known, and its file.
    static func documentList(_ documents: [Document], statuteKeys: [UUID: String], greek: Bool) -> String {
        documents.map { document in
            guard let key = statuteKeys[document.id] else { return "- \(document.filename)" }
            return "- \(statuteName(key, greek: greek)) (\(document.filename))"
        }.joined(separator: "\n")
    }

    // MARK: - User-facing messages

    enum CapabilityTask: Sendable {
        case summary, opinion, template
    }

    static func isGreek(_ text: String) -> Bool {
        GreekLegalEntityMasker.greekLetterRatio(text) >= 0.3
    }

    /// A fixed message for a failed capability, in the request's language. The technical detail
    /// goes to the log only, never to the user.
    static func failureMessage(for error: Error, greek: Bool, task: CapabilityTask) -> String {
        Log.warning("[ChatRouter] \(task) failed: \(String(describing: error))", category: .llm)
        let lead: String
        switch task {
        case .summary: lead = greek ? "Η σύνοψη δεν ολοκληρώθηκε." : "The summary couldn't be completed."
        case .opinion: lead = greek ? "Η γνωμοδότηση δεν ολοκληρώθηκε." : "The legal opinion couldn't be completed."
        case .template: lead = greek ? "Η επιλογή υποδείγματος δεν ολοκληρώθηκε." : "The template choice couldn't be completed."
        }
        return lead + " " + failureReason(for: error, greek: greek)
    }

    static func failureReason(for error: Error, greek: Bool) -> String {
        if error is CancellationError {
            return greek ? "Το αίτημα ακυρώθηκε." : "The request was cancelled."
        }
        if let translatorError = error as? LocalNeuralTranslator.TranslatorError {
            switch translatorError {
            case .modelsMissing, .runtimeUnavailable:
                return greek
                    ? "Τα μοντέλα μετάφρασης δεν υπάρχουν σε αυτή την έκδοση της εφαρμογής."
                    : "The translation models are missing from this build of the app."
            case .unexpectedOutput:
                return greek ? "Η μετάφραση απέτυχε. Δοκιμάστε ξανά." : "Translation failed. Please try again."
            }
        }
        if let generationError = error as? LanguageModelSession.GenerationError {
            switch generationError {
            case .exceededContextWindowSize:
                return greek
                    ? "Το κείμενο είναι πολύ μεγάλο για το μοντέλο της συσκευής. Δοκιμάστε ένα πιο συγκεκριμένο αίτημα ή ένα μικρότερο έγγραφο."
                    : "The text is too long for the on-device model. Try a narrower request or a shorter document."
            case .guardrailViolation, .refusal:
                return greek
                    ? "Το μοντέλο της συσκευής δεν απάντησε σε αυτό το αίτημα. Δοκιμάστε να το διατυπώσετε διαφορετικά."
                    : "The on-device model declined this request. Try wording it differently."
            case .assetsUnavailable:
                return greek
                    ? "Το μοντέλο του Apple Intelligence δεν είναι ακόμη έτοιμο σε αυτή τη συσκευή. Δοκιμάστε ξανά σε λίγο."
                    : "The Apple Intelligence model isn't ready on this device yet. Please try again shortly."
            case .rateLimited, .concurrentRequests:
                return greek
                    ? "Το μοντέλο της συσκευής είναι απασχολημένο. Δοκιμάστε ξανά σε λίγο."
                    : "The on-device model is busy. Please try again shortly."
            case .unsupportedLanguageOrLocale:
                return greek
                    ? "Η γλώσσα της συσκευής δεν υποστηρίζεται από το Apple Intelligence. Ορίστε τα Αγγλικά ως γλώσσα της συσκευής."
                    : "The device language isn't supported by Apple Intelligence. Set the device language to English."
            default:
                break
            }
        }
        return greek ? "Δοκιμάστε ξανά." : "Please try again."
    }

    /// Nil when Apple's on-device model can answer; otherwise the message to show instead.
    static func modelUnavailableMessage(greek: Bool) -> String? {
        guard case .unavailable = SystemLanguageModel.default.availability else { return nil }
        return greek
            ? "Το Apple Intelligence δεν είναι διαθέσιμο σε αυτή τη συσκευή. Ενεργοποιήστε το στις Ρυθμίσεις ή περιμένετε να ολοκληρωθεί η λήψη του μοντέλου."
            : "Apple Intelligence isn't available on this device. Turn it on in Settings, or wait for the model to finish downloading."
    }

    private static func seconds(since start: ContinuousClock.Instant) -> TimeInterval {
        let elapsed = start.duration(to: .now).components
        return TimeInterval(elapsed.seconds) + TimeInterval(elapsed.attoseconds) / 1e18
    }

    private static func metadata(model: String, query: String, since start: ContinuousClock.Instant) -> ResponseMetadata {
        ResponseMetadata(
            totalGenerationTime: seconds(since: start),
            tokensGenerated: 0,
            modelUsed: model,
            retrievalTime: 0,
            originalQuery: query
        )
    }

    // MARK: - Direct Chat Execution

    /// Runs a capability recognised in the prompt. Nil means the prompt is an ordinary question
    /// (or a described arrangement no template fits) and goes on to normal Q&A.
    static func handleChatQuery(
        _ query: String,
        intent precomputedIntent: GreekLegalChatIntent? = nil,
        containerId: UUID,
        ragService: RAGService
    ) async -> ChatCapabilityResult? {
        let intent = precomputedIntent ?? detectIntent(query)
        let start = ContinuousClock.now

        switch intent {
        case .standardQA:
            return nil

        case .statuteSummary(let docTarget):
            let greek = isGreek(query)
            if let unavailable = modelUnavailableMessage(greek: greek) {
                return ChatCapabilityResult(content: unavailable)
            }
            do {
                return try await executeStatuteSummary(docTarget: docTarget, query: query, containerId: containerId, ragService: ragService, start: start)
            } catch {
                return ChatCapabilityResult(content: failureMessage(for: error, greek: greek, task: .summary))
            }

        case .legalOpinion(let question):
            let greek = isGreek(question)
            if let unavailable = modelUnavailableMessage(greek: greek) {
                return ChatCapabilityResult(content: unavailable)
            }
            do {
                return try await executeLegalOpinion(question: question, containerId: containerId, ragService: ragService, start: start)
            } catch {
                return ChatCapabilityResult(content: failureMessage(for: error, greek: greek, task: .opinion))
            }

        case .contractRouting(let terms):
            return await executeContractRouting(terms: terms, start: start, fallBackToQA: false)

        case .possibleContractRouting(let terms):
            return await executeContractRouting(terms: terms, start: start, fallBackToQA: true)
        }
    }

    // MARK: - Statute Summary Execution

    private static func executeStatuteSummary(
        docTarget: String?,
        query: String,
        containerId: UUID,
        ragService: RAGService,
        start: ContinuousClock.Instant
    ) async throws -> ChatCapabilityResult {
        let isGreekQuery = isGreek(query)
        let documents = await MainActor.run { ragService.documentsForContainer(containerId) }

        guard !documents.isEmpty else {
            return ChatCapabilityResult(
                content: isGreekQuery
                    ? "Δεν βρέθηκαν έγγραφα στη βιβλιοθήκη για σύνοψη. Εισαγάγετε ένα νομικό κείμενο ή νόμο στην καρτέλα 'Documents'."
                    : "There are no documents in the library to summarize. Import a legal text or law in the 'Documents' tab."
            )
        }

        let statuteKeys = await ragService.documentStatuteKeys(containerId: containerId, documentIds: documents.map(\.id))
        let docList = documentList(documents, statuteKeys: statuteKeys, greek: isGreekQuery)

        let doc: Document
        switch matchDocument(query: query, target: docTarget, in: documents, statuteKeys: statuteKeys) {
        case .document(let matched):
            doc = matched
        case .notInLibrary(let key, let number):
            let named = key.map { statuteName($0, greek: isGreekQuery) } ?? number ?? ""
            return ChatCapabilityResult(
                content: isGreekQuery
                    ? "Δεν υπάρχει στη βιβλιοθήκη: \(named). Τα έγγραφα της βιβλιοθήκης είναι:\n\n\(docList)"
                    : "Not in the library: \(named). The library holds:\n\n\(docList)"
            )
        case .unnamed:
            guard documents.count == 1, let only = documents.first else {
                return ChatCapabilityResult(
                    content: isGreekQuery
                        ? "Υπάρχουν περισσότερα από ένα νομοθετήματα στη βιβλιοθήκη. Ποιο έγγραφο θα θέλατε να συνοψίσω;\n\n\(docList)"
                        : "The library holds more than one document. Which one should I summarize?\n\n\(docList)"
                )
            }
            doc = only
        }

        let database = try await ragService.dbForContainer(containerId)
        let chunks = try await database.chunks(forDocument: doc.id).sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }
        guard !chunks.isEmpty else {
            return ChatCapabilityResult(
                content: isGreekQuery
                    ? "Το έγγραφο '\(doc.filename)' δεν περιέχει αποσπάσματα για σύνοψη."
                    : "The document '\(doc.filename)' has no passages to summarize."
            )
        }

        let passages = chunks.map(\.content)
        let statuteKey = chunks.lazy.compactMap { $0.legal?.documentStatuteKey }.first
        let heading = statuteKey.map { statuteName($0, greek: isGreekQuery) } ?? doc.filename

        let summary = try await GreekLegalDocumentSummarizer.summarize(
            passages: passages,
            statuteKey: statuteKey
        )
        try Task.checkCancellation()

        let answerText = isGreekQuery ? summary.greek : summary.english
        let retrieved = chunks.prefix(5).enumerated().map { index, chunk in
            RetrievedChunk(chunk: chunk, similarityScore: 1.0, rank: index + 1, sourceDocument: doc.filename)
        }

        return ChatCapabilityResult(
            content: (isGreekQuery ? "### Σύνοψη: " : "### Summary: ") + "\(heading)\n\n" + answerText,
            metadata: metadata(model: "AFM 3 Core (Map-Reduce Summarizer)", query: query, since: start),
            retrievedChunks: retrieved
        )
    }

    // MARK: - Legal Opinion Execution

    private static func executeLegalOpinion(
        question: String,
        containerId: UUID,
        ragService: RAGService,
        start: ContinuousClock.Instant
    ) async throws -> ChatCapabilityResult {
        let isGreekQuery = isGreek(question)
        let opinion = try await ragService.greekLegalOpinion(question: question, containerId: containerId)
        try Task.checkCancellation()

        if let refusal = opinion.refusal {
            return ChatCapabilityResult(
                content: isGreekQuery
                    ? "Δεν κατέστη δυνατή η έκδοση γνωμοδότησης: \(opinion.refusalGreek ?? refusal)."
                    : "Unable to synthesize legal opinion: \(refusal)."
            )
        }

        let answerText = isGreekQuery ? opinion.greek : opinion.english
        let retrieved = opinion.sources.flatMap(\.passages)

        return ChatCapabilityResult(
            content: answerText,
            metadata: metadata(model: "AFM 3 Core (Cross-Statute Legal Opinion)", query: question, since: start),
            retrievedChunks: retrieved
        )
    }

    // MARK: - Contract Template Routing Execution

    /// With `fallBackToQA`, a prompt no template fits returns nil so the chat answers it as a question.
    private static func executeContractRouting(
        terms: String,
        start: ContinuousClock.Instant,
        fallBackToQA: Bool
    ) async -> ChatCapabilityResult? {
        let isGreek = isGreek(terms)
        let decision = await LabourContractTemplateRouter.route(terms)

        guard let template = decision.template else {
            if fallBackToQA { return nil }
            let msg = isGreek
                ? "Δεν βρέθηκε κατάλληλο πρότυπο σύμβασης εργασίας για το αίτημά σας."
                : "No matching labour contract template was found for your request. \(decision.reason)"
            return ChatCapabilityResult(content: msg)
        }

        let methodBadge = decision.method == .model ? "AFM 3 On-Device Model" : "Keyword Rule"
        let articlesLabel = isGreek ? "Εφαρμοστέες διατάξεις" : "Applicable provisions"
        let articlesText = template.articles.isEmpty ? "" : "\n\n**\(articlesLabel):** " + template.articles.joined(separator: ", ")

        let content: String
        if isGreek {
            content = """
            ### Προτεινόμενο Υπόδειγμα: \(template.titleEl)
            *Μέθοδος επιλογής: \(methodBadge)*

            **Αιτιολόγηση:** \(LabourContractTemplateRouter.greekReason(for: template))
            \(articlesText)

            ---

            \(LabourContractTemplateRouter.displayedBody(template))
            """
        } else {
            content = """
            ### Recommended Template: \(template.titleEn)
            *Routing method: \(methodBadge)*

            **Reason:** \(decision.reason)
            \(articlesText)

            ---

            \(LabourContractTemplateRouter.displayedBody(template))
            """
        }

        return ChatCapabilityResult(
            content: content,
            metadata: metadata(model: "AFM 3 (Labour Contract Router)", query: terms, since: start)
        )
    }
}
