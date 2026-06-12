import SwiftUI
import FocusGuardShared

struct ScheduleTab: View {
    @ObservedObject var daemon: DaemonClient
    @State private var editing = false
    @State private var days: Set<Int> = [1, 2, 3, 4, 5]
    @State private var start = Calendar.current.date(from: DateComponents(hour: 9, minute: 0))!
    @State private var end = Calendar.current.date(from: DateComponents(hour: 17, minute: 0))!

    private let dayLabels = [(1, "M"), (2, "T"), (3, "W"), (4, "T"), (5, "F"), (6, "S"), (7, "S")]

    var body: some View {
        VStack(spacing: FG.Spacing.s) {
            if daemon.outsideScheduledHours {
                Label(L10n.Schedule.outsideHours, systemImage: "moon.zzz")
                    .font(.caption2).foregroundColor(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            }

            if editing {
                editor
            } else {
                if daemon.schedules.isEmpty {
                    empty
                } else {
                    list
                }
                Button { withAnimation(FG.Motion.quick) { editing = true } } label: {
                    Label(L10n.Schedule.add, systemImage: "plus").font(.caption)
                }
                .buttonStyle(.borderedProminent).tint(FG.Palette.emerald).controlSize(.small)
            }

            Text(L10n.Schedule.note).font(.caption2).foregroundColor(Color(white: 0.4))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: FG.Spacing.s) {
                ForEach(daemon.schedules) { schedule in
                    HStack {
                        Image(systemName: "calendar").foregroundColor(FG.Palette.emerald)
                        Text(schedule.summary).font(.caption)
                        Spacer()
                        Button { daemon.removeSchedule(schedule.id) } label: {
                            Image(systemName: "xmark.circle.fill").foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(daemon.status != .unlocked)
                        .accessibilityLabel("Remove schedule")
                    }
                    .padding(FG.Spacing.s)
                    .background(FG.Palette.bgCard, in: RoundedRectangle(cornerRadius: FG.Radius.m))
                }
            }
            .frame(maxHeight: 180)
        }
    }

    private var editor: some View {
        VStack(spacing: FG.Spacing.m) {
            HStack(spacing: 6) {
                ForEach(dayLabels, id: \.0) { (num, label) in
                    let on = days.contains(num)
                    Button {
                        if on { days.remove(num) } else { days.insert(num) }
                    } label: {
                        Text(label).font(.caption).fontWeight(.semibold)
                            .frame(width: 28, height: 28)
                            .background(on ? FG.Palette.emerald : FG.Palette.bgCard, in: Circle())
                            .foregroundColor(on ? .black : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                DatePicker("From", selection: $start, displayedComponents: .hourAndMinute).labelsHidden()
                Text("to").font(.caption).foregroundColor(.secondary)
                DatePicker("To", selection: $end, displayedComponents: .hourAndMinute).labelsHidden()
            }
            HStack {
                Button("Cancel") { withAnimation(FG.Motion.quick) { editing = false } }
                    .buttonStyle(.plain).font(.caption)
                Spacer()
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent).tint(FG.Palette.emerald).controlSize(.small)
                    .disabled(days.isEmpty)
            }
        }
        .padding(FG.Spacing.s)
        .background(FG.Palette.bgInset, in: RoundedRectangle(cornerRadius: FG.Radius.l))
    }

    private var empty: some View {
        VStack(spacing: FG.Spacing.s) {
            Image(systemName: "calendar.badge.clock").font(.title2).foregroundColor(Color(white: 0.3))
            Text(L10n.Schedule.empty).font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, FG.Spacing.l)
    }

    private func save() {
        let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
        let schedule = Schedule(id: UUID().uuidString, days: days, start: fmt.string(from: start), end: fmt.string(from: end))
        daemon.addSchedule(schedule)
        withAnimation(FG.Motion.quick) { editing = false }
    }
}
