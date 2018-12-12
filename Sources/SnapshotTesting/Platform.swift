enum Platform: String {
  case iOS
  case macOS
  case tvOS
  case linux
}

extension Platform {
  static var current: Platform {
    #if os(iOS)
    return .iOS
    #elseif os(macOS)
    return .macOS
    #elseif os(tvOS)
    return .tvOS
    #elseif os(Linux)
    return .linux
    #else
    preconditionFailure("Unknown platform")
    #endif
  }
}
