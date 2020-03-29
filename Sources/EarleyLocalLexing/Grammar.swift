//
//  File.swift
//  
//
//  Created by Steven Obua on 29/03/2020.
//

import Foundation

public protocol EvalEnv {
    
    func copy() -> Self

}

public final class Grammar<C : ConstructResult> {
    
    public typealias Value = C.Value
    public typealias Result = C.Result
    public typealias EvalFunc = (EvalEnv, [Value]) -> Value?
    
    typealias Item = EarleyItem<Value, Result>
    
    public struct Rule {
        public let initialEnv : EvalEnv
        public let lhs : Symbol
        public let rhs : [(EvalFunc, Symbol)]
        public let out : EvalFunc
        public let ruleIndex : Int
        
        public init(initialEnv : EvalEnv, lhs : Symbol, rhs : [(EvalFunc, Symbol)], out : @escaping EvalFunc, ruleIndex : Int) {
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
        
        func nextF(dot : Int) -> EvalFunc {
            if dot >= rhs.count { return out } else { return rhs[dot].0 }
        }
        
        func initialItem(k : Int, param : Value) -> Item? {
            let env = initialEnv.copy()
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
