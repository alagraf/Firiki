//
//  GreekLegalOpinionTests.swift
//  OpenIntelligenceTests
//
//  Thesis fork (PoC capability 3): the opinion writer's source choice, links to the Labour Code
//  and sections with a stubbed model, and an opt-in evaluation over
//  `Benchmarks/GreekLabourLibrary/opinion_qa_v1.jsonl`: `TEST_RUNNER_OI_GREEK_OPINION=1`, with
//  `TEST_RUNNER_OI_GREEK_OPINION_SPLIT` `dev` (the default) or `test`. It reads the five-document
//  library that `GreekConstitutionEvaluationTests` imports, so that run must have imported it.
//  Reported per request: citations found, articles cited that the set doesn't expect, key facts,
//  sentences dropped, time.
//

import Foundation
import FoundationModels
import Testing
@testable import OpenIntelligence

@Suite("Greek legal opinion")
struct GreekLegalOpinionTests {
    static func passage(_ document: UUID, _ index: Int, greek: String, english: String, score: Float, statute: String) -> RetrievedChunk {
        RetrievedChunk(
            chunk: DocumentChunk(
                documentId: document, content: english, embedding: [], metadata: ChunkMetadata(chunkIndex: index),
                legal: LegalChunkMetadata(sourceTextEl: greek, sourceLanguage: "el", documentStatuteKey: statute)),
            similarityScore: score, rank: index + 1)
    }

    static let law = UUID(), code = UUID(), decision = UUID(), other = UUID()

    /// Article 7 of Ν. 5239/2025 as the Gazette prints its heading.
    static let overtime = passage(
        law, 8,
        greek: "Άρθρο 7\nΧρονικά όρια εργασίας - Τροποποίηση παρ. 2\nκαι 3 άρθρου 194 Κώδικα Εργατικού Δικαίου\nΣτο άρθρο 194 του Κώδικα Εργατικού Δικαίου (π.δ. 62/2025, Α’ 121) επέρχονται οι ακόλουθες τροποποιήσεις.",
        english: "Article 7 [Άρθρο 7]\nTime limits of work - Amendment of paragraphs 2 and 3 of Article 194 of the Labour Code\n3. Employees working overtime are entitled, for each hour of legal overtime, up to four (4) hours a day and up to one hundred and fifty (150) hours a year, to the hourly wage increased by forty percent (40%).",
        score: 0.9, statute: "LAW:5239/2025")
    static let hiring = passage(
        law, 20,
        greek: "Άρθρο 21\nΠρόσληψη για κάλυψη επειγουσών αναγκών -\nΠροσθήκη άρθρου 578Α στον Κώδικα\nΕργατικού Δικαίου",
        english: "Article 21 [Άρθρο 21]\nRecruitment to cover urgent needs - Addition of Article 578A to the Labour Code",
        score: 0.5, statute: "LAW:5239/2025")
    static let codeArticle = passage(
        code, 400, greek: "Άρθρο 194\nΑμοιβή υπερεργασίας και υπερωρίας", english: "Article 194 [Άρθρο 194]\nPay for extra work and overtime. 3. Up to three (3) hours a day.",
        score: 0.4, statute: "PD:62/2025")
    static let wage = passage(
        decision, 2,
        greek: "Τον καθορισμό, σύμφωνα με το άρθρο 141Α του π.δ. 62/2025 (Α’ 121), του νομοθετημένου κατώτατου μισθού. Έχοντας υπόψη: α) Του άρθρου 141Α του Κώδικα Εργατικού Δικαίου.",
        english: "The statutory minimum wage for employees is set at nine hundred and twenty euros (920.00 €), without distinction of age.",
        score: 0.85, statute: "MD:8934")
    static let unrelated = passage(other, 5, greek: "Άρθρο 11\nΔιαφάνεια", english: "Article 11 [Άρθρο 11]\nPay gap reporting.", score: 0.3, statute: "LAW:5316/2026")

    @Test func linksToTheLabourCodeAreReadFromTheArticleHeadings() {
        let links = GreekLegalOpinionWriter.codeLinks(statuteKey: "LAW:5239/2025", passages: [Self.overtime.chunk, Self.hiring.chunk])
        #expect(links == [
            .init(statuteKey: "LAW:5239/2025", article: "7", kind: .amends, codeArticle: "194"),
            .init(statuteKey: "LAW:5239/2025", article: "21", kind: .adds, codeArticle: "578Α"),
        ])
        #expect(GreekLegalOpinionWriter.codeLinks(statuteKey: "MD:8934", passages: [Self.wage.chunk])
            == [.init(statuteKey: "MD:8934", article: nil, kind: .appliesUnder, codeArticle: "141Α")])
        // The Code links to nothing.
        #expect(GreekLegalOpinionWriter.codeLinks(statuteKey: "PD:62/2025", passages: [Self.codeArticle.chunk]).isEmpty)
        #expect(GreekLegalOpinionWriter.combination([links[0]]) == [
            "Article 7 of Law 5239/2025 amended Article 194 of the Labour Code; the amended text applies, as the later law.",
        ])
    }

    @Test func documentsCloseToTheBestAreKeptAndTheCodeJoinsWhenAmended() {
        let sources = [
            GreekLegalOpinionWriter.Source(document: "law.pdf", statuteKey: "LAW:5239/2025", passages: [Self.overtime, Self.hiring]),
            GreekLegalOpinionWriter.Source(document: "code.pdf", statuteKey: "PD:62/2025", passages: [Self.codeArticle]),
            GreekLegalOpinionWriter.Source(document: "other.pdf", statuteKey: "LAW:5316/2026", passages: [Self.unrelated]),
        ]
        let links = GreekLegalOpinionWriter.codeLinks(statuteKey: "LAW:5239/2025", passages: [Self.overtime.chunk])
        let kept = GreekLegalOpinionWriter.selectSources(sources, links: links)
        // 0.4 is under 60% of 0.9, but the law amends the Code; 0.3 stays out.
        #expect(kept.map(\.document) == ["law.pdf", "code.pdf"])
        #expect(GreekLegalOpinionWriter.selectSources(sources, links: []).map(\.document) == ["law.pdf"])
    }

    @Test func anAmendedCodeArticleIsReadFromTheAmendingLaw() {
        func chunk(_ document: UUID, _ index: Int, _ greek: String, _ english: String, _ statute: String) -> DocumentChunk {
            DocumentChunk(documentId: document, content: english, embedding: [], metadata: ChunkMetadata(chunkIndex: index),
                          legal: LegalChunkMetadata(sourceTextEl: greek, sourceLanguage: "el", documentStatuteKey: statute))
        }
        let code194 = chunk(Self.code, 10, "Άρθρο 194\nΑμοιβή υπερωρίας", "Article 194 [Άρθρο 194]\nPay for overtime.", "PD:62/2025")
        let code194More = chunk(Self.code, 11, "3. Έως τρεις ώρες την ημέρα.", "3. Up to three (3) hours a day.", "PD:62/2025")
        let code195 = chunk(Self.code, 12, "Άρθρο 195\nΠαραγραφή", "Article 195 [Άρθρο 195]\nLimitation: five years.", "PD:62/2025")
        let lawBefore = chunk(Self.law, 7, "Άρθρο 6\nΆλλη ρύθμιση", "Article 6 [Άρθρο 6]\nAnother rule.", "LAW:5239/2025")
        let law7 = Self.overtime.chunk
        let law7More = chunk(Self.law, 9, "παρ. 3 ...", "Up to one hundred and fifty (150) hours a year.", "LAW:5239/2025")
        let documents = ["code.pdf": [code194, code194More, code195], "law.pdf": [lawBefore, law7, law7More]]
        let links = GreekLegalOpinionWriter.codeLinks(statuteKey: "LAW:5239/2025", passages: documents["law.pdf"] ?? [])
        let sources = [
            GreekLegalOpinionWriter.Source(document: "code.pdf", statuteKey: "PD:62/2025", passages: [
                RetrievedChunk(chunk: code194More, similarityScore: 0.8, rank: 1), RetrievedChunk(chunk: code195, similarityScore: 0.5, rank: 2)]),
            GreekLegalOpinionWriter.Source(document: "law.pdf", statuteKey: "LAW:5239/2025", passages: [RetrievedChunk(chunk: lawBefore, similarityScore: 0.4, rank: 1)]),
        ]
        let replaced = GreekLegalOpinionWriter.replacingAmendedCodePassages(sources, links: links, documents: documents)
        // Article 194's text before the amendment is gone; Article 7 of the law takes its place and score.
        #expect(replaced[0].passages.map(\.chunk.id) == [code195.id])
        #expect(replaced[1].passages.map(\.chunk.id) == [law7.id, law7More.id, lawBefore.id])
        #expect(replaced[1].bestScore == 0.8)
        #expect(GreekLegalOpinionWriter.sameArticle("ART:141Α", "141A") && !GreekLegalOpinionWriter.sameArticle("141", "141Α"))
    }

    @Test func sectionsAndConclusionLoseWhatIsNotAnAnswer() {
        #expect(GreekLegalOpinionWriter.cleanedSection(
            "Overtime pays 40% (Article 7 of Law 5239/2025). Not addressed: the rules for posted workers. It applies to all employees.")
            == "Overtime pays 40% (Article 7 of Law 5239/2025). It applies to all employees.")
        let conclusion = """
            Overtime of up to four hours a day is allowed. It pays 40% more. The employee may refuse. A fourth sentence.

            **Conclusion**
            Overtime is allowed, repeated.
            """
        #expect(GreekLegalOpinionWriter.cleanedConclusion(conclusion)
            == "Overtime of up to four hours a day is allowed. It pays 40% more. The employee may refuse.")
        #expect(GreekLegalOpinionWriter.cleanedConclusion("**Conclusion:** Yes, it is allowed.") == "Yes, it is allowed.")
    }

    @Test func sectionsAreCheckedAndTheOpinionIsInGreekSections() async throws {
        let sources = [
            GreekLegalOpinionWriter.Source(document: "law.pdf", statuteKey: "LAW:5239/2025", passages: [Self.overtime]),
            GreekLegalOpinionWriter.Source(document: "other.pdf", statuteKey: "LAW:5316/2026", passages: [Self.unrelated]),
        ]
        let links = GreekLegalOpinionWriter.codeLinks(statuteKey: "LAW:5239/2025", passages: [Self.overtime.chunk])
        actor Calls { var prompts: [(String, String)] = []; func add(_ i: String, _ p: String) { prompts.append((i, p)) } }
        let calls = Calls()
        let opinion = try await GreekLegalOpinionWriter.write(
            question: "Επιτρέπονται τέσσερις ώρες υπερωρία;", questionEn: "Are four hours of overtime allowed?",
            sources: sources, links: links,
            respond: { instructions, prompt in
                await calls.add(instructions, prompt)
                if instructions == GreekLegalOpinionWriter.conclusionInstructions {
                    return "Yes: up to four (4) hours a day, paid at plus 40% (Article 7 of Law 5239/2025)."
                }
                if prompt.contains("Law 5316/2026") { return "Not addressed." }
                return "Overtime is allowed up to four (4) hours a day and 150 hours a year (Article 7 of Law 5239/2025). It is paid at plus 40%. Night work pays 75% more (Article 99 of Law 1234/2020)."
            },
            translate: { "EL " + $0 })
        let prompts = await calls.prompts
        #expect(prompts.count == 3, "two sections and the conclusion")
        #expect(prompts[0].1.contains("Statute: Law 5239/2025") && prompts[0].1.contains("[1] Article 7"))
        #expect(prompts[2].1.contains("How they combine:\nArticle 7 of Law 5239/2025 amended Article 194"))
        #expect(opinion.refusal == nil)
        #expect(opinion.dropped == ["Night work pays 75% more (Article 99 of Law 1234/2020)."], "\(opinion.dropped)")
        #expect(opinion.english.contains(
            "Applicable law:\nLaw 5239/2025, Article 7; the Labour Code (Presidential Decree 62/2025), Article 194 as amended."))
        // The applicable law and the links are written in Greek by the program, not translated.
        #expect(opinion.greek.contains(
            "Εφαρμοστέο δίκαιο\nν. 5239/2025, άρθρο 7· Κώδικας Εργατικού Δικαίου (π.δ. 62/2025), άρθρο 194, όπως τροποποιήθηκε."))
        #expect(opinion.greek.contains(
            "Πώς συνδυάζονται\nΤο άρθρο 7 του ν. 5239/2025 τροποποίησε το άρθρο 194 του Κώδικα Εργατικού Δικαίου· εφαρμόζεται το τροποποιημένο κείμενο."))
        #expect(!opinion.greek.contains("EL Article 7 of Law 5239/2025 amended"), "the links are not translated")
        #expect(!opinion.english.contains("Law 5316/2026"), "a document that doesn't address the question is not applicable law")
        for title in ["Ερώτημα", "Εφαρμοστέο δίκαιο", "Τι προβλέπει κάθε κείμενο", "Πώς συνδυάζονται", "Συμπέρασμα", "Σημείωση"] {
            #expect(opinion.greek.contains(title + "\n"), "\(title)")
        }
        #expect(opinion.greek.contains("EL Yes: up to four (4) hours"))
    }

    /// A decision has no articles: the model cited "(Article 1 of Ministerial Decision 8934)", the
    /// article check dropped the sentence, and the €920 minimum wage was missing from the opinion
    /// (9 Nov 2026). The number is now removed and the sentence is kept.
    @Test func aDecisionWithoutArticlesKeepsItsFigures() async throws {
        let decision = Self.passage(Self.decision, 23, greek: "α) Για τους υπαλλήλους ο κατώτατος μισθός ορίζεται σε εννιακόσια είκοσι ευρώ (920,00 €)",
                                    english: "[Part 2] (a) For employees the minimum wage is set at nine hundred and twenty euros (920,00 €).",
                                    score: 0.48, statute: "MD:8934")
        let source = GreekLegalOpinionWriter.Source(document: "ya.pdf", statuteKey: "MD:8934", passages: [decision])
        #expect(!GreekLegalOpinionWriter.hasArticles(source))
        let instructions = GreekLegalOpinionWriter.sectionInstructions(statute: source.name, hasArticles: false)
        #expect(instructions.contains("Cite each rule as (Ministerial Decision 8934)") && !instructions.contains("Article N"))
        #expect(GreekLegalOpinionWriter.withoutInventedArticles(
            "(Article 1 of Ministerial Decision 8934) sets the minimum wage at €920.", statute: "Ministerial Decision 8934")
            == "Ministerial Decision 8934 sets the minimum wage at €920.")
        #expect(GreekLegalOpinionWriter.withoutInventedArticles(
            "The wage is €920 (Article 1 of Ministerial Decision 8934).", statute: "Ministerial Decision 8934")
            == "The wage is €920 (Ministerial Decision 8934).")
        // Amounts in words keep only their figure before translation.
        let pre = LocalNeuralTranslator.legalEnglishPreEdited
        #expect(pre("for employees at 9 hundred and twenty euros (920,00 €) and for workers at 40-one euros and 9 minutes (41.09 €), effective")
            == "for employees at 920,00 € and for workers at 41.09 €, effective")
        #expect(pre("and nine hundred euros (900 €)") == "and 900 €")
        #expect(pre("every hour of legal overtime—up to four hours daily—is paid")
            == "every hour of legal overtime, up to four hours daily, is paid")
        #expect(pre("Articles 130–134 of the Code") == "Articles 130–134 of the Code")
        let opinion = try await GreekLegalOpinionWriter.write(
            question: "Πόσος είναι ο κατώτατος μισθός;", questionEn: "How much is the minimum wage?",
            sources: [source], links: [],
            respond: { instructions, _ in
                if instructions == GreekLegalOpinionWriter.conclusionInstructions {
                    return "The minimum wage for employees is nine hundred and twenty euros (920,00 €) (Article 1 of Ministerial Decision 8934)."
                }
                return "(Article 1 of Ministerial Decision 8934) sets the minimum wage for employees at nine hundred and twenty euros (920,00 €)."
            },
            translate: { $0 })
        #expect(opinion.refusal == nil)
        #expect(opinion.dropped.isEmpty, "\(opinion.dropped)")
        #expect(opinion.english.contains("Ministerial Decision 8934 sets the minimum wage for employees at nine hundred and twenty euros (920,00 €)."))
        #expect(opinion.english.contains("Conclusion:\nThe minimum wage for employees is nine hundred and twenty euros (920,00 €) (Ministerial Decision 8934)."))
    }

    @Test func greekWordingIsWrittenByTheProgramAndRepaired() {
        let amends = GreekLegalOpinionWriter.CodeLink(statuteKey: "LAW:5239/2025", article: "7", kind: .amends, codeArticle: "194")
        let adds = GreekLegalOpinionWriter.CodeLink(statuteKey: "LAW:5239/2025", article: "21", kind: .adds, codeArticle: "578Α")
        let applies = GreekLegalOpinionWriter.CodeLink(statuteKey: "MD:8934", article: nil, kind: .appliesUnder, codeArticle: "141Α")
        #expect(GreekLegalOpinionWriter.combinationGreek([amends, adds, applies]) == [
            "Το άρθρο 7 του ν. 5239/2025 τροποποίησε το άρθρο 194 του Κώδικα Εργατικού Δικαίου· εφαρμόζεται το τροποποιημένο κείμενο.",
            "Το άρθρο 21 του ν. 5239/2025 πρόσθεσε το άρθρο 578Α στον Κώδικα Εργατικού Δικαίου.",
            "Η Υ.Α. 8934 εκδόθηκε κατ’ εξουσιοδότηση του άρθρου 141Α του Κώδικα Εργατικού Δικαίου και το εφαρμόζει.",
        ])
        #expect(GreekLegalOpinionWriter.greekStatuteName("PD:62/2025") == "Κώδικας Εργατικού Δικαίου (π.δ. 62/2025)")
        #expect(GreekLegalOpinionWriter.greekStatuteName("LAW:5278/2026") == "ν. 5278/2026")
        // The translator's Greek, as the 9 Nov 2026 opinion on overtime showed it.
        #expect(GreekLegalOpinionWriter.repairedGreek(
            "Σύμφωνα με το Άρθρο 7 της Ν. 5239/2025, ο εργοδότης. Το κείμενο του Άρθρο 194 ισχύει. Άρθρο 7 (Άρθρο 7) ορίζει.")
            == "Σύμφωνα με το άρθρο 7 του ν. 5239/2025, ο εργοδότης. Το κείμενο του άρθρου 194 ισχύει. Άρθρο 7 ορίζει.")
        #expect(GreekLegalOpinionWriter.repairedGreek(
            "με αμοιβή ίση με το πληρωμένο ωριαίο επιτόκιο. Η προθεσμία για υπερωρίες είναι 4 ώρες.")
            == "με αμοιβή ίση με το καταβαλλόμενο ωρομίσθιο. Το όριο για υπερωρίες είναι 4 ώρες.")
    }

    /// The opinion over three documents and the summary of Law 5278/2026, as the 9 Nov 2026 run
    /// showed them.
    @Test func greekWordingOfTheThreeDocumentOpinionIsRepaired() {
        let repaired = GreekLegalOpinionWriter.repairedGreek
        #expect(repaired("σύμφωνα με την Υπουργική Απόφαση 8934 υπό Article 141Α του Εργατικού Κώδικα.")
            == "σύμφωνα με την Υπουργική Απόφαση 8934 κατ’ εξουσιοδότηση του άρθρου 141Α του Εργατικού Κώδικα.")
        #expect(repaired("ισχύει για τους εργαζόμενους και τους εργαζόμενους ολόκληρης της χώρας")
            == "ισχύει για τους εργαζόμενους ολόκληρης της χώρας")
        #expect(repaired("Αυτοί οι κανόνες ισχύουν για τους εργαζόμενους που λαμβάνουν νομικές υπερωρίες.")
            == "Αυτοί οι κανόνες ισχύουν για τους εργαζόμενους που λαμβάνουν νόμιμες υπερωρίες.")
        #expect(repaired("αμοιβή ίση με το καταβεβλημένο καταβαλλόμενο ωρομίσθιο που αυξάνεται")
            == "αμοιβή ίση με το καταβαλλόμενο ωρομίσθιο που αυξάνεται")
        #expect(repaired("αμοιβή ίση με το καταβεβλημένο ωριαίο ποσοστό") == "αμοιβή ίση με το καταβαλλόμενο ωρομίσθιο")
        #expect(repaired("του Article 7 του ν. 5239/2025") == "του άρθρου 7 του ν. 5239/2025")
        #expect(repaired("Αλλάζει κυρίως τον χρόνο παράδοσης του λεπτού του ψηφοδελτίου.")
            == "Αλλάζει κυρίως τον χρόνο παράδοσης των πρακτικών του ψηφοδελτίου.")
        // The rerun of the summary on the Mac (9 Nov 2026).
        #expect(repaired("ένα χρονοδιάγραμμα για την παράδοση των εκλογικών λεπτών μετά")
            == "ένα χρονοδιάγραμμα για την παράδοση των εκλογικών πρακτικών μετά")
        #expect(repaired("για τρεις μήνες μετά τη λήξη ή τη λήξη μιας σύμβασης")
            == "για τρεις μήνες μετά τη λήξη ή τη λύση μιας σύμβασης")
        #expect(repaired("Παρατείνει κυρίως την ισχύ των ρυθμιστικών όρων")
            == "Παρατείνει κυρίως την ισχύ των κανονιστικών όρων")
        #expect(repaired("Ο εργοδότης οφείλει να καταβάλει αυτό το αυξημένο τέλος, και")
            == "Ο εργοδότης οφείλει να καταβάλει αυτή την αυξημένη αμοιβή, και")
        // The rerun of the three-document opinion on the Mac (9 Nov 2026).
        #expect(repaired("δεν προσδιορίζεται στο Ν. 5239/2025, καθώς") == "δεν προσδιορίζεται στον ν. 5239/2025, καθώς")
        #expect(repaired("καταβάλλονται με ισοτιμία ίση με την πληρωμένη ωριαία τιμή που αυξάνεται")
            == "καταβάλλονται με αμοιβή ίση με το καταβαλλόμενο ωρομίσθιο που αυξάνεται")
        #expect(repaired("ο οποίος τροποποιεί άρθρο 194 του Εργατικού Κώδικα. ισχύει ο τροποποιημένος κανόνας.")
            == "ο οποίος τροποποιεί το άρθρο 194 του Εργατικού Κώδικα. Ισχύει ο τροποποιημένος κανόνας.")
        #expect(repaired("σύμφωνα με τα άρθρα 220 επ. του Κώδικα") == "σύμφωνα με τα άρθρα 220 επ. του Κώδικα")
        #expect(repaired("η οποία ισχύει σύμφωνα με άρθρο 141Α του Εργατικού Κώδικα. Για υπερωρίες, υπό άρθρο 7 του ν. 5239/2025,")
            == "η οποία ισχύει σύμφωνα με το άρθρο 141Α του Εργατικού Κώδικα. Για υπερωρίες, υπό το άρθρο 7 του ν. 5239/2025,")
        // Untouched: minutes of time, and a phrase that only looks repeated.
        #expect(repaired("μέσα σε 30 λεπτά από τη λήξη") == "μέσα σε 30 λεπτά από τη λήξη")
        #expect(repaired("οι εργοδότες και οι εργαζόμενοι") == "οι εργοδότες και οι εργαζόμενοι")
    }

    @Test func statuteIsLawBeforeTranslation() {
        #expect(LocalNeuralTranslator.legalEnglishPreEdited("This statute mainly changes the collective agreements.")
            == "This law mainly changes the collective agreements.")
        #expect(LocalNeuralTranslator.legalEnglishPreEdited("Statutes of 2025") == "Laws of 2025")
        #expect(LocalNeuralTranslator.legalEnglishPreEdited("the statute of limitations") == "the statute of limitations")
        #expect(!GreekLegalDocumentSummarizer.reduceInstructions.contains("statute"))
    }

    @Test func theConclusionDoesNotRestateTheLinks() {
        let link = GreekLegalOpinionWriter.CodeLink(statuteKey: "LAW:5239/2025", article: "7", kind: .amends, codeArticle: "194")
        let conclusion = "Under Article 7 of Law 5239/2025, overtime of 4 hours a day is allowed, paid at plus 40%. The employee may refuse. The amended text of Article 194 of the Labour Code, as in force for this matter."
        #expect(GreekLegalOpinionWriter.withoutRestatedLinks(conclusion, links: [link])
            == "Under Article 7 of Law 5239/2025, overtime of 4 hours a day is allowed, paid at plus 40%. The employee may refuse.")
        // A sentence with figures of its own stays, amendment or not.
        let figures = "As amended, Article 194 allows 4 hours a day."
        #expect(GreekLegalOpinionWriter.withoutRestatedLinks(figures, links: [link]) == figures)
    }

    @Test func aQuarterIsThreeMonthsBeforeTranslation() {
        #expect(LocalNeuralTranslator.legalEnglishPreEdited("Its terms apply for a quarter from the expiry.")
            == "Its terms apply for three months from the expiry.")
        #expect(LocalNeuralTranslator.legalEnglishPreEdited("in the quarter after expiry") == "in the three-month period after expiry")
        #expect(LocalNeuralTranslator.legalEnglishPreEdited("a quarter of the employees") == "a quarter of the employees")
    }

    @Test func anOpinionWithNoSupportedConclusionIsRefused() async throws {
        let sources = [GreekLegalOpinionWriter.Source(document: "other.pdf", statuteKey: "LAW:5316/2026", passages: [Self.unrelated])]
        let opinion = try await GreekLegalOpinionWriter.write(
            question: "Ποιο είναι το ποσοστό της εισφοράς;", questionEn: "What is the contribution rate?", sources: sources, links: [],
            respond: { _, _ in "Not addressed." }, translate: { $0 })
        #expect(opinion.refusal == "no document of the library addresses the question" && opinion.greek.isEmpty)
    }
}

/// One request of the opinion set.
private struct OpinionCase: Decodable {
    struct Citation: Decodable {
        let document: String
        let article: Int
    }

    let id: Int
    let topic: String
    let question: String
    let citations: [Citation]
    let keyFacts: [String]
    let split: String
}

@Suite("Greek legal opinion evaluation", .serialized,
       .enabled(if: ProcessInfo.processInfo.environment["OI_GREEK_OPINION"] == "1"))
@MainActor
struct GreekLegalOpinionEvaluation {
    @available(iOS 27.0, macOS 27.0, *)
    @Test(.timeLimit(.minutes(60)))
    func opinionSet() async throws {
        let split = ProcessInfo.processInfo.environment["OI_GREEK_OPINION_SPLIT"] ?? "dev"
        let file = GreekEvalCase.repository.appendingPathComponent("Benchmarks/GreekLabourLibrary/opinion_qa_v1.jsonl")
        let cases = try String(contentsOf: file, encoding: .utf8)
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("//") && !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { try JSONDecoder().decode(OpinionCase.self, from: Data($0.utf8)) }
            .filter { $0.split == split }
        for _ in 0..<60 where !SystemLanguageModel.default.isAvailable {
            try await Task.sleep(for: .seconds(5))
        }
        try #require(LocalNeuralTranslator.isAvailable(.englishToGreek))

        let plan = UserDefaults(suiteName: "GreekConstitutionEvaluation.plan") ?? .standard
        let store = EntitlementStore(billingService: StoreKitBillingService(), defaults: plan)
        let libraries = IntentSupport.libraries()
        let engine = RAGService(llmService: GreekEvalOnDeviceModel(), containerService: libraries, entitlementStore: store)
        for _ in 0..<100 where !engine.hasLoadedDocumentsFromDisk {
            try await Task.sleep(for: .milliseconds(100))
        }
        let libraryName = try #require(GreekEvalSet.all["GreekLabourLibrary"]).libraryName(corpus: "library")
        let library = try #require(libraries.containers.first { $0.name == libraryName }, "import the library first")
        let database = try await engine.dbForContainer(library.id)
        var statuteNumbers: [String: String] = [:]
        for document in engine.documents where document.containerId == library.id {
            let key = try await database.chunks(forDocument: document.id, limit: 1).first?.legal?.documentStatuteKey
            statuteNumbers[document.filename] = key.flatMap { $0.split(separator: ":").last?.split(separator: "/").first.map(String.init) }
        }

        var found = 0, expected = 0, factsMet = 0, factsTotal = 0, refused = 0
        for opinionCase in cases {
            let started = Date()
            let opinion = try await engine.greekLegalOpinion(question: opinionCase.question, containerId: library.id)
            let seconds = Int(Date().timeIntervalSince(started))
            let folded = GreekEvalCase.fold(opinion.greek)
            // A citation counts when the opinion names the article and the document's statute number
            // (the decision has no articles: its number alone).
            let cited = opinionCase.citations.filter { citation in
                let number = statuteNumbers[citation.document] ?? "-"
                guard folded.contains(number) else { return false }
                return citation.article == 0 || folded.range(of: #"αρθρ\w*\s+\#(citation.article)(?![\d])"#, options: .regularExpression) != nil
            }
            let expectedArticles = Set(opinionCase.citations.map(\.article))
            let ns = folded as NSString
            let citedArticles = (try? NSRegularExpression(pattern: #"αρθρ\w*\s+(\d{1,4})"#))?
                .matches(in: folded, range: NSRange(location: 0, length: ns.length))
                .compactMap { Int(ns.substring(with: $0.range(at: 1))) } ?? []
            let unexpected = Set(citedArticles).subtracting(expectedArticles).sorted()
            let missing = opinionCase.keyFacts.filter { folded.range(of: GreekEvalCase.fold($0), options: .regularExpression) == nil }
            found += cited.count
            expected += opinionCase.citations.count
            factsMet += opinionCase.keyFacts.count - missing.count
            factsTotal += opinionCase.keyFacts.count
            if opinion.refusal != nil { refused += 1 }
            print("[GreekOpinion] Q\(opinionCase.id): \(opinionCase.question)")
            print("[GreekOpinion]   sources: \(opinion.sources.map { "\($0.document) \(String(format: "%.2f", $0.bestScore))" }) links: \(GreekLegalOpinionWriter.combination(opinion.links))")
            print("[GreekOpinion]   English:\n\(opinion.english)")
            print("[GreekOpinion]   Greek:\n\(opinion.greek)")
            print("[GreekOpinion]   dropped: \(opinion.dropped)")
            print("[GreekOpinion] | \(opinionCase.id) | \(opinionCase.split) | \(opinion.refusal.map { "refused: \($0)" } ?? "written") | citations \(cited.count) of \(opinionCase.citations.count) | other articles cited \(unexpected) | facts \(opinionCase.keyFacts.count - missing.count) of \(opinionCase.keyFacts.count) | dropped \(opinion.dropped.count) | \(seconds) s |")
        }
        print("[GreekOpinion] summary split=\(split): citations \(found) of \(expected), key facts \(factsMet) of \(factsTotal), refused \(refused) of \(cases.count)")
        #expect(!cases.isEmpty)
    }
}
