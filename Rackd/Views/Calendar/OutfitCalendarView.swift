import SwiftData
import SwiftUI

struct OutfitCalendarView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \OutfitPlan.date) private var plans: [OutfitPlan]

    @State private var displayedMonth = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var showPicker = false

    private let calendar = Calendar.current

    private var plansByDay: [Date: [OutfitPlan]] {
        Dictionary(grouping: plans.filter { $0.outfit != nil }) { calendar.startOfDay(for: $0.date) }
    }

    private var selectedPlans: [OutfitPlan] {
        plansByDay[selectedDate] ?? []
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MonthGrid(
                        month: $displayedMonth,
                        selectedDate: $selectedDate,
                        plansByDay: plansByDay
                    )
                    .padding(.horizontal)

                    Divider()

                    dayDetail
                        .padding(.horizontal)
                }
                .padding(.vertical)
            }
            .navigationTitle("Outfit Calendar")
            .navigationBarTitleDisplayMode(.inline)
            .navigationDestination(for: Outfit.self) { outfit in
                OutfitDetailView(outfit: outfit)
            }
            .navigationDestination(for: ClothingItem.self) { item in
                ItemDetailView(item: item)
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Today") {
                        withAnimation {
                            selectedDate = calendar.startOfDay(for: Date())
                            displayedMonth = calendar.startOfMonth(for: Date())
                        }
                    }
                }
            }
            .sheet(isPresented: $showPicker) {
                OutfitPickerSheet(date: selectedDate) { outfit in
                    modelContext.insert(OutfitPlan(date: selectedDate, outfit: outfit))
                    showPicker = false
                }
            }
        }
    }

    private var dayDetail: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(selectedDate.formatted(.dateTime.weekday(.wide)))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(selectedDate.formatted(.dateTime.month(.wide).day()))
                        .font(.title2.weight(.bold))
                }
                Spacer()
                Button {
                    showPicker = true
                } label: {
                    Label("Add Outfit", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
            }

            if selectedPlans.isEmpty {
                Text(selectedDate < calendar.startOfDay(for: Date())
                     ? "Nothing logged for this day."
                     : "Nothing planned yet. Add an outfit to plan what you'll wear.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
            } else {
                ForEach(selectedPlans) { plan in
                    if let outfit = plan.outfit {
                        PlannedOutfitRow(outfit: outfit) {
                            withAnimation { modelContext.delete(plan) }
                        }
                    }
                }
            }
        }
    }
}

private struct PlannedOutfitRow: View {
    let outfit: Outfit
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            NavigationLink(value: outfit) {
                HStack(spacing: 14) {
                    OutfitPreview(outfit: outfit)
                        .frame(width: 96)
                        .padding(6)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(outfit.displayName)
                            .font(.headline)
                        Text(outfit.items.map { $0.name.isEmpty ? $0.category.singularName : $0.name }
                            .joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(.plain)

            Menu {
                Button(role: .destructive, action: onRemove) {
                    Label("Remove from Day", systemImage: "calendar.badge.minus")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Month grid

private struct MonthGrid: View {
    @Binding var month: Date
    @Binding var selectedDate: Date
    let plansByDay: [Date: [OutfitPlan]]

    private let calendar = Calendar.current
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    /// Day cells for the month, with `nil` padding before the 1st.
    private var days: [Date?] {
        guard let range = calendar.range(of: .day, in: .month, for: month) else { return [] }
        let weekdayOfFirst = calendar.component(.weekday, from: month)
        let leading = (weekdayOfFirst - calendar.firstWeekday + 7) % 7
        let dates = range.compactMap { day -> Date? in
            calendar.date(byAdding: .day, value: day - 1, to: month)
        }
        return Array(repeating: nil, count: leading) + dates.map { Optional($0) }
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Text(month.formatted(.dateTime.month(.wide).year()))
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    shiftMonth(by: -1)
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel("Previous month")
                Button {
                    shiftMonth(by: 1)
                } label: {
                    Image(systemName: "chevron.right")
                }
                .accessibilityLabel("Next month")
                .padding(.leading, 16)
            }
            .font(.body.weight(.semibold))

            HStack(spacing: 4) {
                ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                }
            }

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                    if let date {
                        DayCell(
                            date: date,
                            outfit: plansByDay[date]?.first?.outfit,
                            extraCount: max((plansByDay[date]?.count ?? 0) - 1, 0),
                            isSelected: calendar.isDate(date, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(date)
                        )
                        .onTapGesture { selectedDate = date }
                    } else {
                        Color.clear.frame(height: 64)
                    }
                }
            }
        }
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    if value.translation.width < -50 { shiftMonth(by: 1) }
                    if value.translation.width > 50 { shiftMonth(by: -1) }
                }
        )
    }

    private func shiftMonth(by value: Int) {
        guard let newMonth = calendar.date(byAdding: .month, value: value, to: month) else { return }
        withAnimation(.easeInOut(duration: 0.2)) { month = newMonth }
    }
}

private struct DayCell: View {
    let date: Date
    let outfit: Outfit?
    let extraCount: Int
    let isSelected: Bool
    let isToday: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(date.formatted(.dateTime.day()))
                .font(.caption.weight(isToday ? .bold : .regular))
                .foregroundStyle(isToday ? Color.accentColor : Color.primary)

            ZStack(alignment: .topTrailing) {
                if let outfit {
                    OutfitPreview(outfit: outfit)
                        .frame(height: 42)
                } else {
                    Color.clear.frame(height: 42)
                }
                if extraCount > 0 {
                    Text("+\(extraCount)")
                        .font(.system(size: 9, weight: .bold))
                        .padding(.horizontal, 3)
                        .background(Color.accentColor, in: Capsule())
                        .foregroundStyle(.white)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 64)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentColor.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isSelected ? Color.accentColor : Color.clear, lineWidth: 1.5)
        )
        .contentShape(Rectangle())
    }
}

// MARK: - Outfit picker

private struct OutfitPickerSheet: View {
    let date: Date
    let onPick: (Outfit) -> Void

    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Outfit.createdAt, order: .reverse) private var outfits: [Outfit]
    @Query private var items: [ClothingItem]
    @State private var showBuilder = false

    private let columns = [GridItem(.adaptive(minimum: 140), spacing: 14)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Button {
                        showBuilder = true
                    } label: {
                        Label("Create a New Outfit", systemImage: "plus.square.dashed")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                    }
                    .buttonStyle(.bordered)
                    .disabled(items.isEmpty)

                    if outfits.isEmpty {
                        Text(items.isEmpty
                             ? "Add clothes to your wardrobe first, then build outfits to plan."
                             : "You haven't saved any outfits yet.")
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 24)
                    } else {
                        LazyVGrid(columns: columns, spacing: 16) {
                            ForEach(outfits) { outfit in
                                Button {
                                    onPick(outfit)
                                } label: {
                                    OutfitCard(outfit: outfit)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $showBuilder) {
                OutfitBuilderView(onSave: onPick)
            }
        }
    }
}

extension Calendar {
    func startOfMonth(for date: Date) -> Date {
        self.date(from: dateComponents([.year, .month], from: date)) ?? startOfDay(for: date)
    }
}
