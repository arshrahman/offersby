//
//  Offer.swift
//  NIPeekaboo
//
//  Created by Abdul Rahman on 23/7/20.
//  Copyright © 2020 Apple. All rights reserved.
//

import Foundation

@objc(Offer)
class Offer: NSObject, NSCoding {
    
    let text: String
    let imageName: String
    
    
    init(text: String = "", imageName: String = "") {
//        super.init()
        self.text = text
        self.imageName = imageName
    }
    
    func encode(with coder: NSCoder) {
        coder.encode(self.text, forKey: "text")
        coder.encode(self.imageName, forKey: "imageName")
    }
    
    required convenience init?(coder: NSCoder) {
//        guard let text = coder.decodeObject(forKey: "text") as? String else { return nil }
        self.init(text: coder.decodeObject(forKey: "text") as! String, imageName: coder.decodeObject(forKey: "imageName") as! String)
//        self.init()
//        self.text = coder.decodeObject(forKey: "text") as! String
//        self.imageName = coder.decodeObject(forKey: "imageName") as! String
//
    }
    
}
