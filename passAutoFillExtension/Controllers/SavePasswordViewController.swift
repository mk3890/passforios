//
//  SavePasswordViewController.swift
//  passAutoFillExtension
//
//  Created by Matt Kelly on 31/10/2026.
//  Copyright © 2026 Bob Sun. All rights reserved.
//

import passKit
import UIKit

/// Lets users confirm the name of a password AutoFill offers to save, and tells them if it replaces an existing one.
class SavePasswordViewController: UITableViewController {
    private enum Row {
        case name, username, password
    }

    private let entry: NewPasswordEntry
    private let save: (_ name: String, _ username: String) -> Void
    private let cancel: () -> Void

    private let rows: [[Row]] = [[.name], [.username, .password]]
    private lazy var nameTextField = makeTextField(text: entry.suggestedName, placeholder: "Name".localize())
    private lazy var usernameTextField = makeTextField(text: entry.username, placeholder: "Username".localize())

    init(entry: NewPasswordEntry, save: @escaping (_ name: String, _ username: String) -> Void, cancel: @escaping () -> Void) {
        self.entry = entry
        self.save = save
        self.cancel = cancel
        super.init(style: .insetGrouped)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "SavePassword".localize()
        navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(cancelAction))
        navigationItem.rightBarButtonItem = UIBarButtonItem(barButtonSystemItem: .save, target: self, action: #selector(saveAction))
        nameTextField.addTarget(self, action: #selector(nameDidChange), for: .editingChanged)
        nameDidChange()
    }

    override func numberOfSections(in _: UITableView) -> Int {
        rows.count
    }

    override func tableView(_: UITableView, numberOfRowsInSection section: Int) -> Int {
        rows[section].count
    }

    override func tableView(_: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .value1, reuseIdentifier: nil)
        cell.selectionStyle = .none
        switch rows[indexPath.section][indexPath.row] {
        case .name:
            embed(nameTextField, in: cell)
        case .username:
            embed(usernameTextField, in: cell)
        case .password:
            cell.textLabel?.text = "Password".localize()
            cell.detailTextLabel?.text = String(repeating: "•", count: 8)
        }
        return cell
    }

    override func tableView(_: UITableView, titleForFooterInSection section: Int) -> String? {
        section == 0 ? footerText : nil
    }

    private var footerText: String {
        guard let path = NewPasswordEntry.path(forName: nameTextField.text ?? "") else {
            return "PasswordNameInvalid.".localize()
        }
        if PasswordStore.shared.fetchPasswordEntity(with: path) != nil {
            return "SavePasswordReplacesExisting.".localize()
        }
        return "SavePasswordCreatesNew.".localize()
    }

    @objc
    private func nameDidChange() {
        navigationItem.rightBarButtonItem?.isEnabled = NewPasswordEntry.path(forName: nameTextField.text ?? "") != nil
        // Update the footer without reloading the section, which would end editing the name.
        if let footer = tableView.footerView(forSection: 0) {
            footer.textLabel?.text = footerText
            footer.setNeedsLayout()
            tableView.performBatchUpdates(nil)
        }
    }

    @objc
    private func saveAction() {
        view.endEditing(true)
        save(nameTextField.text ?? "", usernameTextField.text ?? "")
    }

    @objc
    private func cancelAction() {
        cancel()
    }

    private func makeTextField(text: String, placeholder: String) -> UITextField {
        let textField = UITextField()
        textField.text = text
        textField.placeholder = placeholder
        textField.autocapitalizationType = .none
        textField.autocorrectionType = .no
        textField.clearButtonMode = .whileEditing
        textField.translatesAutoresizingMaskIntoConstraints = false
        return textField
    }

    private func embed(_ textField: UITextField, in cell: UITableViewCell) {
        cell.contentView.addSubview(textField)
        NSLayoutConstraint.activate([
            textField.leadingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.leadingAnchor),
            textField.trailingAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.trailingAnchor),
            textField.topAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.topAnchor),
            textField.bottomAnchor.constraint(equalTo: cell.contentView.layoutMarginsGuide.bottomAnchor),
            textField.heightAnchor.constraint(greaterThanOrEqualToConstant: 32),
        ])
    }
}
