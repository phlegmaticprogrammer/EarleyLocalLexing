//
//  File.swift
//  
//
//  Created by Steven Obua on 28/03/2020.
//

import Foundation

public protocol Input {
    
    associatedtype Char
    
    typealias Position = Int
        
    subscript(position : Position) -> Char? { get }
                
}
