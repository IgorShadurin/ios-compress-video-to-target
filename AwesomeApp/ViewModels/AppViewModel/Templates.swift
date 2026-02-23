import Foundation

extension AppViewModel {
    var currentTemplateTitle: String {
        selectedTemplateOption?.title ?? NSLocalizedString("template_default_label", comment: "")
    }

    var templateAccessibilityValue: String {
        currentTemplateTitle
    }

    var templateButtonIndicatorActive: Bool {
        guard let defaultId = templateDefaultId else {
            return selectedTemplateId != nil
        }
        guard let selected = selectedTemplateId else { return false }
        return selected != defaultId
    }

    var selectedTemplateOption: TemplateOption? {
        guard let selectedTemplateId else { return nil }
        return templateOptions.first(where: { $0.id == selectedTemplateId })
    }

    func loadTemplatePreference() {
        if let stored = projectPreferencesStore.value(for: .selectedTemplateId) {
            selectedTemplateId = stored
        }
    }

    func loadCachedTemplateOptions() {
        guard let cached = templateCacheStore.load() else { return }
        templateOptions = cached.options
        if templateDefaultId == nil {
            templateDefaultId = cached.options.first?.id
        }
        reconcileTemplateSelection()
        prefetchTemplateImages(for: cached.options)
    }

    func refreshTemplateOptions(force: Bool = false) {
        if isLoadingTemplates && !force { return }
        templateLoadingTask?.cancel()
        templateLoadingTask = Task { [weak self] in
            guard let self else { return }
            await self.performTemplateRefresh()
            self.templateLoadingTask = nil
        }
    }

    func retryTemplateLoad() {
        refreshTemplateOptions(force: true)
    }

    func selectTemplate(withId id: String) {
        guard selectedTemplateId != id else { return }
        selectedTemplateId = id
        projectPreferencesStore.set(id, for: .selectedTemplateId)
    }

    func selectTemplate(_ option: TemplateOption) {
        selectTemplate(withId: option.id)
    }

    private func performTemplateRefresh() async {
        isLoadingTemplates = true
        templateLoadErrorMessage = nil
        do {
            let token: String?
            if currentSession != nil {
                token = try? await ensureValidSession().tokens.accessToken
            } else {
                token = nil
            }
            let responses = try await apiClient.fetchTemplateOptions(accessToken: token)
            let options = responses.map(TemplateOption.init)
            templateOptions = options
            templateCacheStore.save(options: options)
            prefetchTemplateImages(for: options)
            if let currentDefault = templateDefaultId {
                if !options.contains(where: { $0.id == currentDefault }) {
                    templateDefaultId = options.first?.id
                }
            } else {
                templateDefaultId = options.first?.id
            }
            reconcileTemplateSelection()
            isLoadingTemplates = false
        } catch {
            templateLoadErrorMessage = error.localizedDescription
            isLoadingTemplates = false
        }
    }

    private func reconcileTemplateSelection() {
        let availableIds = Set(templateOptions.map(\.id))
        if let current = selectedTemplateId, availableIds.contains(current) {
            return
        }
        if let stored = projectPreferencesStore.value(for: .selectedTemplateId),
           availableIds.contains(stored) {
            selectedTemplateId = stored
            return
        }
        if let fallback = templateDefaultId, availableIds.contains(fallback) {
            selectedTemplateId = fallback
            projectPreferencesStore.set(fallback, for: .selectedTemplateId)
            return
        }
        if let first = templateOptions.first?.id {
            selectedTemplateId = first
            projectPreferencesStore.set(first, for: .selectedTemplateId)
        } else {
            selectedTemplateId = nil
            projectPreferencesStore.set(nil, for: .selectedTemplateId)
        }
    }

    private func prefetchTemplateImages(for options: [TemplateOption]) {
        templateImagePrefetchTask?.cancel()
        let urls = options.compactMap { $0.previewImageURL }
        guard !urls.isEmpty else { return }
        templateImagePrefetchTask = Task.detached(priority: .utility) {
            await withTaskGroup(of: Void.self) { group in
                for url in urls {
                    group.addTask {
                        var request = URLRequest(url: url)
                        request.cachePolicy = .returnCacheDataElseLoad
                        _ = try? await URLSession.shared.data(for: request)
                    }
                }
            }
        }
    }
}
