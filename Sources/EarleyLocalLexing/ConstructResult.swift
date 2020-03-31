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
            
    func evalRule<Item : CompletedItem, In : Input>(input : In, key : ItemKey<Param>, item : Item, rhs : @escaping (Int) -> Result?) -> Result? where Item.Result == Result, Item.Param == Param, In.Char == Param
    
    func evalTerminal(key : ItemKey<Param>, result : Result?) -> Result?
    
    func evalCharacter(position : Int, character : Param) -> Result?
    
    func merge(key : ItemKey<Param>, results : [Result]) -> Result?
    
}
