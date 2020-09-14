struct EarleyItem<Param : Hashable, Result> : Hashable {
    
    let ruleIndex : Int
    
    let env : EvalEnv
    
    let values : [Param]
    
    /// Stores the results of terminal symbols. Results of nonterminals are not stored here, but computed later.
    let results : [Result?]
    
    let indices : [Int]
    
    var param : Param {
        return values[0]
    }
    
    var nextParam : Param {
        return values.last!
    }
    
    var out : Param {
        return values.last!
    }
    
    var origin : Int {
        return indices[0]
    }
    
    var dot : Int {
        return indices.count - 1
    }
    
    func child(rhs : Int) -> (inputParam: Param, outputParam: Param, result: Result?, from: Int, to: Int) {
        return (inputParam: values[2*rhs+1], outputParam: values[2*rhs+2], result: results[rhs], from: indices[rhs], to: indices[rhs+1])
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ruleIndex)
        hasher.combine(values)
        hasher.combine(indices)
    }
        
    static func == (left : EarleyItem<Param, Result>, right : EarleyItem<Param, Result>) -> Bool {
        return left.ruleIndex == right.ruleIndex && left.values == right.values && left.indices == right.indices
    }
}

typealias EarleyBin<Param : Hashable, Result> = Set<EarleyItem<Param, Result>>

public enum TerminalParseMode<Param> {
    case longestMatch
    case andNext
    case notNext(param : Param)
}

final class EarleyParser<L : Lexer, S : Selector, C : ConstructResult> where L.Char == C.Char, L.Param == C.Param, L.Result == C.Result, S.Param == C.Param, S.Result == C.Result {
    
    typealias Param = C.Param
    typealias Bin = EarleyBin<Param, C.Result>
    typealias Bins = [Bin]
    typealias G = Grammar<L, S, C>
    typealias TerminalSet = Set<Int>
    typealias TerminalParseModes = [Int : TerminalParseMode<Param>]
    typealias Item = EarleyItem<Param, C.Result>
    typealias Tokens = EarleyLocalLexing.Tokens<Param, C.Result>
            
    let grammar : G
    let initialSymbol : Symbol
    let initialParam : Param
    let input : Input<L.Char>
    let treatedAsNonterminals : TerminalSet
    let terminalParseModes : G.TerminalParseModes
    let startPosition : Int
    let semantics : G.Semantics
    
    init(grammar : G, initialSymbol : Symbol, initialParam : Param, input : Input<L.Char>, startPosition : Int, semantics : G.Semantics) {
        self.grammar = grammar
        self.initialSymbol = initialSymbol
        self.initialParam = initialParam
        self.input = input
        self.startPosition = startPosition
        switch initialSymbol {
        case let .terminal(index: index):
            self.treatedAsNonterminals = [index]
        default:
            self.treatedAsNonterminals = []
        }
        self.semantics = semantics
        self.terminalParseModes = grammar.terminalParseModes
    }
    
    func InitialBin() -> Bin {
        var bin : Bin = []
        for ruleIndex in grammar.rulesOf(lhs: initialSymbol) {
            let rule = grammar.rules[ruleIndex]
            if let item : EarleyItem<Param, C.Result> = rule.initialItem(ruleIndex: ruleIndex, k: startPosition, param: initialParam) {
                bin.insert(item)
            }
        }
        return bin
    }
    
    func treatAsNonterminal(_ symbol : Symbol) -> Bool {
        switch symbol {
        case .nonterminal: return true
        case let .terminal(index: index): return treatedAsNonterminals.contains(index)
        }
    }
    
    func Predict(bins : inout Bins, k : Int) -> Bool {
        var changed = false
        for item in bins[k - startPosition] {
            let rule = grammar.rules[item.ruleIndex]
            if
                let nextSymbol = rule.nextSymbol(dot: item.dot),
                treatAsNonterminal(nextSymbol)
            {
                let param = item.nextParam
                for ruleIndex in grammar.rulesOf(lhs: nextSymbol) {
                    let rule = grammar.rules[ruleIndex]
                    if let item : EarleyItem<Param, C.Result> = rule.initialItem(ruleIndex: ruleIndex, k: k, param: param) {
                        if bins[k - startPosition].insert(item).inserted {
                            changed = true
                        }
                    }
                }
            }
        }
        return changed
    }
    
    func Complete(bins : inout Bins, k : Int) -> Bool {
        var changed = false
        for item in bins[k - startPosition] {
            let rule = grammar.rules[item.ruleIndex]
            guard rule.nextSymbol(dot: item.dot) == nil else { continue }
            let nextSymbol = rule.lhs
            let param = item.param
            let result = item.out
            for srcItem in bins[item.origin - startPosition] {
                let srcItemRule = grammar.rules[srcItem.ruleIndex]
                if srcItemRule.nextSymbol(dot: srcItem.dot) == nextSymbol && srcItem.nextParam == param {
                    if let item = srcItemRule.nextItem(item: srcItem, k: k, value: result, result: nil) {
                        if bins[k - startPosition].insert(item).inserted {
                            changed = true
                        }
                    }
                }
            }
        }
        return changed
    }
    
    func CollectNewTokens(bins : Bins, tokens : Tokens, k : Int) -> Tokens {
        var tokenCandidates : Set<TerminalKey<Param>> = []
        for item in bins[k - startPosition] {
            let rule = grammar.rules[item.ruleIndex]
            if let nextSymbol = rule.nextSymbol(dot: item.dot) {
                switch nextSymbol {
                case let .terminal(index: index) where !treatAsNonterminal(nextSymbol):
                    let candidate = TerminalKey(terminalIndex: index, inputParam: item.nextParam)
                    if tokens[candidate] == nil {
                        tokenCandidates.insert(candidate)
                    }
                default: break
                }
            }
        }
        guard !tokenCandidates.isEmpty else { return [:] }
        var newTokens : Tokens = [:]
        for candidate in tokenCandidates {
            let candidateSymbol : Symbol = .terminal(index: candidate.terminalIndex)
            let parser = EarleyParser(grammar: grammar,
                                      initialSymbol: candidateSymbol,
                                      initialParam: candidate.inputParam,
                                      input: input,
                                      startPosition: k,
                                      semantics: semantics)
            switch parser.parse() {
            case .failed:
                switch terminalParseModes[candidate.terminalIndex] ?? .longestMatch {
                case let .notNext(param: param):
                    let result = grammar.constructResult.terminal(key: .init(symbol: candidateSymbol, inputParam: candidate.inputParam, outputParam: param, startPosition: k, endPosition: k), result: nil)
                    let tr = Token(length: 0, outputParam: param, result: result)
                    insertTo(dict: &newTokens, key: candidate, value: tr)
                case .andNext, .longestMatch: break
                }
            case let .success(length: length, results: results):
                switch terminalParseModes[candidate.terminalIndex] ?? .longestMatch {
                case .andNext:
                    for (value, result) in results {
                        let tr = Token(length: 0, outputParam: value, result: result)
                        insertTo(dict: &newTokens, key: candidate, value: tr)
                    }
                case .longestMatch:
                    for (value, result) in results {
                        let tr = Token(length: length, outputParam: value, result: result)
                        insertTo(dict: &newTokens, key: candidate, value: tr)
                    }
                case .notNext:
                    break
                }
            }
            for tr in grammar.lexer.parse(input: input, position: k, key: candidate) {
                insertTo(dict: &newTokens, key: candidate, value: tr)
            }
        }
        return newTokens
    }
    
    func selectNewTokens_paper(bins : Bins, tokens : inout Tokens, newTokens : Tokens, k : Int) {
        guard !newTokens.isEmpty else { return }
        let selectedTokens = grammar.selector.select(from: newTokens, alreadySelected: tokens)
        insertTo(dict: &tokens, selectedTokens)
    }

    func selectNewTokens_modified(bins : Bins, tokens : inout Tokens, newTokens : Tokens, k : Int) {
        guard !newTokens.isEmpty else { return }
        var validNewTokens : Tokens = [:]
        for item in bins[k - startPosition] {
            let rule = grammar.rules[item.ruleIndex]
            if let nextSymbol = rule.nextSymbol(dot: item.dot) {
                switch nextSymbol {
                case let .terminal(index: index) where !treatAsNonterminal(nextSymbol):
                    let candidate = TerminalKey(terminalIndex: index, inputParam: item.nextParam)
                    if let results = newTokens[candidate] {
                        for result in results {
                            if rule.hasNextItem(item: item, value: result.outputParam) {
                                insertTo(dict: &validNewTokens, key: candidate, value: result)
                            }
                        }
                    }
                default: break
                }
            }
        }
        let selectedTokens = grammar.selector.select(from: validNewTokens, alreadySelected: tokens)
        insertTo(dict: &tokens, selectedTokens)
    }
    
    func add(bins : inout Bins, k : Int, item : Item) -> Bool {
        let i = k - startPosition
        while bins.count <= i {
            bins.append(Bin())
        }
        return bins[i].insert(item).inserted
    }
    
    func Scan(bins : inout Bins, tokens : Tokens, k : Int) -> Bool {
        var changed = false
        for item in bins[k - startPosition] {
            let rule = grammar.rules[item.ruleIndex]
            if let nextSymbol = rule.nextSymbol(dot: item.dot) {
                switch nextSymbol {
                case let .terminal(index: index) where !treatAsNonterminal(nextSymbol):
                    let candidate = TerminalKey(terminalIndex: index, inputParam: item.nextParam)
                    if let results = tokens[candidate] {
                        for result in results {
                            let l = k + result.length
                            if let nextItem = rule.nextItem(item: item, k: l , value: result.outputParam, result: result.result) {
                                if add(bins: &bins, k: l, item: nextItem) {
                                    changed = true
                                }
                            }
                        }
                    }
                default:
                    break
                }
            }
        }
        return changed
    }
    
    func Pi(bins : inout Bins, tokens : Tokens, k : Int) -> Bool {
        var changeInStep : Bool
        var changed = false
        repeat {
            changeInStep = false
            if Predict(bins: &bins, k: k) { changeInStep = true }
            if Complete(bins: &bins, k: k) { changeInStep = true }
            if Scan(bins: &bins, tokens: tokens, k: k) { changeInStep = true }
            if changeInStep { changed = true }
        } while changeInStep
        return changed
    }
    
    func computeBin(bins : inout Bins, k : Int) {
        var tokens : Tokens = [:]
        var first : Bool = true
        while first || Pi(bins: &bins, tokens: tokens, k: k) {
            first = false
            let newTokens = CollectNewTokens(bins: bins, tokens: tokens, k: k)
            switch semantics {
            case .paper: selectNewTokens_paper(bins: bins, tokens: &tokens, newTokens: newTokens, k: k)
            case .modified: selectNewTokens_modified(bins: bins, tokens: &tokens, newTokens: newTokens, k: k)
            }
        }
    }
        
    func hasBeenRecognized(bin : Bin) -> Bool {
        for item in bin {
            if item.origin == startPosition {
                let rule = grammar.rules[item.ruleIndex]
                if rule.lhs == initialSymbol && rule.nextSymbol(dot: item.dot) == nil && item.param == initialParam {
                    return true
                }
            }
        }
        return false
    }
    
    func parse() -> ParseResult<Param, C.Result> {
        var bins : Bins = []
        bins.append(InitialBin())
        var i = 0
        while i < bins.count {
            computeBin(bins: &bins, k: i + startPosition)
            i += 1
        }
        i = bins.count - 1
        var lastNonEmpty : Int? = nil
        while i >= 0 {
            if hasBeenRecognized(bin: bins[i]) {
                let c = RunResultConstruction<L, S, C>(input: input, grammar: grammar, treatedAsNonterminals: treatedAsNonterminals, bins: Array(bins[0 ... i]), startOffset: startPosition)
                return .success(length: i, results: c.construct(symbol: initialSymbol, param: initialParam))
            }
            if lastNonEmpty == nil && !bins[i].isEmpty {
                lastNonEmpty = i + startPosition
            }
            i -= 1
        }
        return .failed(position: lastNonEmpty ?? startPosition)
    }
    
}
