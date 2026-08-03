import Foundation

public extension Array where Element: Sendable {
    /// Transforms elements concurrently, limiting the number of active operations to available processor cores.
    func concurrentMap<Result: Sendable>(
        _ transform: @escaping @Sendable (Element) async throws -> Result,
    ) async throws -> [Result] {
        guard !isEmpty else { return [] }

        let maximumConcurrentTasks = Swift.max(1, ProcessInfo.processInfo.activeProcessorCount)
        return try await withThrowingTaskGroup(of: (Int, Result).self, returning: [Result].self) {
            group in
            var iterator = enumerated().makeIterator()
            var results = [Result?](repeating: nil, count: count)

            func addNextTask() {
                guard let (index, element) = iterator.next() else { return }
                group.addTask {
                    try await (index, transform(element))
                }
            }

            for _ in 0 ..< Swift.min(maximumConcurrentTasks, count) {
                addNextTask()
            }

            while let (index, result) = try await group.next() {
                results[index] = result
                addNextTask()
            }

            return results.compactMap(\.self)
        }
    }
}
