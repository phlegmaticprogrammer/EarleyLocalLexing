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
public enum Symbol : Hashable {
    
    /// A terminal symbol.
    case terminal(index : Int)
    
    /// A nonterminal symbol.
    case nonterminal(index : Int)

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
/// parsing process with a grammar identical with the current grammar, except that `L` is now treated as a nonterminal symbol. This enables a form of *scannerless parsing*.
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
    
    func hasNextItem<Result>(item : EarleyItem<Param, Result>, value : Param) -> Bool {
        var values = item.values
        values.append(value)
        let env = item.env.copy()
        let nextDot = item.dot + 1
        return eval(env, nextDot, values) != nil
    }
    
}

/// Abstracts the input source which is being parsed, and presents itself as a random access vector of characters of type `Char`.
open class Input<Char> {
    
    /// Empty initializer.
    public init() {}
    
    /// Accesses the character at the given position.
    /// - parameter position: The position of the character in the input.
    /// - returns: The character at the given `position`. If the position is outside the range of the input, in particular at the end of the input, `nil` is returned.
    open subscript (position : Int) -> Char? {
        fatalError("needs to be overriden in subclass")
    }
    
}

/// The result of parsing a particular symbol with a particular input parameter.
/// - seealso: `Grammar.parse(input:position:symbol:param:)`
public enum ParseResult<Param : Hashable, Result> {
    
    /// This denotes the case that parsing has failed at the given `position` in the input.
    case failed(position : Int)
    
    /// This denotes the case of a successful parse.
    /// - `length`: The number of characters in the input that the successful parse encompasses.
    /// - `results`: A dictionary mapping the output parameter of the successfully parsed symbol to an optional result.
    ///   This dictionary will contain at least one entry, and can contain multiple entries in case of an ambiguous parse.
    ///   If the dictionary contains only a single entry this does not necessarily imply that the parse has been unambiguous. This is because
    ///   ambiguity might have been subsumed into the optional result via `ConstructResult.merge(key:results:)`.
    case success(length : Int, results : [Param : Result?])

}

/// The result of parsing a terminal (either via a lexer or via rules).
public struct Token<Param : Hashable, Result> : Hashable {
    
    /// The number of characters in the input that this token encompasses.
    public let length : Int
    
    /// The output parameter associated with the parsed terminal.
    public let outputParam : Param
    
    /// An optional result computed for this terminal.
    public let result : Result?
    
    /// The default initializer.
    public init(length : Int, outputParam : Param, result : Result?) {
        self.length = length
        self.outputParam = outputParam
        self.result = result
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(length)
        hasher.combine(outputParam)
    }
    
    public static func == (left : Token<Param, Result>, right : Token<Param, Result>) -> Bool {
        return left.length == right.length && left.outputParam == right.outputParam
    }

}

/// A `TerminalKey` is used to distinguish which terminal and input parameter are under consideration.
public struct TerminalKey<Param : Hashable> : Hashable {
    
    /// Designates the terminal under consideration, which is `Symbol.terminal(index: terminalIndex)`.
    public let terminalIndex : Int
    
    /// The input parameter associated with the terminal under consideration.
    public let inputParam : Param
    
    /// The default initializer.
    public init(terminalIndex : Int, inputParam : Param) {
        self.terminalIndex = terminalIndex
        self.inputParam = inputParam
    }
}

/// Hosts the associated types `Param` amd `Result` which are needed throughout the grammar specification.
public protocol GrammarComponent {
    
    /// Each symbol has an input and an output parameter of this type associated with them.
    associatedtype Param : Hashable
    
    /// For a successful parse, optionally a result of this type is computed, as specified per `ConstructResult`.
    associatedtype Result

}

/// A `Lexer` manages the custom parsing of terminals.
///
/// Given a `position` in some `input`, and a given terminal with given associated input parameter, the lexer returns a set of tokens.
///
/// - note: Terminals can not only be parsed via the lexer, but also via rules, therefore enabling *scannerless parsing*.
///   In those cases the returned set of tokens will typically be empty, but does not have to be, thus making it possible to mix scannerless and scannerful parsing of terminals.
///   Nevertheless, even in a fully scannerless parser, there needs to be one terminal parsed via the lexer, representing a general character.
/// - seealso: `Rule`
public protocol Lexer : GrammarComponent {
    
    /// The type of character inputs processed by the lexer have.
    associatedtype Char
        
    /// Given a `position` in `input`, and a given terminal with given associated input parameter, the lexer returns a set of parsed tokens.
    /// - parameter input: The input providing the characters to parse.
    /// - parameter position: The position in the input from where to start parsing.
    /// - parameter key: The terminal key distinguishing the terminal with associated input parameter that is being parsed.
    /// - returns: A set of tokens, each token representing a successful parse. An empty set is returned in case of a failed parse.
    func parse(input : Input<Char>, position : Int, key : TerminalKey<Param>) -> Set<Token<Param, Result>>

}

/// Represents the result of parsing a set of terminals at the same position. Each terminal and associated input parameter under consideration is mapped to its set of successfully parsed tokens.
public typealias Tokens<Param : Hashable, Result> = [TerminalKey<Param> : Set<Token<Param, Result>>]

/// A `Selector` selects a subset of tokens from those tokens which have been successfully parsed at at particular position.
public protocol Selector : GrammarComponent {
    
    /// Selects a subset of tokens from those tokens which have been successfully parsed at a particular position.
    /// Selection happens in iterative phases, which correspond to a discovery process of which terminals could possibly occur at the current position based on the current parsing progress.
    /// Tokens already selected in previous phases cannot be deselected in later phases.
    /// - parameter from: Those tokens which have been newly parsed in the current selection phase.
    ///   The terminal keys in `from` are guaranteed to be different from those in `alreadySelected`.
    /// - parameter alreadySelected: The tokens which have been selected in earlier phases.
    /// - returns: The selected tokens, which must be contained in `from`.
    func select(from : Tokens<Param, Result>, alreadySelected : Tokens<Param, Result>) -> Tokens<Param, Result>
    
}

/// The index of a rule in the `Grammar.rules` array.
public typealias RuleIndex = Int

/**
 A `Grammar` describes the syntax of the language to be parsed. Parsing is based on the concept of [*parameterized local lexing*](https://arxiv.org/abs/1704.04215).
 
 A `Grammar` consists of a list of *rules*, a *lexer*, a *selector*, and a specification of how to construct the result of a successful parse.
 
 -  The `Rule`s basically describe a context-free grammar whose *nonterminals* and *terminals* are parameterized by an input and an output parameter, each of type `Grammar.Param`.
    The computation of these parameters is guided via *evaluation functions* of type `EvalFunc`.
    Note that although context-free grammars require the symbol on the left hand side of a rule to be a nonterminal, here we also allow it to be a terminal instead. This enables a form of *scannerless parsing*.
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
        
    /// Each nonterminal and terminal has an input and an output parameter of this type associated with them.
    public typealias Param = C.Param
    
    /// For a successful parse, optionally a result of this type is computed, as specified per `ConstructResult`.
    public typealias Result = C.Result
        
    /// The type of characters that inputs must have which can be parsed by this grammar.
    public typealias Char = L.Char

    /// The rules of this grammar.
    /// - seealso: `Rule`
    public let rules : [Rule<Param>]
    
    /// The lexer of this grammar.
    /// - seealso: `Lexer`
    public let lexer : L
    
    /// The selector of this grammar.
    /// - seealso: `Selector`
    public let selector : S
    
    private let rulesOfSymbols : [Symbol : [RuleIndex]]
    
    /// The specification on how to compute a result from a successful parse.
    /// - seealso: `ConstructResult`
    public let constructResult : C
    
    /// The rules of this grammar that have `lhs` as its left-hand side.
    /// - parameter lhs: The left-hand side symbol of rules queried.
    /// - returns: All rules `L => R1 ... Rn` such that `L == lhs`.
    public func rulesOf(lhs : Symbol) -> [RuleIndex] {
        return rulesOfSymbols[lhs] ?? []
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
    
    /// Designates two slightly different parsing semantics.
    public enum Semantics {
        
        /// Semantics as described in the paper *Parameterized Local Lexing*.
        case paper
        
        /// Experimental semantics that should lead to improved terminal selection.
        case modified
    }
        
    /// Parses the given `symbol` associated with input parameter `inputParam` from a specified `position` in `input`.
    /// - parameter input: The input which is being parsed.
    /// - parameter position: The position in the input from where to start parsing.
    /// - parameter symbol: The start symbol of the parsing process. This can be either a nonterminal or a terminal.
    /// - parameter param: The input parameter associated with the start symbol.
    /// - parameter terminalParseModes: The terminal modes for parsing terminals via the grammar (does not affect Lexer!)
    /// - parameter semantics: The parsing semantics.
    /// - returns: The parse result (see `ParseResult` for a description on how to interpret this).
    public func parse(input : Input<Char>, position : Int, symbol : Symbol, param : Param, terminalParseModes : [Int : TerminalParseMode<Param, Result>], semantics : Semantics = .paper) -> ParseResult<Param, Result> {
        let parser = EarleyParser(grammar: self, initialSymbol: symbol, initialParam: param, input: input, startPosition: position, terminalParseModes: terminalParseModes, semantics: semantics)
        return parser.parse()
    }
    
}
