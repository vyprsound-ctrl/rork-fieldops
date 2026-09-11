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
    ///
    /// View models call this on every catch, so it is the last thing standing
    /// between a raw API failure and a sentence a tradesperson reads. It used
    /// to fall back to `error.localizedDescription`, which for a PostgREST
    /// failure is an internal string written for a developer — "Could not find
    /// the function public.create_job(...) in the schema cache" is not an
    /// instruction anybody can act on.
    ///
    /// It now defers to the gateway's own translation, so a failure reaching
    /// the UI through a view model says exactly what it says when the gateway
    /// reports it directly, and a deterministic failure is never dressed up as
    /// something worth retrying.
    static func wrap(_ error: Error) -> DataError {
        if let dataError = error as? DataError { return dataError }
        return SupabaseDataGateway.translate(error)
    }
}
