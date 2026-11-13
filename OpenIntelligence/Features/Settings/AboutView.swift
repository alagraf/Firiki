import SwiftUI

enum OpenIntelligenceLinks {
    /// This project's repository. Shared answers and exported conversations link here.
    static let projectURL = URL(string: "https://github.com/alagraf/Firiki")!
    /// The open-source app this project extends (MIT licence), credited in About.
    static let upstreamURL = URL(string: "https://github.com/Gunnarguy/OpenIntelligence")!
}

/// Presents product metadata and device-specific capability information.
struct AboutView: View {
    @EnvironmentObject private var settings: SettingsStore
    @Environment(\.openURL) private var openURL
    @State private var deviceCapabilities = DeviceCapabilities()

    /// Single source of truth for hardware identity. `deviceCapabilities` is still used
    /// for the OS version and the Apple Intelligence availability rows, both of which it
    /// gets from live system APIs rather than from its own chip table.
    private let deviceService = DeviceCapabilityService.shared

    /// Human-readable name for the active embedding provider
    private var embeddingDisplayName: String {
        switch settings.defaultEmbeddingProvider {
        case "nl_contextual_embedding":
            return "NLContextual (512D)"
        case "nl_embedding":
            return "NLEmbedding (512D)"
        case "coreml_sentence_embedding":
            return "MiniLM-L6-v2 (384D, Core ML)"
        // Showed the raw id on a Mac with macOS 27, where Core AI is the default (5.7).
        case "coreai_sentence_embedding":
            return "MiniLM-L6-v2 (384D, Core AI)"
        case "apple_fm_embed":
            return "Apple FM (1024D)"
        default:
            return settings.defaultEmbeddingProvider
        }
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DSColors.background, DSColors.surface.opacity(0.95)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: DSSpacing.lg) {
                    // App Info
                    SurfaceCard {
                        SectionHeader(icon: "info.circle", title: "About OpenIntelligence")
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            Text("OpenIntelligence")
                                .font(.title.bold())
                            Text("On-device assistant for Greek labour law · thesis proof of concept")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            Text(
                                "Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "2.0") (Build \(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "19"))"
                            )
                            .font(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, DSSpacing.xxs)
                    }

                    // Your Device
                    SurfaceCard {
                        SectionHeader(icon: "cpu", title: "Your Device")
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            // Read the chip from DeviceCapabilityService, not from
                            // `deviceCapabilities.deviceChip`.
                            //
                            // `RAGService.detectDeviceChip()` switches on the iPhone
                            // identifier family and stops at "iPhone17" (the iPhone 16
                            // line), so every iPhone 17 and newer fell to `default:
                            // return .older` — whose rawValue is the literal string
                            // "A12 or Older", with performanceRating "Limited". Those
                            // two strings were rendered right here, so the newest iPhone
                            // Apple sells reported itself as a 2018 chip, directly above
                            // an "Apple Intelligence ✓" row that reads the live
                            // availability API and was therefore correct.
                            //
                            // DeviceCapabilityService keys iPhones off the major version
                            // number and Macs off the CPU brand string, so it already
                            // resolves A19/A20 and M5 and does not need a new table for
                            // hardware that has not shipped yet.
                            LabeledContent("Device Chip", value: deviceService.chipName)
                            LabeledContent("iOS Version", value: deviceCapabilities.iOSVersion)
                                .monospacedDigit()
                            LabeledContent("Neural Engine", value: "\(deviceService.npuTops) TOPS")
                                .monospacedDigit()
                            LabeledContent("Memory", value: String(format: "%.0f GB", deviceService.memoryGB))
                                .monospacedDigit()
                            LabeledContent("AI Tier", value: deviceService.tier.displayName)
                        }
                        .font(.subheadline)
                    }

                    // AI Capabilities
                    SurfaceCard {
                        SectionHeader(icon: "brain.head.profile", title: "AI Capabilities")
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            capabilityRow(
                                title: "Apple Intelligence", condition: deviceCapabilities.supportsAppleIntelligence)
                            capabilityRow(
                                title: "Foundation Models", condition: deviceCapabilities.supportsFoundationModels)
                            capabilityRow(
                                title: "Private Cloud Compute",
                                condition: deviceCapabilities.supportsPrivateCloudCompute)
                            capabilityRow(title: "Writing Tools", condition: deviceCapabilities.supportsWritingTools)
                        }
                    }

                    // Features
                    SurfaceCard {
                        SectionHeader(icon: "star.circle.fill", title: "Features")
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            FeatureRow(
                                icon: "doc.text.fill", title: "Document Processing",
                                description: "Import PDFs, text files, and more")
                            FeatureRow(
                                icon: "cpu", title: "On-Device Processing",
                                description: "OCR, chunking, and embeddings run locally")
                            FeatureRow(
                                icon: "brain", title: "Multiple AI Pathways",
                                description: "Apple Foundation Models or extractive QA")
                            FeatureRow(
                                icon: "lock.shield.fill", title: "Privacy First",
                                description: "Your data stays on your device by default")
                        }
                    }

                    // Technology
                    SurfaceCard {
                        SectionHeader(icon: "gearshape.2.fill", title: "Technology")
                        VStack(alignment: .leading, spacing: DSSpacing.sm) {
                            LabeledContent("RAG Pipeline", value: "Hybrid (Vector + BM25 → RRF)")
                            LabeledContent("Embeddings", value: embeddingDisplayName)
                            LabeledContent("Vector Store", value: "Persistent JSON (exact k-NN)")
                            LabeledContent("Minimum OS", value: "iOS 26 · macOS 26")
                                .monospacedDigit()
                        }
                        .font(.subheadline)
                    }

                    SurfaceCard {
                        SectionHeader(icon: "book.closed.fill", title: "Project")
                        VStack(alignment: .leading, spacing: DSSpacing.md) {
                            Text("Developed by Alexandros Agrafiotis as a thesis proof of concept. Not legal advice.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            externalLinkRow(
                                title: "Source Code",
                                subtitle: "This project's repository",
                                icon: "chevron.left.forwardslash.chevron.right",
                                tint: .accentColor
                            ) {
                                openURL(OpenIntelligenceLinks.projectURL)
                            }
                            externalLinkRow(
                                title: "Built on OpenIntelligence",
                                subtitle: "The open-source app by Gunnar Hostetler that this project extends (MIT licence)",
                                icon: "heart.fill",
                                tint: .secondary
                            ) {
                                openURL(OpenIntelligenceLinks.upstreamURL)
                            }
                            // The newest crash report, when there is one (`CrashReports`).
                            if let crashReport = CrashReports.all().first {
                                ShareLink(item: crashReport) {
                                    linkRowLabel(
                                        title: "Share the Last Crash Report",
                                        subtitle: "The whole report as a file. It has none of your documents or chats",
                                        icon: "square.and.arrow.up",
                                        tint: .red)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding(DSSpacing.lg)
            }
        }
        .navigationTitle("About")
        #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
        #endif
        .onAppear {
            DispatchQueue.main.async {
                deviceCapabilities = RAGService.checkDeviceCapabilities()
            }
        }
    }

    private func capabilityRow(title: String, condition: Bool) -> some View {
        HStack {
            Text(title)
                .font(.subheadline)
            Spacer()
            Image(systemName: condition ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundStyle(condition ? .green : .secondary)
        }
    }

    private func externalLinkRow(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            linkRowLabel(title: title, subtitle: subtitle, icon: icon, tint: tint)
        }
        .buttonStyle(.plain)
    }

    /// The look of every row on this screen, for a button or a share link.
    private func linkRowLabel(title: String, subtitle: String, icon: String, tint: Color) -> some View {
        HStack(spacing: DSSpacing.md) {
            ZStack {
                RoundedRectangle(cornerRadius: DSCorners.card, style: .continuous)
                    .fill(tint.opacity(0.12))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .scaledFont(size: 15, weight: .semibold)
                    .foregroundStyle(tint)
            }

            VStack(alignment: .leading, spacing: DSSpacing.xxs) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(DSColors.primaryText)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Image(systemName: "arrow.up.forward")
                .font(.caption.weight(.bold))
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, DSSpacing.xxs)
        .frame(minHeight: DSSpacing.tapTarget)
    }
}

#Preview {
    AboutView()
        .environmentObject(SettingsStore(ragService: RAGService()))
}
