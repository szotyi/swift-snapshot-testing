import Foundation

typealias Snapshot = (directoryUrl: URL, fileUrl: URL, fileName: String)
typealias SnapshotBase = (directoryUrl: URL, fileName: String)

func snapshot(file: StaticString,
              name: String?,
              testName: String,
              pathExtension: String) -> Snapshot {
  
  let (directoryUrl, fileName) = snapshotBase(file: file)
  
  let identifier: String
  if let name = name {
    identifier = sanitizePathComponent(name)
  } else {
    let counter = counterQueue.sync { () -> Int in
      let key = directoryUrl.appendingPathComponent(testName)
      counterMap[key, default: 0] += 1
      return counterMap[key]!
    }
    identifier = String(counter)
  }
  
  let testName = sanitizePathComponent(testName)
  let fileUrl = directoryUrl
    .appendingPathComponent("\(testName).\(identifier)")
    .appendingPathExtension(pathExtension)
  return (directoryUrl: directoryUrl, fileUrl: fileUrl, fileName: fileName)
}

func snapshotBase(file: StaticString) -> SnapshotBase {
  let fileUrl = URL(fileURLWithPath: "\(file)")
  let fileName = fileUrl.deletingPathExtension().lastPathComponent
  let directoryUrl = fileUrl.deletingLastPathComponent()
    .appendingPathComponent("__Snapshots__")
    .appendingPathComponent(fileName)
    .appendingPathComponent(Platform.current.rawValue)
  return (directoryUrl: directoryUrl, fileName: fileName)
}

private let counterQueue = DispatchQueue(label: "co.pointfree.SnapshotTesting.snapshotCounter")
private var counterMap: [URL: Int] = [:]
