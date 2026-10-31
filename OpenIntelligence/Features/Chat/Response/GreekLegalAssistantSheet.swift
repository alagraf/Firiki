//
//  GreekLegalAssistantSheet.swift
//  OpenIntelligence
//
//  Thesis fork: dedicated UI panel providing live access to the 3 Greek LegalTech PoC capabilities:
//  - Capability 2: Statute Summarization (GreekLegalDocumentSummarizer.summarize)
//  - Capability 3: Cross-Statute Legal Opinion (RAGService.greekLegalOpinion)
//  - Capability 4: Labour Contract Template Routing (LabourContractTemplateRouter.route)
//

import SwiftUI
import Foundation
import FoundationModels

enum LegalCapabilityTab: Int, CaseIterable, Identifiable, Sendable {
    case opinion = 0
    case router = 1
    case summarizer = 2

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .opinion: return "Γνωμοδότηση"
        case .router: return "Πρότυπα"
        case .summarizer: return "Σύνοψη"
        }
    }

    var subtitle: String {
        switch self {
        case .opinion: return "Legal Opinion"
        case .router: return "Contract Router"
        case .summarizer: return "Statute Summary"
        }
    }

    var icon: String {
        switch self {
        case .opinion: return "scale.3d"
        case .router: return "signature"
        case .summarizer: return "doc.text.below.ecg"
        }
    }
}

struct GreekLegalAssistantSheet: View {
    @ObservedObject var ragService: RAGService
    @State private var selectedTab: LegalCapabilityTab
    var preselectedDocument: Document?
    var onInsertReply: ((String) -> Void)?

    @Environment(\.dismiss) private var dismiss

    init(
        ragService: RAGService,
        initialTab: LegalCapabilityTab = .opinion,
        preselectedDocument: Document? = nil,
        onInsertReply: ((String) -> Void)? = nil
    ) {
        self.ragService = ragService
        _selectedTab = State(initialValue: initialTab)
        self.preselectedDocument = preselectedDocument
        self.onInsertReply = onInsertReply
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Capability Tab Picker
                Picker("Capability", selection: $selectedTab) {
                    ForEach(LegalCapabilityTab.allCases) { tab in
                        Label(tab.title, systemImage: tab.icon).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, DSSpacing.lg)
                .padding(.vertical, DSSpacing.sm)
                .background(DSColors.surface)

                Divider()

                ScrollView {
                    VStack(alignment: .leading, spacing: DSSpacing.lg) {
                        switch selectedTab {
                        case .opinion:
                            LegalOpinionTabView(ragService: ragService, onInsertReply: { content in
                                onInsertReply?(content)
                                dismiss()
                            })
                        case .router:
                            ContractRouterTabView(onInsertReply: { content in
                                onInsertReply?(content)
                                dismiss()
                            })
                        case .summarizer:
                            StatuteSummarizerTabView(
                                ragService: ragService,
                                preselectedDocument: preselectedDocument,
                                onInsertReply: { content in
                                    onInsertReply?(content)
                                    dismiss()
                                }
                            )
                        }
                    }
                    .padding(DSSpacing.lg)
                }
            }
            .background(DSColors.background.ignoresSafeArea())
            .navigationTitle("Greek Legal AI (PoC)")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - Tab 1: Legal Opinion View (Capability 3)

private struct LegalOpinionTabView: View {
    @ObservedObject var ragService: RAGService
    var onInsertReply: ((String) -> Void)?

    @State private var question = ""
    @State private var isGenerating = false
    @State private var opinion: GreekLegalOpinionWriter.Opinion?
    @State private var errorMessage: String?
    @State private var displayLanguage: LanguageSelection = .greek

    private enum LanguageSelection: String, CaseIterable, Identifiable {
        case greek = "Ελληνικά"
        case english = "English"
        var id: String { rawValue }
    }

    private let sampleQuestions: [(title: String, query: String)] = [
        ("Καταγγελία Αορίστου Χρόνου", "Ποιες είναι οι νόμιμες προϋποθέσεις για την καταγγελία σύμβασης εργασίας αορίστου χρόνου;"),
        ("Όρια Υπερωριών", "Ποιο είναι το ανώτατο όριο ημερήσιας και εβδομαδιαίας υπερωριακής απασχόλησης;"),
        ("Άδειες Μητρότητας", "Ποιες οι άδειες μητρότητας και γονικές άδειες σύμφωνα με το ισχύον εργατικό δίκαιο;"),
        ("Τηλεργασία & Αποσύνδεση", "Ποιες ρυθμίσεις ισχύουν για την τηλεργασία και το δικαίωμα αποσύνδεσης;")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            SurfaceCard {
                SectionHeader(
                    icon: "scale.3d",
                    title: "Νομική Γνωμοδότηση (Cross-Statute Opinion)",
                    caption: "Σύνθεση 6 κανονικών ενοτήτων με ανίχνευση τροποποιήσεων και επαλήθευση παραπομπών."
                )

                Text("Εισάγετε το νομικό σας ερώτημα στα ελληνικά ή επιλέξτε από τα προτεινόμενα υποδείγματα:")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.secondaryText)

                // Suggestion chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.sm) {
                        ForEach(sampleQuestions, id: \.title) { item in
                            Button {
                                question = item.query
                                DSHaptics.light()
                            } label: {
                                Text(item.title)
                                    .font(DSTypography.chip)
                                    .padding(.horizontal, DSSpacing.md)
                                    .padding(.vertical, DSSpacing.xs)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    .foregroundStyle(DSColors.primaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField("Πληκτρολογήστε το νομικό ερώτημα...", text: $question, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(DSSpacing.md)
                    .background(DSColors.background, in: RoundedRectangle(cornerRadius: DSCorners.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCorners.card)
                            .stroke(DSColors.border, lineWidth: 1)
                    )

                HStack {
                    Spacer()
                    Button {
                        synthesizeOpinion()
                    } label: {
                        HStack(spacing: DSSpacing.sm) {
                            if isGenerating {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text(isGenerating ? "Σύνταξη..." : "Σύνταξη Γνωμοδότησης")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, DSSpacing.lg)
                        .padding(.vertical, DSSpacing.sm)
                        .background(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating ? Color.gray.opacity(0.3) : DSColors.accent)
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                }
            }

            if let error = errorMessage {
                SurfaceCard {
                    HStack(spacing: DSSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(DSTypography.body)
                            .foregroundStyle(.red)
                    }
                }
            }

            if let op = opinion {
                SurfaceCard {
                    HStack {
                        SectionHeader(icon: "doc.text.fill", title: "Αποτέλεσμα Γνωμοδότησης")
                        Spacer()
                        Picker("Language", selection: $displayLanguage) {
                            ForEach(LanguageSelection.allCases) { lang in
                                Text(lang.rawValue).tag(lang)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                    }

                    if !op.sources.isEmpty {
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text("Πηγές:")
                                .font(DSTypography.meta)
                                .foregroundStyle(DSColors.secondaryText)
                            WrappingRowLayout(spacing: DSSpacing.xs, lineSpacing: DSSpacing.xs) {
                                ForEach(op.sources, id: \.document) { src in
                                    Text(src.name)
                                        .font(DSTypography.meta)
                                        .padding(.horizontal, DSSpacing.sm)
                                        .padding(.vertical, DSSpacing.xxs)
                                        .background(DSColors.systemGray6, in: Capsule())
                                }
                            }
                        }
                    }

                    if !op.links.isEmpty {
                        VStack(alignment: .leading, spacing: DSSpacing.xs) {
                            Text("Ανιχνευθείσες Τροποποιήσεις:")
                                .font(DSTypography.meta)
                                .foregroundStyle(DSColors.secondaryText)
                            ForEach(op.links, id: \.codeArticle) { link in
                                HStack(spacing: DSSpacing.xs) {
                                    Image(systemName: "arrow.triangle.branch")
                                        .font(DSTypography.meta)
                                        .foregroundStyle(DSColors.accent)
                                    Text("\(link.statuteKey) \(link.kind.rawValue) Άρθρο \(link.codeArticle)")
                                        .font(DSTypography.meta)
                                }
                            }
                        }
                    }

                    Divider()

                    MarkdownText(displayLanguage == .greek ? op.greek : op.english)
                        .padding(.vertical, DSSpacing.xs)

                    Divider()

                    HStack(spacing: DSSpacing.md) {
                        Button {
                            let text = displayLanguage == .greek ? op.greek : op.english
                            SystemClipboard.copy(text)
                            DSHaptics.success()
                        } label: {
                            Label("Αντιγραφή", systemImage: "doc.on.doc")
                                .font(DSTypography.body)
                                .padding(.horizontal, DSSpacing.md)
                                .padding(.vertical, DSSpacing.sm)
                                .background(DSColors.systemGray6, in: RoundedRectangle(cornerRadius: DSCorners.chip))
                        }
                        .buttonStyle(.plain)

                        if let onInsert = onInsertReply {
                            Button {
                                let text = displayLanguage == .greek ? op.greek : op.english
                                onInsert(text)
                            } label: {
                                Label("Εισαγωγή στη Συνομιλία", systemImage: "arrow.down.message.fill")
                                    .font(DSTypography.body)
                                    .padding(.horizontal, DSSpacing.md)
                                    .padding(.vertical, DSSpacing.sm)
                                    .background(DSColors.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: DSCorners.chip))
                                    .foregroundStyle(DSColors.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func synthesizeOpinion() {
        guard !question.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isGenerating = true
        errorMessage = nil
        DSHaptics.light()

        Task {
            do {
                let containerId = ragService.containerService.activeContainerId
                let result = try await ragService.greekLegalOpinion(question: question, containerId: containerId)
                await MainActor.run {
                    self.opinion = result
                    self.isGenerating = false
                    DSHaptics.success()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Σφάλμα κατά τη σύνταξη: \(error.localizedDescription)"
                    self.isGenerating = false
                }
            }
        }
    }
}

// MARK: - Tab 2: Contract Template Router View (Capability 4)

private struct ContractRouterTabView: View {
    var onInsertReply: ((String) -> Void)?

    @State private var prompt = ""
    @State private var isRouting = false
    @State private var decision: LabourContractTemplateRouter.Decision?
    @State private var expandedTemplateBody = false
    @State private var showAllTemplatesModal = false

    private let samplePresets: [(title: String, text: String)] = [
        ("Πλήρης Απασχόληση", "Πρόσληψη υπαλλήλου γραφείου πλήρους απασχόλησης αορίστου χρόνου με δοκιμαστική περίοδο 6 μηνών"),
        ("Ορισμένου Χρόνου", "Εποχική σύμβαση ορισμένου χρόνου διάρκειας 4 μηνών σε τουριστική επιχείρηση"),
        ("Μερική Απασχόληση", "Σύμβαση μερικής απασχόλησης 20 ωρών εβδομαδιαίως με σταθερό ωράριο"),
        ("Τηλεργασία", "Σύμβαση εργασίας εξ αποστάσεως (τηλεργασία) με παροχή εξοπλισμού και κάλυψη τηλεπικοινωνιών"),
        ("Μαθητεία / Πρακτική", "Σύμβαση μαθητείας και πρακτικής άσκησης σπουδαστή σε τεχνική εταιρεία"),
        ("Εκ Περιτροπής", "Σύμβαση εκ περιτροπής εργασίας 3 ημέρες την εβδομάδα")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            SurfaceCard {
                SectionHeader(
                    icon: "signature",
                    title: "Δρομολόγηση Προτύπων Συμβάσεων (Contract Router)",
                    caption: "Αυτόματη επιλογή από τα 10 επίσημα υποδείγματα συμβάσεων εργασίας μέσω AFM 3."
                )

                Text("Περιγράψτε τους όρους απασχόλησης ή επιλέξτε ένα υπόδειγμα:")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.secondaryText)

                // Presets
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: DSSpacing.sm) {
                        ForEach(samplePresets, id: \.title) { item in
                            Button {
                                prompt = item.text
                                DSHaptics.light()
                            } label: {
                                Text(item.title)
                                    .font(DSTypography.chip)
                                    .padding(.horizontal, DSSpacing.md)
                                    .padding(.vertical, DSSpacing.xs)
                                    .background(Color.accentColor.opacity(0.12), in: Capsule())
                                    .foregroundStyle(DSColors.primaryText)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                TextField("Εισάγετε όρους σύμβασης (π.χ. ωράριο, διάρκεια, είδος)...", text: $prompt, axis: .vertical)
                    .lineLimit(3...6)
                    .padding(DSSpacing.md)
                    .background(DSColors.background, in: RoundedRectangle(cornerRadius: DSCorners.card))
                    .overlay(
                        RoundedRectangle(cornerRadius: DSCorners.card)
                            .stroke(DSColors.border, lineWidth: 1)
                    )

                HStack {
                    Button {
                        showAllTemplatesModal = true
                    } label: {
                        Label("Περιήγηση στα 10 Πρότυπα", systemImage: "folder")
                            .font(DSTypography.meta)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Button {
                        routeContract()
                    } label: {
                        HStack(spacing: DSSpacing.sm) {
                            if isRouting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.triangle.branch")
                            }
                            Text(isRouting ? "Δρομολόγηση..." : "Εύρεση Προτύπου")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, DSSpacing.lg)
                        .padding(.vertical, DSSpacing.sm)
                        .background(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRouting ? Color.gray.opacity(0.3) : DSColors.accent)
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isRouting)
                }
            }

            if let dec = decision {
                if let tmpl = dec.template {
                    SurfaceCard {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                                Text(tmpl.titleEl)
                                    .font(.headline)
                                    .foregroundStyle(DSColors.primaryText)
                                Text(tmpl.titleEn)
                                    .font(DSTypography.caption)
                                    .foregroundStyle(DSColors.secondaryText)
                            }
                            Spacer()
                            Text(dec.method == .model ? "AFM 3 Model" : "Keyword Fallback")
                                .font(DSTypography.meta)
                                .padding(.horizontal, DSSpacing.sm)
                                .padding(.vertical, DSSpacing.xxs)
                                .background(dec.method == .model ? Color.green.opacity(0.15) : Color.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(dec.method == .model ? Color.green : Color.orange)
                        }

                        if !dec.reason.isEmpty {
                            Text("Αιτιολόγηση: \(dec.reason)")
                                .font(DSTypography.body)
                                .foregroundStyle(DSColors.secondaryText)
                        }

                        if !tmpl.articles.isEmpty {
                            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                                Text("Εφαρμοστέα Άρθρα Εργατικού Κώδικα:")
                                    .font(DSTypography.meta)
                                    .foregroundStyle(DSColors.secondaryText)
                                WrappingRowLayout(spacing: DSSpacing.xs, lineSpacing: DSSpacing.xs) {
                                    ForEach(tmpl.articles, id: \.self) { art in
                                        Text(art)
                                            .font(DSTypography.meta)
                                            .padding(.horizontal, DSSpacing.xs)
                                            .padding(.vertical, DSSpacing.xxs)
                                            .background(DSColors.systemGray6, in: RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                            }
                        }

                        Divider()

                        // Full template disclosure
                        DisclosureGroup("Προεπισκόπηση Πλήρους Κειμένου Σύμβασης", isExpanded: $expandedTemplateBody) {
                            ScrollView {
                                MarkdownText(tmpl.body)
                                    .frame(maxHeight: 320)
                            }
                            .padding(.top, DSSpacing.sm)
                        }

                        Divider()

                        HStack(spacing: DSSpacing.md) {
                            Button {
                                SystemClipboard.copy(tmpl.body)
                                DSHaptics.success()
                            } label: {
                                Label("Αντιγραφή Προτύπου", systemImage: "doc.on.doc")
                                    .font(DSTypography.body)
                                    .padding(.horizontal, DSSpacing.md)
                                    .padding(.vertical, DSSpacing.sm)
                                    .background(DSColors.systemGray6, in: RoundedRectangle(cornerRadius: DSCorners.chip))
                            }
                            .buttonStyle(.plain)

                            if let onInsert = onInsertReply {
                                Button {
                                    onInsert("### \(tmpl.titleEl)\n\n\(tmpl.body)")
                                } label: {
                                    Label("Εισαγωγή στη Συνομιλία", systemImage: "arrow.down.message.fill")
                                        .font(DSTypography.body)
                                        .padding(.horizontal, DSSpacing.md)
                                        .padding(.vertical, DSSpacing.sm)
                                        .background(DSColors.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: DSCorners.chip))
                                        .foregroundStyle(DSColors.accent)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                } else {
                    SurfaceCard {
                        HStack(spacing: DSSpacing.sm) {
                            Image(systemName: "info.circle.fill")
                                .foregroundStyle(.blue)
                            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                                Text("Κανένα πρότυπο δεν ταίριαξε")
                                    .font(.headline)
                                Text(dec.reason.isEmpty ? "Το αίτημα αφορά άλλο αντικείμενο ή ερώτηση γενικού δικαίου." : dec.reason)
                                    .font(DSTypography.body)
                                    .foregroundStyle(DSColors.secondaryText)
                            }
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showAllTemplatesModal) {
            AllBundledTemplatesView()
        }
    }

    private func routeContract() {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isRouting = true
        DSHaptics.light()

        Task {
            let res = await LabourContractTemplateRouter.route(prompt)
            await MainActor.run {
                self.decision = res
                self.expandedTemplateBody = true
                self.isRouting = false
                DSHaptics.success()
            }
        }
    }
}

// MARK: - Tab 3: Statute Summarizer View (Capability 2)

private struct StatuteSummarizerTabView: View {
    @ObservedObject var ragService: RAGService
    var preselectedDocument: Document?
    var onInsertReply: ((String) -> Void)?

    @State private var selectedDocumentId: UUID?
    @State private var isSummarizing = false
    @State private var summary: GreekLegalDocumentSummarizer.Summary?
    @State private var errorMessage: String?
    @State private var displayLanguage: LanguageSelection = .greek

    private enum LanguageSelection: String, CaseIterable, Identifiable {
        case greek = "Ελληνικά"
        case english = "English"
        var id: String { rawValue }
    }

    private var availableDocuments: [Document] {
        ragService.documents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.lg) {
            SurfaceCard {
                SectionHeader(
                    icon: "doc.text.below.ecg",
                    title: "Σύνοψη Νομοθετήματος (Statute Summarizer)",
                    caption: "Ιεραρχική σύνοψη Map-Reduce άρθρο προς άρθρο με έλεγχο μη τεκμηριωμένων στοιχείων."
                )

                Text("Επιλέξτε ένα εισαγόμενο νομοθέτημα ή έγγραφο από τη βιβλιοθήκη για σύνοψη:")
                    .font(DSTypography.body)
                    .foregroundStyle(DSColors.secondaryText)

                if availableDocuments.isEmpty {
                    Text("Δεν υπάρχουν έγγραφα στη βιβλιοθήκη. Εισαγάγετε ένα νόμο ή ΦΕΚ στην καρτέλα 'Documents'.")
                        .font(DSTypography.caption)
                        .foregroundStyle(.orange)
                        .padding(.vertical, DSSpacing.xs)
                } else {
                    Picker("Νομοθέτημα", selection: $selectedDocumentId) {
                        Text("Επιλέξτε έγγραφο...").tag(nil as UUID?)
                        ForEach(availableDocuments) { doc in
                            Text(doc.filename).tag(doc.id as UUID?)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(DSSpacing.sm)
                    .background(DSColors.systemGray6, in: RoundedRectangle(cornerRadius: DSCorners.control))
                }

                HStack {
                    Spacer()
                    Button {
                        summarizeDocument()
                    } label: {
                        HStack(spacing: DSSpacing.sm) {
                            if isSummarizing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "text.quote")
                            }
                            Text(isSummarizing ? "Σύνοψη..." : "Σύνοψη Νομοθετήματος")
                                .fontWeight(.semibold)
                        }
                        .padding(.horizontal, DSSpacing.lg)
                        .padding(.vertical, DSSpacing.sm)
                        .background(selectedDocumentId == nil || isSummarizing ? Color.gray.opacity(0.3) : DSColors.accent)
                        .foregroundStyle(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: DSCorners.control, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(selectedDocumentId == nil || isSummarizing)
                }
            }
            .onAppear {
                if let pre = preselectedDocument {
                    selectedDocumentId = pre.id
                } else if selectedDocumentId == nil, let first = availableDocuments.first {
                    selectedDocumentId = first.id
                }
            }

            if let error = errorMessage {
                SurfaceCard {
                    HStack(spacing: DSSpacing.sm) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(error)
                            .font(DSTypography.body)
                            .foregroundStyle(.red)
                    }
                }
            }

            if let sum = summary {
                SurfaceCard {
                    HStack {
                        SectionHeader(icon: "checkmark.seal.fill", title: "Επίσημη Σύνοψη Νόμου")
                        Spacer()
                        Picker("Language", selection: $displayLanguage) {
                            ForEach(LanguageSelection.allCases) { lang in
                                Text(lang.rawValue).tag(lang)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 170)
                    }

                    // Quality and verification audit chips
                    HStack(spacing: DSSpacing.sm) {
                        Label("\(sum.groups) ομάδες άρθρων", systemImage: "square.grid.2x2")
                            .font(DSTypography.meta)
                            .padding(.horizontal, DSSpacing.xs)
                            .padding(.vertical, DSSpacing.xxs)
                            .background(DSColors.systemGray6, in: Capsule())

                        Label("\(sum.noteCharacters) χαρακτήρες σημειώσεων", systemImage: "character.book.closed")
                            .font(DSTypography.meta)
                            .padding(.horizontal, DSSpacing.xs)
                            .padding(.vertical, DSSpacing.xxs)
                            .background(DSColors.systemGray6, in: Capsule())

                        if !sum.dropped.isEmpty {
                            Label("\(sum.dropped.count) αφαιρεθείσες μη τεκμηριωμένες φράσεις", systemImage: "shield.lefthalf.filled")
                                .font(DSTypography.meta)
                                .padding(.horizontal, DSSpacing.xs)
                                .padding(.vertical, DSSpacing.xxs)
                                .background(Color.green.opacity(0.12), in: Capsule())
                                .foregroundStyle(Color.green)
                        }
                    }

                    Divider()

                    MarkdownText(displayLanguage == .greek ? sum.greek : sum.english)
                        .padding(.vertical, DSSpacing.xs)

                    Divider()

                    HStack(spacing: DSSpacing.md) {
                        Button {
                            let text = displayLanguage == .greek ? sum.greek : sum.english
                            SystemClipboard.copy(text)
                            DSHaptics.success()
                        } label: {
                            Label("Αντιγραφή", systemImage: "doc.on.doc")
                                .font(DSTypography.body)
                                .padding(.horizontal, DSSpacing.md)
                                .padding(.vertical, DSSpacing.sm)
                                .background(DSColors.systemGray6, in: RoundedRectangle(cornerRadius: DSCorners.chip))
                        }
                        .buttonStyle(.plain)

                        if let onInsert = onInsertReply {
                            Button {
                                let text = displayLanguage == .greek ? sum.greek : sum.english
                                onInsert(text)
                            } label: {
                                Label("Εισαγωγή στη Συνομιλία", systemImage: "arrow.down.message.fill")
                                    .font(DSTypography.body)
                                    .padding(.horizontal, DSSpacing.md)
                                    .padding(.vertical, DSSpacing.sm)
                                    .background(DSColors.accent.opacity(0.15), in: RoundedRectangle(cornerRadius: DSCorners.chip))
                                    .foregroundStyle(DSColors.accent)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func summarizeDocument() {
        guard let docId = selectedDocumentId else { return }
        isSummarizing = true
        errorMessage = nil
        DSHaptics.light()

        Task {
            do {
                let containerId = ragService.containerService.activeContainerId
                let database = try await ragService.dbForContainer(containerId)
                let chunks = try await database.chunks(forDocument: docId).sorted { $0.metadata.chunkIndex < $1.metadata.chunkIndex }
                guard !chunks.isEmpty else {
                    await MainActor.run {
                        self.errorMessage = "Το έγγραφο δεν διαθέτει επεξεργασμένα αποσπάσματα."
                        self.isSummarizing = false
                    }
                    return
                }
                let passages = chunks.map { $0.content }
                let statuteKey = chunks.lazy.compactMap { $0.legal?.documentStatuteKey }.first
                let res = try await GreekLegalDocumentSummarizer.summarize(passages: passages, statuteKey: statuteKey)

                await MainActor.run {
                    self.summary = res
                    self.isSummarizing = false
                    DSHaptics.success()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Σφάλμα σύνοψης: \(error.localizedDescription)"
                    self.isSummarizing = false
                }
            }
        }
    }
}

// MARK: - All Bundled Templates Browser Modal

private struct AllBundledTemplatesView: View {
    @Environment(\.dismiss) private var dismiss
    private let templates = LabourContractTemplateRouter.bundledTemplates()
    @State private var selectedTemplate: LabourContractTemplate?

    var body: some View {
        NavigationStack {
            List(templates, id: \.id) { tmpl in
                VStack(alignment: .leading, spacing: DSSpacing.xs) {
                    HStack {
                        Text("\(tmpl.number). \(tmpl.titleEl)")
                            .font(.headline)
                        Spacer()
                        Text(tmpl.id)
                            .font(DSTypography.meta)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                    Text(tmpl.titleEn)
                        .font(DSTypography.caption)
                        .foregroundStyle(DSColors.secondaryText)
                    Text(tmpl.descriptionEl)
                        .font(DSTypography.body)
                        .lineLimit(2)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    selectedTemplate = tmpl
                }
            }
            .navigationTitle("Πρότυπα Συμβάσεων (\(templates.count))")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Κλείσιμο") { dismiss() }
                }
            }
            .sheet(item: $selectedTemplate) { tmpl in
                NavigationStack {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DSSpacing.md) {
                            Text(tmpl.titleEl)
                                .font(.title2.weight(.bold))
                            Text(tmpl.descriptionEl)
                                .font(DSTypography.body)
                                .foregroundStyle(DSColors.secondaryText)
                            Divider()
                            MarkdownText(tmpl.body)
                        }
                        .padding(DSSpacing.lg)
                    }
                    .navigationTitle(tmpl.titleEl)
                    #if os(iOS)
                    .navigationBarTitleDisplayMode(.inline)
                    #endif
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Κλείσιμο") { selectedTemplate = nil }
                        }
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                SystemClipboard.copy(tmpl.body)
                                DSHaptics.success()
                            } label: {
                                Label("Αντιγραφή", systemImage: "doc.on.doc")
                            }
                        }
                    }
                }
            }
        }
    }
}

extension LabourContractTemplate: @retroactive Identifiable {}
