import Observation
import SwiftUI

struct AppModalPresentationID: Hashable, Sendable {
    let rawValue: String

    init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    static let sourceConnection = Self("source-connection")
    static let openSourceLicenses = Self("open-source-licenses")
}

@MainActor
@Observable
final class AppModalPresentationCoordinator {
    private struct PresentedModal {
        let id: AppModalPresentationID
        let dismiss: @MainActor () -> Void
    }

    @ObservationIgnored private var presentedModal: PresentedModal?
    @ObservationIgnored private var dismissalWaiters: [
        AppModalPresentationID: [CheckedContinuation<Void, Never>]
    ] = [:]

    func modalDidPresent(
        _ id: AppModalPresentationID,
        dismiss: @escaping @MainActor () -> Void
    ) {
        if let presentedModal, presentedModal.id != id {
            assertionFailure(
                "A modal was presented without dismissing \(presentedModal.id.rawValue) first."
            )
            return
        }
        presentedModal = PresentedModal(id: id, dismiss: dismiss)
    }

    func modalDidDismiss(_ id: AppModalPresentationID) {
        if presentedModal?.id == id {
            presentedModal = nil
        }
        let waiters = dismissalWaiters.removeValue(forKey: id) ?? []
        for waiter in waiters {
            waiter.resume()
        }
    }

    func dismissPresentedModalBeforePresentingNext() async {
        guard let presentedModal else { return }
        let id = presentedModal.id
        await withCheckedContinuation { continuation in
            dismissalWaiters[id, default: []].append(continuation)
            presentedModal.dismiss()
        }
    }
}

extension View {
    func sequencedSheet<Item: Identifiable, SheetContent: View>(
        item presentedItem: Binding<Item?>,
        coordinator: AppModalPresentationCoordinator,
        id: AppModalPresentationID,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping (Item) -> SheetContent
    ) -> some View {
        sheet(
            item: presentedItem,
            onDismiss: {
                coordinator.modalDidDismiss(id)
                onDismiss()
            },
            content: { item in
                content(item)
                    .onAppear {
                        coordinator.modalDidPresent(id) {
                            presentedItem.wrappedValue = nil
                        }
                    }
            }
        )
    }

    func sequencedSheet<SheetContent: View>(
        isPresented: Binding<Bool>,
        coordinator: AppModalPresentationCoordinator,
        id: AppModalPresentationID,
        onDismiss: @escaping () -> Void = {},
        @ViewBuilder content: @escaping () -> SheetContent
    ) -> some View {
        sheet(
            isPresented: isPresented,
            onDismiss: {
                coordinator.modalDidDismiss(id)
                onDismiss()
            },
            content: {
                content()
                    .onAppear {
                        coordinator.modalDidPresent(id) {
                            isPresented.wrappedValue = false
                        }
                    }
            }
        )
    }
}
