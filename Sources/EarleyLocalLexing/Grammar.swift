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

/// Hosts the associated types `Param` amd `Result` which are needed throughout the grammar specification.
public protocol GrammarComponent {
    
    /// Symbols have parameters of this type associated with them. Nonterminals and terminals have input and output parameters, characters just output parameters.
    associatedtype Param : Hashable
    
    /// For a successful parse a result of this type is computed, as specified per `ConstructResult`.
    associatedtype Result

}

public protocol Lexer : GrammarComponent {
        
    func parse<I : Input>(input : I, position : Int, key : TerminalKey<Param>) -> Set<TokenResult<Param, Result>>

}

public typealias Tokens<Param : Hashable, Result> = [TerminalKey<Param> : Set<TokenResult<Param, Result>>]

public protocol Selector : GrammarComponent {
    
    func select(from tokens : Tokens<Param, Result>) -> Tokens<Param, Result>
    
}

/**
 A `Grammar` describes the syntax of the language to be parsed. Parsing is based on the concept of [*parameterized local lexing*](https://arxiv.org/abs/1704.04215).
 
 A `Grammar` consists of a list of *rules*, a *lexer*, a *selector*, and a specification of how to construct the result of a successful parse.
 
 -  The `Rule`s basically describe a context-free grammar whose *nonterminals* and *terminals* are parameterized by an input and an output parameter, each of type `Grammar.Param`.
    The computation of these parameters is guided via *evaluation functions* of type `EvalFunc`.
    Note that although context-free grammars require the symbol on the left hand side of a rule to be a nonterminal, here we also allow it to be a terminal instead.
 -  The `Lexer` component makes it possible to associate each terminal with a custom parser. These associations are optional, as the syntax of terminals can also be described via rules.
 -  The `Selector` component makes it possible to resolve undesired ambiguities arising between terminals starting at the same position, while also allowing to keep desired or unproblematic ambiguities.
 -  The `ConstructResult` component is a specification of how to construct the `Grammar.Result` of a successful parse.
 
 Given a list of `rules`, a `lexer`, a `selector` and result construction specification `constructResult`, you create a `grammar` via
 
 ```
 let grammar = Grammar(rules: rules, lexer: lexer, selector: selector, constructResult: constructResult)
 ```
 
 You can then use it for parsing:
 
 ```
 let parseResult = grammar.parse(input: input, position: 0, symbol: S, inputParam: param)
 ```

 Here we parse the symbol `S` with input parameter `param` from the beginning of the input source `input` of type `Input`. Note that `S` can be **either** a nonterminal or a terminal.
 See the description of `ParseResult` on how to interpret `parseResult`.
 */
public final class Grammar<L : Lexer, S : Selector, C : ConstructResult> : GrammarComponent where L.Param == C.Param, L.Result == C.Result, S.Param == C.Param, S.Result == C.Result {
        
    public typealias Param = C.Param
    
    public typealias Result = C.Result
    
    public typealias RuleIndex = Int

    public let rules : [Rule<Param>]
    
    public let lexer : L
    
    public let selector : S
    
    private let rulesOfSymbols : [Symbol : [RuleIndex]]
    
    public let constructResult : C
    
    public func rulesOf(symbol : Symbol) -> [RuleIndex] {
        return rulesOfSymbols[symbol] ?? []
    }
    
    /// Creates a grammar with the given rules, lexer, selector and result construction specification.
    public init(rules : [Rule<Param>], lexer : L, selector : S, constructResult : C) {
        self.rules = rules
        self.lexer = lexer
        self.selector = selector
        self.constructResult = constructResult
        var rOf : [Symbol : [RuleIndex]] = [:]
        for (ruleIndex, rule) in rules.enumerated() {
            precondition(rule.ruleIndex == ruleIndex)
            appendTo(dict: &rOf, key: rule.lhs, value: ruleIndex)
        }
        self.rulesOfSymbols = rOf
    }
        
    /// Parses the given `symbol` associated with input parameter `inputParam` from a specified `position` in `input`.
    /// - parameter input: The input which is being parsed.
    /// - parameter position: The position in the input from where to start parsing.
    /// - parameter symbol: The start symbol of the parsing process. This can be either a terminal or a nonterminal (but not a character).
    /// - parameter inputParam: The input parameter associated with the start symbol.
    /// - returns: The parse result (see `ParseResult` for a description on how to interpret this).
    public func parse<I : Input>(input : I, position : Int, symbol : Symbol, inputParam : Param) -> ParseResult<Param, Result> where I.Char == Param {
        let parser = EarleyParser(grammar: self, initialSymbol: symbol, initialParam: inputParam, input: input, startPosition: position, treatedAsNonterminals: [])
        return parser.parse()
    }
    
}
