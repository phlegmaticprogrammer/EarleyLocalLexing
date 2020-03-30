import Foundation

final class RunResultConstruction<C : ConstructResult, In : Input> where In.Char == C.Param {
    
    typealias Param = C.Param
    typealias Result = C.Result
    typealias Bin = EarleyBin<Param, Result>
    typealias Bins = [Bin]
    typealias Item = EarleyItem<C.Param, C.Result>
    typealias Key = ItemKey<Param>
    typealias G = Grammar<C>
    
    let grammar : G
    let bins : Bins
    let input : In
        
    enum CachedResult {
        case computing
        case done(result : Result?)
    }
    
    private var cache : [Key : CachedResult]
    private let treatedAsNonterminals : Set<G.TerminalIndex>
    private let startOffset : Int
    
    init(input : In, grammar : G, treatedAsNonterminals : Set<G.TerminalIndex>, bins : Bins, startOffset : Int) {
        self.grammar = grammar
        self.bins = bins
        self.cache = [:]
        self.treatedAsNonterminals = treatedAsNonterminals
        self.startOffset = startOffset
        self.input = input
    }
    
    func construct(symbol : Symbol, param : Param) -> [Param : Result?] {
        let startPosition = startOffset
        let endPosition = startOffset + bins.count - 1
        let items = findItems(symbol: symbol, input: param, output: nil, startPosition: startOffset, endPosition: endPosition)
        var keyedResults : [Key : [Result]] = [:]
        for item in items {
            let key = Key(symbol: symbol, inputParam: param, outputParam: item.out, startPosition: startPosition, endPosition: endPosition)
            if let result = computeResult(key: key) {
                appendTo(dict: &keyedResults, key: key, value: result)
            } else {
                if keyedResults[key] == nil {
                    keyedResults[key] = []
                }
            }
        }
        var results : [Param : Result?] = [:]
        for (key, rs) in keyedResults {
            let result = grammar.constructResult.merge(key: key, results: rs)
            results[key.outputParam] = result
        }
        return results
    }
    
    enum Task {
        case startKeyTask(key : Key)
        case startKeyItemTask(key : Key, item : Item)
        case completeKeyTask(key : Key, count : Int)
        case completeKeyItemTask(key : Key, item : Item, count : Int)
        case push(result : Result?)
    }
    
    typealias ResultStack = [Result?]
    typealias CommandStack = [Task]
    
    private func computeResult(key initialKey : Key) -> Result? {
        var commandStack : CommandStack = [.startKeyTask(key : initialKey)]
        var resultStack : ResultStack = []
        while let command = commandStack.popLast() {
            switch command {
            case let .startKeyTask(key: key):
                startTask(key: key, commandStack: &commandStack, resultStack: &resultStack)
            case let .startKeyItemTask(key: key, item: item):
                startTask(key: key, item: item, commandStack: &commandStack)
            case let .completeKeyItemTask(key: key, item: item, count: count):
                completeTask(key: key, item: item, count: count, commandStack: &commandStack, resultStack: &resultStack)
            case let .completeKeyTask(key: key, count: count):
                completeTask(key: key, count: count, commandStack: &commandStack, resultStack: &resultStack)
            case let .push(result: result):
                resultStack.append(result)
            }
        }
        precondition(resultStack.count == 1)
        return resultStack[0]
    }
    
    private func startTask(key: Key, commandStack: inout CommandStack, resultStack: inout ResultStack) {
        if let cached = cache[key] {
            switch cached {
            case let .done(result: result):
                resultStack.append(result)
            case .computing:
                resultStack.append(nil)
            }
            return
        }
        cache[key] = .computing
        let items = findItems(symbol: key.symbol, input: key.inputParam, output: key.outputParam, startPosition: key.startPosition, endPosition: key.endPosition)
        let count = items.count
        commandStack.append(.completeKeyTask(key: key, count: count))
        for item in items {
            commandStack.append(.startKeyItemTask(key: key, item: item))
        }
    }
        
    private func startTask(key: Key, item: Item, commandStack: inout CommandStack) {
        let rule = grammar.rules[item.ruleIndex]
        let count = rule.rhs.count
        commandStack.append(.completeKeyItemTask(key: key, item: item, count: count))
        for i in 0 ..< count {
            let child = item.child(rhs: i)
            let symbol = rule.rhs[i].1
            switch symbol {
            case .nonterminal:
                let childKey : Key = Key(symbol: symbol, inputParam: child.inputParam, outputParam: child.outputParam, startPosition: child.from, endPosition: child.to)
                commandStack.append(.startKeyTask(key: childKey))
            case let .terminal(index: index):
                let childKey : Key = Key(symbol: symbol, inputParam: child.inputParam, outputParam: child.outputParam, startPosition: child.from, endPosition: child.to)
                if treatedAsNonterminals.contains(index) {
                    commandStack.append(.startKeyTask(key: childKey))
                } else {
                    commandStack.append(.push(result: grammar.constructResult.evalTerminal(key: childKey, result: child.result)))
                }
            case .character:
                commandStack.append(.push(result: grammar.constructResult.evalCharacter(position: child.from, character: child.outputParam)))
            }
        }
    }
    
    private func completeTask(key: Key, item: Item, count: Int, commandStack: inout CommandStack, resultStack: inout ResultStack) {
        var results : [Result?] = []
        for _ in 0 ..< count {
            let r = resultStack.popLast()!
            results.append(r)
        }
        func subtrees(i : Int) -> Result? {
            return results[i]
        }
        let result = grammar.constructResult.evalRule(input: input, key: key, item : item, rhs: subtrees)
        resultStack.append(result)
    }
    
    private func completeTask(key: Key, count: Int, commandStack: inout CommandStack, resultStack: inout ResultStack) {
        var results : [Result] = []
        for _ in 0 ..< count {
            if let r = resultStack.popLast()! {
                results.append(r)
            }
        }
        let result = grammar.constructResult.merge(key : key, results: results)
        resultStack.append(result)
        cache[key] = .done(result: result)
    }
    
    private func findItems(symbol : Symbol, input : Param, output : Param?, startPosition : Int, endPosition : Int) -> [Item] {
        let bin = bins[endPosition - startOffset]
        var items : [Item] = []
        for item in bin {
            guard item.origin == startPosition else { continue }
            let rule = grammar.rules[item.ruleIndex]
            if rule.lhs == symbol {
                if rule.nextSymbol(dot: item.dot) == nil && item.param == input && (output == nil || item.out == output!) {
                    items.append(item)
                }
            }
        }
        return items
    }
        
}
