import Foundation

/// Every screen models loading, empty, loaded and failed explicitly so no
/// surface can render an ambiguous blank state.
enum LoadState<Value> {
    case idle
    case loading
    case loaded(Value)
    case failed(DataError)

    var value: Value? {
        if case .loaded(let value) = self { return value }
        return nil
    }

    var isLoading: Bool {
        if case .loading = self { return true }
        return false
    }
}

extension DataError {
    /// Normalises any thrown error into a presentable `DataError`.
    static func wrap(_ error: Error) -> DataError {
        (error as? DataError) ?? .unexpected(error.localizedDescription)
    }
}
