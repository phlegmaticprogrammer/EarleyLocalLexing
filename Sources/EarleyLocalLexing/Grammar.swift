import Foundation

public protocol EvalEnv {
    
    func copy() -> Self

}

public typealias EvalFunc<Value> = (EvalEnv, [Value]) -> Value?

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

public struct Rule<Value> {
    public let initialEnv : EvalEnv
    public let lhs : Symbol
    public let rhs : [(EvalFunc<Value>, Symbol)]
    public let out : EvalFunc<Value>
    public let ruleIndex : Int
    
    public init(initialEnv : EvalEnv, lhs : Symbol, rhs : [(EvalFunc<Value>, Symbol)], out : @escaping EvalFunc<Value>, ruleIndex : Int) {
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
    
    func nextF(dot : Int) -> EvalFunc<Value> {
        if dot >= rhs.count { return out } else { return rhs[dot].0 }
    }
    
    func initialItem<Result>(k : Int, param : Value) -> EarleyItem<Value, Result>? {
        let env = initialEnv.copy()
        if let value = nextF(dot: 0)(env, [param]) {
            return EarleyItem<Value, Result>(ruleIndex: ruleIndex, env: env, values: [param, value], results: [], indices: [k])
        } else {
            return nil
        }
    }
    
    func nextItem<Result>(item : EarleyItem<Value, Result>, k : Int, value : Value, result : Result?) -> EarleyItem<Value, Result>?
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

public enum ParseResult<Value : Hashable, Result> {
    case failed(position : Int)
    case success(length : Int, results : [Value : Result?])
}

public final class Grammar<C : ConstructResult> {
    
    public typealias Value = C.Value
    
    public typealias Result = C.Result
            
    public typealias RuleIndex = Int
    
    public struct TokenResult : Hashable {
        public let length : Int
        public let value : Value
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
        public let value : Value
    }
    
    public typealias Tokens = [TerminalKey : Set<TokenResult>]
    
    public typealias Selector = (Tokens) -> Tokens

    public let rules : [Rule<Value>]
    
    public let selector : Selector
    
    private let rulesOfSymbols : [Symbol : [RuleIndex]]
    
    public let constructResult : C
    
    public func rulesOf(symbol : Symbol) -> [RuleIndex] {
        return rulesOfSymbols[symbol] ?? []
    }
    
    public init(rules : [Rule<Value>], selector : @escaping Selector, constructResult : C) {
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
    
    public func parse<I : Input>(input : I, position : Int, symbol : Symbol, param : Value) -> ParseResult<Value, Result> where I.Char == Value {
        let parser = EarleyParser(grammar: self, initialSymbol: symbol, initialParam: param, input: input, startPosition: position, treatedAsNonterminals: [])
        return parser.parse()
    }
    
}
