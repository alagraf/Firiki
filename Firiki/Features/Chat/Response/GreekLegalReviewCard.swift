//
//  GreekLegalReviewCard.swift
//  Firiki
//
//  Thesis fork, plan phase F: the Greek legal review of an answer under Response Details. Shows
//  whether the English draft was verified and translated or replaced by the abstention message,
//  each verification gate's result, the English draft and the question as the gates read it, and
//  which model assets wrote the answer (on device or Private Cloud Compute).
//

import SwiftUI

struct GreekLegalReviewCard: View {
    let review: LegalAnswerReview

    @State private var showDraft = false

    var body: some View {
        VStack(alignment: .leading, spacing: DSSpacing.md) {
            Label("Greek legal review", systemImage: "checkmark.shield.fill")
                .scaledFont(size: 14, weight: .semibold)
                .foregroundStyle(DSColors.secondaryText)

            HStack(alignment: .top, spacing: DSSpacing.sm) {
                Image(systemName: review.abstained ? "hand.raised.fill" : "checkmark.seal.fill")
                    .scaledFont(size: 18, weight: .semibold)
                    .foregroundStyle(review.abstained ? Color.orange : Color.green)
                VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                    Text(review.abstained ? "Not answered: abstained" : "Verified, then translated to Greek")
                        .scaledFont(size: 14, weight: .semibold)
                        .foregroundStyle(DSColors.primaryText)
                    if let reason = review.reason {
                        Text(reason)
                            .scaledFont(size: 12)
                            .foregroundStyle(DSColors.secondaryText)
                            .textSelection(.enabled)
                    }
                }
                Spacer()
                if !review.gates.isEmpty {
                    VStack(alignment: .trailing, spacing: DSSpacing.xxs) {
                        Text(String(format: "%.0f%%", review.overallConfidence * 100))
                            .scaledFont(size: 16, weight: .bold, design: .rounded)
                            .monospacedDigit()
                            .foregroundStyle(DSColors.primaryText)
                        Text("gate confidence")
                            .scaledFont(size: 10)
                            .foregroundStyle(DSColors.secondaryText)
                    }
                }
            }

            if !review.gates.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: DSSpacing.sm) {
                    ForEach(Array(review.gates.enumerated()), id: \.offset) { _, gate in
                        HStack(alignment: .top, spacing: DSSpacing.sm) {
                            Image(systemName: gate.passed ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .scaledFont(size: 13)
                                .foregroundStyle(gate.passed ? Color.green : Color.red)
                            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                                Text(gate.gate)
                                    .scaledFont(size: 12, weight: .semibold)
                                    .foregroundStyle(DSColors.primaryText)
                                Text(gate.details)
                                    .scaledFont(size: 11)
                                    .foregroundStyle(DSColors.secondaryText)
                                    .lineLimit(4)
                                    .textSelection(.enabled)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(gate.gate), \(gate.passed ? "passed" : "failed"). \(gate.details)")
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text("Model: \(review.modelUsed)")
                    .scaledFont(size: 12)
                    .foregroundStyle(DSColors.secondaryText)
                Text("Model assets: \(review.assetIDs.isEmpty ? "not reported" : review.assetIDs.joined(separator: ", "))")
                    .scaledFont(size: 12)
                    .foregroundStyle(DSColors.secondaryText)
                    .textSelection(.enabled)
            }

            if !review.englishDraft.isEmpty || !review.queryEn.isEmpty {
                DisclosureGroup("English draft and question (technical details)", isExpanded: $showDraft) {
                    VStack(alignment: .leading, spacing: DSSpacing.sm) {
                        if !review.queryEn.isEmpty {
                            Text("Question as checked")
                                .scaledFont(size: 11, weight: .semibold)
                                .foregroundStyle(DSColors.secondaryText)
                            Text(review.queryEn)
                                .scaledFont(size: 12)
                                .foregroundStyle(DSColors.primaryText)
                                .textSelection(.enabled)
                        }
                        if !review.englishDraft.isEmpty {
                            Text(review.abstained ? "Draft (not shown as the answer)" : "English draft")
                                .scaledFont(size: 11, weight: .semibold)
                                .foregroundStyle(DSColors.secondaryText)
                            Text(review.englishDraft)
                                .scaledFont(size: 12)
                                .foregroundStyle(DSColors.primaryText)
                                .textSelection(.enabled)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, DSSpacing.sm)
                }
                .scaledFont(size: 12)
            }
        }
        .padding(DSSpacing.md)
        .background(
            RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                .fill(DSColors.surface)
        )
        .padding(.horizontal, DSSpacing.md)
    }
}

#Preview {
    ScrollView {
        GreekLegalReviewCard(review: LegalAnswerReview(
            englishDraft: "Under Article 66 of Law 4808/2021, dismissal must be in writing and severance paid [C1].",
            abstained: false, reason: nil, overallConfidence: 0.82,
            gates: [
                .init(gate: "Gate A: Retrieval Confidence", passed: true, confidence: 0.9, details: "Top score 0.91 ≥ 0.55"),
                .init(gate: "Gate F: Quote Faithfulness", passed: true, confidence: 1, details: "All legal identifiers found in the passages."),
                .init(gate: "Gate I: Statutory Isolation", passed: true, confidence: 1, details: "Passages match the statute the question names"),
            ],
            modelUsed: "Apple Intelligence (On-Device)",
            queryEn: "What are the conditions for dismissal under Article 66 [Άρθρο 66] of Law 4808/2021 [Ν. 4808/2021]?",
            assetIDs: ["instruct_3b"]
        ))
    }
}
