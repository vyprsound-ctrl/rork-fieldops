import SwiftUI

/// Invite somebody into the company.
///
/// The role is chosen here and stamped onto the invitation inside the database.
/// The person joining cannot change it — they redeem a code, and the code
/// decides what they are.
struct TeamInviteSheet: View {
    let terms: Terminology
    let onInvite: (TeamInviteDraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draft = TeamInviteDraft()

    private var invitableRoles: [Role] { [.fieldWorker, .dispatcher, .accounts, .admin] }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Email address", text: $draft.email)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.emailAddress)
                } header: {
                    Text("Who")
                } footer: {
                    Text("They'll use this address to create their sign-in.")
                }

                Section {
                    Picker("Role", selection: $draft.role) {
                        ForEach(invitableRoles) { role in
                            Text(role.title(terms)).tag(role)
                        }
                    }
                    Text(draft.role.summary(terms))
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                } header: {
                    Text("What they can do")
                }

                Section {
                    Picker("Code expires", selection: $draft.expiresInDays) {
                        Text("2 days").tag(2)
                        Text("7 days").tag(7)
                        Text("14 days").tag(14)
                        Text("30 days").tag(30)
                    }
                } footer: {
                    Text("You'll get a join code to pass on. It stops working when it expires, or when you revoke it.")
                }
            }
            .navigationTitle("Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send invite") {
                        onInvite(draft)
                        dismiss()
                    }
                    .disabled(draft.validationMessage != nil)
                }
            }
        }
    }
}

/// Shows the join code once, right after it is issued.
struct TeamInviteCodeSheet: View {
    let invite: TeamInvite

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(invite.roleTitle) invited")
                            .font(.title3.weight(.bold))
                            .foregroundStyle(Theme.ink)
                        Text("\(invite.email) · \(invite.expiresLabel)")
                            .font(.subheadline)
                            .foregroundStyle(Theme.secondary)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Join code").sectionLabelStyle()
                        Text(invite.token)
                            .font(.system(.body, design: .monospaced).weight(.semibold))
                            .foregroundStyle(Theme.ink)
                            .textSelection(.enabled)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardSurface()

                        HStack(spacing: 10) {
                            Button {
                                UIPasteboard.general.string = invite.token
                            } label: {
                                Label("Copy code", systemImage: "doc.on.doc")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.primary)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Theme.primaryTint)
                                    .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                            }
                            .buttonStyle(PressableTileStyle())

                            ShareLink(item: shareText) {
                                Label("Share", systemImage: "square.and.arrow.up")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.primary)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .background(Theme.primaryTint)
                                    .clipShape(.rect(cornerRadius: Theme.buttonRadius))
                            }
                        }
                    }

                    Text("This is the only time the code is shown. Send it to \(invite.email), and they enter it under “Join a company” on the sign-in screen. If it goes astray, revoke the invitation and send a new one.")
                        .font(.footnote)
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(Theme.margin)
            }
            .background(Theme.canvas)
            .navigationTitle("Invitation sent")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var shareText: String {
        """
        You've been invited to join on Harbour South FieldOps as \(invite.roleTitle).

        Join code: \(invite.token)

        Open the app, choose “Join a company” on the sign-in screen, and enter this code with your email address. \(invite.expiresLabel).
        """
    }
}

/// Edit one team member: their details, their role and whether they can work.
struct TeamMemberSheet: View {
    let member: TeamMember
    let terms: Terminology
    let onSave: (String, String, Role, UserStatus) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var phone: String
    @State private var role: Role
    @State private var isActive: Bool

    private var assignableRoles: [Role] { [.fieldWorker, .dispatcher, .accounts, .admin] }

    init(member: TeamMember, terms: Terminology, onSave: @escaping (String, String, Role, UserStatus) -> Void) {
        self.member = member
        self.terms = terms
        self.onSave = onSave
        _name = State(initialValue: member.name)
        _phone = State(initialValue: member.phone ?? "")
        _role = State(initialValue: member.role)
        _isActive = State(initialValue: member.status == .active)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Details") {
                    TextField("Name", text: $name)
                        .textContentType(.name)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    if let email = member.email {
                        LabeledContent("Email", value: email)
                    }
                }

                if member.role != .owner {
                    Section {
                        Picker("Role", selection: $role) {
                            ForEach(assignableRoles) { option in
                                Text(option.title(terms)).tag(option)
                            }
                        }
                        Text(role.summary(terms))
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                    } header: {
                        Text("What they can do")
                    }

                    Section {
                        Toggle("Can sign in and take work", isOn: $isActive)
                            .tint(Theme.primary)
                    } footer: {
                        Text(isActive
                            ? "Turning this off signs them out at their next attempt and stops new work being assigned. Their job history stays."
                            : "They're suspended. Turn this back on to let them work again.")
                    }
                } else {
                    Section {
                        Text("The owner's role and access can't be changed from here.")
                            .font(.footnote)
                            .foregroundStyle(Theme.secondary)
                    }
                }

                if let lastActive = member.lastActiveLabel {
                    Section {
                        Text(lastActive)
                            .font(.footnote)
                            .foregroundStyle(Theme.meta)
                    }
                }
            }
            .navigationTitle(member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(name, phone, role, isActive ? .active : .suspended)
                        dismiss()
                    }
                    .disabled(name.tidied.isEmpty)
                }
            }
        }
    }
}

#Preview {
    TeamInviteSheet(terms: .generic) { _ in }
}
