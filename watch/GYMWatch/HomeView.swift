import SwiftUI

// YOU on the watch: every app's number for today, its streak, and how many you've logged.
struct HomeView: View {
    @Environment(Store.self) private var store
    @AppStorage(Store.reminderOnKey) private var reminderOn = true
    @AppStorage(Store.reminderHourKey) private var reminderHour = 20

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(alignment: .firstTextBaseline, spacing: 5) {
                            Text("\(store.loggedTodayCount)")
                                .font(.system(size: 40, weight: .semibold, design: .rounded))
                                .monospacedDigit()
                            Text("of \(store.connectedCount) logged today")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        Text(Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .listRowBackground(Color.clear)
                    .accessibilityElement(children: .combine)
                }

                if !store.pending.isEmpty || !store.pendingCardio.isEmpty || !store.outbox.isEmpty {
                    Label("Logs waiting to sync", systemImage: "icloud.slash")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
                if let error = store.error {
                    Text(error).font(.footnote).foregroundStyle(.red)
                }

                // Tap an app to log to it; one that isn't set up just shows why.
                ForEach(store.hubTiles) { tile in
                    if tile.status == .notSetUp {
                        TileRow(tile: tile)
                    } else {
                        NavigationLink { quickLog(for: tile.kind) } label: { TileRow(tile: tile) }
                    }
                }

                Section {
                    Toggle("Evening reminder", isOn: $reminderOn)
                    if reminderOn {
                        Picker("Time", selection: $reminderHour) {
                            ForEach(17...23, id: \.self) { h in
                                Text(Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: .now)?.formatted(date: .omitted, time: .shortened) ?? "\(h):00").tag(h)
                            }
                        }
                    }
                } header: {
                    Text("Streak saver")
                } footer: {
                    Text(store.remindersBlocked
                         ? "Notifications are off for YOU. Turn them on in the Watch app on your iPhone: Notifications → YOU."
                         : "Only if something isn't logged yet, with the streak that ends at midnight.")
                }
                .onChange(of: reminderOn) { _, _ in Task { await store.scheduleReminders() } }
                .onChange(of: reminderHour) { _, _ in Task { await store.scheduleReminders() } }

                Section {
                    Button("Refresh") { Task { await store.refreshAll() } }
                    Button(store.pending.isEmpty && store.pendingCardio.isEmpty && store.outbox.isEmpty ? "Sign out" : "Sign out (unsynced logs will be lost)", role: .destructive) {
                        Task { await store.signOut() }
                    }
                } footer: {
                    if let email = store.email { Text(email) }
                }
            }
            .navigationTitle("YOU")
            .refreshable { await store.refreshAll() }
            .overlay { if !store.hubLoaded && store.loading { ProgressView() } }
        }
    }
}

// One app: its name and colour, today's number, a check once you've logged today, and its streak.
// The streak shows faded when you haven't logged yet today, like YOU's.
struct TileRow: View {
    let tile: AppTile

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: tile.kind.symbol)
                    .foregroundStyle(tile.kind.color)
                    .frame(width: 16)
                    .accessibilityHidden(true)
                Text(tile.kind.title)
                    .font(.system(.footnote, design: .rounded, weight: .bold))
                Spacer(minLength: 4)
                if tile.status == .ok && tile.streak.days > 0 {
                    Text("🔥 \(tile.streak.label)")
                        .font(.footnote.weight(.semibold))
                        .monospacedDigit()
                        .opacity(tile.streak.kept ? 1 : 0.5)
                        .accessibilityLabel(tile.streak.kept ? "\(tile.streak.label) days in a row" : "\(tile.streak.label) day streak, log today to keep it")
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(tile.value)
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !tile.unit.isEmpty {
                    Text(tile.unit).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if tile.loggedToday {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(tile.kind.color)
                        .accessibilityLabel("Logged today")
                }
            }
            Text(tile.note)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(.vertical, 2)
        .opacity(tile.status == .ok ? 1 : 0.6)
        .accessibilityElement(children: .combine)
    }
}
