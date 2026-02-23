//
//  ContentView.swift
//  AwesomeApp
//
//  Created by test on 3.11.25.
//

import AVKit
import StoreKit
import SwiftUI
import UIKit

struct ContentView: View {
    @StateObject private var viewModel = AppViewModel()
    @FocusState private var isPromptFocused: Bool
    @State private var isVoicePickerPresented: Bool = false
    @State private var isLanguagePickerPresented: Bool = false
    @State private var isCharacterPickerPresented: Bool = false
    @State private var isProjectSettingsSheetPresented: Bool = false
    @State private var isDurationPickerPresented: Bool = false
    @State private var isTemplatePickerPresented: Bool = false
    @State private var pendingScriptModeTarget: Bool?
    @State private var isScriptModeAlertPresented = false
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var languageManager: LanguageManager

    var body: some View {
        NavigationStack {
            ZStack {
                backgroundGradient
                    .ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        promptSection
                        preferenceButtonsSection
                        actionSection
                    }
                    .padding(.vertical, 32)
                    .padding(.horizontal, 20)
                }

                if viewModel.isGenerationOverlayVisible {
                    GenerationOverlayView(viewModel: viewModel)
                        .transition(.opacity)
                }

                if viewModel.isGuestUpgradeBannerVisible {
                    VStack {
                        Spacer()
                        GuestUpgradeBannerView(
                            titleKey: LocalizedStringKey("guest_upgrade_banner_title"),
                            messageKey: LocalizedStringKey("guest_upgrade_banner_body"),
                            linkAction: {
                                viewModel.openGuestUpgradeSettings()
                            },
                            dismissAction: {
                                viewModel.dismissGuestUpgradeBanner()
                            }
                        )
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .navigationTitle(Text(LocalizedStringKey("app_title")))
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        viewModel.isProjectSheetPresented = true
                    } label: {
                        Image(systemName: "folder")
                            .imageScale(.large)
                    }
                    .accessibilityLabel(Text(LocalizedStringKey("accessibility_projects")))
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        viewModel.isSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape.fill")
                            .imageScale(.large)
                    }
                    .accessibilityLabel(Text(LocalizedStringKey("accessibility_settings")))
                }
            }
        }
        .sheet(isPresented: $viewModel.isProjectSheetPresented) {
            ProjectListView(viewModel: viewModel)
                .id(languageManager.selectedLanguage)
                .environment(\.locale, languageManager.locale)
        }
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            SettingsSheetView(viewModel: viewModel)
                .id(languageManager.selectedLanguage)
                .environment(\.locale, languageManager.locale)
        }
        .sheet(isPresented: $isVoicePickerPresented) {
            VoicePickerSheet(viewModel: viewModel)
                .id(languageManager.selectedLanguage)
                .environment(\.locale, languageManager.locale)
        }
        .sheet(isPresented: $isTemplatePickerPresented) {
            TemplatePickerSheet(viewModel: viewModel)
                .id(languageManager.selectedLanguage)
                .environment(\.locale, languageManager.locale)
        }
        .sheet(isPresented: $isCharacterPickerPresented) {
            CharacterPickerSheet(viewModel: viewModel)
                .id(languageManager.selectedLanguage)
                .environment(\.locale, languageManager.locale)
        }
        .sheet(isPresented: $isLanguagePickerPresented) {
            LanguagePickerSheet(viewModel: viewModel)
                .id(languageManager.selectedLanguage)
                .environment(\.locale, languageManager.locale)
        }
        .sheet(isPresented: $isProjectSettingsSheetPresented) {
            ProjectSettingsSheet(viewModel: viewModel)
                .id(languageManager.selectedLanguage)
                .environment(\.locale, languageManager.locale)
        }
        .sheet(isPresented: $isDurationPickerPresented) {
            DurationPickerSheet(viewModel: viewModel)
                .id(languageManager.selectedLanguage)
                .environment(\.locale, languageManager.locale)
        }
        .sheet(isPresented: $viewModel.isSignInSheetPresented) {
            SignInGateSheet(
                viewModel: viewModel,
                onClose: {
                    viewModel.dismissSignInSheet()
                }
            )
            .environment(\.locale, languageManager.locale)
        }
        .sheet(isPresented: $viewModel.isPaywallPresented) {
            PaywallView(
                products: viewModel.subscriptionProducts,
                isLoadingProducts: viewModel.isSubscriptionProductLoading,
                onAppearLoadProducts: {
                    viewModel.loadSubscriptionProductsIfNeeded()
                },
                onClose: {
                    viewModel.handlePaywallDismissed()
                },
                onSubscribe: { plan in
                    do {
                        try await viewModel.purchaseSubscription(plan: plan)
                        return .success
                    } catch let error as AppViewModel.SubscriptionFlowError {
                        switch error {
                        case .userCancelled:
                            return .cancelled
                        default:
                            return .failure(error.errorDescription ?? NSLocalizedString("settings_auth_error", comment: ""))
                        }
                    } catch {
                        return .failure(error.localizedDescription)
                    }
                },
                onRestore: {
                    await viewModel.restorePurchases()
                },
                isRestoringPurchases: viewModel.isRestoringPurchases
            )
            .environment(\.locale, languageManager.locale)
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
        .alert(
            Text(viewModel.projectCreationErrorMessage ?? NSLocalizedString("error_generic", comment: "")),
            isPresented: Binding(
                get: { viewModel.projectCreationErrorMessage != nil },
                set: { if !$0 { viewModel.projectCreationErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.projectCreationErrorMessage = nil
            }
        }
        .alert(
            scriptModeAlertTitleKey,
            isPresented: $isScriptModeAlertPresented,
            actions: {
                Button(LocalizedStringKey("script_mode_confirm_cancel"), role: .cancel) {
                    pendingScriptModeTarget = nil
                }
                Button(LocalizedStringKey("script_mode_confirm_continue"), role: .destructive) {
                    if let target = pendingScriptModeTarget {
                        viewModel.setDefaultUseScript(target)
                    }
                    pendingScriptModeTarget = nil
                }
            },
            message: {
                Text(scriptModeAlertMessageKey)
            }
        )
        .task {
            viewModel.refreshProjectSummaries(force: false)
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("prompt_title"))
                .font(.title3)
                .bold()

            ZStack(alignment: .topLeading) {
                TextEditor(text: $viewModel.promptText)
                    .focused($isPromptFocused)
                    .scrollContentBackground(.hidden)
                    .frame(minHeight: 160, idealHeight: 200)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: UIRadius.card, style: .continuous)
                            .fill(textEditorBackgroundColor)
                            .shadow(color: .black.opacity(colorScheme == .dark ? 0.2 : 0.05), radius: 12, x: 0, y: 6)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: UIRadius.card, style: .continuous)
                            .stroke(strokeColor, lineWidth: 1)
                    )
                    .disabled(viewModel.isDemoModeActive)
                    .opacity(viewModel.isDemoModeActive ? 0.75 : 1)

                if viewModel.promptText.isEmpty {
                    Text(LocalizedStringKey("prompt_placeholder"))
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .padding(20)
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        characterCounter
                    }
                }
                .padding(16)
            }

            HStack(spacing: 12) {
                if viewModel.shouldShowDemoModeButton {
                    Button {
                        if viewModel.isDemoModeActive {
                            viewModel.cancelDemoPrompt(locale: languageManager.locale)
                        } else {
                            viewModel.beginDemoPrompt(locale: languageManager.locale)
                            isPromptFocused = false
                        }
                    } label: {
                        Label {
                            Text(
                                viewModel.isDemoModeActive
                                ? LocalizedStringKey("demo_cancel")
                                : LocalizedStringKey("demo_fill")
                            )
                                .font(.subheadline.weight(.semibold))
                        } icon: {
                            Image(systemName: viewModel.isDemoModeActive ? "xmark.circle" : "sparkles")
                        }
                    }
                    .buttonStyle(TintedSecondaryButtonStyle(isPressedTint: viewModel.isDemoModeActive))
                }

                Spacer()
            }
        }
    }

    private var characterCounter: some View {
        let current = viewModel.promptCharacterCount
        let limit = viewModel.promptLimit
        let nearLimit = Double(current) / Double(limit) > 0.9

        return Text("\(current)/\(limit)")
            .font(.caption2.monospacedDigit())
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .foregroundStyle(nearLimit ? Color.red : Color.secondary)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(counterBackgroundColor.opacity(0.9))
            )
    }

    private var counterBackgroundColor: Color {
        colorScheme == .dark ? Color.black : Color.white
    }

    private var scriptModeAlertTitleKey: LocalizedStringKey {
        guard let target = pendingScriptModeTarget else {
            return LocalizedStringKey("")
        }
        return LocalizedStringKey(target ? "script_mode_to_script_title" : "script_mode_to_idea_title")
    }

    private var scriptModeAlertMessageKey: LocalizedStringKey {
        guard let target = pendingScriptModeTarget else {
            return LocalizedStringKey("")
        }
        return LocalizedStringKey(target ? "script_mode_to_script_message" : "script_mode_to_idea_message")
    }

    private var actionSection: some View {
        VStack(spacing: 0) {
            Button {
                isPromptFocused = false
                viewModel.handleCreateButtonTap()
            } label: {
                HStack(spacing: 12) {
                    if viewModel.isProjectSubmissionInFlight {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    } else {
                        Image(systemName: "sparkles")
                    }
                    Text(
                        viewModel.isProjectSubmissionInFlight
                        ? LocalizedStringKey("creating_project")
                        : LocalizedStringKey("create_button_title")
                    )
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(PrimaryFilledButtonStyle())
            .disabled(!viewModel.canShowCreateButton)
            .accessibilityLabel(Text(LocalizedStringKey("create_button_accessibility")))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
    }

    private var preferenceButtonsSection: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: 16) {
                settingItem(
                    button: projectSettingsButton,
                    label: LocalizedStringKey("quick_settings_chip_settings")
                )
                settingItem(
                    button: templateButton,
                    label: LocalizedStringKey("quick_settings_chip_template")
                )
                settingItem(
                    button: durationButton,
                    label: LocalizedStringKey("quick_settings_chip_length")
                )
                settingItem(
                    button: languageButton,
                    label: LocalizedStringKey("quick_settings_chip_lang")
                )
                settingItem(
                    button: voiceButton,
                    label: LocalizedStringKey("quick_settings_chip_voice")
                )
                settingItem(
                    button: characterButton,
                    label: LocalizedStringKey("quick_settings_chip_char")
                )
                settingItem(
                    button: scriptModeButton,
                    label: LocalizedStringKey("quick_settings_chip_mode")
                )
            }
            .padding(.vertical, 4)
            .padding(.leading, 1)
            .padding(.trailing, 64)
        }
        .overlay(alignment: .trailing) {
            if colorScheme == .dark {
                // Для темной темы используем градиент к тому же цвету фона
                LinearGradient(
                    stops: [
                        .init(color: Color.clear, location: 0.0),
                        .init(color: Color(red: 0.06, green: 0.08, blue: 0.12).opacity(0.4), location: 0.3),
                        .init(color: Color(red: 0.06, green: 0.08, blue: 0.12).opacity(0.7), location: 0.7),
                        .init(color: Color(red: 0.06, green: 0.08, blue: 0.12), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 54)
                .allowsHitTesting(false)
            } else {
                // Для светлой темы оставляем оригинальный градиент
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0.0),
                        .init(color: Color(.systemBackground).opacity(0.7), location: 0.2),
                        .init(color: Color(.systemBackground).opacity(0.97), location: 0.55),
                        .init(color: Color(.systemBackground), location: 1.0)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .frame(width: 54)
                .allowsHitTesting(false)
            }
        }
    }

    private func settingItem(button: some View, label: LocalizedStringKey) -> some View {
        VStack(spacing: 8) {
            button
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
        }
    }

    private var scriptModeButton: some View {
        let isScript = viewModel.projectSettings.defaultUseScript
        return PreferenceButton(
            iconName: isScript ? "doc.text" : "lightbulb",
            accessibilityTitle: LocalizedStringKey("script_mode_button_title"),
            accessibilityValue: isScript
                ? NSLocalizedString("script_mode_script", comment: "")
                : NSLocalizedString("script_mode_idea", comment: ""),
            showIndicator: isScript,
            isDisabled: false
        ) {
            pendingScriptModeTarget = !isScript
            isScriptModeAlertPresented = true
        }
        .accessibilityHint(Text("Toggles between idea expansion and exact script"))
    }

    private var projectSettingsButton: some View {
        PreferenceButton(
            iconName: "slider.horizontal.3",
            accessibilityTitle: LocalizedStringKey("project_settings_button_title"),
            accessibilityValue: NSLocalizedString("project_settings_button_title", comment: ""),
            showIndicator: viewModel.projectSettingsIndicatorActive
        ) {
            isPromptFocused = false
            isProjectSettingsSheetPresented = true
        }
        .accessibilityHint(Text("Opens project settings"))
    }

    private var durationButton: some View {
        PreferenceButton(
            iconName: "clock",
            accessibilityTitle: LocalizedStringKey("duration_button_title"),
            accessibilityValue: viewModel.projectSettings.defaultUseScript ? NSLocalizedString("duration_disabled_label", comment: "") : viewModel.durationAccessibilityValue,
            showIndicator: !viewModel.isUsingDefaultDuration,
            isDisabled: viewModel.projectSettings.defaultUseScript
        ) {
            isPromptFocused = false
            isDurationPickerPresented = true
        }
        .accessibilityHint(Text("Opens the duration selection sheet"))
    }

    private var characterButton: some View {
        PreferenceButton(
            iconName: "person.crop.square",
            accessibilityTitle: LocalizedStringKey("character_button_title"),
            accessibilityValue: viewModel.characterAccessibilityValue,
            showIndicator: viewModel.characterButtonIndicatorActive
        ) {
            isPromptFocused = false
            isCharacterPickerPresented = true
        }
        .accessibilityHint(Text("Opens the character selection sheet"))
    }

    private var voiceButton: some View {
        PreferenceButton(
            iconName: "person.wave.2.fill",
            accessibilityTitle: LocalizedStringKey("voice_button_title"),
            accessibilityValue: viewModel.currentVoiceTitle,
            showIndicator: !viewModel.isUsingDefaultVoice
        ) {
            isPromptFocused = false
            isVoicePickerPresented = true
        }
        .accessibilityHint(Text("Opens the voice selection sheet"))
    }

    private var templateButton: some View {
        PreferenceButton(
            iconName: "square.grid.3x2",
            accessibilityTitle: LocalizedStringKey("template_button_title"),
            accessibilityValue: viewModel.templateAccessibilityValue,
            showIndicator: viewModel.templateButtonIndicatorActive
        ) {
            isPromptFocused = false
            isTemplatePickerPresented = true
        }
        .accessibilityHint(Text("Opens the template selection sheet"))
    }

    private var languageButton: some View {
        PreferenceButton(
            iconName: "globe",
            accessibilityTitle: LocalizedStringKey("language_button_title"),
            accessibilityValue: viewModel.languageSummaryText,
            showIndicator: !viewModel.isUsingDefaultLanguages
        ) {
            isPromptFocused = false
            isLanguagePickerPresented = true
        }
        .accessibilityHint(Text("Opens the language selection sheet"))
    }

    @ViewBuilder
    private var backgroundGradient: some View {
        if colorScheme == .dark {
            Color(red: 0.06, green: 0.08, blue: 0.12)
        } else {
            Color(.systemBackground)
        }
    }

    private var strokeColor: Color {
        colorScheme == .dark ? UIStrokeColor.dark : UIStrokeColor.light
    }

    private var textEditorBackgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.10, green: 0.12, blue: 0.16) : Color(.systemBackground)
    }
}

private struct VoicePickerSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VoicePickerView(viewModel: viewModel)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
            .navigationTitle(LocalizedStringKey("voice_picker_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.fraction(1.0)])
        .presentationDragIndicator(.visible)
    }
}

private struct TemplatePickerSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TemplatePickerView(viewModel: viewModel)
                .navigationTitle(LocalizedStringKey("template_picker_title"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.fraction(1.0)])
        .presentationDragIndicator(.visible)
    }
}

private struct CharacterPickerSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            CharacterPickerView(viewModel: viewModel)
                .navigationTitle(LocalizedStringKey("character_button_title"))
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.fraction(1.0)])
        .presentationDragIndicator(.visible)
    }
}

private struct LanguagePickerSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                LanguagePickerView(viewModel: viewModel)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
            .navigationTitle(LocalizedStringKey("language_picker_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.fraction(1.0)])
        .presentationDragIndicator(.visible)
    }
}

private struct ProjectSettingsSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var scriptGuidance: String = ""
    @State private var audioGuidance: String = ""
    private let scriptLimit = 4_000
    private let audioLimit = 500

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    Text(LocalizedStringKey("project_settings_description"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if viewModel.isProjectSettingsLoading {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }
                    settingsSection
                    guidanceSection
                }
                .padding(20)
            }
            .navigationTitle(LocalizedStringKey("project_settings_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        commitGuidanceChanges()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.fraction(1.0)])
        .presentationDragIndicator(.visible)
        .onAppear {
            scriptGuidance = viewModel.projectSettings.scriptCreationGuidance
            audioGuidance = viewModel.projectSettings.audioStyleGuidance
            viewModel.refreshProjectSettings(force: true)
        }
        .onDisappear {
            commitGuidanceChanges()
        }
    }

    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey("project_settings_basics_header"))
                .font(.headline)
            SettingToggleRow(
                titleKey: "project_settings_music",
                systemImage: "music.note",
                value: Binding(get: { viewModel.projectSettings.includeDefaultMusic }, set: { viewModel.setIncludeDefaultMusic($0) })
            )
            SettingToggleRow(
                titleKey: "project_settings_overlay",
                systemImage: "rectangle.stack.badge.plus",
                value: Binding(get: { viewModel.projectSettings.addOverlay }, set: { viewModel.setAddOverlay($0) })
            )
            SettingToggleRow(
                titleKey: "project_settings_watermark",
                systemImage: "drop",
                value: Binding(get: { viewModel.projectSettings.watermarkEnabled }, set: { viewModel.setWatermarkEnabled($0) })
            )
            SettingToggleRow(
                titleKey: "project_settings_captions",
                systemImage: "text.bubble",
                value: Binding(get: { viewModel.projectSettings.captionsEnabled }, set: { viewModel.setCaptionsEnabled($0) })
            )
            SettingToggleRow(
                titleKey: "project_settings_cta",
                systemImage: "megaphone",
                value: Binding(get: { viewModel.projectSettings.includeCallToAction }, set: { viewModel.setIncludeCallToAction($0) })
            )
        }
    }

    private var guidanceSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(LocalizedStringKey("project_settings_guidance_header"))
                .font(.headline)

            GuidanceEditor(
                titleKey: "project_settings_script_guidance_title",
                subtitleKey: "project_settings_script_guidance_subtitle",
                placeholderKey: "project_settings_script_guidance_placeholder",
                value: $scriptGuidance,
                enabled: Binding(get: { viewModel.projectSettings.scriptCreationGuidanceEnabled }, set: { viewModel.setScriptCreationGuidanceEnabled($0) }),
                limit: scriptLimit,
                commitAction: { viewModel.setScriptCreationGuidance($0) }
            )

            GuidanceEditor(
                titleKey: "project_settings_audio_guidance_title",
                subtitleKey: "project_settings_audio_guidance_subtitle",
                placeholderKey: "project_settings_audio_guidance_placeholder",
                value: $audioGuidance,
                enabled: Binding(get: { viewModel.projectSettings.audioStyleGuidanceEnabled }, set: { viewModel.setAudioStyleGuidanceEnabled($0) }),
                limit: audioLimit,
                commitAction: { viewModel.setAudioStyleGuidance($0) }
            )
        }
    }

    private func commitGuidanceChanges() {
        let script = String(scriptGuidance.prefix(scriptLimit))
        let audio = String(audioGuidance.prefix(audioLimit))
        if script != viewModel.projectSettings.scriptCreationGuidance {
            viewModel.setScriptCreationGuidance(script)
        }
        if audio != viewModel.projectSettings.audioStyleGuidance {
            viewModel.setAudioStyleGuidance(audio)
        }
    }
}

private struct SettingToggleRow: View {
    let titleKey: LocalizedStringKey
    let systemImage: String
    let value: Binding<Bool>
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Toggle(isOn: value) {
            HStack(spacing: 12) {
                SettingToggleIcon(systemImage: systemImage)
                Text(titleKey)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(SwitchToggleStyle(tint: Color.accentColor))
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .animation(.easeInOut(duration: 0.15), value: value.wrappedValue)
    }

    private var borderColor: Color {
        colorScheme == .dark ? Color.white.opacity(0.08) : Color.black.opacity(0.08)
    }
}

private struct SettingToggleIcon: View {
    let systemImage: String
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 16, weight: .semibold))
            .frame(width: 36, height: 36)
            .foregroundStyle(Color.accentColor)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconBackground)
            )
    }

    private var iconBackground: Color {
        colorScheme == .dark
            ? Color.accentColor.opacity(0.25)
            : Color.accentColor.opacity(0.12)
    }
}

private struct SettingsSheetView: View {
    @ObservedObject var viewModel: AppViewModel
    @EnvironmentObject private var languageManager: LanguageManager
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var subscriptionTapCount = 0
    @State private var restoreAlertMessage: String?
    @State private var isSignOutConfirmationPresented = false
    @State private var isEmailLoginSheetPresented = false
    @State private var isDeleteAccountConfirmationPresented = false
    @State private var isDeleteAccountBillingAlertPresented = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Form {
                    accountSection
                    languageSection
                    websiteSection
                    if viewModel.isAuthenticated {
                        deleteAccountSection
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text(LocalizedStringKey("settings_title")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                    }
                    .accessibilityLabel(Text(LocalizedStringKey("settings_close")))
                }
            }
            .alert(
                Text(verbatim: viewModel.authErrorMessage ?? NSLocalizedString("settings_auth_error", comment: "")),
                isPresented: Binding(
                    get: { viewModel.authErrorMessage != nil },
                    set: { if !$0 { viewModel.authErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.authErrorMessage = nil
                }
            }
            .alert(
                Text(verbatim: restoreAlertMessage ?? ""),
                isPresented: Binding(
                    get: { restoreAlertMessage != nil },
                    set: { if !$0 { restoreAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    restoreAlertMessage = nil
                }
            }
            .alert(LocalizedStringKey("settings_sign_out_confirm_title"), isPresented: $isSignOutConfirmationPresented) {
                Button(LocalizedStringKey("settings_sign_out_confirm_action"), role: .destructive) {
                    viewModel.signOut()
                }
                Button(LocalizedStringKey("settings_sign_out_cancel"), role: .cancel) {}
            } message: {
                Text(LocalizedStringKey("settings_sign_out_confirm_message"))
            }
            .alert(
                Text(verbatim: viewModel.accountDeletionErrorMessage ?? ""),
                isPresented: Binding(
                    get: { viewModel.accountDeletionErrorMessage != nil },
                    set: { if !$0 { viewModel.accountDeletionErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.accountDeletionErrorMessage = nil
                }
            }
            .alert(
                Text(verbatim: viewModel.accountDeletionSuccessMessage ?? ""),
                isPresented: Binding(
                    get: { viewModel.accountDeletionSuccessMessage != nil },
                    set: { if !$0 { viewModel.accountDeletionSuccessMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.accountDeletionSuccessMessage = nil
                }
            }
            .alert(LocalizedStringKey("settings_delete_account_billing_title"), isPresented: $isDeleteAccountBillingAlertPresented) {
                Button(LocalizedStringKey("settings_delete_account_billing_open_link")) {
                    openAppleSubscriptions()
                }
                Button(LocalizedStringKey("settings_delete_account_billing_continue"), role: .destructive) {
                    isDeleteAccountConfirmationPresented = true
                }
                Button(LocalizedStringKey("settings_delete_account_cancel"), role: .cancel) {}
            } message: {
                Text(LocalizedStringKey("settings_delete_account_billing_message"))
            }
            .alert(LocalizedStringKey("settings_delete_account_confirm_title"), isPresented: $isDeleteAccountConfirmationPresented) {
                Button(LocalizedStringKey("settings_delete_account_confirm_action"), role: .destructive) {
                    viewModel.deleteAccount()
                }
                Button(LocalizedStringKey("settings_delete_account_cancel"), role: .cancel) {}
            } message: {
                Text(LocalizedStringKey("settings_delete_account_confirm_message"))
            }
            .onChange(of: viewModel.isSubscribed) { _ in
                subscriptionTapCount = 0
            }
            .sheet(isPresented: $isEmailLoginSheetPresented) {
                EmailSignInSheet(viewModel: viewModel)
                    .environment(\.locale, languageManager.locale)
            }
        }
    }

    private var languageSection: some View {
        Section(header: Text(LocalizedStringKey("settings_language_section"))) {
            Picker("", selection: $languageManager.selectedLanguage) {
                ForEach(AppLanguage.allCases) { language in
                    Text(language.localizedTitle)
                        .tag(language)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
    }

    private var accountSection: some View {
        Section(header: Text(LocalizedStringKey("settings_account_section"))) {
            let isGuestSession = viewModel.connectedAccountProvider == .guest

            if viewModel.isAuthenticated {
                accountStatusRow

                HStack {
                    Text(LocalizedStringKey("settings_account_status_label"))
                    Spacer()
                    Text(viewModel.planStatusKey)
                        .foregroundStyle(viewModel.isSubscribed ? Color.green : Color.secondary)
                        .fontWeight(.semibold)
                }

                tokenBalanceRow

                if isGuestSession {
                    guestLinkButtons
                }
            } else {
                guestLinkButtons
            }

            if viewModel.isAuthenticated {
                if viewModel.isSubscribed {
#if targetEnvironment(simulator)
                    Button {
                        subscriptionTapCount += 1
                        if subscriptionTapCount >= 5 {
                            subscriptionTapCount = 0
                            viewModel.resetSubscription()
                        }
                    } label: {
                        Label {
                            Text(LocalizedStringKey("settings_subscription_active"))
                        } icon: {
                            Image(systemName: "creditcard.fill")
                        }
                        .foregroundStyle(.blue)
                    }
                    .buttonStyle(.plain)
#else
                    Label {
                        Text(LocalizedStringKey("settings_subscription_active"))
                    } icon: {
                        Image(systemName: "creditcard.fill")
                    }
                    .foregroundStyle(.blue)
#endif
                } else {
                    Button {
                        dismiss()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                            viewModel.presentPaywall(force: true, context: .manual)
                        }
                    } label: {
                        Label {
                            Text(LocalizedStringKey("settings_subscribe"))
                        } icon: {
                            Image(systemName: "sparkles.rectangle.stack.fill")
                        }
                    }
                    .disabled(viewModel.isPaywallPresented)
                }

                Button {
                    runSettingsRestoreFlow()
                } label: {
                    Label {
                        Text(
                            LocalizedStringKey(
                                viewModel.isRestoringPurchases
                                ? "settings_restoring_purchases"
                                : "settings_restore_purchases"
                            )
                        )
                        .font(.body)
                        .foregroundStyle(Color.accentColor)
                    } icon: {
                        if viewModel.isRestoringPurchases {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(Color.accentColor)
                                .frame(width: 18, height: 18)
                        } else {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(Color.accentColor)
                                .symbolRenderingMode(.hierarchical)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(viewModel.isRestoringPurchases)
            }

            if viewModel.connectedAccountEmail != nil {
                signOutButton
            }
        }
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            isSignOutConfirmationPresented = true
        } label: {
            if viewModel.isSigningOut {
                Label {
                    Text(LocalizedStringKey("settings_signing_out"))
                } icon: {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 18, height: 18)
                }
            } else {
                Label {
                    Text(LocalizedStringKey("settings_sign_out"))
                } icon: {
                    Image(systemName: "rectangle.portrait.and.arrow.forward")
                }
            }
        }
        .disabled(viewModel.isSigningOut)
    }

    private var websiteSection: some View {
        Section(header: Text(LocalizedStringKey("settings_website_section"))) {
            Link(destination: URL(string: "https://www.awesomeapp.com")!) {
                Label {
                    Text(LocalizedStringKey("settings_website_link"))
                } icon: {
                    Image(systemName: "safari.fill")
                }
            }
        }
    }

    private var deleteAccountSection: some View {
        Section {
            Button(role: .destructive) {
                if viewModel.isSubscribed {
                    isDeleteAccountBillingAlertPresented = true
                } else {
                    isDeleteAccountConfirmationPresented = true
                }
            } label: {
                if viewModel.isDeletingAccount {
                    Label {
                        Text(LocalizedStringKey("settings_deleting_account"))
                    } icon: {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .frame(width: 18, height: 18)
                    }
                } else {
                    Label {
                        Text(LocalizedStringKey("settings_delete_account"))
                    } icon: {
                        Image(systemName: "trash.fill")
                    }
                }
            }
            .disabled(viewModel.isDeletingAccount)
        } footer: {
            Text(LocalizedStringKey("settings_delete_account_footer"))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func openAppleSubscriptions() {
        if #available(iOS 15.0, *) {
            Task { @MainActor in
                guard let scene = activeWindowScene() else {
                    openSubscriptionsURLFallback()
                    return
                }
                do {
                    try await AppStore.showManageSubscriptions(in: scene)
                } catch {
                    openSubscriptionsURLFallback()
                }
            }
        } else {
            openSubscriptionsURLFallback()
        }
    }

    private func activeWindowScene() -> UIWindowScene? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
            ?? UIApplication.shared.connectedScenes.first as? UIWindowScene
    }

    private func openSubscriptionsURLFallback() {
        guard let url = URL(string: "https://apps.apple.com/account/subscriptions") else { return }
        openURL(url)
    }

    private func runSettingsRestoreFlow() {
        guard viewModel.isAuthenticated, !viewModel.isRestoringPurchases else { return }
        Task {
            let outcome = await viewModel.restorePurchases()
            let message = outcome.localizedDescription
            restoreAlertMessage = message.isEmpty ? nil : message
        }
    }

    @ViewBuilder
    private var guestLinkButtons: some View {
        Button {
            viewModel.linkGoogleAccount()
        } label: {
            if viewModel.isGoogleLinking {
                Label {
                    Text(LocalizedStringKey("settings_connecting_google"))
                } icon: {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 18, height: 18)
                }
            } else {
                Label {
                    Text(LocalizedStringKey("settings_connect_google"))
                } icon: {
                    Image("GoogleIcon")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isGoogleLinking || viewModel.isAppleLinking || viewModel.isReviewLinking)

        Button {
            viewModel.linkAppleAccount()
        } label: {
            if viewModel.isAppleLinking {
                Label {
                    Text(LocalizedStringKey("settings_connecting_apple"))
                } icon: {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 18, height: 18)
                }
            } else {
                Label {
                    Text(LocalizedStringKey("settings_connect_apple"))
                } icon: {
                    AppleBadgeIcon()
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isGoogleLinking || viewModel.isAppleLinking || viewModel.isReviewLinking)

        Button {
            isEmailLoginSheetPresented = true
        } label: {
            if viewModel.isReviewLinking {
                Label {
                    Text(LocalizedStringKey("settings_connecting_email"))
                } icon: {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .frame(width: 18, height: 18)
                }
            } else {
                Label {
                    Text(LocalizedStringKey("settings_connect_email"))
                } icon: {
                    Image(systemName: "envelope.fill")
                        .symbolRenderingMode(.hierarchical)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isGoogleLinking || viewModel.isAppleLinking || viewModel.isReviewLinking)
    }

    private var tokenBalanceRow: some View {
        Button {
            guard !viewModel.isLoadingTokenBalance else { return }
            viewModel.reloadTokenBalance()
        } label: {
            HStack {
                Text(LocalizedStringKey("settings_token_balance"))
                    .foregroundStyle(.primary)
                Spacer()
                if viewModel.isLoadingTokenBalance {
                    ProgressView()
                        .progressViewStyle(.circular)
                } else if let balance = viewModel.tokenBalance {
                    Text(tokenBalanceString(for: balance))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.primary)
                } else {
                    Text(LocalizedStringKey("settings_refresh_balance"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text(LocalizedStringKey("settings_refresh_balance")))
    }

    private var accountStatusRow: some View {
        let provider = viewModel.connectedAccountEmail == nil ? AuthProvider.guest : viewModel.connectedAccountProvider

        return HStack(spacing: 12) {
            AccountProviderIcon(provider: provider)

            VStack(alignment: .leading, spacing: 4) {
                Text(providerLabel(for: provider))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let email = viewModel.connectedAccountEmail {
                    Text(verbatim: email)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text(LocalizedStringKey("settings_email_not_linked"))
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if viewModel.connectedAccountEmail != nil {
                Image(systemName: "checkmark.seal.fill")
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(.white, .blue)
            }
        }
        .padding(.vertical, 6)
    }

    private func providerLabel(for provider: AuthProvider) -> LocalizedStringKey {
        switch provider {
        case .google:
            return LocalizedStringKey("settings_google_account_label")
        case .apple:
            return LocalizedStringKey("settings_apple_account_label")
        case .review:
            return LocalizedStringKey("settings_email_account_label")
        case .guest:
            return LocalizedStringKey("settings_guest_account_label")
        }
    }
}

private struct EmailSignInSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var reviewEmail: String = AppConfiguration.reviewLoginEmail
    @State private var reviewPassword: String = ""

    var body: some View {
        NavigationStack {
            ScrollView {
                EmailSignInCard(
                    viewModel: viewModel,
                    email: $reviewEmail,
                    password: $reviewPassword,
                    autoFocusEmail: true
                )
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text(LocalizedStringKey("signin_email_title")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                    }
                    .accessibilityLabel(Text(LocalizedStringKey("settings_close")))
                }
            }
        }
        .presentationDetents([.large])
        .alert(
            Text(verbatim: viewModel.authErrorMessage ?? NSLocalizedString("settings_auth_error", comment: "")),
            isPresented: Binding(
                get: { viewModel.authErrorMessage != nil },
                set: { if (!$0) { viewModel.authErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.authErrorMessage = nil
            }
        }
        .onChange(of: viewModel.isAuthenticated) { isAuthenticated in
            if isAuthenticated {
                reviewPassword = ""
                dismiss()
            }
        }
    }
}

private struct GuidanceEditor: View {
    let titleKey: LocalizedStringKey
    let subtitleKey: LocalizedStringKey
    let placeholderKey: LocalizedStringKey
    @Binding var value: String
    @Binding var enabled: Bool
    let limit: Int
    let commitAction: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(titleKey)
                        .font(.subheadline.weight(.semibold))
                    Text(subtitleKey)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Toggle("", isOn: $enabled)
                    .labelsHidden()
            }

            GuidanceTextEditor(text: $value, placeholderKey: placeholderKey)
                .frame(minHeight: 120)
                .disabled(!enabled)
                .opacity(enabled ? 1 : 0.5)
                .onChange(of: value) { newValue in
                    if newValue.count > limit {
                        value = String(newValue.prefix(limit))
                    }
                }

            HStack {
                Spacer()
                Text("\(value.count)/\(limit)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onChange(of: enabled) { _ in
            if !enabled {
                commitAction(value)
            }
        }
        .onChange(of: value) { newValue in
            if newValue.count > limit {
                value = String(newValue.prefix(limit))
            }
        }
    }
}

private struct GuidanceTextEditor: View {
    @Binding var text: String
    let placeholderKey: LocalizedStringKey

    var body: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $text)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: UIRadius.input, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            if text.isEmpty {
                Text(placeholderKey)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: UIRadius.input, style: .continuous)
                .stroke(Color.primary.opacity(0.1), lineWidth: 1)
        )
    }
}

private struct DurationPickerSheet: View {
    @ObservedObject var viewModel: AppViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                DurationPickerView(viewModel: viewModel)
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 24)
            }
            .navigationTitle(LocalizedStringKey("duration_picker_title"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.fraction(1.0)])
        .presentationDragIndicator(.visible)
    }
}

private struct PreferenceButton: View {
    let iconName: String
    let accessibilityTitle: LocalizedStringKey
    let accessibilityValue: String
    let showIndicator: Bool
    let isDisabled: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    init(iconName: String, accessibilityTitle: LocalizedStringKey, accessibilityValue: String, showIndicator: Bool, isDisabled: Bool = false, action: @escaping () -> Void) {
        self.iconName = iconName
        self.accessibilityTitle = accessibilityTitle
        self.accessibilityValue = accessibilityValue
        self.showIndicator = showIndicator
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                RoundedRectangle(cornerRadius: UIRadius.control, style: .continuous)
                    .fill(backgroundColor)
                    .overlay(
                        RoundedRectangle(cornerRadius: UIRadius.control, style: .continuous)
                            .stroke(borderColor, lineWidth: 1)
                    )
                    .frame(width: 56, height: 56)
                Image(systemName: iconName)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(iconColor)
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                if showIndicator {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 8, height: 8)
                        .padding(.trailing, 12)
                        .padding(.top, 6)
                        .accessibilityLabel(Text("Custom selection active"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.45 : 1)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(Text(accessibilityValue))
    }

    private var backgroundColor: Color {
        colorScheme == .dark ? Color(red: 0.08, green: 0.10, blue: 0.14) : Color.white
    }

    private var borderColor: Color {
        colorScheme == .dark ? UIStrokeColor.dark : UIStrokeColor.light
    }

    private var iconColor: Color {
        colorScheme == .dark ? Color.white : Color.black
    }
}

// MARK: - Generation Overlay

private struct GenerationOverlayView: View {
    @ObservedObject var viewModel: AppViewModel
    @State private var isStageListPresented = false

    private var currentStage: AppViewModel.ProcessingStage {
        guard !viewModel.stages.isEmpty else {
            return AppViewModel.ProcessingStage(
                iconName: "sparkles",
                titleKey: "processing_title",
                iconTint: Color.yellow,
                backgroundTint: Color.yellow.opacity(0.2)
            )
        }
        let index = min(max(viewModel.currentStageIndex, 0), viewModel.stages.count - 1)
        return viewModel.stages[index]
    }

    private var isProcessing: Bool {
        viewModel.phase == .processing
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.45)
                .ignoresSafeArea()

            VStack(spacing: 20) {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: currentStage.iconName)
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(stageIconColor)
                        .frame(width: 44, height: 44)
                        .background(
                            Circle()
                                .fill(stageBackgroundColor)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(isProcessing ? LocalizedStringKey("processing_title") : LocalizedStringKey("result_ready_title"))
                            .font(.headline)
                        Text(LocalizedStringKey(currentStage.titleKey))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        isStageListPresented.toggle()
                    } label: {
                        Image(systemName: isStageListPresented ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(Color.primary.opacity(0.35))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text(isStageListPresented ? LocalizedStringKey("status_hide_all") : LocalizedStringKey("status_show_all")))

                    Button {
                        viewModel.dismissGenerationOverlay()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .buttonStyle(.plain)
                    .tint(.secondary)
                    .accessibilityLabel(Text(LocalizedStringKey("result_close")))
                }

                if isProcessing {
                    progressBar
                }

                if isProcessing {
                    processingBody
                } else {
                    resultBody
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.regularMaterial)
            )
            .padding(.horizontal, 20)
        }
        .animation(.easeInOut, value: viewModel.currentStageIndex)
        .onChange(of: viewModel.phase) { _ in
            isStageListPresented = false
        }
        .sheet(isPresented: $isStageListPresented) {
            StageListSheet(stages: viewModel.stages, currentStageIndex: viewModel.currentStageIndex, phase: viewModel.phase)
        }
    }

    private var progressBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.primary.opacity(0.1))
                        .frame(height: 6)

                    Capsule()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.49, green: 0.39, blue: 0.92),
                                    Color(red: 0.34, green: 0.23, blue: 0.82)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: max(0, geometry.size.width * progressValue), height: 6)
                }
            }
            .frame(height: 6)

            HStack {
                Text(LocalizedStringKey("status_progress_label"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(displayedStep)/\(viewModel.stages.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                Text("\(displayedStep) / \(viewModel.stages.count)")
            )
        }
    }

    private var processingBody: some View {
        VStack(spacing: 16) {
            Text(LocalizedStringKey("processing_subtitle"))
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var resultBody: some View {
        if let player = viewModel.player {
            VStack(alignment: .leading, spacing: 16) {
                Text(LocalizedStringKey("result_ready_subtitle"))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack {
                    Spacer(minLength: 0)
                    VideoPlayer(player: player)
                        .aspectRatio(9/16, contentMode: .fit)
                        .frame(maxWidth: 320)
                        .clipShape(RoundedRectangle(cornerRadius: UIRadius.card, style: .continuous))
                    Spacer(minLength: 0)
                }

                DownloadSectionView(
                    downloadPhase: viewModel.downloadPhase,
                    downloadProgress: viewModel.downloadProgress,
                    onDownload: {
                        Task {
                            await viewModel.downloadResultVideo()
                        }
                    }
                )
            }
        }
    }

    private func color(for index: Int) -> Color {
        if viewModel.phase == .result {
            return .green
        }
        if index < viewModel.currentStageIndex {
            return .green
        }
        if index == viewModel.currentStageIndex {
            return .yellow
        }
        return .secondary
    }

    private var stageIconColor: Color {
        if isProcessing {
            return currentStage.iconTint
        }
        return Color.green
    }

    private var stageBackgroundColor: Color {
        if isProcessing {
            return currentStage.backgroundTint
        }
        return Color.green.opacity(0.18)
    }

    private var displayedStep: Int {
        if viewModel.phase == .result {
            return viewModel.stages.count
        }
        return min(viewModel.currentStageIndex + 1, viewModel.stages.count)
    }

    private var progressValue: Double {
        guard !viewModel.stages.isEmpty else { return 0 }
        if viewModel.phase == .result {
            return 1
        }
        let clampedIndex = max(0, min(viewModel.currentStageIndex, viewModel.stages.count - 1))
        return Double(clampedIndex) / Double(viewModel.stages.count)
    }

}

private struct StageListSheet: View {
    let stages: [AppViewModel.ProcessingStage]
    let currentStageIndex: Int
    let phase: AppViewModel.ViewPhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                List {
                    ForEach(Array(stages.enumerated()), id: \.offset) { index, stage in
                        HStack(spacing: 12) {
                            Image(systemName: stage.iconName)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(iconColor(for: index, stage: stage))
                                .frame(width: 32, height: 32)
                                .background(
                                    Circle()
                                        .fill(iconBackgroundColor(for: index, stage: stage))
                                )

                            Text(LocalizedStringKey(stage.titleKey))
                                .font(.body)
                                .foregroundStyle(textColor(for: index))

                            Spacer()

                            statusIndicator(for: index, stage: stage)
                        }
                    }
                }
                .listStyle(.insetGrouped)

                VStack(alignment: .leading, spacing: 6) {
                    Text(LocalizedStringKey("status_rendering_time_single"))
                    Text(LocalizedStringKey("status_rendering_time_multiple"))
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .navigationTitle(Text(LocalizedStringKey("status_all_steps_title")))
        }
    }

    private func iconColor(for index: Int, stage: AppViewModel.ProcessingStage) -> Color {
        if phase == .result || index < currentStageIndex {
            return .green
        }
        if index == currentStageIndex {
            return stage.iconTint
        }
        return .secondary
    }

    private func iconBackgroundColor(for index: Int, stage: AppViewModel.ProcessingStage) -> Color {
        if phase == .result || index < currentStageIndex {
            return Color.green.opacity(0.15)
        }
        if index == currentStageIndex {
            return stage.backgroundTint
        }
        return Color.secondary.opacity(0.08)
    }

    @ViewBuilder
    private func statusIndicator(for index: Int, stage: AppViewModel.ProcessingStage) -> some View {
        let indicator: some View = Group {
            if isStepCompleted(index) {
                Image(systemName: "checkmark.seal.fill")
                    .foregroundStyle(.green)
            } else if index == currentStageIndex {
                Image(systemName: "hourglass")
                    .foregroundStyle(stage.iconTint)
            } else {
                Image(systemName: "circle")
                    .foregroundStyle(.secondary)
            }
        }
        indicator
            .frame(width: 22, height: 22, alignment: .center)
    }

    private func isStepCompleted(_ index: Int) -> Bool {
        if phase == .result {
            return true
        }
        return index < currentStageIndex
    }

    private func textColor(for index: Int) -> Color {
        if phase == .result {
            return .primary
        }
        if index <= currentStageIndex {
            return .primary
        }
        return .secondary
    }
}

// MARK: - Download Section

private struct PrimaryFilledButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let baseColor = Color(.systemBlue)

        return configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(Color.white.opacity(isEnabled ? 1 : 0.35))
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: UIRadius.control, style: .continuous)
                    .fill(baseColor.opacity(isEnabled ? 1 : 0.4))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIRadius.control, style: .continuous)
                    .stroke(baseColor.opacity(0.9), lineWidth: 0.5)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

private struct TintedSecondaryButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    var isPressedTint: Bool

    func makeBody(configuration: Configuration) -> some View {
        let activeColor = isPressedTint ? Color.red : Color(red: 0.33, green: 0.48, blue: 0.97)
        let foreground = activeColor.opacity(isEnabled ? 1 : 0.35)

        return configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(foreground)
            .padding(.vertical, 8)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(activeColor.opacity(isEnabled ? 0.14 : 0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(activeColor.opacity(isEnabled ? 0.35 : 0.15), lineWidth: 1)
            )
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.85), value: configuration.isPressed)
    }
}

struct DownloadSectionView: View {
    let downloadPhase: AppViewModel.DownloadPhase
    let downloadProgress: DownloadProgress?
    let onDownload: () -> Void
    var onDownloadAll: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let onDownloadAll {
                HStack(spacing: 12) {
                    primaryButton
                    secondaryButton(action: onDownloadAll)
                }
            } else {
                primaryButton
            }

            DownloadStatusView(downloadPhase: downloadPhase)
        }
    }

    private var primaryButton: some View {
        Button {
            guard isButtonEnabled else { return }
            onDownload()
        } label: {
            Label {
                Text(primaryLabelKey)
            } icon: {
                buttonIcon
            }
        }
        .buttonStyle(PrimaryFilledButtonStyle())
        .disabled(!isButtonEnabled)
    }

    private func secondaryButton(action: @escaping () -> Void) -> some View {
        Button {
            guard isButtonEnabled else { return }
            action()
        } label: {
            Label {
                Text(secondaryLabelKey)
            } icon: {
                secondaryIcon
            }
        }
        .buttonStyle(PrimaryFilledButtonStyle())
        .disabled(!isButtonEnabled)
    }

    private var isButtonEnabled: Bool {
        switch downloadPhase {
        case .ready, .failed:
            true
        case .idle:
            false
        case .downloading, .success:
            false
        }
    }

    private var primaryLabelKey: LocalizedStringKey {
        text(for: .single)
    }

    private var secondaryLabelKey: LocalizedStringKey {
        text(for: .all)
    }

    private func text(for mode: DownloadProgress.Mode) -> LocalizedStringKey {
        switch downloadPhase {
        case .downloading:
            if let progress = downloadProgress, progress.mode == mode, progress.total > 1 {
                return LocalizedStringKey("\(progress.current)/\(progress.total)")
            }
            // Only the active mode gets the generic 'Saving…'; other buttons stay disabled without changing text
            if let progress = downloadProgress, progress.mode != mode {
                return mode == .single ? LocalizedStringKey("download_button") : LocalizedStringKey("download_all_button")
            }
            return LocalizedStringKey("download_in_progress_button")
        default:
            switch mode {
            case .single:
                return LocalizedStringKey("download_button")
            case .all:
                return LocalizedStringKey("download_all_button")
            }
        }
    }

    @ViewBuilder
    private var buttonIcon: some View {
        icon(for: .single)
    }

    @ViewBuilder
    private var secondaryIcon: some View {
        icon(for: .all)
    }

    @ViewBuilder
    private func icon(for mode: DownloadProgress.Mode) -> some View {
        let isActive = if case .downloading = downloadPhase { true } else { false }
        let isModeActive = isActive && downloadProgress?.mode == mode

        switch downloadPhase {
        case .downloading where isModeActive:
            ProgressView()
                .progressViewStyle(.circular)
                .tint(.white)
                .frame(width: 20, height: 20)
        default:
            Image(systemName: mode == .all ? "square.and.arrow.down.on.square.fill" : "square.and.arrow.down.fill")
                .imageScale(.medium)
        }
    }
}

struct DownloadStatusView: View {
    let downloadPhase: AppViewModel.DownloadPhase
    @State private var rotation: Angle = .zero

    var body: some View {
        switch downloadPhase {
        case .idle:
            EmptyView()
        case .ready:
            Label {
                Text(LocalizedStringKey("download_ready_status"))
                    .font(.footnote)
            } icon: {
                Image(systemName: "info.circle")
            }
            .foregroundStyle(.secondary)
        case .downloading:
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(Color.blue.opacity(0.3), lineWidth: 3)
                        .frame(width: 34, height: 34)
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(Color.blue)
                        .rotationEffect(rotation)
                        .animation(.linear(duration: 1.2).repeatForever(autoreverses: false), value: rotation)
                        .onAppear {
                            rotation = Angle(degrees: 360)
                        }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(LocalizedStringKey("download_in_progress_status"))
                        .font(.footnote)
                        .bold()
                    Text(LocalizedStringKey("download_keep_open"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 4)
        case .success:
            Label {
                Text(LocalizedStringKey("download_success_status"))
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .foregroundStyle(.green)
            .font(.footnote)
        case .failed(let message):
            VStack(alignment: .leading, spacing: 4) {
                Label {
                    Text(LocalizedStringKey("download_failed_status"))
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                }
                .foregroundStyle(.orange)
                .font(.footnote)
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SignInGateSheet: View {
    @ObservedObject var viewModel: AppViewModel
    let onClose: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var reviewEmail: String = AppConfiguration.reviewLoginEmail
    @State private var reviewPassword: String = ""
    @State private var isEmailFormExpanded: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 32) {
                    header
                    signInButtons
                    emailToggleButton
                    if isEmailFormExpanded {
                        emailLoginSection
                            .transition(.opacity.combined(with: .move(edge: .top)))
                    }
                    infoCard
                    Button {
                        dismissSheet()
                    } label: {
                        Text(LocalizedStringKey("signin_gate_close"))
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 32)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(Text(LocalizedStringKey("signin_gate_title")))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismissSheet()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                    }
                    .accessibilityLabel(Text(LocalizedStringKey("signin_gate_close")))
                }
            }
            .alert(
                Text(verbatim: viewModel.authErrorMessage ?? NSLocalizedString("settings_auth_error", comment: "")),
                isPresented: Binding(
                    get: { viewModel.authErrorMessage != nil },
                    set: { if !$0 { viewModel.authErrorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    viewModel.authErrorMessage = nil
                }
            }
            .onChange(of: viewModel.isAuthenticated) { isAuthenticated in
                if isAuthenticated {
                    reviewPassword = ""
                    dismissSheet()
                }
            }
        }
        .presentationDetents([.large])
    }

    private var header: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.checkmark")
                .font(.system(size: 48))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            Text(LocalizedStringKey("signin_gate_title"))
                .font(.title2.bold())
                .multilineTextAlignment(.center)

            Text(LocalizedStringKey("signin_gate_subtitle"))
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
    }

    private var signInButtons: some View {
        VStack(spacing: 12) {
            googleButton
            appleButton
        }
        .frame(maxWidth: .infinity)
    }

    private var disableOAuthButtons: Bool {
        viewModel.isGoogleLinking || viewModel.isAppleLinking || viewModel.isReviewLinking
    }

    private var emailToggleButton: some View {
        Button {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                isEmailFormExpanded.toggle()
            }
        } label: {
            Text(LocalizedStringKey(isEmailFormExpanded ? "signin_email_toggle_hide" : "signin_email_toggle_show"))
                .font(.subheadline.weight(.semibold))
                .underline()
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isReviewLinking)
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            infoRow(icon: "lock.fill", textKey: "signin_gate_reason_sync")
            infoRow(icon: "arrow.triangle.2.circlepath", textKey: "signin_gate_reason_security")
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: UIRadius.card, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: UIRadius.card, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        )
    }

    private func infoRow(icon: String, textKey: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.accentColor.opacity(0.12))
                )
            Text(LocalizedStringKey(textKey))
                .font(.body)
        }
    }

    private var emailLoginSection: some View {
        EmailSignInCard(
            viewModel: viewModel,
            email: $reviewEmail,
            password: $reviewPassword,
            autoFocusEmail: isEmailFormExpanded,
            showsCaption: true
        )
    }

    private var googleButton: some View {
        Button {
            viewModel.linkGoogleAccount()
        } label: {
            HStack(spacing: 12) {
                if viewModel.isGoogleLinking {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.primary)
                        .frame(width: 24, height: 24)
                } else {
                    Image("GoogleIcon")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 22, height: 22)
                }
                Text(
                    LocalizedStringKey(
                        viewModel.isGoogleLinking
                        ? "settings_connecting_google"
                        : "settings_connect_google"
                    )
                )
                    .font(.body.weight(.semibold))
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: UIRadius.control, style: .continuous)
                    .fill(Color.white)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIRadius.control, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disableOAuthButtons)
    }

    private var appleButton: some View {
        Button {
            viewModel.linkAppleAccount()
        } label: {
            HStack(spacing: 12) {
                if viewModel.isAppleLinking {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "applelogo")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color.white)
                }
                Text(
                    LocalizedStringKey(
                        viewModel.isAppleLinking
                        ? "settings_connecting_apple"
                        : "settings_connect_apple"
                    )
                )
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Color.white)
                Spacer()
            }
            .padding(.vertical, 14)
            .padding(.horizontal, 16)
            .background(
                RoundedRectangle(cornerRadius: UIRadius.control, style: .continuous)
                    .fill(Color.black)
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIRadius.control, style: .continuous)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(disableOAuthButtons)
    }

    private func dismissSheet() {
        dismiss()
        onClose()
    }
}


private struct PaywallView: View {
    struct PlanCard: Identifiable {
        let plan: AppViewModel.PaywallPlan
        let titleKey: LocalizedStringKey
        let descriptionKey: LocalizedStringKey
        let badgeKey: LocalizedStringKey?
        let accent: Color

        var id: AppViewModel.PaywallPlan { plan }
    }

    enum SubscriptionAttemptResult {
        case success
        case cancelled
        case failure(String)
    }

    let products: [AppViewModel.PaywallPlan: Product]
    let isLoadingProducts: Bool
    let onAppearLoadProducts: () -> Void
    let onClose: () -> Void
    let onSubscribe: (AppViewModel.PaywallPlan) async -> SubscriptionAttemptResult
    let onRestore: () async -> AppViewModel.RestoreOutcome
    let isRestoringPurchases: Bool

    private let termsURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private let privacyURL = URL(string: "https://awesomeapp.com/mobile/privacy")!

    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @State private var selectedPlan: AppViewModel.PaywallPlan? = .weekly
    @State private var isSubscribing = false
    @State private var restoreAlertMessage: String?
    @State private var subscribeAlertMessage: String?
    @State private var subscribeSuccessMessage: String?

    private var plans: [PlanCard] {
        [
            PlanCard(
                plan: .weekly,
                titleKey: LocalizedStringKey("paywall_weekly_title"),
                descriptionKey: LocalizedStringKey("paywall_weekly_description"),
                badgeKey: nil,
                accent: Color(red: 0.27, green: 0.52, blue: 0.98)
            ),
            PlanCard(
                plan: .monthly,
                titleKey: LocalizedStringKey("paywall_monthly_title"),
                descriptionKey: LocalizedStringKey("paywall_monthly_description"),
                badgeKey: LocalizedStringKey("paywall_best_value"),
                accent: Color(red: 0.62, green: 0.38, blue: 0.96)
            )
        ]
    }

    private var selectedPlanCard: PlanCard? {
        guard let selectedPlan else { return nil }
        return plans.first { $0.plan == selectedPlan }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.11, green: 0.12, blue: 0.22),
                        Color(red: 0.11, green: 0.17, blue: 0.33)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 28) {
                        VStack(spacing: 12) {
                            Text(LocalizedStringKey("paywall_title"))
                                .font(.largeTitle.bold())
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white)

                            Text(LocalizedStringKey("paywall_subtitle"))
                                .font(.headline)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        .padding(.top, 12)

                        VStack(spacing: 18) {
                            ForEach(plans) { plan in
                                planButton(for: plan, isSelected: plan.plan == selectedPlan)
                            }
                            if isLoadingProducts {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            }
                        }

                        subscribeButton

                        restorePurchasesButton

                        complianceSection
                    }
                    .padding(.horizontal, 28)
                    .padding(.bottom, 40)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        closePaywall()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .imageScale(.large)
                    }
                    .accessibilityLabel(Text(LocalizedStringKey("settings_close")))
                }
            }
            .alert(
                restoreAlertMessage ?? "",
                isPresented: Binding(
                    get: { restoreAlertMessage != nil },
                    set: { if !$0 { restoreAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    restoreAlertMessage = nil
                }
            }
            .alert(
                subscribeAlertMessage ?? "",
                isPresented: Binding(
                    get: { subscribeAlertMessage != nil },
                    set: { if !$0 { subscribeAlertMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    subscribeAlertMessage = nil
                }
            }
            .alert(
                subscribeSuccessMessage ?? "",
                isPresented: Binding(
                    get: { subscribeSuccessMessage != nil },
                    set: { if !$0 { subscribeSuccessMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {
                    subscribeSuccessMessage = nil
                    closePaywall()
                }
            }
        }
        .onAppear {
            onAppearLoadProducts()
        }
    }

    private func planButton(for plan: PlanCard, isSelected: Bool) -> some View {
        Button {
            selectedPlan = plan.plan
        } label: {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(plan.titleKey)
                            .font(.headline)
                            .foregroundStyle(.white)
                        if let badgeKey = plan.badgeKey {
                            Text(badgeKey)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(plan.accent.opacity(0.85))
                                )
                                .overlay(
                                    Capsule()
                                        .stroke(Color.white.opacity(0.4), lineWidth: 1)
                                )
                        }
                    }
                    Text(plan.descriptionKey)
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.8))
                    Text(priceDescription(for: plan.plan))
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.white)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: UIRadius.card, style: .continuous)
                    .fill(isSelected ? plan.accent.opacity(0.2) : Color.white.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIRadius.card, style: .continuous)
                    .stroke(isSelected ? Color(red: 0xFE / 255, green: 0x7A / 255, blue: 0x6F / 255) : Color.white.opacity(0.15), lineWidth: isSelected ? 2 : 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubscribing || isRestoringPurchases)
    }

    private var subscribeButton: some View {
        Button {
            subscribe()
        } label: {
            HStack(spacing: 12) {
                if isSubscribing {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white)
                        .frame(width: 24, height: 24)
                } else {
                    Image(systemName: "sparkles")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }
                Text(LocalizedStringKey(isSubscribing ? "paywall_subscribing" : "paywall_continue_cta"))
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white.opacity(isSubscribing ? 0.75 : 1))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .padding(.horizontal, 20)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 0xFE / 255, green: 0x68 / 255, blue: 0x71 / 255),
                        Color(red: 0xFF / 255, green: 0xA3 / 255, blue: 0x6B / 255)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .opacity(isSubscribing ? 0.7 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: UIRadius.control, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: UIRadius.control, style: .continuous)
                    .stroke(Color.white.opacity(0.25), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.25), radius: 18, x: 0, y: 12)
        }
        .buttonStyle(.plain)
        .disabled(!isPlanReadyForPurchase || isSubscribing || isRestoringPurchases)
        .padding(.top, 8)
    }

    private var restorePurchasesButton: some View {
        Button {
            runRestoreFlow()
        } label: {
            let title = LocalizedStringKey(isRestoringPurchases ? "paywall_restoring" : "paywall_restore_button")
            HStack(spacing: 12) {
                if isRestoringPurchases {
                    ProgressView()
                        .progressViewStyle(.circular)
                        .tint(.white.opacity(0.9))
                        .frame(width: 20, height: 20)
                } else {
                    Image(systemName: "arrow.clockwise.circle")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.85))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .padding(.horizontal, 18)
            .background(
                RoundedRectangle(cornerRadius: UIRadius.control, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: UIRadius.control, style: .continuous)
                    .stroke(Color.white.opacity(0.2), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isRestoringPurchases || isSubscribing)
    }

    private var complianceSection: some View {
        VStack(spacing: 10) {
            VStack(spacing: 6) {
                Text(LocalizedStringKey("paywall_links_caption"))
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                HStack(spacing: 18) {
                    Link(destination: termsURL) {
                        Text(LocalizedStringKey("paywall_terms_link"))
                            .underline()
                    }
                    Link(destination: privacyURL) {
                        Text(LocalizedStringKey("paywall_privacy_link"))
                            .underline()
                    }
                }
                .font(.footnote)
                .tint(.white)
            }
        }
        .padding(.horizontal, 8)
    }

    private func subscribe() {
        guard let plan = selectedPlan, !isSubscribing, !isRestoringPurchases else { return }
        subscribeAlertMessage = nil
        subscribeSuccessMessage = nil
        isSubscribing = true
        let planForPurchase = plan
        Task {
            let result = await onSubscribe(planForPurchase)
            await MainActor.run {
                isSubscribing = false
                switch result {
                case .success:
                    subscribeSuccessMessage = successMessage(for: planForPurchase)
                case .failure(let message):
                    subscribeAlertMessage = message
                case .cancelled:
                    break
                }
            }
        }
    }

    private func runRestoreFlow() {
        guard !isRestoringPurchases, !isSubscribing else { return }
        Task {
            let outcome = await onRestore()
            switch outcome {
            case .restored:
                closePaywall()
            case .notFound, .failed, .guestLinkRequired:
                restoreAlertMessage = outcome.localizedDescription
            case .cancelled:
                break
            }
        }
    }

    private func priceDescription(for plan: AppViewModel.PaywallPlan) -> String {
        guard let product = products[plan] else {
            return NSLocalizedString("paywall_price_loading", comment: "Displayed while localized StoreKit price loads")
        }
        let formatKey: String
        switch plan {
        case .weekly:
            formatKey = "paywall_weekly_price"
        case .monthly:
            formatKey = "paywall_monthly_price"
        }
        let format = NSLocalizedString(formatKey, comment: "Price per period format")
        return String(format: format, product.displayPrice)
    }

    private func successMessage(for plan: AppViewModel.PaywallPlan) -> String {
        let template = NSLocalizedString("paywall_purchase_success_message", comment: "Shown after a successful subscription purchase")
        return String(format: template, planTitle(for: plan))
    }

    private func planTitle(for plan: AppViewModel.PaywallPlan) -> String {
        switch plan {
        case .weekly:
            return NSLocalizedString("paywall_weekly_title", comment: "Weekly plan title")
        case .monthly:
            return NSLocalizedString("paywall_monthly_title", comment: "Monthly plan title")
        }
    }

    private var isPlanReadyForPurchase: Bool {
        guard let selectedPlan else { return false }
        return products[selectedPlan] != nil
    }

    private func closePaywall() {
        subscribeAlertMessage = nil
        subscribeSuccessMessage = nil
        dismiss()
        onClose()
    }

}

private enum TokenBalanceFormatter {
    static let shared: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = " "
        formatter.groupingSize = 3
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 0
        return formatter
    }()
}

private func tokenBalanceString(for value: Int) -> String {
    TokenBalanceFormatter.shared.string(from: NSNumber(value: value)) ?? "\(value)"
}

private struct EmailBadgeIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.systemGray6))
            Image(systemName: "envelope.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(.systemBlue))
        }
        .frame(width: 32, height: 32)
        .overlay(
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

private struct AppleBadgeIcon: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        ZStack {
            Image(systemName: "applelogo")
                .font(.system(size: 18, weight: .regular))
                .foregroundStyle(colorScheme == .dark ? Color.white : Color.black)
        }
        .frame(width: 20, height: 20)
    }
}

private struct AccountProviderIcon: View {
    let provider: AuthProvider

    var body: some View {
        switch provider {
        case .google:
            GoogleBadgeIcon()
        case .apple:
            AppleBadgeIcon()
        case .review:
            EmailBadgeIcon()
        case .guest:
            GuestBadgeIcon()
        }
    }
}

private struct GuestBadgeIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(.systemGray6))
            Image(systemName: "person.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(.systemGray))
        }
        .frame(width: 26, height: 26)
        .overlay(
            Circle()
                .stroke(Color(.systemGray4), lineWidth: 1)
        )
    }
}

private struct GuestUpgradeBannerView: View {
    let titleKey: LocalizedStringKey
    let messageKey: LocalizedStringKey
    let linkAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(titleKey)
                .font(.headline)
                .foregroundStyle(.primary)
            Text(messageKey)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 12) {
                Button {
                    linkAction()
                } label: {
                    Text(LocalizedStringKey("guest_upgrade_banner_cta"))
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    dismissAction()
                } label: {
                    Text(LocalizedStringKey("guest_upgrade_banner_dismiss"))
                        .font(.subheadline.weight(.semibold))
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(.ultraThinMaterial)
                .shadow(color: Color.black.opacity(0.1), radius: 18, x: 0, y: 8)
        )
    }
}

private struct GoogleBadgeIcon: View {
    var body: some View {
        ZStack {
            Circle()
                .fill(Color(red: 0.93, green: 0.95, blue: 1.0))
            Text("G")
                .font(.system(size: 13, weight: .black))
                .foregroundStyle(Color(red: 0.22, green: 0.45, blue: 0.93))
        }
        .frame(width: 26, height: 26)
        .overlay(
            Circle()
                .stroke(Color(red: 0.75, green: 0.84, blue: 1.0), lineWidth: 1)
        )
    }
}

private struct EmailSignInCard: View {
    @ObservedObject var viewModel: AppViewModel
    @Binding var email: String
    @Binding var password: String
    var autoFocusEmail: Bool = false
    var showsCaption: Bool = false
    @FocusState private var focusedField: Field?

    enum Field {
        case email
        case password
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(LocalizedStringKey("signin_email_title"))
                .font(.subheadline.weight(.semibold))

            if showsCaption {
                Text(LocalizedStringKey("signin_email_caption"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 10) {
                TextField(LocalizedStringKey("signin_email_email_label"), text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .disableAutocorrection(true)
                    .textContentType(.emailAddress)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.next)
                    .onSubmit {
                        focusedField = .password
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: UIRadius.input, style: .continuous)
                            .fill(Color(.tertiarySystemBackground))
                    )

                SecureField(LocalizedStringKey("signin_email_password_label"), text: $password)
                    .textContentType(.password)
                    .focused($focusedField, equals: .password)
                    .submitLabel(.go)
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: UIRadius.input, style: .continuous)
                            .fill(Color(.tertiarySystemBackground))
                    )
                    .onSubmit(submit)
            }

            Button {
                submit()
            } label: {
                HStack {
                    if viewModel.isReviewLinking {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(.white)
                    }
                    Text(LocalizedStringKey(viewModel.isReviewLinking ? "settings_connecting_email" : "signin_email_button"))
                        .font(.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: UIRadius.control, style: .continuous)
                        .fill(Color.blue.opacity(viewModel.isReviewLinking ? 0.5 : 0.9))
                )
                .foregroundStyle(Color.white)
            }
            .buttonStyle(.plain)
            .disabled(viewModel.isReviewLinking)
        }
        .onAppear {
            if autoFocusEmail {
                focusedField = .email
            }
        }
    }

    private func submit() {
        guard !viewModel.isReviewLinking else { return }
        viewModel.linkReviewAccount(email: email, password: password)
    }
}

#Preview {
    ContentView()
}
