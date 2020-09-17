/// Information about the right-hand side of a rule that has successfully completed parsing. This information is used when constructing the result of a successful parse.
/// - seealso: ConstructResult
public protocol CompletedRightHandSide : GrammarComponent {
    
    /// The index of the rule in `Grammar.rules`.
    var ruleIndex : RuleIndex { get }
    
    /// The number of symbols on the right-hand side of the rule.
    var count : Int { get }
        
    /// Returns information about the parse of the `k`-th symbol on the right-hand side of the rule.
    /// - parameter k: For a rule of the form `L => R1 ... Rn`, the information returned is about `Rk`.
    /// - returns: Information about the parse of the `k`-th symbol `Rk` on the right hand side of the rule.
    ///     - `inputParam`: The input parameter of `Rk`.
    ///     - `outputParam`: The output parameter of `Rk`
    ///     - `result`: An optional result of parsing `Rk`. Note that it is perfectly legal for a successful parse to return `nil` as its result.
    ///     - `startPosition`: The (inclusive) position of the input where the successful parse started.
    ///     - `endPosition`: The (exclusive) position of the input where the successful parse ended.
    func rhs(_ k : Int) -> (inputParam: Param, outputParam: Param, result: Result?, startPosition: Int, endPosition: Int)
}

/// An `ItemKey` designates a part of the input that has been successfully parsed as a certain symbol with certain parameters.
/// - seealso: ConstructResult
public struct ItemKey<Param : Hashable> : Hashable {
    
    /// The symbol which has been parsed successfully.
    public let symbol : Symbol
    
    /// The input parameter of the parsed symbol.
    public let inputParam : Param
    
    /// The output parameter of the parsed symbol.
    public let outputParam : Param
    
    /// The (inclusive) start position of the input range that has been parsed successfully.
    public let startPosition : Int
    
    /// The (exclusive) end position of the input range that has been parsed successfully.
    public let endPosition : Int

}

/// A `ConstructResult` is a specification for how to compute the result of a successful parse.
public protocol ConstructResult : GrammarComponent {
    
    /// The type of characters of the input being parsed.
    associatedtype Char
            
    /// Constructs the result of a successful invocation of a parse rule.
    /// - parameter input: The input, part of which has been successfully parsed.
    /// - parameter key: This key designates which part of the input has been parsed as what symbol.
    /// - parameter completed: Information about the completed right-hand side of the rule.
    /// - returns: An optional result. Note that it is perfectly legal to return `nil` here.
    func evalRule<RHS : CompletedRightHandSide>(input : Input<Char>, key : ItemKey<Param>, completed : RHS) -> Result? where RHS.Result == Result, RHS.Param == Param
    
    /// Constructs the result from a terminal result.
    /// - parameter key: The key for which this terminal has been parsed successfully.
    /// - parameter result: The result of parsing / lexing the terminal.
    /// - returns: An optional result. Note that it is perfectly legal to return `nil` here.
    func terminal(key : ItemKey<Param>, result : Result?) -> Result?
    
    /// This is called to merge all results for that particular `key` into a single result.
    /// - parameter key: The key for which parsing has completed successfully.
    /// - parameter results: The results of all successful parses for the particular `key` under consideration. If all such parses have returned a `nil` result, then `results` will be empty.
    /// - returns: An optional result that represents the merge of `results`. Note that it is perfectly legal to return `nil` here.
    func merge(key : ItemKey<Param>, results : [Result]) -> Result?
    
    /// This is called when the result construction depends on itself and is therefore failing.
    /// - parameter key: The key for which constructing the parsing result fails
    /// - returns: An optional result to bail the parser out of this situation
    func bailout(key : ItemKey<Param>) -> Result?
    
}
