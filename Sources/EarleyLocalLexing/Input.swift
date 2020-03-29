import Foundation

public protocol Input {
    
    associatedtype Char
    
    subscript(position : Int) -> Char? { get }
                
}
