#if !os(Linux)
import XCTest

/// Enhances failure messages with a command line diff tool expression that can be copied and pasted into a terminal.
///
///     diffTool = "ksdiff"
public var diffTool: String? = nil

/// Whether or not to record all new references.
public var record = false

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
  matching value: @autoclosure () throws -> Value,
  as snapshotting: Snapshotting<Value, Format>,
  named name: String? = nil,
  record recording: Bool = false,
  timeout: TimeInterval = 5,
  file: StaticString = #file,
  testName: String = #function,
  line: UInt = #line
  ) {

  let failure = verifySnapshot(
    matching: value,
    as: snapshotting,
    named: name,
    record: recording,
    timeout: timeout,
    file: file,
    testName: testName,
    line: line
  )
  guard let message = failure else { return }
  XCTFail(message, file: file, line: line)
}

/// Verifies that a given value matches a reference on disk.
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
/// - Returns: A failure message or, if the value matches, nil.
public func verifySnapshot<Value, Format>(
  matching value: @autoclosure () throws -> Value,
  as snapshotting: Snapshotting<Value, Format>,
  named name: String? = nil,
  record recording: Bool = false,
  timeout: TimeInterval = 5,
  file: StaticString = #file,
  testName: String = #function,
  line: UInt = #line
  )
  -> String? {

    let recording = recording || record

    do {
      let (directoryUrl, fileUrl, fileName) = snapshot(file: file, name: name, testName: testName, pathExtension: snapshotting.pathExtension ?? "")
      let fileManager = FileManager.default
      try fileManager.createDirectory(at: directoryUrl, withIntermediateDirectories: true)
      checked[directoryUrl, default: []].append(fileUrl)


      let tookSnapshot = XCTestExpectation(description: "Took snapshot")
      var optionalDiffable: Format?
      snapshotting.snapshot(try value()).run { b in
        optionalDiffable = b
        tookSnapshot.fulfill()
      }
      let result = XCTWaiter.wait(for: [tookSnapshot], timeout: timeout)
      switch result {
      case .completed:
        break
      case .timedOut:
        return "Exceeded timeout of \(timeout) seconds waiting for snapshot"
      case .incorrectOrder, .invertedFulfillment, .interrupted:
        return "Couldn't snapshot value"
      }

      guard let diffable = optionalDiffable else {
        return "Couldn't snapshot value"
      }

      guard !recording, fileManager.fileExists(atPath: fileUrl.path) else {
        try snapshotting.diffing.toData(diffable).write(to: fileUrl)
        return "Recorded snapshot: …\n\n\"\(fileUrl.path)\""
      }

      let data = try Data(contentsOf: fileUrl)
      let reference = snapshotting.diffing.fromData(data)

      guard let (failure, attachments) = snapshotting.diffing.diff(reference, diffable) else {
        return nil
      }

      let artifactsUrl = URL(
        fileURLWithPath: ProcessInfo.processInfo.environment["SNAPSHOT_ARTIFACTS"] ?? NSTemporaryDirectory()
      )
      let artifactsSubUrl = artifactsUrl.appendingPathComponent(fileName)
      try fileManager.createDirectory(at: artifactsSubUrl, withIntermediateDirectories: true)
      let failedSnapshotFileUrl = artifactsSubUrl.appendingPathComponent(fileUrl.lastPathComponent)
      try snapshotting.diffing.toData(diffable).write(to: failedSnapshotFileUrl)

      if !attachments.isEmpty {
        #if !os(Linux)
        XCTContext.runActivity(named: "Attached Failure Diff") { activity in
          attachments.forEach {
            activity.add($0.rawValue)
          }
        }
        #endif
      }

      let diffMessage = diffTool
        .map { "\($0) \"\(fileUrl.path)\" \"\(failedSnapshotFileUrl.path)\"" }
        ?? "@\(minus)\n\"\(fileUrl.path)\"\n@\(plus)\n\"\(failedSnapshotFileUrl.path)\""
      return """
      \(failure.trimmingCharacters(in: .whitespacesAndNewlines))

      \(diffMessage)
      """
    } catch {
      return error.localizedDescription
    }
}

/// Asserts that all snapshots were checked for a test case
///   (call it from the test case's tearDown method)
///
/// - Parameters:
///   - for: The test case's class
///   - file: The file in which failure occurred. Defaults to the file name of the test case in which this function was called.
///   - line: The line number on which failure occurred. Defaults to the line number on which this function was called.
public func assertAllSnapshotsChecked(for testClass: XCTestCase.Type,
                                      file: StaticString = #file,
                                      line: UInt = #line) {
  let failure = verifyAllSnapshotsChecked(for: testClass, file: file)
  guard let message = failure else { return }
  XCTFail(message, file: file, line: line)

}

/// Verify that all snapshots were checked for a test case
///
/// - Parameters:
///   - for: The test case's class
///   - file: The file in which failure occurred. Defaults to the file name of the test case in which this function was called.
func verifyAllSnapshotsChecked(for testClass: XCTestCase.Type, file: StaticString) -> String? {
  guard let testCount = numberOfTestMethods(testClass) else {
    return "Couldn't find methodList for \(testClass)"
  }
  
  let (directoryUrl, _) = snapshotBase(file: file)
  let counter = checkedQueue.sync { () -> Int in
    checkedCounter[directoryUrl, default: 0] += 1
    return checkedCounter[directoryUrl]!
  }
  
  // only assert if all test were run
  guard testCount == counter else { return nil }
  
  let fileManager = FileManager.default
  do {
    let expected = try fileManager.contentsOfDirectory(at: directoryUrl,
                                                       includingPropertiesForKeys: [],
                                                       options: .skipsHiddenFiles)
    let diff: String = expected
      .filter { !checked[directoryUrl, default: []].contains($0) }
      .map { $0.absoluteString }
      .joined(separator: "\n")
    guard diff.isEmpty else {
      return "These files were not checked:\n\(diff)"
    }
    return nil
  } catch {
    return error.localizedDescription
  }
}

private func numberOfTestMethods(_ testClass: XCTestCase.Type) -> Int? {
  var methodCount: UInt32 = 0
  guard let methodList = class_copyMethodList(testClass, &methodCount) else {
    return nil
  }
  let count: Int = (0..<Int(methodCount))
    .reduce(0, { result, index in
      let selName = sel_getName(method_getName(methodList[index]))
      let methodName = String(cString: selName, encoding: .utf8)!
      return result + (methodName.hasPrefix("test") ? 1 : 0)
    })
  return count
}

private let checkedQueue = DispatchQueue(label: "co.pointfree.SnapshotTesting.checkedCounter")
private var checkedCounter: [URL: Int] = [:]
private var checked: [URL: [URL]] = [:]

#endif // Linux

func sanitizePathComponent(_ string: String) -> String {
  return string
    .replacingOccurrences(of: "\\W+", with: "-", options: .regularExpression)
    .replacingOccurrences(of: "^-|-$", with: "", options: .regularExpression)
}
