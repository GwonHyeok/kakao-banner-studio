enum BannerPreset: String, CaseIterable, Identifiable {
    case blank, seamless, custom

    static let builtIn: [Self] = [.blank]
    var id: Self { self }
}

enum BannerFormat {
    static let aspectRatio = 4
}
