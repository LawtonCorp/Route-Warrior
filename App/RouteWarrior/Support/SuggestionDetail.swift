import Foundation
import RouteWarriorKit

/// How autocomplete rows get the detail a driver needs to tell one
/// branch of a chain from another (D-040). Apple's completer answers a
/// business with many locations as a bare name — no address, and often
/// the same name several times over — so the completer looks those
/// names up as places and this merges what it finds back into the list.
/// Pure, so the app target can test the arrangement without a network.
enum SuggestionDetail {
    /// Rows a driver can tell apart without a lookup: at most this many.
    static let rowLimit = 10
    /// Locations a bare name expands to, nearest first.
    static let placesPerName = 5

    /// Subtitles the completer uses to mean "this is a search, not a place".
    private static let placeholders: Set<String> = ["", "search nearby"]

    /// A row that names a business but not where it is.
    static func needsDetail(_ suggestion: AddressSuggestion) -> Bool {
        suggestion.coordinate == nil
            && placeholders.contains(
                suggestion.subtitle.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            )
    }

    /// The names worth looking up in `completions`, in the order they
    /// appear, each once.
    static func namesNeedingDetail(in completions: [AddressSuggestion]) -> [String] {
        var seen = Set<String>()
        return completions.filter(needsDetail).map(\.title).filter { seen.insert($0).inserted }
    }

    /// Nearest first; rows whose distance is unknown go last, in the
    /// order they arrived.
    static func nearest(_ places: [AddressSuggestion], limit: Int = placesPerName) -> [AddressSuggestion] {
        let sorted = places.enumerated().sorted { a, b in
            switch (a.element.distanceMeters, b.element.distanceMeters) {
            case let (da?, db?) where da != db: return da < db
            case (.some, .none): return true
            case (.none, .some): return false
            default: return a.offset < b.offset
            }
        }
        return Array(sorted.map(\.element).prefix(limit))
    }

    /// The rows to show: `completions` in their own order, with each bare
    /// name replaced in place by the places found for it. A name whose
    /// lookup has not answered yet stays as one bare row rather than
    /// several identical ones, and nothing appears twice.
    static func merge(
        completions: [AddressSuggestion],
        details: [String: [AddressSuggestion]],
        limit: Int = rowLimit
    ) -> [AddressSuggestion] {
        var rows: [AddressSuggestion] = []
        var seen = Set<String>()
        for completion in completions {
            let expanded: [AddressSuggestion]
            if needsDetail(completion), let found = details[completion.title], !found.isEmpty {
                expanded = found
            } else {
                expanded = [completion]
            }
            for row in expanded where seen.insert(row.id).inserted {
                rows.append(row)
            }
        }
        return Array(rows.prefix(limit))
    }

    /// The second line of a row: the address, led by how far away it is
    /// when that is known.
    static func detailLine(for suggestion: AddressSuggestion) -> String {
        let address = suggestion.subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let metres = suggestion.distanceMeters else { return address }
        let distance = Format.distance(metres)
        return address.isEmpty ? distance : "\(distance) · \(address)"
    }
}
