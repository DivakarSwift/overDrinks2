//
//  FilterOptionsTVC.swift
//  QuickChat
//
//  Created by Tony Jiang on 9/11/18.
//  Copyright © 2018 Mexonis. All rights reserved.
//

import UIKit

protocol FilterOptionsTVCDelegate: class {
    func filterChanged(newFilters: [Bool])
}

class FilterOptionsTVC: UITableViewController, UITextFieldDelegate {
    let filterChoices: [String] = ["Men", "Women", "Non-binary"]
    
    var filters: [Bool] = []
    
    var delegate: FilterOptionsTVCDelegate?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
        self.navigationController!.navigationBar.shadowImage = UIImage()
        self.navigationController!.navigationBar.isTranslucent = false
        self.navigationController!.navigationBar.backgroundColor = .white
        
        tableView.tableFooterView = UIView(frame: .zero)
        
        filters = defaults.array(forKey: "filters") as! [Bool]
    }
    
    func addAccessoryView(_ textField: UITextField) {
        let toolBar = UIToolbar(frame: CGRect(x: 0, y: 0, width: self.view.frame.size.width, height: 44))
        let doneButton = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(self.doneButtonTapped))
        
        let flexibleSpace = UIBarButtonItem(barButtonSystemItem: .flexibleSpace, target: nil, action: nil)
        
        toolBar.items = [flexibleSpace, doneButton]
        toolBar.tintColor = self.view.tintColor
        
        textField.inputAccessoryView = toolBar
    }
    
    @objc func doneButtonTapped(_ sender: UIBarButtonItem) {
        view.endEditing(true)
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.preferredContentSize = CGSize(width: tableView.frame.width, height: tableView.getHeight() + 44)
    }
    
    
    @IBAction func donePressed(_ sender: UIBarButtonItem) {
        //self.delegate?.filterChanged(newFilters: self.filters)
        self.dismiss(animated: true, completion: nil)
    }
    

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "I am looking for:"
    }
    
    override func tableView(_ tableView: UITableView, willDisplayHeaderView view: UIView, forSection section: Int) {
        let header = view as! UITableViewHeaderFooterView
        header.textLabel?.font = UIFont(name: "AvenirNext-Bold", size: 16)!
        header.textLabel?.textColor = .black
        header.backgroundColor = .lightGray
    }
    
    override func tableView(_ tableView: UITableView, heightForHeaderInSection section: Int) -> CGFloat {
        return 44
    }
    
    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return filterChoices.count + 1
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if indexPath.row <= 2 {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell1", for: indexPath)
            cell.separatorInset = .zero
            
            cell.textLabel?.text = filterChoices[indexPath.row]
            cell.textLabel?.font = UIFont(name: "AvenirNext-Regular", size: 16)!
            
            cell.accessoryType = filters[indexPath.row] ? .checkmark : .none
            
            return cell
        }
        else {
            let cell = tableView.dequeueReusableCell(withIdentifier: "cell2", for: indexPath) as! AgeFilterCell
            cell.separatorInset = .zero
            cell.selectionStyle = .none
            
            cell.minAgeTF.text = defaults.string(forKey: "minAge")
            cell.minAgeTF.tag = 1
            cell.minAgeTF.delegate = self
            
            cell.maxAgeTF.text = defaults.string(forKey: "maxAge")
            cell.maxAgeTF.tag = 2
            cell.maxAgeTF.delegate = self
            
            return cell
        }
    }
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        filters[indexPath.row] = !filters[indexPath.row]
        defaults.set(filters, forKey: "filters")
        delegate?.filterChanged(newFilters: filters)
        tableView.reloadData()
    }
    
    // MARK: textfield delegates
    func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
        addAccessoryView(textField)
        return true
    }
    
    func textFieldDidEndEditing(_ textField: UITextField) {
        switch abs(textField.tag) {
        case 1: // min Age
            guard let text = textField.text, let int = Int(text) else {
                return
            }
            
            if int < defaults.integer(forKey: "maxAge") && int >= 21 {
                defaults.set(int, forKey: "minAge")
            }
        case 2: // max age
            guard let text = textField.text, let int = Int(text) else {
                return
            }
            
            if int > defaults.integer(forKey: "minAge") && int < 120 {
                defaults.set(int, forKey: "maxAge")
            }
        default: ()
        }
        self.delegate?.filterChanged(newFilters: filters)
        tableView.reloadData()
    }
}
