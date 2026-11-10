import SwiftUI

struct SettingsView: View {
    @AppStorage("resolveNames") private var resolveNames = true
    @AppStorage("ownerLookup") private var ownerLookup = false
    @AppStorage("pingInternet") private var pingInternet = true
    @AppStorage("showMenuBar") private var showMenuBar = true

    var body: some View {
        Form {
            Section("Affichage") {
                Toggle("Afficher le débit dans la barre des menus", isOn: $showMenuBar)
            }
            Section {
                Toggle("Retrouver les noms de domaine des adresses", isOn: $resolveNames)
                Text("Pour chaque adresse contactée, Vigie demande son nom à votre serveur DNS habituel (celui de votre box ou de votre opérateur). Cela affiche « www.exemple.fr » plutôt qu'une suite de chiffres, mais ce serveur voit ces demandes.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Noms de domaine") }
            Section {
                Toggle("Identifier les propriétaires des adresses", isOn: $ownerLookup)
                Text("Interroge l'annuaire public rdap.org pour dire à qui appartient une adresse (ex. un hébergeur, un opérateur). ⚠️ Les adresses Internet contactées par votre Mac sont alors envoyées à ce service. Désactivé par défaut.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Propriétaires (facultatif)") }
            Section {
                Toggle("Mesurer la latence vers Internet", isOn: $pingInternet)
                Text("Envoie un « ping » (un très petit message) vers 1.1.1.1 toutes les quelques secondes. La latence vers votre box est toujours mesurée.")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("Latence") }
        }
        .formStyle(.grouped)
        .frame(width: 520, height: 470)
        .preferredColorScheme(.light)
    }
}
