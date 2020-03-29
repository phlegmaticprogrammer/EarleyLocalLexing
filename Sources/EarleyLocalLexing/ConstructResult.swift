import Foundation

public protocol CompletedItem {
    
    associatedtype Value
    
    associatedtype Result

    var ruleIndex : Int { get }
        
    func child(rhs : Int) -> (in: Value, out: Value, result: Result?, from: Int, to: Int)
}

public struct ItemKey<Value : Hashable> : Hashable {
    
    public let symbol : Symbol
    
    public let input : Value
    
    public let output : Value
    
    public let startPosition : Int
    
    public let endPosition : Int

}

public protocol ConstructResult {
    
    associatedtype Result
    
    associatedtype Value : Hashable
        
    func evalRule<Item : CompletedItem, In : Input>(input : In, key : ItemKey<Value>, item : Item, rhs : @escaping (Int) -> Result?) -> Result? where Item.Result == Result, Item.Value == Value, In.Char == Value
    
    func evalTerminal(key : ItemKey<Value>, result : Result?) -> Result?
    
    func evalCharacter(position : Int, character : Value) -> Result?
    
    func merge(key : ItemKey<Value>, results : [Result]) -> Result?
    
}
