import Vapor

public extension Application.Views.Provider {
    static var tau: Self {
        .init {
            /// Pull  the Vapor directory, or leave as set if user has configured directly
            let detected = TemplateEngine.rootDirectory ?? $0.directory.viewsDirectory
            TemplateEngine.rootDirectory = detected
            /// Initialize sources to file-based reader with default settings if set with no sources (default)
            if TemplateEngine.sources.all.isEmpty {
                TemplateEngine.sources = .singleSource(FileSource(fileio: $0.fileio,
                                                                  limits: .default,
                                                                  sandboxDirectory: detected,
                                                                  viewDirectory: detected))
            }
            _ = TemplateEngine.entities
            /// Prime `app` context
            _ = $0.tau.context
            $0.views.use { $0.tau }
        }
    }
}
