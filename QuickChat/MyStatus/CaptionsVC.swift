//
//  CaptionsVC.swift
//  QuickChat
//
//  Created by Tony Jiang on 12/14/18.
//  Copyright © 2018 Mexonis. All rights reserved.
//

import UIKit

class CaptionsVC: UIViewController, UITextViewDelegate {

    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var charLabel: UILabel!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        textView.delegate = self
    }


    @IBAction func donePressed(_ sender: UIBarButtonItem) {
        dismiss(animated: true, completion: nil)
    }

}
