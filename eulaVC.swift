//
//  eulaVC.swift
//  QuickChat
//
//  Created by Tony Jiang on 12/14/18.
//  Copyright © 2018 Mexonis. All rights reserved.
//

import UIKit

class eulaVC: UIViewController {

    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var agreementOutlet: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        agreementOutlet.titleLabel?.numberOfLines = 0
        textView.text = "EULA Agreement"
    }
    
    

}
