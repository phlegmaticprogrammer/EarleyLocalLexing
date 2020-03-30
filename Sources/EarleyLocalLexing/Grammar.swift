import Foundation

public protocol EvalEnv {
    
    func copy() -> Self

}

public typealias EvalFunc<Param> = (EvalEnv, [Param]) -> Param?

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

public struct Rule<Param> {
    public let initialEnv : EvalEnv
    public let lhs : Symbol
    public let rhs : [(EvalFunc<Param>, Symbol)]
    public let out : EvalFunc<Param>
    public let ruleIndex : Int
    
    public init(initialEnv : EvalEnv, lhs : Symbol, rhs : [(EvalFunc<Param>, Symbol)], out : @escaping EvalFunc<Param>, ruleIndex : Int) {
        precondition(lhs != .character)
        self.initialEnv = initialEnv
        self.lhs = lhs
        self.rhs = rhs
        self.out = out
        self.ruleIndex = ruleIndex
    }
    
    func nextSymbol(dot : Int) -> Symbol? {
        if dot >= rhs.count { return nil }
        else { return rhs[dot].1 }
    }
    
    func nextF(dot : Int) -> EvalFunc<Param> {
        if dot >= rhs.count { return out } else { return rhs[dot].0 }
    }
    
    func initialItem<Result>(k : Int, param : Param) -> EarleyItem<Param, Result>? {
        let env = initialEnv.copy()
        if let value = nextF(dot: 0)(env, [param]) {
            return EarleyItem<Param, Result>(ruleIndex: ruleIndex, env: env, values: [param, value], results: [], indices: [k])
        } else {
            return nil
        }
    }
    
    func nextItem<Result>(item : EarleyItem<Param, Result>, k : Int, value : Param, result : Result?) -> EarleyItem<Param, Result>?
    {
        var values = item.values
        values.append(value)
        var results = item.results
        results.append(result)
        let env = item.env.copy()
        if let value = nextF(dot: item.dot+1)(env, values) {
            values.append(value)
            var indices = item.indices
            indices.append(k)
            return EarleyItem(ruleIndex: item.ruleIndex, env: env, values: values, results: results, indices: indices)
        } else {
            return nil
        }
    }
}

public protocol Input {
    
    associatedtype Char
    
    subscript(position : Int) -> Char? { get }
                
}

public enum ParseResult<Param : Hashable, Result> {
    case failed(position : Int)
    case success(length : Int, results : [Param : Result?])
}

public struct TokenResult<Param : Hashable, Result> : Hashable {
    public let length : Int
    public let outputParam : Param
    public let result : Result?
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(length)
        hasher.combine(outputParam)
    }
    
    public static func == (left : TokenResult<Param, Result>, right : TokenResult<Param, Result>) -> Bool {
        return left.length == right.length && left.outputParam == right.outputParam
    }

}

public struct TerminalKey<Param : Hashable> : Hashable {
    public let terminalIndex : Int
    public let inputParam : Param
}

public final class Grammar<C : ConstructResult> {
    
    public typealias Param = C.Param
    
    public typealias Result = C.Result
                
    public typealias RuleIndex = Int
        
    public typealias Tokens = [TerminalKey<Param> : Set<TokenResult<Param, Result>>]
    
    public typealias Selector = (Tokens) -> Tokens

    public let rules : [Rule<Param>]
    
    let selector : Selector
    
    private let rulesOfSymbols : [Symbol : [RuleIndex]]
    
    let constructResult : C
    
    public func rulesOf(symbol : Symbol) -> [RuleIndex] {
        return rulesOfSymbols[symbol] ?? []
    }
    
    public init(rules : [Rule<Param>], selector : @escaping Selector, constructResult : C) {
        self.rules = rules
        self.selector = selector
        self.constructResult = constructResult
        var rOf : [Symbol : [RuleIndex]] = [:]
        for (ruleIndex, rule) in rules.enumerated() {
            precondition(rule.ruleIndex == ruleIndex)
            appendTo(dict: &rOf, key: rule.lhs, value: ruleIndex)
        }
        self.rulesOfSymbols = rOf
    }
    
    public func parse<I : Input>(input : I, position : Int, symbol : Symbol, inputParam : Param) -> ParseResult<Param, Result> where I.Char == Param {
        let parser = EarleyParser(grammar: self, initialSymbol: symbol, initialParam: inputParam, input: input, startPosition: position, treatedAsNonterminals: [])
        return parser.parse()
    }
    
}
