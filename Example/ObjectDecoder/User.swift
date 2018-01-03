//
//  User.swift
//  ObjectDecoder_Example
//
//  Created by Lucas Best on 1/3/18.
//  Copyright © 2018 CocoaPods. All rights reserved.
//

import Foundation
import ObjectDecoder

class User : Decodable{
    var id:Int?
    
    var firstName:String?
    var lastName:String?
    
    static func test() -> Self?{
        let userDictionary:[String : Any] = ["id" : 1,
                                             "firstName" : "Lucas",
                                             "lastName" : "Best"]
        
        let decoder = ObjectDecoder()
        return try? decoder.decode(self, from: userDictionary)
    }
}
