import SwiftUI

extension View {
    /// Attaches the Jishu review sheet to this view.
    ///
    /// Place on your root view. Assign `presenter` to ``Jishu/reviewUIHandler``
    /// before calling ``Jishu/trackLaunch(in:)`` so the SDK uses this presenter.
    ///
    /// ```swift
    /// @State private var reviewPresenter = JishuReviewPresenter()
    ///
    /// ContentView()
    ///     .jishuReviewSheet(presenter: reviewPresenter)
    ///     .task {
    ///         Jishu.reviewUIHandler = reviewPresenter
    ///         await Jishu.trackLaunch(in: scene)
    ///     }
    /// ```
    public func jishuReviewSheet(presenter: JishuReviewPresenter) -> some View {
        sheet(isPresented: Bindable(presenter).isPresented, onDismiss: {
            presenter.dismissReview()
        }) {
            JishuReviewView(presenter: presenter)
        }
    }
}
