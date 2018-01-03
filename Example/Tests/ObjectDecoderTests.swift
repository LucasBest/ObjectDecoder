import UIKit
import XCTest

import ObjectDecoder
@testable import ObjectDecoder_Example

class ObjectDecoderTests: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Put setup code here. This method is called before the invocation of each test method in the class.
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testUserDictionary() {
        let userDictionary:[String : Any] = ["id" : 1,
                                             "firstName" : "Lucas",
                                             "lastName" : "Best"]
        
        let decoder = ObjectDecoder()
        let user = try? decoder.decode(User.self, from: userDictionary)
        
        XCTAssert(user?.id == 1)
        XCTAssert(user?.firstName == "Lucas")
        XCTAssert(user?.lastName == "Best")
    }    
    
}
