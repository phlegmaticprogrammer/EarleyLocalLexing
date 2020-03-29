import Foundation

public enum Symbol : Hashable, CustomStringConvertible {
    
    case terminal(index : Int)
    case nonterminal(index : Int)
    case character
    
    public var description : String {
        switch self {
        case let .terminal(index: index): return "terminal(\(index))"
        case let .nonterminal(index: index): return "nonterminal(\(index))"
        case .character: return "character"
        }
    }

}
