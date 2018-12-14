//
//  LegendVC.swift
//  QuickChat
//
//  Created by Tony Jiang on 9/12/18.
//  Copyright © 2018 Mexonis. All rights reserved.
//

import UIKit

class LegendVC: UIViewController, UITableViewDataSource, UITableViewDelegate {
    @IBOutlet weak var tableView: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        self.navigationController?.navigationBar.setBackgroundImage(UIImage(), for: .default)
        self.navigationController!.navigationBar.shadowImage = UIImage()
        self.navigationController!.navigationBar.isTranslucent = false
        self.navigationController!.navigationBar.backgroundColor = .white
        
        setupTableView()
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.preferredContentSize = CGSize(width: tableView.frame.width, height: tableView.getHeight())
    }
    
    @IBAction func donePressed(_ sender: UIBarButtonItem) {
        self.dismiss(animated: true, completion: nil)
    }
    
    func setupTableView() {
        tableView.delegate = self
        tableView.dataSource = self
        tableView.backgroundColor = .clear
        tableView.estimatedRowHeight = 100
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.tableFooterView = UIView()
        tableView.separatorStyle = .none
    }
    
    // MARK: Tableview setup
    func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 4
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        
        let cell = tableView.dequeueReusableCell(withIdentifier: "cell1", for: indexPath) as! LikeLegendCell
        cell.selectionStyle = .none
        
        switch indexPath.row {
        case 0:
            cell.picView.image = UIImage(named: "flagIcon")!
            cell.descrip.text = "blah"
        case 1:
            cell.picView.image = UIImage(named: "flagIcon")!
            cell.descrip.text = "blah"
        case 2:
            cell.picView.image = UIImage(named: "flagIcon")!
            cell.descrip.text = "blah"
        case 3:
            cell.picView.image = UIImage(named: "flagIcon")!
            cell.descrip.text = "blah"
        default: ()
        }
        
        return cell
    }
}
