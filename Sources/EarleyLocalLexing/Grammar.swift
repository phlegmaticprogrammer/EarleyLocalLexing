import Foundation

/// An environment which an `EvalFunc` can use to store information needed during evaluation.
public protocol EvalEnv {
    
    /// Makes a copy of this environment.
    /// - returns: An identical copy of `self` such that subsequent modifications of the copy or `self` do no affect each other.
    ///   If no corresponding `EvalFunc` modifies this environment or its copy, then this method can just return `self`.
    func copy() -> Self

}

/// A function which is used to compute the parameters of the involved symbols during the parsing progress of an invocation of a rule.
///
/// Assume that the rule has the form
/// ```
/// L => R1 R2 ... Rn
/// ```
/// Then the function will be called at a certain *stage* `k`, where `k` is the number of symbols
/// `R1` ... `Rk` whose parameters have already been computed during previous stages.
/// - parameter env: An environment which a function can use to store information in between calls to it during the parsing progress of the rule as it progresses from stage to stage. The environment is a copy of an environment used during the previous stage.
/// - parameter k: The current stage, where `0 <= k <= n`, and `n` is the number of symbols on the right hand side of the rule.
/// - parameter params: The parameters that have been evaluated so far.
///   We have `params.count == 1 + 2 * k` and the following layout:
///   - `params[0]`: the input parameter of `L`
///   - `params[1]`: the input parameter of `R1`
///   - `params[2]`: the output parameter of `R1`
///   - `params[3]`: the input parameter of `R2`
///   - `params[4]`: the output parameter of `R2`
///   - ...
///   - `params[2*k-1]`: the input parameter of `Rk`
///   - `params[2*k]`: the output parameter of `Rk`
/// - returns: For `k < n` this returns the input parameter of `R(k+1)`. For `k == n` this returns the output parameter of `L`. In case of a return value of `nil`, the parsing at this particular stage is aborted.
/// - seealso: `Rule`
public typealias EvalFunc<Param> = (_ env: EvalEnv,  _ k: Int, _ params: [Param]) -> Param?

/// A `Symbol` denotes either a terminal or a nonterminal.
public enum Symbol : Hashable, CustomStringConvertible {
    
    /// A terminal symbol.
    case terminal(index : Int)
    
    /// A nonterminal symbol.
    case nonterminal(index : Int)
    
    public var description : String {
        switch self {
        case let .terminal(index: index): return "T\(index)"
        case let .nonterminal(index: index): return "N\(index)"
        }
    }

}

/// Represents a rule of the grammar.
///
/// A rule is similar to a rule in a context-free grammar, and has the form
/// ```
/// L => R1 ... Rn
/// ```
/// where `L` is the left-hand side of the rule, and `R1 ... Rn` is the right-hand side of the rule.
///
/// Unlike the rules of a context-free grammar though, each of the symbols `L`, `R1`, ..., `Rn` carries an input and an output parameter with them.
/// The property `eval` (in tandem with the property `initialEnv`) is responsible for computing these parameters along the stages of the parsing process.
///
/// Furthermore, the symbol `L` does not have to be a nonterminal, but can also be a terminal symbol. In this case, the invocation of this rule during parsing spawns a separate
/// parsing process with a grammar identical with the current grammar, except that `L` is now treated as a nonterminal symbol. This enables *scannerless parsing*.
///
/// - seealso: Grammar
/// - seealso: EvalFunc
public struct Rule<Param> {

    /// The left-hand side `L` of a rule of the form `L => R1 ... Rn`.
    public let lhs : Symbol

    /// The right-hand side `[R1 ... Rn]` of a rule of the form `L => R1 ... Rn`
    public let rhs : [Symbol]

    /// The initial environment (actually a copy of it) is  passed to `eval` at stage 0.
    /// - seealso: EvalFunc
    public let initialEnv : EvalEnv

    /// The evaluation function responsible for this rule.
    public let eval : EvalFunc<Param>
    
    /// Creates a rule.
    /// - parameter lhs: The left-hand side `L` of the rule.
    /// - parameter rhs: The right-hand side `R1 ... Rn` of the rule.
    /// - parameter initialEnv: The initial environment of the rule.
    /// - parameter eval: The evaluation function of the rule.
    public init(lhs : Symbol, rhs : [Symbol], initialEnv : EvalEnv, eval : @escaping EvalFunc<Param>) {
        self.initialEnv = initialEnv
        self.lhs = lhs
        self.rhs = rhs
        self.eval = eval
    }
    
    func nextSymbol(dot : Int) -> Symbol? {
        if dot >= rhs.count { return nil }
        else { return rhs[dot] }
    }
        
    func initialItem<Result>(ruleIndex: Int, k : Int, param : Param) -> EarleyItem<Param, Result>? {
        let env = initialEnv.copy()
        if let value = eval(env, 0, [param]) {
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
        let nextDot = item.dot + 1
        if let value = eval(env, nextDot, values) {
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
    
    associatedtype Char
        
    func parse<I : Input>(input : I, position : Int, key : TerminalKey<Param>) -> Set<TokenResult<Param, Result>> where I.Char == Char

}

public typealias Tokens<Param : Hashable, Result> = [TerminalKey<Param> : Set<TokenResult<Param, Result>>]

public protocol Selector : GrammarComponent {
    
    func select(from : Tokens<Param, Result>, alreadySelected : Tokens<Param, Result>) -> Tokens<Param, Result>
    
}

/**
 A `Grammar` describes the syntax of the language to be parsed. Parsing is based on the concept of [*parameterized local lexing*](https://arxiv.org/abs/1704.04215).
 
 A `Grammar` consists of a list of *rules*, a *lexer*, a *selector*, and a specification of how to construct the result of a successful parse.
 
 -  The `Rule`s basically describe a context-free grammar whose *nonterminals* and *terminals* are parameterized by an input and an output parameter, each of type `Grammar.Param`.
    The computation of these parameters is guided via *evaluation functions* of type `EvalFunc`.
    Note that although context-free grammars require the symbol on the left hand side of a rule to be a nonterminal, here we also allow it to be a terminal instead.
 -  The `Lexer` component makes it possible to associate a terminal with a custom parser. Note that the syntax of terminals can not only be described via this lexer, but can also be described via rules.
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
 */
public final class Grammar<L : Lexer, S : Selector, C : ConstructResult> : GrammarComponent where L.Char == C.Char, L.Param == C.Param, L.Result == C.Result, S.Param == C.Param, S.Result == C.Result {
        
    public typealias Param = C.Param
    
    public typealias Result = C.Result
    
    public typealias RuleIndex = Int
    
    public typealias Char = L.Char

    public let rules : [Rule<Param>]
    
    public let lexer : L
    
    public let selector : S
    
    private let rulesOfSymbols : [Symbol : [RuleIndex]]
    
    public let constructResult : C
    
    public func rulesOf(symbol : Symbol) -> [RuleIndex] {
        return rulesOfSymbols[symbol] ?? []
    }
    
    /// Creates a grammar with the given rules, lexer, selector and result construction specification.
    /// - parameter rules: The rules of the grammar.
    /// - parameter lexer: The lexer of this grammar.
    /// - parameter selector: The selector of this grammar.
    /// - parameter constructResult: A specification of how to construct the result of a successful parse.
    public init(rules : [Rule<Param>], lexer : L, selector : S, constructResult : C) {
        self.rules = rules
        self.lexer = lexer
        self.selector = selector
        self.constructResult = constructResult
        var rOf : [Symbol : [RuleIndex]] = [:]
        for (ruleIndex, rule) in rules.enumerated() {
            appendTo(dict: &rOf, key: rule.lhs, value: ruleIndex)
        }
        self.rulesOfSymbols = rOf
    }
        
    /// Parses the given `symbol` associated with input parameter `inputParam` from a specified `position` in `input`.
    /// - parameter input: The input which is being parsed.
    /// - parameter position: The position in the input from where to start parsing.
    /// - parameter symbol: The start symbol of the parsing process. This can be either a nonterminal or a terminal.
    /// - parameter inputParam: The input parameter associated with the start symbol.
    /// - returns: The parse result (see `ParseResult` for a description on how to interpret this).
    public func parse<I : Input>(input : I, position : Int, symbol : Symbol, inputParam : Param) -> ParseResult<Param, Result> where I.Char == L.Char {
        let parser = EarleyParser(grammar: self, initialSymbol: symbol, initialParam: inputParam, input: input, startPosition: position, treatedAsNonterminals: [])
        return parser.parse()
    }
    
}
