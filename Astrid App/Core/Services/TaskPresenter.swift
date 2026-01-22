import SwiftUI
import Combine

/// Manages presenting task detail views programmatically from anywhere in the app
@MainActor
class TaskPresenter: ObservableObject {
    static let shared = TaskPresenter()

    @Published var taskToShow: Task?
    @Published var isShowingTask = false

    private let taskService = TaskService.shared

    private init() {
        print("🎯 [TaskPresenter] Initializing...")
    }

    /// Show task detail view for a task ID
    func showTask(taskId: String) {
        print("🔄 [TaskPresenter] Fetching task \(taskId)...")
        _Concurrency.Task {
            do {
                let task = try await taskService.fetchTask(id: taskId)
                print("✅ [TaskPresenter] Task fetched: \(task.title)")
                await MainActor.run {
                    self.taskToShow = task
                    self.isShowingTask = true
                    print("🎉 [TaskPresenter] isShowingTask set to true - navigation should occur!")
                }
            } catch {
                print("❌ [TaskPresenter] Failed to fetch task for navigation: \(error)")
            }
        }
    }

    /// Show task detail view with an existing task object
    func showTask(_ task: Task) {
        print("🎯 [TaskPresenter] Showing task: \(task.title)")
        self.taskToShow = task
        self.isShowingTask = true
        print("🎉 [TaskPresenter] isShowingTask set to true - navigation should occur!")
    }

    /// Dismiss the task detail view
    func dismiss() {
        isShowingTask = false
        taskToShow = nil
    }
}

/// View modifier to add task presentation capability to any view
struct TaskPresentationModifier: ViewModifier {
    @StateObject private var presenter = TaskPresenter.shared

    func body(content: Content) -> some View {
        content
            .navigationDestination(isPresented: $presenter.isShowingTask) {
                if let task = presenter.taskToShow {
                    TaskDetailViewNew(task: task)
                }
            }
    }
}

extension View {
    /// Enable task presentation for this view
    func withTaskPresentation() -> some View {
        modifier(TaskPresentationModifier())
    }
}
