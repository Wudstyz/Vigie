import SwiftUI

struct SettingsView: View {
    @AppStorage("resolveNames") private var resolveNames = true
    @AppStorage("ownerLookup") private var ownerLookup = false
    @AppStorage("pingInternet") private var pingInternet = true
    @AppStorage("showMenuBar") private var showMenuBar = true
    @AppStorage("vigilance") private var vigilance = true
    @AppStorage("notify") private var notify = true
    @AppStorage("sensitivity") private var sensitivity = Sensitivity.normal.rawValue
    @State private var confirmReset = false

    var body: some View {
        Form {
            Section {
                Toggle("Mode vigilance", isOn: $vigilance)
                Picker("Sensibilité", selection: $sensitivity) { ForEach(Sensitivity.allCases) { Text($0.label).tag($0.rawValue) } }
                    .disabled(!vigilance)
                Toggle("Notification macOS pour les alertes à vérifier", isOn: $notify).disabled(!vigilance)
                    .onChange(of: notify) { _, on in if on { AlertNotifier.requestAuthorization() } }
                Text("Vigie signale ce qui sort de l'ordinaire : envois massifs de données, nouvelles applications, nouveaux appareils, ports ouverts, pannes. Les notifications ne partent que de ce Mac. La sensibilité règle le seuil d'envoi (Faible : 100 Mo/min, Normale : 30, Élevée : 10).")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Oublier ce que Vigie a appris…") { confirmReset = true }
                    .confirmationDialog("Recommencer l'apprentissage ?", isPresented: $confirmReset) {
                        Button("Oublier et recommencer", role: .destructive) { NetworkStore.shared.resetLearning() }
                    } message: { Text("Vigie oubliera les applications, appareils et ports qu'elle connaît, ainsi que vos « faire confiance ». Pendant 15 minutes, aucune nouveauté ne sera signalée.") }
            } header: { Text("Vigilance") }
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
        .frame(width: 540, height: 640)
        .preferredColorScheme(.light)
    }
}
