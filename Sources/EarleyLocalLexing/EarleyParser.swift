//
//  EarleyParser.swift
//
//  Created by Steven Obua on 11/12/2019.
//

import Foundation

public protocol EarleyItemEnv {
    
    func copy() -> Self

}

public enum EarleyKernelSymbol : Hashable, CustomStringConvertible {
    
    case terminal(index : Int)
    case nonterminal(index : Int)
    case character
    
    public var description : String {
        switch self {
        case let .terminal(index: index): return "Terminal\(index)"
        case let .nonterminal(index: index): return "Nonterminal\(index)"
        case .character: return "Character"
        }
    }
}

public struct EarleyKey<Value : Hashable> : Hashable {
    
    public let symbol : EarleyKernelSymbol
    
    public let input : Value
    
    public let output : Value
    
    public let startPosition : Int
    
    public let endPosition : Int
}

public protocol CompletedItem {
    
    associatedtype Value
    
    associatedtype Result

    var ruleIndex : Int { get }
        
    func child(rhs : Int) -> (in: Value, out: Value, result: Result?, from: Int, to: Int)
}

struct EarleyItem<Env : EarleyItemEnv, Value : Hashable, Result> : Hashable, CompletedItem {
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

public protocol ConstructResult {
    
    associatedtype Env : EarleyItemEnv
    associatedtype Value : Hashable
    associatedtype Result
    associatedtype I : Input where I.Char == Value
    
    typealias Key = EarleyKey<Value>
    
    func evalRule<Item : CompletedItem>(input : I, key : Key, item : Item, rhs : @escaping (Int) -> Result?) -> Result? where Item.Result == Result, Item.Value == Value
    
    func evalTerminal(key : Key, result : Result?) -> Result?
    
    func evalCharacter(position : Int, value : Value) -> Result?
    
    func merge(key : Key, results : [Result]) -> Result?
    
}

typealias EarleyBin<Env : EarleyItemEnv, Value : Hashable, Result> = Set<EarleyItem<Env, Value, Result>>

public final class EarleyKernel<C : ConstructResult> {
    
    public typealias Value = C.Value
    public typealias Result = C.Result
    public typealias Env = C.Env
    public typealias Symbol = EarleyKernelSymbol
    public typealias F = (Env, [Value]) -> Value?
    
    typealias Item = EarleyItem<Env, Value, Result>
    
    public struct Rule {
        public let initialEnv : () -> Env
        public let lhs : Symbol
        public let rhs : [(F, Symbol)]
        public let out : F
        public let ruleIndex : Int
        
        public init(initialEnv : @escaping () -> Env, lhs : Symbol, rhs : [(F, Symbol)], out : @escaping F, ruleIndex : Int) {
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
        
        func nextF(dot : Int) -> F {
            if dot >= rhs.count { return out } else { return rhs[dot].0 }
        }
        
        func initialItem(k : Int, param : Value) -> Item? {
            let env = initialEnv()
            if let value = nextF(dot: 0)(env, [param]) {
                return Item(ruleIndex: ruleIndex, env: env, values: [param, value], results: [], indices: [k])
            } else {
                return nil
            }
        }
        
        func nextItem(item : Item, k : Int, value : Value, result : Result?) -> Item? {
            var values = item.values
            values.append(value)
            var results = item.results
            results.append(result)
            let env = item.env.copy()
            if let value = nextF(dot: item.dot+1)(env, values) {
                values.append(value)
                var indices = item.indices
                indices.append(k)
                return Item(ruleIndex: item.ruleIndex, env: env, values: values, results: results, indices: indices)
            } else {
                return nil
            }
        }
    }
        
    typealias RuleIndex = Int
    
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

    public let rules : [Rule]
    
    public let selector : Selector
    
    private let rulesOfSymbols : [Symbol : [RuleIndex]]
    
    public let constructResult : C
    
    func rulesOf(symbol : Symbol) -> [RuleIndex] {
        return rulesOfSymbols[symbol] ?? []
    }
    
    public init(rules : [Rule], selector : @escaping Selector, constructResult : C) {
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
    
}

public final class EarleyParser<C : ConstructResult> {
    
    public typealias Value = C.Value
    typealias Env = C.Env
    public typealias Kernel = EarleyKernel<C>
    typealias Bin = EarleyBin<Env, Value, C.Result>
    typealias Bins = [Bin]
    public typealias Symbol = Kernel.Symbol
    public typealias TerminalSet = Set<Kernel.TerminalIndex>
    typealias Tokens = Kernel.Tokens
    typealias Item = Kernel.Item
    public typealias I = C.I
    typealias TerminalKey = Kernel.TerminalKey
    
    enum RecognitionResult {
        case failed(position : I.Position)
        case success(bins : [Bin], results : Set<Value>)
    }
    
    public enum ParseResult {
        case failed(position : I.Position)
        case success(length : Int, results : [Value : C.Result?])
    }
    
    let kernel : Kernel
    let initialSymbol : Symbol
    let initialParam : Value
    let input : I
    let treatedAsNonterminals : TerminalSet
    let startPosition : I.Position
    
    public init(kernel : Kernel, initialSymbol : Symbol, initialParam : Value, input : I, startPosition : I.Position, treatedAsNonterminals : TerminalSet) {
        self.kernel = kernel
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
        for ruleIndex in kernel.rulesOf(symbol: initialSymbol) {
            let rule = kernel.rules[ruleIndex]
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
            let rule = kernel.rules[item.ruleIndex]
            if
                let nextSymbol = rule.nextSymbol(dot: item.dot),
                treatAsNonterminal(nextSymbol)
            {
                let param = item.nextParam
                for ruleIndex in kernel.rulesOf(symbol: nextSymbol) {
                    let rule = kernel.rules[ruleIndex]
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
            let rule = kernel.rules[item.ruleIndex]
            guard rule.nextSymbol(dot: item.dot) == nil else { continue }
            let nextSymbol = rule.lhs
            let param = item.param
            let result = item.out
            for srcItem in bins[item.origin - startPosition] {
                let srcItemRule = kernel.rules[srcItem.ruleIndex]
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
            let rule = kernel.rules[item.ruleIndex]
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
            let parser = EarleyParser(kernel: kernel,
                                      initialSymbol: .terminal(index: candidate.terminalIndex),
                                      initialParam: candidate.value,
                                      input: input,
                                      startPosition: k,
                                      treatedAsNonterminals: treatedAsNonterminals)
            switch parser.parse() {
            case .failed: break
            case let .success(length: length, results: results):
                for (value, result) in results {
                    let tr = Kernel.TokenResult(length: length, value: value, result: result)
                    insertTo(dict: &newTokens, key: candidate, value: tr)
                }
            }
        }
        guard !newTokens.isEmpty else { return }
        insertTo(dict: &newTokens, tokens)
        let selectedTokens = kernel.selector(newTokens)
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
            let rule = kernel.rules[item.ruleIndex]
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
                let rule = kernel.rules[item.ruleIndex]
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
                let rule = kernel.rules[item.ruleIndex]
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
                let c = EarleyParseTree<C>(input: input, kernel: kernel, treatedAsNonterminals: treatedAsNonterminals, bins: Array(bins[0 ... i]), startOffset: startPosition)
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
