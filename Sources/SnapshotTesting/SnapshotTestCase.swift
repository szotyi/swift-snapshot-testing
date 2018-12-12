#if os(Linux)
import XCTest

/// An XCTest subclass that provides snaphot testing helpers.
open class SnapshotTestCase: XCTestCase {
  /// Whether or not to record all new references.
  open var record = false

  /// Enhances failure messages with a command line expression that can be copied and pasted into a terminal.
  ///
  ///     diffTool = "ksdiff"
  open var diffTool: String? = nil

  /// Asserts that a given value matches a reference on disk.
  ///
  /// - Parameters:
  ///   - value: A value to compare against a reference.
  ///   - snapshotting: A strategy for serializing, deserializing, and comparing values.
  ///   - name: An optional description of the snapshot.
  ///   - recording: Whether or not to record a new reference.
  ///   - timeout: The amount of time a snapshot must be generated in.
  ///   - file: The file in which failure occurred. Defaults to the file name of the test case in which this function was called.
  ///   - testName: The name of the test in which failure occurred. Defaults to the function name of the test case in which this function was called.
  ///   - line: The line number on which failure occurred. Defaults to the line number on which this function was called.
  public func assertSnapshot<Value, Format>(
    matching value: Value,
    as snapshotting: Snapshotting<Value, Format>,
    named name: String? = nil,
    record recording: Bool = false,
    timeout: TimeInterval = 5,
    file: StaticString = #file,
    testName: String = #function,
    line: UInt = #line
    ) {

    let recording = recording || self.record

    do {
      let (directoryUrl, fileUrl, fileName) = snapshot(file: file, name: name, testName: testName, pathExtension: snapshotting.pathExtension ?? "")
      let fileManager = FileManager.default
      try fileManager.createDirectory(at: directoryUrl, withIntermediateDirectories: true)

      let tookSnapshot = self.expectation(description: "Took snapshot")
      var optionalDiffable: Format?
      snapshotting.snapshot(value).run { b in
        optionalDiffable = b
        tookSnapshot.fulfill()
      }
      #if os(Linux)
      self.waitForExpectations(timeout: timeout)
      #else
      self.wait(for: [tookSnapshot], timeout: timeout)
      #endif

      guard let diffing = optionalDiffable else {
        XCTFail("Couldn't snapshot value", file: file, line: line)
        return
      }

      guard !recording, fileManager.fileExists(atPath: fileUrl.path) else {
        try snapshotting.diffing.toData(diffing).write(to: fileUrl)
        XCTFail("Recorded snapshot: …\n\n\"\(fileUrl.path)\"", file: file, line: line)
        return
      }

      let data = try Data(contentsOf: fileUrl)
      let reference = snapshotting.diffing.fromData(data)

      guard let (failure, attachments) = snapshotting.diffing.diff(reference, diffing) else {
        return
      }

      let artifactsUrl = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"] ?? NSTemporaryDirectory()
      )
      let artifactsSubUrl = artifactsUrl.appendingPathComponent(fileName)
      try fileManager.createDirectory(at: artifactsSubUrl, withIntermediateDirectories: true)
      let failedSnapshotFileUrl = artifactsSubUrl.appendingPathComponent(fileUrl.lastPathComponent)
      try snapshotting.diffing.toData(diffing).write(to: failedSnapshotFileUrl)

      if !attachments.isEmpty {
        #if !os(Linux)
        XCTContext.runActivity(named: "Attached Failure Diff") { activity in
          attachments.forEach {
            activity.add($0.rawValue)
          }
        }
        #endif
      }

      let diffMessage = self.diffTool
        .map { "\($0) \"\(fileUrl.path)\" \"\(failedSnapshotFileUrl.path)\"" }
        ?? "@\(minus)\n\"\(fileUrl.path)\"\n@\(plus)\n\"\(failedSnapshotFileUrl.path)\""
      let message = """
      \(failure.trimmingCharacters(in: .whitespacesAndNewlines))

      \(diffMessage)
      """
      XCTFail(message, file: file, line: line)
    } catch {
      XCTFail(error.localizedDescription, file: file, line: line)
    }
  }
}
#endif
