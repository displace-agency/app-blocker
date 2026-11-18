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
                Text(L10n.Schedule.outsideHours).fgCaption().frame(maxWidth: .infinity, alignment: .leading)
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
                    Text(L10n.Schedule.add)
                }
                .buttonStyle(.fgSecondary)
            }

            Text(L10n.Schedule.note).fgCaption()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: FG.Spacing.xs) {
            Text("Weekly · \(daemon.schedules.count)").fgEyebrow()
                .frame(maxWidth: .infinity, alignment: .leading)
            LazyVStack(spacing: 0) {
                ForEach(daemon.schedules) { schedule in
                    HStack {
                        Text(schedule.summary).font(FG.bodyFont).foregroundColor(FG.ink)
                        Spacer()
                        Button { daemon.removeSchedule(schedule.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 10, weight: .medium)).foregroundColor(FG.inkSecondary)
                        }
                        .buttonStyle(.plain)
                        .disabled(daemon.status != .unlocked)
                        .opacity(daemon.status == .unlocked ? 1 : 0.4)
                        .accessibilityLabel("Remove schedule")
                    }
                    .frame(minHeight: 36)
                    if schedule.id != daemon.schedules.last?.id { Divider().overlay(FG.hairline) }
                }
            }
            .padding(.horizontal, FG.Spacing.m)
            .fgCard()
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
                        Text(label).font(.system(size: 12, weight: .medium))
                            .frame(width: 30, height: 28)
                            .background(on ? FG.ink : FG.surface, in: RoundedRectangle(cornerRadius: FG.Radius.control))
                            .overlay(RoundedRectangle(cornerRadius: FG.Radius.control).stroke(on ? FG.ink : FG.border, lineWidth: 1))
                            .foregroundColor(on ? .white : FG.ink)
                    }
                    .buttonStyle(.plain)
                }
            }
            HStack {
                DatePicker("From", selection: $start, displayedComponents: .hourAndMinute).labelsHidden()
                Text("to").fgCaption()
                DatePicker("To", selection: $end, displayedComponents: .hourAndMinute).labelsHidden()
            }
            HStack(spacing: FG.Spacing.s) {
                Button("Cancel") { withAnimation(FG.Motion.quick) { editing = false } }
                    .buttonStyle(.fgSecondary)
                Button("Save") { save() }
                    .buttonStyle(.fgPrimary)
                    .disabled(days.isEmpty)
            }
        }
        .padding(FG.Spacing.m)
        .frame(maxWidth: .infinity)
        .fgCard()
    }

    private var empty: some View {
        Text(L10n.Schedule.empty).fgCaption().multilineTextAlignment(.center)
            .frame(maxWidth: .infinity).padding(.vertical, FG.Spacing.l)
            .fgCard()
    }

    private func save() {
        let fmt = DateFormatter(); fmt.dateFormat = "HH:mm"
        let schedule = Schedule(id: UUID().uuidString, days: days, start: fmt.string(from: start), end: fmt.string(from: end))
        daemon.addSchedule(schedule)
        withAnimation(FG.Motion.quick) { editing = false }
    }
}
