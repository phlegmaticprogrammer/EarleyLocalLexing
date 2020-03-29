import Foundation

struct EarleyItem<Env : EvalEnv, Value : Hashable, Result> : Hashable, CompletedItem {
    let ruleIndex : Int
    let env : Env
    let values : [Value]
    let results : [Result?]
    let indices : [Int]
    
    var param : Value {
        return values[0]
    }
    
    var nextParam : Value {
        return values.last!
    }
    
    var out : Value {
        return values.last!
    }
    
    var origin : Int {
        return indices[0]
    }
    
    var dot : Int {
        return indices.count - 1
    }
    
    func child(rhs : Int) -> (in: Value, out: Value, result: Result?, from: Int, to: Int) {
        return (in: values[2*rhs+1], out: values[2*rhs+2], result: results[rhs], from: indices[rhs], to: indices[rhs+1])
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(ruleIndex)
        hasher.combine(values)
        hasher.combine(indices)
    }
        
    static func == (left : EarleyItem<Env, Value, Result>, right : EarleyItem<Env, Value, Result>) -> Bool {
        return left.ruleIndex == right.ruleIndex && left.values == right.values && left.indices == right.indices
    }
}

typealias EarleyBin<Env : EvalEnv, Value : Hashable, Result> = Set<EarleyItem<Env, Value, Result>>


public final class EarleyParser<C : ConstructResult, Env : EvalEnv, In : Input> where In.Char == C.Value {
    
    public typealias Value = C.Value
    //typealias Env = C.Env
    typealias Bin = EarleyBin<Env, Value, C.Result>
    typealias Bins = [Bin]
    public typealias G = Grammar<C, Env>
    public typealias TerminalSet = Set<G.TerminalIndex>
    typealias Tokens = G.Tokens
    typealias Item = G.Item
    typealias TerminalKey = G.TerminalKey
    
    enum RecognitionResult {
        case failed(position : Int)
        case success(bins : [Bin], results : Set<Value>)
    }
    
    public enum ParseResult {
        case failed(position : Int)
        case success(length : Int, results : [Value : C.Result?])
    }
    
    let grammar : G
    let initialSymbol : Symbol
    let initialParam : Value
    let input : In
    let treatedAsNonterminals : TerminalSet
    let startPosition : Int
    
    public init(grammar : G, initialSymbol : Symbol, initialParam : Value, input : In, startPosition : Int, treatedAsNonterminals : TerminalSet) {
        self.grammar = grammar
        self.initialSymbol = initialSymbol
        self.initialParam = initialParam
        self.input = input
        self.startPosition = startPosition
        switch initialSymbol {
        case let .terminal(index: index):
            self.treatedAsNonterminals = treatedAsNonterminals.union([index])
        default:
            self.treatedAsNonterminals = treatedAsNonterminals
        }
    }
    
    func InitialBin() -> Bin {
        var bin : Bin = []
        for ruleIndex in grammar.rulesOf(symbol: initialSymbol) {
            let rule = grammar.rules[ruleIndex]
            if let item = rule.initialItem(k: startPosition, param: initialParam) {
                bin.insert(item)
            }
        }
        return bin
    }
    
    func treatAsNonterminal(_ symbol : Symbol) -> Bool {
        switch symbol {
        case .character: return false
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
                for ruleIndex in grammar.rulesOf(symbol: nextSymbol) {
                    let rule = grammar.rules[ruleIndex]
                    if let item = rule.initialItem(k: k, param: param) {
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
    
    func CollectTokens(bins : Bins, tokens : inout Tokens, k : Int) {
        var tokenCandidates : Set<TerminalKey> = []
        for item in bins[k - startPosition] {
            let rule = grammar.rules[item.ruleIndex]
            if let nextSymbol = rule.nextSymbol(dot: item.dot) {
                switch nextSymbol {
                case let .terminal(index: index) where !treatAsNonterminal(nextSymbol):
                    let candidate = TerminalKey(terminalIndex: index, value: item.nextParam)
                    if tokens[candidate] == nil {
                        tokenCandidates.insert(candidate)
                    }
                default: break
                }
            }
        }
        guard !tokenCandidates.isEmpty else { return }
        var newTokens : Tokens = [:]
        for candidate in tokenCandidates {
            let parser = EarleyParser(grammar: grammar,
                                      initialSymbol: .terminal(index: candidate.terminalIndex),
                                      initialParam: candidate.value,
                                      input: input,
                                      startPosition: k,
                                      treatedAsNonterminals: treatedAsNonterminals)
            switch parser.parse() {
            case .failed: break
            case let .success(length: length, results: results):
                for (value, result) in results {
                    let tr = G.TokenResult(length: length, value: value, result: result)
                    insertTo(dict: &newTokens, key: candidate, value: tr)
                }
            }
        }
        guard !newTokens.isEmpty else { return }
        insertTo(dict: &newTokens, tokens)
        let selectedTokens = grammar.selector(newTokens)
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
                    let candidate = TerminalKey(terminalIndex: index, value: item.nextParam)
                    if let results = tokens[candidate] {
                        for result in results {
                            let l = k + result.length
                            if let nextItem = rule.nextItem(item: item, k: l , value: result.value, result: result.result) {
                                if add(bins: &bins, k: l, item: nextItem) {
                                    changed = true
                                }
                            }
                        }
                    }
                case .character:
                    if let c = input[k] {
                        if let nextItem = rule.nextItem(item: item, k: k+1, value: c, result: nil) {
                            if add(bins: &bins, k: k+1, item: nextItem) {
                                changed = true
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
        repeat {
            CollectTokens(bins: bins, tokens: &tokens, k: k)
        } while Pi(bins: &bins, tokens: tokens, k: k)
    }
    
    func recognizedResults(bin : Bin) -> Set<Value> {
        var values : Set<Value> = []
        for item in bin {
            if item.origin == startPosition {
                let rule = grammar.rules[item.ruleIndex]
                if rule.lhs == initialSymbol && rule.nextSymbol(dot: item.dot) == nil && item.param == initialParam {
                    values.insert(item.out)
                }
            }
        }
        return values
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

    func recognize() -> RecognitionResult {
        var bins : Bins = []
        bins.append(InitialBin())
        var i = 0
        while i < bins.count {
            computeBin(bins: &bins, k: startPosition + i)
            i += 1
        }
        i = bins.count - 1
        var lastNonEmpty : Int? = nil
        while i >= 0 {
            let results = recognizedResults(bin: bins[i])
            if !results.isEmpty {
                return .success(bins: Array(bins[0 ... i]), results: results)
            }
            if lastNonEmpty == nil && !bins[i].isEmpty {
                lastNonEmpty = startPosition + i
            }
            i -= 1
        }
        return .failed(position: lastNonEmpty ?? startPosition)
    }
    
    public func parse() -> ParseResult {
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
                let c = RunResultConstruction<C, Env, In>(input: input, grammar: grammar, treatedAsNonterminals: treatedAsNonterminals, bins: Array(bins[0 ... i]), startOffset: startPosition)
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
