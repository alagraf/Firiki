import Foundation

/// Which legal order the retrieved evidence belongs to and, when it is not the one the question
/// targets, the caveat the answer carries.
///
/// This replaces the medical `DomainIsolationService` (in vitro / in vivo / clinical), which
/// abstained on a domain mismatch and replaced a drafted answer with "DOMAIN ISOLATION BREACH". A
/// jurisdiction mismatch never blocks an answer: the evidence is used and the answer says what it
/// is. Rule-based and computed at query time only, so nothing is stored and libraries indexed
/// before this existed are covered. A chunk with no recognisable signal is `.unknown` and never
/// triggers a caveat, so a miss stays silent rather than raising a false alarm.
enum JurisdictionService {
    enum Jurisdiction: String, CaseIterable, Sendable {
        case greece = "GR"
        case europeanUnion = "EU"
        case echr = "ECHR"
        case cyprus = "CY"
        case germany = "DE"
        case france = "FR"
        case italy = "IT"
        case unitedKingdom = "UK"
        case unitedStates = "US"
        case unknown = "UNKNOWN"

        nonisolated var isEUMemberState: Bool {
            switch self {
            case .greece, .cyprus, .germany, .france, .italy:
                return true
            default:
                return false
            }
        }

        /// Accusative phrase used in the Greek caveat ("αφορά το κυπριακό δίκαιο").
        nonisolated var greekName: String {
            switch self {
            case .greece: return "το ελληνικό δίκαιο"
            case .europeanUnion: return "το δίκαιο της ΕΕ"
            case .echr: return "την ΕΣΔΑ"
            case .cyprus: return "το κυπριακό δίκαιο"
            case .germany: return "το γερμανικό δίκαιο"
            case .france: return "το γαλλικό δίκαιο"
            case .italy: return "το ιταλικό δίκαιο"
            case .unitedKingdom: return "το δίκαιο του Ηνωμένου Βασιλείου"
            case .unitedStates: return "το δίκαιο των ΗΠΑ"
            case .unknown: return "μη προσδιορισμένο δίκαιο"
            }
        }

        nonisolated var englishName: String {
            switch self {
            case .greece: return "Greek law"
            case .europeanUnion: return "EU law"
            case .echr: return "the ECHR"
            case .cyprus: return "Cypriot law"
            case .germany: return "German law"
            case .france: return "French law"
            case .italy: return "Italian law"
            case .unitedKingdom: return "UK law"
            case .unitedStates: return "US law"
            case .unknown: return "unidentified law"
            }
        }
    }

    struct Classification: Sendable {
        let jurisdiction: Jurisdiction
        let score: Int
    }

    struct Assessment: Sendable {
        let target: Jurisdiction
        /// Jurisdictions found in the evidence that the target's courts are not bound by.
        let mismatched: [Jurisdiction]
        /// Share of chunks with a recognised jurisdiction that are compatible with the target.
        /// 1.0 when no chunk carries a recognisable signal.
        let compatibleShare: Float
        let allRecognisedEvidenceMismatched: Bool
        let caveat: String?
    }

    /// `NSRegularExpression` is immutable and documented as safe to use from several threads.
    private struct Signal: @unchecked Sendable {
        let jurisdiction: Jurisdiction
        let pattern: NSRegularExpression
        let weight: Int
    }

    // Patterns run against lowercased, accent-folded text, so they are written without accents.
    // Greek statute numbers ("ν. 4808/2021") are also how Cypriot law is cited, so that pattern
    // weighs 1 and court and gazette names, which are specific to one legal order, weigh 2.
    private nonisolated static let signals: [Signal] = {
        let table: [(Jurisdiction, Int, [String])] = [
            (.greece, 1, [
                #"(^|[^\p{L}])ν\.\s?\d{1,4}/(19|20)\d{2}"#,
            ]),
            (.greece, 2, [
                #"(^|[^\p{L}])φεκ([^\p{L}]|$)"#,
                #"αρει\w* παγ\w*"#,
                #"(^|[^\p{L}])απ\s+(ολομ\.?\s+)?\d+/(19|20)\d{2}"#,
                #"(^|[^\p{L}])στε\s+(ολομ\.?\s+)?\d+/(19|20)\d{2}"#,
                #"συμβουλι\w* της επικρατειας"#,
                #"(^|[^\p{L}])π\.?\s?δ\.?\s?\d{1,4}/(19|20)\d{2}"#,
                #"ελληνικ\w* (δικαι\w*|δημοκρατι\w*|συνταγμα\w*)"#,
                #"αστικ\w* κωδικ\w*"#,
                #"greek law"#,
            ]),
            (.europeanUnion, 2, [
                #"οδηγι\w*\s+(\((εε|εοκ|εκ)\)\s+)?\d{2,4}/\d{1,4}"#,
                #"κανονισμ\w*\s+\((εε|εοκ|εκ)\)"#,
                #"(^|[^\p{L}])δεε([^\p{L}]|$)"#,
                #"δικαστηρι\w* της ευρωπαικης ενωσης"#,
                #"(^|[^\p{L}\d])c[-‐]\d{1,4}/\d{2}([^\d]|$)"#,
                #"directive\s+(\((eu|eec|ec)\)\s+)?\d{2,4}/\d{1,4}"#,
                #"regulation\s+\((eu|eec|ec)\)"#,
                #"(^|[^\p{L}])cjeu([^\p{L}]|$)"#,
                #"court of justice of the european union"#,
                #"ecli:eu:"#,
            ]),
            (.echr, 2, [
                #"(^|[^\p{L}])εδδα([^\p{L}]|$)"#,
                #"(^|[^\p{L}])εσδα([^\p{L}]|$)"#,
                #"ευρωπαικ\w* δικαστηρι\w* (των )?δικαιωματων του ανθρωπου"#,
                #"european court of human rights"#,
                #"(^|[^\p{L}])ecthr([^\p{L}]|$)"#,
            ]),
            (.cyprus, 2, [
                #"κυπριακ\w*"#,
                #"κυπρ(ος|ου|ο)([^\p{L}]|$)"#,
                #"δικαστηρι\w* εργατικων διαφορων"#,
                #"επαρχιακ\w* δικαστηρι\w*"#,
                #"επισημη εφημεριδα της δημοκρατιας"#,
                #"(^|[^\p{L}])(cyprus|cypriot)([^\p{L}]|$)"#,
            ]),
            (.germany, 2, [
                #"γερμανικ\w* δικαι\w*"#,
                #"bundesarbeitsgericht"#,
                #"kundigungsschutzgesetz"#,
                #"(^|[^\p{L}])bgb([^\p{L}]|$)"#,
                #"german law"#,
            ]),
            (.france, 2, [
                #"γαλλικ\w* δικαι\w*"#,
                #"code du travail"#,
                #"cour de cassation"#,
                #"french law"#,
            ]),
            (.italy, 2, [
                #"ιταλικ\w* δικαι\w*"#,
                #"codice civile"#,
                #"corte di cassazione"#,
                #"italian law"#,
            ]),
            (.unitedKingdom, 2, [
                #"αγγλικ\w* δικαι\w*"#,
                #"employment rights act"#,
                #"employment (appeal )?tribunal"#,
                #"(^|[^\p{L}])(uksc|ewca)([^\p{L}]|$)"#,
                #"(english|uk) law"#,
            ]),
            (.unitedStates, 2, [
                #"αμερικανικ\w* δικαι\w*"#,
                #"\d+\s+u\.s\.c\."#,
                #"(^|[^\p{L}])flsa([^\p{L}]|$)"#,
                #"title vii"#,
                #"(us|u\.s\.|american) law"#,
            ]),
        ]
        // Case folding maps final sigma to σ, so the patterns are folded the same way.
        return table.flatMap { jurisdiction, weight, patterns in
            patterns.compactMap { pattern in
                (try? NSRegularExpression(pattern: pattern.replacingOccurrences(of: "ς", with: "σ"))).map {
                    Signal(jurisdiction: jurisdiction, pattern: $0, weight: weight)
                }
            }
        }
    }()

    nonisolated static func classify(_ text: String) -> Classification {
        let folded = fold(text)
        let range = NSRange(folded.startIndex..., in: folded)
        var scores: [Jurisdiction: Int] = [:]
        for signal in signals where signal.pattern.firstMatch(in: folded, range: range) != nil {
            scores[signal.jurisdiction, default: 0] += signal.weight
        }
        let ranked = scores.sorted {
            $0.value == $1.value ? $0.key.rawValue < $1.key.rawValue : $0.value > $1.value
        }
        guard let best = ranked.first else {
            return Classification(jurisdiction: .unknown, score: 0)
        }
        // A tie is not a classification.
        if ranked.count > 1, ranked[1].value == best.value {
            return Classification(jurisdiction: .unknown, score: best.value)
        }
        return Classification(jurisdiction: best.key, score: best.value)
    }

    nonisolated static func classifyChunk(_ chunk: RetrievedChunk) -> Classification {
        var parts = [chunk.chunk.content, chunk.sourceDocument]
        if let title = chunk.chunk.metadata.sectionTitle {
            parts.append(title)
        }
        if let path = chunk.chunk.metadata.sectionPath {
            parts.append(path.joined(separator: " "))
        }
        return classify(parts.joined(separator: "\n"))
    }

    /// The legal order the question is about. Greek law unless the question names a foreign one;
    /// a question citing an EU instrument is still a question about Greek law.
    nonisolated static func targetJurisdiction(for query: String) -> Jurisdiction {
        let named = classify(query).jurisdiction
        switch named {
        case .unknown, .greece, .europeanUnion, .echr:
            return .greece
        default:
            return named
        }
    }

    nonisolated static func isCompatible(_ evidence: Jurisdiction, with target: Jurisdiction) -> Bool {
        switch evidence {
        case .unknown, .echr:
            return true
        case .europeanUnion:
            return target.isEUMemberState
        default:
            return evidence == target
        }
    }

    nonisolated static func assess(query: String, chunks: [RetrievedChunk]) -> Assessment {
        let target = targetJurisdiction(for: query)
        let recognised = chunks.map { classifyChunk($0).jurisdiction }.filter { $0 != .unknown }
        let compatibleCount = recognised.filter { isCompatible($0, with: target) }.count

        var mismatched: [Jurisdiction] = []
        for jurisdiction in recognised where !isCompatible(jurisdiction, with: target) && !mismatched.contains(jurisdiction) {
            mismatched.append(jurisdiction)
        }

        let compatibleShare: Float = recognised.isEmpty ? 1.0 : Float(compatibleCount) / Float(recognised.count)
        let allMismatched = !recognised.isEmpty && compatibleCount == 0
        let caveat = mismatched.isEmpty
            ? nil
            : caveatText(
                mismatched: mismatched,
                target: target,
                allMismatched: allMismatched,
                greek: containsGreek(query)
            )

        return Assessment(
            target: target,
            mismatched: mismatched,
            compatibleShare: compatibleShare,
            allRecognisedEvidenceMismatched: allMismatched,
            caveat: caveat
        )
    }

    nonisolated static func caveatText(
        mismatched: [Jurisdiction],
        target: Jurisdiction,
        allMismatched: Bool,
        greek: Bool
    ) -> String {
        if greek {
            let sources = joinedList(mismatched.map(\.greekName), conjunction: "και")
            let lead = allMismatched
                ? "Οι διαθέσιμες πηγές αφορούν"
                : "Μέρος των διαθέσιμων πηγών αφορά"
            return "Σημείωση: \(lead) \(sources), ενώ το ερώτημά σας αφορά \(target.greekName). "
                + "Οι πηγές αυτές δεν δεσμεύουν τα δικαστήρια που εφαρμόζουν \(target.greekName) "
                + "και μπορούν να χρησιμεύσουν μόνο ως ερμηνευτικό βοήθημα."
        }
        let sources = joinedList(mismatched.map(\.englishName), conjunction: "and")
        let lead = allMismatched
            ? "The available sources concern"
            : "Some of the available sources concern"
        return "Note: \(lead) \(sources), while your question concerns \(target.englishName). "
            + "Those sources do not bind courts applying \(target.englishName) "
            + "and can serve only as persuasive or interpretive material."
    }

    /// Prefixes the caveat once. A response that already carries it is returned unchanged.
    nonisolated static func applyingCaveat(_ caveat: String, to response: String) -> String {
        let marked = "*\(caveat)*"
        guard !response.hasPrefix(marked) else { return response }
        return response.isEmpty ? marked : "\(marked)\n\n\(response)"
    }

    private nonisolated static func joinedList(_ items: [String], conjunction: String) -> String {
        guard items.count > 1, let last = items.last else { return items.first ?? "" }
        return items.dropLast().joined(separator: ", ") + " \(conjunction) " + last
    }

    private nonisolated static func containsGreek(_ text: String) -> Bool {
        text.unicodeScalars.contains { (0x0370...0x03FF).contains($0.value) || (0x1F00...0x1FFF).contains($0.value) }
    }

    private nonisolated static func fold(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .replacingOccurrences(of: "ς", with: "σ")
    }
}
