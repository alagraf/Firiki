//
//  GreekLegalContextChunkingTests.swift
//  OpenIntelligenceTests
//
//  Thesis fork: unit tests for context-aware document classification and chunking
//  (Statute vs Lawyer's Notes vs Q&A vs Generic prose).
//

import Foundation
import Testing
@testable import OpenIntelligence

@Suite("Context-Aware Greek Legal Chunking")
struct GreekLegalContextChunkingTests {

    // MARK: - Classification Rules Tests

    @Test func classifiesStatuteWithGazetteAndArticles() {
        let statuteText = """
        ΕΦΗΜΕΡΙΔΑ ΤΗΣ ΚΥΒΕΡΝΗΣΕΩΣ
        ΤΗΣ ΕΛΛΗΝΙΚΗΣ ΔΗΜΟΚΡΑΤΙΑΣ
        Τεύχος Α’ 120/15.06.2025

        ΝΟΜΟΣ ΥΠ' ΑΡΙΘ. 5278
        Ρυθμίσεις για την απασχόληση και την αγορά εργασίας.

        Άρθρο 1
        Σκοπός και πεδίο εφαρμογής
        1. Με τον παρόντα νόμο ρυθμίζονται τα ζητήματα της εργασίας και της προστασίας των εργαζομένων.
        2. Οι διατάξεις εφαρμόζονται σε όλους τους μισθωτούς του ιδιωτικού τομέα.

        Άρθρο 2
        Χρονικά όρια εργασίας
        1. Η πλήρης εβδομαδιαία απασχόληση ορίζεται σε σαράντα (40) ώρες.
        2. Επιτρέπεται η κατανομή σε πενθήμερη ή εξαήμερη βάση.

        Άρθρο 3
        Υπερωριακή απασχόληση
        1. Για κάθε ώρα υπερωρίας καταβάλλεται προσαύξηση σαράντα τοις εκατό (40%).
        """

        let result = GreekLegalDocumentClassifier.classifyByRules(text: statuteText, filename: "nomos-5278.pdf")
        #expect(result?.kind == .statute)
    }

    @Test func unarticledGazetteDecisionFallsBackToGenericChunking() {
        let ministerialDecision = """
        ΕΦΗΜΕΡΙΔΑ ΤΗΣ ΚΥΒΕΡΝΗΣΕΩΣ
        ΤΗΣ ΕΛΛΗΝΙΚΗΣ ΔΗΜΟΚΡΑΤΙΑΣ
        Τεύχος Β’ 1759/27.03.2026
        ΑΠΟΦΑΣΕΙΣ
        Αριθμ. 8934
        Καθορισμός νόμιμου κατώτατου μισθού και νόμιμου κατώτατου ημερομισθίου.
        α) Για τους υπαλλήλους ο κατώτατος μισθός ορίζεται στα εννιακόσια είκοσι ευρώ (920,00 €).
        β) Για τους εργατοτέχνες το κατώτατο ημερομίσθιο ορίζεται σε σαράντα ένα ευρώ και εννέα λεπτά (41,09 €).
        """
        let result = GreekLegalDocumentClassifier.classifyByRules(text: ministerialDecision, filename: "ya_8934_2026_fek_b1759.pdf")
        #expect(result?.kind == .generic)
    }

    @Test func classifiesQADocumentInGreekAndEnglish() {
        let greekQAText = """
        Συχνές Ερωτήσεις για τα Εργασιακά Δικαιώματα

        Ερώτηση 1: Πόσες ημέρες κανονικής άδειας δικαιούμαι τον πρώτο χρόνο;
        Απάντηση: Κατά τον πρώτο χρόνο απασχόλησης, ο εργαζόμενος δικαιούται αναλογία είκοσι (20) εργάσιμων ημερών επί πενθημέρου ή είκοσι τεσσάρων (24) επί εξαημέρου.

        Ερώτηση 2: Πότε καταβάλλεται το επίδομα αδείας;
        Απάντηση: Το επίδομα αδείας προκαταβάλλεται κατά την έναρξη της κανονικής άδειας του μισθωτού.

        Ερώτηση 3: Πώς υπολογίζεται η αποζημίωση απόλυσης;
        Απάντηση: Υπολογίζεται βάσει των τακτικών αποδοχών του τελευταίου μήνα υπό καθεστώς πλήρους απασχόλησης.
        """

        let resultGreek = GreekLegalDocumentClassifier.classifyByRules(text: greekQAText, filename: "faq-labour.txt")
        #expect(resultGreek?.kind == .questionAnswer)

        let englishQAText = """
        Frequently Asked Questions: Employment Law

        Question 1: What is the maximum duration of probation?
        Answer: Under the new statutory framework, probation period cannot exceed six months.

        Question 2: Are employers required to record telework equipment?
        Answer: Yes, employers must cover equipment and maintenance costs and provide technical support.

        Question 3: What is the severance calculation formula?
        Answer: Severance is calculated on the basis of regular monthly wages multiplied by the service bracket.
        """

        let resultEnglish = GreekLegalDocumentClassifier.classifyByRules(text: englishQAText, filename: "faq_en.txt")
        #expect(resultEnglish?.kind == .questionAnswer)
    }

    @Test func classifiesLawyerNotesEvenWhenQuotingArticles() {
        // Critical test: A lawyer's memo quoting articles (Άρθρο 5, Άρθρο 8, Άρθρο 12)
        // must be classified as lawyerNotes, NOT as a statute!
        let lawyerMemo = """
        ΓΝΩΜΟΔΟΤΙΚΟ ΣΗΜΕΙΩΜΑ
        Προς: Διοίκηση Ανώνυμης Εταιρείας
        Ημερομηνία: 20 Οκτωβρίου 2026

        ΙΣΤΟΡΙΚΟ
        Η εντολέας εταιρεία απασχολεί προσωπικό με καθεστώς τηλεργασίας. Ανέκυψε ζήτημα σχετικά με το ωράριο εργασίας και την αποζημίωση εξοπλισμού.

        ΕΡΩΤΗΜΑ
        Εάν υφίσταται υποχρέωση καταβολής μηνιαίου ποσού για την κάλυψη τηλεπικοινωνιακού κόστους.

        ΝΟΜΙΚΗ ΑΝΑΛΥΣΗ
        Σύμφωνα με το Άρθρο 5 του σχετικού νόμου, ο εργοδότης αναλαμβάνει το κόστος εξοπλισμού. Επιπλέον, το Άρθρο 8 ορίζει το πλαίσιο ελέγχου, ενώ το Άρθρο 12 προβλέπει το δικαίωμα αποσύνδεσης.

        ΣΥΜΠΕΡΑΣΜΑ
        Κατά την άποψή μας, η εταιρεία οφείλει να καταβάλλει τη σχετική μηνιαία αποζημίωση όπως ορίζεται στις ισχύουσες υπουργικές αποφάσεις.
        """

        let result = GreekLegalDocumentClassifier.classifyByRules(text: lawyerMemo, filename: "memo_telework.pdf")
        #expect(result?.kind == .lawyerNotes)
    }

    @Test func classifiesGenericProse() {
        let genericText = """
        Η εξέλιξη της βιομηχανίας στην Ελλάδα κατά τον 20ό αιώνα.
        Κατά τις πρώτες δεκαετίες, η ελληνική οικονομία παρέμενε κυρίως αγροτική.
        Σταδιακά, η ανάπτυξη των αστικών κέντρων και η εισροή κεφαλαίων οδήγησαν
        στη δημιουργία των πρώτων μεγάλων βιομηχανικών μονάδων στην Αττική και τη Θεσσαλονίκη.
        """

        let result = GreekLegalDocumentClassifier.classifyByRules(text: genericText, filename: "history_essay.txt")
        #expect(result?.kind == .generic)
    }

    // MARK: - QA Chunker Tests

    @Test func qaChunkerKeepsQuestionWithAnswer() {
        let qaText = """
        Ερώτηση 1: Ποιο είναι το ωράριο εργασίας των μισθωτών;
        Απάντηση: Το συμβατικό ωράριο πλήρους απασχόλησης ανέρχεται σε 40 ώρες εβδομαδιαίως, οι οποίες κατανέμονται σε πενθήμερη ή εξαήμερη εβδομαδιαία εργασία.

        Ερώτηση 2: Επιτρέπεται η υπερεργασία;
        Απάντηση: Ναι, επιτρέπεται μέχρι πέντε ώρες την εβδομάδα επί πενθημέρου με προσαύξηση 20% στο καταβαλλόμενο ωρομίσθιο.
        """

        let passages = GreekLegalQAChunker.passages(in: qaText, maxWords: 200, minWords: 20)
        #expect(passages.count == 2)

        #expect(passages[0].question.contains("ωράριο εργασίας"))
        #expect(passages[0].text.contains("Ερώτηση 1:"))
        #expect(passages[0].text.contains("Απάντηση:"))
        #expect(passages[0].text.contains("40 ώρες εβδομαδιαίως"))

        #expect(passages[1].question.contains("υπερεργασία"))
        #expect(passages[1].text.contains("Ερώτηση 2:"))
        #expect(passages[1].text.contains("20%"))
    }

    @Test func qaChunkerRepeatsQuestionHeaderWhenSplittingLongAnswer() {
        let longAnswer = String(repeating: "Αυτή είναι μια αναλυτική επεξήγηση του νομικού πλαισίου με πολλές λεπτομέρειες και ανάλυση διατάξεων. ", count: 20)
        let qaText = """
        Ερώτηση: Ποιες είναι οι υποχρεώσεις του εργοδότη κατά την τηλεργασία;
        Απάντηση: \(longAnswer)
        """

        let passages = GreekLegalQAChunker.passages(in: qaText, maxWords: 60, minWords: 20)
        #expect(passages.count > 1)
        for passage in passages {
            // Every single passage must keep the question at the top!
            #expect(passage.text.contains("Ερώτηση: Ποιες είναι οι υποχρεώσεις"))
        }
    }

    // MARK: - Lawyer Notes Chunker Tests

    @Test func notesChunkerCutsAlongMemoHeadingsNotInternalArticles() {
        let memoText = """
        ΙΣΤΟΡΙΚΟ
        Ο εργαζόμενος προσελήφθη την 1η Ιανουαρίου 2022 με σύμβαση αορίστου χρόνου.
        Κατά τη διάρκεια της απασχόλησής του παρείχε υπηρεσίες ως λογιστής.

        ΕΡΩΤΗΜΑ
        Εάν η καταγγελία της σύμβασης απαιτεί προειδοποίηση.

        ΝΟΜΙΚΗ ΑΝΑΛΥΣΗ
        Σύμφωνα με το Άρθρο 322 του Π.Δ. 62/2025, η καταγγελία σύμβασης εξαρτημένης εργασίας αορίστου χρόνου δύναται να γίνει με ή χωρίς προειδοποίηση. Επίσης, το Άρθρο 323 ορίζει τον χρόνο προειδοποίησης ανάλογα με τα έτη υπηρεσίας.

        ΣΥΜΠΕΡΑΣΜΑ
        Απαιτείται έγγραφη προειδοποίηση δύο μηνών, καθώς η διάρκεια υπηρεσίας υπερβαίνει τα δύο έτη.
        """

        let passages = GreekLegalNotesChunker.passages(in: memoText, maxWords: 200, minWords: 20)
        #expect(passages.count == 4)

        #expect(passages[0].header == "ΙΣΤΟΡΙΚΟ")
        #expect(passages[1].header == "ΕΡΩΤΗΜΑ")
        #expect(passages[2].header == "ΝΟΜΙΚΗ ΑΝΑΛΥΣΗ")
        #expect(passages[3].header == "ΣΥΜΠΕΡΑΣΜΑ")

        // The passage for "ΝΟΜΙΚΗ ΑΝΑΛΥΣΗ" must contain both Article 322 and Article 323 intact!
        #expect(passages[2].text.contains("Άρθρο 322"))
        #expect(passages[2].text.contains("Άρθρο 323"))
    }
}
