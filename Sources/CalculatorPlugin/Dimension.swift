/// What kind of thing a quantity is, as integer exponents over base dimensions: speed is
/// length¹·time⁻¹, area is length², and a plain number has every exponent 0.
struct Dimension: Hashable, Sendable {
    enum Base: Int, CaseIterable, Sendable {
        case length, mass, time, data, temperature
    }

    private var exponents: [Int]

    static let none = Dimension(exponents: Array(repeating: 0, count: Base.allCases.count))

    init(_ base: Base, _ power: Int = 1) {
        self = .none
        exponents[base.rawValue] = power
    }

    private init(exponents: [Int]) {
        self.exponents = exponents
    }

    var isNone: Bool { self == .none }

    static func * (lhs: Dimension, rhs: Dimension) -> Dimension {
        Dimension(exponents: zip(lhs.exponents, rhs.exponents).map(+))
    }

    static func / (lhs: Dimension, rhs: Dimension) -> Dimension {
        Dimension(exponents: zip(lhs.exponents, rhs.exponents).map(-))
    }

    func raised(to power: Int) -> Dimension {
        Dimension(exponents: exponents.map { $0 * power })
    }
}
