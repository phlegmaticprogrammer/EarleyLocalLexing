import Foundation

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

final class EarleyParser<L : Lexer, S : Selector, C : ConstructResult> where L.Char == C.Char, L.Param == C.Param, L.Result == C.Result, S.Param == C.Param, S.Result == C.Result {
    
    typealias Param = C.Param
    typealias Bin = EarleyBin<Param, C.Result>
    typealias Bins = [Bin]
    typealias G = Grammar<L, S, C>
    typealias Item = EarleyItem<Param, C.Result>
    typealias Tokens = EarleyLocalLexing.Tokens<Param, C.Result>
            
    let grammar : G
    let initialSymbol : Symbol
    let initialParam : Param
    let input : Input<L.Char>
    let startPosition : Int
    
    init(grammar : G, initialSymbol : Symbol, initialParam : Param, input : Input<L.Char>, startPosition : Int) {
        self.grammar = grammar
        self.initialSymbol = initialSymbol
        self.initialParam = initialParam
        self.input = input
        self.startPosition = startPosition
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
        case .terminal: return false
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
    
    func CollectNewTokens(level: Int, bins : Bins, tokens : Tokens, k : Int) -> Tokens {
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
            for tr in grammar.lexer.parse(input: input, position: k, key: candidate) {
                insertTo(dict: &newTokens, key: candidate, value: tr)
            }
        }
        return newTokens
    }
    
    func filterNewTokens(bins : Bins, newTokens : Tokens, k : Int) -> Tokens {
        guard !newTokens.isEmpty else { return newTokens }
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
        return validNewTokens
    }
    
    func filterEmptyTokens(_ tokens : Tokens) -> Tokens {
        var result : Tokens = [:]
        for (k, t) in tokens {
            let filtered = Set(t.filter { token in token.length == 0})
            if !filtered.isEmpty {
                result[k] = filtered
            }
        }
        return result
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
    
    func printTokens(_ tokens : Tokens) -> String {
        guard tokens.count > 0 else { return "none" }
        var s = ""
        for (t, r) in tokens {
            let len = r.first!.length
            s.append(" \(t.terminalIndex)[\(len)]")
        }
        return s
    }
    
    func computeBin(level : Int, bins : inout Bins, k : Int) {
        var tokens : Tokens = [:]
        var alreadySelected : Tokens = [:]
        var first : Bool = true
        let selector = grammar.selector
        while first || Pi(bins: &bins, tokens: alreadySelected, k: k) {
            first = false
            let newTokens = filterNewTokens(bins: bins, newTokens: CollectNewTokens(level: level, bins: bins, tokens: tokens, k: k), k: k)
            insertTo(dict: &tokens, newTokens)
            alreadySelected = filterEmptyTokens(selector.select(from: tokens, alreadySelected: alreadySelected))
        }
        let selected = selector.select(from: tokens, alreadySelected: alreadySelected)
        let _ = Scan(bins: &bins, tokens: selected, k: k)
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
    
    func parse(level : Int = 0) -> ParseResult<Param, C.Result> {
        var bins : Bins = []
        bins.append(InitialBin())
        //let startDate = Date()
        var i = 0
        while i < bins.count {
            //let before = Date()
            computeBin(level: level, bins: &bins, k: i + startPosition)
            /*let after = Date()
            let diff = after.timeIntervalSince(before)
            if level == 0 {
                if bins[i].count > 0 {
                    print("computed bin \(i + startPosition) with \(bins[i].count) elements in \(diff * 1000)ms")
                }
            }*/
            i += 1
        }
        i = bins.count - 1
        var lastNonEmpty : Int? = nil
        //let endDate = Date()
        //let timeInterval = endDate.timeIntervalSince(startDate)
        /*if timeInterval*1000 > 10 {
            let offset = String(repeating: " ", count: level * 2)
            print("\(offset)parsed symbol \(grammar.constructResult.nameOf(symbol: initialSymbol)) in \(timeInterval * 1000)ms")
        }*/
        while i >= 0 {
            if hasBeenRecognized(bin: bins[i]) {
                let c = RunResultConstruction<L, S, C>(input: input, grammar: grammar, bins: Array(bins[0 ... i]), startOffset: startPosition)
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
