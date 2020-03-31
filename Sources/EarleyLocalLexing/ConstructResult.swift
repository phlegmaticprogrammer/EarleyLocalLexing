import Foundation

public protocol CompletedItem {
    
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
            
    func evalRule<Item : CompletedItem, I : Input>(input : I, key : ItemKey<Param>, item : Item, rhs : @escaping (Int) -> Result?) -> Result? where Item.Result == Result, Item.Param == Param, I.Char == Char
            
    func merge(key : ItemKey<Param>, results : [Result]) -> Result?
    
}
