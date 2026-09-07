import Foundation

/// All money in this app is `Decimal`, never `Double`.
///
/// Binary floating point cannot represent values like 0.07 or 19.99 exactly, so
/// summing invoice or quote lines with `Double` drifts by cents. `Decimal` is a
/// base-10 type: every helper here rounds explicitly at a defined scale so the
/// same numbers come out of the app, the database and the customer's paperwork.
nonisolated enum Money {
    /// Cent precision used for every stored and displayed amount.
    static let scale: Int16 = 2

    /// Exact decimal from a literal string. Use this instead of a float literal
    /// (`let x: Decimal = 0.07` goes through `Double` and is not exact).
    static func dec(_ literal: String) -> Decimal {
        Decimal(string: literal) ?? .zero
    }

    /// A tax rate from whole/partial percent, e.g. `percent("7")` → exactly 0.07.
    static func percent(_ literal: String) -> Decimal {
        (Decimal(string: literal) ?? .zero) / 100
    }

    static func rounded(_ value: Decimal, scale: Int16 = Money.scale) -> Decimal {
        var input = value
        var result = Decimal()
        NSDecimalRound(&result, &input, Int(scale), .plain)
        return result
    }

    /// Quantity × unit price, rounded to the cent.
    static func lineTotal(quantity: Decimal, unitPrice: Decimal) -> Decimal {
        rounded(quantity * unitPrice)
    }

    /// Tax is calculated per line and rounded to the cent before being summed,
    /// so the printed lines always add up to the printed tax figure.
    static func lineTax(lineTotal: Decimal, taxRate: Decimal) -> Decimal {
        rounded(lineTotal * taxRate)
    }

    static func percentLabel(_ rate: Decimal) -> String {
        let percent = rounded(rate * 100, scale: 3)
        return "\(percent.formatted(.number.precision(.fractionLength(0...3))))%"
    }

    static func quantityLabel(_ quantity: Decimal) -> String {
        quantity.formatted(.number.precision(.fractionLength(0...2)))
    }
}

/// Subtotal / tax / total for a set of line items.
nonisolated struct MoneyTotals: Hashable, Sendable {
    let subtotal: Decimal
    let tax: Decimal
    let total: Decimal

    static let zero = MoneyTotals(subtotal: 0, tax: 0, total: 0)
}

nonisolated protocol MoneyLine {
    var quantity: Decimal { get }
    var unitPrice: Decimal { get }
    var taxRate: Decimal { get }
}

nonisolated extension Money {
    /// Single place where quote and invoice totals are derived. Nothing in the
    /// app is allowed to add up money by itself.
    static func totals(for lines: [some MoneyLine]) -> MoneyTotals {
        var subtotal = Decimal.zero
        var tax = Decimal.zero
        for line in lines {
            let net = lineTotal(quantity: line.quantity, unitPrice: line.unitPrice)
            subtotal += net
            tax += lineTax(lineTotal: net, taxRate: line.taxRate)
        }
        let roundedSubtotal = rounded(subtotal)
        let roundedTax = rounded(tax)
        return MoneyTotals(
            subtotal: roundedSubtotal,
            tax: roundedTax,
            total: roundedSubtotal + roundedTax
        )
    }
}
