import Foundation

public protocol CompletedRightHandSide {
    
    associatedtype Param
    
    associatedtype Result

    var ruleIndex : Int { get }
        
    func child(rhs : Int) -> (inputParam: Param, outputParam: Param, result: Result?, from: Int, to: Int)
}

public struct ItemKey<Param : Hashable> : Hashable {
    
    public let symbol : Symbol
    
    public let inputParam : Param
    
    public let outputParam : Param
    
    public let startPosition : Int
    
    public let endPosition : Int

}

public protocol ConstructResult : GrammarComponent {
    
    associatedtype Char
            
    func evalRule<RHS : CompletedRightHandSide, I : Input>(input : I, key : ItemKey<Param>, rhs : RHS) -> Result? where RHS.Result == Result, RHS.Param == Param, I.Char == Char
            
    func merge(key : ItemKey<Param>, results : [Result]) -> Result?
    
}
