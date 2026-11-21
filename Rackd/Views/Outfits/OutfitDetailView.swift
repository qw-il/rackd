import SwiftData
import SwiftUI

struct OutfitDetailView: View {
    @Bindable var outfit: Outfit

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var showEditor = false
    @State private var showScheduler = false
    @State private var showDeleteConfirmation = false
    @State private var scheduleDate = Date()

    private var sortedPlans: [OutfitPlan] {
        outfit.plans.sorted { $0.date > $1.date }
    }

    var body: some View {
        List {
            Section {
                OutfitPreview(outfit: outfit)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .listRowInsets(EdgeInsets())
                    .background(Color(.secondarySystemBackground))
            }

            Section("Name") {
                TextField("Outfit name", text: $outfit.name)
            }

            Section("Items") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(outfit.resolvedPlacements.map(\.item)) { item in
                            NavigationLink(value: item) {
                                ItemTile(item: item)
                                    .frame(width: 80)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }

            Section {
                Button {
                    scheduleDate = Date()
                    showScheduler = true
                } label: {
                    Label("Plan on Calendar", systemImage: "calendar.badge.plus")
                }

                ForEach(sortedPlans) { plan in
                    let isPast = plan.date <= Calendar.current.startOfDay(for: Date())
                    Label {
                        Text(plan.date.formatted(date: .complete, time: .omitted))
                    } icon: {
                        Image(systemName: isPast ? "checkmark.circle.fill" : "clock")
                            .foregroundStyle(isPast ? Color.green : Color.orange)
                    }
                }
                .onDelete { offsets in
                    let plans = sortedPlans
                    for index in offsets {
                        modelContext.delete(plans[index])
                    }
                }
            } header: {
                Text("Calendar")
            } footer: {
                if !outfit.plans.isEmpty {
                    Text("Worn \(sortedPlans.filter { $0.date <= Calendar.current.startOfDay(for: Date()) }.count) time(s). Swipe to remove a date.")
                }
            }

            Section {
                Button(role: .destructive) {
                    showDeleteConfirmation = true
                } label: {
                    Label("Delete Outfit", systemImage: "trash")
                }
            }
        }
        .navigationTitle(outfit.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Edit") { showEditor = true }
            }
        }
        .sheet(isPresented: $showEditor) {
            OutfitBuilderView(outfit: outfit)
        }
        .sheet(isPresented: $showScheduler) {
            NavigationStack {
                VStack {
                    DatePicker("Date", selection: $scheduleDate, displayedComponents: .date)
                        .datePickerStyle(.graphical)
                        .padding()
                    Spacer()
                }
                .navigationTitle("Plan Outfit")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { showScheduler = false }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Add") {
                            modelContext.insert(OutfitPlan(date: scheduleDate, outfit: outfit))
                            showScheduler = false
                        }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .confirmationDialog("Delete this outfit?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                let context = modelContext
                let doomed = outfit
                dismiss()
                Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    context.delete(doomed)
                }
            }
        } message: {
            Text("Your clothes stay in your wardrobe. Calendar entries for this outfit will be removed.")
        }
    }
}
