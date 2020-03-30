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

public final class Grammar<C : ConstructResult> {
    
    public typealias Param = C.Param
    
    public typealias Result = C.Result
            
    public typealias RuleIndex = Int
    
    public struct TokenResult : Hashable {
        public let length : Int
        public let value : Param
        public let result : Result?
        
        public func hash(into hasher: inout Hasher) {
            hasher.combine(length)
            hasher.combine(value)
        }
        
        public static func == (left : TokenResult, right : TokenResult) -> Bool {
            return left.length == right.length && left.value == right.value
        }

    }
    
    public typealias TerminalIndex = Int
    
    public struct TerminalKey : Hashable {
        public let terminalIndex : TerminalIndex
        public let value : Param
    }
    
    public typealias Tokens = [TerminalKey : Set<TokenResult>]
    
    public typealias Selector = (Tokens) -> Tokens

    public let rules : [Rule<Param>]
    
    public let selector : Selector
    
    private let rulesOfSymbols : [Symbol : [RuleIndex]]
    
    public let constructResult : C
    
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
