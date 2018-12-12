@testable import SnapshotTesting
import XCTest

#if os(macOS)
extension NSTextField {
  var text: String {
    get { return self.stringValue }
    set { self.stringValue = newValue }
  }
}
#endif
